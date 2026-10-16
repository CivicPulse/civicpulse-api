-- Structure + supplied context ONLY: no current-state, authenticity or live authority.
create function civicpulse_delivery.validate_receipt_manifest(
  p_manifest jsonb,p_expected_epoch uuid,p_expected_generation bigint
) returns void language plpgsql immutable security invoker set search_path='' as $$
declare item jsonb; kind text; identifier text; revision text; counter text; value numeric;
  previous_kind text; previous_id text; layer_revisions jsonb := '{}';
  actual_counts jsonb := '{"organization":0,"calendar":0,"event":0,"layer":0,"map":0}';
  kinds constant text[] := array['organization','calendar','event','layer','map'];
begin
  if p_expected_epoch is null or p_expected_generation is null or p_expected_generation<0 then
    raise exception 'Expected epoch and nonnegative generation required' using errcode='22023';
  end if;
  if p_manifest is null or jsonb_typeof(p_manifest)<>'object' then
    raise exception 'Manifest must be an object' using errcode='22023';
  end if;
  if not (p_manifest ?& array['schema_version','dataset_epoch','generation','bootstrap_complete','counts','records','layers'])
    or (select count(*) from jsonb_object_keys(p_manifest))<>7 then
    raise exception 'Manifest keys must match schema 1 exactly' using errcode='22023';
  end if;
  if jsonb_typeof(p_manifest->'schema_version')<>'number' or p_manifest->'schema_version'<>'1'::jsonb
    or p_manifest->'bootstrap_complete'<>'true'::jsonb then
    raise exception 'Manifest requires schema 1 and completed bootstrap' using errcode='22023';
  end if;
  if jsonb_typeof(p_manifest->'dataset_epoch')<>'string' or p_manifest->>'dataset_epoch'<>p_expected_epoch::text then
    raise exception 'Manifest epoch must match canonical expected UUID' using errcode='22023';
  end if;
  counter := p_manifest->>'generation';
  if jsonb_typeof(p_manifest->'generation')<>'string' or length(counter)>19 or counter collate "C" !~ '^(0|[1-9][0-9]*)$' then
    raise exception 'Manifest generation must be canonical decimal text' using errcode='22023';
  end if;
  if counter::numeric>9223372036854775807 or counter::numeric<>p_expected_generation then
    raise exception 'Manifest generation must match expected int8 value' using errcode='22023';
  end if;
  if jsonb_typeof(p_manifest->'counts')<>'object' or jsonb_typeof(p_manifest->'records')<>'array' or jsonb_typeof(p_manifest->'layers')<>'array' then
    raise exception 'Manifest inventory types are invalid' using errcode='22023';
  end if;
  if not (p_manifest->'counts' ?& kinds) or (select count(*) from jsonb_object_keys(p_manifest->'counts'))<>5 then
    raise exception 'Manifest requires exactly five kind counts' using errcode='22023';
  end if;
  foreach kind in array kinds loop
    if jsonb_typeof(p_manifest->'counts'->kind)<>'number' then
      raise exception 'Manifest counts must be safe nonnegative integral numbers' using errcode='22023';
    end if;
    value := (p_manifest->'counts'->>kind)::numeric;
    if value<0 or value>9007199254740991 or trunc(value)<>value then
      raise exception 'Manifest counts must be safe nonnegative integral numbers' using errcode='22023';
    end if;
  end loop;
  if jsonb_array_length(p_manifest->'records')=0 then
    raise exception 'All-empty release requires separately authorized approval' using errcode='22023';
  end if;
  for item in select element from jsonb_array_elements(p_manifest->'records') element loop
    if jsonb_typeof(item)<>'object' then raise exception 'Record tuple must be an object' using errcode='22023'; end if;
    if not (item ?& array['kind','id','revision']) or (select count(*) from jsonb_object_keys(item))<>3 then
      raise exception 'Record tuple keys must match exactly' using errcode='22023';
    end if;
    kind := item->>'kind'; identifier := item->>'id'; revision := item->>'revision';
    if jsonb_typeof(item->'kind')<>'string' or not (kind=any(kinds)) or jsonb_typeof(item->'id')<>'string' or length(identifier)=0 then
      raise exception 'Record kind or ID is invalid' using errcode='22023';
    end if;
    if jsonb_typeof(item->'revision')<>'string' or length(revision)>19 or revision collate "C" !~ '^[1-9][0-9]*$' then
      raise exception 'Record revision must be canonical positive int8 text' using errcode='22023';
    end if;
    if revision::numeric>9223372036854775807 then raise exception 'Record revision exceeds int8' using errcode='22023'; end if;
    if previous_kind is not null and row(kind collate "C",identifier collate "C")<=row(previous_kind collate "C",previous_id collate "C") then
      raise exception 'Records must be unique and sorted by C kind and ID' using errcode='22023';
    end if;
    previous_kind := kind; previous_id := identifier;
    actual_counts := jsonb_set(actual_counts,array[kind],to_jsonb((actual_counts->>kind)::bigint+1));
    if kind='layer' then layer_revisions := jsonb_set(layer_revisions,array[identifier],to_jsonb(revision)); end if;
  end loop;
  if actual_counts<>p_manifest->'counts' then raise exception 'Manifest counts must equal record inventory' using errcode='22023'; end if;
  if jsonb_array_length(p_manifest->'layers')<>(actual_counts->>'layer')::bigint then
    raise exception 'Layer inventory must exhaust layer records' using errcode='22023';
  end if;
  previous_id := null;
  for item in select element from jsonb_array_elements(p_manifest->'layers') element loop
    if jsonb_typeof(item)<>'object' then raise exception 'Layer tuple must be an object' using errcode='22023'; end if;
    if not (item ?& array['id','revision','mode','feature_count']) or (select count(*) from jsonb_object_keys(item))<>4 then
      raise exception 'Layer tuple keys must match exactly' using errcode='22023';
    end if;
    identifier := item->>'id';
    if jsonb_typeof(item->'id')<>'string' or length(identifier)=0 or jsonb_typeof(item->'revision')<>'string'
      or item->'revision' is distinct from layer_revisions->identifier then
      raise exception 'Layer ID and revision must match a layer record' using errcode='22023';
    end if;
    if previous_id is not null and identifier collate "C"<=previous_id collate "C" then
      raise exception 'Layers must be unique and sorted by C ID' using errcode='22023';
    end if;
    previous_id := identifier;
    if item->'mode' is distinct from to_jsonb(case when identifier='event-locations' then 'events'::text else 'stored'::text end) then
      raise exception 'Layer mode does not match M2a layer identity' using errcode='22023';
    end if;
    if jsonb_typeof(item->'feature_count')<>'number' then
      raise exception 'Layer feature count must be a safe nonnegative integral number' using errcode='22023';
    end if;
    value := (item->>'feature_count')::numeric;
    if value<0 or value>9007199254740991 or trunc(value)<>value then
      raise exception 'Layer feature count must be a safe nonnegative integral number' using errcode='22023';
    end if;
  end loop;
end;
$$;
revoke all on function civicpulse_delivery.validate_receipt_manifest(jsonb,uuid,bigint) from public,anon,authenticated;
