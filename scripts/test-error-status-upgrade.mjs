// Disposable historical-error upgrade controls; run after other cp_m21 fixtures.
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const container = 'civicpulse-api-db-test';
const correction = '20261018031708_bind_staff_error_acknowledgment_time.sql';
const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
function execute(args, input, expected = 0) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
  if (expected === 0 && result.status !== 0) throw new Error(result.stderr || result.stdout);
  if (expected !== 0) { assert.notEqual(result.status, 0); assert.match(result.stderr, /Existing error lacks unique durable failure attribution/); }
  return result.stdout;
}
const info = JSON.parse(execute(['inspect', container]))[0];
assert.equal(info.Config.Image, 'docker.io/postgis/postgis:16-3.5'); assert.equal(info.HostConfig.NetworkMode, 'none');
for (const mode of ['unique', 'missing', 'ambiguous']) {
  const database = 'civicpulse_error_upgrade_' + randomUUID().replaceAll('-', '');
  const psql = ['exec','-i',container,'psql','-qXAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'];
  execute(['exec',container,'createdb','-U','postgres','--template=template0',database]);
  try {
    const bootstrap = read('tests/bootstrap.sql').replace(/create role (\w+) nologin;/g, (_, role) => `do $$ begin create role ${role} nologin; exception when duplicate_object then null; end $$;`);
    const migrations = readdirSync(new URL('../supabase/migrations/', import.meta.url)).filter(f => f.endsWith('.sql') && f < correction).sort().map(f => read('supabase/migrations/' + f));
    execute(psql, [bootstrap, ...migrations,
      read('tests/enrollment-source.sql').split('-- BUILD_CLAIMS_SCENARIO')[0],
      read('tests/build-claims.sql').split('-- BUILD_TRANSITIONS_SCENARIO')[0],
      read('tests/build-transitions.sql').split('-- Fresh source receipt')[0],
      `set session authorization cp_m21_runner;
       select pg_temp.phase('queued','failed','{"error_code":"export_failed"}');
       reset session authorization; commit;`
    ].join('\n'));
    const original = execute(psql, "select jsonb_build_object('error',c.last_error,'at',a.acknowledged_at) from civicpulse_delivery.build_counter c cross join civicpulse_delivery.build_transitions a where a.state='failed';").trim();
    assert.equal(JSON.parse(original).error, 'export_failed');
    if (mode === 'missing') execute(psql, "delete from civicpulse_delivery.build_transitions where state='failed';");
    if (mode === 'ambiguous') {
      // Deliberately corrupt disposable historical evidence to simulate an
      // ambiguous restore; never use this as approval/receipt positive proof.
      execute(psql, `do $$ declare j civicpulse_delivery.build_jobs; o civicpulse_delivery.observations; c civicpulse_delivery.observation_challenges;
        jid uuid:=gen_random_uuid(); oid uuid:=gen_random_uuid(); cid uuid:=gen_random_uuid(); begin
        select * into j from civicpulse_delivery.build_jobs;
        select * into o from civicpulse_delivery.observations where observation_id=j.source_observation_id;
        select * into c from civicpulse_delivery.observation_challenges where challenge_id=o.challenge_id;
        c.challenge_id:=cid; insert into civicpulse_delivery.observation_challenges select c.*;
        o.observation_id:=oid; o.challenge_id:=cid; o.consumed_for:=jid; insert into civicpulse_delivery.observations select o.*;
        j.job_id:=jid; j.run_id:='9007199254740993:99'; j.lease_id:=gen_random_uuid(); j.fence:=j.fence+1; j.source_observation_id:=oid;
        insert into civicpulse_delivery.build_jobs select j.*;
        insert into civicpulse_delivery.build_transitions(job_id,sequence,expected_state,state,evidence)
          values(jid,j.transition_sequence,'queued','failed','{"error_code":"export_failed"}');
        end $$;`);
    }
    execute(psql, 'begin;\n' + read('supabase/migrations/' + correction) + '\ncommit;', mode === 'unique' ? 0 : 1);
    if (mode === 'unique') {
      const upgraded = JSON.parse(execute(psql, "select jsonb_build_object('error',last_error,'at',last_error_occurred_at) from civicpulse_delivery.build_counter;").trim());
      assert.deepEqual(upgraded, JSON.parse(original));
      const status = JSON.parse(execute(psql, "set session authorization authenticated; select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000061',false); set timezone='Pacific/Honolulu'; select public.cms_publication_status();").trim().split('\n').find(s=>s.startsWith('{')));
      assert.deepEqual(status.last_error, { code: upgraded.error, occurred_at: upgraded.at });
    } else {
      assert.equal(execute(psql, "select count(*) from information_schema.columns where table_schema='civicpulse_delivery' and table_name='build_counter' and column_name='last_error_occurred_at';").trim(), '0');
      assert.equal(execute(psql, 'select last_error from civicpulse_delivery.build_counter;').trim(), 'export_failed');
    }
    console.log(`Historical staff error upgrade ${mode} passed`);
  } finally {
    try { execute(psql, 'drop owned by cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor; drop role cp_m21_operator,cp_m21_reconciler,cp_m21_runner,cp_m21_impostor;'); }
    finally { execute(['exec',container,'dropdb','-U','postgres',database]); }
  }
}
