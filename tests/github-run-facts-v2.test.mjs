import test from 'node:test';
import assert from 'node:assert/strict';
import { parse } from 'lossless-json';
import { decodeGitHubInProgressRunFactsV2 as decode, assertGitHubInProgressRunFactsV2 as compare } from '../src/server/github-run-facts-v2.mjs';
import { decodeRunFacts } from '../src/server/github-run-facts-v2-internal.mjs';
import { runIdentityLimits as limits } from '../src/server/github-run-json.mjs';

// Synthetic in-progress/same-repository fixtures. No real provider observation.
const policy = (form = 'relative-main') => ({ policy: 'cp-workflow-path-v2', repository_full_name: 'octocat/octo-repo', workflow_path: '.github/workflows/build.yml', source_sha: 'a'.repeat(40), run_path_form: form });
const selectedPath = p => (p.run_path_form === 'repository-main' ? p.repository_full_name + '/' : '') + p.workflow_path + (p.run_path_form === 'bare' ? '' : '@main');
const base = () => ({ id: 123, run_attempt: 1, workflow_id: 456, repository: { id: 789 }, head_repository: { id: 789 }, path: selectedPath(policy()), head_sha: 'a'.repeat(40), head_branch: 'main', event: 'push', status: 'in_progress', conclusion: null });
const raw = (changes = {}) => JSON.stringify({ ...base(), ...changes });
const target = () => ({ identity: { id: '123', run_attempt: '1', workflow_id: '456', repository_id: '789', head_repository_id: '789' }, event: 'push' });
const extra = (body, fields) => body.slice(0, -1) + ',' + fields + '}';
const rejects = (work, code = 'invalid_github_in_progress_run_facts_v2') => assert.throws(work, error => {
  assert.equal(error.code, code); assert.equal(error.message, code);
  assert.equal(Object.hasOwn(error, 'cause'), false); assert.deepEqual(Object.keys(error), ['code']);
  return true;
});
const mismatch = work => rejects(work, 'github_in_progress_run_facts_v2_mismatch');

test('single decode projects exactly nine/five own fields for every endpoint/form/event', () => {
  for (const form of ['bare', 'relative-main', 'repository-main']) for (const endpoint of ['run', 'attempt']) for (const event of ['push', 'schedule', 'workflow_dispatch']) {
    const p = policy(form), path = selectedPath(p);
    const facts = decode(raw({ path, event }), endpoint);
    assert.deepEqual(facts, { schema_version: 2, endpoint, identity: target().identity, raw_path: path, head_sha: p.source_sha, head_branch: 'main', event, status: 'in_progress', conclusion: null });
    assert.equal(Reflect.ownKeys(facts).length, 9); assert.equal(Reflect.ownKeys(facts.identity).length, 5);
    assert.equal(Object.getPrototypeOf(facts), Object.prototype);
    assert.equal(Object.getPrototypeOf(facts.identity), Object.prototype);
    assert.equal(compare(facts, { ...target(), event }, p), undefined);
  }
});

test('A/attempt/B use one fixed target and policy; every identity/event/path change fails', () => {
  const p = Object.freeze(policy()), expected = target();
  Object.freeze(expected.identity); Object.freeze(expected);
  const bodies = ['run', 'attempt', 'run'].map(endpoint => decode(raw(), endpoint));
  for (const facts of bodies) { Object.freeze(facts.identity); Object.freeze(facts); compare(facts, expected, p); }
  assert.equal(bodies[0].raw_path, bodies[1].raw_path); assert.equal(bodies[1].raw_path, bodies[2].raw_path);
  for (const changes of [{ id: 124 }, { run_attempt: 2 }, { workflow_id: 457 }, { repository: { id: 790 } }, { head_repository: { id: 790 } }, { event: 'schedule' }, { head_sha: 'b'.repeat(40) }, { path: p.workflow_path }]) {
    for (const endpoint of ['run', 'attempt']) mismatch(() => compare(decode(raw(changes), endpoint), expected, p));
  }
});

test('large numeric tokens remain lossless; only canonical number tokens accepted', () => {
  for (const id of ['9007199254740992', '9007199254740993', '99999999999999999999']) {
    const body = raw().replace('123', id).replace('456', id).replaceAll('789', id).replace('"run_attempt":1', '"run_attempt":9999999999');
    const facts = decode(body, 'run');
    assert.deepEqual(facts.identity, { id, run_attempt: '9999999999', workflow_id: id, repository_id: id, head_repository_id: id });
    compare(facts, { identity: { ...facts.identity }, event: 'push' }, policy());
  }
  const adjacent = decode(raw().replace('123', '9007199254740992'), 'run');
  mismatch(() => compare(adjacent, { ...target(), identity: { ...target().identity, id: '9007199254740993' } }, policy()));
  for (const [needle, attempt] of [['"id":123', false], ['"workflow_id":456', false], ['"id":789', false], ['"run_attempt":1', true]]) {
    for (const token of ['"1"', '0', '-0', '-1', '1.0', '1e0', 'null', 'true', '[]', '{}', '{"isLosslessNumber":true,"value":"1"}', attempt ? '10000000000' : '100000000000000000000']) {
      rejects(() => decode(raw().replace(needle, needle.slice(0, needle.indexOf(':') + 1) + token), 'run'));
    }
  }
});

test('every required upstream own field is present and typed; duplicate aliases reject', () => {
  for (const key of Object.keys(base())) {
    const missing = base(); delete missing[key]; rejects(() => decode(JSON.stringify(missing), 'run'));
    rejects(() => decode(raw({ [key]: [] }), 'run'));
    const alias = '\\u' + key.charCodeAt(0).toString(16).padStart(4, '0') + key.slice(1);
    for (const duplicate of [key, alias]) rejects(() => decode(extra(raw(), '"' + duplicate + '":' + JSON.stringify(base()[key])), 'run'));
  }
  for (const key of ['repository', 'head_repository']) {
    for (const value of [{}, { id: null }, [], null, 'text', 1]) rejects(() => decode(raw({ [key]: value }), 'run'));
    rejects(() => decode(raw().replace('"' + key + '":{"id":789}', '"' + key + '":{"id":789,"\\u0069d":789}'), 'run'));
  }
  rejects(() => decode(extra(raw(), '"ignored":{"a":1,"\\u0061":1}'), 'attempt'));
});

test('fixed lifecycle and own-null conclusion reject unsupported facts', () => {
  for (const [key, values] of Object.entries({ head_branch: ['', 'Main', 'dev', 'main\n', null], head_sha: ['', 'A'.repeat(40), 'a'.repeat(40) + '\n', 123], event: ['', 'pull_request', 'push\n', null], status: ['queued', 'waiting', 'completed', null], conclusion: ['', 'success', false, 0, {}, []] })) {
    for (const value of values) rejects(() => decode(raw({ [key]: value }), 'run'));
  }
  for (const endpoint of [undefined, null, 'workflow', 'Run', {}, 1]) rejects(() => decode(raw(), endpoint));
  for (const body of [undefined, null, '', '{}', '[]', 'null', 'true', raw() + 'x', '{"x":"\\uZZZZ"}']) rejects(() => decode(body, 'run'));
});

test('upstream metadata cannot override local schema, endpoint, identity or raw path', () => {
  const body = extra(raw(), '"schema_version":99,"endpoint":"workflow","identity":{"id":0},"raw_path":"fake","__proto__":{"polluted":true},"unknown":1e999999');
  assert.deepEqual(decode(body, 'attempt'), decode(raw(), 'attempt'));
  assert.equal({}.polluted, undefined);
  assert.deepEqual(decode(extra(raw(), '"ignored":"\\uD800"'), 'run'), decode(raw(), 'run'));
});

test('raw paths retain every byte until exact policy comparison; SHA errors map distinctly', () => {
  for (const path of ['', '.github/workflows/build.yml', '.github/workflows/build.yml@dev', '.github/workflows/build.yml@refs/heads/main', '.github/workflows/../build.yml@main', '.github/workflows/%62uild.yml@main', 'other/repo/.github/workflows/build.yml@main', selectedPath(policy()) + '\n']) {
    const facts = decode(raw({ path }), 'run'); assert.equal(facts.raw_path, path);
    mismatch(() => compare(facts, target(), policy()));
  }
  mismatch(() => compare(decode(raw({ head_sha: 'b'.repeat(40) }), 'run'), target(), policy()));
  rejects(() => compare({ ...decode(raw(), 'run'), head_sha: 'B'.repeat(40) }, target(), policy()));
});

test('exact actual/target/nested descriptors reject missing/extra/accessor/prototype data', () => {
  const facts = decode(raw(), 'run'), expected = target();
  const cases = [
    [facts, value => compare(value, expected, policy())],
    [facts.identity, value => compare({ ...facts, identity: value }, expected, policy())],
    [expected, value => compare(facts, value, policy())],
    [expected.identity, value => compare(facts, { ...expected, identity: value }, policy())],
  ];
  for (const [baseValue, check] of cases) {
    for (const value of [null, [], Object.create(baseValue), 'text']) rejects(() => check(value));
    for (const key of Reflect.ownKeys(baseValue)) {
      const missing = { ...baseValue }; delete missing[key]; rejects(() => check(missing));
      rejects(() => check({ ...baseValue, [key]: undefined }));
      rejects(() => check(Object.defineProperty({ ...baseValue }, key, { enumerable: false })));
      rejects(() => check(Object.defineProperty({ ...baseValue }, key, { enumerable: true, get() { assert.fail('getter read'); } })));
    }
    for (const key of ['extra', '__proto__', Symbol('extra')]) rejects(() => check(Object.defineProperty({ ...baseValue }, key, { enumerable: true, value: 'x' })));
    check(Object.assign(Object.create(null), baseValue));
    check(new Proxy(baseValue, { get() { assert.fail('property read'); } }));
    rejects(() => check(new Proxy(baseValue, { ownKeys() { throw new Error('private reflection detail'); } })));
  }
});

test('all structural constraints precede path and identity/event equality', () => {
  const facts = decode(raw(), 'run');
  for (const changes of [{ schema_version: '2' }, { schema_version: 1 }, { endpoint: 'workflow' }, { status: 'completed' }, { conclusion: undefined }, { conclusion: false }, { head_branch: 'dev' }, { event: 'pull_request' }, { raw_path: 1 }]) {
    rejects(() => compare({ ...facts, ...changes }, target(), policy()));
  }
  const pathMismatch = { ...facts, raw_path: '' };
  rejects(() => compare(pathMismatch, { ...target(), event: 'pull_request' }, policy()));
  rejects(() => compare(pathMismatch, { ...target(), identity: { ...target().identity, head_repository_id: '790' } }, policy()));
  const numericMismatch = { ...facts, identity: { ...facts.identity, id: '124' } };
  const overlongPolicy = { ...policy(), workflow_path: '.github/workflows/' + 'x'.repeat(65535 - '.github/workflows/'.length - '.yml@main'.length) + '.yml' };
  assert.equal(Buffer.byteLength(overlongPolicy.workflow_path + '@main'), 65535);
  rejects(() => compare(numericMismatch, target(), overlongPolicy));
  rejects(() => compare(pathMismatch, target(), { ...policy(), source_sha: '' }));
  rejects(() => compare(facts, target(), Object.defineProperty(policy(), 'source_sha', { get() { assert.fail('policy getter'); } })));
  mismatch(() => compare({ ...facts, identity: { ...facts.identity, head_repository_id: '790' } }, target(), policy()));
  mismatch(() => compare(facts, { ...target(), event: 'schedule' }, policy()));
  for (const id of ['0', '01', '1.0', 1, '1\n', '1'.repeat(21)]) rejects(() => compare({ ...facts, identity: { ...facts.identity, id } }, target(), policy()));
});

test('actual decoder retains bounded parser byte/depth/string/token limits', () => {
  const valid = raw(), baseline = decode(valid, 'run');
  const exactBytes = valid + ' '.repeat(limits.rawBytes - Buffer.byteLength(valid));
  assert.deepEqual(decode(exactBytes, 'run'), baseline); rejects(() => decode(exactBytes + ' ', 'run'));
  const nested = count => extra(valid, '"ignored":' + '['.repeat(count) + '0' + ']'.repeat(count));
  assert.deepEqual(decode(nested(63), 'run'), baseline); rejects(() => decode(nested(64), 'run'));
  const string = count => extra(valid, '"ignored":"' + 'x'.repeat(count) + '"');
  assert.deepEqual(decode(string(65534), 'run'), baseline); rejects(() => decode(string(65535), 'run'));
  for (const path of ['x'.repeat(65534), 'é'.repeat(32767)]) assert.equal(decode(raw({ path }), 'run').raw_path, path);
  rejects(() => decode(raw({ path: 'é'.repeat(32767) + 'x' }), 'run'));
  // Independent structural token count, safe synthetic numbers only.
  const count = value => Array.isArray(value) ? 2 + Math.max(0, value.length - 1) + value.reduce((s, v) => s + count(v), 0)
    : value !== null && typeof value === 'object' ? 2 + Math.max(0, Object.keys(value).length - 1) + Object.values(value).reduce((s, v) => s + 2 + count(v), 0) : 1;
  const fixed = count(JSON.parse(extra(valid, '"ignored":[]')));
  const entries = Math.floor((limits.tokens - fixed + 1) / 2);
  const make = items => extra(valid, '"ignored":[' + items.join(',') + ']');
  const items = Array(entries).fill('0');
  if (count(JSON.parse(make(items))) < limits.tokens) items[0] = '[]';
  const at = make(items); assert.equal(count(JSON.parse(at)), limits.tokens);
  assert.deepEqual(decode(at, 'run'), baseline);
  const over = make([...items, '0']); assert.ok(count(JSON.parse(over)) > limits.tokens);
  rejects(() => decode(over, 'run'));
});

test('internal seam proves one dependency parse, zero on preflight rejection, no public override', () => {
  let calls = 0;
  const parser = body => { calls++; return parse(body); };
  assert.deepEqual(decodeRunFacts(raw(), 'attempt', parser), decode(raw(), 'attempt'));
  assert.equal(calls, 1);
  for (const body of [raw() + ' '.repeat(limits.rawBytes), extra(raw(), '"ignored":' + '['.repeat(64) + '0' + ']'.repeat(64)), extra(raw(), '"ignored":"' + 'x'.repeat(65535) + '"'), extra(raw(), '"ignored":[' + Array(32768).fill('0').join(',') + ']'), extra(raw(), '"id":123')]) {
    rejects(() => decodeRunFacts(body, 'run', parser));
  }
  rejects(() => decodeRunFacts(raw(), 'workflow', parser));
  assert.equal(calls, 1);
  assert.deepEqual(decode(raw(), 'run', () => { assert.fail('public override invoked'); }), decode(raw(), 'run'));
});
