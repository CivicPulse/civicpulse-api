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

## Final local review coverage

The expanded connected suite covers:

| Boundary | Actual SQL evidence |
| --- | --- |
| Begin atomicity | Late enrollment-update trigger failure restores intent, both receipts, job, fence and lock; repeated begin never authorizes twice |
| Identity | Disabled/expired runner and receipt producer; actual dropped/recreated runner OID; expired/revoked/recreated reconciler denied saved replay |
| Prior production | Changed baseline artifact/source/canonical remains audit-only; first markerless P and second admitted CMS P both exercised |
| Drift | Publication before begin rejects without consumption; publication after begin remains desired while older pinned generation becomes verified live |
| Finish/reconcile atomicity | Late acknowledgment-insert faults restore every authority/receipt/live field |
| Unknown outcome | Lease expiry, operator pause/resume/reset attempts cannot release authority; fresh partial reconciliation repeatedly changes nothing |
| Terminal evidence | Active attempt/unknown conclusion, duplicate numeric-equivalent page, unknown endpoint, status 0 reject; newer attempt and outsider/swapped prior remain audit-only |
| Verified live | Changed admitted served-inventory digest cannot unlock; complete stored inventory only; second-job terminal failure preserves every prior live field and latches intervention |
| Saved acknowledgment | Exact replay after receipt expiry is read-only; wrong fence/purpose and invalid current identity reject |
| Prebegin recovery | Terminal evidence plus actual DB expiry required; no intent/live creation; existing intervention and spent identity retained |
| Concurrency | Separate actual sessions: duplicate begin authorizes once; unexpired begin versus terminal cannot unlock; expired begin loses to proven recovery |

`tests/deployment-control.sql` and `tests/deployment-outcomes.sql` use full private
state snapshots for atomic rejection/nonconsumption assertions. Owner mutations
are restricted to test clock advancement, negative corruption, registry lifecycle
and fault injection. Approvals, source/provider receipts, claims, intents and live
admission are created through actual role-checked functions, never owner-seeded.

`tests/build-claims.sql`/`tests/build-transitions.sql` retain the independently
reviewed objective-supersession and failure/intervention regressions.
`scripts/test-deployment-concurrency.mjs` adds three independent disposable DB
races; existing claim/dispatch concurrency remains intact. Run these harnesses
sequentially: cluster-wide disposable role names are intentionally shared.

Developer validation for this review candidate:

- `npm test`: 66 passed, zero failures/skips.
- `npm run test:db`: exit 0, including all connected scenarios and five
  concurrency lanes (claim, dispatch, three deployment races).
- `node scripts/test-delivery-upgrade.mjs`: exit 0, run after SQL completion;
  populated four-migration baseline preservation and warmed publish retained.
- `node scripts/test-publication-fixture.mjs`: separate sequential M1 preservation
  check exited 0: A7 → B4, generation 7 → 10; withdrawal/pagination/empty-layer/
  idempotency/read-only checks passed.
- `git diff --check`: clean.

Independent M2.3 implementation review is still required. No external grants,
real login, credentials, provider calls, hosted migrations or remote pushes were
performed. M2.3 private function signatures/results are in the linked server-only
types; public v1/M2a remain unchanged.

### Existing status discrepancy routed to lead

The M2.2 `cms_publication_status` function returns `last_error` as text/null, while
`src/publication.types.ts` declares `{code,occurred_at}|null`. This pre-existing
mismatch was reported rather than silently changing the frozen browser shape.
The lead's disposition is required before claiming complete status/type parity.

### Adapter-only limits

SQL validates projected schema, identities, context, receipt freshness and state
transitions. It cannot authenticate caller-supplied GitHub/Cloudflare facts or
prove hashes correspond to acquired bytes. The authorized adapter must acquire
fixed endpoints, verify both run and attempt, full source/config evidence, stage
terminal timing and bracketing, exact deployment correlation, and complete retained
artifact/route/encoding/marker checks at all three origins. Failure evidence must
verify immutable prior P bytes even though candidate marker/artifact fields are
null. The sole uploader must honor one invocation and external-process fencing;
a database fence cannot stop a previously authorized process from uploading again.
These are not replaced by constructed SQL fixtures. No hosted/production approval
or source-adapter implementation proof follows from this local review candidate.
