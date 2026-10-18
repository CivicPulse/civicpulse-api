# Staff error timestamp correction — local review delta

Lead accepted parent integrated contract section 7 at SHA-256
`c52fceb319082f8c62d38697e302dc87f57e3a9b5b3cb63bc873255265ce7cad`.
This corrects SQL to the existing `PublicationStatus` type, which remains unchanged:
`last_error` is null or exactly `{code,occurred_at}`. No new RPC or browser export.

Additive migration:
`20261018031708_bind_staff_error_acknowledgment_time.sql`

SHA-256: `6f63113d01ab3f3237e0f5d4d6b1c81a3a2b5224c31c33219a4895e55fe0784e`.
Prior migration bytes/provenance are unchanged. The private counter adds
`last_error_occurred_at timestamptz`, with both-null/both-present consistency and
the existing six-code allowlist. No new execute or table grants are added.

## Writer and reader behavior

- `transition_build`: captures the inserted failure transition's
  `acknowledged_at` and stores that exact timestamp with the code.
- `finish_deploy(failed)` and failure `reconcile_job`: capture one database time
  and explicitly use it for both the counter pair and durable acknowledgment.
- `cms_publication_status`: retains staff authorization and all existing keys,
  emits the exact object, and fixes function timezone to UTC so caller session
  timezone cannot change timestamp serialization.
- Saved replays return before writer code. Reads, pause/reset, supersession and
  expired-predeploy recovery do not rewrite or clear the pair. Unknown outcomes
  do not manufacture an error timestamp when no recorded error exists.

Locks, caller identity, intervention, receipt consumption and retry semantics
are unchanged from the independently reviewed core. The correction is local and
still requires independent delta review; no hosted action is implied.

## Upgrade behavior

For an existing nonnull error, backfill considers matching durable failure
transitions at the failed job's current sequence, or failed finish/reconcile
acknowledgments for a failed job. Exactly one matching acknowledgment must exist.
Its original timestamp is retained. Missing or multiple matches raise 55000 and
abort the correction transaction. No now(), arbitrary newest/MAX acknowledgment,
error clearing, or intervention clearing is used to repair history.

Run the migration transactionally, as in the rehearsal. An inconsistent historical
local database requires separate reviewed repair; this migration intentionally
will not guess. The clean hosted four-migration baseline has no delivery errors.
No hosted application is authorized by this document.

## Developer validation

Run database harnesses sequentially because they use common disposable role names:

```sh
npm test
npm run test:db
node scripts/test-delivery-upgrade.mjs
node scripts/test-error-status-upgrade.mjs
```

- Node: 66 passed, no skips/failures (developer environment).
- Full SQL: actual public staff RPC checks for null, every build failure class,
  both deployment failure writers, exact top-level/error keys, timestamp string
  equality to durable acknowledgments, UTC output under Honolulu/Kolkata session
  zones, and read/replay stability. Pair/allowlist constraints reject malformed
  storage. Existing full-state rollback/replay checks now include the new field.
  Actual anon, machine, nonstaff/revoked staff denials remain covered.
- Existing claim/dispatch concurrency and all three deployment races pass.
- Populated upgrade: known four-migration baseline through the new correction;
  warmed publication, data preservation and connected actual-role checks pass.
- Historical upgrade: actual API-produced pre-correction failure backfills to the
  identical original time; missing and deliberately ambiguous historical evidence
  aborts with the old text error intact and no partially added timestamp column.
  Corrupt historical rows exist only in negative disposable fixtures.

Core Security evidence at `bcd213e7` is separate: lead relayed full SQL/upgrade/M1
pass and Node 64 passed/2 pre-existing skips. No claim is made that this correction
has already received independent review. Authenticated provider acquisition,
three-origin artifact checks and sole-uploader behavior remain adapter obligations.
