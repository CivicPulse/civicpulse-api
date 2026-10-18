-- LOCAL M2.2 preparation: claim/heartbeat only; no upload or live writer.
create table civicpulse_delivery.build_counter (
  singleton boolean primary key default true check(singleton),
  fence bigint not null default 0 check(fence>=0)
);
insert into civicpulse_delivery.build_counter(singleton) values(true);
create table civicpulse_delivery.build_jobs (
  job_id uuid primary key default gen_random_uuid(),
  run_id text not null unique, source_sha text not null,
  config_version uuid not null references civicpulse_delivery.delivery_configs,
  dataset_epoch uuid not null, target_generation bigint not null check(target_generation>=0),
  actor name not null, actor_oid oid not null,
  lease_id uuid not null unique default gen_random_uuid(),
  fence bigint not null unique check(fence>0),
  created_at timestamptz not null, lease_expires_at timestamptz not null,
  source_observation_id uuid not null unique references civicpulse_delivery.observations,
  state text not null default 'queued' check(state in ('queued','exporting','building','validating','ready','failed','superseded')),
  check(run_id collate "C" ~ '^[1-9][0-9]{0,19}:[1-9][0-9]{0,9}$'),
  check(source_sha collate "C" ~ '^[0-9a-f]{40}$')
);
create unique index one_active_build on civicpulse_delivery.build_jobs ((true)) where state in ('queued','exporting','building','validating','ready');
alter table civicpulse_delivery.enrollment_state add foreign key(active_job_id) references civicpulse_delivery.build_jobs;
alter table civicpulse_delivery.build_counter enable row level security;
alter table civicpulse_delivery.build_jobs enable row level security;
revoke all on civicpulse_delivery.build_counter,civicpulse_delivery.build_jobs from public,anon,authenticated;

create function civicpulse_delivery.build_claim_result(j civicpulse_delivery.build_jobs) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('job_id',j.job_id,'lease_id',j.lease_id,'fence',j.fence::text,
    'dataset_epoch',j.dataset_epoch,'target_generation',j.target_generation::text,'lease_expires_at',j.lease_expires_at);
$$;
create function civicpulse_delivery.claim_build(p_run_id text,p_source_sha text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; c civicpulse_delivery.observation_challenges;
  o civicpulse_delivery.observations; s civicpulse_delivery.publication_state;
  p civicpulse_delivery.pipeline_state; e civicpulse_delivery.enrollment_state;
  at timestamptz; due timestamptz; token bigint;
begin
  perform civicpulse_delivery.require_machine('runner');
  perform civicpulse_delivery.parse_run_identity(p_run_id);
  if p_source_sha is null or p_source_sha collate "C" !~ '^[0-9a-f]{40}$' then raise exception 'Invalid source' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  perform civicpulse_delivery.source_ready();
  select * into s from civicpulse_delivery.publication_state;
  select * into p from civicpulse_delivery.pipeline_state;
  select * into e from civicpulse_delivery.enrollment_state;
  if p.live_dataset_epoch is not null and (p.live_dataset_epoch<>s.dataset_epoch or p.live_generation>s.generation) then
    raise exception 'Baseline anomaly' using errcode='55000'; end if;
  select * into j from civicpulse_delivery.build_jobs where run_id=p_run_id for update;
  if found then
    if j.actor<>session_user or j.actor_oid<>(select oid from pg_roles where rolname=session_user)
      or j.source_sha<>p_source_sha or j.config_version<>e.config_version or j.dataset_epoch<>s.dataset_epoch
      or j.target_generation<>s.generation or j.job_id is distinct from e.active_job_id
      or j.state not in ('queued','exporting','building','validating','ready') or clock_timestamp()>=j.lease_expires_at then
      raise exception 'Existing claim changed or expired' using errcode='40001'; end if;
    return civicpulse_delivery.build_claim_result(j);
  end if;
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
  insert into civicpulse_delivery.build_jobs(run_id,source_sha,config_version,dataset_epoch,target_generation,actor,actor_oid,fence,created_at,lease_expires_at,source_observation_id)
    values(p_run_id,p_source_sha,e.config_version,s.dataset_epoch,s.generation,session_user,(select oid from pg_roles where rolname=session_user),token,at,at+interval '5 minutes',o.observation_id) returning * into j;
  update civicpulse_delivery.observations set consumed_at=at,consumed_for=j.job_id where observation_id=o.observation_id;
  update civicpulse_delivery.enrollment_state set active_job_id=j.job_id;
  perform civicpulse_delivery.check_challenge(c);
  return civicpulse_delivery.build_claim_result(j);
end $$;

create function civicpulse_delivery.heartbeat_build(p_job_id uuid,p_lease_id uuid,p_fence bigint) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; at timestamptz;
begin
  perform civicpulse_delivery.require_machine('runner');
  if p_job_id is null or p_lease_id is null or p_fence is null or p_fence<=0 then raise exception 'Invalid claim identity' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
  if j.job_id is null or j.actor<>session_user or j.actor_oid<>(select oid from pg_roles where rolname=session_user)
    or j.lease_id<>p_lease_id or j.fence<>p_fence or j.state not in ('queued','exporting','building','validating','ready')
    or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state)
    or clock_timestamp()>=j.lease_expires_at then raise exception 'Claim ownership expired or changed' using errcode='40001'; end if;
  at:=clock_timestamp()+interval '5 minutes';
  update civicpulse_delivery.build_jobs set lease_expires_at=at where job_id=j.job_id;
  return jsonb_build_object('lease_expires_at',at);
end $$;
revoke all on function civicpulse_delivery.build_claim_result(civicpulse_delivery.build_jobs),civicpulse_delivery.claim_build(text,text),civicpulse_delivery.heartbeat_build(uuid,uuid,bigint) from public,anon,authenticated;
