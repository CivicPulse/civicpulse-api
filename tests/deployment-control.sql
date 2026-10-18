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
create function pg_temp.authority_snapshot() returns jsonb language sql as $$
 select jsonb_build_object(
 'jobs',(select jsonb_agg(to_jsonb(x) order by job_id) from civicpulse_delivery.build_jobs x),
 'counter',(select to_jsonb(x) from civicpulse_delivery.build_counter x),
 'enrollment',(select to_jsonb(x) from civicpulse_delivery.enrollment_state x),
 'live',(select to_jsonb(x) from civicpulse_delivery.pipeline_state x),
 'desired',(select to_jsonb(x) from civicpulse_delivery.publication_state x),
 'receipts',(select jsonb_agg(to_jsonb(x) order by observation_id) from civicpulse_delivery.observations x),
 'challenges',(select jsonb_agg(to_jsonb(x) order by challenge_id) from civicpulse_delivery.observation_challenges x),
 'intents',(select jsonb_agg(to_jsonb(x) order by attempt_id) from civicpulse_delivery.deployment_intents x),
 'acks',(select jsonb_agg(to_jsonb(x) order by job_id,operation) from civicpulse_delivery.deployment_acknowledgments x));
$$;
-- Test-only late failure: intent and both receipt writes must roll back.
savepoint begin_fault;
create trigger reject_begin_final before update on civicpulse_delivery.enrollment_state for each row execute function pg_temp.reject_audit();
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','23514');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'late begin failure rolls back intent receipts job and lock');
rollback to begin_fault;
savepoint runner_disabled;
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','42501');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'runner_disabled leaves all authority unchanged');
rollback to runner_disabled;
savepoint runner_expired;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','42501');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'runner_expired leaves all authority unchanged');
rollback to runner_expired;
savepoint producer_disabled;
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_reconciler';
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','42501');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'producer_disabled leaves all authority unchanged');
rollback to producer_disabled;
savepoint producer_expired;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_reconciler';
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','42501');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'producer_expired leaves all authority unchanged');
rollback to producer_expired;
savepoint expired_begin;
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second';
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'expired_begin leaves all authority unchanged');
rollback to expired_begin;
savepoint stale_source;
update civicpulse_delivery.observation_challenges set issued_at=issued_at-interval '10 minutes',expires_at=expires_at-interval '10 minutes' where challenge_id=(pg_temp.ctx('deploy_source_challenge')->>'challenge_id')::uuid;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'stale_source leaves all authority unchanged');
rollback to stale_source;
savepoint stale_provider;
update civicpulse_delivery.observation_challenges set issued_at=issued_at-interval '10 minutes',expires_at=expires_at-interval '10 minutes' where challenge_id=(pg_temp.ctx('predeploy_challenge')->>'challenge_id')::uuid;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'stale_provider leaves all authority unchanged');
rollback to stale_provider;
savepoint runner_recreated;
drop owned by cp_m21_runner; drop role cp_m21_runner; create role cp_m21_runner nologin; grant usage on schema civicpulse_delivery to cp_m21_runner; grant execute on function civicpulse_delivery.begin_deploy(uuid,uuid,bigint,uuid,bigint,text,text,text) to cp_m21_runner; grant select,insert on m21_context to cp_m21_runner;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','42501');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'runner_recreated leaves all authority unchanged');
rollback to runner_recreated;
savepoint before_begin_drift;
set session authorization authenticated;
select public.save_draft('organization','m21-org','{"id":"m21-org","name":"Changed before begin"}',1);
select public.publish('organization','m21-org',2);
reset session authorization;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'desired drift before begin cannot consume receipts');
rollback to before_begin_drift;
savepoint prior_bytes;
set session authorization cp_m21_reconciler;
insert into m21_context values('changed_prior_challenge',civicpulse_delivery.open_provider_observation('predeploy',(pg_temp.ctx('claim')->>'job_id')::uuid,null,'fixture-deployment'));
insert into m21_context values('changed_prior_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('changed_prior_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{artifact,artifact_sha256}',to_jsonb('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'::text))));
reset session authorization;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','55000');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'prior_bytes cannot replace pinned prior or consume receipt');
rollback to prior_bytes;
savepoint prior_canonical;
set session authorization cp_m21_reconciler;
insert into m21_context values('changed_prior_challenge',civicpulse_delivery.open_provider_observation('predeploy',(pg_temp.ctx('claim')->>'job_id')::uuid,null,'fixture-deployment'));
insert into m21_context values('changed_prior_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('changed_prior_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{project,canonical_deployment_id}',to_jsonb('outsider'::text))));
reset session authorization;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','55000');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'prior_canonical cannot replace pinned prior or consume receipt');
rollback to prior_canonical;
savepoint prior_source;
set session authorization cp_m21_reconciler;
insert into m21_context values('changed_prior_challenge',civicpulse_delivery.open_provider_observation('predeploy',(pg_temp.ctx('claim')->>'job_id')::uuid,null,'fixture-deployment'));
insert into m21_context values('changed_prior_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('changed_prior_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.baseline(),'{deployment,source_sha}',to_jsonb('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'::text))));
reset session authorization;
insert into m21_context values('atomic_before',pg_temp.authority_snapshot());
set session authorization cp_m21_runner;
select pg_temp.denied('select pg_temp.begin_test()','55000');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('atomic_before'),'prior_source cannot replace pinned prior or consume receipt');
rollback to prior_source;

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
-- Existing intervention is a negative state fixture, not an approval.
update civicpulse_delivery.build_counter set intervention_required=true,last_error='build_failed',last_error_occurred_at='2026-01-01T00:00:00Z';
set session authorization cp_m21_reconciler;
insert into m21_context values('recovery_ack',civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,jsonb_build_object('observation_id',pg_temp.ctx('prebegin_terminal_receipt')->>'observation_id')));
select pg_temp.assert(pg_temp.ctx('recovery_ack')->>'state'='superseded' and pg_temp.ctx('recovery_ack')->'reclaimable'='true','terminal plus DB expiry recovers prebegin only');
select pg_temp.assert(civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,jsonb_build_object('observation_id',pg_temp.ctx('prebegin_terminal_receipt')->>'observation_id'))=pg_temp.ctx('recovery_ack'),'expiry recovery acknowledgment replay');
reset session authorization;
select pg_temp.assert((select recovery_reason='lease_expired' from civicpulse_delivery.deployment_acknowledgments where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'private reason retained');
select pg_temp.assert(not exists(select 1 from civicpulse_delivery.deployment_intents),'expiry recovery never begins upload');
select pg_temp.assert((select intervention_required and last_error='build_failed' and last_error_occurred_at='2026-01-01T00:00:00Z' from civicpulse_delivery.build_counter),'expiry recovery never clears existing intervention');
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
