#!/usr/bin/env node
// TEST ONLY. PostgreSQL API projections, not a PostgREST/Auth emulator.
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
// Deliberately no database URL/container override or hosted environment loading.
const container = 'civicpulse-api-db-test';
const database = `civicpulse_m1_${randomUUID().replaceAll('-', '')}`;
const actor = '00000000-0000-4000-8000-000000000041';
const key = 'local-m1-fixture-only';
const kinds = ['organization', 'calendar', 'event', 'layer', 'map'];
const ids = { organization: 'm1-organization', calendar: 'm1-calendar', event: 'm1-withdraw-event', privateEvent: 'm1-private-event', layer: 'm1-withdraw-layer', derived: 'event-locations', map: 'm1-withdraw-map' };
const sentinels = { event: 'M1_WITHDRAW_EVENT_7fd91', layer: 'M1_WITHDRAW_LAYER_7fd91', feature: 'M1_WITHDRAW_FEATURE_7fd91', map: 'M1_WITHDRAW_MAP_7fd91' };
const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
const json = value => `${literal(JSON.stringify(value))}::jsonb`;
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
let created = false, closing = false, phase = 'container';
function command(args, input) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 60000 });
  if (result.status !== 0) {
    const code = /ERROR:\s+([A-Z0-9]{5}):/.exec(result.stderr || '')?.[1];
    throw Object.assign(new Error('disposable_sql_failed'), { code: code || 'fixture_sql_error' });
  }
  return result.stdout.trim();
}
function sql(statement) {
  return command(['exec', '-i', container, 'psql', '-qAtX', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], statement);
}
const asAdmin = statement => `set session authorization authenticated; set "request.jwt.claim.sub"=${literal(actor)}; ${statement} reset session authorization;`;
const asAnon = statement => `set session authorization anon; ${statement} reset session authorization;`;
function manifest() { return JSON.parse(sql(asAnon('select public.publication_manifest();'))); }
function cleanup() {
  if (created) {
    command(['exec', container, 'dropdb', '-U', 'postgres', '--if-exists', database]);
    created = false;
  }
}
function advance() {
  // Persistent stage and mutations share one transaction. Lost IPC response may
  // be retried in THIS process; it never replays withdrawals. No restart attach.
  return JSON.parse(sql(`begin;
    select stage from m1_fixture.state for update;
    do $fixture$ begin if (select stage from m1_fixture.state)='A' then
      set local session authorization authenticated;
      perform set_config('request.jwt.claim.sub',${literal(actor)},true);
      perform public.withdraw('event',${literal(ids.event)},1);
      perform public.withdraw('map',${literal(ids.map)},1);
      perform public.withdraw('layer',${literal(ids.layer)},1);
      reset session authorization;
      update m1_fixture.state set stage='B',result=jsonb_build_object(
        'stage','B','manifest',public.publication_manifest(),
        'receipts',(select jsonb_agg(jsonb_build_object('kind',kind,'id',id,'revision',revision::text,'action',action,'sequence',sequence::text) order by sequence) from civicpulse.history where action='withdraw'));
    end if; end $fixture$;
    select result from m1_fixture.state; commit;`).split('\n').at(-1));
}
const exactKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => keys.includes(k));
function integer(value, fallback, min, max) {
  if (value === undefined || value === null) return fallback;
  if (!/^(0|[1-9][0-9]*)$/.test(String(value))) throw new Error('invalid_request');
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < min || n > max) throw new Error('invalid_request');
  return n;
}
async function body(request) {
  let buffer = '';
  for await (const chunk of request) {
    buffer += chunk.toString('utf8');
    if (Buffer.byteLength(buffer) > 4096) throw new Error('invalid_request');
  }
  return buffer ? JSON.parse(buffer) : {};
}
const server = createServer(async (request, response) => {
  try {
    if (closing || request.headers.apikey !== key) { response.writeHead(403).end(); return; }
    const url = new URL(request.url, 'http://127.0.0.1');
    let result;
    if (request.method === 'POST' && url.pathname === '/rest/v1/rpc/publication_manifest' && !url.search) {
      const input = await body(request);
      if (!exactKeys(input, []) || Object.keys(input).length) throw new Error('invalid_request');
      result = sql(asAnon('select public.publication_manifest();'));
    } else if (request.method === 'GET' && url.pathname === '/rest/v1/content') {
      const q = url.searchParams;
      if ([...q.keys()].some(k => !['select', 'order', 'kind', 'limit', 'offset'].includes(k) || q.getAll(k).length !== 1) || q.get('select') !== '*' || q.get('order') !== 'kind.asc,id.asc') throw new Error('invalid_request');
      const kind = q.get('kind');
      if (kind !== null && !kinds.some(k => kind === `eq.${k}`)) throw new Error('invalid_request');
      const limit = integer(q.get('limit'), 100, 1, 1000), offset = integer(q.get('offset'), 0, 0, 2147483647);
      result = sql(asAnon(`select coalesce(jsonb_agg(to_jsonb(p) order by kind collate "C",id collate "C"),'[]'::jsonb) from (select * from public.content ${kind ? `where kind=${literal(kind.slice(3))}` : ''} order by kind collate "C",id collate "C" limit ${limit} offset ${offset}) p;`));
    } else if (request.method === 'POST' && url.pathname === '/rest/v1/rpc/layer_geojson' && !url.search) {
      const input = await body(request);
      if (!exactKeys(input, ['p_layer_id', 'p_limit', 'p_offset']) || typeof input.p_layer_id !== 'string' || !/^[a-z0-9-]{1,128}$/.test(input.p_layer_id)) throw new Error('invalid_request');
      const limit = integer(input.p_limit, 500, 1, 1000), offset = integer(input.p_offset, 0, 0, 2147483647);
      result = sql(asAnon(`select public.layer_geojson(${literal(input.p_layer_id)},${limit},${offset});`));
    } else { response.writeHead(404).end(); return; }
    response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store, max-age=0' }).end(result);
  } catch (error) {
    response.writeHead(error.code === 'P0002' ? 404 : 400, { 'Content-Type': 'application/json' }).end(JSON.stringify({ code: error.code || '22023', message: 'fixture_request_rejected' }));
  }
});
async function close(id) {
  if (closing) return;
  closing = true;
  await new Promise(resolve => server.close(resolve));
  try {
    cleanup();
    if (id !== undefined) emit({ type: 'result', id, command: 'close', closed: true });
  } catch {
    emit({ type: 'error', id: id ?? null, code: 'fixture_cleanup_failed' });
    process.exitCode = 1;
  } finally { process.stdin.destroy(); }
}
try {
  // Fixed local container must be the documented offline PostGIS runtime.
  const inspection = JSON.parse(command(['inspect', container]))[0];
  if (inspection.Config.Image !== 'docker.io/postgis/postgis:16-3.5' || inspection.HostConfig.NetworkMode !== 'none') throw new Error('unsafe_fixture_container');
  created = true; // Also clean up if createdb commits but its transport times out.
  command(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
  phase = 'migrations';
  const bootstrap = readFileSync(root + 'tests/bootstrap.sql', 'utf8').replace(/create role (\w+) nologin;/g, (_, name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`);
  sql(bootstrap + '\n' + readdirSync(root + 'supabase/migrations').filter(f => f.endsWith('.sql')).sort().map(f => readFileSync(root + 'supabase/migrations/' + f, 'utf8')).join('\n'));
  phase = 'seed';
  const event = { id: ids.event, title: sentinels.event, start: '2026-11-01T12:00:00-05:00', end: '2026-11-01T13:00:00-05:00', category: 'Community', location: 'Synthetic library', address: 'Synthetic public address', sample: false, sourceUrl: 'https://example.org/m1', sourceChecked: '2026-10-17', organizationId: ids.organization, calendarIds: [ids.calendar], coordinates: [-83.6, 32.8] };
  const privateEvent = { ...event, id: ids.privateEvent, title: 'M1 retained private event', addressPrivate: true, address: 'Private location — see organizer for details', location: 'Private location — see organizer for details' }; delete privateEvent.coordinates;
  const records = [
    ['organization', { id: ids.organization, name: 'M1 organization' }],
    ['calendar', { id: ids.calendar, name: 'M1 calendar', organizationId: ids.organization }],
    ['event', event], ['event', privateEvent],
    ['layer', { id: ids.layer, name: sentinels.layer, kind: 'point', geojson: { type: 'FeatureCollection', features: [0, 1].map(i => ({ type: 'Feature', id: `m1-feature-${i}`, properties: { name: sentinels.feature + i }, geometry: { type: 'Point', coordinates: [-83.6 + i / 100, 32.8] } })) } }],
    ['layer', { id: ids.derived, name: 'M1 event locations', kind: 'point', dynamic: 'events' }],
    ['map', { id: ids.map, name: sentinels.map, layers: [ids.layer, ids.derived] }],
  ];
  sql(`insert into auth.users values (${literal(actor)}); insert into civicpulse.members values (${literal(actor)},'admin');` + asAdmin(records.map(([kind, payload]) => `select public.save_draft(${literal(kind)},${literal(payload.id)},${json(payload)},0); select public.publish(${literal(kind)},${literal(payload.id)},1);`).join('\n')) + `
    -- Owner fixture bootstrap only: no approval/live writer is implemented here.
    update civicpulse_delivery.publication_state set bootstrap_complete=true;
    create schema m1_fixture; revoke all on schema m1_fixture from public,anon,authenticated;
    create table m1_fixture.state(stage text not null,result jsonb); insert into m1_fixture.state values('A',null);`);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  emit({ type: 'ready', schema_version: 1, fixture_id: database, url: `http://127.0.0.1:${server.address().port}`, publishableKey: key, test_only: true, owner_bootstrap_fixture: true, manifest: manifest(), expected: { ids, countsA: { organization: 1, calendar: 1, event: 2, layer: 2, map: 1 }, countsB: { organization: 1, calendar: 1, event: 1, layer: 1, map: 0 }, generationA: '7', generationB: '10', sentinels } });
  let pending = Buffer.alloc(0);
  process.stdin.on('data', chunk => {
    pending = Buffer.concat([pending, chunk]);
    while (pending.includes(10)) {
      const end = pending.indexOf(10), line = pending.subarray(0, end); pending = pending.subarray(end + 1);
      let input;
      try {
        if (line.length > 4096) throw new Error();
        input = JSON.parse(line.toString('utf8'));
        if (!exactKeys(input, ['id', 'command']) || typeof input.id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(input.id) || !['advanceB', 'close'].includes(input.command) || closing) throw new Error();
        if (input.command === 'close') { void close(input.id).catch(() => { process.exitCode = 1; }); return; }
        emit({ type: 'result', id: input.id, command: input.command, ...advance() });
      } catch (error) { emit({ type: 'error', id: typeof input?.id === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(input.id) ? input.id : null, code: error?.code || 'invalid_fixture_command' }); }
    }
    if (pending.length > 4096) { emit({ type: 'error', id: null, code: 'fixture_line_too_large' }); void close().catch(() => { process.exitCode = 1; }); }
  });
  process.stdin.on('end', () => { void close().catch(() => { process.exitCode = 1; }); });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { void close().catch(() => { process.exitCode = 1; }); });
} catch (error) {
  emit({ type: 'error', id: null, code: 'fixture_start_failed', phase, sqlstate: error.code || null });
  try { cleanup(); } catch { emit({ type: 'error', id: null, code: 'fixture_cleanup_failed' }); }
  process.exitCode = 1;
}
