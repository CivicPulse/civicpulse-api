import { spawn } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

// Each race gets an independent DB, real API-created approvals/receipts and
// actual session identities. Never run alongside another cp_m21 role fixture.
export async function testDeploymentConcurrency(command, container) {
  const info = JSON.parse(command(['inspect', container]))[0];
  assert.equal(info.Config.Image, 'docker.io/postgis/postgis:16-3.5');
  assert.equal(info.HostConfig.NetworkMode, 'none');
  const read = name => readFileSync(new URL('../' + name, import.meta.url), 'utf8');
  const bootstrap = read('tests/bootstrap.sql').replace(/create role (\w+) nologin;/g,
    (_, role) => `do $$ begin create role ${role} nologin; exception when duplicate_object then null; end $$;`);
  const migrations = readdirSync(new URL('../supabase/migrations/', import.meta.url)).filter(f => f.endsWith('.sql')).sort().map(f => read('supabase/migrations/' + f)).join('\n');
  for (const mode of ['duplicate-begin', 'begin-vs-terminal', 'expired-begin-vs-recovery']) {
    const database = 'civicpulse_race_' + randomUUID().replaceAll('-', '');
    const psql = ['exec', '-i', container, 'psql', '-qXAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1'];
    command(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
    try {
      const setup = [bootstrap, migrations,
        read('tests/enrollment-source.sql').split('-- BUILD_CLAIMS_SCENARIO')[0],
        read('tests/build-claims.sql').split('-- BUILD_TRANSITIONS_SCENARIO')[0],
        read('tests/build-transitions.sql').split('-- Fresh source receipt')[0],
        read('tests/deployment-control.sql').split('create function pg_temp.authority_snapshot()')[0],
        `grant execute on function civicpulse_delivery.reconcile_job(uuid,bigint,jsonb) to cp_m21_reconciler;
         set session authorization cp_m21_reconciler;
         insert into m21_context values('race_challenge',civicpulse_delivery.open_provider_observation('terminal',(pg_temp.ctx('claim')->>'job_id')::uuid,null,null));
         insert into m21_context values('race_receipt',civicpulse_delivery.record_provider_observation((pg_temp.ctx('race_challenge')->>'challenge_id')::uuid,
           jsonb_build_object('schema_version',1,'project',pg_temp.baseline()->'project','deployment',null,'markers',null,'artifact',null,
             'github_terminal',(select jsonb_build_object('run',r,'attempt',r) from (select (pg_temp.source()->'run_before')-array['id','path','actor_id','triggering_actor_id','referenced_workflows']||jsonb_build_object('run_id','9007199254740993','raw_path','.github/workflows/publish.yml@main','status','completed','conclusion','success') r) x),
             'requests',(select jsonb_agg(jsonb_build_object('endpoint_key',k,'page',1,'status',200,'request_id',null)) from unnest(array['project_before','project_after','github_run_terminal','github_attempt_terminal']) k))));
         reset session authorization;
         ${mode.startsWith('expired') ? "update civicpulse_delivery.build_jobs set lease_expires_at=clock_timestamp()-interval '1 second';" : ''}
         select jsonb_build_object('race',true,'claim',pg_temp.ctx('claim'),'receipt',pg_temp.ctx('race_receipt')); commit;`
      ].join('\n');
      const line = command(psql, setup).split('\n').find(line => line.startsWith('{') && JSON.parse(line).race);
      const { claim: c, receipt } = JSON.parse(line);
      const uuid = value => { assert.match(value, /^[0-9a-f-]{36}$/); return `'${value}'::uuid`; };
      assert.match(c.fence, /^[1-9][0-9]*$/); assert.match(c.target_generation, /^[0-9]+$/);
      const begin = `civicpulse_delivery.begin_deploy(${uuid(c.job_id)},${uuid(c.lease_id)},${c.fence},${uuid(c.dataset_epoch)},${c.target_generation},repeat('a',64),repeat('b',64),repeat('f',40))`;
      const recover = `civicpulse_delivery.reconcile_job(${uuid(c.job_id)},${c.fence},jsonb_build_object('observation_id',${uuid(receipt.observation_id)}))`;
      const session = (role, call) => new Promise((resolve, reject) => {
        const child = spawn('podman', psql, { stdio: ['pipe', 'pipe', 'pipe'] });
        let output = '', error = '';
        const timer = setTimeout(() => child.kill('SIGTERM'), 30000);
        child.stdout.on('data', data => output += data); child.stderr.on('data', data => error += data);
        child.on('error', reject);
        child.on('close', code => { clearTimeout(timer); if (code) reject(new Error(error)); else resolve(JSON.parse(output.trim().split('\n').find(s => s.startsWith('{')))); });
        child.stdin.end(`create function pg_temp.race() returns jsonb language plpgsql security invoker as $$ begin return ${call}; exception when others then return jsonb_build_object('error',sqlstate); end $$;
          set session authorization ${role}; begin; select pg_temp.race(); select pg_sleep(0.2); commit;`);
      });
      const results = await Promise.all([session('cp_m21_runner', begin), mode === 'duplicate-begin' ? session('cp_m21_runner', begin) : session('cp_m21_reconciler', recover)]);
      if (mode.startsWith('expired')) {
        assert.equal(results[0].error, '40001'); assert.equal(results[1].reclaimable, true);
        assert.equal(command(psql, 'select count(*) from civicpulse_delivery.deployment_intents;').trim(), '0');
        assert.equal(command(psql, "select state from civicpulse_delivery.build_jobs;").trim(), 'superseded');
        assert.equal(command(psql, 'select count(*) from civicpulse_delivery.deployment_acknowledgments;').trim(), '1');
      } else {
        assert.equal(results.filter(r => r.authorized === true).length, 1);
        assert.ok(results.some(r => r.error === '40001' || (mode !== 'duplicate-begin' && r.error === '55000')));
        assert.equal(command(psql, 'select count(*) from civicpulse_delivery.deployment_intents;').trim(), '1');
        assert.equal(command(psql, 'select external_authority from civicpulse_delivery.enrollment_state;').trim(), 't');
        assert.equal(command(psql, 'select count(*) from civicpulse_delivery.deployment_acknowledgments;').trim(), '0');
      }
      console.log(`Concurrent actual-session deployment ${mode} passed`);
    } finally {
      command(psql, 'drop owned by cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor; drop role cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor;');
      command(['exec', container, 'dropdb', '-U', 'postgres', database]);
    }
  }
}
