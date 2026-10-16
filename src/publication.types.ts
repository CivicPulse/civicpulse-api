/** Local additive contract; not available on hosted Supabase until rollout approval. */
export type ContentKind = 'organization' | 'calendar' | 'event' | 'layer' | 'map';
/** Unsigned base-10 integer text. Never convert revision/generation to JS Number. */
export type DecimalCounter = string;
export interface PublicationManifest {
  schema_version: 1;
  dataset_epoch: string;
  generation: DecimalCounter;
  bootstrap_complete: boolean;
  counts: Record<ContentKind, number>;
  records: Array<{ kind: ContentKind; id: string; revision: DecimalCounter }>;
  layers: Array<{ id: string; revision: DecimalCounter; mode: 'stored' | 'events'; feature_count: number }>;
}

export type WebsiteState = 'unknown' | 'pending_publication' | 'pending_removal' | 'live' | 'absent';
export type DeliveryState = 'queued' | 'exporting' | 'building' | 'validating' | 'ready' | 'deploying' | 'live' | 'superseded' | 'failed' | 'deployment_unknown';
export interface PublicationStatus {
  dataset_epoch: string;
  desired_generation: DecimalCounter;
  live_dataset_epoch: string | null;
  live_generation: DecimalCounter | null;
  generation_lag: DecimalCounter | null;
  live_inventory_complete: boolean;
  live_deployment_id: string | null;
  live_source_sha: string | null;
  live_at: string | null;
  paused: boolean;
  bootstrap_complete: boolean;
  /** Always null in M2b foundation: job controls are not implemented. */
  state: DeliveryState | null;
  active_job: { job_id: string; generation: DecimalCounter; run_url: string | null } | null;
  last_error: { code: 'export_failed' | 'build_failed' | 'validation_failed' | 'deployment_failed' | 'deployment_unknown' | 'reconciliation_failed'; occurred_at: string } | null;
  next_attempt_at: string | null;
  status_error: 'live_generation_ahead' | null;
  observed_at: string;
}
export interface RecordPublicationStatus {
  dataset_epoch: string;
  live_dataset_epoch: string | null;
  last_event_id: string | null;
  last_action: 'publish' | 'withdraw' | null;
  last_generation: DecimalCounter | null;
  published_revision: DecimalCounter | null;
  live_revision: DecimalCounter | null;
  website_state: WebsiteState;
  observed_at: string;
}
