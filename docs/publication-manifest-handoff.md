# Local additive manifest handoff (M2)

**Local-only implementation. Hosted Supabase still serves frozen v1 and does not
have this RPC.** Security review and rollout approval precede any hosted migration.
Architecture baseline: web ADR `539792bd9aef5eca165800cfcc14436bd3ef7e65`, with
subsequent architect-owned maintenance/privacy clarifications. This increment
contains no runner grants, bootstrap approvals, or deployment controls yet.

## Call and exact shape

`POST /rest/v1/rpc/publication_manifest`, JSON body `{}`, publishable key in
`apikey`; no staff session required. `api.publicationManifest()` in `src/client.mjs`
is the matching helper. `src/database.types.ts` adds `publication_manifest` with
`Args: never; Returns: Json`; this local SQL signature was checked in disposable
Postgres and is not a newly generated hosted schema. The explicit structural
interface is `PublicationManifest` in `src/publication.types.ts`.

```json
{
  "schema_version": 1,
  "dataset_epoch": "UUID",
  "generation": "0",
  "bootstrap_complete": false,
  "counts": {"organization":0,"calendar":0,"event":0,"layer":0,"map":0},
  "records": [],
  "layers": []
}
```

Every record is `{kind,id,revision}`; every layer is
`{id,revision,mode,feature_count}`, with `mode: "stored" | "events"`.
Generation and revisions are decimal **strings**; counts are nonnegative JSON
integers. Records are sorted `(kind COLLATE "C", id COLLATE "C")`; layers by
`id COLLATE "C"`. The manifest is exhaustive, returned as one JSON value, not a
paged rowset; the 1,000-row REST cap must not truncate it. Object-key order is not
significant. Validate and compare the full normalized manifest, not raw JSON text.

Stored counts match the exact published feature rows. Event-derived count matches
published event feature rows, before venue grouping. The v1 publisher only creates
those for a coordinate array, rejects private/virtual coordinates, and validates
longitude/latitude bounds. Private validation is being tightened in a separate
security-reviewed increment; never infer map eligibility from coordinates alone
in Web-Dev's adapter.

All five zero counts, an empty record inventory, and a published zero-feature
layer are represented explicitly. Missing fields or unexpected missing rows are
not successful empties. Fresh epoch/generation 0 has bootstrap false. **False
always blocks production activation**, even after valid records are published.
Operator-reviewed bootstrap comes in a later local increment; it is not a CMS flag.
Withdraw creates a durable private tombstone and removes the record from the
next public inventory. Public manifest does not expose withdrawn IDs or job state.

## Consistency and cache boundary

The manifest is a `STABLE` SQL function whose complete JSON value is assembled by
one SQL statement/snapshot. A transactional singleton UPDATE increments generation
and appends a logged outbox row under the existing catalog lock, in the same
transaction as v1 publication/history. Saves do not advance it; failures roll back
content, counter, and intent together. V1 republish changes `published_at`, so it
advances generation even for the same draft revision. There is no timestamp noise
in the manifest itself. Epoch resets are operator-owned, not implemented here.

The function sets the PostgREST response header `Cache-Control: no-store,
max-age=0`; the Fetch helper now passes `cache: 'no-store'` on all requests. Web's
own Supabase/fetch adapter must similarly bypass caches for **all** A/page/B reads.
Use the authoritative primary project REST endpoint, not a read-replica URL or
caching proxy. The function guarantees a database statement snapshot; it cannot
prove that a consumer used the primary, disable an external misconfigured cache,
or make multiple REST calls one transaction. HTTP header propagation is not yet
tested against a local PostgREST service; its SQL response-header value is tested.

Read A, validate/bootstrap-check it, fetch every expected page/feature, then read B.
Require equal full inventory/counts/epoch/generation and discard the entire candidate
on mismatch. Compare decimal strings as counters without converting to JS Number.
Do not mix partial retry results. Stage and activate immutable snapshot directories
under the architect's consumer contract.

## Existing page and feature calls (unchanged v1)

- Records: `GET /content?select=*&order=kind.asc,id.asc&limit=100&offset=0`.
  Add `kind=eq.event` (or another kind) when fetching by kind; still validate total
  tuple membership/count against A. Increment offset explicitly. Payload ID must
  match row ID. V1 row `revision` is still a JSON number: require a safe positive
  integer before converting to decimal text; fail closed if unsafe. No v1 signature
  was changed to solve this future range limitation.
- Query ordering is deterministic database text ordering for fixed data; canonical
  manifest sorting uses explicit C collation. Validate tuple membership separately;
  do not assume the database's locale sort exactly matches canonical array indices.
- Layers: `POST /rpc/layer_geojson` body
  `{ "p_layer_id":"ID", "p_limit":500, "p_offset":0 }`, no viewport bounds.
  Response `{type:"FeatureCollection",features:[...],nextOffset:number|null}`.
  Follow the exact integer offset; require advancement and final explicit null.
  SQL orders stored features by `(id,ordinal)`. Page-position ordinal is the export
  identity; source feature IDs may repeat. Empty layer: `features:[],nextOffset:null`.
  Verify the final count equals the manifest. Missing cursor is an error.
- For event-locations, derive from the same captured, validated event records;
  compare eligible-event count before the web grouping transformation.

## Vendor snapshot and validation

`node scripts/export-web-client.mjs OUTPUT_DIRECTORY` exports four files:
`client.mjs`, `database.types.ts`, `publication.types.ts`, and `manifest.json` with
hashes and contract label `civicpulse-content-api-v1+publication-v1-local`.
Vendor all four from the exact API commit provided with the handoff; do not infer
hosted availability from generated/structural types. Existing frozen v1 vendor
may stay pinned until Web-Dev deliberately adopts the additive local interface.

Disposable tests cover fresh zeros, bootstrap gating, permission isolation,
rollback/outbox failure atomicity, publish/republication/withdraw generations,
tombstones, stored/event zero-feature layers, exhaustive inventory >1,000 rows,
and decimal precision beyond JS safe integers. V1 permission/geometry tests still
pass. No production API call or content write is part of these tests.
