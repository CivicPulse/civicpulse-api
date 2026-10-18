// External-process contract test. Synthetic acquisition only; actual SQL receipts.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { parse, stringify, LosslessNumber } from 'lossless-json';
import { sourceJsonStats } from '../src/server/github-run-json.mjs';
import { decodeGitHubSourceResponse, assembleGitHubSourceEvidence } from '../src/server/github-source-evidence.mjs';
import { decodeGitHubTerminalRun, assertGitHubTerminalRun } from '../src/server/github-terminal-run.mjs';
import { createCivicPulseClient } from '../src/client.mjs';

const fixturePath=new URL('./serve-delivery-fixture.mjs',import.meta.url).pathname;
const m23=process.argv.includes('--m23');
const selectedSha=m23?'b64b89da245fbe885ff795ae9b6b030352635337':'153514ca42f7821bed239e198e15156a1a1ab5b4'; // known frozen Web source; no checkout proof implied
const selectedWorkflow='25eee8bfbea0cfa733ecbb0a14b3f922faecece553e508968e55a7038512bc25'; // SHA256 of committed validate.yml (3927 bytes)
const selectedArgs=['--test-only','--source-sha',selectedSha,'--workflow-file-sha256',selectedWorkflow];
for(const suffix of [[],['A'.repeat(64)],['a'.repeat(63)],[selectedWorkflow+'\n'],[selectedWorkflow,'--workflow-file-sha256',selectedWorkflow]]) {
 const result=spawnSync(process.execPath,[fixturePath,'--test-only','--source-sha',selectedSha,'--workflow-file-sha256',...suffix],{encoding:'utf8',timeout:10000});assert.equal(result.status,2);assert.equal(result.stdout,'');
}
for(const invalidArgs of [[],['--test-only','--source-sha',selectedSha+'\n'],['--test-only','--source-sha'],['--test-only','--source-sha','a'.repeat(39)],['--test-only','--source-sha','A'.repeat(40)],['--test-only','--source-sha',selectedSha,'--source-sha',selectedSha],['--test-only','--unknown',selectedSha],['--source-sha',selectedSha,'--test-only']]) {
 const result=spawnSync(process.execPath,[fixturePath,...invalidArgs],{encoding:'utf8',timeout:10000});assert.equal(result.status,2);assert.equal(result.stdout,'');
}
for(const tail of [[],[selectedSha],['A'.repeat(40)],['a'.repeat(39)],['a'.repeat(40)+'\n'],['a'.repeat(40),'--next-source-sha','b'.repeat(40)]]){
 const result=spawnSync(process.execPath,[fixturePath,...selectedArgs,'--next-source-sha',...tail],{encoding:'utf8',timeout:10000});assert.equal(result.status,2);assert.equal(result.stdout,'');
}
const child=spawn(process.execPath,[fixturePath,...selectedArgs,...(m23?['--next-source-sha','7548bd1b518dc0aa47dc8e05c8474a131ff9429a']:[])],{stdio:['pipe','pipe','inherit']});
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
  assert.equal(s.workflow_path,'.github/workflows/validate.yml');assert.equal(s.workflow_file_sha256,selectedWorkflow);
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
  const sc=await ok('openSource');assert.equal(sc.source_sha,selectedSha);assert.equal(parse(sc.config_json).source.workflow_file_sha256,selectedWorkflow);
  const wrongWorkflow=parse(stringify(source));wrongWorkflow.workflow_file.sha256='0'.repeat(64);
  assert.equal((await send('recordSource',{challenge_id:sc.challenge_id,evidence_json:stringify(wrongWorkflow)})).code,'40001');
  assert.equal((await ok('inspect')).receipts,1);
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
  if(m23){
    assert.equal((await send('advanceSource')).code,'55000');
    let active={...ready.inputs}, prior=baseline, job=claim;
    for(let slot=0;slot<2;slot++){
      const currentSource=parse(stringify(source));
      for(const key of ['run_before','run_attempt','run_after']){currentSource[key].head_sha=active.source_sha;currentSource[key].run_attempt=active.run_id.split(':')[1];}
      for(const key of ['ref_before','ref_after'])currentSource[key].sha=active.source_sha;
      currentSource.workflow_file.source_sha=active.source_sha;
      if(slot){
        const c=await ok('openSource');await ok('recordSource',{challenge_id:c.challenge_id,evidence_json:stringify(currentSource)});job=await ok('claim');assert.equal(job.target_generation,'8');
        await ok('transition',{expected_state:'queued',state:'exporting',evidence:{}});
        await ok('transition',{expected_state:'exporting',state:'building',evidence:{publication_manifest:ready.manifest,snapshot_sha256:'3'.repeat(64)}});
        await ok('transition',{expected_state:'building',state:'validating',evidence:{artifact_sha256:'4'.repeat(64)}});
        await ok('transition',{expected_state:'validating',state:'ready',evidence:{}});
      }
      const ds=await ok('openDeploySource');await ok('recordSource',{challenge_id:ds.challenge_id,evidence_json:stringify(currentSource)});
      const pp=await ok('openPredeploy');await ok('recordProvider',{challenge_id:pp.challenge_id,evidence_json:JSON.stringify(prior)});
      const beginId='begin-'+slot, begun=await ok('begin',{},beginId);assert.equal(begun.authorized,true);
      assert.equal((await send('begin',{},beginId)).code,'begin_ack_not_replayable');assert.equal((await send('begin')).code,'40001');
      const locked=await ok('inspect');assert.equal(locked.external_authority,true);assert.equal(locked.delivery.attempt.attempt_id,begun.attempt_id);
      if(!slot)assert.equal((await send('advanceSource')).code,'55000');
      if(!slot){
        assert.equal((await ok('finish',{outcome:'unknown',deployment_id:null,observation_id:null})).state,'deployment_unknown');
        const uncertain=await ok('inspect');assert.equal(uncertain.external_authority,true);assert.equal(uncertain.delivery.active_job,job.job_id);
        assert.equal((await send('begin')).code,'40001');assert.equal((await send('advanceSource')).code,'55000');
      }
      const candidate='fixture-candidate-'+slot;
      const marker={schema_version:1,job_id:job.job_id,dataset_epoch:job.dataset_epoch,generation:'8',source_sha:active.source_sha,snapshot_sha256:(slot?'3':'1').repeat(64)};
      const live={...baseline,project:{...baseline.project,canonical_deployment_id:candidate},deployment:{...baseline.deployment,id:candidate,source_sha:active.source_sha},markers:{deployment:marker,production:marker,pages:marker},artifact:{artifact_sha256:(slot?'4':'2').repeat(64),served_inventory_sha256:'5'.repeat(64)},requests:baseline.requests.map(x=>({...x,status:200}))};
      assert.equal((await send('openOutcome',{deployment_id:'x'.repeat(129)})).code,'invalid_fixture_command');
      const partialChallenge=await ok('openOutcome',{deployment_id:candidate});
      const partial={...live,markers:{...live.markers,production:{...marker,generation:'999'}}};
      const partialReceipt=await ok('recordProvider',{challenge_id:partialChallenge.challenge_id,evidence_json:JSON.stringify(partial)});
      const beforePartial=await ok('inspect');
      assert.equal((await send('finish',{outcome:'live',deployment_id:candidate,observation_id:partialReceipt.observation_id})).code,'55000');
      const afterPartial=await ok('inspect');delete beforePartial.calls;delete afterPartial.calls;assert.deepEqual(afterPartial,beforePartial);
      assert.equal(afterPartial.delivery.observations.find(x=>x.observation_id===partialReceipt.observation_id).consumed,false);
      const oc=await ok('openOutcome',{deployment_id:candidate});
      const beforeRejected=await ok('inspect');
      const malformed={...live,unexpected_field:true};
      const rejected=await send('recordProvider',{challenge_id:oc.challenge_id,evidence_json:JSON.stringify(malformed)});
      assert.equal(rejected.type,'error');
      const afterRejected=await ok('inspect');delete beforeRejected.calls;delete afterRejected.calls;assert.deepEqual(afterRejected,beforeRejected);
      const ob=await ok('recordProvider',{challenge_id:oc.challenge_id,evidence_json:JSON.stringify(live)});
      assert.equal((await ok('finish',{outcome:'live',deployment_id:candidate,observation_id:ob.observation_id})).state,'live');
      assert.equal((await ok('inspect')).external_authority,true);
      const tc=await ok('openTerminal',{deployment_id:candidate});
      const terminal=decodeGitHubTerminalRun(rawRun.replace('"status":"in_progress"','"status":"completed"').replace('"conclusion":null','"conclusion":"success"').replace(selectedSha,active.source_sha).replace('"run_attempt":1','"run_attempt":'+active.run_id.split(':')[1]));
      assertGitHubTerminalRun(terminal,{identity:{id:r.id,run_attempt:active.run_id.split(':')[1],workflow_id:r.workflow_id,repository_id:r.repository_id,head_repository_id:r.head_repository_id},event:r.event},{policy:'cp-workflow-path-v2',repository_full_name:s.repository_full_name,workflow_path:s.workflow_path,source_sha:active.source_sha,run_path_form:s.run_path_form},'run');
      const terminalEvidence={...live,github_terminal:{run:terminal,attempt:terminal},requests:[...live.requests,...['github_run_terminal','github_attempt_terminal'].map(endpoint_key=>({endpoint_key,page:1,status:200,request_id:null}))]};
      const tr=await ok('recordProvider',{challenge_id:tc.challenge_id,evidence_json:JSON.stringify(terminalEvidence)});
      const reconciled=await ok('reconcile',{observation_id:tr.observation_id});assert.equal(reconciled.reclaimable,true);
      const unlocked=await ok('inspect');assert.equal(unlocked.external_authority,false);assert.equal(unlocked.live_inventory_complete,true);assert.equal(unlocked.delivery.live.source_sha,active.source_sha);
      prior=live;
      if(!slot){active=await ok('advanceSource');assert.equal(active.source_sha,ready.scenarios[1].source_sha);assert.deepEqual(await ok('advanceSource'),active);}
    }
    console.log('M2.3 connected: two real SQL source slots, begin nonreplay, provider outcomes, actual terminal projection, live locks and reconciliation; no uploader/provider authentication');
  }
  assert.equal((await ok('close')).closed,true);assert.equal(await exited,0);
  console.log(JSON.stringify({config:sourceJsonStats(ready.config_json,true),evidence:sourceJsonStats(evidenceJson,true)}));
  console.log('Delivery fixture: actual baseline/source open-record, operator approval, claim/heartbeat/export/build/ready; 7 records, generation8, two consumed receipts; invalid evidence/replay/read-only/no-live controls passed');
} finally {clearTimeout(timeout);if(child.exitCode===null){child.stdin.end();await exited;}}
