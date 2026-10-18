grant execute on function civicpulse_delivery.finish_deploy(uuid,bigint,text,text,jsonb) to cp_m21_runner,cp_m21_reconciler;
grant execute on function civicpulse_delivery.reconcile_job(uuid,bigint,jsonb) to cp_m21_reconciler;
create function pg_temp.finish_test(outcome text,doc jsonb,dep text default 'candidate') returns jsonb language sql as $$
 select civicpulse_delivery.finish_deploy((pg_temp.ctx('begin')->>'attempt_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,dep,outcome,doc);
$$;
create function pg_temp.reconcile_test(doc jsonb) returns jsonb language sql as $$
 select civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,doc);
$$;
create function pg_temp.receipt(key text) returns jsonb language sql as $$
 select jsonb_build_object('observation_id',pg_temp.ctx(key)->>'observation_id');
$$;
create function pg_temp.terminal() returns jsonb language sql as $$
 with fact as (select (pg_temp.source()->'run_before')-array['id','path','actor_id','triggering_actor_id','referenced_workflows']||jsonb_build_object('run_id','9007199254740993','raw_path','.github/workflows/publish.yml@main','status','completed','conclusion','success') r)
 select jsonb_build_object('run',r,'attempt',r) from fact;
$$;
create function pg_temp.provider_success(terminal boolean default false) returns jsonb language plpgsql as $$
declare d jsonb:=pg_temp.baseline(); marker jsonb; requests jsonb;
begin
 marker:=jsonb_build_object('schema_version',1,'job_id',pg_temp.ctx('claim')->>'job_id','dataset_epoch',pg_temp.ctx('claim')->>'dataset_epoch',
   'generation',pg_temp.ctx('claim')->>'target_generation','source_sha',repeat('f',40),'snapshot_sha256',repeat('a',64));
 select jsonb_agg(jsonb_set(value,'{status}','200')) into requests from jsonb_array_elements(d->'requests');
 if terminal then requests:=requests||jsonb_build_array(
   jsonb_build_object('endpoint_key','github_run_terminal','page',1,'status',200,'request_id',null),
   jsonb_build_object('endpoint_key','github_attempt_terminal','page',1,'status',200,'request_id',null)); end if;
 return d||jsonb_build_object('project',d->'project'||'{"canonical_deployment_id":"candidate"}',
  'deployment',d->'deployment'||jsonb_build_object('id','candidate','source_sha',repeat('f',40)),
  'markers',jsonb_build_object('deployment',marker,'production',marker,'pages',marker),
  'artifact',jsonb_build_object('artifact_sha256',repeat('b',64),'served_inventory_sha256',repeat('e',64)),
  'github_terminal',case when terminal then pg_temp.terminal() else 'null'::jsonb end,'requests',requests);
end $$;
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('partial_receipt'))$q$);
insert into m21_context values('unknown_ack',pg_temp.finish_test('unknown','{}',null));
select pg_temp.assert(pg_temp.finish_test('unknown','{}',null)=pg_temp.ctx('unknown_ack'),'unknown replay exact');
reset session authorization;
select pg_temp.assert((select state='deployment_unknown' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'unknown retains pending state');
select pg_temp.assert((select external_authority from civicpulse_delivery.enrollment_state),'unknown never unlocks');
savepoint unknown_lock;
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'synthetic unknown outcome hold');
select pg_temp.denied($q$select civicpulse_delivery.set_pipeline_paused(false,'cannot resume through unknown')$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.reset_epoch((pg_temp.ctx('claim')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000099','cannot reset unknown')$q$,'55000');
reset session authorization;
select pg_temp.assert((select external_authority and active_job_id is not null from civicpulse_delivery.enrollment_state),'expiry and operator pause cannot release unknown');
rollback to unknown_lock;

set session authorization cp_m21_reconciler;
insert into m21_context values('terminal_partial_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('terminal_partial_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('terminal_partial_challenge')->>'challenge_id')::uuid,pg_temp.ctx('partial')));
reset session authorization;
insert into m21_context values('partial_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))->'reclaimable'='false','partial reconciliation is not reclaimable');
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))->'reclaimable'='false','partial replay does not upgrade');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('partial_before'),'partial repeated reconcile changes no authority state');
select pg_temp.assert((select consumed_at is null and eligibility='audit' from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('terminal_partial_receipt')->>'observation_id')::uuid),'partial never consumed');
savepoint live_candidate;
set session authorization cp_m21_reconciler;
insert into m21_context values('live_challenge',civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('live_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('live_challenge')->>'challenge_id')::uuid,pg_temp.provider_success()));
reset session authorization;
savepoint finish_fault;
create trigger reject_finish_final before insert on civicpulse_delivery.deployment_acknowledgments for each row execute function pg_temp.reject_audit();
insert into m21_context values('finish_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))$q$,'23514');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('finish_before'),'late finish failure rolls back live receipt job and acknowledgment');
rollback to finish_fault;
-- Publication after authorized begin must remain desired, while the pinned
-- older generation may truthfully become live and report pending publication.
set session authorization authenticated;
select public.save_draft('organization','m21-org','{"id":"m21-org","name":"Changed after begin"}',1);
select public.publish('organization','m21-org',2);
reset session authorization;
set session authorization cp_m21_reconciler;
insert into m21_context values('live_ack',pg_temp.finish_test('live',pg_temp.receipt('live_receipt')));
select pg_temp.assert(pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))=pg_temp.ctx('live_ack'),'live finish replay');
reset session authorization;
select pg_temp.assert((select live_inventory_complete and live_inventory=pg_temp.ctx('claimed_manifest')->'records' and live_deployment_id='candidate' from civicpulse_delivery.pipeline_state),'live stores exact complete job inventory');
select pg_temp.assert((select s.generation>p.live_generation from civicpulse_delivery.publication_state s cross join civicpulse_delivery.pipeline_state p),'late desired generation preserved');
select pg_temp.assert((select external_authority and active_job_id is not null from civicpulse_delivery.enrollment_state),'live does not release uploader');
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.finish_test('unknown','{}','candidate')$q$,'40001');
reset session authorization;
set session authorization cp_m21_reconciler;
-- A fresh terminal receipt must still match bytes admitted by finish(live).
insert into m21_context values('changed_terminal_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('changed_terminal_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('changed_terminal_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{artifact,served_inventory_sha256}',to_jsonb(repeat('f',64)))));
reset session authorization;
insert into m21_context values('changed_terminal_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('changed_terminal_receipt'))$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('changed_terminal_before'),'changed admitted bytes cannot release or consume');
set session authorization cp_m21_reconciler;
insert into m21_context values('terminal_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('terminal_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('terminal_challenge')->>'challenge_id')::uuid,pg_temp.provider_success(true)));
reset session authorization;
savepoint reconcile_fault;
create trigger reject_reconcile_final before insert on civicpulse_delivery.deployment_acknowledgments for each row execute function pg_temp.reject_audit();
insert into m21_context values('reconcile_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))$q$,'23514');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('reconcile_before'),'late reconcile failure rolls back authority release receipt and acknowledgment');
rollback to reconcile_fault;
set session authorization cp_m21_reconciler;
insert into m21_context values('terminal_ack',pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt')));
select pg_temp.assert(pg_temp.ctx('terminal_ack')->'reclaimable'='true','completed uploader and unchanged provider release');
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))=pg_temp.ctx('terminal_ack'),'terminal acknowledgment replay');
reset session authorization;
select pg_temp.assert((select not external_authority and active_job_id is null from civicpulse_delivery.enrollment_state),'terminal releases only completed uploader');
select pg_temp.assert((select not intervention_required from civicpulse_delivery.build_counter),'successful release does not create failure');
-- A second real job uses the admitted CMS prior, not the initial local baseline.
savepoint cms_prior_cycle;
insert into m21_context values('previous_live_evidence',pg_temp.provider_success());
insert into m21_context values('previous_live_state',(select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
-- Backdate only the disposable debounce clock; receipts still come from APIs.
update civicpulse_delivery.outbox set occurred_at=occurred_at-interval '3 minutes';
set session authorization cp_m21_reconciler;
insert into m21_context values('next_source_challenge',civicpulse_delivery.open_source_observation('9007199254740993:2',repeat('f',40),'claim',null));
insert into m21_context values('next_source_receipt',civicpulse_delivery.record_source_observation((pg_temp.ctx('next_source_challenge')->>'challenge_id')::uuid,pg_temp.source_attempt('2')));
reset session authorization;
update m21_context set value=public.publication_manifest() where key='claimed_manifest';
set session authorization cp_m21_runner;
update m21_context set value=civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40)) where key='claim';
select pg_temp.reach_phase('ready');
reset session authorization;
set session authorization cp_m21_reconciler;
insert into m21_context values('next_deploy_source',civicpulse_delivery.open_source_observation('9007199254740993:2',repeat('f',40),'deploy',(pg_temp.ctx('claim')->>'job_id')::uuid));
select civicpulse_delivery.record_source_observation((pg_temp.ctx('next_deploy_source')->>'challenge_id')::uuid,pg_temp.source_attempt('2'));
insert into m21_context values('next_prior_challenge',civicpulse_delivery.open_provider_observation('predeploy',(pg_temp.ctx('claim')->>'job_id')::uuid,null,'candidate'));
insert into m21_context values('next_prior_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('next_prior_challenge')->>'challenge_id')::uuid,pg_temp.ctx('previous_live_evidence')));
reset session authorization;
set session authorization cp_m21_runner;
update m21_context set value=pg_temp.begin_test() where key='begin';
reset session authorization;
insert into m21_context values('next_failure',pg_temp.provider_success(true)||jsonb_build_object(
 'project',pg_temp.ctx('previous_live_evidence')->'project',
 'deployment',pg_temp.provider_success()->'deployment'||'{"id":"candidate-two","status":"failure"}',
 'markers',null,'artifact',null,
 'github_terminal',jsonb_set(jsonb_set(pg_temp.terminal(),'{run,run_attempt}','"2"'),'{attempt,run_attempt}','"2"'),
 'requests',(select jsonb_agg(value) from jsonb_array_elements(pg_temp.provider_success(true)->'requests') where value->>'endpoint_key' not like 'marker_%')));
set session authorization cp_m21_reconciler;
insert into m21_context values('next_failure_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate-two'));
insert into m21_context values('next_failure_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('next_failure_challenge')->>'challenge_id')::uuid,pg_temp.ctx('next_failure')));
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('next_failure_receipt'))->>'state'='failed','terminal failure reconciliation releases second job');
reset session authorization;
select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('previous_live_state') from civicpulse_delivery.pipeline_state p),'failure preserves every previously verified live field');
select pg_temp.assert((select intervention_required and next_attempt_at is null from civicpulse_delivery.build_counter),'second failure requires intervention');
rollback to cms_prior_cycle;

-- Saved replay remains read-only after receipt expiry, but not revocation.
savepoint saved_replay;
update civicpulse_delivery.observation_challenges set issued_at=issued_at-interval '10 minutes',expires_at=expires_at-interval '10 minutes';
insert into m21_context values('replay_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))=pg_temp.ctx('live_ack'),'saved live replay after expiry');
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))=pg_temp.ctx('terminal_ack'),'saved terminal replay after expiry');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('replay_before'),'saved replay never updates any authority or receipt');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_reconciler';
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))$q$);
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))$q$);
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('replay_before'),'revoked identity cannot replay');
rollback to saved_replay;
savepoint saved_expired_identity;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_reconciler';
insert into m21_context values('identity_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))$q$);
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))$q$);
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('identity_before'),'saved_expired_identity denies saved replay without mutations');
rollback to saved_expired_identity;

savepoint saved_recreated_identity;
drop owned by cp_m21_reconciler; drop role cp_m21_reconciler; create role cp_m21_reconciler nologin; grant usage on schema civicpulse_delivery to cp_m21_reconciler; grant execute on function civicpulse_delivery.finish_deploy(uuid,bigint,text,text,jsonb),civicpulse_delivery.reconcile_job(uuid,bigint,jsonb) to cp_m21_reconciler; grant select on m21_context to cp_m21_reconciler;
insert into m21_context values('identity_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))$q$);
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))$q$);
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('identity_before'),'saved_recreated_identity denies saved replay without mutations');
rollback to saved_recreated_identity;

rollback to live_candidate;
select 'Connected provider/begin/unknown/live/terminal checks passed' as result;

create function pg_temp.provider_failure() returns jsonb language plpgsql as $$
declare d jsonb:=pg_temp.provider_success(true); requests jsonb;
begin
 select jsonb_agg(value) into requests from jsonb_array_elements(d->'requests') where value->>'endpoint_key' not like 'marker_%';
 return d||jsonb_build_object('project',pg_temp.baseline()->'project','deployment',d->'deployment'||'{"status":"failure"}',
   'markers',null,'artifact',null,'requests',requests);
end $$;
savepoint failure_candidate;
set session authorization cp_m21_reconciler;
insert into m21_context values('failure_challenge',civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('failure_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('failure_challenge')->>'challenge_id')::uuid,pg_temp.provider_failure()));
insert into m21_context values('failure_ack',pg_temp.finish_test('failed',pg_temp.receipt('failure_receipt')));
select pg_temp.assert(pg_temp.finish_test('failed',pg_temp.receipt('failure_receipt'))=pg_temp.ctx('failure_ack'),'failure acknowledgment replay');
reset session authorization;
select pg_temp.assert((select intervention_required and last_error='deployment_failed' and next_attempt_at is null from civicpulse_delivery.build_counter),'provider failure requires intervention');
select pg_temp.assert((select not external_authority and active_job_id is null from civicpulse_delivery.enrollment_state),'terminal failure releases');
select pg_temp.assert((select not live_inventory_complete and live_deployment_id is null from civicpulse_delivery.pipeline_state),'failure preserves markerless prior without fabricated CMS live');
rollback to failure_candidate;

-- Unsupported stage/status and swapped canonical remain nonconsumable.
savepoint unsupported_candidate;
set session authorization cp_m21_reconciler;
do $$ declare doc jsonb; key text; challenge jsonb; receipt jsonb; begin
 foreach key in array array['build','initialize','clone_repo','queued'] loop
  challenge:=civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate');
  doc:=jsonb_set(pg_temp.provider_failure(),'{deployment,stage}',to_jsonb(key));
  receipt:=civicpulse_delivery.record_provider_observation((challenge->>'challenge_id')::uuid,doc);
  perform pg_temp.denied(format('select pg_temp.finish_test(''failed'',%L::jsonb)',jsonb_build_object('observation_id',receipt->>'observation_id')),'55000');
 end loop;
 foreach key in array array['active','idle','canceled','skipped','unknown'] loop
  challenge:=civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate');
  doc:=jsonb_set(pg_temp.provider_failure(),'{deployment,status}',to_jsonb(key));
  receipt:=civicpulse_delivery.record_provider_observation((challenge->>'challenge_id')::uuid,doc);
  perform pg_temp.denied(format('select pg_temp.finish_test(''failed'',%L::jsonb)',jsonb_build_object('observation_id',receipt->>'observation_id')),'55000');
 end loop;
end $$;
reset session authorization;
select pg_temp.assert((select external_authority from civicpulse_delivery.enrollment_state),'unsupported failure never releases');
select pg_temp.assert((select not intervention_required from civicpulse_delivery.build_counter),'unsupported failure never fabricates terminal state');
rollback to unsupported_candidate;

savepoint stale_partial;
update civicpulse_delivery.observation_challenges set issued_at=issued_at-interval '10 minutes',expires_at=expires_at-interval '10 minutes'
 where challenge_id=(pg_temp.ctx('terminal_partial_challenge')->>'challenge_id')::uuid;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))$q$,'40001');
reset session authorization;
rollback to stale_partial;

-- Even a valid live projection cannot admit malformed owner-corrupted stored inventory.
-- Corruption is a negative fixture, never a successful receipt/approval bypass.
savepoint malformed_inventory;
set session authorization cp_m21_reconciler;
insert into m21_context values('malformed_live_challenge',civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('malformed_live_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('malformed_live_challenge')->>'challenge_id')::uuid,pg_temp.provider_success()));
reset session authorization;
update civicpulse_delivery.build_jobs set publication_manifest=jsonb_set(publication_manifest,'{records}','[]') where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('malformed_live_receipt'))$q$,'40001');
reset session authorization;
select pg_temp.assert((select consumed_at is null from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('malformed_live_receipt')->>'observation_id')::uuid),'invalid inventory rejection leaves receipt unspent');
select pg_temp.assert((select not live_inventory_complete from civicpulse_delivery.pipeline_state),'invalid inventory cannot write live');
rollback to malformed_inventory;

savepoint terminal_active;
set session authorization cp_m21_reconciler;
insert into m21_context values('invalid_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
reset session authorization;
insert into m21_context values('invalid_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('invalid_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{github_terminal,attempt,status}','"in_progress"'))$q$,'22023');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('invalid_before'),'terminal_active rejects at actual receipt boundary without mutation');
rollback to terminal_active;
savepoint terminal_conclusion;
set session authorization cp_m21_reconciler;
insert into m21_context values('invalid_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
reset session authorization;
insert into m21_context values('invalid_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('invalid_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{github_terminal,attempt,conclusion}','"mystery"'))$q$,'22023');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('invalid_before'),'terminal_conclusion rejects at actual receipt boundary without mutation');
rollback to terminal_conclusion;
savepoint duplicate_decimal_page;
set session authorization cp_m21_reconciler;
insert into m21_context values('invalid_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
reset session authorization;
insert into m21_context values('invalid_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('invalid_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{requests}',(pg_temp.provider_success(true)->'requests')||jsonb_build_array(jsonb_set(pg_temp.provider_success(true)->'requests'->0,'{page}','1.0'))))$q$,'22023');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('invalid_before'),'duplicate_decimal_page rejects at actual receipt boundary without mutation');
rollback to duplicate_decimal_page;
savepoint unknown_request;
set session authorization cp_m21_reconciler;
insert into m21_context values('invalid_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
reset session authorization;
insert into m21_context values('invalid_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('invalid_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{requests,0,endpoint_key}','"caller_url"'))$q$,'22023');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('invalid_before'),'unknown_request rejects at actual receipt boundary without mutation');
rollback to unknown_request;
savepoint timeout_status_zero;
set session authorization cp_m21_reconciler;
insert into m21_context values('invalid_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
reset session authorization;
insert into m21_context values('invalid_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.record_provider_observation((pg_temp.ctx('invalid_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{requests,0,status}','0'))$q$,'22023');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('invalid_before'),'timeout_status_zero rejects at actual receipt boundary without mutation');
rollback to timeout_status_zero;
savepoint newer_attempt;
set session authorization cp_m21_reconciler;
insert into m21_context values('audit_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('audit_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('audit_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{github_terminal,run,run_attempt}','"2"')));
reset session authorization;
insert into m21_context values('audit_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('audit_receipt'))->'reclaimable'='false','newer_attempt never releases');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('audit_before'),'newer_attempt remains unconsumed');
rollback to newer_attempt;
savepoint outsider_canonical;
set session authorization cp_m21_reconciler;
insert into m21_context values('audit_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('audit_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('audit_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_success(true),'{project,canonical_deployment_id}','"outsider"')));
reset session authorization;
insert into m21_context values('audit_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('audit_receipt'))->'reclaimable'='false','outsider_canonical never releases');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('audit_before'),'outsider_canonical remains unconsumed');
rollback to outsider_canonical;
savepoint failure_swapped_prior;
set session authorization cp_m21_reconciler;
insert into m21_context values('audit_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('audit_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('audit_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_failure(),'{project,canonical_deployment_id}','"outsider"')));
reset session authorization;
insert into m21_context values('audit_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('audit_receipt'))->'reclaimable'='false','failure_swapped_prior never releases');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('audit_before'),'failure_swapped_prior remains unconsumed');
rollback to failure_swapped_prior;
savepoint failure_candidate_equals_prior;
set session authorization cp_m21_reconciler;
insert into m21_context values('audit_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('audit_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('audit_challenge')->>'challenge_id')::uuid,jsonb_set(pg_temp.provider_failure(),'{deployment,id}','"fixture-deployment"')));
reset session authorization;
insert into m21_context values('audit_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('audit_receipt'))->'reclaimable'='false','failure_candidate_equals_prior never releases');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('audit_before'),'failure_candidate_equals_prior remains unconsumed');
rollback to failure_candidate_equals_prior;

-- Catalog and direct-table boundaries for every added callable/table.
select pg_temp.assert(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='civicpulse_delivery' and p.proname in ('begin_deploy','finish_deploy','reconcile_job','provider_receipt','deployment_replay','provider_classification','provider_requests','check_terminal_facts','check_provider_context','require_source_job','current_prior_observation','expected_job_marker')
 and (p.proowner<>(select oid from pg_roles where rolname='postgres') or not ('search_path=""'=any(p.proconfig))
 or has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))),'private functions owner/path/client execute denial');
set session authorization cp_m21_runner;
select pg_temp.denied('select * from civicpulse_delivery.deployment_intents');
select pg_temp.denied('select * from civicpulse_delivery.deployment_acknowledgments');
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))$q$);
reset session authorization;
select 'Connected provider failure/partial/stale/inventory/grant checks passed' as result;

-- Wrong fence and cross-purpose references fail before any authority mutation.
insert into m21_context values('binding_before',pg_temp.authority_snapshot());
set session authorization cp_m21_reconciler;
select pg_temp.denied($q$select civicpulse_delivery.finish_deploy((pg_temp.ctx('begin')->>'attempt_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint+1,'candidate','live',pg_temp.receipt('partial_receipt'))$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.reconcile_job((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint+1,pg_temp.receipt('terminal_partial_receipt'))$q$,'40001');
select pg_temp.denied($q$select pg_temp.reconcile_test(pg_temp.receipt('partial_receipt'))$q$,'40001');
select pg_temp.denied($q$select pg_temp.finish_test('live',pg_temp.receipt('terminal_partial_receipt'))$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.authority_snapshot()=pg_temp.ctx('binding_before'),'wrong fence and purpose cannot mutate or consume');
