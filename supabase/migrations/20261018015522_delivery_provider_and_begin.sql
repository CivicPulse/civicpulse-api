-- LOCAL M2.3: checked provider observations and one-shot begin, no network.
alter table civicpulse_delivery.observation_challenges add column prior_observation_id uuid references civicpulse_delivery.observations;
alter table civicpulse_delivery.observation_challenges add column prior_evidence jsonb;
alter table civicpulse_delivery.observations add column eligibility text not null default 'audit';
alter table civicpulse_delivery.enrollment_state add column live_observation_id uuid references civicpulse_delivery.observations;
alter table civicpulse_delivery.build_jobs drop constraint build_jobs_state_check;
alter table civicpulse_delivery.build_jobs add check(state in ('queued','exporting','building','validating','ready','deploying','deployment_unknown','live','failed','superseded'));
drop index civicpulse_delivery.one_active_build;
create unique index one_active_build on civicpulse_delivery.build_jobs ((true)) where state in ('queued','exporting','building','validating','ready','deploying','deployment_unknown');

create function civicpulse_delivery.require_source_job(id uuid,run text,sha text) returns void
language plpgsql security invoker set search_path='' as $$ begin
  if not exists(select 1 from civicpulse_delivery.build_jobs j cross join civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s
    where j.job_id=id and j.job_id=e.active_job_id and j.state='ready' and j.run_id=run and j.source_sha=sha
      and j.config_version=e.config_version and j.dataset_epoch=s.dataset_epoch and j.target_generation=s.generation and clock_timestamp()<j.lease_expires_at)
    then raise exception 'Ready source job changed' using errcode='40001'; end if;
end $$;
revoke all on function civicpulse_delivery.require_source_job(uuid,text,text) from public,anon,authenticated;

create function civicpulse_delivery.check_terminal_facts(doc jsonb,j civicpulse_delivery.build_jobs) returns boolean
language plpgsql security invoker set search_path='' as $$
declare r jsonb; cfg jsonb; original jsonb; path text; k text; f text; matches boolean:=true;
begin
  if doc='null'::jsonb then return false; end if;
  perform civicpulse_delivery.exact_object(doc,array['run','attempt']);
  select config->'source' into cfg from civicpulse_delivery.delivery_configs where config_version=j.config_version;
  select evidence->'run_before' into original from civicpulse_delivery.observations where observation_id=j.source_observation_id;
  path:=case cfg->>'run_path_form' when 'bare' then cfg->>'workflow_path' when 'relative-main' then (cfg->>'workflow_path')||'@main' else (cfg->>'repository_full_name')||'/'||(cfg->>'workflow_path')||'@main' end;
  foreach k in array array['run','attempt'] loop
    r:=doc->k;
    perform civicpulse_delivery.exact_object(r,array['repository_id','head_repository_id','workflow_id','run_id','run_attempt','raw_path','head_branch','head_sha','event','status','conclusion']);
    foreach f in array array['repository_id','head_repository_id','workflow_id','run_id'] loop perform civicpulse_delivery.text_field(r,f,'^[1-9][0-9]{0,19}$'); end loop;
    perform civicpulse_delivery.text_field(r,'run_attempt','^[1-9][0-9]{0,9}$');
    perform civicpulse_delivery.text_field(r,'head_sha','^[0-9a-f]{40}$');
    foreach f in array array['raw_path','head_branch','event'] loop perform civicpulse_delivery.text_field(r,f,'^[ -~]+$'); end loop;
    if octet_length(r->>'raw_path')>65534 or r->'status' is distinct from '"completed"'::jsonb then raise exception 'Invalid terminal lifecycle' using errcode='22023'; end if;
    perform civicpulse_delivery.text_field(r,'conclusion','^(action_required|cancelled|failure|neutral|skipped|stale|startup_failure|success|timed_out)$');
    if r->>'repository_id'<>j.repository_id or r->>'head_repository_id'<>j.repository_id or r->'workflow_id' is distinct from cfg->'workflow_id'
      or (r->>'run_id')||':'||(r->>'run_attempt')<>j.run_id or r->>'raw_path'<>path or r->>'head_branch'<>'main'
      or r->>'head_sha'<>j.source_sha or r->'event' is distinct from original->'event' then matches:=false; end if;
  end loop;
  return matches and doc->'run'=doc->'attempt';
end $$;

create function civicpulse_delivery.provider_requests(doc jsonb) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
declare r jsonb; k text; n numeric; seen text[]:='{}'; result jsonb:='{}'; pages integer:=0; max_page numeric:=0;
begin
  if doc is null or jsonb_typeof(doc)<>'array' then raise exception 'Invalid provider requests' using errcode='22023'; end if;
  for r in select value from jsonb_array_elements(doc) loop
    perform civicpulse_delivery.exact_object(r,array['endpoint_key','page','status','request_id']);
    k:=civicpulse_delivery.text_field(r,'endpoint_key','^(project_before|project_after|deployment|deployment_list|marker_deployment|marker_production|marker_pages|artifact_files|github_run_terminal|github_attempt_terminal)$');
    if jsonb_typeof(r->'page')<>'number' or jsonb_typeof(r->'status')<>'number' then raise exception 'Invalid request numbers' using errcode='22023'; end if;
    n:=(r->>'page')::numeric;
    if n<1 or n>9007199254740991 or trunc(n)<>n or (k<>'deployment_list' and n<>1)
      or (r->>'status')::numeric<100 or (r->>'status')::numeric>599 or trunc((r->>'status')::numeric)<>(r->>'status')::numeric then raise exception 'Invalid request values' using errcode='22023'; end if;
    if (k||':'||trunc(n)::text)=any(seen) then raise exception 'Duplicate provider request' using errcode='22023'; end if;
    seen:=array_append(seen,k||':'||trunc(n)::text);
    if r->'request_id'<>'null'::jsonb then
      perform civicpulse_delivery.text_field(r,'request_id','^[ -~]+$');
      if length(r->>'request_id')>256 then raise exception 'Request ID too long' using errcode='22023'; end if;
    end if;
    if k='artifact_files' and (r->'status'<>'200'::jsonb or r->'request_id'<>'null'::jsonb) then raise exception 'Invalid aggregate evidence' using errcode='22023'; end if;
    if k='deployment_list' then pages:=pages+1; max_page:=greatest(max_page,n); end if;
    result:=result||jsonb_build_object(k,r->'status');
  end loop;
  if pages<>max_page then raise exception 'Incomplete deployment pagination' using errcode='22023'; end if;
  if result->'project_before' is distinct from '200'::jsonb or result->'project_after' is distinct from '200'::jsonb then raise exception 'Fixed project observation required' using errcode='22023'; end if;
  return result;
end $$;

create function civicpulse_delivery.expected_job_marker(j civicpulse_delivery.build_jobs) returns jsonb
language sql immutable security invoker set search_path='' as $$
  select jsonb_build_object('schema_version',1,'job_id',j.job_id,'dataset_epoch',j.dataset_epoch,'generation',j.target_generation::text,'source_sha',j.source_sha,'snapshot_sha256',j.snapshot_sha256);
$$;

create function civicpulse_delivery.provider_classification(doc jsonb,c civicpulse_delivery.observation_challenges) returns text
language plpgsql security invoker set search_path='' as $$
declare cfg jsonb; j civicpulse_delivery.build_jobs; intent civicpulse_delivery.deployment_intents; d jsonb; m jsonb; a jsonb; req jsonb; required jsonb; key text; r jsonb; terminal boolean; marker jsonb; prior jsonb:=c.prior_evidence; lists boolean;
begin
  perform civicpulse_delivery.exact_object(doc,array['schema_version','project','deployment','markers','artifact','github_terminal','requests']);
  if doc->'schema_version' is distinct from '1'::jsonb then raise exception 'Invalid provider schema' using errcode='22023'; end if;
  select config into cfg from civicpulse_delivery.delivery_configs where config_version=c.config_version;
  select * into j from civicpulse_delivery.build_jobs where job_id=c.job_id;
  select * into intent from civicpulse_delivery.deployment_intents where job_id=c.job_id;
  r:=doc->'project'; perform civicpulse_delivery.exact_object(r,array['id','name','canonical_deployment_id','production_branch']);
  foreach key in array array['id','name','canonical_deployment_id','production_branch'] loop perform civicpulse_delivery.text_field(r,key,'^[A-Za-z0-9_-]{1,128}$'); end loop;
  if r->'id' is distinct from cfg->'provider'->'project_id' or r->'name' is distinct from cfg->'provider'->'project_name' then raise exception 'Wrong fixed project' using errcode='40001'; end if;
  d:=doc->'deployment'; m:=doc->'markers'; a:=doc->'artifact';
  if d<>'null'::jsonb then
    perform civicpulse_delivery.exact_object(d,array['id','project_id','project_name','environment','stage','status','source_sha','branch']);
    foreach key in array array['id','project_id','project_name','environment','stage','status','branch'] loop perform civicpulse_delivery.text_field(d,key,'^[A-Za-z0-9_-]{1,128}$'); end loop;
    perform civicpulse_delivery.text_field(d,'source_sha','^[0-9a-f]{40}$');
  end if;
  if a<>'null'::jsonb then
    perform civicpulse_delivery.exact_object(a,array['artifact_sha256','served_inventory_sha256']);
    perform civicpulse_delivery.text_field(a,'artifact_sha256','^[0-9a-f]{64}$'); perform civicpulse_delivery.text_field(a,'served_inventory_sha256','^[0-9a-f]{64}$');
  end if;
  if m<>'null'::jsonb then
    perform civicpulse_delivery.exact_object(m,array['deployment','production','pages']);
    foreach key in array array['deployment','production','pages'] loop
      r:=m->key;
      if r<>'null'::jsonb then
        perform civicpulse_delivery.exact_object(r,array['schema_version','job_id','dataset_epoch','generation','source_sha','snapshot_sha256']);
        if r->'schema_version' is distinct from '1'::jsonb then raise exception 'Invalid marker schema' using errcode='22023'; end if;
        perform civicpulse_delivery.text_field(r,'job_id','^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
        perform civicpulse_delivery.text_field(r,'dataset_epoch','^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
        perform civicpulse_delivery.text_field(r,'generation','^(0|[1-9][0-9]{0,18})$');
        if (r->>'generation')::numeric>9223372036854775807 then raise exception 'Marker generation overflow' using errcode='22023'; end if;
        perform civicpulse_delivery.text_field(r,'source_sha','^[0-9a-f]{40}$'); perform civicpulse_delivery.text_field(r,'snapshot_sha256','^[0-9a-f]{64}$');
      end if;
    end loop;
  end if;
  terminal:=civicpulse_delivery.check_terminal_facts(doc->'github_terminal',j);
  req:=civicpulse_delivery.provider_requests(doc->'requests');
  lists:=req ? 'deployment_list';
  if lists and (c.deployment_id is not null or intent.attempt_id is null) then raise exception 'Unexpected deployment search' using errcode='22023'; end if;
  if lists and exists(select 1 from jsonb_array_elements(doc->'requests') q where q->>'endpoint_key'='deployment_list' and q->'status'<>'200'::jsonb) then return 'audit'; end if;
  req:=req-'deployment_list';
  if doc->'project'->>'production_branch'<>'main' then return 'audit'; end if;
  if c.purpose='terminal' and intent.attempt_id is null then
    required:='{"project_before":200,"project_after":200,"github_run_terminal":200,"github_attempt_terminal":200}';
    if terminal and req=required and d='null'::jsonb and m='null'::jsonb and a='null'::jsonb
      and doc->'project'=prior->'project' then return 'predeploy_terminal'; end if;
    return 'audit';
  end if;
  if d='null'::jsonb then return 'audit'; end if;
  if d->'project_id' is distinct from cfg->'provider'->'project_id' or d->'project_name' is distinct from cfg->'provider'->'project_name'
    or d->>'environment'<>'production' or d->>'branch'<>'main' or d->>'stage'<>'deploy' then return 'audit'; end if;
  if c.deployment_id is not null and d->>'id'<>c.deployment_id then return 'audit'; end if;
  if c.purpose='predeploy' then
    required:=jsonb_build_object('project_before',200,'project_after',200,'deployment',200,'artifact_files',200,
      'marker_deployment',case when prior->'markers'->'deployment'='null'::jsonb then 404 else 200 end,
      'marker_production',case when prior->'markers'->'deployment'='null'::jsonb then 404 else 200 end,
      'marker_pages',case when prior->'markers'->'deployment'='null'::jsonb then 404 else 200 end);
    if req=required and doc->'github_terminal'='null'::jsonb and doc-'requests'-'github_terminal' is not distinct from prior-'requests'-'github_terminal' then return 'predeploy'; end if;
    return 'audit';
  end if;
  if intent.attempt_id is null or d->>'source_sha'<>j.source_sha then return 'audit'; end if;
  required:='{"project_before":200,"project_after":200,"deployment":200,"artifact_files":200}';
  if d->>'status'='failure' then
    required:=required||'{"github_run_terminal":200,"github_attempt_terminal":200}';
    if terminal and req=required and doc->'project'=prior->'project' and d->>'id'<>prior->'deployment'->>'id'
      and m='null'::jsonb and a='null'::jsonb then return 'failure'; end if;
  elsif d->>'status'='success' then
    marker:=civicpulse_delivery.expected_job_marker(j);
    required:=required||'{"marker_deployment":200,"marker_production":200,"marker_pages":200}';
    if doc->'github_terminal'<>'null'::jsonb then required:=required||'{"github_run_terminal":200,"github_attempt_terminal":200}'; end if;
    if req=required and doc->'project'->>'canonical_deployment_id'=d->>'id'
      and m=jsonb_build_object('deployment',marker,'production',marker,'pages',marker)
      and a->>'artifact_sha256'=j.artifact_sha256 and (doc->'github_terminal'='null'::jsonb or terminal)
      and (c.purpose<>'terminal' or terminal) then return 'success'; end if;
  end if;
  return 'audit';
end $$;
revoke all on function civicpulse_delivery.check_terminal_facts(jsonb,civicpulse_delivery.build_jobs),civicpulse_delivery.provider_requests(jsonb),civicpulse_delivery.expected_job_marker(civicpulse_delivery.build_jobs),civicpulse_delivery.provider_classification(jsonb,civicpulse_delivery.observation_challenges) from public,anon,authenticated;
create or replace function civicpulse_delivery.open_source_observation(p_run_id text,p_source_sha text,p_purpose text,p_job_id uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  perform civicpulse_delivery.parse_run_identity(p_run_id);
  if p_source_sha is null or p_source_sha collate "C" !~ '^[0-9a-f]{40}$' or p_purpose is null or p_purpose not in ('claim','deploy') or (p_purpose='claim' and p_job_id is not null) then raise exception 'Invalid source target' using errcode='22023'; end if;
  if p_purpose='deploy' and p_job_id is null then raise exception 'Ready job required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler'); perform civicpulse_delivery.source_ready();
  if p_purpose='deploy' then perform civicpulse_delivery.require_source_job(p_job_id,p_run_id,p_source_sha); end if;
  insert into civicpulse_delivery.observation_challenges(family,config_version,dataset_epoch,actor,actor_oid,issued_at,expires_at,purpose,run_id,source_sha,job_id)
    select 'source',e.config_version,s.dataset_epoch,session_user,(select oid from pg_roles where rolname=session_user),t.at,t.at+interval '120 seconds',p_purpose,p_run_id,p_source_sha,p_job_id
    from civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s cross join (select clock_timestamp() at) t returning * into c;
  select d.config into config from civicpulse_delivery.delivery_configs d where d.config_version=c.config_version;
  return jsonb_build_object('challenge_id',c.challenge_id,'config_version',c.config_version,'issued_at',c.issued_at,'expires_at',c.expires_at,'run_id',c.run_id,'source_sha',c.source_sha,'purpose',c.purpose,'job_id',c.job_id,'config',config);
end $$;
create or replace function civicpulse_delivery.record_source_observation(p_challenge_id uuid,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; o civicpulse_delivery.observations; config jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_challenge_id is null then raise exception 'Challenge required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=p_challenge_id for update;
  if c.family is distinct from 'source' or c.actor is distinct from session_user or c.actor_oid is distinct from (select oid from pg_roles where rolname=session_user) then raise exception 'Source challenge changed' using errcode='40001'; end if;
  if c.purpose='deploy' then perform civicpulse_delivery.require_source_job(c.job_id,c.run_id,c.source_sha); end if;
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

-- Read the retained authoritative P, never a caller-selected prior deployment.
create function civicpulse_delivery.current_prior_observation() returns uuid
language sql stable security invoker set search_path='' as $$
  select coalesce(e.live_observation_id,e.baseline_observation_id)
  from civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s
  where e.baseline_epoch=s.dataset_epoch;
$$;
revoke all on function civicpulse_delivery.current_prior_observation() from public,anon,authenticated;

create or replace function civicpulse_delivery.open_provider_observation(p_purpose text,p_job_id uuid,p_attempt_id uuid,p_deployment_id text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; cfg jsonb; j civicpulse_delivery.build_jobs;
  i civicpulse_delivery.deployment_intents; prior_id uuid; prior jsonb;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_purpose is null or p_purpose not in ('baseline','predeploy','outcome','terminal')
    or (p_deployment_id is not null and p_deployment_id collate "C" !~ '^[A-Za-z0-9_-]{1,128}$') then
    raise exception 'Invalid provider target' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  if p_purpose='baseline' then
    if p_job_id is not null or p_attempt_id is not null or p_deployment_id is null then raise exception 'Invalid baseline target' using errcode='22023'; end if;
    perform civicpulse_delivery.baseline_ready();
  else
    if p_job_id is null then raise exception 'Job required' using errcode='22023'; end if;
    select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
    if j.job_id is null or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state)
      or j.config_version is distinct from (select config_version from civicpulse_delivery.enrollment_state)
      or j.dataset_epoch is distinct from (select dataset_epoch from civicpulse_delivery.publication_state) then
      raise exception 'Provider job changed' using errcode='40001'; end if;
    select * into i from civicpulse_delivery.deployment_intents where job_id=j.job_id;
    if p_purpose='predeploy' then
      if p_attempt_id is not null or p_deployment_id is null then raise exception 'Invalid predeploy target' using errcode='22023'; end if;
      if j.state<>'ready' or i.attempt_id is not null or clock_timestamp()>=j.lease_expires_at then raise exception 'Predeploy job changed' using errcode='40001'; end if;
    elsif p_purpose='outcome' then
      if p_attempt_id is null then raise exception 'Attempt required' using errcode='22023'; end if;
      if i.attempt_id is distinct from p_attempt_id then raise exception 'Attempt changed' using errcode='40001'; end if;
    elsif i.attempt_id is distinct from p_attempt_id then raise exception 'Terminal attempt changed' using errcode='40001'; end if;
    if i.attempt_id is null then
      if p_purpose='terminal' and p_deployment_id is not null then raise exception 'Prebegin terminal has no candidate' using errcode='22023'; end if;
      prior_id:=civicpulse_delivery.current_prior_observation();
      select evidence into prior from civicpulse_delivery.observations where observation_id=prior_id;
    else prior_id:=i.prior_observation_id; prior:=i.prior_production;
    end if;
    if prior_id is null or prior is null then raise exception 'Approved prior unavailable' using errcode='55000'; end if;
    if p_purpose='predeploy' and p_deployment_id is distinct from prior->'deployment'->>'id' then raise exception 'Prior deployment changed' using errcode='40001'; end if;
  end if;
  insert into civicpulse_delivery.observation_challenges(family,config_version,dataset_epoch,actor,actor_oid,issued_at,expires_at,purpose,job_id,attempt_id,deployment_id,prior_observation_id,prior_evidence)
    select 'provider',e.config_version,s.dataset_epoch,session_user,(select oid from pg_roles where rolname=session_user),t.at,t.at+interval '120 seconds',p_purpose,p_job_id,p_attempt_id,p_deployment_id,prior_id,prior
    from civicpulse_delivery.enrollment_state e cross join civicpulse_delivery.publication_state s cross join (select clock_timestamp() at) t returning * into c;
  select config into cfg from civicpulse_delivery.delivery_configs where config_version=c.config_version;
  return jsonb_build_object('challenge_id',c.challenge_id,'config_version',c.config_version,'purpose',c.purpose,'job_id',c.job_id,'attempt_id',c.attempt_id,'deployment_id',c.deployment_id,'issued_at',c.issued_at,'expires_at',c.expires_at,'config',cfg);
end $$;

create function civicpulse_delivery.check_provider_context(c civicpulse_delivery.observation_challenges) returns void
language plpgsql security invoker set search_path='' as $$
declare j civicpulse_delivery.build_jobs; i civicpulse_delivery.deployment_intents;
begin
  perform civicpulse_delivery.check_challenge(c);
  if c.purpose='baseline' then perform civicpulse_delivery.baseline_ready(); return; end if;
  select * into j from civicpulse_delivery.build_jobs where job_id=c.job_id for update;
  if j.job_id is null or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state)
    or j.config_version is distinct from c.config_version or j.dataset_epoch is distinct from c.dataset_epoch then raise exception 'Provider job changed' using errcode='40001'; end if;
  select * into i from civicpulse_delivery.deployment_intents where job_id=j.job_id;
  if c.attempt_id is distinct from i.attempt_id then raise exception 'Provider attempt changed' using errcode='40001'; end if;
  if i.attempt_id is null then
    if c.prior_observation_id is distinct from civicpulse_delivery.current_prior_observation() then raise exception 'Prior production changed' using errcode='40001'; end if;
    if c.purpose='predeploy' and (j.state<>'ready' or clock_timestamp()>=j.lease_expires_at) then raise exception 'Predeploy job changed' using errcode='40001'; end if;
  elsif c.prior_observation_id is distinct from i.prior_observation_id or c.prior_evidence is distinct from i.prior_production then
    raise exception 'Prior intent changed' using errcode='40001';
  end if;
end $$;
revoke all on function civicpulse_delivery.check_provider_context(civicpulse_delivery.observation_challenges) from public,anon,authenticated;

create or replace function civicpulse_delivery.record_provider_observation(p_challenge_id uuid,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare c civicpulse_delivery.observation_challenges; o civicpulse_delivery.observations; cfg jsonb; classification text;
begin
  perform civicpulse_delivery.require_machine('reconciler');
  if p_challenge_id is null then raise exception 'Challenge required' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('reconciler');
  select * into c from civicpulse_delivery.observation_challenges where challenge_id=p_challenge_id for update;
  if c.family is distinct from 'provider' or c.actor is distinct from session_user or c.actor_oid is distinct from (select oid from pg_roles where rolname=session_user) then raise exception 'Provider challenge changed' using errcode='40001'; end if;
  perform civicpulse_delivery.check_provider_context(c);
  select * into o from civicpulse_delivery.observations where challenge_id=c.challenge_id;
  if found then
    if o.evidence is distinct from p_evidence or o.consumed_at is not null then raise exception 'Observation changed or consumed' using errcode='40001'; end if;
    -- An immutable audit row is never promoted by replay after state changes.
  else
    if c.purpose='baseline' then
      select config into cfg from civicpulse_delivery.delivery_configs where config_version=c.config_version;
      perform civicpulse_delivery.validate_baseline_evidence(p_evidence,cfg,c.deployment_id);
      classification:='baseline';
    else classification:=civicpulse_delivery.provider_classification(p_evidence,c);
    end if;
    insert into civicpulse_delivery.observations(challenge_id,evidence,evidence_sha256,received_at,eligibility)
      values(c.challenge_id,p_evidence,encode(sha256(convert_to(p_evidence::text,'UTF8')),'hex'),clock_timestamp(),classification) returning * into o;
  end if;
  perform civicpulse_delivery.check_provider_context(c);
  return jsonb_build_object('observation_id',o.observation_id,'challenge_id',c.challenge_id,'config_version',c.config_version,'received_at',o.received_at,'expires_at',c.expires_at,'evidence_sha256',o.evidence_sha256);
end $$;

create function civicpulse_delivery.begin_deploy(p_job_id uuid,p_lease_id uuid,p_fence bigint,p_epoch uuid,p_generation bigint,p_manifest_sha256 text,p_artifact_sha256 text,p_source_sha text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; sc civicpulse_delivery.observation_challenges; pc civicpulse_delivery.observation_challenges;
  so civicpulse_delivery.observations; po civicpulse_delivery.observations; i civicpulse_delivery.deployment_intents;
begin
  perform civicpulse_delivery.require_machine('runner');
  if p_job_id is null or p_lease_id is null or p_fence is null or p_fence<=0 or p_epoch is null or p_generation is null or p_generation<0
    or p_manifest_sha256 is null or p_manifest_sha256 collate "C" !~ '^[0-9a-f]{64}$'
    or p_artifact_sha256 is null or p_artifact_sha256 collate "C" !~ '^[0-9a-f]{64}$'
    or p_source_sha is null or p_source_sha collate "C" !~ '^[0-9a-f]{40}$' then raise exception 'Invalid deployment target' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
  if j.job_id is null or j.actor is distinct from session_user or j.actor_oid is distinct from (select oid from pg_roles where rolname=session_user)
    or j.lease_id<>p_lease_id or j.fence<>p_fence or j.state<>'ready' or clock_timestamp()>=j.lease_expires_at
    or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state)
    or j.config_version is distinct from (select config_version from civicpulse_delivery.enrollment_state)
    or j.dataset_epoch<>p_epoch or j.target_generation<>p_generation or j.snapshot_sha256 is distinct from p_manifest_sha256
    or j.artifact_sha256 is distinct from p_artifact_sha256 or j.source_sha<>p_source_sha
    or exists(select 1 from civicpulse_delivery.deployment_intents where job_id=p_job_id) then raise exception 'Deployment claim changed' using errcode='40001'; end if;
  perform civicpulse_delivery.source_ready();
  if (select intervention_required from civicpulse_delivery.build_counter) then raise exception 'Intervention required' using errcode='55000'; end if;
  perform civicpulse_delivery.validate_receipt_manifest(j.publication_manifest,j.dataset_epoch,j.target_generation);
  if j.publication_manifest is distinct from public.publication_manifest() then raise exception 'Publication changed' using errcode='40001'; end if;
  select c.* into sc from civicpulse_delivery.observation_challenges c join civicpulse_delivery.observations o using(challenge_id)
    where c.family='source' and c.purpose='deploy' and c.job_id=j.job_id and c.run_id=j.run_id and c.source_sha=j.source_sha
      and c.config_version=j.config_version and c.dataset_epoch=j.dataset_epoch and o.consumed_at is null
    order by c.issued_at desc,c.challenge_id desc limit 1 for update of c,o;
  select c.* into pc from civicpulse_delivery.observation_challenges c join civicpulse_delivery.observations o using(challenge_id)
    where c.family='provider' and c.purpose='predeploy' and c.job_id=j.job_id and c.config_version=j.config_version
      and c.dataset_epoch=j.dataset_epoch and o.consumed_at is null
    order by c.issued_at desc,c.challenge_id desc limit 1 for update of c,o;
  perform civicpulse_delivery.check_challenge(sc);
  perform civicpulse_delivery.check_provider_context(pc);
  select * into so from civicpulse_delivery.observations where challenge_id=sc.challenge_id;
  select * into po from civicpulse_delivery.observations where challenge_id=pc.challenge_id;
  if po.eligibility<>'predeploy' or civicpulse_delivery.provider_classification(po.evidence,pc)<>'predeploy' then raise exception 'Predeploy evidence incomplete' using errcode='55000'; end if;
  insert into civicpulse_delivery.deployment_intents(job_id,fence,config_version,dataset_epoch,generation,source_sha,snapshot_sha256,artifact_sha256,publication_manifest,actor,actor_oid,source_observation_id,predeploy_observation_id,prior_observation_id,prior_deployment_id,prior_production)
    values(j.job_id,j.fence,j.config_version,j.dataset_epoch,j.target_generation,j.source_sha,j.snapshot_sha256,j.artifact_sha256,j.publication_manifest,session_user,j.actor_oid,so.observation_id,po.observation_id,pc.prior_observation_id,pc.prior_evidence->'deployment'->>'id',pc.prior_evidence) returning * into i;
  update civicpulse_delivery.observations set consumed_at=clock_timestamp(),consumed_for=i.attempt_id where observation_id in (so.observation_id,po.observation_id);
  update civicpulse_delivery.build_jobs set state='deploying' where job_id=j.job_id;
  update civicpulse_delivery.enrollment_state set external_authority=true;
  return jsonb_build_object('attempt_id',i.attempt_id,'authorized',true);
end $$;
revoke all on function civicpulse_delivery.begin_deploy(uuid,uuid,bigint,uuid,bigint,text,text,text) from public,anon,authenticated;
