import { LosslessNumber } from 'lossless-json';
import { parseBoundedRunResponse } from './github-run-json.mjs';
export { runIdentityLimits } from './github-run-json.mjs';

// Pure, unauthenticated identity projection. No source/admission authority.
const invalid = () => Object.assign(new Error('invalid_github_run_identity'), { code: 'invalid_github_run_identity' });
const mismatch = () => Object.assign(new Error('github_run_identity_mismatch'), { code: 'github_run_identity_mismatch' });
const fields = ['id','run_attempt','workflow_id','repository_id','head_repository_id','path'];
const fullMatch = (pattern, value) => typeof value === 'string' && pattern.exec(value)?.[0] === value;
const validId = value => fullMatch(/^[1-9][0-9]{0,19}$/u, value);
const validAttempt = value => fullMatch(/^[1-9][0-9]{0,9}$/u, value);
const validPath = value => fullMatch(/^\.github\/workflows\/[A-Za-z0-9][A-Za-z0-9_-]*\.ya?ml$/u, value);


function object(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}
function numberToken(value, attempt = false) {
  if (!(value instanceof LosslessNumber) || !(attempt ? validAttempt(value.value) : validId(value.value))) throw invalid();
  return value.value;
}

/** @returns {{id:string,run_attempt:string,workflow_id:string,repository_id:string,head_repository_id:string,path:string}} */
export function decodeGitHubRunIdentity(rawJson) {
  try {
    const body = parseBoundedRunResponse(rawJson);
    if (!object(body) || !object(body.repository) || !object(body.head_repository) || !validPath(body.path)) throw invalid();
    return {
      id: numberToken(body.id),
      run_attempt: numberToken(body.run_attempt,true),
      workflow_id: numberToken(body.workflow_id),
      repository_id: numberToken(body.repository.id),
      head_repository_id: numberToken(body.head_repository.id),
      path: body.path,
    };
  } catch { throw invalid(); } // Never retain parser messages, raw body or cause.
}

function validateFacts(facts) {
  try {
    if (!object(facts)) throw invalid();
    const keys = Reflect.ownKeys(facts);
    if (keys.length !== fields.length || !fields.every(key => keys.includes(key))) throw invalid();
    const snapshot = {};
    for (const key of fields) {
      const descriptor = Object.getOwnPropertyDescriptor(facts,key);
      if (!descriptor || !Object.hasOwn(descriptor,'value') || !descriptor.enumerable || typeof descriptor.value !== 'string') throw invalid();
      if (!(key === 'path' ? validPath(descriptor.value) : key === 'run_attempt' ? validAttempt(descriptor.value) : validId(descriptor.value))) throw invalid();
      snapshot[key] = descriptor.value;
    }
    return snapshot;
  } catch { throw invalid(); }
}

export function assertGitHubRunIdentity(actual, expected) {
  const actualValues = validateFacts(actual);
  const expectedValues = validateFacts(expected);
  if (expectedValues.repository_id !== expectedValues.head_repository_id) throw invalid();
  if (fields.some(key => actualValues[key] !== expectedValues[key])) throw mismatch();
}
