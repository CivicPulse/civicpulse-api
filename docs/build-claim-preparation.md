# Local M2.2 claim preparation

Historical preparation checkpoint `5dff551`. The connected transition/failure
implementation now follows [the M2.2 handoff](build-control-handoff.md); the
unfinished list below records the scope of this earlier checkpoint.

Depends on frozen M2.1 `b7639f78a766c79d9442815584f1e26f98ace338` and its
[private wire and trust boundary](enrollment-source-handoff.md). This is a scoped
claim/heartbeat preparation checkpoint, **not complete M2.2 or a deploy gate**.
No hosted migration, provisioned role, browser export or provider call is added.

## Implemented private SQL

- `claim_build(p_run_id text,p_source_sha text)` returns JSON null or
  `{job_id,lease_id,fence,dataset_epoch,target_generation,lease_expires_at}`.
  Fence and generation are decimal strings. Requires actual registered runner
  name/OID, eligible current config/bootstrap/baseline, and an actual fresh
  reconciler receipt from M2.1. Chooses newest eligible issued_at/challenge UUID,
  consumes once, and pins immutable source/config/epoch/generation. One partial
  unique index plus the shared catalog lock permits one active job. Exact active
  same-owner replay returns its existing lease without consuming another receipt.
  Changed desired generation returns40001 without retargeting. No-work null
  requires complete same-epoch exact generation/source verified live; no writer
  for that live state exists in this increment.
- `heartbeat_build(p_job_id uuid,p_lease_id uuid,p_fence bigint)` returns
  `{lease_expires_at}`. It verifies actual runner identity, active ownership,
  exact lease/fence and exclusive expiry before extending by five DB minutes.
  Caller cadence remains one minute. Heartbeat does not change job identity.

All functions have empty search_path and explicit PUBLIC/anon/authenticated
EXECUTE revokes; no real runner grants are installed. Tables use RLS and no
direct machine writes. Fence exhaustion fails55000; epoch reset never resets
the separate monotonic counter. An active job, including an expired one, prevents
reset/enrollment. There is no automatic expired-lease takeover.

The claim coalescer uses current-epoch publish/withdraw events after verified live
generation (zero if no verified current baseline), due at the earlier of newest
event+30seconds and oldest event+120seconds. Bootstrap events do not debounce.
Source receipts retain their original120second deadline throughout this work.
SQL source evidence remains a trusted reconciler projection, not provider proof.

## Validation and unfinished pieces

Developer `npm run test:db` passed, including actual M2.1 operator/reconciler
calls producing the approval and receipt used by actual runner claims. Added
checks cover claim insertion fault rollback (fence/receipt/job), wrong capability,
wrong fence, revoked owner, lease expiry/no takeover, actual publication after
claim without retargeting, and exact replay. Two backend sessions compete:
one job/consumed receipt, one ownership conflict; concurrent same-owner retries
return the exact original claim. Existing dispatch concurrency remains separate.
Concurrency setup uses actual M2.1 functions, never owner-seeded approvals.
`node scripts/test-delivery-upgrade.mjs` also passed the populated v1 upgrade
plus the connected claim/heartbeat scenario.

No transition_build, retry scheduling, predeploy reclaim, staff job projection,
begin/finish/reconcile or verified receipt writer exists yet. No terminal run
identity reuse is allowed. Lead-routed disposition is pending for exact stage
failure classification/intervention and terminal retry identity. Named failure
codes cannot currently distinguish transport errors from privacy/schema failure;
no automatic retry policy is invented here. Final M2.2 freeze must include that
disposition, phase/manifest immutability, debounce boundaries and further
role/catalog/rollback tests. Web adapter→SQL integration remains required.
