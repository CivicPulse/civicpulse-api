-- LOCAL ONLY. Reject before the v1 validator/mutations, never silently redact.
create function civicpulse.validate_private_event(doc jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare key text; value jsonb; authority text; host text; port text;
  placeholder constant text := 'Private location — see organizer for details';
  allowed constant text[] := array['id','title','start','end','category','location','address','description','note','sample',
    'sourceUrl','sourceChecked','organizer','sourceLabel','sourceGroup','sourceEventId','sourceCalendar',
    'organizationId','calendarIds','allDay','endTimeUnknown','isVirtual','addressPrivate','coordinates'];
  booleans constant text[] := array['sample','allDay','endTimeUnknown','isVirtual','addressPrivate'];
begin
  if doc ? 'addressPrivate' and jsonb_typeof(doc->'addressPrivate') <> 'boolean' then
    raise exception 'addressPrivate must be a boolean' using errcode='22023';
  end if;
  if doc->'addressPrivate' is distinct from 'true'::jsonb then return; end if;
  for key,value in select * from jsonb_each(doc) loop
    if not (key=any(allowed)) then
      raise exception 'Private event contains unsupported structured fields' using errcode='22023';
    elsif key='coordinates' then
      if value <> 'null'::jsonb then
        raise exception 'Private event coordinates must be absent or null' using errcode='22023';
      end if;
    elsif key='calendarIds' then
      if jsonb_typeof(value) <> 'array' then raise exception 'calendarIds must be an array of strings' using errcode='22023'; end if;
      if jsonb_array_length(value)=0 or exists(select 1 from jsonb_array_elements(value) item where jsonb_typeof(item)<>'string') then
        raise exception 'calendarIds must be a nonempty array of strings' using errcode='22023';
      end if;
    elsif key=any(booleans) then
      if jsonb_typeof(value)<>'boolean' then raise exception 'Private event boolean field has incorrect type' using errcode='22023'; end if;
    elsif jsonb_typeof(value)<>'string' then
      raise exception 'Private event public text fields must be strings' using errcode='22023';
    end if;
  end loop;
  if doc->>'address' is distinct from placeholder or doc->>'location' is distinct from placeholder then
    raise exception 'Private event address and location must use the canonical public placeholder' using errcode='22023';
  end if;
  -- URL authority is parsed separately from path/query/fragment. Public prose and
  -- source links remain editorial responsibility; this is not arbitrary PII detection.
  if not (doc ? 'sourceUrl') or doc->>'sourceUrl' ~ '[[:space:][:cntrl:]\\]' then
    raise exception 'sourceUrl must be a public HTTP(S) URL without whitespace or controls' using errcode='22023';
  end if;
  authority := substring(doc->>'sourceUrl' from '(?i)^https?://([^/?#]+)');
  if authority is null or authority ~ '[@%]' then
    raise exception 'sourceUrl requires a host and forbids userinfo or encoded authority' using errcode='22023';
  end if;
  if left(authority,1)='[' then
    if authority !~ '^\[[0-9A-Fa-f:.]+\](:[0-9]{1,5})?$' then
      raise exception 'sourceUrl has invalid host or port' using errcode='22023';
    end if;
    host := substring(authority from '^\[([^]]+)\]');
    begin
      if family(host::inet)<>6 then raise exception 'invalid address'; end if;
    exception when others then raise exception 'sourceUrl has invalid IPv6 host' using errcode='22023'; end;
    port := substring(authority from '\]:([0-9]+)$');
  else
    if authority !~ '^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)*[.]?(:[0-9]{1,5})?$' then
      raise exception 'sourceUrl has invalid host or port' using errcode='22023';
    end if;
    port := substring(authority from ':([0-9]+)$');
  end if;
  if port is not null and port::integer>65535 then
    raise exception 'sourceUrl has invalid port' using errcode='22023';
  end if;
end;
$$;
revoke all on function civicpulse.validate_private_event(jsonb) from public,anon,authenticated;
alter function civicpulse.validate_publication(text,jsonb) rename to validate_publication_v1;
create function civicpulse.validate_publication(p_kind text,doc jsonb) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if p_kind='event' then perform civicpulse.validate_private_event(doc); end if;
  perform civicpulse.validate_publication_v1(p_kind,doc);
end;
$$;
revoke all on function civicpulse.validate_publication(text,jsonb) from public,anon,authenticated;
