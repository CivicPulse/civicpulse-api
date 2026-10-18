import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

/** Actual M2.1 APIs establish approval/receipts; no owner-seeded authority. */
export async function testBuildConcurrency(command, container, database) {
  const psql = ['exec','-i',container,'psql','-qXAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'];
  const setup = readFileSync(new URL('../tests/enrollment-source.sql', import.meta.url), 'utf8').split('-- BUILD_CLAIMS_SCENARIO')[0];
  const roles = 'cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor,cp_m22_runner';
  command(psql, setup + `
    create role cp_m22_runner nologin;
    grant usage on schema civicpulse_delivery to cp_m22_runner;
    insert into civicpulse_delivery.machine_registry select rolname,oid,'runner',true,clock_timestamp()+interval '1 hour' from pg_roles where rolname='cp_m22_runner';
    grant execute on function civicpulse_delivery.claim_build(text,text) to cp_m21_runner,cp_m22_runner;
    commit;
  `);
  try {
    const session = name => new Promise((resolve,reject) => {
      const child = spawn('podman',psql,{stdio:['pipe','pipe','pipe']});
      let output='',error='';
      child.stdout.on('data',data=>output+=data);
      child.stderr.on('data',data=>error+=data);
      child.on('error',reject);
      child.on('close',code=>code===0
        ? resolve(JSON.parse(output.trim().split('\n').find(line=>line.startsWith('{'))))
        : reject(new Error(error)));
      child.stdin.end(`
        create function pg_temp.attempt_claim() returns jsonb language plpgsql security invoker as $$
        begin return civicpulse_delivery.claim_build('9007199254740993:1',repeat('f',40));
        exception when others then return jsonb_build_object('error',sqlstate); end $$;
        set session authorization ${name}; begin;
        select pg_temp.attempt_claim(); select pg_sleep(0.3); commit;
      `);
    });
    const competing = await Promise.all(['cp_m21_runner','cp_m22_runner'].map(session));
    assert.equal(competing.filter(row=>row.job_id).length,1);
    assert.equal(competing.filter(row=>row.error==='40001').length,1);
    const winner = command(psql,'select actor from civicpulse_delivery.build_jobs;').trim();
    const replay = await Promise.all([session(winner),session(winner)]);
    assert.deepEqual(replay[0],replay[1]);
    assert.deepEqual(replay[0],competing.find(row=>row.job_id));
    assert.equal(command(psql,'select count(*) from civicpulse_delivery.build_jobs;').trim(),'1');
    assert.equal(command(psql,"select count(*) from civicpulse_delivery.observations o join civicpulse_delivery.observation_challenges c using(challenge_id) where c.family='source' and o.consumed_at is not null;").trim(),'1');
    console.log('Concurrent actual-runner claims passed: one job/receipt, different-owner conflict, exact same-owner replay');
  } finally {
    // Database is disposable and dropped by the caller; these NOLOGIN roles are
    // cluster-wide and must not survive successful/failed competing sessions.
    command(psql,`drop owned by ${roles}; drop role ${roles};`);
  }
}
