-- Actual-session, connected source/provider/begin controls; no provider calls.
savepoint deployment_controls;
grant execute on function civicpulse_delivery.begin_deploy(uuid,uuid,bigint,uuid,bigint,text,text,text) to cp_m21_runner;
create function pg_temp.begin_test() returns jsonb language sql as $$
 select civicpulse_delivery.begin_deploy((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'lease_id')::uuid,
   (pg_temp.ctx('claim')->>'fence')::bigint,(pg_temp.ctx('claim')->>'dataset_epoch')::uuid,
   (pg_temp.ctx('claim')->>'target_generation')::bigint,repeat('a',64),repeat('b',64),repeat('f',40));
$$;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('ready');
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
set session authorization cp_m21_reconciler;
insert into m21_context values('deploy_source_challenge',civicpulse_delivery.open_source_observation('9007199254740993:1',repeat('f',40),'deploy',(pg_temp.ctx('claim')->>'job_id')::uuid));
insert into m21_context values('deploy_source_receipt',civicpulse_delivery.record_source_observation((pg_temp.ctx('deploy_source_challenge')->>'challenge_id')::uuid,pg_temp.source()));
insert into m21_context values('predeploy_challenge',civicpulse_delivery.open_provider_observation('predeploy',(pg_temp.ctx('claim')->>'job_id')::uuid,null,'fixture-deployment'));
insert into m21_context values('predeploy_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('predeploy_challenge')->>'challenge_id')::uuid,pg_temp.baseline()));
select pg_temp.assert(civicpulse_delivery.record_provider_observation((pg_temp.ctx('predeploy_challenge')->>'challenge_id')::uuid,pg_temp.baseline())=pg_temp.ctx('predeploy_receipt'),'exact provider replay');
select pg_temp.denied('select pg_temp.begin_test()');
reset session authorization;
select pg_temp.assert((select eligibility='predeploy' and consumed_at is null from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('predeploy_receipt')->>'observation_id')::uuid),'actual markerless prior receipt eligible');
-- Real terminal observation cannot recover an unexpired lease; expiry alone
-- cannot recover it either. Only their conjunction is consumable.
savepoint prebegin_recovery;
grant execute on function civicpulse_delivery.reconcile_job(uuid,bigint,jsonb) to cp_m21_reconciler;
insert into m21_context values('prebegin_terminal',jsonb_build_object('schema_version',1,'project',pg_temp.baseline()->'project','deployment',null,'markers',null,'artifact',null,
 'github_terminal',(select jsonb_build_object('run',r,'attempt',r) from (select (pg_temp.source()->'run_before')-array['id','path','actor_id','triggering_actor_id','referenced_workflows']||jsonb_build_object('run_id','9007199254740993','raw_path','.github/workflows/publish.yml@main','status','completed','conclusion','success') r) x),
 'requests',(select jsonb_agg(jsonb_build_object('endpoint_key',k,'page',1,'status',200,'request_id',null)) from unnest(array['project_before','project_after','github_run_terminal','github_attempt_terminal']) k)));
set session authorization cp_m21_reconciler;
insert into m21_context values('prebegin_terminal_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,null,null));
insert into m21_context values('prebegin_terminal_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('prebegin_terminal_challenge')->>'challenge_id')::uuid,pg_temp.ctx('prebegin_terminal')));
select pg_temp.denied($q$select civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,jsonb_build_object('observation_id',pg_temp.ctx('prebegin_terminal_receipt')->>'observation_id'))$q$,'55000');
reset session authorization;
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
set session authorization cp_m21_reconciler;
insert into m21_context values('recovery_ack',civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,jsonb_build_object('observation_id',pg_temp.ctx('prebegin_terminal_receipt')->>'observation_id')));
select pg_temp.assert(pg_temp.ctx('recovery_ack')->>'state'='superseded' and pg_temp.ctx('recovery_ack')->'reclaimable'='true','terminal plus DB expiry recovers prebegin only');
select pg_temp.assert(civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,jsonb_build_object('observation_id',pg_temp.ctx('prebegin_terminal_receipt')->>'observation_id'))=pg_temp.ctx('recovery_ack'),'expiry recovery acknowledgment replay');
reset session authorization;
select pg_temp.assert((select recovery_reason='lease_expired' from civicpulse_delivery.deployment_acknowledgments where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'private reason retained');
select pg_temp.assert(not exists(select 1 from civicpulse_delivery.deployment_intents),'expiry recovery never begins upload');
rollback to prebegin_recovery;
set session authorization cp_m21_runner;
insert into m21_context values('begin',pg_temp.begin_test());
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
select pg_temp.assert((select external_authority from civicpulse_delivery.enrollment_state),'begin retains external authority');
select pg_temp.assert((select state='deploying' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'begin changes job state');
select pg_temp.assert((select count(*)=2 from civicpulse_delivery.observations where consumed_for=(pg_temp.ctx('begin')->>'attempt_id')::uuid),'both fresh receipts consumed once');
select pg_temp.assert((select prior_production=pg_temp.baseline() and prior_deployment_id='fixture-deployment' from civicpulse_delivery.deployment_intents),'immutable full prior bytes retained');
select pg_temp.denied('update civicpulse_delivery.deployment_intents set prior_deployment_id=''other''','55000');
set session authorization cp_m21_reconciler;
insert into m21_context values('partial_challenge',civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('partial',jsonb_build_object('schema_version',1,'project',pg_temp.baseline()->'project','deployment',null,'markers',null,'artifact',null,'github_terminal',null,'requests',jsonb_build_array(
  jsonb_build_object('endpoint_key','project_before','page',1,'status',200,'request_id',null),
  jsonb_build_object('endpoint_key','project_after','page',1,'status',200,'request_id',null))));
insert into m21_context values('partial_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('partial_challenge')->>'challenge_id')::uuid,pg_temp.ctx('partial')));
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('partial_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.ctx('partial'),'{deployment}','{}'))$q$,'40001');
reset session authorization;
select pg_temp.assert((select eligibility='audit' and consumed_at is null from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('partial_receipt')->>'observation_id')::uuid),'partial remains immutable audit only');
-- FINISH_RECONCILE_SCENARIO
rollback to deployment_controls;
