/** JSON text containing lossless numeric tokens. Never native-parse and reserialize policy bodies. */
export type SourceEvidenceJson = string & { readonly __sourceEvidenceJson: unique symbol };
export type SourceResponseEndpoint = 'repository' | 'workflow' | 'run' | 'attempt' | 'ref' | 'classic' | 'ruleset_list' | 'ruleset_detail' | 'effective_rules';
/** Pure structure only; does not authenticate endpoint, freshness or authority. */
export function decodeGitHubSourceResponse(rawJson: string, endpoint: SourceResponseEndpoint): SourceEvidenceJson;
export type SourceEvidenceParts = Record<'repository' | 'workflow' | 'run_before' | 'run_attempt' | 'run_after' | 'ref_before' | 'ref_after' | 'protection_before' | 'protection_after' | 'workflow_file' | 'requests', string>;
export function assembleGitHubSourceEvidence(parts: SourceEvidenceParts): SourceEvidenceJson;
export interface RulesetFacts { id: string; source_type: 'Repository' | 'Organization'; source: string; enforcement: 'active' | 'disabled' | 'evaluate'; bypass_present: boolean; bypass_actors?: Array<{ actor_id: string | null; actor_type: string; bypass_mode: string }> }
export interface RepositorySourceFacts { id: string; owner_id: string; full_name: string; fork: boolean; archived: boolean; default_branch: string; owner_type: 'User' | 'Organization' }
export interface SourceRunFacts { id: string; run_attempt: string; workflow_id: string; path: string; repository_id: string; head_repository_id: string; event: 'push' | 'schedule' | 'workflow_dispatch'; head_branch: 'main'; head_sha: string; status: 'in_progress'; conclusion: null; actor_id: string; triggering_actor_id: string; referenced_workflows: [] }
export interface SourceResponseFactMap {
 repository: RepositorySourceFacts; workflow: { id: string; path: string; state: string };
 run: SourceRunFacts; attempt: SourceRunFacts; ref: { ref: string; object_type: string; sha: string };
 classic: null; ruleset_list: RulesetFacts[]; ruleset_detail: RulesetFacts;
 effective_rules: Array<{ruleset_id: string; source_type: string; source: string}>;
}
export function projectGitHubSourceResponse<E extends SourceResponseEndpoint>(rawJson: string, endpoint: E): { json: SourceEvidenceJson; canonical_json: SourceEvidenceJson; facts: SourceResponseFactMap[E] };
export function canonicalizeGitHubPolicyJson(json: string): SourceEvidenceJson;
export function projectGitHubSourceConfig(configJson: string): { source: Record<string, string | string[]>; provider: Record<string,string>; protection_json: SourceEvidenceJson; canonical_json: SourceEvidenceJson };
export interface PolicyPage { page: number; next_page: number | null; json: string }
export function assembleGitHubProtectionEvidence(input: { classic_json: string; list_pages: PolicyPage[]; detail_json: string[]; effective_pages: PolicyPage[] }, context: { repository_full_name: string; owner: string; owner_type: 'User' | 'Organization'; scope: 'repository' | 'organization' }): SourceEvidenceJson;
export function inspectGitHubSourceResponseBudget(rawJson: string): { tokens: number; bytes: number };
/** Private acquisition sidecar. Never add these fields to SQL requests. */
export interface SourceRequestAudit {
  request_index: number; phase: 'before' | 'after'; operation: SourceResponseEndpoint | 'workflow_file';
  scope: 'repository' | 'organization'; repository_id: string; repository_owner_id: string; repository_full_name: string;
  ruleset_id: string | null; page: number | null; per_page: 100 | null; includes_parents: true | null;
  path: string; query: ReadonlyArray<readonly [string,string]>; next_page: number | null;
  body_sha256: string; github_request_id: string | null;
}
export interface SourceAcquisitionAudit {
  schema_version: 1; challenge_id: string; config_version: string; source_sha: string;
  evidence_sha256: string; requests: SourceRequestAudit[];
}
