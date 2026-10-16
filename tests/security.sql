begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003');
insert into civicpulse.members(user_id,role) values
 ('00000000-0000-4000-8000-000000000001','admin'),
 ('00000000-0000-4000-8000-000000000002','editor');
create function pg_temp.assert(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.denied(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Wrong error: % % (expected %)',sqlstate,sqlerrm,expected;
  end;
  raise exception 'Unexpected success: %',statement;
end $$;
set local role anon;
select pg_temp.assert((select count(*)=0 from public.content),'empty public content');
select pg_temp.denied('select * from public.cms_drafts','42501');
select pg_temp.denied($q$select public.save_draft('organization','org','{"id":"org"}',0)$q$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select pg_temp.assert(public.cms_role() is null,'ordinary user has no role');
select pg_temp.denied($q$select public.save_draft('organization','org','{"id":"org"}',0)$q$,'42501');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select pg_temp.assert(public.cms_role()='editor','editor recognized');
select public.save_draft('organization','org','{"id":"org","name":"Original"}',0);
select pg_temp.assert((select count(*)=1 from public.cms_drafts),'editor reads draft');
select pg_temp.assert((select count(*)=0 from public.content),'draft not public');
select pg_temp.denied($q$select public.publish('organization','org',1)$q$,'42501');
select pg_temp.denied($q$update civicpulse.members set role='admin'$q$,'42501');
select pg_temp.denied($q$insert into civicpulse.published(kind,id,revision,payload) values('organization','org',1,'{}')$q$,'42501');
select pg_temp.denied($q$select public.save_draft('organization','org','{"id":"org"}',0)$q$,'40001');
select pg_temp.denied($q$select public.save_draft('organization','org','{}',1)$q$,'22023');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.publish('organization','org',1);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select public.save_draft('organization','org','{"id":"org","name":"Changed draft"}',1);
select pg_temp.assert((select payload->>'name'='Original' from public.content where id='org'),'published snapshot survives editing');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select pg_temp.denied($q$select public.publish('organization','org',1)$q$,'40001');
select public.save_draft('calendar','cal','{"id":"cal","name":"Calendar","organizationId":"org"}',0);
select public.publish('calendar','cal',1);
select pg_temp.denied($q$select public.withdraw('organization','org',1)$q$,'23503');
select public.save_draft('event','event','{"id":"event","title":"Sourced event","start":"2026-10-16T12:00:00-04:00","end":"2026-10-16T13:00:00-04:00","category":"Community","location":"Library","address":"Public address","sample":false,"sourceUrl":"https://example.org/event","sourceChecked":"2026-10-16","organizationId":"org","calendarIds":["cal"],"coordinates":[-83.6,32.8]}',0);
select public.publish('event','event',1);
select public.save_draft('layer','event-locations','{"id":"event-locations","name":"Events","kind":"point","dynamic":"events"}',0);
select public.publish('layer','event-locations',1);
select pg_temp.assert(jsonb_array_length(public.layer_geojson('event-locations')->'features')=1,'event geometry published');
select public.save_draft('layer','places','{"id":"places","name":"Places","kind":"point","geojson":{"type":"FeatureCollection","features":[{"type":"Feature","id":"one","properties":{"name":"One"},"geometry":{"type":"Point","coordinates":[-83.6,32.8]}},{"type":"Feature","id":"two","properties":{"name":"Two"},"geometry":{"type":"Point","coordinates":[-84,33]}}]}}',0);
select public.publish('layer','places',1);
select pg_temp.assert((public.layer_geojson('places',1)->>'nextOffset')::integer=1,'geo pagination');
select pg_temp.assert(public.layer_geojson('places',1,1)->>'nextOffset' is null,'geo final page');
select pg_temp.assert(jsonb_array_length(public.layer_geojson('places',500,0,-83.7,32.7,-83.5,32.9)->'features')=1,'spatial bounds');
select pg_temp.denied($q$select public.layer_geojson('places',500,0,-83.7,null,null,null)$q$,'22023');
select pg_temp.denied($q$select public.layer_geojson('places',1001)$q$,'22023');
select public.save_draft('map','map','{"id":"map","name":"Map","layers":["places"]}',0);
select public.publish('map','map',1);
select pg_temp.denied($q$select public.withdraw('layer','places',1)$q$,'23503');
select public.save_draft('calendar','cal','{"id":"cal","name":"Calendar","organizationId":"other"}',1);
select pg_temp.denied($q$select public.publish('calendar','cal',2)$q$,'23503');
select public.save_draft('event','event',(select payload || '{"sample":true}'::jsonb from public.cms_drafts where kind='event' and id='event'),1);
select pg_temp.denied($q$select public.publish('event','event',2)$q$,'22023');
select public.save_draft('event','event',(select payload || '{"sample":false,"addressPrivate":true}'::jsonb from public.cms_drafts where kind='event' and id='event'),2);
select pg_temp.denied($q$select public.publish('event','event',3)$q$,'22023');
select public.save_draft('layer','places','{"id":"places","name":"Bad geometry","kind":"point","geojson":{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"Point","coordinates":[300,95]}}]}}',1);
select pg_temp.denied($q$select public.publish('layer','places',2)$q$,'22023');
select pg_temp.assert(jsonb_array_length(public.layer_geojson('places')->'features')=2,'failed publication rolls back all features');
reset role;
set local role anon;
select pg_temp.assert((select count(*)=6 from public.content),'anonymous reads published only');
select pg_temp.assert(jsonb_array_length(public.layer_geojson('places')->'features')=2,'anonymous GeoJSON');
select pg_temp.denied('select * from public.cms_history','42501');
reset role;
delete from civicpulse.members where role='editor';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select pg_temp.denied($q$select public.save_draft('organization','org','{"id":"org"}',2)$q$,'42501');
select pg_temp.assert((select count(*)=0 from public.cms_drafts),'membership revocation takes immediate effect');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.withdraw('map','map',1);
select public.withdraw('layer','places',1);
select pg_temp.assert((select count(*)=0 from civicpulse.features where id='places'),'withdraw removes geometry');
select pg_temp.assert((select count(*)>0 from public.cms_history where action='withdraw'),'withdraw audited');
reset role;
rollback;
select 'All permission, publication, and PostGIS checks passed' as result;
