# Local M2.1 enrollment and source handoff

Local implementation of parent integrated contract SHA256
`6f0208e4fdd7b30b9510ce0063bcf8bee19529b9acd739be3fc81968e7d82831`.
The migration is `20261018010946_delivery_enrollment_source.sql`. Public v1,
M2a manifest and browser vendors are unchanged. No hosted migration, real login,
credential, provider request, job, upload or live-receipt writer is included.

Migration SHA256: `08d5f12fbdb537eb3124dbed3936d9a12513bf68d9cc8290154646476fde3e19`.
The parent document subsequently read during freeze has SHA256
`16d36c322fe1f80aff6dc24ee4603fcb3f899117a2055af176ac59ef1a3d4727`;
the assigned scope and lead-confirmed SQL/adapter trust split above remain the
implementation boundary, not an assertion of independent review of this code.

## Calling boundary

All new functions are private SQL in `civicpulse_delivery`; call through a
separately reviewed TLS database connection, **not** browser PostgREST. There are
no production machine EXECUTE/CONNECT grants in the migration. Disposable tests
use distinct NOLOGIN roles and actual `SET SESSION AUTHORIZATION` to exercise
session_user name/OID, including SECURITY DEFINER calls. Inherited SET ROLE
cannot impersonate a registered identity.

| Capability | Explicit future entrypoint EXECUTE allowlist |
| --- | --- |
| publication_operator | `enroll_delivery_config(uuid,jsonb,text)`, `approve_bootstrap(uuid,bigint,jsonb,text)`, `reset_epoch(uuid,uuid,text)`, `approve_epoch_baseline(uuid,text,jsonb,text)`, `set_pipeline_paused(boolean,text)` |
| reconciler | `open_source_observation(text,text,text,uuid)`, `record_source_observation(uuid,jsonb)`, `open_provider_observation(text,uuid,uuid,text)`, `record_provider_observation(uuid,jsonb)` |
| runner / dispatcher / staff / anon / PUBLIC | None of the above |

No helper/table privileges accompany those grants. Every entrypoint checks current
capability, name+OID and expiry, takes catalog lock728361904 then pipeline/
enrollment rows, and rechecks identity after locking. Registry share locks prevent
an in-flight identity change. Definers have empty search_path and UTC timezone;
helpers are private invokers. Roles, evidence and approvals remain private.

## Operator sequence

1. `enroll_delivery_config(null, config, review_reference)` returns
   `{config_version,approved_at}`; later enrollment CASes exact prior UUID.
   Use the exact parent config shape. New versions are immutable; rotation
   invalidates baseline authorization and old receipt context. SQL validates the
   policy representation, not whether remote protection/environment exists.
2. Read real `public.publication_manifest()` and review the complete prestate.
   `approve_bootstrap(epoch, generation, prestate, review_reference)` requires
   paused/nonempty/bootstrapfalse. It validates and atomically commits the
   mechanical N+1/true target, one outbox event and full private prestate/target
   audit. Internal target digest is SHA256 of UTF8 PostgreSQL JSONB text, encoding
   `pg-jsonb-text-v1`, not the snapshot/artifact hash. Actual postmanifest must
   equal the target. int8max fails55000 before addition; duplicate old-prestate
   call fails40001 and cannot append another event.
3. Reconciler obtains the first markerless baseline receipt below. Operator
   reviews its retained artifact and invokes
   `approve_epoch_baseline(epoch,deployment_id,{observation_id},review_reference)`.
   Return `{approved_epoch,previous_live_deployment_id}`. Receipt is consumed once
   and binds epoch/config/deployment/recovery digests. No CMS live tuple is made up.
4. `set_pipeline_paused(false,review_reference)` succeeds only with active config,
   bootstrap and approved current baseline, without outstanding authority/anomaly.
   This enables source observations only: job/claim/deploy functions do not exist.

`reset_epoch(old,new,review_reference)` requires paused/quiescent, a distinct
never-used UUID, preserves qualified live/history, resets generation0/bootstrap
false and invalidates baseline/source context. After any baseline approval,
first-markerless enrollment cannot be reused after reset/config rotation;
rebaseline is intentionally55000 pending later reviewed recovery implementation.
Review references are1–512 printable ASCII. No reference is fetched/interpreted.

## Reconciler adapter wire

Use SQL arguments in the exact order below, with bound parameters in the actual
consumer. The public browser client is deliberately not extended.

Private structural declarations are `src/server/delivery-enrollment.types.ts`.
They do not perform runtime validation or provide provider origin proof. Existing
server-tooling bundle pins are unchanged; do not silently replace their inventory
to include this new file. A coordinated consumer handoff must pin the new source
commit/bytes separately when Web uses these declarations.

```text
open_source_observation(run_id,source_sha,purpose,job_id)
 -> {challenge_id,config_version,issued_at,expires_at,run_id,source_sha,purpose,job_id,config}
record_source_observation(challenge_id,evidence)
 -> {observation_id,challenge_id,config_version,source_sha,received_at,expires_at,evidence_sha256}

open_provider_observation(purpose,job_id,attempt_id,deployment_id)
 -> {challenge_id,config_version,purpose,job_id,attempt_id,deployment_id,issued_at,expires_at,config}
record_provider_observation(challenge_id,evidence)
 -> {observation_id,challenge_id,config_version,received_at,expires_at,evidence_sha256}
```

Source accepts claim/null job only. Provider accepts baseline/null job+attempt and
explicit deployment ID only. Well-formed source deploy and provider predeploy/
outcome/terminal return55000; no future job is simulated. Invalid purpose22023.
Run ID is canonical `ID:ATTEMPT`,20/10 digits; no JS Number conversion. UUIDs,
lowercase SHA strings, complete exact source/provider evidence keys and path-v2
profile match the parent contract. Request IDs are null or1–256 printable ASCII;
deployment IDs use the conservative1–128 ASCII alphanumeric/underscore/hyphen
opaque identifier subset. These bounds must be checked before external rollout.

The adapter must acquire all evidence **after** opening the challenge. DB expiry
is issued_at+120seconds and exclusive; recording/replay never renews it. Record
checks same caller identity, immutable active config and epoch, exact context and
complete evidence. Saved exact replay retains original IDs/times/hash; changed,
consumed, stale or expired receipts reject. Disabled/expired/recreated producers
also cannot have receipts consumed by the operator.

Errors:42501 authorization;22023 malformed representation;40001 stale/mismatching
context or replay;55000 missing operational gates/unsupported future capability.
The database stores full evidence plus SHA256 UTF8 JSONB text and the encoding
label; adapters must not compare this to JavaScript canonical snapshot hashes.

## Baseline trust split

Baseline requires active config, paused pipeline, bootstrap and no prior baseline
approval/verified-live/active authority. Exact project/deployment must be successful
production/main; all three markers are explicitly null with actual marker404
audit entries, complete project-before/after/deployment/artifact audit entries,
non-null complete artifact/served digests, and null GitHub terminal facts.

**SQL cannot detect fabricated hashes from an otherwise authorized reconciler.**
The exact section5 wire has no extra per-origin inventory field. Lead accepted
that SQL checks the submitted projection while Web's actual adapter must reject
missing/transformed/incomplete bytes **before record** and retain the complete
private raw recovery inventory, routes/control mapping, encoding and per-origin
evidence sidecar bound to the submitted digests. No new evidence keys or bypass
RPC were invented. SQL tests prove rejection of missing audit/artifact/marker
fields and invalid bindings, not actual origin authenticity or byte comparison.

Hosted baseline remains blocked on measured all-origin recovery evidence and
the custom-domain Email Protection transformation policy. A local synthetic
receipt is not production approval. Live inventory stays incomplete and website
status unknown after baseline/source success.

## Reproduction and remaining integration

`npm run test:db` executes actual config→N+1 bootstrap→baseline observation→
operator consumption→resume→source observation and receipt, plus actual-role
negatives, atomic injected audit/outbox/postmanifest failures, max-generation
controls, immutable replay/config/epoch expiry and identity revocation/recreation.
It also runs existing publication/privacy/URL/status/dispatch/receipt suites.

Developer checks at this freeze all exited0:

- `npm test`:66 tests passed.
- `npm run test:db`: connected actual-role scenario, full owner/search_path/
  definer/client-ACL catalog, private-table RLS/direct-write checks, baseline
  expiry/partial-origin-audit negatives, and prior suites including two-backend
  dispatch concurrency passed.
- `node scripts/test-delivery-upgrade.mjs`: populated upgrade and connected
  scenario passed with the exact migration hash above.
- `node scripts/test-publication-fixture.mjs`: unchanged M1 actual SQL/HTTP
  A7→B4/generation7→10, pagination/empty-layer/withdrawal/idempotency passed with
  the additive migration installed.
- `git diff --check`: passed.

These are developer results. Frozen independent Security review remains required.

`node scripts/test-delivery-upgrade.mjs` applies the exact hosted four-migration
baseline, synthetic populated state, explicit four foundations plus M2.1, verifies
unchanged original rows/warmed v1 behavior, then runs the connected scenario in a
rolled-back synthetic transaction. No hosted history/version assertion is implied.

Web owns authenticated source/baseline acquisition and its injected upstream
transport tests. The next cross-repo test must submit that adapter's actual
projection into these real SQL functions, with zero record calls on failed
acquisition; constructed SQL evidence alone does not close that integration.
Source-only jobs, receipt consumption by claims, build/deploy fences and actual
live writes remain M2.2/M2.3, not inferred from this checkpoint.
