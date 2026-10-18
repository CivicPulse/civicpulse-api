-- Nested in the actual receipt-backed runner claim scenario; each case rolls back.
grant execute on function civicpulse_delivery.transition_build(uuid,uuid,bigint,text,text,jsonb) to cp_m21_runner;
insert into m21_context values('claimed_manifest',public.publication_manifest());
create function pg_temp.phase(previous text,next text,evidence jsonb) returns jsonb language sql security invoker as $$
  select civicpulse_delivery.transition_build((pg_temp.ctx('claim')->>'job_id')::uuid,(pg_temp.ctx('claim')->>'lease_id')::uuid,(pg_temp.ctx('claim')->>'fence')::bigint,previous,next,evidence);
$$;
create function pg_temp.reach_phase(target text) returns void language plpgsql security invoker as $$ begin
  if target='queued' then return; end if;
  perform pg_temp.phase('queued','exporting','{}');
  if target='exporting' then return; end if;
  perform pg_temp.phase('exporting','building',jsonb_build_object('publication_manifest',pg_temp.ctx('claimed_manifest'),'snapshot_sha256',repeat('a',64)));
  if target='building' then return; end if;
  perform pg_temp.phase('building','validating',jsonb_build_object('artifact_sha256',repeat('b',64)));
  if target='validating' then return; end if;
  perform pg_temp.phase('validating','ready','{}');
end $$;
create function pg_temp.source_attempt(attempt text,sha text default repeat('f',40)) returns jsonb language plpgsql immutable as $$
declare doc jsonb:=pg_temp.source(); key text;
begin
  foreach key in array array['run_before','run_attempt','run_after'] loop
    doc:=jsonb_set(doc,array[key,'run_attempt'],to_jsonb(attempt));
    doc:=jsonb_set(doc,array[key,'head_sha'],to_jsonb(sha));
  end loop;
  doc:=jsonb_set(doc,'{ref_before,sha}',to_jsonb(sha));
  doc:=jsonb_set(doc,'{ref_after,sha}',to_jsonb(sha));
  doc:=jsonb_set(doc,'{workflow_file,source_sha}',to_jsonb(sha));
  return doc;
end $$;
-- Fresh source receipt is created through the actual reconciler API, before failures.
set session authorization cp_m21_reconciler;
insert into m21_context values('second_source_challenge',civicpulse_delivery.open_source_observation('9007199254740993:2',repeat('f',40),'claim',null));
insert into m21_context values('second_source_receipt',civicpulse_delivery.record_source_observation((pg_temp.ctx('second_source_challenge')->>'challenge_id')::uuid,pg_temp.source_attempt('2')));
reset session authorization;

-- Both-null/both-present and the closed code allowlist are database constraints.
select pg_temp.denied($q$update civicpulse_delivery.build_counter set last_error='export_failed'$q$,'23514');
select pg_temp.denied($q$update civicpulse_delivery.build_counter set last_error_occurred_at=clock_timestamp()$q$,'23514');
select pg_temp.denied($q$update civicpulse_delivery.build_counter set last_error='invented',last_error_occurred_at=clock_timestamp()$q$,'23514');

-- Security regression: a caller reason and a fresh SAME-SHA second-attempt
-- receipt cannot turn a failed candidate into a nonintervention replacement.
savepoint supersession_lies;
insert into m21_context values('supersession_before',jsonb_build_object(
  'jobs',(select jsonb_agg(to_jsonb(j) order by fence) from civicpulse_delivery.build_jobs j),
  'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),
  'enrollment',(select to_jsonb(e) from civicpulse_delivery.enrollment_state e),
  'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o),
  'acks',(select jsonb_agg(to_jsonb(a) order by job_id,sequence) from civicpulse_delivery.build_transitions a)));
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('supersession_before')=jsonb_build_object(
  'jobs',(select jsonb_agg(to_jsonb(j) order by fence) from civicpulse_delivery.build_jobs j),
  'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),
  'enrollment',(select to_jsonb(e) from civicpulse_delivery.enrollment_state e),
  'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o),
  'acks',(select jsonb_agg(to_jsonb(a) order by job_id,sequence) from civicpulse_delivery.build_transitions a)),
  'all false supersession reasons and same-SHA replacement leave every authority field unchanged');
rollback to supersession_lies;

savepoint rewound_generation;
update civicpulse_delivery.publication_state set generation=0;
insert into m21_context values('rewind_before',jsonb_build_object(
  'jobs',(select jsonb_agg(to_jsonb(j) order by fence) from civicpulse_delivery.build_jobs j),
  'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),
  'enrollment',(select to_jsonb(e) from civicpulse_delivery.enrollment_state e),
  'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o),
  'acks',(select jsonb_agg(to_jsonb(a) order by job_id,sequence) from civicpulse_delivery.build_transitions a)));
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('rewind_before')=jsonb_build_object(
  'jobs',(select jsonb_agg(to_jsonb(j) order by fence) from civicpulse_delivery.build_jobs j),
  'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),
  'enrollment',(select to_jsonb(e) from civicpulse_delivery.enrollment_state e),
  'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o),
  'acks',(select jsonb_agg(to_jsonb(a) order by job_id,sequence) from civicpulse_delivery.build_transitions a)),
  'rewind denial preserves complete job/enrollment/receipt/fence/intervention/ack snapshots');
select pg_temp.assert((select state='queued' and transition_sequence=0 from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid)
  and (select active_job_id=(pg_temp.ctx('claim')->>'job_id')::uuid from civicpulse_delivery.enrollment_state)
  and (select not intervention_required and fence=1 from civicpulse_delivery.build_counter)
  and (select consumed_at is null from civicpulse_delivery.observations where observation_id=(pg_temp.ctx('second_source_receipt')->>'observation_id')::uuid),
  'generation rewind cannot release ownership, consume replacement receipt or mutate fence/intervention');
rollback to rewound_generation;

-- Simulate an external restore's epoch change only in this disposable owner
-- fixture. The normal operator reset correctly refuses an active job.
savepoint restored_epoch;
update civicpulse_delivery.publication_state set dataset_epoch='00000000-0000-4000-8000-000000000089';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.assert(pg_temp.phase('queued','superseded','{"reason":"epoch_changed"}')='{"state":"superseded"}'::jsonb,'actual different epoch permits epoch supersession');
select pg_temp.assert(pg_temp.phase('queued','superseded','{"reason":"epoch_changed"}')='{"state":"superseded"}'::jsonb,'exact supersession acknowledgment replays');
reset session authorization;
rollback to restored_epoch;

savepoint failure_queued;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('queued');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"build_failed"}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed","raw":"forbidden"}')$q$,'22023');
reset session authorization;
create trigger reject_transition before insert on civicpulse_delivery.build_transitions for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed"}')$q$,'23514');
reset session authorization;
drop trigger reject_transition on civicpulse_delivery.build_transitions;
select pg_temp.assert((select state='queued' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid) and (select not intervention_required from civicpulse_delivery.build_counter),'failure write rollback retains stage and gate');
insert into m21_context values('live_before', (select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
set session authorization cp_m21_runner;
select pg_temp.phase('queued','failed','{"error_code":"export_failed"}');
select pg_temp.assert(pg_temp.phase('queued','failed','{"error_code":"export_failed"}')='{"state":"failed"}'::jsonb,'exact terminal acknowledgment replay');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null and last_error='export_failed' from civicpulse_delivery.build_counter),'coarse failure latches intervention');
insert into m21_context values('expected_error',(select jsonb_build_object('code',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter));
select pg_temp.assert((select c.last_error_occurred_at=a.acknowledged_at from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id) where j.job_id=(pg_temp.ctx('claim')->>'job_id')::uuid and a.sequence=j.transition_sequence),'counter time bound to inserted failure transition');
set session authorization authenticated;
select pg_temp.assert_error_status(pg_temp.ctx('expected_error')->>'code',(pg_temp.ctx('expected_error')->>'at')::timestamptz);
reset session authorization;

select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('live_before') from civicpulse_delivery.pipeline_state p),'failure preserves prior pipeline/live fields');
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
insert into m21_context values('terminal_snapshot',jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)));
set session authorization cp_m21_runner;
select pg_temp.assert(pg_temp.phase('queued','failed','{"error_code":"export_failed"}')='{"state":"failed"}'::jsonb,'expired terminal acknowledgment exact replay');
select pg_temp.denied($q$select pg_temp.phase('queued','superseded','{"reason":"source_changed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('terminal_snapshot')=jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)),'replay changes no lease/fence/receipt/evidence');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_m21_runner';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'intervention persists');
select civicpulse_delivery.set_pipeline_paused(false,'resume is not clearance');
reset session authorization;
select pg_temp.assert((select intervention_required from civicpulse_delivery.build_counter),'pause/resume cannot clear intervention');
rollback to failure_queued;

savepoint failure_exporting;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('exporting');
select pg_temp.denied($q$select pg_temp.phase('exporting','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('exporting','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('exporting','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('exporting','failed','{"error_code":"build_failed"}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('exporting','failed','{"error_code":"export_failed","raw":"forbidden"}')$q$,'22023');
reset session authorization;
create trigger reject_transition before insert on civicpulse_delivery.build_transitions for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('exporting','failed','{"error_code":"export_failed"}')$q$,'23514');
reset session authorization;
drop trigger reject_transition on civicpulse_delivery.build_transitions;
select pg_temp.assert((select state='exporting' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid) and (select not intervention_required from civicpulse_delivery.build_counter),'failure write rollback retains stage and gate');
insert into m21_context values('live_before', (select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
set session authorization cp_m21_runner;
select pg_temp.phase('exporting','failed','{"error_code":"export_failed"}');
select pg_temp.assert(pg_temp.phase('exporting','failed','{"error_code":"export_failed"}')='{"state":"failed"}'::jsonb,'exact terminal acknowledgment replay');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null and last_error='export_failed' from civicpulse_delivery.build_counter),'coarse failure latches intervention');
insert into m21_context values('expected_error',(select jsonb_build_object('code',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter));
select pg_temp.assert((select c.last_error_occurred_at=a.acknowledged_at from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id) where j.job_id=(pg_temp.ctx('claim')->>'job_id')::uuid and a.sequence=j.transition_sequence),'counter time bound to inserted failure transition');
set session authorization authenticated;
select pg_temp.assert_error_status(pg_temp.ctx('expected_error')->>'code',(pg_temp.ctx('expected_error')->>'at')::timestamptz);
reset session authorization;

select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('live_before') from civicpulse_delivery.pipeline_state p),'failure preserves prior pipeline/live fields');
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
insert into m21_context values('terminal_snapshot',jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)));
set session authorization cp_m21_runner;
select pg_temp.assert(pg_temp.phase('exporting','failed','{"error_code":"export_failed"}')='{"state":"failed"}'::jsonb,'expired terminal acknowledgment exact replay');
select pg_temp.denied($q$select pg_temp.phase('exporting','superseded','{"reason":"source_changed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('terminal_snapshot')=jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)),'replay changes no lease/fence/receipt/evidence');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('exporting','failed','{"error_code":"export_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('exporting','failed','{"error_code":"export_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_m21_runner';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'intervention persists');
select civicpulse_delivery.set_pipeline_paused(false,'resume is not clearance');
reset session authorization;
select pg_temp.assert((select intervention_required from civicpulse_delivery.build_counter),'pause/resume cannot clear intervention');
rollback to failure_exporting;

savepoint failure_building;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('building');
select pg_temp.denied($q$select pg_temp.phase('building','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('building','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('building','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('building','failed','{"error_code":"validation_failed"}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('building','failed','{"error_code":"build_failed","raw":"forbidden"}')$q$,'22023');
reset session authorization;
create trigger reject_transition before insert on civicpulse_delivery.build_transitions for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('building','failed','{"error_code":"build_failed"}')$q$,'23514');
reset session authorization;
drop trigger reject_transition on civicpulse_delivery.build_transitions;
select pg_temp.assert((select state='building' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid) and (select not intervention_required from civicpulse_delivery.build_counter),'failure write rollback retains stage and gate');
insert into m21_context values('live_before', (select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
set session authorization cp_m21_runner;
select pg_temp.phase('building','failed','{"error_code":"build_failed"}');
select pg_temp.assert(pg_temp.phase('building','failed','{"error_code":"build_failed"}')='{"state":"failed"}'::jsonb,'exact terminal acknowledgment replay');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null and last_error='build_failed' from civicpulse_delivery.build_counter),'coarse failure latches intervention');
insert into m21_context values('expected_error',(select jsonb_build_object('code',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter));
select pg_temp.assert((select c.last_error_occurred_at=a.acknowledged_at from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id) where j.job_id=(pg_temp.ctx('claim')->>'job_id')::uuid and a.sequence=j.transition_sequence),'counter time bound to inserted failure transition');
set session authorization authenticated;
select pg_temp.assert_error_status(pg_temp.ctx('expected_error')->>'code',(pg_temp.ctx('expected_error')->>'at')::timestamptz);
reset session authorization;

select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('live_before') from civicpulse_delivery.pipeline_state p),'failure preserves prior pipeline/live fields');
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
insert into m21_context values('terminal_snapshot',jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)));
set session authorization cp_m21_runner;
select pg_temp.assert(pg_temp.phase('building','failed','{"error_code":"build_failed"}')='{"state":"failed"}'::jsonb,'expired terminal acknowledgment exact replay');
select pg_temp.denied($q$select pg_temp.phase('building','superseded','{"reason":"source_changed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('terminal_snapshot')=jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)),'replay changes no lease/fence/receipt/evidence');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('building','failed','{"error_code":"build_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('building','failed','{"error_code":"build_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_m21_runner';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'intervention persists');
select civicpulse_delivery.set_pipeline_paused(false,'resume is not clearance');
reset session authorization;
select pg_temp.assert((select intervention_required from civicpulse_delivery.build_counter),'pause/resume cannot clear intervention');
rollback to failure_building;

savepoint failure_validating;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('validating');
select pg_temp.denied($q$select pg_temp.phase('validating','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('validating','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('validating','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('validating','failed','{"error_code":"build_failed"}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('validating','failed','{"error_code":"validation_failed","raw":"forbidden"}')$q$,'22023');
reset session authorization;
create trigger reject_transition before insert on civicpulse_delivery.build_transitions for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('validating','failed','{"error_code":"validation_failed"}')$q$,'23514');
reset session authorization;
drop trigger reject_transition on civicpulse_delivery.build_transitions;
select pg_temp.assert((select state='validating' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid) and (select not intervention_required from civicpulse_delivery.build_counter),'failure write rollback retains stage and gate');
insert into m21_context values('live_before', (select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
set session authorization cp_m21_runner;
select pg_temp.phase('validating','failed','{"error_code":"validation_failed"}');
select pg_temp.assert(pg_temp.phase('validating','failed','{"error_code":"validation_failed"}')='{"state":"failed"}'::jsonb,'exact terminal acknowledgment replay');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null and last_error='validation_failed' from civicpulse_delivery.build_counter),'coarse failure latches intervention');
insert into m21_context values('expected_error',(select jsonb_build_object('code',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter));
select pg_temp.assert((select c.last_error_occurred_at=a.acknowledged_at from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id) where j.job_id=(pg_temp.ctx('claim')->>'job_id')::uuid and a.sequence=j.transition_sequence),'counter time bound to inserted failure transition');
set session authorization authenticated;
select pg_temp.assert_error_status(pg_temp.ctx('expected_error')->>'code',(pg_temp.ctx('expected_error')->>'at')::timestamptz);
reset session authorization;

select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('live_before') from civicpulse_delivery.pipeline_state p),'failure preserves prior pipeline/live fields');
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
insert into m21_context values('terminal_snapshot',jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)));
set session authorization cp_m21_runner;
select pg_temp.assert(pg_temp.phase('validating','failed','{"error_code":"validation_failed"}')='{"state":"failed"}'::jsonb,'expired terminal acknowledgment exact replay');
select pg_temp.denied($q$select pg_temp.phase('validating','superseded','{"reason":"source_changed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('terminal_snapshot')=jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)),'replay changes no lease/fence/receipt/evidence');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('validating','failed','{"error_code":"validation_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('validating','failed','{"error_code":"validation_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_m21_runner';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'intervention persists');
select civicpulse_delivery.set_pipeline_paused(false,'resume is not clearance');
reset session authorization;
select pg_temp.assert((select intervention_required from civicpulse_delivery.build_counter),'pause/resume cannot clear intervention');
rollback to failure_validating;

savepoint failure_ready;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('ready');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"epoch_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"build_failed"}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"validation_failed","raw":"forbidden"}')$q$,'22023');
reset session authorization;
create trigger reject_transition before insert on civicpulse_delivery.build_transitions for each row execute function pg_temp.reject_audit();
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')$q$,'23514');
reset session authorization;
drop trigger reject_transition on civicpulse_delivery.build_transitions;
select pg_temp.assert((select state='ready' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid) and (select not intervention_required from civicpulse_delivery.build_counter),'failure write rollback retains stage and gate');
insert into m21_context values('live_before', (select to_jsonb(p) from civicpulse_delivery.pipeline_state p));
set session authorization cp_m21_runner;
select pg_temp.phase('ready','failed','{"error_code":"validation_failed"}');
select pg_temp.assert(pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')='{"state":"failed"}'::jsonb,'exact terminal acknowledgment replay');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null and last_error='validation_failed' from civicpulse_delivery.build_counter),'coarse failure latches intervention');
insert into m21_context values('expected_error',(select jsonb_build_object('code',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter));
select pg_temp.assert((select c.last_error_occurred_at=a.acknowledged_at from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a join civicpulse_delivery.build_jobs j using(job_id) where j.job_id=(pg_temp.ctx('claim')->>'job_id')::uuid and a.sequence=j.transition_sequence),'counter time bound to inserted failure transition');
set session authorization authenticated;
select pg_temp.assert_error_status(pg_temp.ctx('expected_error')->>'code',(pg_temp.ctx('expected_error')->>'at')::timestamptz);
reset session authorization;

select pg_temp.assert((select to_jsonb(p)=pg_temp.ctx('live_before') from civicpulse_delivery.pipeline_state p),'failure preserves prior pipeline/live fields');
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second' where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid;
insert into m21_context values('terminal_snapshot',jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)));
set session authorization cp_m21_runner;
select pg_temp.assert(pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')='{"state":"failed"}'::jsonb,'expired terminal acknowledgment exact replay');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"source_changed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert(pg_temp.ctx('terminal_snapshot')=jsonb_build_object('jobs',(select jsonb_agg(to_jsonb(j)) from civicpulse_delivery.build_jobs j),'counter',(select to_jsonb(c) from civicpulse_delivery.build_counter c),'receipts',(select jsonb_agg(to_jsonb(o) order by observation_id) from civicpulse_delivery.observations o)),'replay changes no lease/fence/receipt/evidence');
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')$q$);
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_m21_runner';
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'intervention persists');
select civicpulse_delivery.set_pipeline_paused(false,'resume is not clearance');
reset session authorization;
select pg_temp.assert((select intervention_required from civicpulse_delivery.build_counter),'pause/resume cannot clear intervention');
rollback to failure_ready;


savepoint durable_intervention;
set session authorization cp_m21_runner;
select pg_temp.phase('queued','failed','{"error_code":"export_failed"}');
reset session authorization;
savepoint new_runner_identity;
drop owned by cp_m21_runner;
drop role cp_m21_runner;
create role cp_m21_runner nologin;
grant usage on schema civicpulse_delivery to cp_m21_runner;
grant select on m21_context to cp_m21_runner;
grant execute on function civicpulse_delivery.claim_build(text,text),civicpulse_delivery.transition_build(uuid,uuid,bigint,text,text,jsonb) to cp_m21_runner;
update civicpulse_delivery.machine_registry set role_oid='cp_m21_runner'::regrole::oid where role_name='cp_m21_runner';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed"}')$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:2',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
rollback to new_runner_identity;
set session authorization cp_m21_operator;
select civicpulse_delivery.set_pipeline_paused(true,'review cannot implicitly clear');
select civicpulse_delivery.enroll_delivery_config((pg_temp.ctx('config')->>'config_version')::uuid,pg_temp.config(),'new config is not recovery');
select civicpulse_delivery.reset_epoch((pg_temp.ctx('claim')->>'dataset_epoch')::uuid,'00000000-0000-4000-8000-000000000088','new epoch is not recovery');
reset session authorization;
select pg_temp.assert((select intervention_required and next_attempt_at is null from civicpulse_delivery.build_counter),'config and epoch rotation preserve intervention');
select pg_temp.assert((select count(*)=1 and min(run_id)='9007199254740993:1' and min(repository_id)='9007199254740993' from civicpulse_delivery.build_jobs),'spent repository/run attempt reservation retained across epoch/config');
set session authorization cp_m21_runner;
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
reset session authorization;
rollback to durable_intervention;

savepoint supersession_case;
set session authorization cp_m21_reconciler;
insert into m21_context values('third_source_challenge',civicpulse_delivery.open_source_observation('9007199254740993:3',repeat('e',40),'claim',null));
select civicpulse_delivery.record_source_observation((pg_temp.ctx('third_source_challenge')->>'challenge_id')::uuid,pg_temp.source_attempt('3',repeat('e',40)));
reset session authorization;
set session authorization authenticated;
select public.save_draft('organization','m21-org','{"id":"m21-org","name":"New desired for replacement"}',1);
select public.publish('organization','m21-org',2);
reset session authorization;
set session authorization cp_m21_runner;
select pg_temp.phase('queued','superseded','{"reason":"content_changed"}');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40))$q$,'55000');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:1',repeat('e',40))$q$,'40001');
select pg_temp.denied($q$select civicpulse_delivery.claim_build('9007199254740993:3',repeat('e',40))$q$,'55000');
reset session authorization;
-- Move only disposable event time to exercise the quiet window without sleeps.
update civicpulse_delivery.outbox set occurred_at=clock_timestamp()-interval '31 seconds' where dataset_epoch=(pg_temp.ctx('claim')->>'dataset_epoch')::uuid and action='publish';
set session authorization cp_m21_runner;
insert into m21_context values('second_claim',civicpulse_delivery.claim_build('9007199254740993:3',repeat('e',40)));
reset session authorization;
select pg_temp.assert((pg_temp.ctx('second_claim')->>'fence')::bigint>(pg_temp.ctx('claim')->>'fence')::bigint and pg_temp.ctx('second_claim')->>'job_id'<>pg_temp.ctx('claim')->>'job_id','supersession permits new run identity and fence');
select pg_temp.assert((select state='superseded' from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'old job remains immutable terminal');
select pg_temp.assert((select source_sha=repeat('e',40) and target_generation=2 from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('second_claim')->>'job_id')::uuid),'replacement pins new desired and independently observed source');
rollback to supersession_case;

savepoint invalid_progress;
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','live','{}')$q$,'22023');
select pg_temp.denied($q$select pg_temp.phase('queued','ready','{}')$q$,'22023');
select pg_temp.phase('queued','exporting','{}');
select pg_temp.denied($q$select pg_temp.phase('exporting','building',jsonb_build_object('publication_manifest',jsonb_set(pg_temp.ctx('claimed_manifest'),'{generation}','"2"'),'snapshot_sha256',repeat('a',64)))$q$,'22023');
select pg_temp.phase('exporting','building',jsonb_build_object('publication_manifest',pg_temp.ctx('claimed_manifest'),'snapshot_sha256',repeat('a',64)));
select pg_temp.denied($q$select pg_temp.phase('exporting','building',jsonb_build_object('publication_manifest',pg_temp.ctx('claimed_manifest'),'snapshot_sha256',repeat('c',64)))$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('queued','exporting','{}')$q$,'40001');
reset session authorization;
select pg_temp.assert((select snapshot_sha256=repeat('a',64) and publication_manifest=pg_temp.ctx('claimed_manifest') from civicpulse_delivery.build_jobs where job_id=(pg_temp.ctx('claim')->>'job_id')::uuid),'earlier evidence cannot be replaced');
rollback to invalid_progress;

-- DEPLOYMENT_SCENARIO

savepoint ready_status;
set session authorization cp_m21_runner;
select pg_temp.reach_phase('ready');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"source_changed"}')$q$,'55000');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"content_changed"}')$q$,'40001');
select pg_temp.denied($q$select pg_temp.phase('ready','superseded','{"reason":"epoch_changed"}')$q$,'40001');
reset session authorization;
set session authorization authenticated;
select pg_temp.assert(public.cms_publication_status()->>'state'='ready' and public.cms_publication_status()->'active_job'->>'job_id'=pg_temp.ctx('claim')->>'job_id','staff sees actual ready job');
select pg_temp.assert((select count(*)=3 from jsonb_object_keys(public.cms_publication_status()->'active_job')),'staff job projection contains only three approved fields');
select pg_temp.denied($q$select pg_temp.phase('ready','failed','{"error_code":"validation_failed"}')$q$);
reset session authorization;
rollback to ready_status;

savepoint expired_transition;
update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second';
set session authorization cp_m21_runner;
select pg_temp.denied($q$select pg_temp.phase('queued','failed','{"error_code":"export_failed"}')$q$,'40001');
reset session authorization;
select pg_temp.assert((select not intervention_required from civicpulse_delivery.build_counter),'expired first acknowledgment cannot latch failure');
rollback to expired_transition;
select pg_temp.assert(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='civicpulse_delivery' and p.proname in ('claim_build','heartbeat_build','transition_build')
  and (not p.prosecdef or p.proowner<>'postgres'::regrole::oid or not(p.proconfig @> array['search_path=""'])
    or exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee in (0,'anon'::regrole::oid,'authenticated'::regrole::oid)))),'claim/heartbeat/transition catalog boundaries');
select pg_temp.assert(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='civicpulse_delivery' and c.relname in ('build_counter','build_jobs','build_transitions')
  and (not c.relrowsecurity or has_table_privilege('cp_m21_runner',c.oid,'INSERT,UPDATE,DELETE'))),'build RLS/direct-write boundary');
select 'Connected phase/failure/intervention/terminal replay checks passed' as result;
