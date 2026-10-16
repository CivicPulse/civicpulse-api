import test from 'node:test';
import assert from 'node:assert/strict';
import { createCivicPulseClient, ApiError } from '../src/client.mjs';
import { mergeEvents, importDrafts } from '../scripts/import-web.mjs';

test('client sends current user token and expected revision, never a privileged key', async () => {
  let token='first'; const calls=[];
  const client=createCivicPulseClient({url:'https://example.supabase.co',publishableKey:'sb_publishable_test',accessToken:()=>token,
    fetch:async(url,options)=>{calls.push({url,options});return new Response('2');}});
  await client.saveDraft('organization',{id:'org',name:'Org'},1);
  token='refreshed'; await client.publish('organization','org',2);
  assert.equal(calls[0].url.pathname,'/rest/v1/rpc/save_draft');
  assert.equal(calls[0].options.headers.apikey,'sb_publishable_test');
  assert.equal(calls[1].options.headers.Authorization,'Bearer refreshed');
  assert.equal(JSON.parse(calls[1].options.body).p_expected_revision,2);
});
test('conflicts preserve API error codes for CMS reload prompts',async()=>{
  const client=createCivicPulseClient({url:'https://example.org',publishableKey:'key',fetch:async()=>new Response(JSON.stringify({code:'40001',message:'Draft changed'}),{status:409})});
  await assert.rejects(client.publish('event','event',1),error=>error instanceof ApiError&&error.code==='40001'&&error.status===409);
});
test('public calls omit authorization and encode filters',async()=>{
  const client=createCivicPulseClient({url:'https://example.org',publishableKey:'key',fetch:async(url,options)=>{
    assert.equal(options.headers.Authorization,undefined);
    assert.equal(url.searchParams.get('kind'),'eq.event');
    assert.equal(url.searchParams.get('offset'),'100');
    return new Response('[]');
  }});
  assert.deepEqual(await client.listPublished('event',{limit:100,offset:100}),[]);
  await assert.rejects(client.listPublished('event',{limit:1001}),/limit/);
});
const catalog={organizations:[{id:'org'}],calendars:[{id:'cal',organizationId:'org',sourceCalendar:'source'}]};
const event={id:'one',title:'One',start:'2026-10-16',sample:false,sourceUrl:'https://example.org/one',organizationId:'org',calendarIds:['cal']};
test('event merge matches refreshed Mobilize and calendar inference',()=>{
  const current={...event,title:'Current'};
  const inferred={...event,id:'two',sourceUrl:'https://example.org/two',calendarIds:undefined,sourceCalendar:'source'};
  assert.deepEqual(mergeEvents(catalog,[[event],[current],[inferred],[],[]]).map(e=>[e.id,e.title,e.calendarIds]),[['two','One',['cal']],['one','Current',['cal']]]);
});
test('invalid samples, duplicate IDs and calendar memberships stop imports',()=>{
  assert.throws(()=>mergeEvents(catalog,[[{...event,sample:true}],[],[],[],[]]),/sample/);
  assert.throws(()=>mergeEvents(catalog,[[],[event],[event],[],[]]),/Duplicate/);
  assert.throws(()=>mergeEvents(catalog,[[{...event,calendarIds:['unknown']}],[],[],[],[]]),/membership/);
});
test('re-running import preserves edited drafts and skips identical records',async()=>{
  const calls=[];
  const client={getDraft:async(kind,id)=>id==='new'?null:{payload:{id,name:'Existing'}},saveDraft:async(...args)=>calls.push(args)};
  const report=await importDrafts(client,[{kind:'organization',payload:{id:'new',name:'New'}},
    {kind:'organization',payload:{id:'same',name:'Existing'}},{kind:'organization',payload:{id:'changed',name:'Imported'}}]);
  assert.deepEqual(report,{created:1,unchanged:1,conflicts:['organization/changed']});
  assert.equal(calls.length,1);assert.equal(calls[0][2],0);
});

test('manifest uses exact additive RPC and bypasses fetch caches',async()=>{
  const manifest={schema_version:1,dataset_epoch:'epoch',generation:'9007199254740993',bootstrap_complete:false,counts:{organization:0,calendar:0,event:0,layer:0,map:0},records:[],layers:[]};
  const client=createCivicPulseClient({url:'https://example.org',publishableKey:'key',fetch:async(url,options)=>{
    assert.equal(url.pathname,'/rest/v1/rpc/publication_manifest');
    assert.equal(options.method,'POST');assert.equal(options.body,'{}');assert.equal(options.cache,'no-store');
    return new Response(JSON.stringify(manifest));
  }});
  assert.deepEqual(await client.publicationManifest(),manifest);
});
