# Local connected observer fixture

This API-owned external process tests actual migrated PostgreSQL baseline/source
challenge and receipt functions, operator approval, and runner claim through ready.
It grants no provider, hosted, upload or verified-live authority. It uses the current
private signatures in [enrollment/source](enrollment-source-handoff.md) and
[deployment](deployment-control-plan.md); the public v1/M2a interfaces are unchanged.

From a pinned standalone API checkout with locked dependencies and the cached
`docker.io/postgis/postgis:16-3.5` image:

```sh
node scripts/serve-delivery-fixture.mjs --test-only --source-sha FULL_FROZEN_WEB_SHA
```

`--source-sha` accepts exactly one full 40-character lowercase hexadecimal SHA,
after `--test-only`, before startup. Unknown, repeated, reordered or malformed
arguments exit 2 before container creation. It is immutable for the process and
binds source challenge/run/evidence expectations, receipt and claim consistently.
The enrolled config retains its exact existing fields (it has no source SHA key).
The external consumer proves the checkout/archive and build source match; the API
does not read a sibling repo or attest provenance. Omitting the flag uses `f`*40
for a clearly synthetic non-build SQL fixture only.

The driver creates a random, labelled, network-none container/database, waits for
the final postgres PID (not the image's temporary initialization server), applies
local migrations, publishes seven synthetic records through actual staff RPCs,
and uses an actual registered NOLOGIN operator to enroll/bootstrap generation 8.
It shifts only fixture outbox debounce timestamps. It does not seed observations,
claims, approvals of a baseline, or live receipts. Separate containers isolate
cluster-wide role names from all other SQL harnesses. No connection/container/URL
argument or hosted environment configuration is accepted. There are no bind mounts.

## NDJSON v1

Each stdin line is exactly UTF-8 `JSON.stringify({id,command,args})` plus LF;
`args` may be omitted for empty arguments. No duplicate keys, BOM, CRLF or alternate
whitespace encoding. `id` matches `[A-Za-z0-9_-]{1,64}`. Envelope cap is **16,781,312
bytes excluding LF**. Each frame contains at most one JSON-text field of at most
**8,388,608 UTF-8 bytes**: `evidence_json` inbound, `config_json` outbound. All other
context is bounded fixture data. Never put a second aggregate text field in a frame.
Evidence/config are strings, not native-number objects. The driver validates the
aggregate scanner limits then binds evidence text directly to `::jsonb`, without
native parsing/reserialization. JSONB preserves numeric values, not original number
spelling. SQLSTATE errors never include the body or PostgreSQL error message.

Startup emits one ready object:

```text
{type:"ready",schema_version:1,test_only:true,fixture_id,
 url,publishableKey,config_json,dataset_epoch,manifest,
 expected:{ids,counts,generation:"8",sentinels},
 inputs:{run_id:"9007199254740993:1",source_sha:selected startup SHA,
 baseline:{deployment_id:"fixture-deployment",source_sha,artifact_sha256,served_inventory_sha256}}}
```

Counts: organization 1, calendar 1, event 2 (one canonical private event), layer 2
(stored two features, event-derived one feature), map 1. This is fixture A content;
this driver has no advance/withdraw operation. The separate M1 fixture owns A/B.

Success: `{type:"result",id,command,result}`. Error:
`{type:"error",id:string|null,code}`. Startup errors additionally expose only
`phase` and `sqlstate`; cleanup failure is `fixture_cleanup_failed`.

| command | exact args | actual session / result |
|---|---|---|
| openBaseline | `{}` | reconciler; baseline challenge for fixed deployment |
| recordBaseline | `{challenge_id,evidence_json}` | reconciler; actual provider receipt |
| approveBaseline | `{observation_id}` | operator; approval and resume in one transaction; `{baseline,pipeline}` |
| openSource | `{}` | reconciler; claim-purpose challenge for fixed run/SHA |
| recordSource | `{challenge_id,evidence_json}` | reconciler; actual source receipt |
| claim | `{}` | runner; BuildClaim or null |
| heartbeat | `{}` | runner; current claimed tuple heartbeat |
| transition | `{expected_state,state,evidence}` | runner; actual transition result; stage-specific evidence below |
| inspect | `{}` | read-only manifest/job summary, receipt counts, precision control, external/live booleans, prior call ledger |
| close | `{}` | removes only this labelled container/volumes; `{closed:true}` |

Challenge results preserve existing fields except replacing `config` with
`config_json` (SQL JSONB text). The database binds config/epoch internally; do not
invent a dataset_epoch challenge property. Ready supplies current epoch. Challenges
expire after 120 DB seconds. The role registry expires after one hour. No producer
receipt is extended by this harness.

Transitions: queued->exporting `{}`; exporting->building
`{publication_manifest,snapshot_sha256}`; building->validating `{artifact_sha256}`;
validating->ready `{}`. Failure evidence remains the documented exact SQL contract.
The driver gets the claimed tuple read-only and submits it under actual runner
session identity. No per-command source override and no caller-selected SQL, role, run, job or deploy operation.

SQL errors include `22023` malformed evidence, `40001` stale/mismatch and `55000`
closed gate; capability denial remains `42501`. Invalid envelopes/commands use
`invalid_fixture_command`; underlying aggregate scan rejection is redacted
`invalid_github_run_identity`. Podman failures are `fixture_sql_error`.

At most 256 successful command IDs are cached in this process. An identical
serialized request ID returns the saved result without another SQL call; altered
reuse rejects. Errors are not success acknowledgments. `inspect.calls` is a bounded
read-only command ledger, with sequence/id/command/outcome/code, no evidence or
credentials. Its snapshot excludes the current inspect itself. Reusing an inspect
ID returns its old snapshot. This is test IPC replay, not a production retry policy.
An unknown process exit loses this cache: discard the fixture; do not attach/retry
against another database. EOF/signals request cleanup. A timeout is not proof that
an operation failed; inspect the same running fixture before further action.

## Public reads and consumer sequence

`url` is loopback only; `publishableKey` is a non-secret test literal. The existing
client can perform publicationManifest/listPublished/layerGeoJSON calls with its
unchanged request shape. Routes execute actual anon SQL projections and return
PostgreSQL JSON with cache-control no-store. They are not PostgREST/Auth emulation;
there is no HTTP mutation/control endpoint. See [M1 fixture](publication-fixture-handoff.md).

Web launches this process externally, acquires baseline/source fixture HTTP bodies
through its own fixed-endpoint adapter, sends exact evidence text to open/record,
approves/resumes, claims, heartbeats, reads A/pages/B and builds before submitting
its actual snapshot/artifact digests through transitions. API's own regression uses
synthetic digests and does not prove a Web build. No Web checkout or sibling import
is required by this driver. No deploy/begin/finish/grants RPC is exposed.

Run `node scripts/test-delivery-fixture.mjs` for the actual SQL connected regression.
It covers rejected evidence/no receipt, exact large actor/ruleset identity and
high-precision/underflow JSONB value preservation, replay, seven-record public reads,
ready without live authority, and at/over 8MiB escaped text transport. Existing SQL
role/ACL/concurrency suites remain separate; this harness does not replace them.

Final developer regression: config 179 lexical tokens / 1859 UTF-8 bytes;
assembled source evidence 668 tokens / 4680 bytes. Both actual receipts were
consumed (baseline by operator, source by claim), job reached ready, generation
remained 8, external_authority=false and live_inventory_complete=false. These
counts describe this synthetic fixture, not production policy coverage.
