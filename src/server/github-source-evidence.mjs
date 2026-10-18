import { LosslessNumber, stringify } from 'lossless-json';
import { parseBoundedRunResponse, parseBoundedSourceAggregate, sourceJsonStats } from './github-run-json.mjs';

const invalid=()=>Object.assign(new Error('invalid_github_source_evidence'),{code:'invalid_github_source_evidence'});
const match=(pattern,value)=>typeof value==='string'&&pattern.exec(value)?.[0]===value;
const object=value=>{if(!value||typeof value!=='object'||Array.isArray(value)||value instanceof LosslessNumber)throw invalid();return value;};
const own=(value,key)=>{object(value);if(!Object.hasOwn(value,key))throw invalid();return value[key];};
const id=(value,attempt=false)=>{if(!(value instanceof LosslessNumber)||!match(attempt?/^[1-9][0-9]{0,9}$/u:/^[1-9][0-9]{0,19}$/u,value.value))throw invalid();return value.value;};
const text=value=>{if(typeof value!=='string')throw invalid();return value;};
const bool=value=>{if(typeof value!=='boolean')throw invalid();return value;};
const sha=value=>{if(!match(/^[0-9a-f]{40}$/u,value))throw invalid();return value;};
const array=value=>{if(!Array.isArray(value))throw invalid();return value;};

/** JSON TEXT, not a native-number object. Policy bodies retain all fields and
 * original numeric tokens. Identity projections use canonical decimal strings.
 * This checks response structure only; callers bind endpoint/context/authority.
 */
function decodeBody(body,endpoint) {
  try {
    if(!['repository','workflow','run','attempt','ref','classic','ruleset_list','ruleset_detail','effective_rules'].includes(endpoint))throw invalid();
    let result;
    if(endpoint==='repository') result={id:id(own(body,'id')),owner_id:id(own(own(body,'owner'),'id')),full_name:text(own(body,'full_name')),fork:bool(own(body,'fork')),archived:bool(own(body,'archived')),default_branch:text(own(body,'default_branch'))};
    else if(endpoint==='workflow')result={id:id(own(body,'id')),path:text(own(body,'path')),state:text(own(body,'state'))};
    else if(endpoint==='run'||endpoint==='attempt') {
      if(own(body,'status')!=='in_progress'||own(body,'conclusion')!==null||own(body,'head_branch')!=='main'||!['push','schedule','workflow_dispatch'].includes(own(body,'event'))||array(own(body,'referenced_workflows')).length)throw invalid();
      result={id:id(own(body,'id')),run_attempt:id(own(body,'run_attempt'),true),workflow_id:id(own(body,'workflow_id')),path:text(own(body,'path')),repository_id:id(own(own(body,'repository'),'id')),head_repository_id:id(own(own(body,'head_repository'),'id')),event:body.event,head_branch:'main',head_sha:sha(own(body,'head_sha')),status:'in_progress',conclusion:null,actor_id:id(own(own(body,'actor'),'id')),triggering_actor_id:id(own(own(body,'triggering_actor'),'id')),referenced_workflows:[]};
    } else if(endpoint==='ref')result={ref:text(own(body,'ref')),object_type:text(own(own(body,'object'),'type')),sha:sha(own(own(body,'object'),'sha'))};
    else if(endpoint==='classic')result=object(body);
    else if(endpoint==='ruleset_detail') { id(own(body,'id'));result=object(body); }
    else {result=array(body);if(result.length>100)throw invalid();for(const item of result){object(item);if(endpoint==='ruleset_list')id(own(item,'id'));}}
    return stringify(result);
  } catch {throw invalid();}
}

export function decodeGitHubSourceResponse(rawJson,endpoint) {
  try{return decodeBody(parseBoundedRunResponse(rawJson),endpoint);}catch{throw invalid();}
}

const evidenceParts=Object.freeze(['repository','workflow','run_before','run_attempt','run_after','ref_before','ref_after','protection_before','protection_after','workflow_file','requests']);
/** Each own data property is JSON TEXT. Never JSON.parse policy text natively.
 * SQL validates the assembled evidence against its challenge and configuration.
 */
export function assembleGitHubSourceEvidence(parts) {
  try {
    if(!parts||typeof parts!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(parts))||Reflect.ownKeys(parts).length!==evidenceParts.length)throw invalid();
    const texts=Object.create(null);let bytes=0;
    for(const key of evidenceParts){const d=Object.getOwnPropertyDescriptor(parts,key);if(!d||!Object.hasOwn(d,'value')||!d.enumerable||typeof d.value!=='string')throw invalid();texts[key]=d.value;bytes+=Buffer.byteLength(d.value);if(bytes>8388608)throw invalid();}
    let tokens=0;for(const key of evidenceParts){tokens+=sourceJsonStats(texts[key],true).tokens;if(tokens>262144)throw invalid();}
    const candidate='{\"schema_version\":1,'+evidenceParts.map(key=>JSON.stringify(key)+':'+texts[key]).join(',')+'}';
    sourceJsonStats(candidate,true); // fixed wrapper budget checked before dependency parsing
    const value={schema_version:1};
    for(const key of evidenceParts)value[key]=parseBoundedSourceAggregate(texts[key]);
    if(!Array.isArray(value.requests)||value.requests.length>256)throw invalid();
    const result=stringify(value);
    // Apply the reviewed aggregate depth/token limits as well as per-part bounds.
    parseBoundedSourceAggregate(result);
    if(Buffer.byteLength(result)>8388608)throw invalid();
    return result;
  }catch{throw invalid();}
}

const byteCompare=(a,b)=>Buffer.compare(Buffer.from(a,'utf8'),Buffer.from(b,'utf8'));
function canonical(value) {
  if(value instanceof LosslessNumber)return value.value;
  if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
  if(value!==null&&typeof value==='object')return '{'+Object.keys(value).sort(byteCompare).map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';
  return JSON.stringify(value);
}
const rulesetFacts=(value,detail=false)=>{
  const source_type=text(own(value,'source_type')),enforcement=text(own(value,'enforcement'));
  if(!['Repository','Organization'].includes(source_type)||!['active','disabled','evaluate'].includes(enforcement))throw invalid();
  const facts={id:id(own(value,'id')),source_type,source:text(own(value,'source')),enforcement,bypass_present:Object.hasOwn(value,'bypass_actors')};
  if(detail)facts.bypass_actors=array(own(value,'bypass_actors')).map(actor=>({actor_id:own(actor,'actor_id')===null?null:id(actor.actor_id),actor_type:text(own(actor,'actor_type')),bypass_mode:text(own(actor,'bypass_mode'))}));
  return facts;
};
/** Safe orchestration facts beside full lossless policy JSON, never numeric body objects. */
export function projectGitHubSourceResponse(rawJson,endpoint) {
  try {
    const original=parseBoundedRunResponse(rawJson);
    const json=decodeBody(original,endpoint);
    let facts;
    if(endpoint==='repository') {
      const owner_type=text(own(own(original,'owner'),'type'));
      if(!['Organization','User'].includes(owner_type))throw invalid();
      facts={...JSON.parse(json),owner_type}; // projection contains strings/booleans only
    } else if(endpoint==='ruleset_list') facts=array(original).map(item=>rulesetFacts(item));
    else if(endpoint==='ruleset_detail')facts=rulesetFacts(original,true);
    else if(endpoint==='effective_rules')facts=array(original).map(item=>({ruleset_id:id(own(item,'ruleset_id')),source_type:text(own(item,'ruleset_source_type')),source:text(own(item,'ruleset_source'))}));
    else if(endpoint==='classic')facts=null;
    else facts=JSON.parse(json); // closed non-policy projection: strings/booleans/null/empty array
    return {json,canonical_json:canonical(original),facts};
  }catch{throw invalid();}
}
export function canonicalizeGitHubPolicyJson(json) {
  try{return canonical(parseBoundedSourceAggregate(json));}catch{throw invalid();}
}
/** Fixed aggregate context. Full policy stays text; only known config identity
 * strings and bounded numeric protocol versions are projected into JS values. */
export function projectGitHubSourceConfig(configJson) {
  try {
    const c=parseBoundedSourceAggregate(configJson),s=own(c,'source'),p=own(c,'provider');
    const source={};
    for(const key of ['repository_id','repository_owner_id','repository_full_name','workflow_id','workflow_path','workflow_file_sha256','ref','api_version','run_path_form'])source[key]=text(own(s,key));
    for(const key of ['repository_id','repository_owner_id','workflow_id'])if(!match(/^[1-9][0-9]{0,19}$/u,source[key]))throw invalid();
    source.allowed_events=array(own(s,'allowed_events')).map(text);
    const provider={};for(const key of ['account_id','project_id','project_name','production_origin','pages_origin'])provider[key]=text(own(p,key));
    return {source,provider,protection_json:canonical(own(s,'protection_bundle')),canonical_json:canonical(c)};
  }catch{throw invalid();}
}

function descriptors(value,keys) {
  if(!value||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value))||Reflect.ownKeys(value).length!==keys.length)throw invalid();
  const copy=Object.create(null);
  for(const key of keys){const d=Object.getOwnPropertyDescriptor(value,key);if(!d||!Object.hasOwn(d,'value')||!d.enumerable)throw invalid();copy[key]=d.value;}
  return copy;
}
function pages(values,read) {
  array(values);if(!values.length||values.length>256)throw invalid();const records=[];
  let mustProbe=false;
  for(let i=0;i<values.length;i++){
    const p=descriptors(values[i],['page','next_page','json']);
    if(p.page!==i+1||!(p.next_page===null||p.next_page===i+2))throw invalid();
    const entries=array(read(p.json));if(entries.length>100)throw invalid();
    if(mustProbe&&(entries.length||p.next_page!==null))throw invalid();
    records.push(...entries);
    if(p.next_page===null&&entries.length<100){if(i!==values.length-1)throw invalid();return records;}
    mustProbe=p.next_page===null;
  }
  throw invalid(); // missing next/probe page
}
/** Fixture/adapter supplied acquisition transcript. Validates membership and
 * pagination closure, not Link headers, HTTPS, credentials or DB freshness. */
export function assembleGitHubProtectionEvidence(input,context) {
  try {
    const x=descriptors(input,['classic_json','list_pages','detail_json','effective_pages']);
    const c=descriptors(context,['repository_full_name','owner','owner_type','scope']);
    if(!match(/^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/u,c.owner)||!match(/^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/u,c.repository_full_name)||c.repository_full_name.split('/')[0]!==c.owner||!['User','Organization'].includes(c.owner_type)||!['repository','organization'].includes(c.scope)||(c.scope==='organization'&&c.owner_type!=='Organization'))throw invalid();
    let reads=0,bytes=0,tokens=0;
    const read=raw=>{if(typeof raw!=='string'||++reads>256||(bytes+=Buffer.byteLength(raw))>8388608)throw invalid();tokens+=sourceJsonStats(raw).tokens;if(tokens>262144)throw invalid();return parseBoundedRunResponse(raw);};
    const classic=object(read(x.classic_json));
    const summaries=pages(x.list_pages,read),details=array(x.detail_json).map(read),effective=pages(x.effective_pages,read);
    const bound=f=>{if(f.source_type==='Repository'){if(c.scope!=='repository'||f.source!==c.repository_full_name)throw invalid();}else if(f.source!==c.owner||c.owner_type!=='Organization')throw invalid();};
    const byId=new Map();
    for(const summary of summaries){const f=rulesetFacts(summary);bound(f);if(byId.has(f.id))throw invalid();byId.set(f.id,summary);}
    const ordered=[...byId.keys()].sort((a,b)=>a.length-b.length||byteCompare(a,b));
    if(details.length!==ordered.length)throw invalid();
    for(let i=0;i<details.length;i++){
      const d=details[i],f=rulesetFacts(d,true);bound(f);if(f.id!==ordered[i])throw invalid();const summary=byId.get(f.id);
      for(const key of Object.keys(summary))if(Object.hasOwn(d,key)&&canonical(summary[key])!==canonical(d[key]))throw invalid();
    }
    const complete=new Map(details.map(d=>[id(d.id),d]));
    for(const e of effective){const d=complete.get(id(own(e,'ruleset_id')));if(!d||d.enforcement!=='active'||own(e,'ruleset_source_type')!==d.source_type||own(e,'ruleset_source')!==d.source)throw invalid();}
    const sorted=effective.map(canonical).sort(byteCompare);
    const result='{"classic":'+canonical(classic)+',"rulesets":['+details.map(canonical).join(',')+'],"effective_rules":['+sorted.join(',')+']}';
    sourceJsonStats(result,true);if(Buffer.byteLength(result)>8388608)throw invalid();return result;
  }catch{throw invalid();}
}

/** Per-response preflight metrics let the adapter enforce cumulative counters
 * BEFORE retaining the next body. No dependency parse or endpoint trust here. */
export function inspectGitHubSourceResponseBudget(rawJson) {
  try{return sourceJsonStats(rawJson);}catch{throw invalid();}
}
