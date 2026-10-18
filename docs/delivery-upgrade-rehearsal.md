# M2 preparation: hosted baseline → delivery foundations

2026-10-17. Local rehearsal only; no hosted apply, login provisioning or source/
job/deploy authority. M1 transport handoff is [separate](publication-fixture-handoff.md).
The lead is coordinating the integrated M2.1 contract, including prospective
bootstrap generation precision. Do not implement an alternate approval path.

## Reproduced upgrade boundary

Run `node scripts/test-delivery-upgrade.mjs` using the documented offline
`civicpulse-api-db-test` container. No DB URL, hosted config or container override
is accepted. The script creates/drops one random disposable database, installs
the four actually hosted SQLs in their deployed order, then creates an unrelated
synthetic analogue of the retained QA state: three published revision1 records,
organization/calendar draft1, private event draft5, ten history rows and no
features. These are not copies of hosted identities/payloads.

Hosted baseline files:

1. `20261016195541_civicpulse_content_api.sql`
2. `20261016195619_restrict_platform_trigger_execution.sql`
3. `20261016231409_private_event_publication_validation.sql`
4. `20261016231420_private_event_source_url_v1.sql`

Then apply these **existing local foundations**, each in a transaction, in this
explicit order (not a blanket timestamp-based push):

| File | SHA256 |
| --- | --- |
| `20261016203213_publication_generation_manifest.sql` | `78d526345735394ea9fc74ffa1750a2eda6139f0cec5eff272104335391b212a` |
| `20261016215623_delivery_identity_status_foundation.sql` | `0ca0767d19155256a47cffea801876b00c2a78bf4d4518232fbfb4f53e92cd5b` |
| `20261016220416_delivery_dispatch_leases.sql` | `e75cebae83536f330b1dabfae0d6c7ce7765f9685b45589ae23fc9b8317ac21d` |
| `20261016221834_receipt_manifest_structure.sql` | `fa0b9fc4fac6d7e622639c883e478ddb94cc503f148b7446bea178adfeafb945` |

Passed developer evidence: `node scripts/test-delivery-upgrade.mjs` exit0.
Exact JSONB snapshots of drafts/publications/history/features/members survive
the upgrade unchanged. Existing publications appear in the new complete manifest
at generation0/bootstrapfalse; no historical outbox events are fabricated.
Pipeline remains paused, epoch unapproved, live inventory incomplete. A v1
publish prepared and executed before upgrade, reused in the same session after
upgrade under authenticated session authorization, increments generation and
creates one durable intent. Rolling back that test publication restores the
entire prior snapshot/generation. Staff status remains unknown/null, never live.

This does **not** rehearse future unimplemented authority migrations, Supabase
migration-history recording, hosted PostgREST reload, pooler identity, provider
access or production credentials. The full existing disposable SQL suite passed
alongside M1; independent review remains a separate checkpoint.

## Integrated contract boundary to freeze through Lead

Use [ADR0004](../../docs/adr/0004-source-admission-trust.md), the
[publication contract](../../docs/architecture-publication-contract.md), and
[delivery gates](../../docs/architecture-delivery-gates.md) together. Batch the
following actual interfaces and adversarial tests; do not add another series of
standalone parser prerequisites or a temporary operator admission bypass.

- Operator: exact source-config enrollment/activation while paused and without
  active/unknown uploader; bootstrap/epoch baseline/reset/resume with reviewed
  exact tuples. Bootstrap must freeze prospective post-approval N+1 manifest
  semantics; no caller can turn bootstrap into all-empty approval. Prior live
  receipt remains honestly qualified across epochs.
- Reconciler: accepted `open_source_observation(run_id,source_sha,purpose,job_id)`
  then `record_source_observation(challenge_id,evidence)`. DB-issued120s expiry
  never resets; exact config, actor name+OID, run/attempt, source, purpose and job
  binding, immutable redacted evidence and receipt digest. The reviewed
  authenticated provider adapter establishes origin; SQL JSON structure does not.
- Runner: `claim_build`, `heartbeat_build`, `transition_build`, `begin_deploy`,
  `finish_deploy` signatures from the contract. Freeze exact source-receipt
  selection/consumption with those preserved signatures, configuration fields,
  transition evidence and provider observation wire before implementation.
  Claim pins latest desired epoch/generation and admitted source. Duplicate
  run/attempt returns its existing claim; a source-only release is distinct.
  Phase CAS cannot enter deploying/live; deploy needs a fresh purpose=deploy
  observation after any human review wait and current manifest equality.
- Completion/recovery: only the persisted validated ready manifest can become
  live. Authenticate matching provider deployment and production marker against
  stored attempt/job/source/snapshot/artifact; inventory structure/counts and
  identity admission are atomic. Timeout/crash means unknown, never proof of
  unchanged production. `reconcile_job` must establish stopped CI plus terminal
  provider/marker evidence; lease expiry alone never authorizes a new uploader.
- Staff status: fill existing lifecycle fields from actual jobs/receipts, retain
  published-vs-draft distinction and same-epoch verified inventory semantics.
  No secrets/provider errors/machine identity in browser status.

Each capability uses actual session identity and narrowly granted fixed SQL
entrypoints, never direct table/content/member writes or `SET ROLE` impersonation.
Tests must cover disabled/expired/recreated/revoked identities, wrong capability,
forged/expired/changed/reused evidence, config changes, concurrent duplicate claims,
source/generation changes, malformed last-field receipt rollback and unknown
uploader lockout. Successful local fixtures attest implementation behavior only.

## Concrete future hosted plan (not authorized by this document)

1. Freeze all integrated M2 migration bytes/hashes/order and client/adapter
   commits; independently review real-role tests and extend this rehearsal to
   those **exact** migrations. No claim of complete rehearsal before they exist.
2. Read hosted migration history/catalog and exact current synthetic ledger;
   stop unexplained drift. Capture backup/restore evidence, extension versions,
   RLS/ACL/owners/search paths, v1 signatures and preserved-row digests.
3. Apply only reviewed named SQL transactions through supported migration tool;
   inspect generated version/history and stored bytes after every application.
   Older local foundation timestamps are not evidence of hosted application.
   Reconcile generated versions only after byte/order proof, never rewrite SQL
   or mark unapplied migrations complete. Halt on uncertain outcome; no rollback
   to privacy-open behavior and no automatic migration retry.
4. Verify v1/guards unchanged; initial manifest inventories real current content,
   bootstrapfalse/paused/unapproved, no invented live/job receipt. Check public
   view/RLS, helper ACL/owner/search_path, anonymous/staff read boundaries and
   advisor output. No publish/import is required merely to apply foundations.
5. Provision separately reviewed identities/config only after actual custom-role
   TLS/session/pooler identity, reuse/revocation checks; operator is never CI.
   Keep complete baseline review/import and source/provider/protection acceptance
   separate. The three QA publications are not the935-record production baseline.
6. Supervised release uses the same accepted source/claim/fence/receipt path
   intended for automation. No site-live claim until provider/marker verification;
   no unattended dispatch before recovery and cache/withdrawal checks pass.

Hosted changes await the concrete frozen plan and Security/Lead checkpoint.
