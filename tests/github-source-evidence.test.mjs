import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeGitHubSourceResponse, projectGitHubSourceResponse, canonicalizeGitHubPolicyJson, assembleGitHubProtectionEvidence, assembleGitHubSourceEvidence } from '../src/server/github-source-evidence.mjs';
import { sourceJsonStats, parseBoundedSourceAggregate } from '../src/server/github-run-json.mjs';
const invalid=e=>e.code==='invalid_github_source_evidence'&&!e.cause&&e.message==='invalid_github_source_evidence';
const detail='{"id":9007199254740993,"source_type":"Repository","source":"CivicPulse/fixture","enforcement":"active","bypass_actors":[],"unknown":[1e-400,9007199254740995,0.12345678901234567890123456789]}';
const context={repository_full_name:'CivicPulse/fixture',owner:'CivicPulse',owner_type:'Organization',scope:'repository'};
const page=json=>[{page:1,next_page:null,json}];
const input=()=>({classic_json:'{}',list_pages:page('['+detail+']'),detail_json:[detail],effective_pages:page('[{"ruleset_id":9007199254740993,"ruleset_source_type":"Repository","ruleset_source":"CivicPulse/fixture","type":"pull_request"}]')});
test('public response facts retain large identities and complete policy numeric tokens',()=>{
  const p=projectGitHubSourceResponse(detail,'ruleset_detail');assert.equal(p.facts.id,'9007199254740993');assert.equal(p.facts.bypass_present,true);assert.ok(p.json.includes('1e-400'));assert.ok(p.json.includes('0.12345678901234567890123456789'));
  const repo=projectGitHubSourceResponse('{"id":9007199254740993,"owner":{"id":9007199254740994,"type":"Organization"},"full_name":"CivicPulse/fixture","fork":false,"archived":false,"default_branch":"main"}','repository');assert.equal(repo.facts.owner_type,'Organization');assert.equal(repo.facts.owner_id,'9007199254740994');assert.ok(!repo.json.includes('owner_type'));
  for(const raw of [detail.replace('9007199254740993','1e2'),detail.replace('9007199254740993','"9007199254740993"'),detail.replace('"bypass_actors":[],',''),detail.replace('"id":9007199254740993','"id":9007199254740993,"\\u0069d":9007199254740993')])assert.throws(()=>projectGitHubSourceResponse(raw,'ruleset_detail'),invalid);
});
test('canonical policy preserves number lexemes, unknown fields, arrays and prototype keys',()=>{
 assert.equal(canonicalizeGitHubPolicyJson('{"z":1e-400,"__proto__":{"x":9007199254740993},"a":[2,1]}'),'{"__proto__":{"x":9007199254740993},"a":[2,1],"z":1e-400}');
 assert.notEqual(canonicalizeGitHubPolicyJson('{"x":1}'),canonicalizeGitHubPolicyJson('{"x":1.0}'));
});
test('complete detail membership, scope, visibility, contributor and pagination closure',()=>{
 assert.ok(assembleGitHubProtectionEvidence(input(),context).includes('1e-400'));
 for(const mutate of [x=>x.detail_json=[],x=>x.detail_json=[detail.replace('9007199254740993','9007199254740994')],x=>x.detail_json=[detail.replace('CivicPulse/fixture','other/repo')],x=>x.detail_json=[detail.replace('"bypass_actors":[],','')],x=>x.list_pages[0].next_page=2,x=>x.list_pages.push({page:1,next_page:null,json:'[]'}),x=>x.list_pages[0].json='['+detail+','+detail+']',x=>x.effective_pages[0].json=x.effective_pages[0].json.replace('9007199254740993','9007199254740994')]){const x=input();mutate(x);assert.throws(()=>assembleGitHubProtectionEvidence(x,context),invalid);}
 const inherited=input();for(const key of ['list_pages','effective_pages'])inherited[key][0].json=inherited[key][0].json.replaceAll('Repository','Organization').replaceAll('CivicPulse/fixture','CivicPulse');inherited.detail_json=[detail.replaceAll('Repository','Organization').replaceAll('CivicPulse/fixture','CivicPulse')];assert.ok(assembleGitHubProtectionEvidence(inherited,context));
});
test('full final list page requires empty next probe, canonical numeric detail order',()=>{
 const ds=Array.from({length:100},(_,i)=>detail.replaceAll('9007199254740993',String(i+1)));
 const x={classic_json:'{}',list_pages:[{page:1,next_page:null,json:'['+ds.join(',')+']'},{page:2,next_page:null,json:'[]'}],detail_json:ds,effective_pages:page('[]')};
 assert.ok(assembleGitHubProtectionEvidence(x,context));x.list_pages.pop();assert.throws(()=>assembleGitHubProtectionEvidence(x,context),invalid);
});
test('raw per-response bounds unchanged; aggregate 262144 token inclusive boundary',()=>{
 // [0,...,0,[]] has 2n+4 lexical tokens: punctuation counted independently.
 const at='['+'0,'.repeat(131070)+'[]]';assert.equal(sourceJsonStats(at,true).tokens,262144);
 assert.equal(canonicalizeGitHubPolicyJson(at),at);
 const over=at.slice(0,-3)+'[0]]';assert.throws(()=>canonicalizeGitHubPolicyJson(over),invalid);let calls=0;assert.throws(()=>parseBoundedSourceAggregate(over,()=>{calls++;}));assert.equal(calls,0);
 assert.throws(()=>decodeGitHubSourceResponse(at,'effective_rules'),invalid);
});
test('aggregate depth72/string65536/8MiB at and one-over controls',()=>{
 const at='['.repeat(72)+'0'+']'.repeat(72);assert.equal(canonicalizeGitHubPolicyJson(at),at);assert.throws(()=>canonicalizeGitHubPolicyJson('['+at+']'),invalid);
 const string='"'+'a'.repeat(65534)+'"';assert.equal(canonicalizeGitHubPolicyJson(string),string);assert.throws(()=>canonicalizeGitHubPolicyJson('"'+'a'.repeat(65535)+'"'),invalid);
 const body='['+Array(127).fill(string).join(',')+']';const exact=body+' '.repeat(8388608-Buffer.byteLength(body));assert.equal(Buffer.byteLength(exact),8388608);assert.ok(canonicalizeGitHubPolicyJson(exact));assert.throws(()=>canonicalizeGitHubPolicyJson(exact+' '),invalid);
});
test('assembly never invokes accessors; numbers remain raw JSON tokens',()=>{
 const x=Object.fromEntries(['repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','protection_before','protection_after','workflow_file','requests'].map(k=>[k,'{}']));x.requests='[]';x.protection_before='{"x":1e-400}';assert.ok(assembleGitHubSourceEvidence(x).includes('1e-400'));
 Object.defineProperty(x,'workflow',{get(){throw Error('do not invoke');}});assert.throws(()=>assembleGitHubSourceEvidence(x),invalid);
});
test('depth64 upstream remains valid inside actual config and evidence wrappers',()=>{
 const deep='['.repeat(63)+'0'+']'.repeat(63);
 const raw='{"unknown":'+deep+'}';assert.equal(sourceJsonStats(raw).tokens,131);
 assert.ok(decodeGitHubSourceResponse(raw,'classic'));
 const config='{"source":{"protection_bundle":{"classic":'+raw+',"rulesets":[],"effective_rules":[]}}}';
 assert.ok(canonicalizeGitHubPolicyJson(config));
 const evidence='{"schema_version":1,"protection_before":{"classic":'+raw+',"rulesets":[],"effective_rules":[]}}';
 assert.ok(canonicalizeGitHubPolicyJson(evidence));
 const challenge='{"config":'+config+'}';assert.ok(canonicalizeGitHubPolicyJson(challenge));
 assert.throws(()=>decodeGitHubSourceResponse('{"extra":'+raw+'}','classic'),invalid);
});
test('equivalent JSONB numeric spellings intentionally fail lexical policy equality',()=>{
 const expanded='0.'+'0'.repeat(399)+'1';
 assert.notEqual(canonicalizeGitHubPolicyJson('{"x":1e-400}'),canonicalizeGitHubPolicyJson('{"x":'+expanded+'}'));
 assert.equal(canonicalizeGitHubPolicyJson('{"x":9007199254740993}'),canonicalizeGitHubPolicyJson('{"x":9007199254740993}'));
});
