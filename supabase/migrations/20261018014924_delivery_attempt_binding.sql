-- LOCAL M2.3 schema preparation only. No begin/finish/reconcile callable exists.
-- Intent bindings are append-only; outcomes/reconciliation will be separate
-- records under the accepted provider matrix, never edits to reviewed intent.
create table civicpulse_delivery.deployment_intents (
  attempt_id uuid primary key default gen_random_uuid(),
  job_id uuid not null unique references civicpulse_delivery.build_jobs,
  fence bigint not null unique check(fence>0),
  config_version uuid not null references civicpulse_delivery.delivery_configs,
  dataset_epoch uuid not null, generation bigint not null check(generation>=0),
  source_sha text not null check(source_sha collate "C" ~ '^[0-9a-f]{40}$'),
  snapshot_sha256 text not null check(snapshot_sha256 collate "C" ~ '^[0-9a-f]{64}$'),
  artifact_sha256 text not null check(artifact_sha256 collate "C" ~ '^[0-9a-f]{64}$'),
  publication_manifest jsonb not null check(jsonb_typeof(publication_manifest)='object'),
  actor name not null, actor_oid oid not null,
  begun_at timestamptz not null default clock_timestamp(),
  source_observation_id uuid not null unique references civicpulse_delivery.observations,
  predeploy_observation_id uuid not null unique references civicpulse_delivery.observations,
  -- Full prior approved provider projection is captured at begin, allowing
  -- later failure checks without treating candidate ID as current production.
  prior_observation_id uuid not null references civicpulse_delivery.observations,
  prior_deployment_id text not null,
  prior_production jsonb not null check(jsonb_typeof(prior_production)='object')
);
alter table civicpulse_delivery.deployment_intents enable row level security;
revoke all on civicpulse_delivery.deployment_intents from public,anon,authenticated;
create function civicpulse_delivery.preserve_deployment_intent() returns trigger
language plpgsql security invoker set search_path='' as $$ begin
  raise exception 'Deployment intent is immutable' using errcode='55000';
end $$;
revoke all on function civicpulse_delivery.preserve_deployment_intent() from public,anon,authenticated;
create trigger immutable_deployment_intent before update or delete on civicpulse_delivery.deployment_intents
  for each row execute function civicpulse_delivery.preserve_deployment_intent();
