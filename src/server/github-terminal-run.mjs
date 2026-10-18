import { LosslessNumber } from 'lossless-json';
import { parseBoundedRunResponse } from './github-run-json.mjs';
import { validateTarget } from './github-run-facts-v2-internal.mjs';
import { assertGitHubWorkflowPathV2 } from './github-workflow-path-v2.mjs';
const invalid=()=>Object.assign(new Error('invalid_github_terminal_run'),{code:'invalid_github_terminal_run'});
const mismatch=()=>Object.assign(new Error('github_terminal_run_mismatch'),{code:'github_terminal_run_mismatch'});
const fields=['repository_id','head_repository_id','workflow_id','run_id','run_attempt','raw_path','head_branch','head_sha','event','status','conclusion'];
const conclusions=['action_required','cancelled','failure','neutral','skipped','stale','startup_failure','success','timed_out'];
const match=(re,s)=>typeof s==='string'&&re.exec(s)?.[0]===s;
function object(v){if(!v||typeof v!=='object'||Array.isArray(v)||![null,Object.prototype].includes(Object.getPrototypeOf(v)))throw invalid();}
function own(v,k){object(v);const d=Object.getOwnPropertyDescriptor(v,k);if(!d||!d.enumerable||!Object.hasOwn(d,'value'))throw invalid();return d.value;}
function validate(v){object(v);const keys=Reflect.ownKeys(v);if(keys.length!==fields.length||!fields.every(k=>keys.includes(k)))throw invalid();const r=Object.fromEntries(fields.map(k=>[k,own(v,k)]));
 for(const k of fields.slice(0,5))if(!match(k==='run_attempt'?/^[1-9][0-9]{0,9}$/u:/^[1-9][0-9]{0,19}$/u,r[k]))throw invalid();
 if(typeof r.raw_path!=='string'||r.raw_path.length>65534||Buffer.byteLength(r.raw_path)>65534||r.head_branch!=='main'||!match(/^[0-9a-f]{40}$/u,r.head_sha)||!['push','schedule','workflow_dispatch'].includes(r.event)||r.status!=='completed'||!conclusions.includes(r.conclusion))throw invalid();return r;
}
function token(v){if(!(v instanceof LosslessNumber))throw invalid();return v.value;}
/** Pure projection; no provider authentication or endpoint inference. */
export function decodeGitHubTerminalRun(rawJson){try{const b=parseBoundedRunResponse(rawJson);const r={repository_id:token(own(own(b,'repository'),'id')),head_repository_id:token(own(own(b,'head_repository'),'id')),workflow_id:token(own(b,'workflow_id')),run_id:token(own(b,'id')),run_attempt:token(own(b,'run_attempt')),raw_path:own(b,'path'),head_branch:own(b,'head_branch'),head_sha:own(b,'head_sha'),event:own(b,'event'),status:own(b,'status'),conclusion:own(b,'conclusion')};return validate(r);}catch{throw invalid();}}
export function assertGitHubTerminalRun(actual,target,pathPolicy,endpoint){let a,t;try{a=validate(actual);t=validateTarget(target);if(!['run','attempt'].includes(endpoint))throw invalid();}catch{throw invalid();}
 try{assertGitHubWorkflowPathV2({endpoint,raw_path:a.raw_path,head_branch:a.head_branch,head_sha:a.head_sha},pathPolicy);}catch(e){if(e.code==='github_workflow_path_v2_mismatch')throw mismatch();throw invalid();}
 if(a.event!==t.event||['repository_id','head_repository_id','workflow_id','run_attempt'].some(k=>a[k]!==t.identity[k])||a.run_id!==t.identity.id)throw mismatch();
}
