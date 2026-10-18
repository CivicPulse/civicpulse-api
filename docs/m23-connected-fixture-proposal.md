# M2.3 connected fixture interface

API-owned test-only interface accepted through lead for parent handoff4a526592.
Frozen implementation still requires independent review before Web consumption. Existing ready-only NDJSONv1 commands and
bundle83 stay unchanged until a separately reviewed new export. No provider or
hosted authority. All calls below use existing private SQL signatures/roles.

## Immutable startup scenario

Keep current ordered --test-only --source-sha SHA1 --workflow-file-sha256 HASH.
Optional final --next-source-sha SHA2 enables exactly two slots. SHA2 must be full
lower40hex, distinct fromSHA1, and uses the SAME fixed validate.yml digest/config.
No caller run/role/config/URL/SQL flag. Slots use fixed canonical run identities
9007199254740993:1 and9007199254740993:2 (different attempts). Candidate real sources
through lead: b64b89da245fbe885ff795ae9b6b030352635337 then
7548bd1b518dc0aa47dc8e05c8474a131ff9429a; Web proves both archives/workflow equality.
Ready adds scenarios:[{index:0,run_id,source_sha},{index:1,run_id,source_sha}] only
when second slot supplied. Existing inputs describe slot0. No per-command retarget.

## Exact additional command/args choices

Same {id,command,args}, bounds/errors as existing driver. Existing recordSource
handles claim or deploy challenges, with untouched evidence_json text binding.
Provider record likewise uses ONE aggregate text field; all IDs boundedUUID or
provider deployment ID matching ^[A-Za-z0-9_-]{1,128}$, never interpolated SQL.

| command | exact args | actual guarded operation/result |
| --- | --- | --- |
| openDeploySource | {} | reconciler open_source_observation fixed active run/source, deploy,current job; challenge/config_json |
| openPredeploy | {} | reconciler open_provider_observation predeploy,current job,null, prior deployment read from immutable baseline/live binding |
| openOutcome | {deployment_id:string|null} | reconciler outcome,current job,current attempt, bounded candidate; challenge/config_json |
| openTerminal | {deployment_id:string|null} | reconciler terminal,current job,current attempt or null; challenge/config_json |
| recordProvider | {challenge_id,evidence_json} | reconciler record_provider_observation; exact receipt |
| begin | {} | runner begin_deploy current persisted job/lease/fence/epoch/gen/snapshot/artifact/source; exact BeginDeployResult |
| finish | {outcome,deployment_id,observation_id} | runner for unknown, reconciler for live/failed, current attempt/fence; unknown requires observation_id null; live/failed requires UUID and nonnull deploymentID; builds existing observation object only |
| reconcile | {observation_id} | reconciler current job/fence; exact ReconcileJobResult |
| advanceSource | {} | driver slot0->1 ONLY after actual successful terminal reconcile released authority, no intervention and no active job; no SQL writer; returns {index:1,run_id,source_sha}; repeated calls return same slot1 |

No command writes receipt/live rows directly. Driver reads persisted tuples and
uses actual registered session identity, existing immutable prior bindings and
existing SQL gates; ordinary SQLSTATE errors retained. Malformed args reject before
SQL. Full current driver cleanup/randomcontainer/networknone/read-onlyHTTP rules
remain. Provider ID transport binding is not provider authentication.

Inspect adds bounded delivery object:
{source_index,attempt:{attempt_id,job_id,fence,state,deployment_id}|null,
 active_job:string|null,external_authority:boolean,intervention_required:boolean,
 live:{dataset_epoch,generation,source_sha,deployment_id,inventory_complete},
 observations:[{observation_id,purpose,consumed:boolean}]}
All counters/revisions/fences/generations decimal strings; no raw evidence/errors,
role secrets or credentials. Exact state column mapping verified during code;
no invented production wire. Existing inspect fields remain unchanged.

## Acknowledgment and one-submission boundary

Unlike ordinary successful IPC caching, begin MUST NEVER replay authorized:true.
Exclude begin from successful reply cache: repeated ID returns a redacted
begin_ack_not_replayable error without SQL; different ID reaches existing SQL and
must fail40001 after first begin. Mark seen ID before invocation, so uncertain SQL
outcome cannot reopen it. Driver never uploads. Inspect exposes persisted attempt
for read-only reconciliation; timeout/lost ack does not authorize caller action.

Web owns an attempt-bound durable private journal and one-submission counter for
its direct fixedREST multipart transport: persist invocation intent before sending;
never replay after caller/process/IPC ambiguity, even if response is lost. Driver
process-memory cache is NOT durable upload protection. Whole fixture process loss
ends the disposable scenario; do not reconnect a new fixture and call it recovery.
Tests must include duplicate/lostbegin responses, timeoutafteraccept, journal reload
and zero second submission. Direct REST redirect:error/no retry/authrefresh agreed;
full Wrangler deploy is excluded. No production provider invocation in this batch.

## Public terminal projection choice

New server-only export `civicpulse-source-tooling-local/terminal-run`:
`decodeGitHubTerminalRun(rawJson): TerminalRun` and
`assertGitHubTerminalRun(actual, target: RunTargetV2, pathPolicy: WorkflowPathPolicyV2, endpoint:'run'|'attempt'): void`.
TerminalRun exact existing eleven-field private type; no endpoint/schema field
added to SQL shape. Decoder uses existing raw bounded lossless parser ONCE, five
canonical decimal IDs, raw path unchanged, main/lower40SHA/allowed event,
status completed, own-present conclusion from existing nine-value allowlist.
Comparator validates exact own data descriptors first, existing path-v2 next,
then exact target IDs/event and expected-only same-repo rule. Redacted errors:
invalid_github_terminal_run and github_terminal_run_mismatch. No change to legacy
or in-progress APIs, no public parser override, new dependency or native numeric
parse. Raw limits1MiB/depth64/32768tokens/string65536 unchanged. Terminal output
contains only strings and is safe to stringify into existing evidence; full unknown
provider policy remains lossless JSON text, never mixed into this projection.

Package exporter includes complete transitive modules/types/tests/license and new
external manifest/verifier/source pins only after implementation freeze. Bundle83
remains immutable and usable for prior source/build consumer. New bundle tests must
exercise completed run+attempt assembly through actual provider SQL, not helper-only
success. Current candidate design is not provider freshness/origin proof.

## Reproducible connected lane

Run `node scripts/test-delivery-fixture.mjs --m23` from a clean API checkout with
local Podman available. It creates its own network-none disposable database,
performs the existing config/bootstrap setup and actual registered-role calls,
and closes/removes its exact fixture container. No hosted environment or provider
credentials are used. `node scripts/test-delivery-fixture.mjs` retains the prior
ready-only lane. Tests construct synthetic provider evidence; they do not build
Web or authenticate upstream origin. Web owns actual archive/workflow validation,
HTTP acquisition fixtures, artifact construction and durable uploader journal.

External consumer launch (stdin/stdout are canonical NDJSON, no shell control):

```sh
node scripts/serve-delivery-fixture.mjs --test-only \
  --source-sha b64b89da245fbe885ff795ae9b6b030352635337 \
  --workflow-file-sha256 25eee8bfbea0cfa733ecbb0a14b3f922faecece553e508968e55a7038512bc25 \
  --next-source-sha 7548bd1b518dc0aa47dc8e05c8474a131ff9429a
```

Both source archives contain the same fixed workflow3927bytes. The driver checks
only startup grammar and immutable binding, not source authenticity. Existing
[observer fixture](delivery-observer-fixture.md) documents full ready/error/close,
16,781,312-byte encoded frame and one8MiB text field limits. No production SQL
signature, migration, browser vendor or bundle83 bytes change in this increment.

## Developer verification at implementation freeze

`npm test`:82/82 passed on local Node26.11.1 (including seven terminal cases and
17 package inventory/adversarial checks). `node scripts/test-delivery-fixture.mjs
--m23`:exit0 against actual isolated SQL; two immutable source slots, real
baseline/source/deploy/provider receipts, begin replay denial, unknown-outcome
lock retention, partial evidence audit-only/no consumption, malformed-schema
rollback, live finish and terminal reconciliation, source-only second claim.
The terminal helper's decoded completed run is submitted through actual provider
recording and reconciliation. No uploader or external provider was invoked.
The base ready-only flow remains covered as the prefix of this connected lane.

Earlier test expectation treated a changed marker as schema rejection; actual SQL
correctly recorded it as partial evidence. The final test asserts its receipt
cannot finish live or be consumed, separately from malformed-schema rejection.
Standalone exported package checks and external pins are recorded separately after
committing the exact source; this developer report is not independent review.
