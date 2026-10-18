# Connected local M2.3

Implementation follows parent `docs/architecture-m2-integrated-contract.md`,
Security-reviewed matrix SHA-256
`2283f59099c0b32be74f86af2a30d9e651c89d45b057e43f7b7ce24fdd2beb23`
and editorial clarification
`140cb62f7073317b6234982624c4ba80bc00599d92439a76aff6827ca9b0051f`.
The reproduced M2.2 supersession finding was independently closed at
`bb1dcf8f07e4ca766bdf108a09eb4ea06ac978fe`. Its final migration is
`20261018015330_reject_rewound_content_supersession.sql`, SHA-256
`ae2730d59a0e3e01d4658cecfd383f313b7da57ae2dca82f8a40c93415628cc1`.

This is local development, pending independent frozen implementation review.
No hosted migration, credentials, provider requests, uploader, or Web adapter is
installed. Constructed reconciler SQL evidence does not prove authenticated
acquisition or three-origin byte equality.

## Connected implementation

- `20261018014924_delivery_attempt_binding.sql` retains immutable intent and prior
  production P. RLS and revoked direct permissions protect the private table.
- `20261018015522_delivery_provider_and_begin.sql` extends existing source/provider
  observations without changing their wire. Provider challenges retain P; their
  immutable classification distinguishes eligible evidence from audit-only data.
  All three marker 404s and full baseline artifact remain required for first
  predeploy. Partial replay never promotes a receipt.
- `begin_deploy` requires the owning runner, ready/unexpired claim, current exact
  manifest, approved epoch, fresh job-bound source and predeploy receipts. It
  consumes both and retains external authority atomically. Repeat begin returns
  40001, including a lost-response retry; only the initial result authorizes upload.
- `20261018023809_delivery_finish_reconcile.sql` adds saved acknowledgments and
  finish/reconciliation. Runner unknown retains authority. Reconciler live admits
  only the complete stored job inventory and retains the uploader lock. Separate
  terminal run+attempt/provider proof releases it. Failure requires deploy/failure,
  unchanged immutable prior P and complete terminal proof; it preserves prior live
  and latches intervention. Prebegin expiry recovery needs terminal proof plus DB
  expiry and no intent, preserves the spent run/fence/intervention, and records
  private `lease_expired` recovery reason.
- Correctly bound fresh audit-only reconciliation returns reclaimable:false
  without consuming evidence. Stale/wrong context returns 40001. Saved consuming
  acknowledgments replay read-only for the same currently valid registry identity.

[Private wire types](../src/server/delivery-deployment.types.ts) complement
[enrollment/source](enrollment-source-handoff.md) and
[claim/phase controls](build-control-handoff.md). Public v1/M2a and browser exports
remain unchanged. New functions receive no external EXECUTE grants; actual-role
fixtures grant only the exact functions to disposable NOLOGIN identities.

## Validation and remaining work

`npm run test:db` exercises actual operator/reconciler/runner enrollment, source,
claim, ready, predeploy, begin, unknown, live and terminal calls. New scenarios
cover immutable prior bytes, first markerless evidence, repeat begin denial,
partial nonconsumption/replay, prebegin expiry recovery, terminal failure and
unsupported stage/status denial, invalid stored inventory, stale receipts and
private catalog/direct-table permissions. Existing objective supersession, claim
concurrency and dispatch concurrency remain in the same suite.

`node scripts/test-delivery-upgrade.mjs` runs separately because fixtures share
cluster-wide test role names. It rehearses the populated known four-migration
hosted baseline through the exact local migration inventory, preserving existing
rows and warmed publication checks before connected scenarios.

Developer checkpoint: `npm test` passed 66/66; `npm run test:db` and the
sequential `node scripts/test-delivery-upgrade.mjs` both exited 0. No independent
M2.3 implementation review is claimed.

Before final M2.3 review, expand adversarial and concurrent begin/recovery coverage,
including changed prior/canonical bytes, receipt identity revocation, rollback
injection, terminal failure reconciliation and post-begin desired generation drift.
The current positive/negative SQL tests are not a claim that the full accepted
matrix has independent closure. Web-owned source/provider acquisition, artifact
sidecars, real route/encoding checks and sole-uploader integration remain separate.
Remote main and PR4 remain unchanged; no rollout authorization is inferred.
