import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, cp, chmod, readFile, writeFile, rm, symlink, link, lstat } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { verifySourceToolingBundle as verify } from '../scripts/verify-source-tooling-bundle.mjs';

const root = new URL('../', import.meta.url);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('directory bundle export and verifier enforce pinned bytes, modes and exact inventory', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'cp-source-bundle-test-'));
  t.after(() => rm(parent, { recursive: true, force: true }));
  await chmod(parent, 0o700);
  assert.equal((await lstat(parent)).mode & 0o7777, 0o700);
  const repository = join(parent, 'repo'); await mkdir(repository);
  // Isolated fixture Git repository, never the API/shared index.
  for (const directory of ['src/server', 'tooling/source-bundle']) await cp(new URL(directory, root), join(repository, directory), { recursive: true });
  for (const directory of ['tests', 'scripts', 'docs']) await mkdir(join(repository, directory));
  for (const file of ['docs/source-evidence-consumer.md', 'tests/github-source-evidence.test.mjs', 'LICENSE', 'scripts/export-source-tooling.mjs', 'scripts/verify-source-tooling-bundle.mjs', 'tests/github-run-identity.test.mjs', 'tests/github-run-facts-v2.test.mjs', 'tests/github-workflow-path-v2.test.mjs']) {
    await cp(new URL(file, root), join(repository, file));
  }
  const git = args => execFileSync('git', ['-C', repository, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  git(['init', '-q']); git(['add', '.']);
  const commit = () => { git(['-c', 'user.name=Bundle Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'test fixture']); return git(['rev-parse', 'HEAD']).trim(); };
  const source = commit();
  const exporter = join(repository, 'scripts/export-source-tooling.mjs');
  const exportTo = (destination, revision = source) => JSON.parse(execFileSync(process.execPath, [exporter, revision, destination], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  const original = join(parent, 'original'), first = exportTo(original);
  const second = exportTo(join(parent, 'second'));
  assert.equal(first.source_commit, source); assert.equal(first.manifest_sha256, second.manifest_sha256);
  assert.equal(first.verifier_sha256, hash(await readFile(new URL('scripts/verify-source-tooling-bundle.mjs', root))));
  const manifest = await verify(original, first.manifest_sha256);
  assert.equal(manifest.source_commit, source);
  assert.equal(Object.keys(manifest.files).length, 22);
  assert.equal(manifest.files['src/server/github-run-facts-v2.mjs'].sha256, hash(await readFile(new URL('src/server/github-run-facts-v2.mjs', root))));
  assert.throws(() => exportTo(original));
  assert.throws(() => exportTo(join(parent, 'short-commit'), source.slice(0, 7)));
  await assert.rejects(verify(original, '0'.repeat(64)));
  await assert.rejects(verify(original, undefined));

  let serial = 0;
  const changed = async mutate => {
    const directory = join(parent, 'changed-' + serial++);
    await cp(original, directory, { recursive: true });
    await mutate(directory);
    await assert.rejects(verify(directory, first.manifest_sha256));
  };
  for (const [name, mutate] of [
    ['unexpected file', d => writeFile(join(d, 'extra.mjs'), '')],
    ['unexpected empty directory', d => mkdir(join(d, 'extra'))],
    ['preexisting node_modules', d => mkdir(join(d, 'node_modules'))],
    ['missing file', d => rm(join(d, 'LICENSE'))],
    ['modified bytes', d => writeFile(join(d, 'LICENSE'), 'changed')],
    ['executable file', d => chmod(join(d, 'LICENSE'), 0o755)],
    ['writable directory', d => chmod(join(d, 'src'), 0o777)],
    ['wrong root mode', d => chmod(d, 0o777)],
    ['external symlink', async d => { await rm(join(d, 'LICENSE')); await symlink(join(original, 'LICENSE'), join(d, 'LICENSE')); }],
    ['external hardlink alias', async d => { await rm(join(d, 'LICENSE')); await link(join(original, 'LICENSE'), join(d, 'LICENSE')); }],
    ['manifest hardlink alias', async d => { await link(join(d, 'manifest.json'), join(parent, 'manifest-alias')); }],
    ['FIFO special file', async d => { await rm(join(d, 'LICENSE')); execFileSync('mkfifo', [join(d, 'LICENSE')]); }],
  ]) await t.test(name, () => changed(mutate));

  await t.test('root and ancestor symlinks reject; exporter refuses symlink parent', async () => {
    const alias = join(parent, 'root-alias'); await symlink(original, alias);
    await assert.rejects(verify(alias, first.manifest_sha256));
    const ancestor = join(parent, 'parent-alias'); await symlink(parent, ancestor);
    await assert.rejects(verify(join(ancestor, 'second'), second.manifest_sha256));
    assert.throws(() => exportTo(join(ancestor, 'new-artifact')));
  });
  await t.test('export and verification require a private current-user parent', async () => {
    const shared = join(parent, 'shared'); await mkdir(shared, { mode: 0o755 }); await chmod(shared, 0o755);
    assert.throws(() => exportTo(join(shared, 'bundle')));
    await cp(join(parent, 'second'), join(shared, 'bundle'), { recursive: true });
    await assert.rejects(verify(join(shared, 'bundle'), second.manifest_sha256));
    await chmod(shared, 0o700);
    await verify(join(shared, 'bundle'), second.manifest_sha256);
  });
  await t.test('trusted-digest manifests still cannot introduce unsafe paths or directory maps', async () => {
    for (const name of ['../escape', '/absolute', 'src/../escape', 'bad\n', 'src\\escape']) {
      const directory = join(parent, 'path-' + serial++); await cp(join(parent, 'second'), directory, { recursive: true });
      const value = structuredClone(manifest); value.files[name] = value.files.LICENSE;
      const bytes = Buffer.from(JSON.stringify(value)); await writeFile(join(directory, 'manifest.json'), bytes);
      await assert.rejects(verify(directory, hash(bytes)));
    }
  });
  await t.test('exporter ignores uncommitted source changes and rejects executable Git blobs', async () => {
    await writeFile(join(repository, 'src/server/github-run-facts-v2.mjs'), 'unreviewed working tree bytes');
    const clean = exportTo(join(parent, 'pinned'));
    assert.equal(clean.manifest_sha256, first.manifest_sha256);
    await chmod(join(repository, 'src/server/github-run-facts-v2.mjs'), 0o755);
    git(['add', 'src/server/github-run-facts-v2.mjs']); git(['update-index', '--chmod=+x', 'src/server/github-run-facts-v2.mjs']);
    const executable = commit();
    assert.throws(() => exportTo(join(parent, 'executable'), executable));
    await rm(join(repository, 'src/server/github-run-facts-v2.mjs'));
    await symlink('github-run-identity.mjs', join(repository, 'src/server/github-run-facts-v2.mjs'));
    git(['add', 'src/server/github-run-facts-v2.mjs']); const symbolic = commit();
    assert.throws(() => exportTo(join(parent, 'symbolic'), symbolic));
  });
});
