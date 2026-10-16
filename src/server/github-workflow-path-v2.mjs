// Pure structural comparison only; no provider authentication or source authority.
const maxBytes = 65534;
const invalid = () => Object.assign(new Error('invalid_github_workflow_path_v2'), { code: 'invalid_github_workflow_path_v2' });
const mismatch = () => Object.assign(new Error('github_workflow_path_v2_mismatch'), { code: 'github_workflow_path_v2_mismatch' });
const fullMatch = (pattern, value) => pattern.exec(value)?.[0] === value;
const policyFields = ['policy', 'repository_full_name', 'workflow_path', 'source_sha', 'run_path_form'];
const observationFields = ['endpoint', 'raw_path', 'head_branch', 'head_sha'];

function snapshot(value, allowed) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw invalid();
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) throw invalid();
  const keys = Reflect.ownKeys(value);
  if (keys.some(key => !allowed.includes(key))) throw invalid();
  const result = Object.create(null);
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || !Object.hasOwn(descriptor, 'value') || !descriptor.enumerable) throw invalid();
    const field = descriptor.value;
    if (typeof field !== 'string' || field.length > maxBytes || Buffer.byteLength(field, 'utf8') > maxBytes) throw invalid();
    result[key] = field;
  }
  return result;
}

function exactFields(value, fields) {
  if (Object.keys(value).length !== fields.length || !fields.every(key => Object.hasOwn(value, key))) throw invalid();
}

export function assertGitHubWorkflowPathV2(observation, expected) {
  let actual, policy, expectedPath;
  try {
    actual = snapshot(observation, observationFields);
    policy = snapshot(expected, policyFields);
    exactFields(policy, policyFields);
    if (policy.policy !== 'cp-workflow-path-v2' ||
        !['bare', 'relative-main', 'repository-main'].includes(policy.run_path_form) ||
        !fullMatch(/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?\/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/u, policy.repository_full_name) ||
        policy.repository_full_name.endsWith('.git') ||
        !fullMatch(/^\.github\/workflows\/[A-Za-z0-9][A-Za-z0-9_-]*\.ya?ml$/u, policy.workflow_path) ||
        !fullMatch(/^[0-9a-f]{40}$/u, policy.source_sha)) throw invalid();
    if (actual.endpoint === 'workflow') {
      exactFields(actual, ['endpoint', 'raw_path']);
    } else if (actual.endpoint === 'run' || actual.endpoint === 'attempt') {
      exactFields(actual, observationFields);
      if (!fullMatch(/^[0-9a-f]{40}$/u, actual.head_sha)) throw invalid();
    } else throw invalid();

    // Check the selected run policy even for metadata, before concatenating.
    const runBytes = Buffer.byteLength(policy.workflow_path, 'utf8') +
      (policy.run_path_form === 'bare' ? 0 : 5) +
      (policy.run_path_form === 'repository-main' ? Buffer.byteLength(policy.repository_full_name, 'utf8') + 1 : 0);
    if (runBytes > maxBytes) throw invalid();
    expectedPath = actual.endpoint === 'workflow' || policy.run_path_form === 'bare'
      ? policy.workflow_path
      : policy.run_path_form === 'relative-main'
        ? policy.workflow_path + '@main'
        : policy.repository_full_name + '/' + policy.workflow_path + '@main';
  } catch { throw invalid(); } // No input, reflection exception or cause escapes.
  if (actual.raw_path !== expectedPath || (actual.endpoint !== 'workflow' &&
      (actual.head_branch !== 'main' || actual.head_sha !== policy.source_sha))) throw mismatch();
}
