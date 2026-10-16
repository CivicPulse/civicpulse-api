-- One backend connection warms publish's pre-migration function call plan.
-- Entire fixture and guard DDL roll back; runner then applies guards afresh.
begin;
insert into auth.users values ('00000000-0000-4000-8000-000000000031');
insert into civicpulse.members values ('00000000-0000-4000-8000-000000000031','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
prepare warmed_publish(text,text,bigint) as select public.publish($1,$2,$3);
select public.save_draft('organization','mvp-warm-org','{"id":"mvp-warm-org","name":"Synthetic warm plan"}',0);
execute warmed_publish('organization','mvp-warm-org',1);
reset role;
-- APPLY_REVIEWED_GUARDS
do $$ declare row record; begin
  for row in select p.oid,p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) owner from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='civicpulse' and p.proname in ('validate_publication','validate_publication_v1','validate_private_event','valid_private_source_url') loop
    if row.prosecdef or row.owner<>'postgres' or row.proconfig is distinct from array['search_path=""']::text[]
      or has_function_privilege('anon',row.oid,'execute') or has_function_privilege('authenticated',row.oid,'execute')
      or exists(select 1 from aclexplode(coalesce((select proacl from pg_proc where oid=row.oid),acldefault('f',(select proowner from pg_proc where oid=row.oid)))) where grantee=0 and privilege_type='EXECUTE')
      then raise exception 'Unexpected validator security catalog'; end if;
  end loop;
end $$;
set local role authenticated;
select public.save_draft('calendar','mvp-warm-cal','{"id":"mvp-warm-cal","name":"Synthetic calendar","organizationId":"mvp-warm-org"}',0);
execute warmed_publish('calendar','mvp-warm-cal',1);
select public.save_draft('event','mvp-warm-event','{"id":"mvp-warm-event","title":"Synthetic privacy rejection","start":"2026-10-16T12:00:00-04:00","end":"2026-10-16T13:00:00-04:00","category":"Community","location":"SENTINEL private location","address":"SENTINEL private address","addressPrivate":true,"sample":false,"sourceUrl":"https://example.org/test","sourceChecked":"2026-10-16","organizationId":"mvp-warm-org","calendarIds":["mvp-warm-cal"]}',0);
do $$ begin
  begin execute 'execute warmed_publish(''event'',''mvp-warm-event'',1)';
    raise exception 'Warmed plan bypassed private validator';
  exception when sqlstate '22023' then null; end;
  if exists(select 1 from public.content where kind='event' and id='mvp-warm-event') then raise exception 'Rejected event became public'; end if;
end $$;
reset role;
deallocate warmed_publish;
rollback;
select 'Warm pre-migration publish plan rejected unsafe private event; validator ACL/search_path passed' as result;
