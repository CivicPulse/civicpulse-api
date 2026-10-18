-- LOCAL correction of the accepted null|{code,occurred_at} staff wire.
-- Historical errors require unique durable attribution; never invent a time.
alter table civicpulse_delivery.build_counter add column last_error_occurred_at timestamptz;
do $$
declare code text; times timestamptz[];
begin
  select last_error into code from civicpulse_delivery.build_counter for update;
  if code is not null then
    select array_agg(occurred_at) into times from (
      select a.acknowledged_at occurred_at
      from civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id)
      where a.state='failed' and j.state='failed' and a.sequence=j.transition_sequence
        and a.evidence=jsonb_build_object('error_code',code)
        and code in ('export_failed','build_failed','validation_failed')
      union all
      select a.acknowledged_at from civicpulse_delivery.deployment_acknowledgments a
        join civicpulse_delivery.build_jobs j using(job_id)
      where j.state='failed' and a.result->>'state'='failed'
        and a.operation in ('failed','reconcile') and code='deployment_failed'
    ) failures;
    if coalesce(cardinality(times),0)<>1 then
      raise exception 'Existing error lacks unique durable failure attribution' using errcode='55000';
    end if;
    update civicpulse_delivery.build_counter set last_error_occurred_at=times[1];
  end if;
end $$;
alter table civicpulse_delivery.build_counter add constraint bound_last_error check(
  (last_error is null and last_error_occurred_at is null) or
  (last_error is not null and last_error_occurred_at is not null and last_error in
    ('export_failed','build_failed','validation_failed','deployment_failed','deployment_unknown','reconciliation_failed')));

create or replace function civicpulse_delivery.transition_build(p_job_id uuid,p_lease_id uuid,p_fence bigint,p_expected_state text,p_state text,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; ack civicpulse_delivery.build_transitions; code text; normal boolean; failure_time timestamptz;
begin
  perform civicpulse_delivery.require_machine('runner');
  if p_job_id is null or p_lease_id is null or p_fence is null or p_fence<=0
    or p_expected_state is null or p_expected_state not in ('queued','exporting','building','validating','ready')
    or p_state is null then raise exception 'Invalid transition identity' using errcode='22023'; end if;
  normal:= (p_expected_state,p_state) in (('queued','exporting'),('exporting','building'),('building','validating'),('validating','ready'));
  if p_state='failed' then
    perform civicpulse_delivery.exact_object(p_evidence,array['error_code']);
    code:=case p_expected_state when 'queued' then 'export_failed' when 'exporting' then 'export_failed' when 'building' then 'build_failed' else 'validation_failed' end;
    if p_evidence->'error_code' is distinct from to_jsonb(code) then raise exception 'Wrong failure stage' using errcode='22023'; end if;
  elsif p_state='superseded' then
    perform civicpulse_delivery.exact_object(p_evidence,array['reason']);
    perform civicpulse_delivery.text_field(p_evidence,'reason','^(content_changed|source_changed|epoch_changed)$');
  elsif normal then
    if p_state='building' then
      perform civicpulse_delivery.exact_object(p_evidence,array['publication_manifest','snapshot_sha256']);
      perform civicpulse_delivery.text_field(p_evidence,'snapshot_sha256','^[0-9a-f]{64}$');
    elsif p_state='validating' then
      perform civicpulse_delivery.exact_object(p_evidence,array['artifact_sha256']);
      perform civicpulse_delivery.text_field(p_evidence,'artifact_sha256','^[0-9a-f]{64}$');
    else perform civicpulse_delivery.exact_object(p_evidence,'{}'); end if;
  else raise exception 'Illegal transition' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
  if j.job_id is null or j.actor<>session_user or j.actor_oid<>(select oid from pg_roles where rolname=session_user)
    or j.lease_id<>p_lease_id or j.fence<>p_fence then raise exception 'Transition owner changed' using errcode='40001'; end if;
  select * into ack from civicpulse_delivery.build_transitions where job_id=j.job_id and sequence=j.transition_sequence;
  if ack.job_id is not null and ack.expected_state=p_expected_state and ack.state=p_state and ack.evidence=p_evidence then
    if j.state in ('failed','superseded') or clock_timestamp()<j.lease_expires_at then
      return jsonb_build_object('state',ack.state);
    end if;
  end if;
  if j.state<>p_expected_state or clock_timestamp()>=j.lease_expires_at
    or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state) then
    raise exception 'Transition state or lease changed' using errcode='40001'; end if;
  if p_state='superseded' then
    if p_evidence->>'reason'='source_changed' then
      raise exception 'Authenticated source-change gate unavailable' using errcode='55000';
    elsif p_evidence->>'reason'='content_changed' then
      if not exists(select 1 from civicpulse_delivery.publication_state s
        where s.dataset_epoch=j.dataset_epoch and s.generation>j.target_generation) then
        raise exception 'Content has not changed' using errcode='40001'; end if;
    elsif p_evidence->>'reason'='epoch_changed' then
      if not exists(select 1 from civicpulse_delivery.publication_state s where s.dataset_epoch<>j.dataset_epoch) then
        raise exception 'Epoch has not changed' using errcode='40001'; end if;
    end if;
  end if;
  if normal then
    if not exists(select 1 from civicpulse_delivery.publication_state s cross join civicpulse_delivery.enrollment_state e
      where s.dataset_epoch=j.dataset_epoch and s.generation=j.target_generation and e.config_version=j.config_version)
      then raise exception 'Desired tuple changed' using errcode='40001'; end if;
    if p_state='building' then
      perform civicpulse_delivery.validate_receipt_manifest(p_evidence->'publication_manifest',j.dataset_epoch,j.target_generation);
      if p_evidence->'publication_manifest' is distinct from public.publication_manifest() then raise exception 'Manifest changed' using errcode='40001'; end if;
      update civicpulse_delivery.build_jobs set publication_manifest=p_evidence->'publication_manifest',snapshot_sha256=p_evidence->>'snapshot_sha256' where job_id=j.job_id;
    elsif p_state='validating' then
      if j.publication_manifest is null or j.snapshot_sha256 is null then raise exception 'Snapshot missing' using errcode='55000'; end if;
      update civicpulse_delivery.build_jobs set artifact_sha256=p_evidence->>'artifact_sha256' where job_id=j.job_id;
    elsif p_state='ready' then
      if j.publication_manifest is null or j.snapshot_sha256 is null or j.artifact_sha256 is null then raise exception 'Build evidence missing' using errcode='55000'; end if;
    end if;
  end if;
  insert into civicpulse_delivery.build_transitions(job_id,sequence,expected_state,state,evidence)
    values(j.job_id,j.transition_sequence+1,p_expected_state,p_state,p_evidence) returning acknowledged_at into failure_time;
  update civicpulse_delivery.build_jobs set state=p_state,transition_sequence=j.transition_sequence+1 where job_id=j.job_id;
  if p_state in ('failed','superseded') then
    update civicpulse_delivery.enrollment_state set active_job_id=null;
    if p_state='failed' then
      update civicpulse_delivery.build_counter set intervention_required=true,last_error=code,last_error_occurred_at=failure_time,next_attempt_at=null;
    end if;
  end if;
  return jsonb_build_object('state',p_state);
end $$;

create or replace function civicpulse_delivery.finish_deploy(p_attempt_id uuid,p_fence bigint,p_deployment_id text,p_outcome text,p_observation jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare cap text; i civicpulse_delivery.deployment_intents; j civicpulse_delivery.build_jobs; o civicpulse_delivery.observations;
  p civicpulse_delivery.pipeline_state; args jsonb; result jsonb; failure_time timestamptz;
begin
  cap:=case when p_outcome='unknown' then 'runner' else 'reconciler' end;
  perform civicpulse_delivery.require_machine(cap);
  if p_attempt_id is null or p_fence is null or p_fence<=0 or p_outcome is null or p_outcome not in ('unknown','live','failed')
    or (p_deployment_id is not null and p_deployment_id collate "C" !~ '^[A-Za-z0-9_-]{1,128}$') then raise exception 'Invalid finish target' using errcode='22023'; end if;
  if p_outcome='unknown' then perform civicpulse_delivery.exact_object(p_observation,array[]::text[]);
  elsif p_deployment_id is null then raise exception 'Deployment required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment(cap);
  select * into i from civicpulse_delivery.deployment_intents where attempt_id=p_attempt_id;
  select * into j from civicpulse_delivery.build_jobs where job_id=i.job_id for update;
  if i.attempt_id is null or i.fence<>p_fence then raise exception 'Deployment attempt changed' using errcode='40001'; end if;
  args:=jsonb_build_object('attempt_id',p_attempt_id,'fence',p_fence::text,'deployment_id',p_deployment_id,'outcome',p_outcome,'observation',p_observation);
  result:=civicpulse_delivery.deployment_replay(j.job_id,p_outcome,args);
  if result is not null then return result; end if;
  if j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state)
    or not (select external_authority from civicpulse_delivery.enrollment_state)
    or j.state not in ('deploying','deployment_unknown') or j.config_version is distinct from (select config_version from civicpulse_delivery.enrollment_state)
    or j.dataset_epoch is distinct from (select dataset_epoch from civicpulse_delivery.publication_state) then raise exception 'Deployment authority changed' using errcode='40001'; end if;
  select * into p from civicpulse_delivery.pipeline_state;
  if p_outcome='unknown' then
    if j.actor is distinct from session_user or j.actor_oid is distinct from (select oid from pg_roles where rolname=session_user) then raise exception 'Not owning runner' using errcode='42501'; end if;
    update civicpulse_delivery.build_jobs set state='deployment_unknown' where job_id=j.job_id;
  else
    o:=civicpulse_delivery.provider_receipt(p_observation,j,'outcome',i.attempt_id);
    if o.evidence->'deployment'->>'id' is distinct from p_deployment_id then raise exception 'Candidate changed' using errcode='40001'; end if;
    if p_outcome='live' then
      if o.eligibility<>'success' then raise exception 'Live evidence incomplete' using errcode='55000'; end if;
      perform civicpulse_delivery.validate_receipt_manifest(i.publication_manifest,i.dataset_epoch,i.generation);
      if i.dataset_epoch is distinct from j.dataset_epoch or i.generation is distinct from j.target_generation
        or i.config_version is distinct from j.config_version or i.fence is distinct from j.fence
        or i.publication_manifest is distinct from j.publication_manifest or i.snapshot_sha256 is distinct from j.snapshot_sha256
        or i.artifact_sha256 is distinct from j.artifact_sha256 or i.source_sha is distinct from j.source_sha
        or p.approved_epoch is distinct from i.dataset_epoch or (p.live_dataset_epoch=i.dataset_epoch and p.live_generation>i.generation) then
        raise exception 'Stored deployment inventory changed' using errcode='40001'; end if;
      update civicpulse_delivery.pipeline_state set live_dataset_epoch=i.dataset_epoch,live_generation=i.generation,
        live_deployment_id=p_deployment_id,live_source_sha=i.source_sha,live_at=clock_timestamp(),
        live_inventory_complete=true,live_inventory=i.publication_manifest->'records';
      update civicpulse_delivery.enrollment_state set live_observation_id=o.observation_id;
      update civicpulse_delivery.build_jobs set state='live' where job_id=j.job_id;
      -- Retain active_job_id and external_authority until separate terminal proof.
    else
      if o.eligibility<>'failure' then raise exception 'Terminal failure evidence incomplete' using errcode='55000'; end if;
      update civicpulse_delivery.build_jobs set state='failed' where job_id=j.job_id;
      update civicpulse_delivery.enrollment_state set active_job_id=null,external_authority=false;
      failure_time:=clock_timestamp();
      update civicpulse_delivery.build_counter set intervention_required=true,last_error='deployment_failed',last_error_occurred_at=failure_time,next_attempt_at=null;
    end if;
    update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=i.attempt_id where observation_id=o.observation_id;
  end if;
  select jsonb_build_object('state',b.state,'live_generation',s.live_generation::text,'live_deployment_id',s.live_deployment_id) into result
    from civicpulse_delivery.build_jobs b cross join civicpulse_delivery.pipeline_state s where b.job_id=j.job_id;
  insert into civicpulse_delivery.deployment_acknowledgments(job_id,operation,actor,actor_oid,arguments,result,observation_id,acknowledged_at)
    values(j.job_id,p_outcome,session_user,(select oid from pg_roles where rolname=session_user),args,result,o.observation_id,coalesce(failure_time,clock_timestamp()));
  return result;
end $$;

create or replace function civicpulse_delivery.reconcile_job(p_job_id uuid,p_fence bigint,p_observation jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; i civicpulse_delivery.deployment_intents; o civicpulse_delivery.observations;
  admitted civicpulse_delivery.observations; args jsonb; result jsonb; recovery text; failure_time timestamptz;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_job_id is null or p_fence is null or p_fence<=0 then raise exception 'Invalid reconcile target' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
  if j.job_id is null or j.fence<>p_fence then raise exception 'Job fence changed' using errcode='40001'; end if;
  args:=jsonb_build_object('job_id',p_job_id,'fence',p_fence::text,'observation',p_observation);
  result:=civicpulse_delivery.deployment_replay(j.job_id,'reconcile',args);
  if result is not null then return result; end if;
  select * into i from civicpulse_delivery.deployment_intents where job_id=j.job_id;
  o:=civicpulse_delivery.provider_receipt(p_observation,j,'terminal',i.attempt_id);
  if o.eligibility='audit' then
    return jsonb_build_object('state',j.state,'reclaimable',false,'live_generation',(select live_generation::text from civicpulse_delivery.pipeline_state));
  end if;
  if i.attempt_id is null then
    if o.eligibility<>'predeploy_terminal' or j.state not in ('queued','exporting','building','validating','ready')
      or clock_timestamp()<j.lease_expires_at or (select external_authority from civicpulse_delivery.enrollment_state) then raise exception 'Expiry recovery unavailable' using errcode='55000'; end if;
    recovery:='lease_expired';
    update civicpulse_delivery.build_jobs set state='superseded' where job_id=j.job_id;
    -- Preserve spent run reservation, fence, prior live and any intervention.
  else
    if not (select external_authority from civicpulse_delivery.enrollment_state) then raise exception 'Uploader authority changed' using errcode='40001'; end if;
    if j.state='live' and o.eligibility='success' then
      select * into admitted from civicpulse_delivery.observations where observation_id=(select live_observation_id from civicpulse_delivery.enrollment_state);
      if o.evidence-'requests'-'github_terminal' is distinct from admitted.evidence-'requests'-'github_terminal'
        or (select live_deployment_id from civicpulse_delivery.pipeline_state) is distinct from o.evidence->'deployment'->>'id'
        or (select live_dataset_epoch from civicpulse_delivery.pipeline_state) is distinct from j.dataset_epoch
        or (select live_generation from civicpulse_delivery.pipeline_state) is distinct from j.target_generation then raise exception 'Admitted live evidence changed' using errcode='40001'; end if;
    elsif j.state in ('deploying','deployment_unknown') and o.eligibility='failure' then
      update civicpulse_delivery.build_jobs set state='failed' where job_id=j.job_id;
      failure_time:=clock_timestamp();
      update civicpulse_delivery.build_counter set intervention_required=true,last_error='deployment_failed',last_error_occurred_at=failure_time,next_attempt_at=null;
    else raise exception 'Terminal deployment evidence incomplete' using errcode='55000'; end if;
  end if;
  update civicpulse_delivery.enrollment_state set active_job_id=null,external_authority=false;
  update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=coalesce(i.attempt_id,j.job_id) where observation_id=o.observation_id;
  select jsonb_build_object('state',state,'reclaimable',true,'live_generation',(select live_generation::text from civicpulse_delivery.pipeline_state)) into result
    from civicpulse_delivery.build_jobs where job_id=j.job_id;
  insert into civicpulse_delivery.deployment_acknowledgments(job_id,operation,actor,actor_oid,arguments,result,observation_id,recovery_reason,acknowledged_at)
    values(j.job_id,'reconcile',session_user,(select oid from pg_roles where rolname=session_user),args,result,o.observation_id,recovery,coalesce(failure_time,clock_timestamp()));
  return result;
end $$;

create or replace function civicpulse_delivery.cms_publication_status() returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare result jsonb; j civicpulse_delivery.build_jobs; active uuid; repository text;
begin
  perform civicpulse.require_role();
  select jsonb_build_object(
    'dataset_epoch',s.dataset_epoch,'desired_generation',s.generation::text,
    'bootstrap_complete',s.bootstrap_complete,'paused',p.paused,
    'live_dataset_epoch',p.live_dataset_epoch,'live_generation',p.live_generation::text,
    'live_deployment_id',p.live_deployment_id,'live_source_sha',p.live_source_sha,'live_at',p.live_at,
    'live_inventory_complete',p.live_inventory_complete,
    'generation_lag',case when p.live_inventory_complete and p.live_dataset_epoch=s.dataset_epoch
      and p.live_generation<=s.generation then (s.generation-p.live_generation)::text else null end,
    'status_error',case when p.live_dataset_epoch=s.dataset_epoch and p.live_generation>s.generation then 'live_generation_ahead' else null end,
    'state',null,'active_job',null,'last_error',null,'next_attempt_at',null,'observed_at',statement_timestamp())
    into result from civicpulse_delivery.publication_state s cross join civicpulse_delivery.pipeline_state p
    where s.singleton and p.singleton;
  select active_job_id into active from civicpulse_delivery.enrollment_state;
  select * into j from civicpulse_delivery.build_jobs order by fence desc limit 1;
  if active is not null then select * into j from civicpulse_delivery.build_jobs where job_id=active; end if;
  if j.job_id is not null then
    select config->'source'->>'repository_full_name' into repository from civicpulse_delivery.delivery_configs where config_version=j.config_version;
    result:=result||jsonb_build_object('state',j.state,'active_job',case when active is not null then
      jsonb_build_object('job_id',j.job_id,'generation',j.target_generation::text,
        'run_url','https://github.com/'||repository||'/actions/runs/'||split_part(j.run_id,':',1)||'/attempts/'||split_part(j.run_id,':',2)) else null end);
  end if;
  result:=result||jsonb_build_object('last_error',(select case when last_error is null then null else jsonb_build_object('code',last_error,'occurred_at',last_error_occurred_at) end from civicpulse_delivery.build_counter),
    'next_attempt_at',(select next_attempt_at from civicpulse_delivery.build_counter));
  return result;
end;
$$;
