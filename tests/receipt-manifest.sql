begin;
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.reject_manifest(doc jsonb,epoch uuid default 'aaaaaaaa-0000-4000-8000-000000000001',generation bigint default 1) returns void language plpgsql as $$
begin
  begin
    perform civicpulse_delivery.validate_receipt_manifest(doc,epoch,generation);
  exception when sqlstate '22023' then return; end;
  raise exception 'Unexpected structurally accepted fixture';
end $$;
create temporary table manifest_state_before as select
  (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.publication_state s) as publication,
  (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.pipeline_state s) as pipeline,
  (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.outbox s) as outbox;
do $$
declare base jsonb := '{"schema_version":1,"dataset_epoch":"aaaaaaaa-0000-4000-8000-000000000001","generation":"1","bootstrap_complete":true,"counts":{"organization":1,"calendar":0,"event":0,"layer":2,"map":0},"records":[{"kind":"layer","id":"__proto__","revision":"1"},{"kind":"layer","id":"event-locations","revision":"2"},{"kind":"organization","id":"__proto__","revision":"3"}],"layers":[{"id":"__proto__","revision":"1","mode":"stored","feature_count":0},{"id":"event-locations","revision":"2","mode":"events","feature_count":0}]}';
 epoch uuid := 'aaaaaaaa-0000-4000-8000-000000000001'; value jsonb; key text; doc jsonb;
begin
  perform civicpulse_delivery.validate_receipt_manifest(base,epoch,1);
  -- Numeric JSON lexical spelling is intentionally not constrained after JSONB parsing.
  perform civicpulse_delivery.validate_receipt_manifest(jsonb_set(jsonb_set(base,'{schema_version}','1.0'),'{counts,layer}','2e0'),epoch,1);
  perform civicpulse_delivery.validate_receipt_manifest(jsonb_set(base,'{layers,0,feature_count}','9007199254740991'),epoch,1);
  perform civicpulse_delivery.validate_receipt_manifest(jsonb_set(base,'{generation}','"9223372036854775807"'),epoch,9223372036854775807);
  perform civicpulse_delivery.validate_receipt_manifest(jsonb_set(base,'{generation}','"0"'),epoch,0);
  doc:=jsonb_set(jsonb_set(base,'{records,0,revision}','"9223372036854775807"'),'{layers,0,revision}','"9223372036854775807"');
  perform civicpulse_delivery.validate_receipt_manifest(doc,epoch,1);
  -- Special IDs are literal data. Same ID in different kinds is valid.
  doc:=jsonb_set(jsonb_set(base,'{records,0,id}','"[quote\"].é"'),'{layers,0,id}','"[quote\"].é"');
  perform civicpulse_delivery.validate_receipt_manifest(doc,epoch,1);
  perform pg_temp.reject_manifest(null);
  for value in select x from jsonb_array_elements('[null,true,1,"text",[]]') x loop perform pg_temp.reject_manifest(value); end loop;
  for key in select jsonb_object_keys(base) loop
    perform pg_temp.reject_manifest(base-key);
    perform pg_temp.reject_manifest(jsonb_set(base,array[key],'null'));
  end loop;
  perform pg_temp.reject_manifest(base||'{"approved":true}');
  perform pg_temp.reject_manifest(base||'{"source_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}');
  perform pg_temp.reject_manifest(base||'{"schema_version":2}');
  perform pg_temp.reject_manifest(base||'{"schema_version":"1"}');
  perform pg_temp.reject_manifest(base||'{"bootstrap_complete":false}');
  perform pg_temp.reject_manifest(base||'{"bootstrap_complete":"true"}');
  perform pg_temp.reject_manifest(base||'{"dataset_epoch":"AAAAAAAA-0000-4000-8000-000000000001"}');
  perform pg_temp.reject_manifest(base||'{"dataset_epoch":"not-a-uuid"}');
  perform pg_temp.reject_manifest(base,gen_random_uuid(),1);
  perform pg_temp.reject_manifest(base,null,1);
  perform pg_temp.reject_manifest(base,epoch,null);
  perform pg_temp.reject_manifest(base,epoch,-1);
  perform pg_temp.reject_manifest(base,epoch,2);
  for value in select x from jsonb_array_elements('[1,"01","-1","+1","1.0","1e0","9223372036854775808","999999999999999999999999","",true,null,{}]') x loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{generation}',value));
  end loop;
  for value in select x from jsonb_array_elements('[-1,0.1,9007199254740992,1e1000,"1",true,null,{},[]]') x loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{counts,organization}',value));
    perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0,feature_count}',value));
  end loop;
  perform pg_temp.reject_manifest(jsonb_set(base,'{counts}',(base->'counts')-'map'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{counts}',(base->'counts')||'{"unknown":0}'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{counts,event}','1'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{counts,layer}','1'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{records}',base->'records'||jsonb_build_array(base->'records'->2)));
  perform pg_temp.reject_manifest(jsonb_set(base,'{records}',jsonb_build_array(base->'records'->1,base->'records'->0,base->'records'->2)));
  for value in select x from jsonb_array_elements('[null,true,[],"tuple"]') x loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{records,0}',value));
    perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0}',value));
  end loop;
  foreach key in array array['kind','id','revision'] loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{records,0}',(base->'records'->0)-key));
    perform pg_temp.reject_manifest(jsonb_set(base,array['records','0',key],'null'));
  end loop;
  perform pg_temp.reject_manifest(jsonb_set(base,'{records,0}',(base->'records'->0)||'{"extra":0}'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{records,0,kind}','"unsupported"'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{records,0,id}','""'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{records,0,id}','123'));
  for value in select x from jsonb_array_elements('[0,1,"0","01","-1","+1","1.0","1e0","9223372036854775808","",true,null,{}]') x loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{records,0,revision}',value));
    perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0,revision}',value));
  end loop;
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers}','[]'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers}',jsonb_build_array(base->'layers'->0,base->'layers'->0)));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers}',jsonb_build_array(base->'layers'->1,base->'layers'->0)));
  foreach key in array array['id','revision','mode','feature_count'] loop
    perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0}',(base->'layers'->0)-key));
    perform pg_temp.reject_manifest(jsonb_set(base,array['layers','0',key],'null'));
  end loop;
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0}',(base->'layers'->0)||'{"extra":0}'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0,id}','"unknown"'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0,revision}','"2"'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers,0,mode}','"events"'));
  perform pg_temp.reject_manifest(jsonb_set(base,'{layers,1,mode}','"stored"'));
  doc:=base||'{"counts":{"organization":1,"calendar":0,"event":0,"layer":0,"map":0},"records":[{"kind":"organization","id":" ","revision":"1"}],"layers":[]}';
  perform civicpulse_delivery.validate_receipt_manifest(doc,epoch,1); -- nonempty means no trimming/renaming
  perform pg_temp.reject_manifest(base||'{"counts":{"organization":0,"calendar":0,"event":0,"layer":0,"map":0},"records":[],"layers":[]}');
end $$;
select pg_temp.assert((select publication is not distinct from (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.publication_state s)
  and pipeline is not distinct from (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.pipeline_state s)
  and outbox is not distinct from (select jsonb_agg(to_jsonb(s)) from civicpulse_delivery.outbox s)
  from manifest_state_before),'pure validation leaves publication, live and dispatch state unchanged');
select pg_temp.assert((select not prosecdef and provolatile='i' and proconfig=array['search_path=""']
  and pg_get_userbyid(proowner)='postgres' from pg_proc where oid='civicpulse_delivery.validate_receipt_manifest(jsonb,uuid,bigint)'::regprocedure), 'immutable invoker, empty path and local expected owner');
create role cp_manifest_dispatcher nologin;
create role cp_manifest_runner nologin;
create role cp_manifest_reconciler nologin;
create role cp_manifest_operator nologin;
grant usage on schema civicpulse_delivery to cp_manifest_dispatcher,cp_manifest_runner,cp_manifest_reconciler,cp_manifest_operator;
insert into civicpulse_delivery.machine_registry select rolname,oid,case rolname
  when 'cp_manifest_operator' then 'publication_operator' else replace(rolname,'cp_manifest_','') end,true,clock_timestamp()+interval '1 hour'
from pg_roles where rolname in ('cp_manifest_dispatcher','cp_manifest_runner','cp_manifest_reconciler','cp_manifest_operator');
create function pg_temp.helper_denied() returns void language plpgsql security invoker as $$
begin
  begin perform civicpulse_delivery.validate_receipt_manifest('{}',gen_random_uuid(),0);
  exception when insufficient_privilege then return; end;
  raise exception 'External helper EXECUTE unexpectedly permitted';
end $$;
set session authorization anon;
select pg_temp.helper_denied();
reset session authorization;
set session authorization authenticated;
select pg_temp.helper_denied();
reset session authorization;
set session authorization cp_manifest_dispatcher;
select pg_temp.helper_denied();
reset session authorization;
set session authorization cp_manifest_runner;
select pg_temp.helper_denied();
reset session authorization;
set session authorization cp_manifest_reconciler;
select pg_temp.helper_denied();
reset session authorization;
set session authorization cp_manifest_operator;
select pg_temp.helper_denied();
reset session authorization;
select pg_temp.assert(not exists(select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.oid='civicpulse_delivery.validate_receipt_manifest(jsonb,uuid,bigint)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'no PUBLIC execute');
rollback;
select 'Pure receipt manifest structure and external-grant checks passed' as result;
