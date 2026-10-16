import { LosslessNumber } from 'lossless-json';
import { parseBoundedRunResponse } from './github-run-json.mjs';

export const invalid = () => Object.assign(new Error('invalid_github_in_progress_run_facts_v2'), { code: 'invalid_github_in_progress_run_facts_v2' });
export const identityFields = Object.freeze(['id', 'run_attempt', 'workflow_id', 'repository_id', 'head_repository_id']);
const factFields = ['schema_version', 'endpoint', 'identity', 'raw_path', 'head_sha', 'head_branch', 'event', 'status', 'conclusion'];
const fullMatch = (pattern, value) => typeof value === 'string' && pattern.exec(value)?.[0] === value;
const validId = (value, attempt = false) => fullMatch(attempt ? /^[1-9][0-9]{0,9}$/u : /^[1-9][0-9]{0,19}$/u, value);
const validEvent = value => ['push', 'schedule', 'workflow_dispatch'].includes(value);
const validEndpoint = value => value === 'run' || value === 'attempt';

function object(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw invalid();
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) throw invalid();
}

function ownData(value, key) {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  if (!descriptor || !Object.hasOwn(descriptor, 'value') || !descriptor.enumerable) throw invalid();
  return descriptor.value;
}

function snapshot(value, fields) {
  object(value);
  const keys = Reflect.ownKeys(value);
  if (keys.length !== fields.length || !fields.every(key => keys.includes(key))) throw invalid();
  const result = Object.create(null);
  for (const key of fields) result[key] = ownData(value, key);
  return result;
}

function identity(value) {
  const result = snapshot(value, identityFields);
  for (const key of identityFields) if (!validId(result[key], key === 'run_attempt')) throw invalid();
  return result;
}

export function validateFacts(value) {
  const result = snapshot(value, factFields);
  result.identity = identity(result.identity);
  if (result.schema_version !== 2 || !validEndpoint(result.endpoint) ||
      typeof result.raw_path !== 'string' || result.raw_path.length > 65534 || Buffer.byteLength(result.raw_path, 'utf8') > 65534 ||
      !fullMatch(/^[0-9a-f]{40}$/u, result.head_sha) || result.head_branch !== 'main' ||
      !validEvent(result.event) || result.status !== 'in_progress' || result.conclusion !== null) throw invalid();
  return result;
}

export function validateTarget(value) {
  const result = snapshot(value, ['identity', 'event']);
  result.identity = identity(result.identity);
  if (!validEvent(result.event) || result.identity.repository_id !== result.identity.head_repository_id) throw invalid();
  return result;
}

function token(value, attempt = false) {
  if (!(value instanceof LosslessNumber) || !validId(value.value, attempt)) throw invalid();
  return value.value;
}

// Internal-only dependency-parser seam. Preflight still always runs before it;
// the public wrapper never accepts or forwards a caller-supplied parser.
export function decodeRunFacts(rawJson, endpoint, parser) {
  try {
    if (!validEndpoint(endpoint)) throw invalid();
    const body = parseBoundedRunResponse(rawJson, parser);
    object(body);
    const repository = ownData(body, 'repository');
    const head = ownData(body, 'head_repository');
    object(repository); object(head);
    const result = {
      schema_version: 2,
      endpoint,
      identity: {
        id: token(ownData(body, 'id')),
        run_attempt: token(ownData(body, 'run_attempt'), true),
        workflow_id: token(ownData(body, 'workflow_id')),
        repository_id: token(ownData(repository, 'id')),
        head_repository_id: token(ownData(head, 'id')),
      },
      raw_path: ownData(body, 'path'),
      head_sha: ownData(body, 'head_sha'),
      head_branch: ownData(body, 'head_branch'),
      event: ownData(body, 'event'),
      status: ownData(body, 'status'),
      conclusion: ownData(body, 'conclusion'),
    };
    validateFacts(result);
    return result;
  } catch { throw invalid(); }
}
