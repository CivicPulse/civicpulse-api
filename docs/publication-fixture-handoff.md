# M1 disposable SQL → HTTP fixture

Test-only external process; no sibling imports are needed by Web. Start from a
pinned clean API checkout with Node 22.12+ and the existing documented local
`civicpulse-api-db-test` Podman container (PostGIS16-3.5, network `none`):

```sh
node scripts/serve-publication-fixture.mjs
```

The script resolves migrations relative to its own checkout. It creates a fresh
`civicpulse_m1_<random UUID hex>` database, applies all local migrations, and
publishes fixture content through actual `public.save_draft` / `public.publish`
under `SET SESSION AUTHORIZATION authenticated` and a fixture admin claim. The
minimal test Auth schema is not the hosted Auth service. No database URL,
credentials, dotenv, hosted configuration or container override is accepted.
The fixed container image/network are checked before database creation. No real
login is provisioned. Owner-only `bootstrap_complete=true` is explicitly fixture
setup, not bootstrap approval, source admission, verified receipt or job authority.

## Wire version 1

stdout is NDJSON, stderr is not a protocol. First successful line:

```json
{"type":"ready","schema_version":1,"fixture_id":"civicpulse_m1_<hex>","url":"http://127.0.0.1:<ephemeral>","publishableKey":"local-m1-fixture-only","test_only":true,"owner_bootstrap_fixture":true,"manifest":{},"expected":{"ids":{},"countsA":{"organization":1,"calendar":1,"event":2,"layer":2,"map":1},"countsB":{"organization":1,"calendar":1,"event":1,"layer":1,"map":0},"generationA":"7","generationB":"10","sentinels":{}}}
```

`manifest` is the complete actual public RPC result, including fresh epoch.
`ids` contains organization, calendar, event, privateEvent, layer, derived, map.
`sentinels` contains event/layer/feature/map unique strings to search in output
and embedded assets. Feature names append `0`/`1` to the feature sentinel.
These expected counts/IDs are independent fixture expectations, not invented
manifest records. Both event categories/source metadata pass the actual guards.
The retained private event has canonical placeholders and no coordinates.

stdin accepts UTF-8 NDJSON objects with exactly `id` and `command`. `id` matches
`[A-Za-z0-9_-]{1,64}`; command is `advanceB` or `close`. Each line is at most4096
bytes. Malformed/unsupported commands return an error without mutation. An
overlong unterminated line terminates/cleans up the fixture. No other IPC actions
are implemented; no HTTP control route exists.

```json
{"id":"step-b","command":"advanceB"}
{"type":"result","id":"step-b","command":"advanceB","stage":"B","manifest":{},"receipts":[{"kind":"event","id":"m1-withdraw-event","revision":"1","action":"withdraw","sequence":"15"}]}
{"id":"finish","command":"close"}
{"type":"result","id":"finish","command":"close","closed":true}
```

The abbreviated receipts example shows shape, not the full array. B atomically
withdraws event1, map1, layer1 in dependency-safe order. It stores the actual
result manifest and three actual history receipts in a private fixture table
in the same transaction. Revision/sequence/generation are decimal strings.
Repeated `advanceB` (including a lost-response retry) returns that persisted B
result without another write. Request IDs correlate replies, not authority.
The process does not attach/resume across restarts: a new process is a new DB,
epoch and fixture. Never reuse A artifacts against a restarted fixture.

Errors are `{type:"error",id:<valid request id or null>,code:<redacted code>}`.
Codes: `invalid_fixture_command`, `fixture_line_too_large`, SQLSTATE or
`fixture_sql_error`, `fixture_start_failed`, `fixture_cleanup_failed`. Startup
errors additionally report `phase` and nullable `sqlstate`, never SQL/body/secrets.
Startup/cleanup failures exit nonzero. EOF/SIGINT/SIGTERM/close close the server
and drop only the process-owned database; normal close exits0. SIGKILL/host loss
can leave an orphan: inspect the exact ready fixture_id before operator cleanup;
there is no wildcard cleanup/restart recovery. Never target the hosted QA IDs.

## HTTP surface and limitations

Bind is IPv4 loopback only. Supply the ready marker as `apikey`; it is a public
test routing marker, **not authentication**. No CORS/browser exposure is intended.
Use the existing M2a client unchanged:

- `publicationManifest()` → POST `/rest/v1/rpc/publication_manifest`, `{}`.
- `listPublished(kind?, {limit,offset})` → GET `/rest/v1/content` with exact
  `select=*`, `order=kind.asc,id.asc`, optional supported `kind=eq.<kind>`.
- `layerGeoJSON(id,{limit,offset})` → POST `/rest/v1/rpc/layer_geojson` with
  `p_layer_id`, optional `p_limit` and `p_offset`. Spatial bounds are unsupported
  in this integration fixture, not removed from v1.

Every read uses real anonymous session authorization and public SQL functions or
the real `public.content` view, C-ordered pagination, and PostgreSQL JSON bytes
directly. HTTP200 includes `Cache-Control: no-store, max-age=0`. JSON generation/
revision strings are never converted through Number. Removed layer RPC returns
404/P0002; other rejected requests400, missing marker403, unsupported route404.
Bodies are bounded4096 bytes. SQL inputs are exact allowlisted shapes, bounded
integers or escaped literals; no arbitrary query input is accepted.

This is a **thin test transport**, not PostgREST, JWT authentication, connection
pooler, provider, dispatcher, runner, uploader or verified-live implementation.
It proves the actual migrated PostgreSQL projections/publication boundary. The
existing disposable role/ACL/privacy/source-URL suites remain separate required
evidence; this adapter cannot substitute for hosted Auth/PostgREST QA.

## Verification

```sh
node scripts/test-publication-fixture.mjs
npm run test:db
```

The focused test uses the real API client over HTTP, checks complete A/B tuples,
two-page stored geometry, derived geometry1→0, exact withdrawn receipts, retained
private event, missing layer, mutation-route denial and idempotent B. Web owns
export/pinned-reader/materializer/Astro integration and artifact sentinel checks.
No synthetic transport outcome may be called a deployment receipt or live status.
