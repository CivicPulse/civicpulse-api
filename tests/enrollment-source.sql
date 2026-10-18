begin;
create role cp_m21_operator nologin;
create role cp_m21_reconciler nologin;
create role cp_m21_runner nologin;
create role cp_m21_impostor nologin;
grant cp_m21_operator to cp_m21_impostor;
grant usage on schema civicpulse_delivery to cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor;
grant execute on function civicpulse_delivery.enroll_delivery_config(uuid,jsonb,text),civicpulse_delivery.approve_bootstrap(uuid,bigint,jsonb,text),civicpulse_delivery.reset_epoch(uuid,uuid,text),civicpulse_delivery.approve_epoch_baseline(uuid,text,jsonb,text),civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_m21_operator;
grant execute on function civicpulse_delivery.open_source_observation(text,text,text,uuid),civicpulse_delivery.record_source_observation(uuid,jsonb),civicpulse_delivery.open_provider_observation(text,uuid,uuid,text),civicpulse_delivery.record_provider_observation(uuid,jsonb) to cp_m21_reconciler;
insert into civicpulse_delivery.machine_registry(role_name,role_oid,capability,enabled,expires_at)
select rolname,oid,case rolname when 'cp_m21_operator' then 'publication_operator' when 'cp_m21_reconciler' then 'reconciler' else 'runner' end,true,clock_timestamp()+interval '1 hour'
from pg_roles where rolname in ('cp_m21_operator','cp_m21_reconciler','cp_m21_runner');
create temporary table m21_context(key text primary key,value jsonb);
grant select,insert,update on m21_context to cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor,authenticated,anon;
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.denied(command text,expected text default '42501') returns void language plpgsql security invoker as $$ begin
  begin execute command; exception when others then if sqlstate=expected then return; end if; raise exception 'Expected % got %: %',expected,sqlstate,sqlerrm; end;
  raise exception 'Unexpected success: %',command;
end $$;
create function pg_temp.ctx(k text) returns jsonb language sql as $$ select value from m21_context where key=k $$;
create function pg_temp.config() returns jsonb language sql immutable as $$ select jsonb_build_object(
 'schema_version',1,
 'source',jsonb_build_object('repository_id','9007199254740993','repository_owner_id','9007199254740994','repository_full_name','CivicPulse/fixture','workflow_id','99999999999999999999','workflow_path','.github/workflows/publish.yml','workflow_file_sha256',repeat('a',64),'ref','refs/heads/main','allowed_events','["push","schedule","workflow_dispatch"]'::jsonb,'api_version','2026-03-10','policy_format_version',1,'protection_bundle','{"classic":{"required_status_checks":{"strict":true,"contexts":["civicpulse-validate"]}},"rulesets":[],"effective_rules":[]}'::jsonb,'checkout_contract_version',1,'run_path_form','relative-main'),
 'provider',jsonb_build_object('account_id',repeat('a',32),'project_id','fixture-project','project_name','civicpulse-fixture','production_origin','https://www.civpulse.org','pages_origin','https://civicpulse-fixture.pages.dev'),
 'operation',jsonb_build_object('mode','solo-supervised-v1','environment_name','production','environment_evidence_sha256',repeat('b',64),'operator_user_id','9007199254740995','required_check_context','civicpulse-validate','required_check_app_id','42')); $$;
create function pg_temp.baseline() returns jsonb language sql immutable as $$ select jsonb_build_object(
 'schema_version',1,'project',jsonb_build_object('id','fixture-project','name','civicpulse-fixture','canonical_deployment_id','fixture-deployment','production_branch','main'),
 'deployment',jsonb_build_object('id','fixture-deployment','project_id','fixture-project','project_name','civicpulse-fixture','environment','production','stage','deploy','status','success','source_sha',repeat('c',40),'branch','main'),
 'markers','{"deployment":null,"production":null,"pages":null}'::jsonb,'artifact',jsonb_build_object('artifact_sha256',repeat('d',64),'served_inventory_sha256',repeat('e',64)), 'github_terminal',null,
 'requests',(select jsonb_agg(jsonb_build_object('endpoint_key',k,'page',1,'status',case when k like 'marker_%' then 404 else 200 end,'request_id',null)) from unnest(array['project_before','project_after','deployment','marker_deployment','marker_production','marker_pages','artifact_files']) k)); $$;
create function pg_temp.source() returns jsonb language sql immutable as $$
 with config as (select pg_temp.config()->'source' s), facts as (select s,jsonb_build_object('id','9007199254740993','run_attempt','1','workflow_id',s->>'workflow_id','path','.github/workflows/publish.yml@main','repository_id',s->>'repository_id','head_repository_id',s->>'repository_id','event','workflow_dispatch','head_branch','main','head_sha',repeat('f',40),'status','in_progress','conclusion',null,'actor_id','31','triggering_actor_id','32','referenced_workflows','[]'::jsonb) r from config)
 select jsonb_build_object('schema_version',1,'repository',jsonb_build_object('id',s->>'repository_id','owner_id',s->>'repository_owner_id','full_name',s->>'repository_full_name','fork',false,'archived',false,'default_branch','main'),'workflow',jsonb_build_object('id',s->>'workflow_id','path',s->>'workflow_path','state','active'),
 'run_before',r,'run_attempt',r,'run_after',r,'ref_before',jsonb_build_object('ref','refs/heads/main','object_type','commit','sha',repeat('f',40)),'ref_after',jsonb_build_object('ref','refs/heads/main','object_type','commit','sha',repeat('f',40)),
 'protection_before',s->'protection_bundle','protection_after',s->'protection_bundle','workflow_file',jsonb_build_object('path',s->>'workflow_path','source_sha',repeat('f',40),'sha256',s->>'workflow_file_sha256','bytes',123),
 'requests',(select jsonb_agg(jsonb_build_object('endpoint_key',k,'page',1,'status',200,'github_request_id',null)) from unnest(array['repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','classic_before','classic_after','rulesets_before','rulesets_after','effective_rules_before','effective_rules_after','workflow_file']) k)) from facts; $$;
-- No fixtures seed approvals/receipts/live state: all arise from actual RPC calls.
insert into m21_context values('empty',public.publication_manifest());
set session authorization anon;
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'review')$q$);
select pg_temp.denied('select * from civicpulse_delivery.observations');
reset session authorization;
set session authorization authenticated;
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'review')$q$);
reset session authorization;
set session authorization cp_m21_impostor;
set role cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'review')$q$);
reset role; reset session authorization;
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap((pg_temp.ctx('empty')->>'dataset_epoch')::uuid,0,pg_temp.ctx('empty'),'empty')$q$,'22023');
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config()||'{"extra":true}','review')$q$,'22023');
insert into m21_context values('config',civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'synthetic config review'));
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'duplicate')$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.set_pipeline_paused(false,'premature')$q$,'55000');
reset session authorization;
insert into auth.users values('00000000-0000-4000-8000-000000000061');
insert into civicpulse.members values('00000000-0000-4000-8000-000000000061','admin');
set session authorization authenticated;
set "request.jwt.claim.sub"='00000000-0000-4000-8000-000000000061';
select public.save_draft('organization','m21-org','{"id":"m21-org","name":"M21 fixture"}',0);
select public.publish('organization','m21-org',1);
reset session authorization;
set session authorization cp_m21_operator;
select civicpulse_delivery.reset_epoch((pg_temp.ctx('empty')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000062','reset for N0 control');
reset session authorization;
insert into m21_context values('prestate',public.publication_manifest());
-- Actual operator call must roll back all prior writes on late audit failure.
create function pg_temp.reject_audit() returns trigger language plpgsql as $$ begin raise exception 'injected audit failure' using errcode='23514'; end $$;
create trigger reject_audit before insert on civicpulse_delivery.maintenance_approvals for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,0,pg_temp.ctx('prestate'),'audit fault')$q$,'23514');
reset session authorization;
drop trigger reject_audit on civicpulse_delivery.maintenance_approvals;
select pg_temp.assert(public.publication_manifest()=pg_temp.ctx('prestate') and not exists(select 1 from civicpulse_delivery.outbox where action='bootstrap'),'audit failure rolls back state and outbox');
create trigger reject_outbox before insert on civicpulse_delivery.outbox for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,0,pg_temp.ctx('prestate'),'outbox fault')$q$,'23514');
reset session authorization;
drop trigger reject_outbox on civicpulse_delivery.outbox;
select pg_temp.assert(public.publication_manifest()=pg_temp.ctx('prestate') and not exists(select 1 from civicpulse_delivery.maintenance_approvals where action='bootstrap'),'outbox failure rolls back state and audit');
create function pg_temp.change_target() returns trigger language plpgsql as $$ begin
  if not old.bootstrap_complete and new.bootstrap_complete then update civicpulse_delivery.publication_state set generation=generation+1; end if; return new;
end $$;
create trigger change_target after update on civicpulse_delivery.publication_state for each row execute function pg_temp.change_target();
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,0,pg_temp.ctx('prestate'),'postmanifest fault')$q$,'40001');
reset session authorization;
drop trigger change_target on civicpulse_delivery.publication_state;
select pg_temp.assert(public.publication_manifest()=pg_temp.ctx('prestate') and not exists(select 1 from civicpulse_delivery.outbox where action='bootstrap'),'postmanifest failure rolls back all writes');
set session authorization cp_m21_operator;
insert into m21_context values('bootstrap',civicpulse_delivery.approve_bootstrap((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,0,pg_temp.ctx('prestate'),'approve exact target'));
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,0,pg_temp.ctx('prestate'),'duplicate')$q$,'40001');
reset session authorization;
select pg_temp.assert(public.publication_manifest()=pg_temp.ctx('prestate')||'{"generation":"1","bootstrap_complete":true}','prospective N+1 exact target');
select pg_temp.assert((select evidence->'target'=public.publication_manifest() and evidence->>'target_manifest_sha256'=encode(sha256(convert_to((evidence->'target')::text,'UTF8')),'hex') from civicpulse_delivery.maintenance_approvals where action='bootstrap'),'full target + internal encoding hash');
select pg_temp.assert((select count(*)=1 from civicpulse_delivery.outbox where action='bootstrap'),'one bootstrap event');
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'deploy',null)$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.open_provider_observation('outcome',null,null,null)$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'claim',null)$q$,'55000');
insert into m21_context values('baseline_challenge',civicpulse_delivery.open_provider_observation('baseline',null,null,'fixture-deployment'));
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,pg_temp.baseline()-'artifact')$q$,'22023');
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{markers,production}','{}'))$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{requests,3,status}','200'))$q$,'22023');
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{requests}',(pg_temp.baseline()->'requests')-5))$q$,'22023');
insert into m21_context values('baseline_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,pg_temp.baseline()));
select pg_temp.assert(civicpulse_delivery.record_provider_observation((pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid,pg_temp.baseline())=pg_temp.ctx('baseline_receipt'),'baseline exact replay no expiry renewal');
select pg_temp.denied($q$select civicpulse_delivery.approve_epoch_baseline((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'fixture-deployment',jsonb_build_object('observation_id',pg_temp.ctx('baseline_receipt')->>'observation_id'),'forbidden')$q$);
reset session authorization;
savepoint expired_baseline;
with t as materialized(select clock_timestamp() at) update civicpulse_delivery.observation_challenges set issued_at=t.at-interval '121 seconds',expires_at=t.at-interval '1 second' from t where challenge_id=(pg_temp.ctx('baseline_challenge')->>'challenge_id')::uuid;
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_epoch_baseline((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'fixture-deployment',jsonb_build_object('observation_id',pg_temp.ctx('baseline_receipt')->>'observation_id'),'expired baseline')$q$,'40001');
reset session authorization;
select pg_temp.assert((select consumed_at is null from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('baseline_receipt')->>'observation_id')::uuid) and (select approved_epoch is null from civicpulse_delivery.pipeline_state),'expired baseline cannot consume or approve');
rollback to expired_baseline;
-- Producer revocation between record and operator consumption cannot authorize.
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_reconciler';
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_epoch_baseline((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'fixture-deployment',jsonb_build_object('observation_id',pg_temp.ctx('baseline_receipt')->>'observation_id'),'revoked producer')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true where role_name='cp_m21_reconciler';
set session authorization cp_m21_operator;
insert into m21_context values('baseline',civicpulse_delivery.approve_epoch_baseline((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'fixture-deployment',jsonb_build_object('observation_id',pg_temp.ctx('baseline_receipt')->>'observation_id'),'reviewed retained recovery artifact'));
select pg_temp.denied($q$select civicpulse_delivery.approve_epoch_baseline((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'fixture-deployment',jsonb_build_object('observation_id',pg_temp.ctx('baseline_receipt')->>'observation_id'),'duplicate')$q$,'40001');
select civicpulse_delivery.set_pipeline_paused(false,'ready for source observation only');
reset session authorization;
select pg_temp.assert((select not live_inventory_complete and live_generation is null and live_deployment_id is null from civicpulse_delivery.pipeline_state),'baseline does not fabricate CMS live');
set session authorization cp_m21_reconciler;
insert into m21_context values('source_challenge',civicpulse_delivery.open_source_observation('9007199254740993:1',repeat('f',40),'claim',null));
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.source(),'{run_before,id}','"9007199254740992"'))$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.source(),'{workflow_file,bytes}','null'))$q$,'22023');
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source()-'ref_after')$q$,'22023');
insert into m21_context values('source_receipt',civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source()));
select pg_temp.assert(civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source())=pg_temp.ctx('source_receipt'),'source replay exact');
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.source(),'{requests,0,github_request_id}','"changed"'))$q$,'40001');
select pg_temp.denied('select * from civicpulse_delivery.observations');
reset session authorization;
savepoint config_change;
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'config rotation');
select civicpulse_delivery.enroll_delivery_config((pg_temp.ctx('config')->>'config_version')::uuid,pg_temp.config(),'rotate immutable version');
reset session authorization;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source())$q$,'40001');
reset session authorization;
select pg_temp.assert((select count(*)=2 from civicpulse_delivery.delivery_configs),'config rotation preserves old version');
select pg_temp.assert((select approved_epoch is null from civicpulse_delivery.pipeline_state),'rotation invalidates baseline');
rollback to config_change;
savepoint epoch_change;
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'epoch rotation');
select civicpulse_delivery.reset_epoch((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000066','new epoch');
reset session authorization;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source())$q$,'40001');
reset session authorization;
rollback to epoch_change;
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_reconciler';
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source())$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp() where role_name='cp_m21_reconciler';
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'claim',null)$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour',role_oid=0 where role_name='cp_m21_reconciler';
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'claim',null)$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set role_oid='cp_m21_reconciler'::regrole::oid where role_name='cp_m21_reconciler';
with t as materialized(select clock_timestamp() at) update civicpulse_delivery.observation_challenges set issued_at=t.at-interval '121 seconds',expires_at=t.at-interval '1 second' from t where challenge_id=(pg_temp.ctx('source_challenge')->>'challenge_id')::uuid;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_source_observation((pg_temp.ctx('source_challenge')->>'challenge_id')::uuid,pg_temp.source())$q$,'40001');
reset session authorization;
select pg_temp.assert((select count(*)=2 from civicpulse_delivery.observations),'rejections never add receipts');
select pg_temp.assert(to_regprocedure('civicpulse_delivery.claim_build(text,text)') is null,'no build authority');
-- Assert the complete new authority/helper catalog, not only selected wrappers.
select pg_temp.assert(not exists(
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='civicpulse_delivery' and p.proname=any(array[
    'exact_object','text_field','review_reference','lock_enrollment','assert_quiescent','validate_delivery_config',
    'enroll_delivery_config','approve_bootstrap','reset_epoch','check_challenge','source_ready','validate_request_audit',
    'validate_source_evidence','open_source_observation','record_source_observation','baseline_ready','validate_baseline_evidence',
    'open_provider_observation','record_provider_observation','approve_epoch_baseline','set_pipeline_paused'])
  and (p.proowner<>'postgres'::regrole::oid or not(p.proconfig @> array['search_path=""'])
    or p.prosecdef is distinct from (p.proname=any(array['enroll_delivery_config','approve_bootstrap','reset_epoch',
      'open_source_observation','record_source_observation','open_provider_observation','record_provider_observation',
      'approve_epoch_baseline','set_pipeline_paused']))
    or exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where a.grantee in (0,'anon'::regrole::oid,'authenticated'::regrole::oid)))
), 'complete M2.1 function owner/search_path/definer/client ACL boundary');
select pg_temp.assert(not exists(
  select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='civicpulse_delivery' and c.relname=any(array['delivery_configs','enrollment_state','epoch_history','maintenance_approvals','observation_challenges','observations'])
  and (not c.relrowsecurity or c.relowner<>'postgres'::regrole::oid
    or has_table_privilege('cp_m21_operator',c.oid,'INSERT,UPDATE,DELETE')
    or has_table_privilege('cp_m21_reconciler',c.oid,'INSERT,UPDATE,DELETE'))
), 'private tables have RLS and no machine direct mutation');
-- Each new entrypoint remains denied by actual runner identity even with an
-- accidental EXECUTE grant; internal helpers have no client/machine EXECUTE.
grant execute on function civicpulse_delivery.enroll_delivery_config(uuid,jsonb,text),civicpulse_delivery.open_source_observation(text,text,text,uuid) to cp_m21_runner;
set session authorization cp_m21_runner;
select pg_temp.denied($q$select civicpulse_delivery.enroll_delivery_config(null,pg_temp.config(),'runner')$q$);
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'claim',null)$q$);
select pg_temp.denied('update civicpulse_delivery.pipeline_state set live_inventory_complete=true');
reset session authorization;
select pg_temp.assert(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace,
  lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where n.nspname='civicpulse_delivery' and p.proname in ('exact_object','text_field','check_challenge','validate_source_evidence','validate_baseline_evidence','approve_bootstrap','enroll_delivery_config','record_source_observation','record_provider_observation') and a.grantee in (0,'anon'::regrole::oid,'authenticated'::regrole::oid)), 'no PUBLIC/anon/auth EXECUTE on new authority/helpers');
-- Maximum generation is checked before bigint addition, retaining exact state.
savepoint boundary_cases;
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'boundary fixtures');
select civicpulse_delivery.reset_epoch((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000063','boundary epoch');
reset session authorization;
update civicpulse_delivery.publication_state set generation=9223372036854775806;
insert into m21_context values('max_minus_one',public.publication_manifest());
set session authorization cp_m21_operator;
select pg_temp.assert(civicpulse_delivery.approve_bootstrap('00000000-0000-4000-8000-000000000063',9223372036854775806,pg_temp.ctx('max_minus_one'),'max positive')->>'generation'='9223372036854775807','max-1 valid target max');
reset session authorization;
rollback to boundary_cases;
savepoint exhausted_case;
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'exhaustion fixture');
select civicpulse_delivery.reset_epoch((pg_temp.ctx('prestate')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000064','exhaustion epoch');
reset session authorization;
update civicpulse_delivery.publication_state set generation=9223372036854775807;
insert into m21_context values('max',public.publication_manifest());
set session authorization cp_m21_operator;
select pg_temp.denied($q$select civicpulse_delivery.approve_bootstrap('00000000-0000-4000-8000-000000000064',9223372036854775807,pg_temp.ctx('max'),'exhausted')$q$,'55000');
reset session authorization;
select pg_temp.assert(public.publication_manifest()=pg_temp.ctx('max') and not exists(select 1 from civicpulse_delivery.outbox where dataset_epoch='00000000-0000-4000-8000-000000000064'),'exhaustion leaves no partial writes');
rollback to exhausted_case;
-- Actual dropped/recreated name cannot inherit the obsolete registered OID.
drop owned by cp_m21_reconciler;
drop role cp_m21_reconciler;
create role cp_m21_reconciler nologin;
grant usage on schema civicpulse_delivery to cp_m21_reconciler;
grant execute on function civicpulse_delivery.open_source_observation(text,text,text,uuid) to cp_m21_reconciler;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.open_source_observation('1:1',repeat('f',40),'claim',null)$q$);
reset session authorization;
rollback;
select 'Connected enrollment/bootstrap/baseline/source actual-role checks passed' as result;
