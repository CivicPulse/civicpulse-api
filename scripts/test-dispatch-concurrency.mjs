import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

/** Disposable harness only: two separate backend sessions with real identities. */
export async function testDispatchConcurrency(command, container, database) {
  const names = [`${database}_a`, `${database}_b`];
  const psql = ['exec','-i',container,'psql','-q','-X','-A','-t','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'];
  command(psql, `
    create role ${names[0]} nologin; create role ${names[1]} nologin;
    grant usage on schema civicpulse_delivery to ${names.join(',')};
    grant execute on function civicpulse_delivery.claim_dispatch(text,integer) to ${names.join(',')};
    insert into civicpulse_delivery.machine_registry
      select rolname,oid,'dispatcher',true,clock_timestamp()+interval '1 hour' from pg_roles where rolname in ('${names[0]}','${names[1]}');
    update civicpulse_delivery.publication_state set bootstrap_complete=true;
    update civicpulse_delivery.pipeline_state set paused=false,approved_epoch=(select dataset_epoch from civicpulse_delivery.publication_state);
    update civicpulse_delivery.outbox set dispatch_state='accepted';
    insert into civicpulse_delivery.outbox(dataset_epoch,generation,action,kind,id,revision)
      select dataset_epoch,generation+1,'publish','event','concurrency-fixture',1 from civicpulse_delivery.publication_state;
  `);
  try {
    const session = name => new Promise((resolve,reject) => {
      const child=spawn('podman',psql,{stdio:['pipe','pipe','pipe']});
      let output='',error='';
      child.stdout.on('data',data=>output+=data);
      child.stderr.on('data',data=>error+=data);
      child.on('error',reject);
      child.on('close',code=>code===0?resolve(output.trim().split('\n').filter(line=>line.startsWith('[')).map(JSON.parse).flat()):reject(new Error(error)));
      child.stdin.end(`set session authorization ${name}; begin; select civicpulse_delivery.claim_dispatch('${name}',100); select pg_sleep(0.3); commit;`);
    });
    const receipts=(await Promise.all(names.map(session))).flat();
    assert.equal(receipts.filter(row=>row.event.id==='concurrency-fixture').length,1);
    assert.equal(new Set(receipts.map(row=>row.event.event_id)).size,receipts.length);
    assert.equal(command(psql,"select dispatch_attempts from civicpulse_delivery.outbox where id='concurrency-fixture';").trim(),'1');
    console.log('Concurrent real-session dispatch claims passed: unique lease, one attempt');
  } finally {
    command(psql,`delete from civicpulse_delivery.machine_registry where role_name in ('${names[0]}','${names[1]}'); drop owned by ${names.join(',')}; drop role ${names.join(',')};`);
  }
}
