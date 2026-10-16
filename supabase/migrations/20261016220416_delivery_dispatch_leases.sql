-- LOCAL ONLY. Canonical GitHub identity is text, never a JSON/JavaScript number.
create function civicpulse_delivery.parse_run_identity(p_run_id text) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
begin
  if p_run_id is null or p_run_id collate "C" !~ '^[1-9][0-9]{0,19}:[1-9][0-9]{0,9}$' then
    raise exception 'Canonical run_id:attempt required' using errcode='22023';
  end if;
  return jsonb_build_object('run_id',split_part(p_run_id,':',1),'run_attempt',split_part(p_run_id,':',2));
end;
$$;
revoke all on function civicpulse_delivery.parse_run_identity(text) from public,anon,authenticated;

alter table civicpulse_delivery.outbox
  add column lease_role_name name,
  add column lease_role_oid oid,
  add column ack_outcome text,
  add column ack_run_id text,
  add column ack_error_code text,
  add column ack_result jsonb;

create function civicpulse_delivery.dispatch_retry_at(p_attempt integer) returns timestamptz
language sql volatile security invoker set search_path='' as $$
  select clock_timestamp()+make_interval(secs =>
    (case p_attempt when 1 then 30 when 2 then 120 when 3 then 600 else 3600 end)*(1+random()*0.2));
$$;
revoke all on function civicpulse_delivery.dispatch_retry_at(integer) from public,anon,authenticated;

create function civicpulse_delivery.claim_dispatch(p_worker_id text,p_limit integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s civicpulse_delivery.publication_state%rowtype; p civicpulse_delivery.pipeline_state%rowtype;
  event civicpulse_delivery.outbox%rowtype; result jsonb := '[]'; caller_oid oid; observed timestamptz;
begin
  perform civicpulse_delivery.require_machine('dispatcher');
  if p_worker_id is null or p_worker_id collate "C" !~ '^[a-z0-9][a-z0-9._:-]{0,127}$' or p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'Valid worker identifier and batch limit 1..100 required' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(728361904);
  perform civicpulse_delivery.require_machine('dispatcher');
  select * into strict s from civicpulse_delivery.publication_state where singleton;
  select * into strict p from civicpulse_delivery.pipeline_state where singleton;
  if p.paused or not s.bootstrap_complete or p.approved_epoch is distinct from s.dataset_epoch then
    raise exception 'Dispatch requires approved active publication epoch' using errcode='55000';
  end if;
  select oid into strict caller_oid from pg_catalog.pg_roles where rolname=session_user;
  observed := clock_timestamp();
  -- Expiry is a failed delivery attempt, never evidence of successful dispatch.
  update civicpulse_delivery.outbox set
    dispatch_state=case when dispatch_attempts>=5 then 'failed' else 'retry' end,
    error_code='lease_expired',next_attempt_at=case when dispatch_attempts>=5 then null else civicpulse_delivery.dispatch_retry_at(dispatch_attempts) end
    where dataset_epoch=s.dataset_epoch and dispatch_state='leased' and lease_expires_at<=observed;
  for event in select * from civicpulse_delivery.outbox
    where dataset_epoch=s.dataset_epoch and dispatch_state in ('pending','retry') and dispatch_attempts<5
      and (next_attempt_at is null or next_attempt_at<=observed)
    order by generation for update limit p_limit
  loop
    update civicpulse_delivery.outbox set dispatch_state='leased',dispatch_attempts=dispatch_attempts+1,
      dispatch_lease_id=gen_random_uuid(),lease_expires_at=clock_timestamp()+interval '2 minutes',
      worker_id=p_worker_id,lease_role_name=session_user,lease_role_oid=caller_oid,
      next_attempt_at=null,ack_outcome=null,ack_run_id=null,ack_error_code=null,ack_result=null
      where event_id=event.event_id returning * into event;
    result := result||jsonb_build_array(jsonb_build_object(
      'event',jsonb_build_object('schema_version',event.schema_version,'event_id',event.event_id,
        'dataset_epoch',event.dataset_epoch,'generation',event.generation::text,'action',event.action,
        'kind',event.kind,'id',event.id,'revision',event.revision::text,'occurred_at',event.occurred_at),
      'dispatch_lease_id',event.dispatch_lease_id,'lease_expires_at',event.lease_expires_at,'attempt',event.dispatch_attempts));
  end loop;
  return result;
end;
$$;
revoke all on function civicpulse_delivery.claim_dispatch(text,integer) from public,anon,authenticated;

create function civicpulse_delivery.finish_dispatch(p_event_id uuid,p_dispatch_lease_id uuid,p_outcome text,p_run_id text,p_error_code text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare event civicpulse_delivery.outbox%rowtype; result jsonb; retry_at timestamptz; caller_oid oid;
begin
  perform civicpulse_delivery.require_machine('dispatcher');
  if p_outcome is null or p_outcome not in ('accepted','retry','failed') then
    raise exception 'Valid dispatch outcome required' using errcode='22023';
  end if;
  if p_outcome='accepted' then
    if p_error_code is not null then raise exception 'Accepted dispatch cannot have an error' using errcode='22023'; end if;
    if p_run_id is not null then perform civicpulse_delivery.parse_run_identity(p_run_id); end if;
  elsif p_run_id is not null or p_error_code is null or
    (p_outcome='retry' and p_error_code not in ('dispatch_timeout','dispatch_unavailable','dispatch_rate_limited')) or
    (p_outcome='failed' and p_error_code not in ('dispatch_unauthorized','dispatch_invalid_request','dispatch_configuration')) then
    raise exception 'Valid dispatch error code required, without run identity' using errcode='22023';
  end if;
  select oid into strict caller_oid from pg_catalog.pg_roles where rolname=session_user;
  select * into event from civicpulse_delivery.outbox where event_id=p_event_id for update;
  if not found then raise exception 'Stale dispatch lease' using errcode='40001'; end if;
  perform civicpulse_delivery.require_machine('dispatcher');
  if event.dispatch_lease_id is distinct from p_dispatch_lease_id or p_dispatch_lease_id is null
    or event.lease_role_name is distinct from session_user or event.lease_role_oid is distinct from caller_oid then
    raise exception 'Stale dispatch lease' using errcode='40001';
  end if;
  -- Exact saved acknowledgements remain replayable after time passes, but only
  -- with the original valid registered caller and the unreplaced lease token.
  if event.ack_result is not null then
    if event.ack_outcome=p_outcome and event.ack_run_id is not distinct from p_run_id and event.ack_error_code is not distinct from p_error_code then
      return event.ack_result;
    end if;
    raise exception 'Dispatch acknowledgement conflict' using errcode='40001';
  end if;
  if event.dispatch_state<>'leased' or event.lease_expires_at<=clock_timestamp() then
    raise exception 'Expired dispatch lease' using errcode='40001';
  end if;
  if p_outcome='retry' and event.dispatch_attempts<5 then
    retry_at := civicpulse_delivery.dispatch_retry_at(event.dispatch_attempts);
  end if;
  result := jsonb_build_object('accepted',p_outcome='accepted','next_attempt_at',retry_at);
  update civicpulse_delivery.outbox set
    dispatch_state=case when p_outcome='accepted' then 'accepted' when retry_at is not null then 'retry' else 'failed' end,
    next_attempt_at=retry_at,run_id=p_run_id,error_code=p_error_code,
    ack_outcome=p_outcome,ack_run_id=p_run_id,ack_error_code=p_error_code,ack_result=result
    where event_id=p_event_id;
  return result;
end;
$$;
revoke all on function civicpulse_delivery.finish_dispatch(uuid,uuid,text,text,text) from public,anon,authenticated;
-- No real machine roles or grants: provisioning remains separately authorized.
