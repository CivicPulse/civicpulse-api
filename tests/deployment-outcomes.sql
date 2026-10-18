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
set session authorization cp_m21_reconciler;
insert into m21_context values('terminal_partial_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,null));
insert into m21_context values('terminal_partial_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('terminal_partial_challenge')->>'challenge_id')::uuid,pg_temp.ctx('partial')));
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))->'reclaimable'='false','partial reconciliation is not reclaimable');
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_partial_receipt'))->'reclaimable'='false','partial replay does not upgrade');
reset session authorization;
select pg_temp.assert((select consumed_at is null and eligibility='audit' from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('terminal_partial_receipt')->>'observation_id')::uuid),'partial never consumed');
savepoint live_candidate;
set session authorization cp_m21_reconciler;
insert into m21_context values('live_challenge',civicpulse_delivery.open_provider_observation('outcome',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('live_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('live_challenge')->>'challenge_id')::uuid,pg_temp.provider_success()));
insert into m21_context values('live_ack',pg_temp.finish_test('live',pg_temp.receipt('live_receipt')));
select pg_temp.assert(pg_temp.finish_test('live',pg_temp.receipt('live_receipt'))=pg_temp.ctx('live_ack'),'live finish replay');
reset session authorization;
select pg_temp.assert((select live_inventory_complete and live_inventory=pg_temp.ctx('claimed_manifest')->'records' and live_deployment_id='candidate' from civicpulse_delivery.pipeline_state),'live stores exact complete job inventory');
select pg_temp.assert((select external_authority and active_job_id is not null from civicpulse_delivery.enrollment_state),'live does not release uploader');
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.finish_test('unknown','{}','candidate')$q$,'40001');
reset session authorization;
set session authorization cp_m21_reconciler;
insert into m21_context values('terminal_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('begin')->>'attempt_id')::uuid,'candidate'));
insert into m21_context values('terminal_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('terminal_challenge')->>'challenge_id')::uuid,pg_temp.provider_success(true)));
insert into m21_context values('terminal_ack',pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt')));
select pg_temp.assert(pg_temp.ctx('terminal_ack')->'reclaimable'='true','completed uploader and unchanged provider release');
select pg_temp.assert(pg_temp.reconcile_test(pg_temp.receipt('terminal_receipt'))=pg_temp.ctx('terminal_ack'),'terminal acknowledgment replay');
reset session authorization;
select pg_temp.assert((select not external_authority and active_job_id is null from civicpulse_delivery.enrollment_state),'terminal releases only completed uploader');
select pg_temp.assert((select not intervention_required from civicpulse_delivery.build_counter),'successful release does not create failure');
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
