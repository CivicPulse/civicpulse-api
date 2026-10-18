-- Synthetic analogue only. Never reads/copies the three hosted QA identities.
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
insert into auth.users values ('00000000-0000-4000-8000-000000000051');
insert into civicpulse.members(user_id,role) values ('00000000-0000-4000-8000-000000000051','admin');
set session authorization authenticated;
set "request.jwt.claim.sub"='00000000-0000-4000-8000-000000000051';
select public.save_draft('organization','upgrade-org','{"id":"upgrade-org","name":"Upgrade organization"}',0);
select public.publish('organization','upgrade-org',1);
select public.save_draft('calendar','upgrade-cal','{"id":"upgrade-cal","name":"Upgrade calendar","organizationId":"upgrade-org"}',0);
select public.publish('calendar','upgrade-cal',1);
select public.save_draft('event','upgrade-event','{"id":"upgrade-event","title":"Upgrade private event","start":"2026-11-01T12:00:00-05:00","end":"2026-11-01T13:00:00-05:00","category":"Community","location":"Private location — see organizer for details","address":"Private location — see organizer for details","addressPrivate":true,"sample":false,"sourceUrl":"https://example.org/upgrade","sourceChecked":"2026-10-17","organizationId":"upgrade-org","calendarIds":["upgrade-cal"]}',0);
select public.publish('event','upgrade-event',1);
do $$ begin for revision in 1..4 loop
  perform public.save_draft('event','upgrade-event',(select payload from public.cms_drafts where kind='event' and id='upgrade-event'),revision);
end loop; end $$;
prepare warmed_publish as select public.publish('organization','upgrade-org',1);
begin; execute warmed_publish; rollback;
reset session authorization;
create function pg_temp.snapshot() returns jsonb language sql as $$
select jsonb_build_object(
  'drafts',(select jsonb_agg(to_jsonb(t) order by kind,id) from civicpulse.drafts t),
  'published',(select jsonb_agg(to_jsonb(t) order by kind,id) from civicpulse.published t),
  'history',(select jsonb_agg(to_jsonb(t) order by sequence) from civicpulse.history t),
  'features',(select jsonb_agg(to_jsonb(t) order by kind,id,ordinal) from civicpulse.features t),
  'members',(select jsonb_agg(to_jsonb(t) order by user_id) from civicpulse.members t)); $$;
create temporary table preserved as select pg_temp.snapshot() as value;
-- APPLY_FOUNDATION_UPGRADE
select pg_temp.assert(pg_temp.snapshot()=(select value from preserved),'all existing content/drafts/history/features/members unchanged');
select pg_temp.assert((select count(*)=3 from public.content),'existing public inventory retained');
select pg_temp.assert((select count(*)=10 from civicpulse.history),'existing history retained');
select pg_temp.assert((select count(*)=0 from civicpulse_delivery.outbox),'no invented historical delivery intent');
select pg_temp.assert(public.publication_manifest()->>'generation'='0','new epoch starts at generation zero');
select pg_temp.assert(public.publication_manifest()->>'bootstrap_complete'='false','upgrade is unbootstrapped');
select pg_temp.assert(jsonb_array_length(public.publication_manifest()->'records')=3,'manifest inventories preexisting publications');
select pg_temp.assert((select paused and approved_epoch is null and not live_inventory_complete from civicpulse_delivery.pipeline_state),'no source/baseline/live authority');
begin;
set session authorization authenticated;
execute warmed_publish;
select pg_temp.assert(public.publication_manifest()->>'generation'='1','warmed original RPC enters new transactional generation trigger');
select pg_temp.assert(public.cms_publication_status()->>'state' is null,'no invented job state');
select pg_temp.assert(public.cms_record_publication_status('event','upgrade-event')->>'website_state'='unknown','no invented live receipt');
reset session authorization;
select pg_temp.assert((select count(*)=1 from civicpulse_delivery.outbox),'warmed RPC adds one outbox event');
rollback;
select pg_temp.assert(pg_temp.snapshot()=(select value from preserved),'test publication rollback restores full prior state');
select pg_temp.assert(public.publication_manifest()->>'generation'='0','test rollback restores generation');
select 'Hosted-baseline to local-foundation upgrade and warmed publication passed (no source/job/live authority)' as result;
