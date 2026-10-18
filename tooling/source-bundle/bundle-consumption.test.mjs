import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { decodeGitHubInProgressRunFactsV2, assertGitHubInProgressRunFactsV2 } from 'civicpulse-source-tooling-local/run-facts-v2';
import { assertGitHubWorkflowPathV2 } from 'civicpulse-source-tooling-local/workflow-path-v2';

test('standalone package exports reach reviewed helpers, not internal seams', async () => {
  for (const helper of [decodeGitHubInProgressRunFactsV2, assertGitHubInProgressRunFactsV2, assertGitHubWorkflowPathV2]) assert.equal(typeof helper, 'function');
  await assert.rejects(import('civicpulse-source-tooling-local/src/server/github-run-facts-v2-internal.mjs'), { code: 'ERR_PACKAGE_PATH_NOT_EXPORTED' });
});

test('locked dependency version and MIT notice match installed artifact', async () => {
  const root = new URL('../', import.meta.url);
  const installed = JSON.parse(await readFile(new URL('node_modules/lossless-json/package.json', root), 'utf8'));
  assert.equal(installed.version, '4.3.2'); assert.equal(installed.license, 'MIT');
  assert.equal(installed.repository.url, 'https://github.com/josdejong/lossless-json.git');
  assert.deepEqual(await readFile(new URL('node_modules/lossless-json/LICENSE.md', root)), await readFile(new URL('LOSSLESS-JSON-LICENSE.md', root)));
  const lock = JSON.parse(await readFile(new URL('package-lock.json', root), 'utf8'));
  assert.deepEqual(Object.keys(lock.packages).sort(), ['', 'node_modules/lossless-json']);
  assert.equal(lock.packages['node_modules/lossless-json'].integrity, 'sha512-TWT1oIGJKaHkme0nDFoW9Tsv0/IZxy6P8rzD03hZpk7de04PWGfl/uMj/WcENrJLNF4P+QGGByPjap6qx++bDQ==');
});

import { projectGitHubSourceResponse, canonicalizeGitHubPolicyJson } from 'civicpulse-source-tooling-local/source-evidence';
test('public source evidence export retains policy precision without internal import',()=>{
 const actual=projectGitHubSourceResponse('{"id":9007199254740993,"source_type":"Repository","source":"CivicPulse/fixture","enforcement":"active","bypass_actors":[],"unknown":1e-400}','ruleset_detail');
 assert.equal(actual.facts.id,'9007199254740993');assert.ok(actual.json.includes('1e-400'));
 assert.equal(canonicalizeGitHubPolicyJson('{"z":9007199254740993,"a":1e-400}'),'{"a":1e-400,"z":9007199254740993}');
});
