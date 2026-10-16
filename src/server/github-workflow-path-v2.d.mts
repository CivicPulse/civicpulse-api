/** Structured pure comparison arguments; neither configuration nor approval. */
export interface WorkflowPathPolicyV2 {
  policy: 'cp-workflow-path-v2';
  repository_full_name: string;
  workflow_path: string;
  source_sha: string;
  run_path_form: 'bare' | 'relative-main' | 'repository-main';
}
export type WorkflowPathObservationV2 =
  | { endpoint: 'workflow'; raw_path: string }
  | { endpoint: 'run' | 'attempt'; raw_path: string; head_branch: string; head_sha: string };
/** Returns void on structural equality only; does not authenticate a source. */
export declare function assertGitHubWorkflowPathV2(observation: WorkflowPathObservationV2, expected: WorkflowPathPolicyV2): void;
