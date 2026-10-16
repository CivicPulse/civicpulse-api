// Bootstrap this verifier by its independently reviewed SHA256 before execution.
// Builtins only: never imports or executes any artifact code.
import { lstat, readdir, readFile, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = () => { throw new Error('invalid_source_tooling_bundle'); };
const digest = value => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value) && value.length === 64;
const safePath = value => typeof value === 'string' && value.split('/').every(part => /^[A-Za-z0-9][A-Za-z0-9._-]*$/u.exec(part)?.[0] === part && part !== '.' && part !== '..');

export async function verifySourceToolingBundle(rootArgument, expectedDigest) {
  if (!digest(expectedDigest)) fail();
  const root = resolve(rootArgument);
  const parentStat = await lstat(dirname(root));
  if (!parentStat.isDirectory() || (parentStat.mode & 0o7777) !== 0o700 || typeof process.getuid !== 'function' || parentStat.uid !== process.getuid()) fail();
  // Also reject symlink ancestors. Parent ownership/concurrent writers are an
  // operational precondition, not a race-safety guarantee of these checks.
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink() || rootStat.uid !== process.getuid() || (rootStat.mode & 0o7777) !== 0o755 || await realpath(root) !== root) fail();
  const manifestPath = join(root, 'manifest.json');
  const stat = await lstat(manifestPath);
  if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o7777) !== 0o644 || stat.size > 1048576) fail();
  const bytes = await readFile(manifestPath);
  if (hash(bytes) !== expectedDigest) fail();
  const manifest = JSON.parse(bytes);
  if (manifest.format !== 'civicpulse-source-tooling-local-v1' || !/^[0-9a-f]{40}$/u.test(manifest.source_commit) || manifest.source_commit.length !== 40 || !manifest.files || !manifest.directories) fail();
  const expectedFiles = new Set(['manifest.json']);
  const expectedDirectories = new Set();
  for (const [name, entry] of Object.entries(manifest.files)) {
    if (!safePath(name) || name === 'manifest.json' || !digest(entry.sha256) || !Number.isSafeInteger(entry.bytes) || entry.bytes < 0 || entry.mode !== '0644' || entry.git_mode !== '100644' || !safePath(entry.source_path)) fail();
    expectedFiles.add(name);
    const parts = name.split('/'); parts.pop();
    while (parts.length) { expectedDirectories.add(parts.join('/')); parts.pop(); }
  }
  if (JSON.stringify(Object.keys(manifest.directories).sort()) !== JSON.stringify([...expectedDirectories].sort())) fail();
  for (const mode of Object.values(manifest.directories)) if (mode !== '0755') fail();
  const seenFiles = new Set(), seenDirectories = new Set();
  const walk = async (directory, prefix = '') => {
    for (const name of await readdir(directory)) {
      const relative = prefix + name, path = join(directory, name), info = await lstat(path);
      if (info.isDirectory() && !info.isSymbolicLink()) {
        if (!expectedDirectories.has(relative) || (info.mode & 0o7777) !== 0o755) fail();
        seenDirectories.add(relative); await walk(path, relative + '/');
      } else {
        if (!expectedFiles.has(relative) || !info.isFile() || info.nlink !== 1 || (info.mode & 0o7777) !== 0o644) fail();
        seenFiles.add(relative);
        if (relative !== 'manifest.json') {
          const entry = manifest.files[relative];
          if (info.size !== entry.bytes || hash(await readFile(path)) !== entry.sha256) fail();
        }
      }
    }
  };
  await walk(root);
  if (seenFiles.size !== expectedFiles.size || seenDirectories.size !== expectedDirectories.size) fail();
  return manifest;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.length !== 4) throw new Error('Usage: node verify-bundle.mjs DIRECTORY INDEPENDENT_MANIFEST_SHA256');
  const manifest = await verifySourceToolingBundle(process.argv[2], process.argv[3]);
  console.log(`Verified ${manifest.format} source ${manifest.source_commit}`);
}
