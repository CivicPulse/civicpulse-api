begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000011');
insert into civicpulse.members(user_id,role) values ('00000000-0000-4000-8000-000000000011','admin');
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.denied(statement text,expected text) returns void language plpgsql as $$
begin
 begin execute statement;
 exception when others then if sqlstate=expected then return; end if; raise; end;
 raise exception 'Unexpected success: %',statement;
end $$;
set local role anon;
select pg_temp.assert(public.publication_manifest()->>'generation'='0','initial generation');
select pg_temp.assert(public.publication_manifest()->'bootstrap_complete'='false'::jsonb,'bootstrap is gated');
select pg_temp.assert(public.publication_manifest()->'counts'='{"organization":0,"calendar":0,"event":0,"layer":0,"map":0}'::jsonb,'explicit zero counts');
select pg_temp.assert(public.publication_manifest()->'records'='[]'::jsonb,'empty inventory');
select pg_temp.assert(public.publication_manifest()->'layers'='[]'::jsonb,'empty layer inventory');
select pg_temp.assert(current_setting('response.headers') like '%no-store%','manifest cache header');
select pg_temp.denied('select * from civicpulse_delivery.outbox','42501');
select pg_temp.denied('update civicpulse_delivery.publication_state set bootstrap_complete=true','42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
select public.save_draft('organization','test-org','{"id":"test-org","name":"Test"}',0);
select pg_temp.assert(public.publication_manifest()->>'generation'='0','draft saves do not change generation');
savepoint before_publish;
select public.publish('organization','test-org',1);
select pg_temp.assert(public.publication_manifest()->>'generation'='1','publish increments generation');
rollback to before_publish;
select pg_temp.assert(public.publication_manifest()->>'generation'='0','transaction rollback restores generation');
reset role;
select pg_temp.assert((select count(*)=0 from civicpulse_delivery.outbox),'rollback removes outbox intent');
-- Deliberately fail the event insert. Content must not survive the failure.
create function pg_temp.fail_event() returns trigger language plpgsql as $$ begin raise exception 'injected outbox failure' using errcode='23514'; end $$;
create trigger fail_event before insert on civicpulse_delivery.outbox for each row execute function pg_temp.fail_event();
set local role authenticated;
select pg_temp.denied($q$select public.publish('organization','test-org',1)$q$,'23514');
select pg_temp.assert((select count(*)=0 from public.content),'failed intent rolls back public content');
select pg_temp.assert(public.publication_manifest()->>'generation'='0','failed intent rolls back counter');
reset role;
drop trigger fail_event on civicpulse_delivery.outbox;
set local role authenticated;
select public.publish('organization','test-org',1);
select public.publish('organization','test-org',1);
select pg_temp.assert(public.publication_manifest()->>'generation'='2','v1 republish changes observable timestamp and advances generation');
select public.save_draft('layer','empty-layer','{"id":"empty-layer","name":"Empty layer","kind":"point","geojson":{"type":"FeatureCollection","features":[]}}',0);
select public.publish('layer','empty-layer',1);
select public.save_draft('layer','event-locations','{"id":"event-locations","name":"Events","kind":"point","dynamic":"events"}',0);
select public.publish('layer','event-locations',1);
select pg_temp.assert(public.publication_manifest()->'layers'='[{"id":"empty-layer","revision":"1","mode":"stored","feature_count":0},{"id":"event-locations","revision":"1","mode":"events","feature_count":0}]'::jsonb,'exhaustive stored and derived zero layers');
select pg_temp.assert(public.publication_manifest()->'records'->0->>'kind'='layer','C-sorted inventory');
select public.withdraw('organization','test-org',1);
select pg_temp.assert(public.publication_manifest()->'counts'->>'organization'='0','withdraw intentional empty');
select pg_temp.assert(public.publication_manifest()->>'generation'='5','withdraw increments generation');
select pg_temp.denied($q$select public.withdraw('organization','test-org',1)$q$,'P0002');
select pg_temp.assert(public.publication_manifest()->>'generation'='5','failed withdraw creates no generation');
select pg_temp.denied('select * from civicpulse_delivery.outbox','42501');
reset role;
select pg_temp.assert((select count(*)=5 from civicpulse_delivery.outbox),'one outbox event per committed mutation');
select pg_temp.assert((select revision=1 and action='withdraw' and id='test-org' from civicpulse_delivery.outbox where generation=5),'durable withdrawal tombstone');
select pg_temp.assert((select bool_and(dataset_epoch=(public.publication_manifest()->>'dataset_epoch')::uuid) from civicpulse_delivery.outbox),'epoch consistent');
-- A scalar JSON RPC must not truncate the complete inventory to the API row cap.
set local role authenticated;
do $$ begin
  for i in 1..1001 loop
    perform public.save_draft('organization','inventory-'||i,jsonb_build_object('id','inventory-'||i,'name','Inventory '||i),0);
    perform public.publish('organization','inventory-'||i,1);
  end loop;
end $$;
select pg_temp.assert(jsonb_array_length(public.publication_manifest()->'records')=1003,'manifest includes more than 1000 records');
reset role;
update civicpulse_delivery.publication_state set generation=9007199254740992;
set local role authenticated;
select public.publish('organization','inventory-1',1);
select pg_temp.assert(public.publication_manifest()->>'generation'='9007199254740993','counter survives beyond JS safe integers as decimal text');
reset role;
rollback;
select 'Publication generation/outbox/manifest checks passed' as result;
