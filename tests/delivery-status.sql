begin;
-- Disposable NOLOGIN identities; SET SESSION AUTHORIZATION exercises session_user,
-- including inside definer functions. No real credentials/logins are provisioned.
create role cp_test_dispatcher nologin;
create role cp_test_runner nologin;
create role cp_test_reconciler nologin;
create role cp_test_operator nologin;
create role cp_test_impostor nologin;
grant cp_test_operator to cp_test_impostor;
grant usage on schema civicpulse_delivery to cp_test_dispatcher,cp_test_runner,cp_test_reconciler,cp_test_operator,cp_test_impostor;
-- Only the operator gets its production-intended function grant. Other identities
-- receive it temporarily below to prove registry checks independently of ACLs.
grant execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_test_operator;
insert into civicpulse_delivery.machine_registry(role_name,role_oid,capability,enabled,expires_at)
select rolname,oid,replace(rolname,'cp_test_',''),true,clock_timestamp()+interval '1 hour'
from pg_roles where rolname in ('cp_test_dispatcher','cp_test_runner','cp_test_reconciler');
insert into civicpulse_delivery.machine_registry values('cp_test_operator','cp_test_operator'::regrole::oid,'publication_operator',true,clock_timestamp()+interval '1 hour');
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.denied(command text,expected text default '42501') returns void language plpgsql security invoker as $$
begin
  begin execute command; exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Unexpected SQLSTATE %, wanted %',sqlstate,expected;
  end;
  raise exception 'Expected rejection: %',command;
end $$;
insert into auth.users values ('00000000-0000-4000-8000-000000000031'),('00000000-0000-4000-8000-000000000032'),('00000000-0000-4000-8000-000000000033');
insert into civicpulse.members values('00000000-0000-4000-8000-000000000031','admin'),('00000000-0000-4000-8000-000000000032','editor');
set session authorization anon;
select pg_temp.denied('select public.cms_publication_status()');
select pg_temp.denied('select public.cms_record_publication_status(''event'',''x'')');
select pg_temp.denied('select * from civicpulse_delivery.pipeline_state');
reset session authorization;
set session authorization authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000033',true);
select pg_temp.denied('select public.cms_publication_status()');
select pg_temp.denied('select civicpulse_delivery.cms_publication_status()');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
select pg_temp.assert(public.cms_publication_status() @> '{"paused":true,"bootstrap_complete":false,"state":null,"active_job":null,"live_generation":null,"live_dataset_epoch":null,"generation_lag":null,"live_inventory_complete":false,"last_error":null}', 'initial status truthful');
select pg_temp.assert(public.cms_record_publication_status('event','missing')->>'website_state'='unknown','no receipt is unknown, not absent');
select public.save_draft('organization','status-org','{"id":"status-org","name":"Public"}',0);
select public.publish('organization','status-org',1);
select pg_temp.denied('update civicpulse_delivery.pipeline_state set paused=false');
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''review'')');
reset session authorization;
-- Owner seeds verified receipts to exercise read semantics; this is test setup,
-- not a machine permission test or a claim that verification RPCs exist.
update civicpulse_delivery.pipeline_state set live_dataset_epoch=(select dataset_epoch from civicpulse_delivery.publication_state),
  live_generation=0,live_deployment_id='test-deployment',live_source_sha=repeat('a',40),live_at=clock_timestamp(),
  live_inventory_complete=true,live_inventory='[]';
set session authorization authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000032',true);
select pg_temp.assert(public.cms_publication_status()->>'generation_lag'='1','same epoch lag');
select pg_temp.assert(public.cms_record_publication_status('event','missing')->>'website_state'='absent','known empty inventory');
select pg_temp.assert(public.cms_record_publication_status('organization','status-org')->>'website_state'='pending_publication','new published record pending');
select public.save_draft('organization','status-org','{"id":"status-org","name":"Unpublished draft"}',1);
select pg_temp.assert(public.cms_record_publication_status('organization','status-org')->>'published_revision'='1','draft revision ignored');
reset session authorization;
update civicpulse_delivery.pipeline_state set live_inventory='[{"kind":"organization","id":"status-org","revision":"1"}]',live_generation=1;
set session authorization authenticated;
select pg_temp.assert(public.cms_record_publication_status('organization','status-org')->>'website_state'='live','exact published tuple live despite edited draft');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
select public.withdraw('organization','status-org',1);
select pg_temp.assert(public.cms_record_publication_status('organization','status-org') @> '{"website_state":"pending_removal","last_action":"withdraw","last_generation":"2","published_revision":null,"live_revision":"1"}', 'withdrawal status uses tombstone');
reset session authorization;
update civicpulse_delivery.pipeline_state set live_dataset_epoch=gen_random_uuid();
set session authorization authenticated;
select pg_temp.assert(public.cms_publication_status() @> '{"generation_lag":null,"live_generation":"1","live_deployment_id":"test-deployment"}','cross epoch preserves receipt without lag');
select pg_temp.assert(public.cms_record_publication_status('organization','status-org') @> '{"website_state":"unknown","live_revision":"1"}', 'cross epoch unknown with qualified prior revision');
reset session authorization;
update civicpulse_delivery.pipeline_state set live_dataset_epoch=(select dataset_epoch from civicpulse_delivery.publication_state),live_generation=3;
set session authorization authenticated;
select pg_temp.assert(public.cms_publication_status() @> '{"generation_lag":null,"status_error":"live_generation_ahead"}','same epoch rewind alarm');
select pg_temp.assert(public.cms_record_publication_status('organization','status-org')->>'website_state'='unknown','rewind cannot claim pending or live');
reset session authorization;
update civicpulse_delivery.pipeline_state set live_dataset_epoch=(select dataset_epoch from civicpulse_delivery.publication_state),live_inventory_complete=false;
set session authorization authenticated;
select pg_temp.assert(public.cms_publication_status()->'generation_lag'='null'::jsonb,'incomplete receipt has null lag');
select pg_temp.assert(public.cms_record_publication_status('event','missing')->>'website_state'='unknown','incomplete inventory is unknown');
reset session authorization;
delete from civicpulse.members where user_id='00000000-0000-4000-8000-000000000031';
set session authorization authenticated;
select pg_temp.denied('select public.cms_publication_status()');
reset session authorization;
set session authorization cp_test_operator;
select pg_temp.assert(civicpulse_delivery.set_pipeline_paused(true,'fixture-review')='{"paused":true}'::jsonb,'operator can pause');
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(false,''fixture-review'')','55000');
select pg_temp.denied('select * from civicpulse_delivery.machine_registry');
select pg_temp.denied('update civicpulse_delivery.pipeline_state set paused=false');
select pg_temp.denied('select * from civicpulse.drafts');
select pg_temp.denied('select civicpulse_delivery.require_machine(''publication_operator'')');
select pg_temp.denied('select public.cms_publication_status()');
reset session authorization;
set session authorization cp_test_impostor;
set role cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''forged'')');
reset role;
reset session authorization;
-- ACL and capability enforcement are independent. Wrong capabilities cannot act
-- even when an operator EXECUTE grant is accidentally inherited/provisioned.
grant execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_test_runner,cp_test_dispatcher,cp_test_reconciler;
set session authorization cp_test_runner;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''wrong capability'')');
select pg_temp.denied('insert into civicpulse.members values(gen_random_uuid(),''admin'')');
select pg_temp.denied('select public.save_draft(''organization'',''x'',''{"id":"x","name":"X"}'',0)');
reset session authorization;
set session authorization cp_test_dispatcher;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''wrong capability'')');
select pg_temp.denied('select * from civicpulse_delivery.outbox');
reset session authorization;
set session authorization cp_test_reconciler;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''wrong capability'')');
reset session authorization;
revoke execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) from cp_test_operator;
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''ACL revoked'')');
reset session authorization;
grant execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_test_operator;
update civicpulse_delivery.machine_registry set role_oid=0 where role_name='cp_test_operator';
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''obsolete identity'')');
reset session authorization;
update civicpulse_delivery.machine_registry set role_oid='cp_test_operator'::regrole::oid where role_name='cp_test_operator';
-- Drop/recreate under the same name must not revive the old registration.
revoke cp_test_operator from cp_test_impostor;
revoke execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) from cp_test_operator;
revoke usage on schema civicpulse_delivery from cp_test_operator;
drop role cp_test_operator;
create role cp_test_operator nologin;
grant usage on schema civicpulse_delivery to cp_test_operator;
grant execute on function civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_test_operator;
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''recreated name'')');
reset session authorization;
update civicpulse_delivery.machine_registry set role_oid='cp_test_operator'::regrole::oid where role_name='cp_test_operator';
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_test_operator';
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''disabled'')');
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_test_operator';
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''expired'')');
reset session authorization;
delete from civicpulse_delivery.machine_registry where role_name='cp_test_operator';
set session authorization cp_test_operator;
select pg_temp.denied('select civicpulse_delivery.set_pipeline_paused(true,''revoked'')');
reset session authorization;
select pg_temp.assert((select paused from civicpulse_delivery.pipeline_state),'foundation stays paused');
select pg_temp.assert((select count(*)=1 from civicpulse_delivery.operator_audit),'only authorized operator mutation audited');
rollback;
select 'Delivery identity/status real-session checks passed' as result;
