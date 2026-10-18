/** Private SQL wire; no browser exports or provider acquisition/authentication. */
import type { DeliveryState } from '../publication.types.js';
import type { DeliveryConfig, ObservationReceipt } from './delivery-enrollment.types.js';
export type ProviderTarget =
  | { purpose: 'baseline'; job_id: null; attempt_id: null; deployment_id: string }
  | { purpose: 'predeploy'; job_id: string; attempt_id: null; deployment_id: string }
  | { purpose: 'outcome'; job_id: string; attempt_id: string; deployment_id: string | null }
  | { purpose: 'terminal'; job_id: string; attempt_id: null; deployment_id: null }
  | { purpose: 'terminal'; job_id: string; attempt_id: string; deployment_id: string | null };
export type ProviderChallenge = ProviderTarget & {
  challenge_id: string; config_version: string; issued_at: string; expires_at: string; config: DeliveryConfig;
};
/** Existence never implies eligibility; SQL retains classification privately. */
export type ProviderReceipt = ObservationReceipt;
export type TerminalConclusion = 'action_required' | 'cancelled' | 'failure' | 'neutral' | 'skipped' | 'stale' | 'startup_failure' | 'success' | 'timed_out';
export interface TerminalRun {
  repository_id: string; head_repository_id: string; workflow_id: string;
  run_id: string; run_attempt: string; raw_path: string; head_branch: 'main';
  head_sha: string; event: 'push' | 'schedule' | 'workflow_dispatch';
  status: 'completed'; conclusion: TerminalConclusion;
}
export interface DeploymentMarker {
  schema_version: 1; job_id: string; dataset_epoch: string; generation: string;
  source_sha: string; snapshot_sha256: string;
}
export interface ProviderEvidence {
  schema_version: 1;
  project: { id: string; name: string; canonical_deployment_id: string; production_branch: string };
  deployment: null | { id: string; project_id: string; project_name: string; environment: string; stage: string; status: string; source_sha: string; branch: string };
  markers: null | { deployment: DeploymentMarker | null; production: DeploymentMarker | null; pages: DeploymentMarker | null };
  artifact: null | { artifact_sha256: string; served_inventory_sha256: string };
  github_terminal: null | { run: TerminalRun; attempt: TerminalRun };
  requests: Array<{ endpoint_key: 'project_before' | 'project_after' | 'deployment' | 'deployment_list' | 'marker_deployment' | 'marker_production' | 'marker_pages' | 'artifact_files' | 'github_run_terminal' | 'github_attempt_terminal'; page: number; status: number; request_id: string | null }>;
}
export interface BeginDeployArguments {
  p_job_id: string; p_lease_id: string; p_fence: string; p_epoch: string; p_generation: string;
  /** Snapshot digest, not PostgreSQL manifest encoding digest. */
  p_manifest_sha256: string; p_artifact_sha256: string; p_source_sha: string;
}
/** Only the first successful call authorizes one invocation. Never retry upload. */
export interface BeginDeployResult { attempt_id: string; authorized: true }
export type FinishDeployArguments = { p_attempt_id: string; p_fence: string } & (
  | { p_outcome: 'unknown'; p_deployment_id: string | null; p_observation: Record<string, never> }
  | { p_outcome: 'live' | 'failed'; p_deployment_id: string; p_observation: { observation_id: string } }
);
export interface FinishDeployResult { state: 'deployment_unknown' | 'live' | 'failed'; live_generation: string | null; live_deployment_id: string | null }
export interface ReconcileJobArguments { p_job_id: string; p_fence: string; p_observation: { observation_id: string } }
export interface ReconcileJobResult { state: DeliveryState; reclaimable: boolean; live_generation: string | null }
