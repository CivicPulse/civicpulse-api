// Disposable rehearsal of the KNOWN hosted four-migration baseline -> local M2.2.
// Upload/live-writer authority and hosted application are not implied here.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';
const container = 'civicpulse-api-db-test';
const database = 'civicpulse_upgrade_' + randomUUID().replaceAll('-', '');
const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const baseline = ['20261016195541_civicpulse_content_api.sql', '20261016195619_restrict_platform_trigger_execution.sql', '20261016231409_private_event_publication_validation.sql', '20261016231420_private_event_source_url_v1.sql'];
const additions = ['20261016203213_publication_generation_manifest.sql', '20261016215623_delivery_identity_status_foundation.sql', '20261016220416_delivery_dispatch_leases.sql', '20261016221834_receipt_manifest_structure.sql', '20261018010946_delivery_enrollment_source.sql', '20261018013652_delivery_build_claims.sql', '20261018014106_delivery_build_transitions.sql', '20261018015030_require_objective_build_supersession.sql'];
function command(args, input) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'Local upgrade test failed');
  return result.stdout;
}
const inspection = JSON.parse(command(['inspect', container]))[0];
if (inspection.Config.Image !== 'docker.io/postgis/postgis:16-3.5' || inspection.HostConfig.NetworkMode !== 'none') throw new Error('Unsafe fixture container');
try {
  command(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
  const bootstrap = read('tests/bootstrap.sql').replace(/create role (\w+) nologin;/g, (_, name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`);
  const upgraded = read('tests/delivery-upgrade.sql').replace('-- APPLY_FOUNDATION_UPGRADE', () => additions.map(name => 'begin;\n' + read('supabase/migrations/' + name) + '\ncommit;').join('\n'));
  const connected = read('tests/enrollment-source.sql').replace("insert into m21_context values('empty',public.publication_manifest());", "delete from civicpulse.dependencies; delete from civicpulse.features; delete from civicpulse.published; delete from civicpulse.drafts; delete from civicpulse.history; delete from civicpulse.members; update civicpulse_delivery.publication_state set generation=0;\ninsert into m21_context values('empty',public.publication_manifest());");
  // The existing-row preservation test runs first. Connected tests clear only
  // this disposable DB's synthetic rows inside their rolled-back transaction.
  const output = command(['exec', '-i', container, 'psql', '-qX', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1'], [bootstrap, ...baseline.map(name => read('supabase/migrations/' + name)), upgraded, 'drop function pg_temp.assert(boolean,text);', connected.replace('-- BUILD_CLAIMS_SCENARIO', () => read('tests/build-claims.sql').replace('-- BUILD_TRANSITIONS_SCENARIO', () => read('tests/build-transitions.sql')))].join('\n'));
  console.log(output.split('\n').filter(line => line.includes('passed')).join('\n'));
  console.log(JSON.stringify({ scope: 'M2.2-local-through-ready-no-upload-live-writer', baseline, additions: additions.map(name => ({ name, sha256: createHash('sha256').update(read('supabase/migrations/' + name)).digest('hex') })) }));
} finally { command(['exec', container, 'dropdb', '-U', 'postgres', '--if-exists', database]); }
