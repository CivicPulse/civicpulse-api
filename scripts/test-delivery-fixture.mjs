// External-process contract test. Synthetic acquisition only; actual SQL receipts.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { parse, stringify, LosslessNumber } from 'lossless-json';
import { sourceJsonStats } from '../src/server/github-run-json.mjs';
import { decodeGitHubSourceResponse, assembleGitHubSourceEvidence } from '../src/server/github-source-evidence.mjs';
import { createCivicPulseClient } from '../src/client.mjs';

const fixturePath=new URL('./serve-delivery-fixture.mjs',import.meta.url).pathname;
const selectedSha='97a7fa79ff85e76ea35bf9ba994f1d561a05c90c'; // known frozen Web source; no checkout proof implied
for(const invalidArgs of [[],['--test-only','--source-sha',selectedSha+'\n'],['--test-only','--source-sha'],['--test-only','--source-sha','a'.repeat(39)],['--test-only','--source-sha','A'.repeat(40)],['--test-only','--source-sha',selectedSha,'--source-sha',selectedSha],['--test-only','--unknown',selectedSha],['--source-sha',selectedSha,'--test-only']]) {
 const result=spawnSync(process.execPath,[fixturePath,...invalidArgs],{encoding:'utf8',timeout:10000});assert.equal(result.status,2);assert.equal(result.stdout,'');
}
const child=spawn(process.execPath,[fixturePath,'--test-only','--source-sha',selectedSha],{stdio:['pipe','pipe','inherit']});
const messages=[],waiters=[];
createInterface({input:child.stdout}).on('line',line=>{const m=JSON.parse(line); const w=waiters.shift(); if(w)w(m);else messages.push(m);});
const exited=new Promise(resolve=>child.on('exit',resolve));
const next=()=>messages.length?Promise.resolve(messages.shift()):Promise.race([new Promise(resolve=>waiters.push(resolve)),exited.then(code=>{throw Error(`fixture exited ${code}`);})]);
const timeout=setTimeout(()=>{child.kill('SIGTERM');process.exitCode=1;},180000);
let sequence=0;
const send=async(command,args={},id=`request-${++sequence}`)=>{child.stdin.write(JSON.stringify({id,command,args})+'\n');return next();};
const ok=async(command,args={},id)=>{const m=await send(command,args,id);assert.equal(m.type,'result',JSON.stringify(m));return m.result;};
try {
  const ready=await next(); assert.equal(ready.type,'ready',JSON.stringify(ready)); assert.equal(ready.schema_version,1);assert.equal(ready.inputs.source_sha,selectedSha);
  const api=createCivicPulseClient({url:ready.url,publishableKey:ready.publishableKey});
  assert.deepEqual(await api.publicationManifest(),ready.manifest);
  assert.equal(ready.manifest.generation,'8'); assert.equal(ready.manifest.bootstrap_complete,true);
  const initial=await ok('inspect'); assert.equal(initial.receipts,0);assert.equal(initial.job,null);
  assert.equal((await send('claim')).code,'55000');
  const config=parse(ready.config_json); const p=config.provider,b=ready.inputs.baseline,s=config.source;
  const baseline={schema_version:1,project:{id:p.project_id,name:p.project_name,canonical_deployment_id:b.deployment_id,production_branch:'main'},deployment:{id:b.deployment_id,project_id:p.project_id,project_name:p.project_name,environment:'production',stage:'deploy',status:'success',source_sha:b.source_sha,branch:'main'},markers:{deployment:null,production:null,pages:null},artifact:{artifact_sha256:b.artifact_sha256,served_inventory_sha256:b.served_inventory_sha256},github_terminal:null,requests:['project_before','project_after','deployment','marker_deployment','marker_production','marker_pages','artifact_files'].map(endpoint_key=>({endpoint_key,page:1,status:endpoint_key.startsWith('marker_')?404:200,request_id:null}))};
  const bc=await ok('openBaseline'); assert.equal(bc.config_json,ready.config_json);
  // Exact 8MiB JSON text, dominated by escaped backslashes, fits the one-text-field envelope.
  const rawString='"'+'\\\\'.repeat(32767)+'"';
  const rawBody='['+Array(127).fill(rawString).join(',')+']';
  const maximum=rawBody+' '.repeat(8388608-Buffer.byteLength(rawBody));
  assert.equal(Buffer.byteLength(maximum),8388608);
  const envelope=JSON.stringify({id:'maximum',command:'recordBaseline',args:{challenge_id:bc.challenge_id,evidence_json:maximum}});
  assert.ok(Buffer.byteLength(envelope)<=16781312);
  assert.equal((await send('recordBaseline',{challenge_id:bc.challenge_id,evidence_json:maximum},'maximum')).code,'22023');
  assert.equal((await send('recordBaseline',{challenge_id:bc.challenge_id,evidence_json:maximum+' '})).code,'invalid_fixture_command');
  const bad=structuredClone(baseline);delete bad.artifact;
  assert.equal((await send('recordBaseline',{challenge_id:bc.challenge_id,evidence_json:JSON.stringify(bad)})).code,'22023');
  assert.equal((await ok('inspect')).receipts,0);
  const br=await ok('recordBaseline',{challenge_id:bc.challenge_id,evidence_json:JSON.stringify(baseline)});
  await ok('approveBaseline',{observation_id:br.observation_id});
  const r={id:ready.inputs.run_id.split(':')[0],run_attempt:'1',workflow_id:s.workflow_id,path:s.workflow_path+'@main',repository_id:s.repository_id,head_repository_id:s.repository_id,event:'workflow_dispatch',head_branch:'main',head_sha:ready.inputs.source_sha,status:'in_progress',conclusion:null,actor_id:'9007199254740995',triggering_actor_id:'9007199254740996',referenced_workflows:[]};
  const source={schema_version:1,repository:{id:s.repository_id,owner_id:s.repository_owner_id,full_name:s.repository_full_name,fork:false,archived:false,default_branch:'main'},workflow:{id:s.workflow_id,path:s.workflow_path,state:'active'},run_before:r,run_attempt:r,run_after:r,ref_before:{ref:s.ref,object_type:'commit',sha:ready.inputs.source_sha},ref_after:{ref:s.ref,object_type:'commit',sha:ready.inputs.source_sha},protection_before:s.protection_bundle,protection_after:s.protection_bundle,workflow_file:{path:s.workflow_path,source_sha:ready.inputs.source_sha,sha256:s.workflow_file_sha256,bytes:123},requests:['repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','classic_before','classic_after','rulesets_before','rulesets_after','effective_rules_before','effective_rules_after','workflow_file'].map(endpoint_key=>({endpoint_key,page:1,status:200,github_request_id:null}))};
  const sc=await ok('openSource');assert.equal(sc.source_sha,selectedSha);
  const wrong=parse(stringify(source));wrong.run_after.head_sha='0'.repeat(40);
  assert.equal((await send('recordSource',{challenge_id:sc.challenge_id,evidence_json:stringify(wrong)})).code,'40001');
  assert.equal((await ok('inspect')).receipts,1);
  const rawRun=stringify({...r,id:new LosslessNumber(r.id),run_attempt:new LosslessNumber(r.run_attempt),workflow_id:new LosslessNumber(r.workflow_id),repository:{id:new LosslessNumber(r.repository_id)},head_repository:{id:new LosslessNumber(r.head_repository_id)},actor:{id:new LosslessNumber(r.actor_id)},triggering_actor:{id:new LosslessNumber(r.triggering_actor_id)}});
  const runJson=decodeGitHubSourceResponse(rawRun,'run');
  const parts=Object.fromEntries(Object.entries(source).filter(([key])=>key!=='schema_version').map(([key,value])=>[key,stringify(value)]));
  parts.run_before=runJson;parts.run_attempt=decodeGitHubSourceResponse(rawRun,'attempt');parts.run_after=runJson;
  const evidenceJson=assembleGitHubSourceEvidence(parts);
  const receipt=await ok('recordSource',{challenge_id:sc.challenge_id,evidence_json:evidenceJson});
  assert.ok(receipt.observation_id);assert.equal(receipt.source_sha,selectedSha);
  const claim=await ok('claim',{},'claim-once');assert.equal(claim.target_generation,'8');assert.equal((await ok('inspect')).job.state,'queued');
  assert.deepEqual(await ok('claim',{},'claim-once'),claim);
  assert.equal((await send('heartbeat',{},'claim-once')).code,'invalid_fixture_command');
  await ok('heartbeat');
  await ok('transition',{expected_state:'queued',state:'exporting',evidence:{}});
  const records=[];
  for(let offset=0;;offset+=2){const page=await api.listPublished(undefined,{limit:2,offset});records.push(...page);if(page.length<2)break;}
  assert.equal(records.length,7);assert.deepEqual(records.map(({kind,id,revision})=>({kind,id,revision:String(revision)})),ready.manifest.records);
  assert.equal((await api.layerGeoJSON(ready.expected.ids.layer)).features.length,2);
  assert.equal((await api.layerGeoJSON('event-locations')).features.length,1);
  assert.deepEqual(await api.publicationManifest(),ready.manifest);
  await ok('transition',{expected_state:'exporting',state:'building',evidence:{publication_manifest:ready.manifest,snapshot_sha256:'1'.repeat(64)}});
  await ok('transition',{expected_state:'building',state:'validating',evidence:{artifact_sha256:'2'.repeat(64)}});
  await ok('transition',{expected_state:'validating',state:'ready',evidence:{}});
  const final=await ok('inspect');assert.equal(final.precision_preserved,true);assert.equal(final.job.state,'ready');assert.equal(final.job.source_sha,selectedSha);assert.equal(final.receipts,2);assert.equal(final.consumed_receipts,2);assert.equal(final.external_authority,false);assert.equal(final.live_inventory_complete,false);
  assert.equal(final.calls.filter(c=>c.id==='claim-once'&&c.outcome==='result').length,1);
  assert.equal((await send('beginDeploy')).code,'invalid_fixture_command');
  assert.equal((await fetch(ready.url+'/rest/v1/rpc/save_draft',{method:'POST',headers:{apikey:ready.publishableKey}})).status,404);
  assert.deepEqual(await api.publicationManifest(),ready.manifest);
  assert.equal((await ok('close')).closed,true);assert.equal(await exited,0);
  console.log(JSON.stringify({config:sourceJsonStats(ready.config_json,true),evidence:sourceJsonStats(evidenceJson,true)}));
  console.log('Delivery fixture: actual baseline/source open-record, operator approval, claim/heartbeat/export/build/ready; 7 records, generation8, two consumed receipts; invalid evidence/replay/read-only/no-live controls passed');
} finally {clearTimeout(timeout);if(child.exitCode===null){child.stdin.end();await exited;}}
