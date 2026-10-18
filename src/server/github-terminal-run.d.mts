import type { RunTargetV2 } from './github-run-facts-v2.mjs';
import type { WorkflowPathPolicyV2 } from './github-workflow-path-v2.mjs';
export interface TerminalRun {
  repository_id: string; head_repository_id: string; workflow_id: string;
  run_id: string; run_attempt: string; raw_path: string; head_branch: 'main';
  head_sha: string; event: 'push'|'schedule'|'workflow_dispatch'; status: 'completed';
  conclusion: 'action_required'|'cancelled'|'failure'|'neutral'|'skipped'|'stale'|'startup_failure'|'success'|'timed_out';
}
export declare function decodeGitHubTerminalRun(rawJson: string): TerminalRun;
export declare function assertGitHubTerminalRun(actual: TerminalRun,target: RunTargetV2,pathPolicy: WorkflowPathPolicyV2,endpoint: 'run'|'attempt'): void;
