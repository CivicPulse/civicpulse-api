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
