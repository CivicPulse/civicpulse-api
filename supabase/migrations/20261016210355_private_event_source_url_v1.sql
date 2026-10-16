-- cp-source-url-v1: original bytes only, no normalization or network lookup.
create function civicpulse.valid_private_source_url(url text) returns boolean
language plpgsql immutable security invoker set search_path='' as $$
declare authority text; host text; port text; tail text; label text; octet text;
  labels text[]; position integer := 1; character text; triplet text;
begin
  if url is null or url collate "C" !~ '^https?://' or url collate "C" ~ '[^!-~]' or strpos(url,chr(92))>0 then return false; end if;
  authority := substring(url from '^https?://([^/?#]*)');
  if authority is null or authority='' then return false; end if;
  host := split_part(authority,':',1);
  if strpos(authority,':')>0 then
    port := substring(authority from ':(.*)$');
    if port collate "C" !~ '^[1-9][0-9]{0,4}$' then return false; end if;
    if port::integer>65535 then return false; end if;
  end if;
  labels := string_to_array(host,'.');
  if host collate "C" ~ '^[0-9.]+$' then
    if cardinality(labels)<>4 then return false; end if;
    foreach octet in array labels loop
      if octet collate "C" !~ '^(0|[1-9][0-9]{0,2})$' then return false; end if;
      if octet::integer>255 then return false; end if;
    end loop;
  else
    if octet_length(host)>253 or cardinality(labels)<2 then return false; end if;
    foreach label in array labels loop
      if octet_length(label)>63 or label collate "C" !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' or left(label,4)='xn--' then return false; end if;
    end loop;
    if labels[cardinality(labels)] collate "C" !~ '^[a-z]{2,63}$' then return false; end if;
  end if;
  tail := substring(url from length(substring(url from '^https?://'))+length(authority)+1);
  while position<=length(tail) loop
    character := substring(tail from position for 1);
    if character='%' then
      triplet := substring(tail from position+1 for 2);
      if triplet collate "C" !~ '^[0-9A-Fa-f]{2}$' then return false; end if;
      if upper(triplet) ~ '^(0[0-9A-F]|1[0-9A-F]|7F|5C)$' then return false; end if;
      position := position+3;
    else
      if character collate "C" !~ '^[A-Za-z0-9]$' and strpos($alphabet$-._~!$&'()*+,;=:@/?#[]$alphabet$,character)=0 then return false; end if;
      position := position+1;
    end if;
  end loop;
  return true;
end;
$$;
revoke all on function civicpulse.valid_private_source_url(text) from public,anon,authenticated;

create or replace function civicpulse.validate_private_event(doc jsonb) returns void
language plpgsql security invoker set search_path='' as $$
declare key text; value jsonb;
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
  if not civicpulse.valid_private_source_url(doc->>'sourceUrl') then
    raise exception 'sourceUrl must satisfy cp-source-url-v1' using errcode='22023';
  end if;
end;
$$;
revoke all on function civicpulse.validate_private_event(jsonb) from public,anon,authenticated;
