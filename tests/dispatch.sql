begin;
create function pg_temp.assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.denied(command text,expected text default '42501') returns void language plpgsql security invoker as $$
begin
  begin execute command; exception when others then
    if sqlstate=expected then return; end if;
    raise exception 'Unexpected SQLSTATE %, wanted %',sqlstate,expected;
  end;
  raise exception 'Expected rejection: %',command;
end $$;
select pg_temp.assert(civicpulse_delivery.parse_run_identity('1:1')='{"run_id":"1","run_attempt":"1"}'::jsonb,'minimum identity');
select pg_temp.assert(civicpulse_delivery.parse_run_identity('99999999999999999999:9999999999')->>'run_id'='99999999999999999999','large identity stays text');
do $$ declare value text; begin
  foreach value in array array[null,'','0:1','1:0','01:1','1:01','1','1:1:1','+1:1','1:-1','100000000000000000000:1','1:10000000000',' 1:1',E'1:1\n','1:1 '] loop
    perform pg_temp.denied(format('select civicpulse_delivery.parse_run_identity(%L)',value),'22023');
  end loop;
end $$;
create role cp_dispatch_one nologin;
create role cp_dispatch_two nologin;
create role cp_dispatch_runner nologin;
create role cp_dispatch_reconciler nologin;
create role cp_dispatch_operator nologin;
grant usage on schema civicpulse_delivery to cp_dispatch_one,cp_dispatch_two,cp_dispatch_runner,cp_dispatch_reconciler,cp_dispatch_operator;
grant execute on function civicpulse_delivery.claim_dispatch(text,integer),civicpulse_delivery.finish_dispatch(uuid,uuid,text,text,text)
  to cp_dispatch_one,cp_dispatch_two,cp_dispatch_runner,cp_dispatch_reconciler,cp_dispatch_operator;
insert into civicpulse_delivery.machine_registry
select rolname,oid,case rolname when 'cp_dispatch_runner' then 'runner' when 'cp_dispatch_reconciler' then 'reconciler' when 'cp_dispatch_operator' then 'publication_operator' else 'dispatcher' end,true,clock_timestamp()+interval '1 hour'
from pg_roles where rolname in ('cp_dispatch_one','cp_dispatch_two','cp_dispatch_runner','cp_dispatch_reconciler','cp_dispatch_operator');
create temporary table dispatch_receipts(label text primary key,body jsonb);
grant select,insert,update on dispatch_receipts to cp_dispatch_one,cp_dispatch_two;
set session authorization anon;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)');
reset session authorization;
set session authorization authenticated;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)');
reset session authorization;
set session authorization cp_dispatch_runner;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)');
reset session authorization;
set session authorization cp_dispatch_reconciler;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)');
reset session authorization;
set session authorization cp_dispatch_operator;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)');
reset session authorization;
set session authorization cp_dispatch_one;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)','55000');
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''BAD worker'',1)','22023');
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',101)','22023');
select pg_temp.denied('select * from civicpulse_delivery.outbox');
reset session authorization;
-- Owner setup only: no production resume/bootstrap/baseline function exists.
update civicpulse_delivery.pipeline_state set paused=false;
set session authorization cp_dispatch_one;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)','55000');
reset session authorization;
update civicpulse_delivery.publication_state set bootstrap_complete=true;
set session authorization cp_dispatch_one;
select pg_temp.denied('select civicpulse_delivery.claim_dispatch(''worker'',1)','55000');
reset session authorization;
update civicpulse_delivery.pipeline_state set approved_epoch=(select dataset_epoch from civicpulse_delivery.publication_state);
insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
select dataset_epoch,1,'publish','event','dispatch-fixture',1 from civicpulse_delivery.publication_state;
set session authorization cp_dispatch_one;
-- Subtransaction rollback restores the lease/counter.
do $$ begin
  begin
    perform civicpulse_delivery.claim_dispatch('rolled-back',1);
    raise exception 'rollback fixture';
  exception when raise_exception then null; end;
end $$;
insert into dispatch_receipts values('first',civicpulse_delivery.claim_dispatch('worker-1',1)->0);
select pg_temp.assert((select body->>'attempt'='1' from dispatch_receipts where label='first'),'rolled-back claim consumes no attempt');
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker-1',1)='[]'::jsonb,'leased event not reclaimed');
reset session authorization;
set session authorization cp_dispatch_two;
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker-2',1)='[]'::jsonb,'second session cannot duplicate lease');
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',null,null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='first'),'40001');
reset session authorization;
set session authorization cp_dispatch_one;
insert into dispatch_receipts values('ack', (select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'accepted',null,null) from dispatch_receipts where label='first'));
select pg_temp.assert((select body='{"accepted":true,"next_attempt_at":null}'::jsonb from dispatch_receipts where label='ack'),'wake-up accepted without invented run');
reset session authorization;
update civicpulse_delivery.outbox set lease_expires_at=clock_timestamp()-interval '1 hour';
set session authorization cp_dispatch_one;
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'accepted',null,null) from dispatch_receipts where label='first')=(select body from dispatch_receipts where label='ack'),'exact accepted ack replay after expiry');
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',''1:2'',null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='first'),'40001');
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=false where role_name='cp_dispatch_one';
set session authorization cp_dispatch_one;
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',null,null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='first'));
reset session authorization;
update civicpulse_delivery.machine_registry set enabled=true,expires_at=clock_timestamp()-interval '1 second' where role_name='cp_dispatch_one';
set session authorization cp_dispatch_one;
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',null,null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='first'));
reset session authorization;
update civicpulse_delivery.machine_registry set expires_at=clock_timestamp()+interval '1 hour' where role_name='cp_dispatch_one';
insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
select dataset_epoch,2,'withdraw','event','retry-fixture',1 from civicpulse_delivery.publication_state;

set session authorization cp_dispatch_one;
insert into dispatch_receipts values('retry1',civicpulse_delivery.claim_dispatch('retry-worker',1)->0);
select pg_temp.assert((select body->>'attempt'='1' from dispatch_receipts where label='retry1'),'retry attempt 1');
insert into dispatch_receipts values('retryack1',(select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry1'));
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry1')=(select body from dispatch_receipts where label='retryack1'),'retry ack preserves persisted jitter');
reset session authorization;
select pg_temp.assert((select next_attempt_at>clock_timestamp()+interval '28 seconds' and next_attempt_at<=clock_timestamp()+interval '37.0 seconds' from civicpulse_delivery.outbox where id='retry-fixture'),'persisted retry jitter 1');
update civicpulse_delivery.outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id='retry-fixture';

set session authorization cp_dispatch_one;
insert into dispatch_receipts values('retry2',civicpulse_delivery.claim_dispatch('retry-worker',1)->0);
select pg_temp.assert((select body->>'attempt'='2' from dispatch_receipts where label='retry2'),'retry attempt 2');
insert into dispatch_receipts values('retryack2',(select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry2'));
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry2')=(select body from dispatch_receipts where label='retryack2'),'retry ack preserves persisted jitter');
reset session authorization;
select pg_temp.assert((select next_attempt_at>clock_timestamp()+interval '118 seconds' and next_attempt_at<=clock_timestamp()+interval '145.0 seconds' from civicpulse_delivery.outbox where id='retry-fixture'),'persisted retry jitter 2');
update civicpulse_delivery.outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id='retry-fixture';

set session authorization cp_dispatch_one;
insert into dispatch_receipts values('retry3',civicpulse_delivery.claim_dispatch('retry-worker',1)->0);
select pg_temp.assert((select body->>'attempt'='3' from dispatch_receipts where label='retry3'),'retry attempt 3');
insert into dispatch_receipts values('retryack3',(select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry3'));
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry3')=(select body from dispatch_receipts where label='retryack3'),'retry ack preserves persisted jitter');
reset session authorization;
select pg_temp.assert((select next_attempt_at>clock_timestamp()+interval '598 seconds' and next_attempt_at<=clock_timestamp()+interval '721.0 seconds' from civicpulse_delivery.outbox where id='retry-fixture'),'persisted retry jitter 3');
update civicpulse_delivery.outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id='retry-fixture';

set session authorization cp_dispatch_one;
insert into dispatch_receipts values('retry4',civicpulse_delivery.claim_dispatch('retry-worker',1)->0);
select pg_temp.assert((select body->>'attempt'='4' from dispatch_receipts where label='retry4'),'retry attempt 4');
insert into dispatch_receipts values('retryack4',(select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry4'));
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry4')=(select body from dispatch_receipts where label='retryack4'),'retry ack preserves persisted jitter');
reset session authorization;
select pg_temp.assert((select next_attempt_at>clock_timestamp()+interval '3598 seconds' and next_attempt_at<=clock_timestamp()+interval '4321.0 seconds' from civicpulse_delivery.outbox where id='retry-fixture'),'persisted retry jitter 4');
update civicpulse_delivery.outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id='retry-fixture';

set session authorization cp_dispatch_one;
insert into dispatch_receipts values('retry5',civicpulse_delivery.claim_dispatch('retry-worker',1)->0);
select pg_temp.assert((select body->>'attempt'='5' from dispatch_receipts where label='retry5'),'retry attempt 5');
insert into dispatch_receipts values('retryack5',(select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry5'));
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'retry',null,'dispatch_timeout') from dispatch_receipts where label='retry5')=(select body from dispatch_receipts where label='retryack5'),'retry ack preserves persisted jitter');
reset session authorization;

select pg_temp.assert((select dispatch_state='failed' and next_attempt_at is null and dispatch_attempts=5 from civicpulse_delivery.outbox where id='retry-fixture'),'fifth failure requires intervention');
set session authorization cp_dispatch_one;
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker',1)='[]'::jsonb,'no sixth automatic attempt');
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''retry'',null,''dispatch_timeout'')',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='retry1'),'40001');
reset session authorization;
insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
select dataset_epoch,3,'publish','event','expiry-fixture',1 from civicpulse_delivery.publication_state;
set session authorization cp_dispatch_one;
insert into dispatch_receipts values('expired',civicpulse_delivery.claim_dispatch('worker',1)->0);
reset session authorization;
update civicpulse_delivery.outbox set lease_expires_at=clock_timestamp()-interval '1 second',dispatch_attempts=5 where id='expiry-fixture';
set session authorization cp_dispatch_one;
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',null,null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='expired'),'40001');
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker',1)='[]'::jsonb,'expired fifth attempt intervention');
reset session authorization;
select pg_temp.assert((select dispatch_state='failed' and error_code='lease_expired' from civicpulse_delivery.outbox where id='expiry-fixture'),'expiry classified internally');
-- Permanent errors stop immediately; malformed acknowledgements consume nothing.
insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
select dataset_epoch,4,'publish','event','permanent-fixture',1 from civicpulse_delivery.publication_state;
set session authorization cp_dispatch_one;
insert into dispatch_receipts values('permanent',civicpulse_delivery.claim_dispatch('worker',1)->0);
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',''1:01'',null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='permanent'),'22023');
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''retry'',null,''lease_expired'')',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='permanent'),'22023');
select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'failed',null,'dispatch_unauthorized') from dispatch_receipts where label='permanent';
reset session authorization;
select pg_temp.assert((select dispatch_state='failed' and dispatch_attempts=1 and next_attempt_at is null from civicpulse_delivery.outbox where id='permanent-fixture'),'permanent error immediate intervention');
-- Expiry is counted once and imposes a persisted retry delay.
insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
select dataset_epoch,5,'publish','event','single-expiry-fixture',1 from civicpulse_delivery.publication_state;
set session authorization cp_dispatch_one;
insert into dispatch_receipts values('single-expiry',civicpulse_delivery.claim_dispatch('worker',1)->0);
reset session authorization;
update civicpulse_delivery.outbox set lease_expires_at=clock_timestamp()-interval '1 second' where id='single-expiry-fixture';
set session authorization cp_dispatch_one;
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker',1)='[]'::jsonb,'expiry backoff, no immediate redispatch');
select pg_temp.assert(civicpulse_delivery.claim_dispatch('worker',1)='[]'::jsonb,'repeat expiry sweep does not re-count');
reset session authorization;
select pg_temp.assert((select dispatch_attempts=1 and dispatch_state='retry' from civicpulse_delivery.outbox where id='single-expiry-fixture'),'one expired attempt counted once');
update civicpulse_delivery.outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id='single-expiry-fixture';
set session authorization cp_dispatch_one;
insert into dispatch_receipts values('second-expiry',civicpulse_delivery.claim_dispatch('worker',1)->0);
select pg_temp.assert((select body->>'attempt'='2' from dispatch_receipts where label='second-expiry'),'new claim is second attempt');
select pg_temp.assert((select civicpulse_delivery.finish_dispatch((body->'event'->>'event_id')::uuid,(body->>'dispatch_lease_id')::uuid,'accepted','99999999999999999999:9999999999',null)->>'accepted'='true' from dispatch_receipts where label='second-expiry'),'accepted canonical large run identity');
reset session authorization;
-- A reused registered role name with a new OID cannot replay its old acknowledgement.
revoke execute on function civicpulse_delivery.claim_dispatch(text,integer),civicpulse_delivery.finish_dispatch(uuid,uuid,text,text,text) from cp_dispatch_one;
revoke usage on schema civicpulse_delivery from cp_dispatch_one;
revoke select,insert,update on dispatch_receipts from cp_dispatch_one;
drop role cp_dispatch_one;
create role cp_dispatch_one nologin;
grant usage on schema civicpulse_delivery to cp_dispatch_one;
grant execute on function civicpulse_delivery.claim_dispatch(text,integer),civicpulse_delivery.finish_dispatch(uuid,uuid,text,text,text) to cp_dispatch_one;
grant select on dispatch_receipts to cp_dispatch_one;
-- Explicit new registration is valid but it does not acquire the old lease identity.
update civicpulse_delivery.machine_registry set role_oid='cp_dispatch_one'::regrole::oid where role_name='cp_dispatch_one';
set session authorization cp_dispatch_one;
select pg_temp.denied((select format('select civicpulse_delivery.finish_dispatch(%L,%L,''accepted'',null,null)',body->'event'->>'event_id',body->>'dispatch_lease_id') from dispatch_receipts where label='first'),'40001');
reset session authorization;
rollback;
select 'Dispatch lease/ack real-session checks passed' as result;
