import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createCivicPulseClient, ApiError } from '../src/client.mjs';
const config = process.argv[2] ? JSON.parse(readFileSync(process.argv[2],'utf8')) : {
  url:process.env.SUPABASE_URL,publishableKey:process.env.SUPABASE_PUBLISHABLE_KEY,
};
const client=createCivicPulseClient(config);
assert.ok(Array.isArray(await client.listPublished()));
await assert.rejects(client.listDrafts(),e=>e instanceof ApiError && [401,403].includes(e.status));
await assert.rejects(client.saveDraft('organization',{id:'anonymous-must-not-write'},0),e=>e instanceof ApiError && [401,403].includes(e.status));
console.log('Hosted HTTP checks passed: public reads work; anonymous draft reads and writes are denied.');
