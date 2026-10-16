-- LOCAL M2b foundation. No machine logins or deployment authority are provisioned.
create table civicpulse_delivery.machine_registry (
  role_name name primary key,
  role_oid oid not null unique,
  capability text not null check(capability in ('dispatcher','runner','reconciler','publication_operator')),
  enabled boolean not null default false,
  expires_at timestamptz not null
);
alter table civicpulse_delivery.machine_registry enable row level security;
revoke all on civicpulse_delivery.machine_registry from public,anon,authenticated;

-- No public/runner write path to verified live receipts exists in this increment.
-- Future finish/reconcile operations must validate complete inventory atomically.
create table civicpulse_delivery.pipeline_state (
  singleton boolean primary key default true check(singleton),
  paused boolean not null default true,
  approved_epoch uuid,
  live_dataset_epoch uuid,
  live_generation bigint check(live_generation>=0),
  live_deployment_id text,
  live_source_sha text check(live_source_sha collate "C" ~ '^[0-9a-f]{40}$'),
  live_at timestamptz,
  live_inventory_complete boolean not null default false,
  live_inventory jsonb,
  check(not live_inventory_complete or
    (live_dataset_epoch is not null and live_generation is not null and
     live_deployment_id is not null and live_source_sha is not null and live_at is not null and
     live_inventory is not null and jsonb_typeof(live_inventory)='array'))
);
insert into civicpulse_delivery.pipeline_state(singleton) values(true);
alter table civicpulse_delivery.pipeline_state enable row level security;
revoke all on civicpulse_delivery.pipeline_state from public,anon,authenticated;

create table civicpulse_delivery.operator_audit (
  id uuid primary key default gen_random_uuid(),
  actor name not null,
  action text not null,
  review_reference text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
alter table civicpulse_delivery.operator_audit enable row level security;
revoke all on civicpulse_delivery.operator_audit from public,anon,authenticated;

-- Called only from narrowly granted definer entrypoints, never directly granted.
-- session_user survives SET ROLE and SECURITY DEFINER. Bind name AND OID so a
-- dropped/recreated login does not inherit an obsolete registration.
create function civicpulse_delivery.require_machine(p_capability text) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if not exists(select 1 from civicpulse_delivery.machine_registry r
    join pg_catalog.pg_roles p on p.oid=r.role_oid and p.rolname=r.role_name
    where r.role_name=session_user and r.capability=p_capability and r.enabled
      and r.expires_at>clock_timestamp()) then
    raise exception 'Machine capability required' using errcode='42501';
  end if;
end;
$$;
revoke all on function civicpulse_delivery.require_machine(text) from public,anon,authenticated;

create function civicpulse_delivery.set_pipeline_paused(p_paused boolean,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform civicpulse_delivery.require_machine('publication_operator');
  if p_paused is null or p_review_reference is null or length(btrim(p_review_reference))=0 or length(p_review_reference)>1000 then
    raise exception 'Pause flag and review reference required' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(728361904);
  -- Exact bootstrap/baseline, unknown-outcome and resume gates are not yet implemented.
  if not p_paused then raise exception 'Pipeline resume is not enabled' using errcode='55000'; end if;
  update civicpulse_delivery.pipeline_state set paused=true where singleton;
  insert into civicpulse_delivery.operator_audit(actor,action,review_reference)
    values(session_user,'pause',p_review_reference);
  return jsonb_build_object('paused',true);
end;
$$;
revoke all on function civicpulse_delivery.set_pipeline_paused(boolean,text) from public,anon,authenticated;

create function civicpulse_delivery.cms_publication_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
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
  return result;
end;
$$;
create function civicpulse_delivery.cms_record_publication_status(p_kind text,p_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform civicpulse.require_role();
  if p_kind is null or p_kind not in ('organization','calendar','event','layer','map') or p_id is null or length(p_id)=0 then
    raise exception 'Valid content kind and id required' using errcode='22023';
  end if;
  with context as (
    select s.dataset_epoch,p.live_dataset_epoch,p.live_inventory_complete,
      p.live_inventory_complete and p.live_dataset_epoch=s.dataset_epoch and p.live_generation<=s.generation as known,p.live_inventory
    from civicpulse_delivery.publication_state s cross join civicpulse_delivery.pipeline_state p where s.singleton and p.singleton
  ), revisions as (
    select c.*,(select revision from civicpulse.published where kind=p_kind and id=p_id) as published,
      (select (item->>'revision')::bigint from jsonb_array_elements(coalesce(c.live_inventory,'[]'::jsonb)) item
        where item->>'kind'=p_kind and item->>'id'=p_id) as live from context c
  )
  select jsonb_build_object('dataset_epoch',r.dataset_epoch,'live_dataset_epoch',r.live_dataset_epoch,'observed_at',statement_timestamp(),
    'last_event_id',e.event_id,'last_action',e.action,'last_generation',e.generation::text,
    'published_revision',r.published::text,'live_revision',case when r.live_inventory_complete then r.live::text else null end,
    'website_state',case when r.known is not true then 'unknown'
      when r.published is null and r.live is not null then 'pending_removal'
      when r.published is not null and (r.live is null or r.published<>r.live) then 'pending_publication'
      when r.published is not null then 'live' else 'absent' end)
    into result from revisions r left join lateral (
      select event_id,action,generation from civicpulse_delivery.outbox
      where dataset_epoch=r.dataset_epoch and kind=p_kind and id=p_id order by generation desc limit 1
    ) e on true;
  return result;
end;
$$;
revoke all on function civicpulse_delivery.cms_publication_status() from public,anon,authenticated;
revoke all on function civicpulse_delivery.cms_record_publication_status(text,text) from public,anon,authenticated;
grant execute on function civicpulse_delivery.cms_publication_status() to authenticated;
grant execute on function civicpulse_delivery.cms_record_publication_status(text,text) to authenticated;

create function public.cms_publication_status() returns jsonb
language sql stable security invoker set search_path='' as $$ select civicpulse_delivery.cms_publication_status(); $$;
create function public.cms_record_publication_status(p_kind text,p_id text) returns jsonb
language sql stable security invoker set search_path='' as $$ select civicpulse_delivery.cms_record_publication_status(p_kind,p_id); $$;
revoke all on function public.cms_publication_status() from public,anon,authenticated;
revoke all on function public.cms_record_publication_status(text,text) from public,anon,authenticated;
grant execute on function public.cms_publication_status() to authenticated;
grant execute on function public.cms_record_publication_status(text,text) to authenticated;
