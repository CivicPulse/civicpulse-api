-- LOCAL M2.2 exact transitions and persistent intervention; no deploy/live writer.
alter table civicpulse_delivery.build_counter add column intervention_required boolean not null default false;
alter table civicpulse_delivery.build_counter add column last_error text;
alter table civicpulse_delivery.build_counter add column next_attempt_at timestamptz;
alter table civicpulse_delivery.build_jobs add column repository_id text;
update civicpulse_delivery.build_jobs j set repository_id=c.config->'source'->>'repository_id' from civicpulse_delivery.delivery_configs c where c.config_version=j.config_version;
alter table civicpulse_delivery.build_jobs alter column repository_id set not null;
alter table civicpulse_delivery.build_jobs drop constraint build_jobs_run_id_key;
alter table civicpulse_delivery.build_jobs add unique(repository_id,run_id);
alter table civicpulse_delivery.build_jobs add column publication_manifest jsonb;
alter table civicpulse_delivery.build_jobs add column snapshot_sha256 text;
alter table civicpulse_delivery.build_jobs add column artifact_sha256 text;
alter table civicpulse_delivery.build_jobs add column transition_sequence bigint not null default 0;
create table civicpulse_delivery.build_transitions (
  job_id uuid not null references civicpulse_delivery.build_jobs,
  sequence bigint not null, expected_state text not null, state text not null,
  evidence jsonb not null, acknowledged_at timestamptz not null default clock_timestamp(),
  primary key(job_id,sequence)
);
alter table civicpulse_delivery.build_transitions enable row level security;
revoke all on civicpulse_delivery.build_transitions from public,anon,authenticated;

create or replace function civicpulse_delivery.claim_build(p_run_id text,p_source_sha text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; c civicpulse_delivery.observation_challenges;
  o civicpulse_delivery.observations; s civicpulse_delivery.publication_state;
  p civicpulse_delivery.pipeline_state; e civicpulse_delivery.enrollment_state;
  at timestamptz; due timestamptz; token bigint; repository text;
begin
  perform civicpulse_delivery.require_machine('runner');
  perform civicpulse_delivery.parse_run_identity(p_run_id);
  if p_source_sha is null or p_source_sha collate "C" !~ '^[0-9a-f]{40}$' then raise exception 'Invalid source' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  select * into s from civicpulse_delivery.publication_state;
  select * into p from civicpulse_delivery.pipeline_state;
  select * into e from civicpulse_delivery.enrollment_state;
  if p.live_dataset_epoch is not null and (p.live_dataset_epoch<>s.dataset_epoch or p.live_generation>s.generation) then
    raise exception 'Baseline anomaly' using errcode='55000'; end if;
  select config->'source'->>'repository_id' into repository from civicpulse_delivery.delivery_configs where config_version=e.config_version;
  select * into j from civicpulse_delivery.build_jobs where repository_id=repository and run_id=p_run_id for update;
  if found then
    if j.source_sha<>p_source_sha then raise exception 'Reserved source changed' using errcode='40001'; end if;
    if j.state in ('failed','superseded') then raise exception 'Run attempt spent' using errcode='55000'; end if;
    perform civicpulse_delivery.source_ready();
  if (select intervention_required from civicpulse_delivery.build_counter) then raise exception 'Intervention required' using errcode='55000'; end if;
    if j.actor<>session_user or j.actor_oid<>(select oid from pg_roles where rolname=session_user)
      or j.source_sha<>p_source_sha or j.config_version<>e.config_version or j.dataset_epoch<>s.dataset_epoch
      or j.target_generation<>s.generation or j.job_id is distinct from e.active_job_id
      or j.state not in ('queued','exporting','building','validating','ready') or clock_timestamp()>=j.lease_expires_at then
      raise exception 'Existing claim changed or expired' using errcode='40001'; end if;
    return civicpulse_delivery.build_claim_result(j);
  end if;
  perform civicpulse_delivery.source_ready();
  if (select intervention_required from civicpulse_delivery.build_counter) then raise exception 'Intervention required' using errcode='55000'; end if;
  if e.active_job_id is not null then raise exception 'Active claim exists' using errcode='40001'; end if;
  -- Select only currently eligible producer receipts; syntax is not source proof.
  select ch.* into c from civicpulse_delivery.observation_challenges ch
    join civicpulse_delivery.observations ob using(challenge_id)
    join civicpulse_delivery.machine_registry mr on mr.role_name=ch.actor and mr.role_oid=ch.actor_oid
    join pg_roles pr on pr.oid=mr.role_oid and pr.rolname=mr.role_name
    where ch.family='source' and ch.purpose='claim' and ch.job_id is null
      and ch.run_id=p_run_id and ch.source_sha=p_source_sha and ch.config_version=e.config_version
      and ch.dataset_epoch=s.dataset_epoch and ch.expires_at>clock_timestamp() and ob.consumed_at is null
      and mr.capability='reconciler' and mr.enabled and mr.expires_at>clock_timestamp()
    order by ch.issued_at desc,ch.challenge_id desc limit 1 for update of ch,ob;
  if not found then raise exception 'Fresh source receipt required' using errcode='55000'; end if;
  perform civicpulse_delivery.check_challenge(c);
  select * into o from civicpulse_delivery.observations where challenge_id=c.challenge_id;
  if p.live_inventory_complete and p.live_dataset_epoch=s.dataset_epoch and p.live_generation=s.generation and p.live_source_sha=p_source_sha then
    return 'null'::jsonb;
  end if;
  select least(max(occurred_at)+interval '30 seconds',min(occurred_at)+interval '120 seconds') into due
    from civicpulse_delivery.outbox where dataset_epoch=s.dataset_epoch and action in ('publish','withdraw')
      and generation>case when p.live_dataset_epoch=s.dataset_epoch and p.live_inventory_complete then p.live_generation else 0 end;
  if due is not null and clock_timestamp()<due then raise exception 'Content quiet window pending' using errcode='55000'; end if;
  select fence into token from civicpulse_delivery.build_counter for update;
  if token=9223372036854775807 then raise exception 'Fence exhausted' using errcode='55000'; end if;
  token:=token+1;
  update civicpulse_delivery.build_counter set fence=token;
  at:=clock_timestamp();
  insert into civicpulse_delivery.build_jobs(repository_id,run_id,source_sha,config_version,dataset_epoch,target_generation,actor,actor_oid,fence,created_at,lease_expires_at,source_observation_id)
    values(repository,p_run_id,p_source_sha,e.config_version,s.dataset_epoch,s.generation,session_user,(select oid from pg_roles where rolname=session_user),token,at,at+interval '5 minutes',o.observation_id) returning * into j;
  update civicpulse_delivery.observations set consumed_at=at,consumed_for=j.job_id where observation_id=o.observation_id;
  update civicpulse_delivery.enrollment_state set active_job_id=j.job_id;
  perform civicpulse_delivery.check_challenge(c);
  return civicpulse_delivery.build_claim_result(j);
end $$;

create function civicpulse_delivery.transition_build(p_job_id uuid,p_lease_id uuid,p_fence bigint,p_expected_state text,p_state text,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; ack civicpulse_delivery.build_transitions; code text; normal boolean;
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
    values(j.job_id,j.transition_sequence+1,p_expected_state,p_state,p_evidence);
  update civicpulse_delivery.build_jobs set state=p_state,transition_sequence=j.transition_sequence+1 where job_id=j.job_id;
  if p_state in ('failed','superseded') then
    update civicpulse_delivery.enrollment_state set active_job_id=null;
    if p_state='failed' then
      update civicpulse_delivery.build_counter set intervention_required=true,last_error=code,next_attempt_at=null;
    end if;
  end if;
  return jsonb_build_object('state',p_state);
end $$;
revoke all on function civicpulse_delivery.transition_build(uuid,uuid,bigint,text,text,jsonb) from public,anon,authenticated;


-- Existing staff status shape now reflects actual jobs; no machine data is exposed.
create or replace function civicpulse_delivery.cms_publication_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
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
  result:=result||jsonb_build_object('last_error',(select last_error from civicpulse_delivery.build_counter),
    'next_attempt_at',(select next_attempt_at from civicpulse_delivery.build_counter));
  return result;
end;
$$;
