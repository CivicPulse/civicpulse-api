-- Local security correction: caller reason is not proof of supersession.
create or replace function civicpulse_delivery.transition_build(p_job_id uuid,p_lease_id uuid,p_fence bigint,p_expected_state text,p_state text,p_evidence jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare j civicpulse_delivery.build_jobs; ack civicpulse_delivery.build_transitions; code text; normal boolean;
begin
  perform civicpulse_delivery.require_machine('runner');
  if p_job_id is null or p_lease_id is null or p_fence is null or p_fence<=0
    or p_expected_state is null or p_expected_state not in ('queued','exporting','building','validating','ready')
    or p_state is null then raise exception 'Invalid transition identity' using errcode='22023'; end if;
  normal:= (p_expected_state,p_state) in (('queued','exporting'),('exporting','building'),('building','validating'),('validating','ready'));
  if p_state='failed' then
    perform civicpulse_delivery.exact_object(p_evidence,array['error_code']);
    code:=case p_expected_state when 'queued' then 'export_failed' when 'exporting' then 'export_failed' when 'building' then 'build_failed' else 'validation_failed' end;
    if p_evidence->'error_code' is distinct from to_jsonb(code) then raise exception 'Wrong failure stage' using errcode='22023'; end if;
  elsif p_state='superseded' then
    perform civicpulse_delivery.exact_object(p_evidence,array['reason']);
    perform civicpulse_delivery.text_field(p_evidence,'reason','^(content_changed|source_changed|epoch_changed)$');
  elsif normal then
    if p_state='building' then
      perform civicpulse_delivery.exact_object(p_evidence,array['publication_manifest','snapshot_sha256']);
      perform civicpulse_delivery.text_field(p_evidence,'snapshot_sha256','^[0-9a-f]{64}$');
    elsif p_state='validating' then
      perform civicpulse_delivery.exact_object(p_evidence,array['artifact_sha256']);
      perform civicpulse_delivery.text_field(p_evidence,'artifact_sha256','^[0-9a-f]{64}$');
    else perform civicpulse_delivery.exact_object(p_evidence,'{}'); end if;
  else raise exception 'Illegal transition' using errcode='22023'; end if;
  perform civicpulse_delivery.lock_enrollment('runner');
  select * into j from civicpulse_delivery.build_jobs where job_id=p_job_id for update;
  if j.job_id is null or j.actor<>session_user or j.actor_oid<>(select oid from pg_roles where rolname=session_user)
    or j.lease_id<>p_lease_id or j.fence<>p_fence then raise exception 'Transition owner changed' using errcode='40001'; end if;
  select * into ack from civicpulse_delivery.build_transitions where job_id=j.job_id and sequence=j.transition_sequence;
  if ack.job_id is not null and ack.expected_state=p_expected_state and ack.state=p_state and ack.evidence=p_evidence then
    if j.state in ('failed','superseded') or clock_timestamp()<j.lease_expires_at then
      return jsonb_build_object('state',ack.state);
    end if;
  end if;
  if j.state<>p_expected_state or clock_timestamp()>=j.lease_expires_at
    or j.job_id is distinct from (select active_job_id from civicpulse_delivery.enrollment_state) then
    raise exception 'Transition state or lease changed' using errcode='40001'; end if;
  if p_state='superseded' then
    if p_evidence->>'reason'='source_changed' then
      raise exception 'Authenticated source-change gate unavailable' using errcode='55000';
    elsif p_evidence->>'reason'='content_changed' then
      if not exists(select 1 from civicpulse_delivery.publication_state s
        where s.dataset_epoch=j.dataset_epoch and s.generation<>j.target_generation) then
        raise exception 'Content has not changed' using errcode='40001'; end if;
    elsif p_evidence->>'reason'='epoch_changed' then
      if not exists(select 1 from civicpulse_delivery.publication_state s where s.dataset_epoch<>j.dataset_epoch) then
        raise exception 'Epoch has not changed' using errcode='40001'; end if;
    end if;
  end if;
  if normal then
    if not exists(select 1 from civicpulse_delivery.publication_state s cross join civicpulse_delivery.enrollment_state e
      where s.dataset_epoch=j.dataset_epoch and s.generation=j.target_generation and e.config_version=j.config_version)
      then raise exception 'Desired tuple changed' using errcode='40001'; end if;
    if p_state='building' then
      perform civicpulse_delivery.validate_receipt_manifest(p_evidence->'publication_manifest',j.dataset_epoch,j.target_generation);
      if p_evidence->'publication_manifest' is distinct from public.publication_manifest() then raise exception 'Manifest changed' using errcode='40001'; end if;
      update civicpulse_delivery.build_jobs set publication_manifest=p_evidence->'publication_manifest',snapshot_sha256=p_evidence->>'snapshot_sha256' where job_id=j.job_id;
    elsif p_state='validating' then
      if j.publication_manifest is null or j.snapshot_sha256 is null then raise exception 'Snapshot missing' using errcode='55000'; end if;
      update civicpulse_delivery.build_jobs set artifact_sha256=p_evidence->>'artifact_sha256' where job_id=j.job_id;
    elsif p_state='ready' then
      if j.publication_manifest is null or j.snapshot_sha256 is null or j.artifact_sha256 is null then raise exception 'Build evidence missing' using errcode='55000'; end if;
    end if;
  end if;
  insert into civicpulse_delivery.build_transitions(job_id,sequence,expected_state,state,evidence)
    values(j.job_id,j.transition_sequence+1,p_expected_state,p_state,p_evidence);
  update civicpulse_delivery.build_jobs set state=p_state,transition_sequence=j.transition_sequence+1 where job_id=j.job_id;
  if p_state in ('failed','superseded') then
    update civicpulse_delivery.enrollment_state set active_job_id=null;
    if p_state='failed' then
      update civicpulse_delivery.build_counter set intervention_required=true,last_error=code,next_attempt_at=null;
    end if;
  end if;
  return jsonb_build_object('state',p_state);
end $$;
revoke all on function civicpulse_delivery.transition_build(uuid,uuid,bigint,text,text,jsonb) from public,anon,authenticated;
