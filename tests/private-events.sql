begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000021'),('00000000-0000-4000-8000-000000000022');
insert into civicpulse.members(user_id,role) values ('00000000-0000-4000-8000-000000000021','admin');
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.reject_private(doc jsonb) returns void language plpgsql as $$
declare version bigint; before_manifest jsonb; previous_payload jsonb;
begin
  before_manifest:=public.publication_manifest();
  select payload into previous_payload from public.content where kind='event' and id='private-test';
  select revision into version from public.cms_drafts where kind='event' and id='private-test';
  version:=public.save_draft('event','private-test',doc,coalesce(version,0));
  begin
    perform public.publish('event','private-test',version);
    raise exception 'UNEXPECTED successful private publication';
  exception when sqlstate '22023' then
    if sqlerrm like '%SENTINEL%' then raise exception 'Private value leaked in error'; end if;
  end;
  perform pg_temp.assert(public.publication_manifest()=before_manifest,'failed private publish preserves manifest');
  perform pg_temp.assert((select payload from public.content where kind='event' and id='private-test') is not distinct from previous_payload,'failed private publish preserves public payload');
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
select public.save_draft('organization','private-org','{"id":"private-org","name":"Organizer"}',0);
select public.publish('organization','private-org',1);
select public.save_draft('calendar','private-cal','{"id":"private-cal","name":"Calendar","organizationId":"private-org"}',0);
select public.publish('calendar','private-cal',1);
select public.save_draft('layer','event-locations','{"id":"event-locations","name":"Events","kind":"point","dynamic":"events"}',0);
select public.publish('layer','event-locations',1);
do $$
declare base jsonb := '{"id":"private-test","title":"Public title","start":"2026-10-16T12:00:00-04:00","end":"2026-10-16T13:00:00-04:00","category":"Community","location":"Private location — see organizer for details","address":"Private location — see organizer for details","addressPrivate":true,"sample":false,"sourceUrl":"https://example.org/signup?public=1#details","sourceChecked":"2026-10-16","organizationId":"private-org","calendarIds":["private-cal"]}';
 value jsonb; field text; version bigint; unsafe text;
begin
  -- Keep a successful sanitized public version while exercising independent rejects.
  version:=public.save_draft('event','private-test',base,0);
  perform public.publish('event','private-test',version);
  perform pg_temp.assert((select payload=base from public.content where kind='event' and id='private-test'),'exact reviewed payload published without projection');
  perform pg_temp.reject_private(base||'{"address":"SENTINEL secret street"}');
  perform pg_temp.reject_private(base||'{"location":"SENTINEL private meeting"}');
  foreach field in array array['sourceCity','sourceLocation','venueId','libraryBranchId','geocodedAddress','latitude','longitude','geometry','bounds','postcode','directionsUrl','attachments','metadata','newUnexpectedAlias'] loop
    perform pg_temp.reject_private(base||jsonb_build_object(field,jsonb_build_object('private','SENTINEL nested location')));
    perform pg_temp.reject_private(base||jsonb_build_object(field,null));
  end loop;
  for value in select element.value from jsonb_array_elements('[[],[0,0],[-83.6,32.8],{},true,"SENTINEL"]') as element loop
    perform pg_temp.reject_private(base||jsonb_build_object('coordinates',value));
  end loop;
  foreach field in array array['title','description','note','organizer','sourceLabel','sourceGroup','sourceEventId','sourceCalendar'] loop
    perform pg_temp.reject_private(base||jsonb_build_object(field,jsonb_build_object('private','SENTINEL')));
    perform pg_temp.reject_private(base||jsonb_build_object(field,null));
  end loop;
  foreach field in array array['addressPrivate','sample','allDay','endTimeUnknown','isVirtual'] loop
    perform pg_temp.reject_private(base||jsonb_build_object(field,'true'));
  end loop;
  foreach unsafe in array array['https://user:SENTINEL@example.org/','https://','https:///missing','javascript:alert(1)','https://example.org:99999/','https://example.org/SENTINEL secret',E'https://example.org/\nSENTINEL',E'https://example.org/\tSENTINEL',E'https://example.org/\\SENTINEL'] loop
    perform pg_temp.reject_private(base||jsonb_build_object('sourceUrl',unsafe));
  end loop;
  select revision into version from public.cms_drafts where kind='event' and id='private-test';
  version:=public.save_draft('event','private-test',base||'{"coordinates":null,"isVirtual":true,"description":"Editors deliberately publish this public prose."}',version);
  perform public.publish('event','private-test',version);
  perform pg_temp.assert(jsonb_array_length(public.layer_geojson('event-locations')->'features')=0,'private plus virtual creates no public feature');
  perform pg_temp.assert(public.publication_manifest()->'layers'->0->>'feature_count'='0','no private event in manifest feature count');
  -- Heterogeneous nonprivate fields still retain the frozen v1 contract.
  version:=public.save_draft('event','private-test',base||'{"addressPrivate":false,"address":"Public venue","location":"Public venue","coordinates":[-83.6,32.8],"sourceCity":"Public city"}',version);
  perform public.publish('event','private-test',version);
  perform pg_temp.assert(jsonb_array_length(public.layer_geojson('event-locations')->'features')=1,'nonprivate regression publishes geometry');
  version:=public.save_draft('event','private-test',base,version);
  perform public.publish('event','private-test',version);
  -- Last draft retains staff evidence while public revision remains safe.
  perform public.save_draft('event','private-test',base||'{"address":"SENTINEL final draft","metadata":{"private":"SENTINEL"}}',version);
  perform pg_temp.assert((select payload->>'address' like '%SENTINEL%' from public.cms_drafts where id='private-test'),'staff retains original private evidence');
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000022',true);
select pg_temp.assert((select count(*)=0 from public.cms_drafts),'nonstaff cannot read private drafts');
select pg_temp.assert((select count(*)=0 from public.cms_history),'nonstaff cannot read private history');
reset role;
set local role anon;
select pg_temp.assert((select payload::text not like '%SENTINEL%' from public.content where kind='event' and id='private-test'),'anonymous raw payload has no sentinel');
select pg_temp.assert(jsonb_array_length(public.layer_geojson('event-locations')->'features')=0,'anonymous GeoJSON has no private event');
reset role;
select pg_temp.assert((select count(*)=0 from civicpulse_delivery.outbox where id='private-test' and revision=2),'rejected revision has no durable intent');
rollback;
select 'Private-event publication rejection checks passed' as result;
