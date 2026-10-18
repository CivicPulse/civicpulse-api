/** Private SQL wire only. No browser client, credentials, or origin attestation. */
export type UUID = string;
export type Decimal = string;
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export interface DeliveryConfig {
  schema_version: 1;
  source: {
    repository_id: Decimal; repository_owner_id: Decimal; repository_full_name: string;
    workflow_id: Decimal; workflow_path: string; workflow_file_sha256: string;
    ref: 'refs/heads/main'; allowed_events: ('push' | 'schedule' | 'workflow_dispatch')[];
    api_version: '2026-03-10'; policy_format_version: 1;
    protection_bundle: { classic: { [key: string]: Json }; rulesets: Json[]; effective_rules: Json[] };
    checkout_contract_version: 1; run_path_form: 'bare' | 'relative-main' | 'repository-main';
  };
  provider: {
    account_id: string; project_id: string; project_name: string;
    production_origin: 'https://www.civpulse.org'; pages_origin: string;
  };
  operation: {
    mode: 'solo-supervised-v1'; environment_name: 'production';
    environment_evidence_sha256: string; operator_user_id: Decimal;
    required_check_context: 'civicpulse-validate'; required_check_app_id: Decimal;
  };
}
export interface SourceChallenge {
  challenge_id: UUID; config_version: UUID; issued_at: string; expires_at: string;
  run_id: string; source_sha: string; purpose: 'claim'; job_id: null; config: DeliveryConfig;
}
export interface BaselineChallenge {
  challenge_id: UUID; config_version: UUID; purpose: 'baseline'; job_id: null;
  attempt_id: null; deployment_id: string; issued_at: string; expires_at: string;
  config: DeliveryConfig;
}
export interface ObservationReceipt {
  observation_id: UUID; challenge_id: UUID; config_version: UUID;
  received_at: string; expires_at: string; evidence_sha256: string;
}
export interface SourceReceipt extends ObservationReceipt { source_sha: string }
/** Private local claim preparation; no upload permission is implied. */
export interface BuildClaim {
  job_id: UUID; lease_id: UUID; fence: Decimal; dataset_epoch: UUID;
  target_generation: Decimal; lease_expires_at: string;
}
export interface SourceRunEvidence {
  id: Decimal; run_attempt: Decimal; workflow_id: Decimal; path: string;
  repository_id: Decimal; head_repository_id: Decimal; event: 'push' | 'schedule' | 'workflow_dispatch';
  head_branch: 'main'; head_sha: string; status: 'in_progress'; conclusion: null;
  actor_id: Decimal; triggering_actor_id: Decimal; referenced_workflows: [];
}
export interface SourceEvidence {
  schema_version: 1;
  repository: { id: Decimal; owner_id: Decimal; full_name: string; fork: false; archived: false; default_branch: 'main' };
  workflow: { id: Decimal; path: string; state: 'active' };
  run_before: SourceRunEvidence; run_attempt: SourceRunEvidence; run_after: SourceRunEvidence;
  ref_before: { ref: 'refs/heads/main'; object_type: 'commit'; sha: string };
  ref_after: { ref: 'refs/heads/main'; object_type: 'commit'; sha: string };
  protection_before: DeliveryConfig['source']['protection_bundle'];
  protection_after: DeliveryConfig['source']['protection_bundle'];
  workflow_file: { path: string; source_sha: string; sha256: string; bytes: number };
  requests: { endpoint_key: 'repository' | 'workflow' | 'run_before' | 'run_attempt' | 'run_after' | 'ref_before' | 'ref_after' | 'classic_before' | 'classic_after' | 'rulesets_before' | 'rulesets_after' | 'effective_rules_before' | 'effective_rules_after' | 'workflow_file'; page: number; status: 200; github_request_id: string | null }[];
}
export interface BaselineEvidence {
  schema_version: 1;
  project: { id: string; name: string; canonical_deployment_id: string; production_branch: 'main' };
  deployment: { id: string; project_id: string; project_name: string; environment: 'production'; stage: 'deploy'; status: 'success'; source_sha: string; branch: 'main' };
  markers: { deployment: null; production: null; pages: null };
  artifact: { artifact_sha256: string; served_inventory_sha256: string };
  github_terminal: null;
  requests: { endpoint_key: 'project_before' | 'project_after' | 'deployment' | 'marker_deployment' | 'marker_production' | 'marker_pages' | 'artifact_files'; page: number; status: 200 | 404; request_id: string | null }[];
}
