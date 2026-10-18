# Local M2.2 build control handoff

Implements the accepted integrated contract/section4 precision SHA256
`867d23ba36de887640aa583c2aad27ce1a68e8163a71493a3da08057242c04a4`,
on M2.1 `b7639f7` and claim preparation `5dff551`. Public v1/M2a signatures
and browser vendors are unchanged. No hosted migration or credentials are used.

## Private SQL wire

All entrypoints use actual registered runner session_user name+OID, enabled/expiry
checks, shared catalog lock, empty search_path and explicit client EXECUTE revokes.
No real machine grants are installed. Future reviewed grants are EXECUTE on these
three functions only; no table/helper grants:

| Function | Result |
| --- | --- |
| `claim_build(text run_id,text source_sha)` | null or `{job_id,lease_id,fence,dataset_epoch,target_generation,lease_expires_at}` |
| `heartbeat_build(uuid job_id,uuid lease_id,bigint fence)` | `{lease_expires_at}` |
| `transition_build(uuid job_id,uuid lease_id,bigint fence,text expected_state,text state,jsonb evidence)` | `{state}` |

Counter/fence/generation JSON fields remain decimal strings. Claim requires a
fresh actual M2.1 receipt, picks newest eligible issued_at/challenge UUID, consumes
once and pins config/repository/run/source/epoch/generation. One active-job index
and locks prevent competing owners. Active exact replay retains original lease;
heartbeat alone extends five minutes. New desired content cannot retarget a job.
Expired ownership cannot be reclaimed in M2.2. Fences never reset with epochs.
No-work null requires complete same-epoch exact generation/source verified live;
this increment still has no verified-live writer.

The spent identity key is `(enrolled repository_id, canonical run_id:attempt)`;
config/epoch/workflow/source/owner changes do not create reuse dimensions.
Terminal claim55000; changed source on reserved identity40001 once operational
gates permit evaluating the reservation. Fresh attempt/receipt cannot bypass an
active/expired owner or intervention. No-work/debounce/rollback spend no identity.

## Transition evidence and failure rules

| Transition | Exact evidence |
| --- | --- |
| queued→exporting | `{}` |
| exporting→building | `{publication_manifest,snapshot_sha256}` |
| building→validating | `{artifact_sha256}` |
| validating→ready | `{}` |
| queued/exporting→failed | `{error_code:"export_failed"}` |
| building→failed | `{error_code:"build_failed"}` |
| validating/ready→failed | `{error_code:"validation_failed"}` |
| predeploy→superseded | `{reason:"content_changed"|"source_changed"|"epoch_changed"}` |

Full manifest structure/context and current authoritative JSONB equality are
required at building capture. Job manifest/snapshot/artifact and acknowledgments
are retained; later phases cannot replace earlier evidence. Supplied digests do
not prove filesystem bytes. Normal progression checks desired epoch/generation
and config. No reverse/same-state/deploy/live transition exists.

Security independently reproduced a failure escape in the original `3859239`
supersession branch: a caller reason alone released the active claim without
intervention. The focused correction
`20261018015030_require_objective_build_supersession.sql` checks objective cause
under the same catalog lock: content_changed requires the same epoch and a
strictly greater authoritative generation; epoch_changed requires a different epoch.
Unchanged reasons40001 cannot release the job. source_changed is deliberately
unavailable55000 until an exact authenticated changed-source proof gate is
reviewed; a caller string or fresh same-SHA receipt is never that proof.
Existing exact acknowledgments still replay read-only after identity checks.
M2.2 closure awaits independent correction review.

Correction SHA256:
`9be7fefb6dcf2cf4fd3011ea4af773c135d162c1d2fb9623eeb853d5842d3237`.
Regressions reject all three false reasons at all five predeploy stages and prove
a fresh same-SHA second-attempt receipt cannot create a replacement. Full job,
counter, enrollment, receipt and acknowledgment snapshots remain unchanged.
Positive controls use actual content publication and a labelled disposable
owner-simulated restore epoch; normal operator reset refuses an active job.
No hosted application or automatic historical-data repair is included.

Strict-forward follow-up `20261018015330_reject_rewound_content_supersession.sql`
matches parent precision SHA256
`2283f59099c0b32be74f86af2a30d9e651c89d45b057e43f7b7ce24fdd2beb23`.
It rejects a lower same-epoch generation as an anomaly, preserving complete
job/enrollment/receipt/fence/intervention/acknowledgment snapshots. Equal-generation
negatives and real newer-publication positives remain. Follow-up SQL SHA256:
`ae2730d59a0e3e01d4658cecfd383f313b7da57ae2dca82f8a40c93415628cc1`.

All named failures atomically latch persistent intervention and null next retry;
there is no automatic build retry or clearance RPC. Config rotation, epoch reset,
pause/resume, new source/attempt/receipt and registry recreation cannot clear it.
Prior live state and desired work remain unchanged. Supersession alone does not
latch intervention; eligible replacement requires a distinct run attempt and
fresh receipt. Source/code/privacy failures are not reclassified as transient.

Exact last transition acknowledgment returns read-only for the same currently
authorized job/owner/OID/lease/fence/predecessor/result/evidence. Terminal replay
may occur after expiry, without renewal or any fence/receipt mutation. A first
expired acknowledgment or changed/intervened acknowledgment40001; malformed
evidence22023; unauthorized caller42501. Operational gates55000. Failures roll
back atomically, including injected audit failures.

Existing staff status now reflects actual job state, its three-field approved
active_job projection, and allowlisted last_error/null next_attempt_at. It exposes
no machine identity, lease, fence, raw evidence or provider error. No-job remains
null. Record website status stays unknown without a verified CMS-live inventory.

## Reproduction and remaining integration

Developer checks: `npm run test:db` and
`node scripts/test-delivery-upgrade.mjs` exercise actual config/bootstrap/baseline/
source APIs before actual runner claims/phases. Coverage includes all five failure
mappings, fault rollback, exact replay before/after expiry, revoked/expired/recreated
identity, config/epoch intervention persistence, immutable evidence, staff status,
source/content replacement and debounce, plus two-backend competing/same-owner
claims. Catalog/RLS/direct-write checks and prior privacy/URL tests remain included.
Upgrade applies explicit migrations to a populated four-migration hosted analogue
and preserves original rows/warmed v1 behavior; it does not touch hosted history.
Run these harnesses sequentially: their disposable NOLOGIN role names are
cluster-wide even though each database is isolated. One overlapping developer
run hit a role-exists collision; the SQL suite passed and the upgrade was rerun
alone. This is harness isolation, not evidence of a migration/permission failure.

New transition migration SHA256:
`106ff4a62bb5b2d079ae11d12b321708b677078e58b248d7d3d349191763e923`.
These are developer checks pending independent frozen review.

Web's actual authenticated-source adapter→SQL→M1 exporter/build/immutable artifact
integration remains required. SQL tests use constructed upstream evidence through
the real reconciler entrypoints and do not prove provider acquisition. No actual
provider, runtime workflow, source-only verified-live positive control, upload,
begin/finish/reconcile, expired-process recovery or live receipt writer is supplied
by this increment. Those remain the later reviewed M2.3/integration boundary.
