# Local M2b identity and staff-status foundation

Local only. [Parent ADR 0001](../../docs/adr/0001-static-resident-publication.md)
and its supporting contract define the agreed shapes and future controls. This
increment preserves all frozen v1 signatures and the M2a manifest. It introduces
no machine login, password, role membership, connection grant or hosted change.

## Browser contract and consumption

`POST /rest/v1/rpc/cms_publication_status`, body `{}`: use client
`publicationStatus()`. `POST /rest/v1/rpc/cms_record_publication_status`, body
`{"p_kind":"event","p_id":"source-id"}`: use `recordPublicationStatus(kind,id)`.
Both require a live editor/admin membership; anonymous and nonstaff callers fail
with `42501`. Invalid kind/empty ID fails `22023` after authorization. Status reads
use a single coherent SQL snapshot and fetch uses `cache: no-store`.

Exact structures are `PublicationStatus` and `RecordPublicationStatus` in
`src/publication.types.ts`; local RPC declarations are in `src/database.types.ts`.
Use the standalone export procedure in [the manifest handoff](publication-manifest-handoff.md),
from this increment's pinned commit, into a **new local-only vendor directory**.
Do not replace the hosted v1 or frozen M2a bundle merely to pick up status methods.
The exported file hashes change; there is no package publication or remote RPC yet.

Initial global status has actual epoch/generation, paused true, bootstrap false,
null job/live/error/retry fields and live_inventory_complete false. It never
synthesizes queued/live from a successful publication. Per-record status is exactly
unknown, pending_publication, pending_removal, live or absent, comparing published
revision (never draft revision) against complete verified same-epoch inventory.
Cross-epoch live receipts/revisions remain qualified by live_dataset_epoch;
comparison is unknown. Same-epoch live generation ahead produces status_error
live_generation_ahead, null lag and unknown per-record status. Incomplete inventory
also prevents comparison. observed_at is read time, not evidence of website freshness.

## Grants matrix

| Identity | Staff status wrappers / underlying helpers | Pause function | Private tables / role guard |
| --- | --- | --- | --- |
| PUBLIC / anon | No EXECUTE | No EXECUTE | No access |
| authenticated nonstaff | EXECUTE; live membership check denies | No EXECUTE | No access |
| editor / admin | EXECUTE; live membership required on every read | No EXECUTE | No delivery-table access |
| dispatcher | No grant | No grant; capability check also denies | No access |
| runner | No grant | No grant; capability check also denies | No access |
| reconciler | No grant | No grant; capability check also denies | No access |
| publication_operator | No grant | Future narrowly provisioned EXECUTE only; registry required | No access |

Machine provisioning is deferred: no actual machine has an EXECUTE grant in this
migration. Tests grant the intended operator entrypoint to disposable NOLOGIN
identities. Future provisioning must separately grant CONNECT, schema USAGE and
only approved fixed functions, using a dedicated verified TLS/session login. No
machine is a CMS staff member or inherits authenticated/service-role privileges.

The private registry matches session_user name **and role OID**, capability,
enabled flag and database-clock expiry. SET ROLE or a mutable JWT claim cannot
supply machine identity. Drop/recreate of a name invalidates the prior registration.
Registry and private-state RLS have no browser/machine policies. Only the migration
owner can provision registry rows; no registry-management RPC exists.

Public wrappers are SECURITY INVOKER. The two underlying status functions and
pause entrypoint are SECURITY DEFINER, owned by the migration executor (postgres
in the disposable harness), with empty search_path and fully qualified relations.
The machine guard is invoker-only and has no external EXECUTE grant. Explicit
PUBLIC/anon/authenticated revokes precede narrow status grants. The status helper
also checks membership, so direct helper invocation cannot bypass authorization.
No new entrypoint writes CMS content, drafts, membership or publication generation.

`set_pipeline_paused(true, review_reference)` requires the operator registry and
EXECUTE privilege, takes the catalog lock and records a private audit receipt.
False always fails `55000`; bootstrap/baseline/unknown-deployment resume checks do
not exist yet. Pausing never clears live receipt evidence.

## Validation and remaining scope

`npm test` covers additive client request shape/auth; `npm run test:db` applies all
local migrations to a fresh disposable database and runs the existing security,
publication and privacy suites plus `tests/delivery-status.sql`. Database is dropped
finally. Tests use SET SESSION AUTHORIZATION for actual anon/authenticated and
separate dispatcher/runner/reconciler/operator/impostor identities, never owner
execution as the privilege assertion. Owner-only fixture setup seeds verified
receipts; that setup is not evidence of an implemented deployment verification API.

Coverage includes staff revocation, absent/unknown/live/pending/epoch/rewind states,
draft-vs-public revision, direct-table denial, cross-capability denial even with an
accidental EXECUTE grant, inherited-role impersonation, revoked EXECUTE, mismatched
OID, actual dropped/recreated role name, disabled/expired/deleted registrations.
No real login or credentials persist: fixture roles are rolled back.

**At the M2b foundation checkpoint, unimplemented:** dispatch/build claims, job storage/transitions, leases/fences,
begin/finish deploy, reconciliation/provider attestations, retry scheduling,
bootstrap approval, epoch reset/baseline approval, source-only release authority,
all-empty approval and resume. No deployment route exists to bypass those gates.
Follow-up increments require their own real-role/concurrency/transition tests and
independent Security review. This foundation cannot make a website update live. The subsequent dispatch-only
increment below changes only its dispatch coverage.

## Local dispatch lease/ack increment

Implements only the accepted run/dispatch portion of parent
[delivery gate precision](../../docs/architecture-delivery-gates.md).
`civicpulse_delivery.claim_dispatch(p_worker_id text,p_limit integer)` returns a
JSON receipt array, or `[]`. `finish_dispatch(p_event_id uuid,p_dispatch_lease_id
uuid,p_outcome text,p_run_id text,p_error_code text)` returns
`{accepted:boolean,next_attempt_at:timestamp|null}`. These are private SQL/session
interfaces, not browser RPCs; there is no browser client/vendor update for them.

Both functions are definer functions with empty search_path and explicit machine
checks, including after lock acquisition. PUBLIC/anon/authenticated execution is
revoked. No real machine receives a grant. Future dispatcher provisioning alone
may grant these two fixed functions and schema USAGE/CONNECT; runner/reconciler/
operator capabilities cannot use them, even with an accidental function grant.
Internal run-parser and retry-time helpers have no external grants.

Claims require valid dispatcher name/OID/registry/expiry plus unpaused,
bootstrapped, approved current epoch. Current public/operator interfaces cannot
establish those gates: tests seed them as owner only. Claims serialize on the
catalog lock, select current-epoch events in generation order, enforce batch
1–100 and canonical worker syntax, and create two-minute DB-clock leases bound
to caller name/OID/token. Worker labels are not identities. Dispatch does not
coalesce or mutate generation/live state; build debounce remains future work.

Accepted acknowledgements permit null run correlation; otherwise require positive
canonical decimal `run_id:attempt` text (20/10-digit limits), never JS Number.
Accepted error is null. Retry errors are dispatch_timeout, dispatch_unavailable,
dispatch_rate_limited; permanent errors are dispatch_unauthorized,
dispatch_invalid_request, dispatch_configuration. `lease_expired` is internal.
No raw provider response is stored. Exact acknowledgement replays return the saved
result without new jitter or mutation, only for the same still-authorized identity
and unreplaced token. Changed/expired-first/stale/other-owner acknowledgements
fail `40001`; malformed inputs `22023`; unauthorized registry/ACL `42501`.

Retries persist 30/120/600/3600-second bases plus 0–20% positive jitter. Each
expired attempt is counted once. Fifth failed/expired attempt or any permanent
failure records dispatch_state failed with no next automatic attempt (intervention
required). Durable event/publication intent remains. No automatic recovery or
operator retry method exists yet. A future adapter must honor longer Retry-After
without adding an unreviewed RPC parameter. No GitHub HTTP calls occur here.

Validation: `npm run test:db` includes actual-role dispatch SQL plus two concurrent
PostgreSQL backends using distinct session identities. It checks unique leasing,
transaction rollback, empty work, gates, capability separation, malformed values,
null/large run correlation, saved-result replay, revoked/recreated callers,
changed/replaced leases, expiry, persisted jitter and fifth/permanent failure.
The concurrency harness isolates owner-created fixture state in the disposable
DB, then drops all fixture roles; no credentials are created. No claim_build,
heartbeat/transition, begin/finish_deploy, source admission, verified-live writer,
bootstrap/reset/baseline or all-empty approval is added by this increment.
