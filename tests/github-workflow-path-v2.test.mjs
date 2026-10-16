import test from 'node:test';
import assert from 'node:assert/strict';
import { assertGitHubWorkflowPathV2 as compare } from '../src/server/github-workflow-path-v2.mjs';
import { decodeGitHubRunIdentity } from '../src/server/github-run-identity.mjs';

// Synthetic structured facts, not authenticated provider responses.
const forms = ['bare', 'relative-main', 'repository-main'];
const policy = (form = 'relative-main') => ({ policy: 'cp-workflow-path-v2', repository_full_name: 'octocat/octo-repo', workflow_path: '.github/workflows/build.yml', source_sha: 'a'.repeat(40), run_path_form: form });
const path = p => (p.run_path_form === 'repository-main' ? p.repository_full_name + '/' : '') + p.workflow_path + (p.run_path_form === 'bare' ? '' : '@main');
const observation = (p, endpoint = 'run') => endpoint === 'workflow'
  ? { endpoint, raw_path: p.workflow_path }
  : { endpoint, raw_path: path(p), head_branch: 'main', head_sha: p.source_sha };
const rejects = (actual, expected, code = 'invalid_github_workflow_path_v2') => assert.throws(() => compare(actual, expected), error => {
  assert.equal(error.message, code);
  assert.equal(error.code, code);
  assert.equal(Object.hasOwn(error, 'cause'), false);
  assert.deepEqual(Object.keys(error), ['code']);
  return true;
});
const mismatch = (actual, expected) => rejects(actual, expected, 'github_workflow_path_v2_mismatch');

test('all selected forms and endpoints compare without changing frozen inputs', () => {
  for (const form of forms) for (const endpoint of ['workflow', 'run', 'attempt']) {
    const p = Object.freeze(policy(form));
    const actual = Object.freeze(observation(p, endpoint));
    const before = JSON.stringify([actual, p]);
    assert.equal(compare(actual, p), undefined);
    assert.equal(JSON.stringify([actual, p]), before);
    assert.equal(compare(Object.assign(Object.create(null), actual), Object.assign(Object.create(null), p)), undefined);
  }
});

test('cross-form run/attempt observations never fall back; metadata stays bare', () => {
  for (const selected of forms) for (const supplied of forms) {
    if (selected === supplied) continue;
    for (const endpoint of ['run', 'attempt']) mismatch(observation(policy(supplied), endpoint), policy(selected));
  }
  for (const form of forms) {
    const p = policy(form);
    mismatch({ endpoint: 'workflow', raw_path: p.workflow_path + '@main' }, p);
    compare(observation(p, 'run'), p);
    mismatch({ ...observation(p, 'attempt'), raw_path: path(policy(forms.find(f => f !== form))) }, p);
    compare(observation(p, 'run'), p); // A/B equality cannot rescue a mismatched attempt.
  }
});

test('bounded raw path ambiguities are mismatches, never normalized', () => {
  for (const form of forms) {
    const p = policy(form), actual = observation(p);
    const wrong = [p.workflow_path + '@refs/heads/main', p.workflow_path + '@refs/tags/main',
      p.workflow_path + '@' + p.source_sha, p.workflow_path + '@dev', p.workflow_path + '@',
      p.workflow_path + '@main@main', '../' + actual.raw_path, actual.raw_path.replace('build', '%62uild'),
      actual.raw_path.replace('build', 'other'), actual.raw_path.replace('build', 'Build'),
      actual.raw_path.replace('/', '\\'), actual.raw_path + '?q=1', actual.raw_path + '#main',
      ' ' + actual.raw_path, actual.raw_path + '\n', '', 'other/repo/' + actual.raw_path];
    if (form === 'repository-main') wrong.push(actual.raw_path.replace('octocat', 'Octocat'), actual.raw_path.replace('octo-repo', 'other-repo'));
    for (const raw_path of wrong) mismatch({ ...actual, raw_path }, p);
    for (const head_branch of ['', 'Main', 'main\n', 'refs/heads/main', 'dev']) mismatch({ ...actual, head_branch }, p);
    mismatch({ ...actual, head_sha: 'b'.repeat(40) }, p);
    for (const head_sha of ['', 'A'.repeat(40), 'a'.repeat(39), 'a'.repeat(40) + '\n', null]) rejects({ ...actual, head_sha }, p);
  }
});

test('policy grammar/literals are exact and invalid precedes mismatch', () => {
  const p = policy(), actual = observation(p);
  const invalidFields = {
    policy: ['', 'cp-workflow-path-v1'], run_path_form: ['', 'relative', 'Relative-main'],
    repository_full_name: ['a/.', 'a/..', 'a/x.git', '-a/b', 'a-/b', 'a/_b', 'a/b/c', 'a/b\n', 'é/b', 'a'.repeat(40) + '/b', 'a/' + 'b'.repeat(101)],
    workflow_path: ['.github/workflows/a.yml@main', '.github/workflows/../a.yml', '.github/workflows/a.yml\n', '.github/workflows/a.YML', '.github/workflows/.a.yml'],
    source_sha: ['', 'A'.repeat(40), 'a'.repeat(40) + '\n'],
  };
  for (const [key, values] of Object.entries(invalidFields)) for (const value of values) {
    rejects({ ...actual, raw_path: 'wrong' }, { ...p, [key]: value });
  }
  const valid = { ...p, repository_full_name: 'A'.repeat(39) + '/' + 'B'.repeat(100), workflow_path: '.github/workflows/A_0-x.yaml' };
  compare(observation(valid), valid);
});

test('exact own enumerable data properties only, without executing getters', () => {
  const p = policy(), actual = observation(p);
  for (const side of ['actual', 'policy']) {
    const base = side === 'actual' ? actual : p;
    const check = value => side === 'actual' ? rejects(value, p) : rejects(actual, value);
    for (const value of [null, [], 'text', 1, Object.create(base), new Date()]) check(value);
    for (const key of Object.keys(base)) {
      const missing = { ...base }; delete missing[key]; check(missing);
      for (const value of [undefined, null, 1, {}, () => 'x']) check({ ...base, [key]: value });
      check(Object.defineProperty({ ...base }, key, { value: base[key], enumerable: false }));
      check(Object.defineProperty({ ...base }, key, { get() { assert.fail('getter executed'); }, enumerable: true }));
    }
    for (const key of ['extra', '__proto__', 'constructor', Symbol('extra')]) {
      check(Object.defineProperty({ ...base }, key, { value: 'x', enumerable: true }));
    }
    check(new Proxy(base, { ownKeys() { throw new Error('private reflection detail'); } }));
  }
  rejects({ ...actual, endpoint: 'unknown' }, p);
  rejects({ ...actual, endpoint: 'workflow' }, p);
  rejects({ endpoint: 'run', raw_path: actual.raw_path }, p);
});

test('descriptor snapshots avoid property reads and preserve readonly data', () => {
  const p = policy(), actual = observation(p);
  const trap = { get() { assert.fail('property read invoked'); } };
  compare(new Proxy(actual, trap), new Proxy(p, trap));
  for (const object of [p, actual]) for (const key of Object.keys(object)) {
    Object.defineProperty(object, key, { writable: false, configurable: false });
  }
  compare(actual, p);
});

test('constructed path inclusive cap for every form including metadata policy checks', () => {
  for (const form of forms) for (const total of [65534, 65535]) {
    const p = policy(form);
    const overhead = (form === 'bare' ? 0 : 5) + (form === 'repository-main' ? p.repository_full_name.length + 1 : 0);
    p.workflow_path = '.github/workflows/' + 'x'.repeat(total - overhead - '.github/workflows/'.length - '.yml'.length) + '.yml';
    assert.equal(Buffer.byteLength(path(p)), total);
    if (form !== 'bare') assert.ok(Buffer.byteLength(p.workflow_path) <= 65534);
    for (const endpoint of ['workflow', 'run', 'attempt']) {
      if (total === 65534) assert.equal(compare(observation(p, endpoint), p), undefined);
      else rejects(observation(p, endpoint), p);
    }
    if (total === 65535) rejects({ endpoint: 'workflow', raw_path: 'wrong' }, p);
  }
});

test('individual UTF8 limits precede mismatch, including multibyte and code-unit guards', () => {
  const p = policy(), actual = observation(p);
  for (const field of ['raw_path', 'head_branch']) {
    for (const value of ['x'.repeat(65534), 'é'.repeat(32767)]) {
      assert.equal(Buffer.byteLength(value), 65534);
      mismatch({ ...actual, [field]: value }, p);
    }
    for (const value of ['x'.repeat(65535), 'é'.repeat(32767) + 'x', '😀'.repeat(16384)]) rejects({ ...actual, [field]: value }, p);
  }
  rejects({ ...actual, raw_path: '' }, { ...p, workflow_path: 'x'.repeat(65535) });
});

test('legacy six-field decoder still rejects suffixed paths unchanged', () => {
  const raw = { id: 1, run_attempt: 1, workflow_id: 1, repository: { id: 1 }, head_repository: { id: 1 }, path: '.github/workflows/build.yml' };
  assert.equal(decodeGitHubRunIdentity(JSON.stringify(raw)).path, raw.path);
  for (const form of ['relative-main', 'repository-main']) assert.throws(
    () => decodeGitHubRunIdentity(JSON.stringify({ ...raw, path: path(policy(form)) })),
    { code: 'invalid_github_run_identity' });
});
