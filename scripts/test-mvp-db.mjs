// Disposable ONLY: prove hosted v1 + the two reviewed privacy guards without delivery.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const container = process.env.CIVICPULSE_TEST_CONTAINER || 'civicpulse-api-db-test';
const database = `civicpulse_mvp_${Date.now()}`;
const read = path => readFileSync(path, 'utf8');
const command = (args, input) => {
  const result = spawnSync('podman', args, { input, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout;
};
const migrations = ['20261016195541_civicpulse_content_api.sql', '20261016195619_restrict_platform_trigger_execution.sql',
  '20261016231409_private_event_publication_validation.sql', '20261016231420_private_event_source_url_v1.sql'];
const guards = migrations.slice(2).map(name => read('supabase/migrations/' + name)).join('\n');
const bootstrap = read('tests/bootstrap.sql').replace(/create role (\w+) nologin;/g,
  (_, name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`);
const corpus = JSON.parse(read('tests/fixtures/cp-source-url-v1.json'));
corpus.accept.push('https://' + 'a'.repeat(63) + '.test/', 'https://' + ['a'.repeat(63), 'b'.repeat(63), 'c'.repeat(63), 'd'.repeat(61)].join('.') + '/');
corpus.reject.push('https://' + 'a'.repeat(64) + '.test/', 'https://' + ['a'.repeat(63), 'b'.repeat(63), 'c'.repeat(63), 'd'.repeat(62)].join('.') + '/');
const literal = value => "'" + JSON.stringify(value).replaceAll("'", "''") + "'::jsonb";
const urlCases = `
for value in select item from jsonb_array_elements(${literal(corpus.accept)}) item loop
  select revision into version from public.cms_drafts where kind='event' and id='private-test';
  version:=public.save_draft('event','private-test',base||jsonb_build_object('sourceUrl',value),version);
  perform public.publish('event','private-test',version);
  perform pg_temp.assert((select payload->'sourceUrl'=value from public.content where kind='event' and id='private-test'),'accepted URL bytes preserved');
end loop;
for value in select item from jsonb_array_elements(${literal(corpus.reject.filter(v => typeof v !== 'string' || !v.includes('\u0000')))}) item loop
  perform pg_temp.reject_private(base||jsonb_build_object('sourceUrl',value));
end loop;`;
// Reuse all existing private publish assertions. Replace ONLY delivery observers
// with a test-local content/GeoJSON snapshot; no manifest/outbox is deployed here.
const snapshot = `create function pg_temp.mvp_snapshot() returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_object('content',(select jsonb_agg(to_jsonb(c) order by kind,id) from public.content c),
'layers',jsonb_build_array(jsonb_build_object('feature_count',jsonb_array_length(public.layer_geojson('event-locations')->'features')))); $$;`;
const privateTests = read('tests/private-events.sql')
  .replace("'outbox',(select count(*) from civicpulse_delivery.outbox)", "'outbox',0")
  .replaceAll('public.publication_manifest()', 'pg_temp.mvp_snapshot()')
  .replace("select pg_temp.assert((select count(*)=0 from civicpulse_delivery.outbox where id='private-test' and revision=2),'rejected revision has no durable intent');", "select pg_temp.assert(to_regnamespace('civicpulse_delivery') is null,'MVP has no delivery schema');")
  .replace('-- SHARED_URL_PUBLISH_CORPUS', () => urlCases)
  .replace('begin;', () => 'begin;\n' + snapshot);
const upgrade = read('tests/mvp-guard-upgrade.sql').replace('-- APPLY_REVIEWED_GUARDS', () => guards);
command(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
try {
  const sql = [bootstrap, ...migrations.slice(0, 2).map(name => read('supabase/migrations/' + name)),
    upgrade, guards, read('tests/security.sql'), privateTests,
    `do $$ begin if to_regnamespace('civicpulse_delivery') is not null or to_regprocedure('public.publication_manifest()') is not null then raise exception 'Unexpected delivery dependency'; end if; end $$;`,
    `select 'MVP four-migration subset passed; delivery absent' as result;`].join('\n');
  const output = command(['exec', '-i', container, 'psql', '-q', '-X', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1'], sql);
  console.log(output.split('\n').filter(line => /passed|Warm pre-migration/u.test(line)).join('\n'));
  console.log(JSON.stringify({ migrations, urlAccept: corpus.accept.length, urlReject: corpus.reject.length, rawNul: 'database representation rejection checked separately' }));
} finally { command(['exec', container, 'dropdb', '-U', 'postgres', database]); }
