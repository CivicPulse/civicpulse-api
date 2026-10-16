import type { WorkflowPathPolicyV2 } from './github-workflow-path-v2.mjs';

export interface RunNumericIdentityV2 {
  id: string;
  run_attempt: string;
  workflow_id: string;
  repository_id: string;
  head_repository_id: string;
}
/** Unauthenticated facts; endpoint/schema are local context, not provider proof. */
export interface InProgressRunFactsV2 {
  schema_version: 2;
  endpoint: 'run' | 'attempt';
  identity: RunNumericIdentityV2;
  raw_path: string;
  head_sha: string;
  head_branch: 'main';
  event: 'push' | 'schedule' | 'workflow_dispatch';
  status: 'in_progress';
  conclusion: null;
}
export interface RunTargetV2 {
  identity: RunNumericIdentityV2;
  event: 'push' | 'schedule' | 'workflow_dispatch';
}
export declare function decodeGitHubInProgressRunFactsV2(rawJson: string, endpoint: 'run' | 'attempt'): InProgressRunFactsV2;
export declare function assertGitHubInProgressRunFactsV2(actual: InProgressRunFactsV2, expected: RunTargetV2, pathPolicy: WorkflowPathPolicyV2): void;
