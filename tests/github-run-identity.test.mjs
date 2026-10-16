import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeGitHubRunIdentity as decode, assertGitHubRunIdentity as compare, runIdentityLimits as limits } from '../src/server/github-run-identity.mjs';

// Synthetic, unauthenticated provider-shaped fixtures; never production config.
const raw = ({ id='123', attempt='1', workflow='456', repository='789', head='789', path='.github/workflows/publish.yml', extra='' }={}) =>
  `{"id":${id},"run_attempt":${attempt},"workflow_id":${workflow},"repository":{"id":${repository}},"head_repository":{"id":${head}},"path":${JSON.stringify(path)}${extra}}`;
const invalid = work => assert.throws(work,error => {
  assert.equal(error.code,'invalid_github_run_identity');
  assert.equal(error.message,'invalid_github_run_identity');
  assert.equal(error.cause,undefined);
  return true;
});
const mismatch = work => assert.throws(work,error => error.code==='github_run_identity_mismatch' && error.message==='github_run_identity_mismatch');

test('valid decode and comparator return exactly six string facts without authority',()=>{
  const facts=decode(raw());
  assert.deepEqual(facts,{id:'123',run_attempt:'1',workflow_id:'456',repository_id:'789',head_repository_id:'789',path:'.github/workflows/publish.yml'});
  assert.equal(Object.getPrototypeOf(facts),Object.prototype);
  assert.equal(compare(facts,{...facts}),undefined);
});
test('adjacent unsafe integers and full ID/attempt maxima remain distinct exact tokens',()=>{
  const ids=['9007199254740991','9007199254740992','9007199254740993','99999999999999999999'];
  for (const id of ids) {
    const facts=decode(raw({id,workflow:id,repository:id,head:id,attempt:'9999999999'}));
    assert.equal(facts.id,id);assert.equal(facts.workflow_id,id);assert.equal(facts.repository_id,id);assert.equal(facts.head_repository_id,id);
    assert.equal(facts.run_attempt,'9999999999');compare(facts,{...facts});
  }
  mismatch(()=>compare(decode(raw({id:ids[1]})),decode(raw({id:ids[2]}))));
});
test('upstream IDs must be canonical bounded positive NUMBER tokens',()=>{
  for (const field of ['id','workflow','repository','head','attempt']) {
    for (const token of ['null','"123"','0','-0','-1','1.0','1e0','+1','01','true','[]','{}','{"isLosslessNumber":true,"value":"1"}',field==='attempt'?'10000000000':'100000000000000000000']) {
      invalid(()=>decode(raw({[field]:token})));
    }
  }
  for (const field of ['id','run_attempt','workflow_id','repository','head_repository','path']) {
    const data=JSON.parse(raw());delete data[field];invalid(()=>decode(JSON.stringify(data)));
  }
});
test('equal, unequal, escaped-equivalent and nested duplicate keys reject before projection',()=>{
  for (const extra of [',"id":123',',"id":124',',"\\u0069d":123',',"unknown":{"x":1,"x":1}',',"unknown":{"x":1,"\\u0078":1}',',"unknown":[{"a":{"z":1},"a":{"z":1}}]',',"__proto__":{},"__proto__":{}']) invalid(()=>decode(raw({extra})));
  invalid(()=>decode(raw().replace('"repository":{"id":789}','"repository":{"id":789,"\\u0069d":789}')));
});
test('malformed root/objects/JSON and escapes produce only stable redacted errors',()=>{
  for (const value of [undefined,null,123,'',' ','[]','null','true','{}','{"secret":"SENTINEL",','{"x":"\\u12zz"}','{"x":"\\uD800','{"x":"\\q"}',raw()+' {}',raw().replace('"id":123','"id":NaN'),raw().replace('"id":123','"id":Infinity'),raw().replace('"id":123','"id":.1'),raw().replace('"id":123','"id":1.')]) invalid(()=>decode(value));
  for (const value of ['null','[]','"SENTINEL"','123','{}']) invalid(()=>decode(raw().replace('{"id":789}',value)));
});
test('exact run workflow path is validated and renamed path mismatches',()=>{
  const actual=decode(raw());
  mismatch(()=>compare(actual,{...actual,path:'.github/workflows/renamed.yaml'}));
  for (const path of ['.github/workflows/../publish.yml','.github/workflows/sub/publish.yml','.github/workflows/%70ublish.yml','.github/workflows/publish.yml@main','.github/workflows/publish.yml?ref=main','.github/workflows/publish.yml#main','.github/workflows/publish.yml\n','.github/workflows/é.yml','.github/workflows/\\publish.yml','.github/workflows/.yml',' .github/workflows/publish.yml','.github/workflows/publish.yml ','.github/workflows/\ud800.yml']) invalid(()=>decode(raw({path})));
  assert.equal(decode(raw({path:'.github/workflows/A_1-foo.yaml'})).path,'.github/workflows/A_1-foo.yaml');
});
test('unknown huge numbers/prototype keys stay lossless or inert and never enter output',()=>{
  const value=decode(raw({extra:',"unknown":1e999999,"__proto__":{"polluted":true},"constructor":{"prototype":{"polluted":true}},"metadata":{"id":999999999999999999999999999999999999999}'}));
  assert.deepEqual(value,decode(raw()));assert.equal(value.polluted,undefined);assert.equal({}.polluted,undefined);
  assert.equal(Object.getPrototypeOf(value),Object.prototype);
});
test('comparator rejects malformed expected/actual facts, extras and accessors without reading them',()=>{
  const good=decode(raw());
  for (const key of Object.keys(good)) {
    const missing={...good};delete missing[key];invalid(()=>compare(good,missing));invalid(()=>compare(missing,good));
    invalid(()=>compare(good,{...good,[key]:123}));
    invalid(()=>compare({...good,[key]:null},good));
  }
  invalid(()=>compare(good,{...good,approved:true}));
  invalid(()=>compare(good,{...good,[Symbol('extra')]:true}));
  invalid(()=>compare(good,{...good,head_repository_id:'790'}));
  mismatch(()=>compare(decode(raw({head:'790'})),good));
  let read=false;const getter={...good};Object.defineProperty(getter,'id',{enumerable:true,get(){read=true;return '123';}});
  invalid(()=>compare(getter,good));assert.equal(read,false);
  invalid(()=>compare({...good,id:'123\n'},good));
});
test('raw UTF8 byte cap is inclusive and applies before lossless parsing',()=>{
  const base=raw();const exact=base+' '.repeat(limits.rawBytes-Buffer.byteLength(base));
  assert.deepEqual(decode(exact),decode(base));invalid(()=>decode(exact+' '));
  invalid(()=>decode(raw({extra:',"large":"'+'é'.repeat(limits.rawBytes/2)+'"'})));
});
test('iterative depth limit applies to unknown nested containers without recursive precheck',()=>{
  const nested=n=>raw({extra:',"unknown":'+'['.repeat(n)+'0'+']'.repeat(n)});
  assert.deepEqual(decode(nested(limits.depth-1)),decode(raw()));
  invalid(()=>decode(nested(limits.depth)));
  invalid(()=>decode(nested(10000)));
  assert.deepEqual(decode(raw({extra:',"unknown":"[[[}}}\\\""'})),decode(raw()));
});
test('string token byte cap includes quotes and counts UTF8 bytes',()=>{
  const text='x'.repeat(limits.stringBytes-2);
  assert.deepEqual(decode(raw({extra:',"unknown":'+JSON.stringify(text)})),decode(raw()));
  invalid(()=>decode(raw({extra:',"unknown":'+JSON.stringify(text+'x')})));
  invalid(()=>decode(raw({extra:',"unknown":'+JSON.stringify('é'.repeat(limits.stringBytes/2))})));
});
test('token budget bounds large arrays and many unknown members',()=>{
  invalid(()=>decode(raw({extra:',"unknown":['+Array(limits.tokens).fill('0').join(',')+']'})));
  invalid(()=>decode(raw({extra:',"unknown":{'+Array.from({length:limits.tokens},(_,i)=>`"k${i}":0`).join(',')+'}'})));
});

test('valid 32767/32768-token objects pass and 32769-token object fails',()=>{
  // Independent structural count of these synthetic SAFE-number fixtures only.
  // This native parse is never used by the lossless production decoder.
  const tokenCount=value=>{
    if (Array.isArray(value)) return 2+Math.max(0,value.length-1)+value.reduce((sum,item)=>sum+tokenCount(item),0);
    if (value!==null && typeof value==='object') {
      const values=Object.values(value);
      return 2+Math.max(0,values.length-1)+values.reduce((sum,item)=>sum+2+tokenCount(item),0);
    }
    return 1;
  };
  // Base has 33 tokens; additional unknown array contributes 4 + 2*N.
  const body=n=>raw({extra:',"unknown":['+Array(n).fill('0').join(',')+']'});
  assert.equal(tokenCount(JSON.parse(body(16365))),32767);
  assert.deepEqual(decode(body(16365)),decode(raw()));
  // Replace one primitive token with two array delimiters: exactly 32768.
  const atLimit=raw({extra:',"unknown":['+['[]',...Array(16364).fill('0')].join(',')+']'});
  assert.equal(tokenCount(JSON.parse(atLimit)),32768);
  assert.deepEqual(decode(atLimit),decode(raw()));
  assert.equal(tokenCount(JSON.parse(body(16366))),32769);
  invalid(()=>decode(body(16366)));
});
test('exact UTF8 and raw escaped string boundaries include keys and surrogate code units',()=>{
  const multibyte=raw({extra:',"unknown":"é"'});
  const exact=multibyte+' '.repeat(limits.rawBytes-Buffer.byteLength(multibyte));
  assert.ok(exact.length<limits.rawBytes);assert.deepEqual(decode(exact),decode(raw()));invalid(()=>decode(exact+' '));
  const key='k'.repeat(limits.stringBytes-2);
  assert.deepEqual(decode(raw({extra:','+JSON.stringify(key)+':0'})),decode(raw()));
  invalid(()=>decode(raw({extra:','+JSON.stringify(key+'k')+':0'})));
  const escaped='\\u0061'.repeat(10922)+'aa'; // 65534 raw content bytes, plus quotes
  assert.deepEqual(decode(raw({extra:',"unknown":"'+escaped+'"'})),decode(raw()));
  invalid(()=>decode(raw({extra:',"unknown":"'+escaped+'a"'})));
  for (const text of ['\\uD83D\\uDE00','\\uD800','\\uDC00','\ud800','😀']) {
    assert.deepEqual(decode(raw({extra:',"unknown":"'+text+'"'})),decode(raw()));
  }
  invalid(()=>decode(raw({extra:',"unknown":"\\uD80X"'})));
  invalid(()=>decode(raw({extra:',"unknown":"\\uD800\\uZZZZ"'})));
  invalid(()=>decode(raw({extra:',"unknown":{"\\uD800":1,"\ud800":1}'})));
});
test('limits and duplicates stop before the dependency parser boundary',async()=>{
  const { parseBoundedRunResponse }=await import('../src/server/github-run-json.mjs');
  let calls=0;const parser=()=>{calls++;return 'synthetic parser reached';};
  for (const body of [raw()+' '.repeat(limits.rawBytes),raw({extra:',"unknown":'+'['.repeat(10000)+'0'+']'.repeat(10000)}),raw({extra:',"unknown":"'+'x'.repeat(limits.stringBytes)+'"'}),raw({extra:',"id":123'}),raw({extra:',"unknown":['+Array(16366).fill('0').join(',')+']'})]) {
    invalid(()=>parseBoundedRunResponse(body,parser));
  }
  assert.equal(calls,0);
  assert.equal(parseBoundedRunResponse(raw(),parser),'synthetic parser reached');assert.equal(calls,1);
});

test('comparator snapshots data descriptors and accepts safe null-prototype facts',()=>{
  const facts=decode(raw());
  compare(facts,Object.assign(Object.create(null),facts));
  const hostile=new Proxy(facts,{get(){throw new Error('SENTINEL getter must not run');}});
  assert.equal(compare(hostile,facts),undefined);
  invalid(()=>compare(new Proxy(facts,{ownKeys(){throw new Error('SENTINEL raw error');}}),facts));
});
