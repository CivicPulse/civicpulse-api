-- LOCAL M2.3. Reconciler attestations are trusted acquisition projections,
-- not provider authentication supplied by these SQL functions.
create table civicpulse_delivery.deployment_acknowledgments (
  job_id uuid not null references civicpulse_delivery.build_jobs,
  operation text not null check(operation in ('unknown','live','failed','reconcile')),
  actor name not null, actor_oid oid not null,
  arguments jsonb not null, result jsonb not null,
  recovery_reason text check(recovery_reason is null or recovery_reason='lease_expired'),
  observation_id uuid unique references civicpulse_delivery.observations,
  acknowledged_at timestamptz not null default clock_timestamp(),
  primary key(job_id,operation)
);
alter table civicpulse_delivery.deployment_acknowledgments enable row level security;
revoke all on civicpulse_delivery.deployment_acknowledgments from public,anon,authenticated;
create trigger immutable_deployment_ack before update or delete on civicpulse_delivery.deployment_acknowledgments
  for each row execute function civicpulse_delivery.preserve_deployment_intent();

create function civicpulse_delivery.deployment_replay(id uuid,op text,args jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare ack civicpulse_delivery.deployment_acknowledgments;
begin
  select * into ack from civicpulse_delivery.deployment_acknowledgments where job_id=id and operation=op;
  if not found then return null; end if;
  if ack.actor is distinct from session_user or ack.actor_oid is distinct from (select oid from pg_roles where rolname=session_user)
    or ack.arguments is distinct from args then raise exception 'Deployment acknowledgment changed' using errcode='40001'; end if;
  return ack.result;
end $$;

create function civicpulse_delivery.provider_receipt(doc jsonb,j civicpulse_delivery.build_jobs,purpose text,attempt uuid)
returns civicpulse_delivery.observations language plpgsql security invoker set search_path='' as $$
declare id uuid; o civicpulse_delivery.observations; c civicpulse_delivery.observation_challenges;
begin
  perform civicpulse_delivery.exact_object(doc,array['observation_id']);
  id:=civicpulse_delivery.text_field(doc,'observation_id','^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')::uuid;
  select * into o from civicpulse_delivery.observations where observation_id=id for update;
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=o.challenge_id for update;
  if o.observation_id is null or o.consumed_at is not null or c.family is distinct from 'provider' or c.purpose is distinct from purpose
    or c.job_id is distinct from j.job_id or c.attempt_id is distinct from attempt then raise exception 'Provider receipt changed' using errcode='40001'; end if;
  perform civicpulse_delivery.check_provider_context(c);
  if o.eligibility<>'audit' and o.eligibility is distinct from civicpulse_delivery.provider_classification(o.evidence,c) then raise exception 'Provider classification changed' using errcode='40001'; end if;
  return o;
end $$;

create function civicpulse_delivery.finish_deploy(p_attempt_id uuid,p_fence bigint,p_deployment_id text,p_outcome text,p_observation jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare cap text; i civicpulse_delivery.deployment_intents; j civicpulse_delivery.build_jobs; o civicpulse_delivery.observations;
  p civicpulse_delivery.pipeline_state; args jsonb; result jsonb;
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
      update civicpulse_delivery.build_counter set intervention_required=true,last_error='deployment_failed',next_attempt_at=null;
    end if;
    update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=i.attempt_id where observation_id=o.observation_id;
  end if;
  select jsonb_build_object('state',b.state,'live_generation',s.live_generation::text,'live_deployment_id',s.live_deployment_id) into result
    from civicpulse_delivery.build_jobs b cross join civicpulse_delivery.pipeline_state s where b.job_id=j.job_id;
  insert into civicpulse_delivery.deployment_acknowledgments(job_id,operation,actor,actor_oid,arguments,result,observation_id)
    values(j.job_id,p_outcome,session_user,(select oid from pg_roles where rolname=session_user),args,result,o.observation_id);
  return result;
end $$;

create function civicpulse_delivery.reconcile_job(p_job_id uuid,p_fence bigint,p_observation jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; i civicpulse_delivery.deployment_intents; o civicpulse_delivery.observations;
  admitted civicpulse_delivery.observations; args jsonb; result jsonb; recovery text;
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
      update civicpulse_delivery.build_counter set intervention_required=true,last_error='deployment_failed',next_attempt_at=null;
    else raise exception 'Terminal deployment evidence incomplete' using errcode='55000'; end if;
  end if;
  update civicpulse_delivery.enrollment_state set active_job_id=null,external_authority=false;
  update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=coalesce(i.attempt_id,j.job_id) where observation_id=o.observation_id;
  select jsonb_build_object('state',state,'reclaimable',true,'live_generation',(select live_generation::text from civicpulse_delivery.pipeline_state)) into result
    from civicpulse_delivery.build_jobs where job_id=j.job_id;
  insert into civicpulse_delivery.deployment_acknowledgments(job_id,operation,actor,actor_oid,arguments,result,observation_id,recovery_reason)
    values(j.job_id,'reconcile',session_user,(select oid from pg_roles where rolname=session_user),args,result,o.observation_id,recovery);
  return result;
end $$;
revoke all on function civicpulse_delivery.deployment_replay(uuid,text,jsonb),civicpulse_delivery.provider_receipt(jsonb,civicpulse_delivery.build_jobs,text,uuid),
  civicpulse_delivery.finish_deploy(uuid,bigint,text,text,jsonb),civicpulse_delivery.reconcile_job(uuid,bigint,jsonb) from public,anon,authenticated;
