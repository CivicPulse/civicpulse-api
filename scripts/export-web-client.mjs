import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
const output = process.argv[2];
if (!output) throw new Error('Usage: node scripts/export-web-client.mjs OUTPUT_DIRECTORY');
const files = ['client.mjs','database.types.ts','publication.types.ts'];
await mkdir(resolve(output), { recursive:true });
const manifest = { contract:'civicpulse-content-api-v1+publication-v1-local', files:{} };
for (const name of files) {
  const bytes = await readFile(new URL(`../src/${name}`,import.meta.url));
  await writeFile(join(output,name),bytes);
  manifest.files[name] = { sha256:createHash('sha256').update(bytes).digest('hex') };
}
await writeFile(join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Exported self-contained client/types and checksum manifest to ${resolve(output)}`);
