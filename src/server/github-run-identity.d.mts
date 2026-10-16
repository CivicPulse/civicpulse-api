/** Six unauthenticated identity facts only; no approval or source authority. */
export interface RunIdentityFacts {
  id: string;
  run_attempt: string;
  workflow_id: string;
  repository_id: string;
  head_repository_id: string;
  path: string;
}
export declare const runIdentityLimits: Readonly<{ rawBytes: number; depth: number; tokens: number; stringBytes: number }>;
export declare function decodeGitHubRunIdentity(rawJson: string): RunIdentityFacts;
export declare function assertGitHubRunIdentity(actual: RunIdentityFacts, expected: RunIdentityFacts): void;
