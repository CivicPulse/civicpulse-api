import { assertGitHubWorkflowPathV2 } from './github-workflow-path-v2.mjs';
import { decodeRunFacts, identityFields, invalid, validateFacts, validateTarget } from './github-run-facts-v2-internal.mjs';

const mismatch = () => Object.assign(new Error('github_in_progress_run_facts_v2_mismatch'), { code: 'github_in_progress_run_facts_v2_mismatch' });

// Pure facts only: endpoint is caller context, never authenticated origin.
export function decodeGitHubInProgressRunFactsV2(rawJson, endpoint) {
  return decodeRunFacts(rawJson, endpoint);
}

export function assertGitHubInProgressRunFactsV2(actual, expected, pathPolicy) {
  let facts, target;
  try {
    facts = validateFacts(actual);
    target = validateTarget(expected);
  } catch { throw invalid(); }
  try {
    assertGitHubWorkflowPathV2({ endpoint: facts.endpoint, raw_path: facts.raw_path,
      head_branch: facts.head_branch, head_sha: facts.head_sha }, pathPolicy);
  } catch (error) {
    if (error.code === 'github_workflow_path_v2_mismatch') throw mismatch();
    throw invalid();
  }
  if (facts.event !== target.event || identityFields.some(key => facts.identity[key] !== target.identity[key])) throw mismatch();
}
