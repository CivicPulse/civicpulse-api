-- LOCAL ONLY: additive ADR contract. Applying this is separately rollout-gated.
create schema civicpulse_delivery;
revoke all on schema civicpulse_delivery from public, anon, authenticated;
grant usage on schema civicpulse_delivery to anon, authenticated;

create table civicpulse_delivery.publication_state (
  singleton boolean primary key default true check(singleton),
  dataset_epoch uuid not null unique default gen_random_uuid(),
  generation bigint not null default 0 check(generation>=0),
  bootstrap_complete boolean not null default false
);
insert into civicpulse_delivery.publication_state(singleton) values(true);
alter table civicpulse_delivery.publication_state enable row level security;
create policy public_metadata on civicpulse_delivery.publication_state for select to anon,authenticated using(true);
grant select on civicpulse_delivery.publication_state to anon,authenticated;

create table civicpulse_delivery.outbox (
  event_id uuid primary key default gen_random_uuid(),
  schema_version integer not null default 1 check(schema_version=1),
  dataset_epoch uuid not null,
  generation bigint not null check(generation>0),
  action text not null check(action in ('publish','withdraw','bootstrap')),
  kind text, id text, revision bigint,
  occurred_at timestamptz not null default clock_timestamp(),
  dispatch_state text not null default 'pending' check(dispatch_state in ('pending','leased','accepted','retry','failed')),
  dispatch_attempts integer not null default 0 check(dispatch_attempts>=0),
  next_attempt_at timestamptz,
  dispatch_lease_id uuid,
  lease_expires_at timestamptz,
  worker_id text, run_id text, error_code text,
  unique(dataset_epoch,generation),
  check((action='bootstrap' and kind is null and id is null and revision is null) or
    (action in ('publish','withdraw') and kind in ('organization','calendar','event','layer','map')
      and id is not null and revision is not null and revision>0))
);
alter table civicpulse_delivery.outbox enable row level security;
revoke all on civicpulse_delivery.outbox from public,anon,authenticated;
create index outbox_dispatch on civicpulse_delivery.outbox(dispatch_state,next_attempt_at);
create index outbox_record on civicpulse_delivery.outbox(kind,id,generation desc);

-- Every existing v1 published mutation appends history only after its content /
-- features are complete. Its catalog lock remains held through this trigger and
-- commit. Re-publishing changes published_at in v1, so always advances generation.
-- A failed outbox append aborts the original publication transaction.
create function civicpulse_delivery.record_publication() returns trigger
language plpgsql security invoker set search_path='' as $$
declare epoch uuid; version bigint;
begin
  if new.action not in ('publish','withdraw') then return new; end if;
  perform pg_advisory_xact_lock(728361904);
  update civicpulse_delivery.publication_state set generation=generation+1
    where singleton returning dataset_epoch,generation into strict epoch,version;
  insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
    values(epoch,version,new.action,new.kind,new.id,new.revision);
  return new;
end;
$$;
revoke all on function civicpulse_delivery.record_publication() from public,anon,authenticated;
create trigger publication_intent after insert on civicpulse.history
  for each row execute function civicpulse_delivery.record_publication();

-- STABLE SQL executes all CTEs in one statement snapshot. Inventory is complete,
-- not affected by PostgREST's row limit: the function returns one JSON object.
create function public.publication_manifest() returns jsonb
language sql stable security invoker set search_path='' as $$
  with headers as materialized (
    select set_config('response.headers','[{"Cache-Control":"no-store, max-age=0"}]',true)
  ), inventory as materialized (
    select kind,id,revision,payload from civicpulse.published
  ), counts as (
    select jsonb_build_object(
      'organization',count(*) filter(where kind='organization'),
      'calendar',count(*) filter(where kind='calendar'),
      'event',count(*) filter(where kind='event'),
      'layer',count(*) filter(where kind='layer'),
      'map',count(*) filter(where kind='map')) as value from inventory
  ), feature_counts as (
    select kind,id,count(*) as n from civicpulse.features group by kind,id
  ), event_count as (
    select coalesce(sum(n),0) as n from feature_counts where kind='event'
  ), layer_inventory as (
    select l.id,l.revision,
      case when l.id='event-locations' then 'events' else 'stored' end as mode,
      case when l.id='event-locations' then e.n else coalesce(f.n,0) end as n
    from inventory l cross join event_count e
    left join feature_counts f on f.kind='layer' and f.id=l.id
    where l.kind='layer'
  )
  select jsonb_build_object(
    'schema_version',1,'dataset_epoch',s.dataset_epoch,'generation',s.generation::text,
    'bootstrap_complete',s.bootstrap_complete,'counts',c.value,
    'records',(select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'revision',revision::text)
      order by kind collate "C",id collate "C"),'[]'::jsonb) from inventory),
    'layers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',revision::text,
      'mode',mode,'feature_count',n) order by id collate "C"),'[]'::jsonb) from layer_inventory)
  ) from civicpulse_delivery.publication_state s cross join counts c cross join headers
  where s.singleton;
$$;
revoke all on function public.publication_manifest() from public,anon,authenticated;
grant execute on function public.publication_manifest() to anon,authenticated;
