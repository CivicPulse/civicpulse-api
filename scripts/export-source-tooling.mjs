import { execFileSync } from 'node:child_process';
import { mkdir, writeFile, chmod, realpath, lstat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [commit, output] = process.argv.slice(2);
if (process.argv.length !== 4 || !/^[0-9a-f]{40}$/u.test(commit ?? '') || commit.length !== 40 || !output) throw new Error('Usage: node scripts/export-source-tooling.mjs FULL_SOURCE_COMMIT NEW_OUTPUT_DIRECTORY');
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const git = args => execFileSync('git', ['-C', repository, ...args], { maxBuffer: 4 * 1024 * 1024 });
if (git(['rev-parse', '--verify', commit + '^{commit}']).toString().trim() !== commit) throw new Error('invalid_source_commit');
const modules = ['github-terminal-run.mjs', 'github-terminal-run.d.mts', 'github-source-evidence.mjs', 'github-source-evidence.d.mts', 'github-run-json.mjs', 'github-run-identity.mjs', 'github-run-identity.d.mts', 'github-workflow-path-v2.mjs', 'github-workflow-path-v2.d.mts', 'github-run-facts-v2.mjs', 'github-run-facts-v2-internal.mjs', 'github-run-facts-v2.d.mts'];
const files = Object.fromEntries([
  ...modules.map(name => ['src/server/' + name, 'src/server/' + name]),
  ...['github-terminal-run.test.mjs', 'github-source-evidence.test.mjs', 'github-run-identity.test.mjs', 'github-workflow-path-v2.test.mjs', 'github-run-facts-v2.test.mjs'].map(name => ['tests/' + name, 'tests/' + name]),
  ['tests/bundle-consumption.test.mjs', 'tooling/source-bundle/bundle-consumption.test.mjs'],
  ['package.json', 'tooling/source-bundle/package.json'], ['package-lock.json', 'tooling/source-bundle/package-lock.json'],
  ['LICENSE', 'LICENSE'], ['LOSSLESS-JSON-LICENSE.md', 'tooling/source-bundle/LOSSLESS-JSON-LICENSE.md'],
  ['verify-bundle.mjs', 'scripts/verify-source-tooling-bundle.mjs'],
  ['README.md', 'tooling/source-bundle/README.md'], ['SOURCE-EVIDENCE.md', 'docs/source-evidence-consumer.md'],
]);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = { format: 'civicpulse-source-tooling-local-v1', source_commit: commit,
  entrypoints: { './terminal-run': { import: 'src/server/github-terminal-run.mjs', types: 'src/server/github-terminal-run.d.mts' }, './source-evidence': { import: 'src/server/github-source-evidence.mjs', types: 'src/server/github-source-evidence.d.mts' }, './run-facts-v2': { import: 'src/server/github-run-facts-v2.mjs', types: 'src/server/github-run-facts-v2.d.mts' }, './workflow-path-v2': { import: 'src/server/github-workflow-path-v2.mjs', types: 'src/server/github-workflow-path-v2.d.mts' } },
  dependency: { name: 'lossless-json', version: '4.3.2', resolved: 'https://registry.npmjs.org/lossless-json/-/lossless-json-4.3.2.tgz', integrity: 'sha512-TWT1oIGJKaHkme0nDFoW9Tsv0/IZxy6P8rzD03hZpk7de04PWGfl/uMj/WcENrJLNF4P+QGGByPjap6qx++bDQ==', license: 'MIT', repository: 'https://github.com/josdejong/lossless-json.git' },
  directories: {}, files: {} };
const payloads = new Map();
// Resolve all allowlisted regular blobs before creating any artifact directory.
for (const name of Object.keys(files).sort()) {
  const source = files[name];
  const tree = git(['ls-tree', '-z', commit, '--', source]).toString();
  if (!/^100644 blob [0-9a-f]{40}\t/u.test(tree) || tree.split('\0').length !== 2 || tree.slice(tree.indexOf('\t') + 1, -1) !== source) throw new Error('invalid_source_blob_mode');
  const bytes = git(['show', commit + ':' + source]); payloads.set(name, bytes);
  manifest.files[name] = { sha256: hash(bytes), bytes: bytes.length, mode: '0644', git_mode: '100644', source_path: source };
  const parts = name.split('/'); parts.pop();
  while (parts.length) { manifest.directories[parts.join('/')] = '0755'; parts.pop(); }
}
manifest.directories = Object.fromEntries(Object.entries(manifest.directories).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
const destination = resolve(output);
if (await realpath(dirname(destination)) !== dirname(destination)) throw new Error('symlink_output_parent');
const parent = await lstat(dirname(destination));
if (!parent.isDirectory() || (parent.mode & 0o7777) !== 0o700 || typeof process.getuid !== 'function' || parent.uid !== process.getuid()) throw new Error('private_owned_parent_required');
await mkdir(destination, { mode: 0o755 }); // Never overwrite/reuse an existing path.
await chmod(destination, 0o755);
for (const name of Object.keys(manifest.directories)) { await mkdir(join(destination, name), { mode: 0o755 }); await chmod(join(destination, name), 0o755); }
for (const [name, bytes] of payloads) { await writeFile(join(destination, name), bytes, { flag: 'wx', mode: 0o644 }); await chmod(join(destination, name), 0o644); }
const bytes = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
await writeFile(join(destination, 'manifest.json'), bytes, { flag: 'wx', mode: 0o644 }); await chmod(join(destination, 'manifest.json'), 0o644);
console.log(JSON.stringify({ source_commit: commit, manifest_sha256: hash(bytes), verifier_sha256: manifest.files['verify-bundle.mjs'].sha256, output: destination }, null, 2));
