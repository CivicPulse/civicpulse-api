-- The public schema is the HTTP surface; internal tables are never exposed directly.
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create schema if not exists civicpulse;
revoke all on schema civicpulse from public;
grant usage on schema civicpulse, extensions to anon, authenticated;

create table civicpulse.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('editor', 'admin')),
  created_at timestamptz not null default now()
);
alter table civicpulse.members enable row level security;
create policy own_membership on civicpulse.members for select to authenticated
  using (user_id = (select auth.uid()));
grant select on civicpulse.members to authenticated;

create function public.cms_role() returns text language sql stable security invoker
set search_path = '' as $$
  select role from civicpulse.members where user_id = (select auth.uid());
$$;
revoke all on function public.cms_role() from public, anon;
grant execute on function public.cms_role() to authenticated;

create table civicpulse.drafts (
  kind text not null check (kind in ('organization','calendar','event','layer','map')),
  id text not null check (id ~ '^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$'),
  revision bigint not null check (revision > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object' and payload->>'id' = id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (kind,id)
);
create table civicpulse.published (
  kind text not null,
  id text not null,
  revision bigint not null,
  payload jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid references auth.users(id) on delete set null,
  primary key (kind,id),
  foreign key (kind,id) references civicpulse.drafts(kind,id)
);
create table civicpulse.dependencies (
  kind text not null, id text not null,
  target_kind text not null, target_id text not null,
  primary key (kind,id,target_kind,target_id),
  foreign key (kind,id) references civicpulse.published(kind,id) on delete cascade,
  foreign key (target_kind,target_id) references civicpulse.published(kind,id)
);
create index dependencies_target on civicpulse.dependencies(target_kind,target_id);
create table civicpulse.features (
  kind text not null, id text not null, ordinal bigint not null,
  feature jsonb not null,
  geom extensions.geometry(Geometry,4326) not null,
  primary key (kind,id,ordinal),
  foreign key (kind,id) references civicpulse.published(kind,id) on delete cascade,
  check (not extensions.st_isempty(geom) and extensions.st_isvalid(geom))
);
create index features_geom on civicpulse.features using gist(geom);
create table civicpulse.history (
  sequence bigint generated always as identity primary key,
  kind text not null, id text not null, revision bigint not null,
  action text not null check (action in ('save','publish','withdraw')),
  actor uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  payload jsonb not null
);
create index history_document on civicpulse.history(kind,id,sequence desc);
create index drafts_updated_by on civicpulse.drafts(updated_by);
create index published_by on civicpulse.published(published_by);
create index history_actor on civicpulse.history(actor);

alter table civicpulse.drafts enable row level security;
alter table civicpulse.published enable row level security;
alter table civicpulse.features enable row level security;
alter table civicpulse.dependencies enable row level security;
alter table civicpulse.history enable row level security;
create policy staff_read on civicpulse.drafts for select to authenticated
  using ((select public.cms_role()) in ('editor','admin'));
create policy staff_read on civicpulse.history for select to authenticated
  using ((select public.cms_role()) in ('editor','admin'));
create policy public_read on civicpulse.published for select to anon, authenticated using (true);
create policy public_read on civicpulse.features for select to anon, authenticated using (true);
create policy public_read on civicpulse.dependencies for select to anon, authenticated using (true);
grant select on civicpulse.drafts, civicpulse.history to authenticated;
grant select on civicpulse.published, civicpulse.features, civicpulse.dependencies to anon, authenticated;
-- No client gets table write privileges, even admins. All writes use checked RPCs.
create view public.cms_drafts with (security_invoker = true) as select * from civicpulse.drafts;
create view public.cms_history with (security_invoker = true) as select * from civicpulse.history;
create view public.content with (security_invoker = true) as
  select kind,id,revision,payload,published_at from civicpulse.published;
revoke all on public.cms_drafts, public.cms_history, public.content from public, anon, authenticated;
grant select on public.cms_drafts, public.cms_history to authenticated;
grant select on public.content to anon, authenticated;

-- Privileged implementations live outside exposed schemas. Every entry point checks
-- auth.uid() and live membership, not mutable user metadata or stale JWT role claims.
create function civicpulse.require_role(admin_only boolean default false) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare actor uuid := auth.uid(); staff_role text;
begin
  select role into staff_role from civicpulse.members where user_id = actor;
  if actor is null or staff_role is null or (admin_only and staff_role <> 'admin') then
    raise exception 'Staff permission required' using errcode = '42501';
  end if;
  return actor;
end;
$$;

create function civicpulse.save_draft(p_kind text, p_id text, p_payload jsonb, p_expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor uuid; current_revision bigint; next_revision bigint;
begin
  actor := civicpulse.require_role();
  -- Serializes the small editorial workload, including cross-document references.
  perform pg_advisory_xact_lock(728361904);
  select revision into current_revision from civicpulse.drafts where kind=p_kind and id=p_id for update;
  if p_expected_revision is null or p_expected_revision <> coalesce(current_revision,0) then
    raise exception 'Draft changed; reload before saving' using errcode = '40001';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or
     p_payload->>'id' is distinct from p_id then
    raise exception 'Payload must be an object with matching id' using errcode = '22023';
  end if;
  next_revision := coalesce(current_revision,0)+1;
  insert into civicpulse.drafts(kind,id,revision,payload,updated_by)
    values(p_kind,p_id,next_revision,p_payload,actor)
    on conflict(kind,id) do update set revision=excluded.revision,payload=excluded.payload,
      updated_by=excluded.updated_by,updated_at=now();
  insert into civicpulse.history(kind,id,revision,action,actor,payload)
    values(p_kind,p_id,next_revision,'save',actor,p_payload);
  return next_revision;
end;
$$;

create function civicpulse.require_text(doc jsonb, field text) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if jsonb_typeof(doc->field) is distinct from 'string' or btrim(doc->>field) = '' then
    raise exception 'Required text field: %',field using errcode = '22023';
  end if;
end;
$$;

create function civicpulse.validate_publication(p_kind text, doc jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare field text; item jsonb; coords jsonb; start_at timestamptz; end_at timestamptz;
begin
  perform civicpulse.require_text(doc,case when p_kind='event' then 'title' else 'name' end);
  if p_kind='event' then
    foreach field in array array['start','end','category','location','address','organizationId','sourceUrl','sourceChecked'] loop
      perform civicpulse.require_text(doc,field);
    end loop;
    if doc->>'sourceUrl' !~ '^https?://[^[:space:]]+$' or
       doc->>'sourceChecked' !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Event requires source URL and checked date' using errcode='22023';
    end if;
    perform (doc->>'sourceChecked')::date;
    if doc->'sample' is distinct from 'false'::jsonb then
      raise exception 'Only sourced, non-sample events may be published' using errcode='22023';
    end if;
    foreach field in array array['start','end'] loop
      if doc->>field !~ '^\d{4}-\d{2}-\d{2}T.*(Z|[+-]\d{2}:\d{2})$' then
        raise exception 'Event times require an explicit timezone' using errcode='22023';
      end if;
    end loop;
    start_at := (doc->>'start')::timestamptz; end_at := (doc->>'end')::timestamptz;
    if end_at < start_at or (end_at = start_at and doc->'endTimeUnknown' is distinct from 'true'::jsonb) then
      raise exception 'Event end must follow start' using errcode='22023';
    end if;
    if jsonb_typeof(doc->'calendarIds') is distinct from 'array' or jsonb_array_length(doc->'calendarIds')=0 then
      raise exception 'At least one calendar is required' using errcode='22023';
    end if;
    for item in select value from jsonb_array_elements(doc->'calendarIds') loop
      if jsonb_typeof(item) <> 'string' or not exists (
        select 1 from civicpulse.published where kind='calendar' and id=item#>>'{}'
        and payload->>'organizationId'=doc->>'organizationId'
      ) then raise exception 'Calendar must be published and belong to event organization' using errcode='23503'; end if;
    end loop;
    foreach field in array array['allDay','endTimeUnknown','isVirtual','addressPrivate'] loop
      if doc ? field and jsonb_typeof(doc->field) <> 'boolean' then
        raise exception 'Expected boolean: %',field using errcode='22023';
      end if;
    end loop;
    coords := doc->'coordinates';
    if coords is not null and coords <> 'null'::jsonb then
      if jsonb_typeof(coords) <> 'array' or jsonb_array_length(coords) <> 2 then
        raise exception 'Coordinates must be [longitude, latitude]' using errcode='22023';
      end if;
      if jsonb_typeof(coords->0) <> 'number' or jsonb_typeof(coords->1) <> 'number' or
        (coords->>0)::float8 not between -180 and 180 or (coords->>1)::float8 not between -90 and 90 then
        raise exception 'Coordinates outside WGS84 bounds' using errcode='22023';
      end if;
      if doc->'addressPrivate'='true'::jsonb or doc->'isVirtual'='true'::jsonb then
        raise exception 'Private-address and virtual events cannot publish coordinates' using errcode='22023';
      end if;
    end if;
  elsif p_kind='calendar' then
    perform civicpulse.require_text(doc,'organizationId');
    if exists (select 1 from civicpulse.published e where e.kind='event'
      and e.payload->'calendarIds' ? (doc->>'id')
      and e.payload->>'organizationId' is distinct from doc->>'organizationId') then
      raise exception 'Calendar organization conflicts with published events' using errcode='23503';
    end if;
  elsif p_kind='map' then
    if jsonb_typeof(doc->'layers') is distinct from 'array' or jsonb_array_length(doc->'layers')=0 then
      raise exception 'Map must reference at least one layer' using errcode='22023';
    end if;
    for item in select value from jsonb_array_elements(doc->'layers') loop
      if jsonb_typeof(item) <> 'string' then raise exception 'Layer IDs must be strings' using errcode='22023'; end if;
    end loop;
  elsif p_kind='layer' then
    if doc->>'kind' is null or doc->>'kind' not in ('point','line','area') then
      raise exception 'Layer kind must be point, line, or area' using errcode='22023';
    end if;
    if doc->>'id' = 'event-locations' then
      if doc->>'dynamic' is distinct from 'events' or doc ? 'geojson' then
        raise exception 'event-locations is generated from published events' using errcode='22023';
      end if;
    else
      if doc->'geojson'->>'type' is distinct from 'FeatureCollection' or
         jsonb_typeof(doc->'geojson'->'features') is distinct from 'array' then
        raise exception 'Layer requires a GeoJSON FeatureCollection' using errcode='22023';
      end if;
    end if;
  end if;
end;
$$;

create function civicpulse.publish(p_kind text, p_id text, p_expected_revision bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare actor uuid; draft civicpulse.drafts; item record; shape extensions.geometry;
begin
  actor := civicpulse.require_role(true);
  perform pg_advisory_xact_lock(728361904);
  select * into draft from civicpulse.drafts where kind=p_kind and id=p_id for update;
  if not found then raise exception 'Draft not found' using errcode='P0002'; end if;
  if p_expected_revision is distinct from draft.revision then
    raise exception 'Draft changed; review the latest revision' using errcode='40001';
  end if;
  perform civicpulse.validate_publication(p_kind,draft.payload);
  insert into civicpulse.published(kind,id,revision,payload,published_by)
    values(p_kind,p_id,draft.revision,case when p_kind='layer' then draft.payload-'geojson' else draft.payload end,actor)
    on conflict(kind,id) do update set revision=excluded.revision,payload=excluded.payload,
      published_by=excluded.published_by,published_at=now();
  delete from civicpulse.dependencies where kind=p_kind and id=p_id;
  if p_kind in ('event','calendar') then
    insert into civicpulse.dependencies values(p_kind,p_id,'organization',draft.payload->>'organizationId');
  end if;
  if p_kind='event' then
    insert into civicpulse.dependencies select distinct p_kind,p_id,'calendar',value
      from jsonb_array_elements_text(draft.payload->'calendarIds');
  elsif p_kind='map' then
    insert into civicpulse.dependencies select distinct p_kind,p_id,'layer',value
      from jsonb_array_elements_text(draft.payload->'layers');
  end if;
  delete from civicpulse.features where kind=p_kind and id=p_id;
  if p_kind='layer' and p_id <> 'event-locations' then
    for item in select value,ordinality from jsonb_array_elements(draft.payload->'geojson'->'features') with ordinality loop
      if item.value->>'type' is distinct from 'Feature' or
         jsonb_typeof(item.value->'properties') is distinct from 'object' or
         jsonb_typeof(item.value->'geometry') is distinct from 'object' then
        raise exception 'Each feature requires geometry and an object of properties' using errcode='22023';
      end if;
      shape := extensions.st_geomfromgeojson(item.value->'geometry');
      if extensions.st_isempty(shape) or not extensions.st_isvalid(shape) then
        raise exception 'Feature % has invalid geometry: %',item.ordinality,extensions.st_isvalidreason(shape) using errcode='22023';
      end if;
      if extensions.st_srid(shape) <> 4326 or extensions.st_ndims(shape) <> 2 or
         not extensions.st_coveredby(shape,extensions.st_makeenvelope(-180,-90,180,90,4326)) then
        raise exception 'Geometry must use two-dimensional WGS84 coordinates' using errcode='22023';
      end if;
      if (draft.payload->>'kind'='point' and extensions.st_geometrytype(shape) not in ('ST_Point','ST_MultiPoint')) or
         (draft.payload->>'kind'='line' and extensions.st_geometrytype(shape) not in ('ST_LineString','ST_MultiLineString')) or
         (draft.payload->>'kind'='area' and extensions.st_geometrytype(shape) not in ('ST_Polygon','ST_MultiPolygon')) then
        raise exception 'Geometry does not match layer kind' using errcode='22023';
      end if;
      insert into civicpulse.features values(p_kind,p_id,item.ordinality,item.value,shape);
    end loop;
  elsif p_kind='event' and jsonb_typeof(draft.payload->'coordinates')='array' then
    shape := extensions.st_setsrid(extensions.st_makepoint((draft.payload->'coordinates'->>0)::float8,
      (draft.payload->'coordinates'->>1)::float8),4326);
    insert into civicpulse.features values(p_kind,p_id,1,
      jsonb_build_object('type','Feature','id',p_id,'geometry',extensions.st_asgeojson(shape)::jsonb,'properties',draft.payload),shape);
  end if;
  insert into civicpulse.history(kind,id,revision,action,actor,payload)
    values(p_kind,p_id,draft.revision,'publish',actor,draft.payload);
  return draft.revision;
end;
$$;

create function civicpulse.withdraw(p_kind text,p_id text,p_expected_revision bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid; published civicpulse.published;
begin
  actor := civicpulse.require_role(true);
  perform pg_advisory_xact_lock(728361904);
  select * into published from civicpulse.published where kind=p_kind and id=p_id for update;
  if not found then raise exception 'Published record not found' using errcode='P0002'; end if;
  if p_expected_revision is distinct from published.revision then
    raise exception 'Publication changed; reload first' using errcode='40001';
  end if;
  -- FK prevents orphaned calendars, events or maps. Withdraw dependents first.
  delete from civicpulse.published where kind=p_kind and id=p_id;
  insert into civicpulse.history(kind,id,revision,action,actor,payload)
    values(p_kind,p_id,published.revision,'withdraw',actor,published.payload);
end;
$$;

create function public.save_draft(p_kind text,p_id text,p_payload jsonb,p_expected_revision bigint)
returns bigint language sql security invoker set search_path = '' as $$
  select civicpulse.save_draft(p_kind,p_id,p_payload,p_expected_revision);
$$;
create function public.publish(p_kind text,p_id text,p_expected_revision bigint)
returns bigint language sql security invoker set search_path = '' as $$
  select civicpulse.publish(p_kind,p_id,p_expected_revision);
$$;
create function public.withdraw(p_kind text,p_id text,p_expected_revision bigint)
returns void language sql security invoker set search_path = '' as $$
  select civicpulse.withdraw(p_kind,p_id,p_expected_revision);
$$;
revoke all on all functions in schema civicpulse from public, anon, authenticated;
grant execute on function civicpulse.save_draft(text,text,jsonb,bigint),
  civicpulse.publish(text,text,bigint),civicpulse.withdraw(text,text,bigint) to authenticated;
revoke all on function public.save_draft(text,text,jsonb,bigint),
  public.publish(text,text,bigint),public.withdraw(text,text,bigint) from public,anon,authenticated;
grant execute on function public.save_draft(text,text,jsonb,bigint),
  public.publish(text,text,bigint),public.withdraw(text,text,bigint) to authenticated;

-- Bounded, ordered GeoJSON pages. A null nextOffset indicates completion.
create function public.layer_geojson(p_layer_id text,p_limit integer default 500,p_offset integer default 0,
  p_west float8 default null,p_south float8 default null,p_east float8 default null,p_north float8 default null)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare bbox extensions.geometry; result jsonb; row_count integer; coordinates integer;
begin
  if p_limit is null or p_limit not between 1 and 1000 or p_offset is null or p_offset < 0 then
    raise exception 'limit must be 1..1000; offset must be nonnegative' using errcode='22023';
  end if;
  coordinates := num_nonnulls(p_west,p_south,p_east,p_north);
  if coordinates not in (0,4) then raise exception 'Supply all four bounds' using errcode='22023'; end if;
  if coordinates=4 then
    if not (p_west >= -180 and p_east <= 180 and p_south >= -90 and p_north <= 90
      and p_west < p_east and p_south < p_north) then
      raise exception 'Invalid WGS84 bounding box; split boxes crossing the antimeridian' using errcode='22023';
    end if;
    bbox := extensions.st_makeenvelope(p_west,p_south,p_east,p_north,4326);
  end if;
  if not exists(select 1 from civicpulse.published where kind='layer' and id=p_layer_id) then
    raise exception 'Published layer not found' using errcode='P0002';
  end if;
  with page as (
    select f.feature,f.id,f.ordinal from civicpulse.features f
    where ((p_layer_id='event-locations' and f.kind='event') or (f.kind='layer' and f.id=p_layer_id))
      and (bbox is null or extensions.st_intersects(f.geom,bbox))
    order by f.id,f.ordinal limit p_limit+1 offset p_offset
  ), numbered as (select *,row_number() over(order by id,ordinal) as n from page)
  select coalesce(jsonb_agg(feature order by id,ordinal) filter(where n<=p_limit),'[]'::jsonb),count(*)
    into result,row_count from numbered;
  return jsonb_build_object('type','FeatureCollection','features',result,
    'nextOffset',case when row_count>p_limit then p_offset+p_limit else null end);
end;
$$;
revoke all on function public.layer_geojson(text,integer,integer,float8,float8,float8,float8) from public;
grant execute on function public.layer_geojson(text,integer,integer,float8,float8,float8,float8) to anon,authenticated;
