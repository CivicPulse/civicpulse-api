// Real SQL/HTTP integration. Opt-in, requires the documented disposable runtime.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { createCivicPulseClient } from '../src/client.mjs';

const child = spawn(process.execPath, [new URL('./serve-publication-fixture.mjs', import.meta.url).pathname], { stdio: ['pipe', 'pipe', 'inherit'] });
const messages = [], waiters = [];
createInterface({ input: child.stdout }).on('line', line => {
  const message = JSON.parse(line);
  const waiter = waiters.shift();
  if (waiter) waiter(message); else messages.push(message);
});
const exit = new Promise(resolve => child.on('exit', resolve));
const next = () => messages.length ? Promise.resolve(messages.shift()) : Promise.race([
  new Promise(resolve => waiters.push(resolve)),
  exit.then(code => { throw new Error(`Fixture exited before response (${code})`); }),
]);
const timer = setTimeout(() => { child.kill('SIGTERM'); process.exitCode = 1; }, 180000);
const send = (id, command) => { child.stdin.write(JSON.stringify({ id, command }) + '\n'); return next(); };
try {
  const ready = await next();
  assert.equal(ready.type, 'ready', JSON.stringify(ready));
  assert.equal(ready.test_only, true);
  const api = createCivicPulseClient({ url: ready.url, publishableKey: ready.publishableKey });
  const a = await api.publicationManifest();
  assert.deepEqual(a, ready.manifest);
  assert.deepEqual(a.counts, ready.expected.countsA);
  assert.equal(a.generation, '7');
  assert.equal(a.records.length, 7);
  assert.deepEqual(a.layers.map(l => [l.id, l.mode, l.feature_count]), [['event-locations', 'events', 1], [ready.expected.ids.layer, 'stored', 2]]);
  const rawManifest = await fetch(ready.url + '/rest/v1/rpc/publication_manifest', { method: 'POST', headers: { apikey: ready.publishableKey }, body: '{}' });
  assert.equal(rawManifest.headers.get('cache-control'), 'no-store, max-age=0');
  const all = [];
  for (let offset = 0; ; offset += 2) {
    const page = await api.listPublished(undefined, { limit: 2, offset });
    all.push(...page); if (page.length < 2) break;
  }
  assert.equal(all.length, 7);
  assert.deepEqual(all.map(({ kind, id, revision }) => ({ kind, id, revision: String(revision) })), a.records);
  assert.equal((await api.listPublished('event')).length, 2);
  const first = await api.layerGeoJSON(ready.expected.ids.layer, { limit: 1 });
  assert.equal(first.features.length, 1); assert.equal(first.nextOffset, 1);
  const second = await api.layerGeoJSON(ready.expected.ids.layer, { limit: 1, offset: first.nextOffset });
  assert.equal(second.features.length, 1); assert.equal(second.nextOffset, null);
  assert.equal((await api.layerGeoJSON('event-locations')).features.length, 1);
  assert.equal((await fetch(ready.url + '/rest/v1/content?select=*', { headers: { apikey: ready.publishableKey } })).status, 400);
  assert.equal((await fetch(ready.url + '/rest/v1/rpc/withdraw', { method: 'POST', headers: { apikey: ready.publishableKey } })).status, 404);
  assert.equal((await fetch(ready.url + '/rest/v1/content')).status, 403);
  const b = await send('advance-1', 'advanceB');
  assert.equal(b.type, 'result', JSON.stringify(b));
  assert.equal(b.stage, 'B'); assert.deepEqual(b.manifest.counts, ready.expected.countsB);
  assert.equal(b.manifest.generation, '10'); assert.equal(b.manifest.dataset_epoch, a.dataset_epoch);
  assert.deepEqual(b.receipts.map(r => [r.kind, r.id, r.revision, r.action]), [
    ['event', ready.expected.ids.event, '1', 'withdraw'], ['map', ready.expected.ids.map, '1', 'withdraw'], ['layer', ready.expected.ids.layer, '1', 'withdraw'],
  ]);
  assert.deepEqual(await api.publicationManifest(), b.manifest);
  assert.equal((await api.layerGeoJSON('event-locations')).features.length, 0);
  await assert.rejects(api.layerGeoJSON(ready.expected.ids.layer), error => error.code === 'P0002');
  const retained = await api.listPublished();
  assert.equal(retained.length, 4);
  for (const sentinel of Object.values(ready.expected.sentinels)) assert.ok(!JSON.stringify(retained).includes(sentinel));
  const retry = await send('advance-retry', 'advanceB');
  assert.deepEqual(retry.manifest, b.manifest); assert.deepEqual(retry.receipts, b.receipts);
  assert.equal((await send('bad-command', 'publish')).type, 'error');
  child.stdin.write('{not-json}\n'); assert.equal((await next()).code, 'invalid_fixture_command');
  child.stdin.write(JSON.stringify({ id: 'extra-field', command: 'advanceB', sql: 'select 1' }) + '\n');
  assert.equal((await next()).type, 'error');
  assert.deepEqual(await api.publicationManifest(), b.manifest);
  const closed = await send('close-1', 'close'); assert.equal(closed.closed, true);
  assert.equal(await exit, 0);
  console.log('M1 real SQL/HTTP A7 -> B4; generation7 -> 10; withdrawal/pagination/empty-layer/idempotency/read-only checks passed');
} finally {
  clearTimeout(timer);
  if (child.exitCode === null) { child.stdin.end(); await exit; }
}
