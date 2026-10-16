# Static publication: API boundary and missing support

Status: requirements and additive direction agreed with the lead/CP-Architect;
implementation-ready shapes and explicit implementation handoff pending. **Nothing
in this document is a deployed API extension.** Existing v1 signatures remain
unchanged. No hosted migrations, production imports, secrets, or infrastructure
changes are authorized at this stage.

Architecture owner: CP-Architect (`w12:p5`). The named decision artifact is
`civicpulse-web/docs/static-publication-architecture.md` in the web repository.
It was not yet present when this API document was prepared; the direction below
records the architect's explicit coordination message, not an independent ADR.
API-Dev owns subsequent database/RPC implementation once that contract is handed
off. The lead selected **GitHub Actions as the trusted runner**. Actions is enabled
for `CivicPulse/civicpulse-web`; no deployment workflow, Actions secrets, or
environment has been configured yet.

## User requirements

- Resident-facing pages and their data work while the API is offline.
- Publish/withdraw should trigger a new Astro static build/deployment, preserving
  the last successful deployed site on API/export/build/deploy failures.
- Truly dynamic browser features always have a usable static fallback.
- Publication accepted by the API is distinct from website deployment completed.
- Failed, repeated, overlapping, and missed triggers must reconcile safely.

## Current deployed v1 evidence

Source: [migration](../supabase/migrations/20261016195541_civicpulse_content_api.sql)
and [API contract](api.md).

| Existing behavior | Missing capability |
| --- | --- |
| `publish(kind,id,expected_revision)` returns the reviewed draft revision | No global dataset generation, dataset epoch, event receipt, or build correlation |
| `withdraw(kind,id,expected_revision)` returns void | No explicit durable export tombstone contract or deployment receipt |
| Successful writes append `civicpulse.history` in the same transaction | Audit is durable, but has no delivery claim/lease/retry state; sequence is not a supported commit-ordered generation or delivery cursor |
| History includes sequence, action, kind/id, revision, actor, time, payload | No global publication state; saves also produce entries; republishing the same draft revision produces another audit entry |
| `content` and `layer_geojson` expose current published state | No atomic complete export inventory, immutable snapshot handle, dataset bootstrap marker, or stable multi-page snapshot guarantee |
| Published layer payload omits geometry; publication audit retains draft payload including geometry | Withdraw audit contains published metadata only; rebuilding an immutable dataset from history would need a separately designed reconstruction contract |
| `cms_history` is staff-readable | No deployment-status read contract or last-success generation/URL, and no runner write/status interface |
| PostgreSQL controls admin publication | No trusted runner identity/grants, queue consumer, deployment webhook, build workflow, or configured Cloudflare credentials |

Do not infer an inventory from a successful first page or treat an empty API as
an intentional empty published site. Do not use draft revision as a global event
ID. A successful v1 publish alone cannot prove that the resident website updated.

## Architect-agreed additive direction (not implemented)

- Publish/withdraw only: atomically increment a **global generation**, separate
  from document revision, and write durable logged outbox intent. Record removals
  as tombstones. A dataset epoch identifies restore/reinitialization boundaries.
- An atomic manifest RPC returns a complete inventory from one database
  statement/snapshot: `(kind,id,revision)`, counts, per-layer feature counts,
  `bootstrapComplete`, and the common epoch/generation. Intentional empty datasets
  and deleted records must be distinguishable from incomplete/bootstrap data.
- Export uses Manifest A → deterministic paginated content/features → Manifest B.
  Identical epoch/generation plus validated inventory/counts makes an export
  candidate eligible for use. Any inconsistency discards the **whole** candidate;
  do not mix pages from retries or silently fill missing rows from older data.
  The runner persists the validated candidate as an immutable build input; a
  live manifest by itself is not an immutable stored snapshot.
- Runner-only claim/lease/retry/status operations, idempotent reconciliation, and
  staff-only deployment visibility are additive. An optional v2 publication
  receipt may later expose event correlation; existing v1 responses stay stable.
- Authenticated GitHub Actions polling is the reliable delivery baseline.
  Server-side dispatch may accelerate it but is not the sole durable trigger.
  The runner must preserve the last successful site and prevent stale jobs from
  superseding newer accepted deployments; precise fencing belongs to the ADR.

## Agreement needed before API implementation starts

CP-Architect supplies the implementation-ready contract, including:

1. Object/RPC names, argument/result/error shapes, grants, runner authentication,
   and separation from normal staff identities.
2. Epoch initialization/restore rules; bootstrap ownership and completion criteria;
   generation increments, including same-revision republish/no-op semantics.
3. Manifest canonical equality, complete inventory/count definitions (including
   generated event-locations), pagination ordering, tombstones/removal semantics,
   and resource bounds for large layers.
4. Event deduplication/coalescing, leases/expiry, retries/backoff, reconciliation,
   deployment ordering/fencing, status transitions, and allowed status readers.
5. Snapshot/build/deploy identifiers and retention responsibilities across API,
   GitHub Actions, and Cloudflare; how last-success state survives failures.

After explicit agreement, API-Dev can prepare additive migrations/RPCs and
**disposable local** tests without deploying them. Verification should cover
atomic intent on commit/rollback, no generation change on draft saves, concurrent
publish/withdraw, intentional empties/removals, epoch changes, interrupted exports,
duplicate/stale worker attempts, lease recovery, authorization, and last-success
status retention. Hosted changes require separate lead coordination.

## Remaining operational tasks

- Web-Dev: public Supabase URL/publishable-key configuration; choose supported Auth
  login/callback behavior and confirm hosted redirects/provider/email delivery.
- Lead/operator: hosted signup policy, staff memberships, leaked-password
  protection setting, and initial staff session for an explicitly authorized
  draft import/admin-reviewed publication.
- Architect/lead: GitHub workflow/environment/secret setup and Cloudflare deployment
  credentials/project binding after contract agreement. No browser deploy secrets.
- Preserve existing web content until bootstrap/export readiness is explicit.

The [Web-Dev handoff](web-integration-handoff.md) remains the v1 integration source;
[this import procedure](import-data.md) remains draft-only and production-gated.
