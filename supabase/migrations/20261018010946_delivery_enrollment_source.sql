-- LOCAL M2.1. No provisioned logins, grants to machines, jobs, upload or live writer.
create table civicpulse_delivery.delivery_configs (
  config_version uuid primary key default gen_random_uuid(), config jsonb not null,
  approved_at timestamptz not null default clock_timestamp(), actor name not null,
  actor_oid oid not null, review_reference text not null
);
create table civicpulse_delivery.enrollment_state (
  singleton boolean primary key default true check(singleton),
  config_version uuid references civicpulse_delivery.delivery_configs,
  baseline_observation_id uuid, baseline_epoch uuid,
  -- Future job gates must share these locks; no M2.1 function grants authority.
  active_job_id uuid, external_authority boolean not null default false
);
insert into civicpulse_delivery.enrollment_state(singleton) values(true);
create table civicpulse_delivery.epoch_history (
  dataset_epoch uuid primary key, created_at timestamptz not null default clock_timestamp()
);
insert into civicpulse_delivery.epoch_history(dataset_epoch) select dataset_epoch from civicpulse_delivery.publication_state;
create table civicpulse_delivery.maintenance_approvals (
  approval_id uuid primary key default gen_random_uuid(), action text not null,
  actor name not null, actor_oid oid not null, approved_at timestamptz not null default clock_timestamp(),
  review_reference text not null, evidence jsonb not null
);
create table civicpulse_delivery.observation_challenges (
  challenge_id uuid primary key default gen_random_uuid(), family text not null check(family in ('source','provider')),
  config_version uuid not null references civicpulse_delivery.delivery_configs,
  dataset_epoch uuid not null, actor name not null, actor_oid oid not null,
  issued_at timestamptz not null, expires_at timestamptz not null,
  purpose text not null, run_id text, source_sha text, job_id uuid, attempt_id uuid, deployment_id text,
  check(expires_at=issued_at+interval '120 seconds')
);
create table civicpulse_delivery.observations (
  observation_id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null unique references civicpulse_delivery.observation_challenges,
  evidence jsonb not null, evidence_sha256 text not null,
  evidence_encoding text not null default 'pg-jsonb-text-v1' check(evidence_encoding='pg-jsonb-text-v1'),
  received_at timestamptz not null, consumed_at timestamptz, consumed_for uuid
);
alter table civicpulse_delivery.enrollment_state add foreign key(baseline_observation_id) references civicpulse_delivery.observations;
do $$ declare t text; begin
  foreach t in array array['delivery_configs','enrollment_state','epoch_history','maintenance_approvals','observation_challenges','observations'] loop
    execute format('alter table civicpulse_delivery.%I enable row level security',t);
    execute format('revoke all on civicpulse_delivery.%I from public,anon,authenticated',t);
  end loop;
end $$;

create function civicpulse_delivery.exact_object(doc jsonb,keys text[]) returns void
language plpgsql immutable security invoker set search_path='' as $$ begin
  if doc is null or jsonb_typeof(doc)<>'object' then raise exception 'Invalid object' using errcode='22023'; end if;
  if not(doc ?& keys) or (select count(*) from jsonb_object_keys(doc))<>cardinality(keys) then
    raise exception 'Invalid object keys' using errcode='22023'; end if;
end $$;
create function civicpulse_delivery.text_field(doc jsonb,key text,pattern text) returns text
language plpgsql immutable security invoker set search_path='' as $$ begin
  if jsonb_typeof(doc->key) is distinct from 'string' or (doc->>key) collate "C" !~ pattern then
    raise exception 'Invalid text field' using errcode='22023'; end if;
  return doc->>key;
end $$;
create function civicpulse_delivery.review_reference(value text) returns void
language plpgsql immutable security invoker set search_path='' as $$ begin
  if value is null or length(value)>512 or value collate "C" !~ '^[ -~]+$' then raise exception 'Invalid review reference' using errcode='22023'; end if;
end $$;
create function civicpulse_delivery.lock_enrollment(capability text) returns void
language plpgsql security invoker set search_path='' as $$ begin
  perform civicpulse_delivery.require_machine(capability);
  perform pg_advisory_xact_lock(728361904);
  perform 1 from civicpulse_delivery.pipeline_state where singleton for update;
  perform 1 from civicpulse_delivery.enrollment_state where singleton for update;
  -- Prevent concurrent registry mutation while authority is recorded/consumed.
  perform 1 from civicpulse_delivery.machine_registry where role_name=session_user for share;
  perform civicpulse_delivery.require_machine(capability);
end $$;
create function civicpulse_delivery.assert_quiescent() returns void
language plpgsql security invoker set search_path='' as $$ begin
  if exists(select 1 from civicpulse_delivery.enrollment_state where active_job_id is not null or external_authority) then
    raise exception 'Outstanding authority' using errcode='55000'; end if;
end $$;
create function civicpulse_delivery.validate_delivery_config(doc jsonb) returns void
language plpgsql immutable security invoker set search_path='' as $$
declare s jsonb; p jsonb; o jsonb; item jsonb; previous text; name text; key text; path text;
begin
  perform civicpulse_delivery.exact_object(doc,array['schema_version','source','provider','operation']);
  if doc->'schema_version' is distinct from '1'::jsonb then raise exception 'Invalid config schema' using errcode='22023'; end if;
  s:=doc->'source'; p:=doc->'provider'; o:=doc->'operation';
  perform civicpulse_delivery.exact_object(s,array['repository_id','repository_owner_id','repository_full_name','workflow_id','workflow_path','workflow_file_sha256','ref','allowed_events','api_version','policy_format_version','protection_bundle','checkout_contract_version','run_path_form']);
  foreach key in array array['repository_id','repository_owner_id','workflow_id'] loop perform civicpulse_delivery.text_field(s,key,'^[1-9][0-9]{0,19}$'); end loop;
  name:=civicpulse_delivery.text_field(s,'repository_full_name','^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$');
  if name ~ '\.git$' then raise exception 'Invalid repository name' using errcode='22023'; end if;
  path:=civicpulse_delivery.text_field(s,'workflow_path','^\.github/workflows/[A-Za-z0-9][A-Za-z0-9_-]*\.ya?ml$');
  perform civicpulse_delivery.text_field(s,'workflow_file_sha256','^[0-9a-f]{64}$');
  perform civicpulse_delivery.text_field(s,'run_path_form','^(bare|relative-main|repository-main)$');
  if octet_length(path)+(case s->>'run_path_form' when 'bare' then 0 when 'relative-main' then 5 else octet_length(name)+6 end)>65534 then raise exception 'Oversized workflow path' using errcode='22023'; end if;
  if s->'ref' is distinct from '"refs/heads/main"'::jsonb or s->'api_version' is distinct from '"2026-03-10"'::jsonb or s->'policy_format_version' is distinct from '1'::jsonb or s->'checkout_contract_version' is distinct from '1'::jsonb then raise exception 'Unsupported source policy' using errcode='22023'; end if;
  if jsonb_typeof(s->'allowed_events')<>'array' or jsonb_array_length(s->'allowed_events')=0 then raise exception 'Invalid events' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(s->'allowed_events') loop
    if item not in ('"push"'::jsonb,'"schedule"'::jsonb,'"workflow_dispatch"'::jsonb) or (previous is not null and (item#>>'{}') collate "C"<=previous collate "C") then raise exception 'Invalid events' using errcode='22023'; end if;
    previous:=item#>>'{}';
  end loop;
  perform civicpulse_delivery.exact_object(s->'protection_bundle',array['classic','rulesets','effective_rules']);
  if jsonb_typeof(s->'protection_bundle'->'classic')<>'object' or jsonb_typeof(s->'protection_bundle'->'rulesets')<>'array' or jsonb_typeof(s->'protection_bundle'->'effective_rules')<>'array' then raise exception 'Incomplete protection bundle' using errcode='22023'; end if;
  perform civicpulse_delivery.exact_object(p,array['account_id','project_id','project_name','production_origin','pages_origin']);
  perform civicpulse_delivery.text_field(p,'account_id','^[0-9a-f]{32}$');
  perform civicpulse_delivery.text_field(p,'project_id','^[A-Za-z0-9_-]{1,128}$');
  name:=civicpulse_delivery.text_field(p,'project_name','^[a-z0-9]([a-z0-9-]{0,56}[a-z0-9])?$');
  if p->'production_origin' is distinct from '"https://www.civpulse.org"'::jsonb or p->>'pages_origin' is distinct from 'https://'||name||'.pages.dev' then raise exception 'Invalid provider origins' using errcode='22023'; end if;
  perform civicpulse_delivery.exact_object(o,array['mode','environment_name','environment_evidence_sha256','operator_user_id','required_check_context','required_check_app_id']);
  if o->'mode' is distinct from '"solo-supervised-v1"'::jsonb or o->'environment_name' is distinct from '"production"'::jsonb or o->'required_check_context' is distinct from '"civicpulse-validate"'::jsonb then raise exception 'Unsupported operation policy' using errcode='22023'; end if;
  perform civicpulse_delivery.text_field(o,'environment_evidence_sha256','^[0-9a-f]{64}$');
  perform civicpulse_delivery.text_field(o,'operator_user_id','^[1-9][0-9]{0,19}$');
  perform civicpulse_delivery.text_field(o,'required_check_app_id','^[1-9][0-9]{0,19}$');
end $$;

create function civicpulse_delivery.enroll_delivery_config(p_expected_config_version uuid,p_config jsonb,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare version uuid; at timestamptz;
begin
  perform civicpulse_delivery.require_machine('publication_operator');
  perform civicpulse_delivery.review_reference(p_review_reference);
  perform civicpulse_delivery.validate_delivery_config(p_config);
  perform civicpulse_delivery.lock_enrollment('publication_operator');
  if (select config_version from civicpulse_delivery.enrollment_state) is distinct from p_expected_config_version then raise exception 'Configuration changed' using errcode='40001'; end if;
  if not(select paused from civicpulse_delivery.pipeline_state) then raise exception 'Pause required' using errcode='55000'; end if;
  perform civicpulse_delivery.assert_quiescent();
  insert into civicpulse_delivery.delivery_configs(config,actor,actor_oid,review_reference)
    values(p_config,session_user,(select oid from pg_roles where rolname=session_user),p_review_reference) returning config_version,approved_at into version,at;
  update civicpulse_delivery.enrollment_state set config_version=version,baseline_observation_id=null,baseline_epoch=null;
  update civicpulse_delivery.pipeline_state set approved_epoch=null;
  return jsonb_build_object('config_version',version,'approved_at',at);
end $$;

create function civicpulse_delivery.approve_bootstrap(p_expected_epoch uuid,p_expected_generation bigint,p_expected_manifest jsonb,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare before jsonb; target jsonb; next_generation bigint; event uuid;
begin
  perform civicpulse_delivery.require_machine('publication_operator');
  perform civicpulse_delivery.review_reference(p_review_reference);
  if p_expected_epoch is null or p_expected_generation is null or p_expected_generation<0 or p_expected_manifest->'bootstrap_complete' is distinct from 'false'::jsonb then raise exception 'Invalid bootstrap prestate' using errcode='22023'; end if;
  -- Validate input structure at its supplied N; final approval validates T at N+1.
  perform civicpulse_delivery.validate_receipt_manifest(p_expected_manifest||'{"bootstrap_complete":true}',p_expected_epoch,p_expected_generation);
  perform civicpulse_delivery.lock_enrollment('publication_operator');
  before:=public.publication_manifest();
  if before is distinct from p_expected_manifest then raise exception 'Bootstrap prestate changed' using errcode='40001'; end if;
  if not(select paused from civicpulse_delivery.pipeline_state) then raise exception 'Pause required' using errcode='55000'; end if;
  perform civicpulse_delivery.assert_quiescent();
  if p_expected_generation=9223372036854775807 then raise exception 'Generation exhausted' using errcode='55000'; end if;
  next_generation:=p_expected_generation+1;
  target:=before||jsonb_build_object('generation',next_generation::text,'bootstrap_complete',true);
  perform civicpulse_delivery.validate_receipt_manifest(target,p_expected_epoch,next_generation);
  update civicpulse_delivery.publication_state set generation=next_generation,bootstrap_complete=true;
  insert into civicpulse_delivery.outbox(dataset_epoch,generation,action) values(p_expected_epoch,next_generation,'bootstrap') returning event_id into event;
  insert into civicpulse_delivery.maintenance_approvals(action,actor,actor_oid,review_reference,evidence)
    values('bootstrap',session_user,(select oid from pg_roles where rolname=session_user),p_review_reference,
      jsonb_build_object('prestate',before,'target',target,'event_id',event,'target_manifest_sha256',encode(sha256(convert_to(target::text,'UTF8')),'hex'),'manifest_encoding','pg-jsonb-text-v1'));
  if public.publication_manifest() is distinct from target then raise exception 'Bootstrap target changed' using errcode='40001'; end if;
  return jsonb_build_object('dataset_epoch',p_expected_epoch,'generation',next_generation::text,'event_id',event,'bootstrap_complete',true);
end $$;

create function civicpulse_delivery.reset_epoch(p_expected_epoch uuid,p_new_epoch uuid,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$ begin
  perform civicpulse_delivery.require_machine('publication_operator');
  perform civicpulse_delivery.review_reference(p_review_reference);
  if p_expected_epoch is null or p_new_epoch is null or p_expected_epoch=p_new_epoch then raise exception 'Invalid epoch' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('publication_operator');
  if (select dataset_epoch from civicpulse_delivery.publication_state)<>p_expected_epoch or exists(select 1 from civicpulse_delivery.epoch_history where dataset_epoch=p_new_epoch) then raise exception 'Epoch changed or reused' using errcode='40001'; end if;
  if not(select paused from civicpulse_delivery.pipeline_state) then raise exception 'Pause required' using errcode='55000'; end if;
  perform civicpulse_delivery.assert_quiescent();
  insert into civicpulse_delivery.epoch_history(dataset_epoch) values(p_new_epoch);
  update civicpulse_delivery.publication_state set dataset_epoch=p_new_epoch,generation=0,bootstrap_complete=false;
  update civicpulse_delivery.pipeline_state set approved_epoch=null;
  update civicpulse_delivery.enrollment_state set baseline_observation_id=null,baseline_epoch=null;
  insert into civicpulse_delivery.maintenance_approvals(action,actor,actor_oid,review_reference,evidence) values('reset_epoch',session_user,(select oid from pg_roles where rolname=session_user),p_review_reference,jsonb_build_object('previous_epoch',p_expected_epoch,'dataset_epoch',p_new_epoch));
  return jsonb_build_object('dataset_epoch',p_new_epoch,'generation','0','bootstrap_complete',false);
end $$;

create function civicpulse_delivery.check_challenge(c civicpulse_delivery.observation_challenges) returns void
language plpgsql security invoker set search_path='' as $$ begin
  if c.challenge_id is null or c.config_version is distinct from (select config_version from civicpulse_delivery.enrollment_state)
    or c.dataset_epoch is distinct from (select dataset_epoch from civicpulse_delivery.publication_state)
    or clock_timestamp()>=c.expires_at then raise exception 'Observation context expired or changed' using errcode='40001'; end if;
  perform 1 from civicpulse_delivery.machine_registry where role_name=c.actor for share;
  if not exists(select 1 from civicpulse_delivery.machine_registry r join pg_roles p on p.oid=r.role_oid and p.rolname=r.role_name
    where r.role_name=c.actor and r.role_oid=c.actor_oid and r.capability='reconciler' and r.enabled and r.expires_at>clock_timestamp()) then
    raise exception 'Observation producer no longer authorized' using errcode='42501'; end if;
end $$;
create function civicpulse_delivery.source_ready() returns void
language plpgsql security invoker set search_path='' as $$ begin
  if not exists(select 1 from civicpulse_delivery.publication_state s cross join civicpulse_delivery.pipeline_state p cross join civicpulse_delivery.enrollment_state e
    where s.bootstrap_complete and not p.paused and p.approved_epoch=s.dataset_epoch and e.baseline_epoch=s.dataset_epoch and e.config_version is not null and e.baseline_observation_id is not null and not e.external_authority) then
    raise exception 'Source pipeline not approved' using errcode='55000'; end if;
end $$;
create function civicpulse_delivery.validate_request_audit(items jsonb,required_keys text[],marker_absence boolean default false) returns void
language plpgsql immutable security invoker set search_path='' as $$
declare item jsonb; k text; seen text[]:='{}'; n numeric;
begin
  if items is null or jsonb_typeof(items)<>'array' then raise exception 'Invalid request audit' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(items) loop
    -- Provider and source use differently named request-ID fields, fixed by family.
    perform civicpulse_delivery.exact_object(item,array['endpoint_key','page','status',case when marker_absence then 'request_id' else 'github_request_id' end]);
    k:=item->>'endpoint_key';
    if jsonb_typeof(item->'endpoint_key')<>'string' or not(k=any(required_keys)) or jsonb_typeof(item->'page')<>'number' or jsonb_typeof(item->'status')<>'number' then raise exception 'Invalid request audit' using errcode='22023'; end if;
    n:=(item->>'page')::numeric;
    if n<1 or n>9007199254740991 or trunc(n)<>n or item->'status'<>to_jsonb(case when marker_absence and k like 'marker_%' then 404 else 200 end) then raise exception 'Invalid request outcome' using errcode='22023'; end if;
    if item->(case when marker_absence then 'request_id' else 'github_request_id' end)<>'null'::jsonb then
      perform civicpulse_delivery.text_field(item,case when marker_absence then 'request_id' else 'github_request_id' end,'^[ -~]+$');
      if length(item->>(case when marker_absence then 'request_id' else 'github_request_id' end))>256 then raise exception 'Request ID too long' using errcode='22023'; end if;
    end if;
    seen:=array_append(seen,k);
  end loop;
  if not(seen @> required_keys) then raise exception 'Incomplete request audit' using errcode='22023'; end if;
end $$;
create function civicpulse_delivery.validate_source_evidence(doc jsonb,config jsonb,run text,sha text) returns void
language plpgsql immutable security invoker set search_path='' as $$
declare s jsonb:=config->'source'; r jsonb; key text; field text; path text;
begin
  perform civicpulse_delivery.exact_object(doc,array['schema_version','repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','protection_before','protection_after','workflow_file','requests']);
  if doc->'schema_version' is distinct from '1'::jsonb then raise exception 'Invalid source evidence schema' using errcode='22023'; end if;
  perform civicpulse_delivery.exact_object(doc->'repository',array['id','owner_id','full_name','fork','archived','default_branch']);
  foreach field in array array['id','owner_id'] loop perform civicpulse_delivery.text_field(doc->'repository',field,'^[1-9][0-9]{0,19}$'); end loop;
  perform civicpulse_delivery.text_field(doc->'repository','full_name','^[ -~]+$');
  perform civicpulse_delivery.text_field(doc->'repository','default_branch','^[ -~]+$');
  if jsonb_typeof(doc->'repository'->'fork')<>'boolean' or jsonb_typeof(doc->'repository'->'archived')<>'boolean' then raise exception 'Invalid repository flags' using errcode='22023'; end if;
  if doc->'repository' is distinct from jsonb_build_object('id',s->>'repository_id','owner_id',s->>'repository_owner_id','full_name',s->>'repository_full_name','fork',false,'archived',false,'default_branch','main') then raise exception 'Repository mismatch' using errcode='40001'; end if;
  perform civicpulse_delivery.exact_object(doc->'workflow',array['id','path','state']);
  perform civicpulse_delivery.text_field(doc->'workflow','id','^[1-9][0-9]{0,19}$');
  perform civicpulse_delivery.text_field(doc->'workflow','path','^[ -~]+$');
  perform civicpulse_delivery.text_field(doc->'workflow','state','^[a-z_]+$');
  if doc->'workflow' is distinct from jsonb_build_object('id',s->>'workflow_id','path',s->>'workflow_path','state','active') then raise exception 'Workflow mismatch' using errcode='40001'; end if;
  path:=case s->>'run_path_form' when 'bare' then s->>'workflow_path' when 'relative-main' then (s->>'workflow_path')||'@main' else (s->>'repository_full_name')||'/'||(s->>'workflow_path')||'@main' end;
  foreach key in array array['run_before','run_attempt','run_after'] loop
    r:=doc->key;
    perform civicpulse_delivery.exact_object(r,array['id','run_attempt','workflow_id','path','repository_id','head_repository_id','event','head_branch','head_sha','status','conclusion','actor_id','triggering_actor_id','referenced_workflows']);
    foreach field in array array['workflow_id','repository_id','head_repository_id'] loop perform civicpulse_delivery.text_field(r,field,'^[1-9][0-9]{0,19}$'); end loop;
    foreach field in array array['path','head_branch','event','status'] loop perform civicpulse_delivery.text_field(r,field,'^[ -~]+$'); end loop;
    perform civicpulse_delivery.text_field(r,'head_sha','^[0-9a-f]{40}$');
    if octet_length(r->>'path')>65534 or jsonb_typeof(r->'referenced_workflows')<>'array' then raise exception 'Invalid run facts' using errcode='22023'; end if;
    perform civicpulse_delivery.text_field(r,'id','^[1-9][0-9]{0,19}$');
    perform civicpulse_delivery.text_field(r,'run_attempt','^[1-9][0-9]{0,9}$');
    perform civicpulse_delivery.text_field(r,'actor_id','^[1-9][0-9]{0,19}$');
    perform civicpulse_delivery.text_field(r,'triggering_actor_id','^[1-9][0-9]{0,19}$');
    if r->'workflow_id' is distinct from s->'workflow_id' or r->'repository_id' is distinct from s->'repository_id' or r->'head_repository_id' is distinct from s->'repository_id'
      or (r->>'id')||':'||(r->>'run_attempt')<>run or r->'path' is distinct from to_jsonb(path)
      or r->'head_sha' is distinct from to_jsonb(sha) or r->'head_branch' is distinct from '"main"'::jsonb
      or r->'status' is distinct from '"in_progress"'::jsonb or r->'conclusion' is distinct from 'null'::jsonb
      or r->'referenced_workflows' is distinct from '[]'::jsonb or not(s->'allowed_events' @> jsonb_build_array(r->'event')) then raise exception 'Run mismatch' using errcode='40001'; end if;
  end loop;
  if doc->'run_before' is distinct from doc->'run_attempt' or doc->'run_before' is distinct from doc->'run_after' then raise exception 'Run changed' using errcode='40001'; end if;
  foreach key in array array['ref_before','ref_after'] loop
    perform civicpulse_delivery.exact_object(doc->key,array['ref','object_type','sha']);
    if doc->key is distinct from jsonb_build_object('ref','refs/heads/main','object_type','commit','sha',sha) then raise exception 'Main changed' using errcode='40001'; end if;
  end loop;
  if doc->'protection_before' is distinct from s->'protection_bundle' or doc->'protection_after' is distinct from s->'protection_bundle' then raise exception 'Protection changed' using errcode='40001'; end if;
  r:=doc->'workflow_file'; perform civicpulse_delivery.exact_object(r,array['path','source_sha','sha256','bytes']);
  if jsonb_typeof(r->'bytes')<>'number' then raise exception 'Invalid workflow bytes' using errcode='22023'; end if;
  if (r->>'bytes')::numeric<0 or (r->>'bytes')::numeric>9007199254740991 or trunc((r->>'bytes')::numeric)<>(r->>'bytes')::numeric then raise exception 'Invalid workflow bytes' using errcode='22023'; end if;
  if r->'path' is distinct from s->'workflow_path' or r->'source_sha' is distinct from to_jsonb(sha) or r->'sha256' is distinct from s->'workflow_file_sha256' then raise exception 'Workflow bytes mismatch' using errcode='40001'; end if;
  perform civicpulse_delivery.validate_request_audit(doc->'requests',array['repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','classic_before','classic_after','rulesets_before','rulesets_after','effective_rules_before','effective_rules_after','workflow_file']);
end $$;
create function civicpulse_delivery.open_source_observation(p_run_id text,p_source_sha text,p_purpose text,p_job_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  perform civicpulse_delivery.parse_run_identity(p_run_id);
  if p_source_sha is null or p_source_sha collate "C" !~ '^[0-9a-f]{40}$' or p_purpose is null or p_purpose not in ('claim','deploy') or (p_purpose='claim' and p_job_id is not null) then raise exception 'Invalid source target' using errcode='22023'; end if;
  if p_purpose='deploy' then raise exception 'Jobs not implemented' using errcode='55000'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler'); perform civicpulse_delivery.source_ready();
  insert into civicpulse_delivery.observation_challenges(family,config_version,dataset_epoch,actor,actor_oid,issued_at,expires_at,purpose,run_id,source_sha)
    select 'source',e.config_version,s.dataset_epoch,session_user,(select oid from pg_roles where rolname=session_user),t.at,t.at+interval '120 seconds',p_purpose,p_run_id,p_source_sha
    from civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s cross join (select clock_timestamp() at) t returning * into c;
  select d.config into config from civicpulse_delivery.delivery_configs d where d.config_version=c.config_version;
  return jsonb_build_object('challenge_id',c.challenge_id,'config_version',c.config_version,'issued_at',c.issued_at,'expires_at',c.expires_at,'run_id',c.run_id,'source_sha',c.source_sha,'purpose',c.purpose,'job_id',c.job_id,'config',config);
end $$;
create function civicpulse_delivery.record_source_observation(p_challenge_id uuid,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; o civicpulse_delivery.observations; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_challenge_id is null then raise exception 'Challenge required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=p_challenge_id for update;
  if c.family is distinct from 'source' or c.actor is distinct from session_user or c.actor_oid is distinct from (select oid from pg_roles where rolname=session_user) then raise exception 'Source challenge changed' using errcode='40001'; end if;
  if c.purpose<>'claim' then raise exception 'Jobs not implemented' using errcode='55000'; end if;
  perform civicpulse_delivery.check_challenge(c); perform civicpulse_delivery.source_ready();
  select d.config into config from civicpulse_delivery.delivery_configs d where d.config_version=c.config_version;
  perform civicpulse_delivery.validate_source_evidence(p_evidence,config,c.run_id,c.source_sha);
  select * into o from civicpulse_delivery.observations where challenge_id=c.challenge_id;
  if found then
    if o.evidence is distinct from p_evidence or o.consumed_at is not null then raise exception 'Observation changed or consumed' using errcode='40001'; end if;
  else
    insert into civicpulse_delivery.observations(challenge_id,evidence,evidence_sha256,received_at)
      values(c.challenge_id,p_evidence,encode(sha256(convert_to(p_evidence::text,'UTF8')),'hex'),clock_timestamp()) returning * into o;
    if o.received_at>=c.expires_at then raise exception 'Observation expired' using errcode='40001'; end if;
  end if;
  perform civicpulse_delivery.check_challenge(c);
  return jsonb_build_object('observation_id',o.observation_id,'challenge_id',c.challenge_id,'config_version',c.config_version,'source_sha',c.source_sha,'received_at',o.received_at,'expires_at',c.expires_at,'evidence_sha256',o.evidence_sha256);
end $$;
revoke all on function civicpulse_delivery.check_challenge(civicpulse_delivery.observation_challenges),civicpulse_delivery.source_ready(),civicpulse_delivery.validate_request_audit(jsonb,text[],boolean),civicpulse_delivery.validate_source_evidence(jsonb,jsonb,text,text),civicpulse_delivery.open_source_observation(text,text,text,uuid),civicpulse_delivery.record_source_observation(uuid,jsonb) from public,anon,authenticated;

create function civicpulse_delivery.baseline_ready() returns void
language plpgsql security invoker set search_path='' as $$ begin
  perform civicpulse_delivery.assert_quiescent();
  if not exists(select 1 from civicpulse_delivery.publication_state s cross join civicpulse_delivery.pipeline_state p cross join civicpulse_delivery.enrollment_state e
    where s.bootstrap_complete and p.paused and e.config_version is not null and p.live_deployment_id is null and not p.live_inventory_complete)
    or exists(select 1 from civicpulse_delivery.maintenance_approvals where action='baseline') then
    raise exception 'First markerless baseline unavailable' using errcode='55000'; end if;
end $$;
create function civicpulse_delivery.validate_baseline_evidence(doc jsonb,config jsonb,deployment text) returns void
language plpgsql immutable security invoker set search_path='' as $$
declare p jsonb:=config->'provider'; d jsonb;
begin
  perform civicpulse_delivery.exact_object(doc,array['schema_version','project','deployment','markers','artifact','github_terminal','requests']);
  if doc->'schema_version' is distinct from '1'::jsonb or doc->'github_terminal' is distinct from 'null'::jsonb then raise exception 'Invalid baseline evidence' using errcode='22023'; end if;
  perform civicpulse_delivery.exact_object(doc->'project',array['id','name','canonical_deployment_id','production_branch']);
  if doc->'project' is distinct from jsonb_build_object('id',p->>'project_id','name',p->>'project_name','canonical_deployment_id',deployment,'production_branch','main') then raise exception 'Provider project mismatch' using errcode='40001'; end if;
  d:=doc->'deployment';
  perform civicpulse_delivery.exact_object(d,array['id','project_id','project_name','environment','stage','status','source_sha','branch']);
  perform civicpulse_delivery.text_field(d,'source_sha','^[0-9a-f]{40}$');
  if d-'source_sha' is distinct from jsonb_build_object('id',deployment,'project_id',p->>'project_id','project_name',p->>'project_name','environment','production','stage','deploy','status','success','branch','main') then raise exception 'Provider deployment mismatch' using errcode='40001'; end if;
  perform civicpulse_delivery.exact_object(doc->'markers',array['deployment','production','pages']);
  if doc->'markers' is distinct from '{"deployment":null,"production":null,"pages":null}'::jsonb then raise exception 'Baseline marker not absent' using errcode='40001'; end if;
  perform civicpulse_delivery.exact_object(doc->'artifact',array['artifact_sha256','served_inventory_sha256']);
  perform civicpulse_delivery.text_field(doc->'artifact','artifact_sha256','^[0-9a-f]{64}$');
  perform civicpulse_delivery.text_field(doc->'artifact','served_inventory_sha256','^[0-9a-f]{64}$');
  -- Full three-origin bytes/routes/retention are verified by the trusted adapter.
  -- These hashes/audits do not let SQL detect a dishonest valid reconciler.
  perform civicpulse_delivery.validate_request_audit(doc->'requests',array['project_before','project_after','deployment','marker_deployment','marker_production','marker_pages','artifact_files'],true);
end $$;
create function civicpulse_delivery.open_provider_observation(p_purpose text,p_job_id uuid,p_attempt_id uuid,p_deployment_id text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_purpose is null or p_purpose not in ('baseline','predeploy','outcome','terminal') then raise exception 'Invalid observation purpose' using errcode='22023'; end if;
  if p_purpose<>'baseline' then raise exception 'Job observations unavailable' using errcode='55000'; end if;
  if p_job_id is not null or p_attempt_id is not null or p_deployment_id is null or p_deployment_id collate "C" !~ '^[A-Za-z0-9_-]{1,128}$' then raise exception 'Invalid baseline target' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler'); perform civicpulse_delivery.baseline_ready();
  insert into civicpulse_delivery.observation_challenges(family,config_version,dataset_epoch,actor,actor_oid,issued_at,expires_at,purpose,deployment_id)
    select 'provider',e.config_version,s.dataset_epoch,session_user,(select oid from pg_roles where rolname=session_user),t.at,t.at+interval '120 seconds',p_purpose,p_deployment_id
    from civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s cross join (select clock_timestamp() at) t returning * into c;
  select d.config into config from civicpulse_delivery.delivery_configs d where d.config_version=c.config_version;
  return jsonb_build_object('challenge_id',c.challenge_id,'config_version',c.config_version,'purpose',c.purpose,'job_id',c.job_id,'attempt_id',c.attempt_id,'deployment_id',c.deployment_id,'issued_at',c.issued_at,'expires_at',c.expires_at,'config',config);
end $$;
create function civicpulse_delivery.record_provider_observation(p_challenge_id uuid,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; o civicpulse_delivery.observations; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_challenge_id is null then raise exception 'Challenge required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=p_challenge_id for update;
  if c.family is distinct from 'provider' or c.actor is distinct from session_user or c.actor_oid is distinct from (select oid from pg_roles where rolname=session_user) then raise exception 'Provider challenge changed' using errcode='40001'; end if;
  if c.purpose<>'baseline' then raise exception 'Job observations unavailable' using errcode='55000'; end if;
  perform civicpulse_delivery.check_challenge(c);
  select * into o from civicpulse_delivery.observations where challenge_id=c.challenge_id;
  if found and (o.evidence is distinct from p_evidence or o.consumed_at is not null) then raise exception 'Observation changed or consumed' using errcode='40001'; end if;
  perform civicpulse_delivery.baseline_ready();
  select d.config into config from civicpulse_delivery.delivery_configs d where d.config_version=c.config_version;
  perform civicpulse_delivery.validate_baseline_evidence(p_evidence,config,c.deployment_id);
  if o.observation_id is null then
    insert into civicpulse_delivery.observations(challenge_id,evidence,evidence_sha256,received_at)
      values(c.challenge_id,p_evidence,encode(sha256(convert_to(p_evidence::text,'UTF8')),'hex'),clock_timestamp()) returning * into o;
    if o.received_at>=c.expires_at then raise exception 'Observation expired' using errcode='40001'; end if;
  end if;
  perform civicpulse_delivery.check_challenge(c);
  return jsonb_build_object('observation_id',o.observation_id,'challenge_id',c.challenge_id,'config_version',c.config_version,'received_at',o.received_at,'expires_at',c.expires_at,'evidence_sha256',o.evidence_sha256);
end $$;
create function civicpulse_delivery.approve_epoch_baseline(p_expected_epoch uuid,p_live_deployment_id text,p_live_marker jsonb,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; o civicpulse_delivery.observations; observation uuid;
begin
  perform civicpulse_delivery.require_machine('publication_operator');
  perform civicpulse_delivery.review_reference(p_review_reference);
  perform civicpulse_delivery.exact_object(p_live_marker,array['observation_id']);
  observation:=civicpulse_delivery.text_field(p_live_marker,'observation_id','^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')::uuid;
  if p_expected_epoch is null or p_live_deployment_id is null or p_live_deployment_id collate "C" !~ '^[A-Za-z0-9_-]{1,128}$' then raise exception 'Invalid baseline approval' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('publication_operator');
  select * into o from civicpulse_delivery.observations where observation_id=observation for update;
  if o.observation_id is null or o.consumed_at is not null then raise exception 'Baseline receipt missing or consumed' using errcode='40001'; end if;
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=o.challenge_id for update;
  perform civicpulse_delivery.check_challenge(c);
  if c.family<>'provider' or c.purpose<>'baseline' or c.dataset_epoch<>p_expected_epoch or c.deployment_id<>p_live_deployment_id then raise exception 'Baseline binding mismatch' using errcode='40001'; end if;
  perform civicpulse_delivery.baseline_ready();
  update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=p_expected_epoch where observation_id=observation;
  update civicpulse_delivery.enrollment_state set baseline_observation_id=observation,baseline_epoch=p_expected_epoch;
  update civicpulse_delivery.pipeline_state set approved_epoch=p_expected_epoch;
  insert into civicpulse_delivery.maintenance_approvals(action,actor,actor_oid,review_reference,evidence)
    values('baseline',session_user,(select oid from pg_roles where rolname=session_user),p_review_reference,
      jsonb_build_object('observation_id',observation,'dataset_epoch',p_expected_epoch,'config_version',c.config_version,'deployment_id',c.deployment_id,'artifact',o.evidence->'artifact','evidence_sha256',o.evidence_sha256));
  return jsonb_build_object('approved_epoch',p_expected_epoch,'previous_live_deployment_id',c.deployment_id);
end $$;
create or replace function civicpulse_delivery.set_pipeline_paused(p_paused boolean,p_review_reference text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$ begin
  perform civicpulse_delivery.require_machine('publication_operator');
  perform civicpulse_delivery.review_reference(p_review_reference);
  if p_paused is null then raise exception 'Pause flag required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('publication_operator');
  if not p_paused then
    perform civicpulse_delivery.assert_quiescent();
    if not exists(select 1 from civicpulse_delivery.publication_state s cross join civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.pipeline_state p
      where e.config_version is not null and e.baseline_observation_id is not null and e.baseline_epoch=s.dataset_epoch and p.approved_epoch=s.dataset_epoch and s.bootstrap_complete
      and (p.live_dataset_epoch is null or (p.live_dataset_epoch=s.dataset_epoch and p.live_generation<=s.generation))) then raise exception 'Resume gates incomplete' using errcode='55000'; end if;
  end if;
  update civicpulse_delivery.pipeline_state set paused=p_paused;
  insert into civicpulse_delivery.operator_audit(actor,action,review_reference) values(session_user,case when p_paused then 'pause' else 'resume' end,p_review_reference);
  return jsonb_build_object('paused',p_paused);
end $$;
revoke all on function civicpulse_delivery.baseline_ready(),civicpulse_delivery.validate_baseline_evidence(jsonb,jsonb,text),civicpulse_delivery.open_provider_observation(text,uuid,uuid,text),civicpulse_delivery.record_provider_observation(uuid,jsonb),civicpulse_delivery.approve_epoch_baseline(uuid,text,jsonb,text),civicpulse_delivery.set_pipeline_paused(boolean,text) from public,anon,authenticated;

-- Every helper and entrypoint is private; provisioning is a later reviewed action.
revoke all on function civicpulse_delivery.exact_object(jsonb,text[]),civicpulse_delivery.text_field(jsonb,text,text),civicpulse_delivery.review_reference(text),civicpulse_delivery.lock_enrollment(text),civicpulse_delivery.assert_quiescent(),civicpulse_delivery.validate_delivery_config(jsonb),civicpulse_delivery.enroll_delivery_config(uuid,jsonb,text),civicpulse_delivery.approve_bootstrap(uuid,bigint,jsonb,text),civicpulse_delivery.reset_epoch(uuid,uuid,text) from public,anon,authenticated;
