# Reviewed import preparation

Production content import is **not authorized yet**. All preparation below reads
source data and writes only local, derived artifacts or a disposable test database.
The importer remains draft-only even when an eventual `--apply` is authorized.

## Two elementary-zone repairs

The original layer's publication stopped at its first invalid feature. Inspecting
all 23 features found two self-touching rings:

| Feature | Name | Original defect | Derived form |
| --- | --- | --- | --- |
| `school-zones-elementary:5` (ordinal 5) | Hartley Elementary Zone | Ring self-intersection at `[-83.6851205356295, 32.8153025000676]` | Polygon with one explicit interior ring |
| `school-zones-elementary:10` (ordinal 10) | Porter Elementary Zone | Ring self-intersection at `[-83.7114326322725, 32.7532164608388]` | Polygon with one explicit interior ring |

The derived repair splits the self-touching interior loop out of the exterior
ring; it does not move a vertex, invent a boundary, or change district membership
by a deliberate geometric adjustment. Both repairs pass:

- Original and derived geometry type: `Polygon`; derived valid and nonempty.
- Exact topological equality of boundary point sets and Hausdorff distance `0`.
- Relative planar area difference below `1e-12` (approximately `1.15e-15` for
  Hartley and `2.19e-15` for Porter). These are coordinate-space comparisons in
  square degrees, not claims about land area in square metres.
- Feature IDs, feature properties, source URLs, check dates, attribution, other
  feature fields, all other 21 features, and original source bytes are unchanged.

Input: `civicpulse-web/public/data/school-zones-elementary.geojson`.
Reviewed whole-file SHA-256:
`235080b70b452d65e2796b29cc30ec004d266b25b8f5e68e552e2fec38fd80bb`.
The original snapshots under civicpulse-web's `data/sources/bcsd` and the original
public GeoJSON remain untouched. No source snapshot is rewritten or replaced.

The committed artifact
[`data/import-repairs/school-zones-elementary.json`](../data/import-repairs/school-zones-elementary.json)
contains both original and derived geometry values, the source hash, feature IDs,
algorithm/version, and measured evidence. Original source bytes remain the
canonical snapshot; JSON geometry copies in the artifact are not byte snapshots.
Shapely's [linework make-valid algorithm](https://shapely.readthedocs.io/en/stable/reference/shapely.make_valid.html)
is used because it preserves the input edge/vertex linework. For these exact
features its boundary equality and area tests establish the narrow repair above;
this is not permission to repair arbitrary invalid geometry automatically.

## Reproduce and verify

Python is needed only to regenerate/independently verify the artifact, not for
normal Node import. Use Shapely 2.1.2 (pinned in
[`scripts/requirements-geometry.txt`](../scripts/requirements-geometry.txt)).

```sh
python3 -m venv /tmp/civicpulse-geometry-venv
/tmp/civicpulse-geometry-venv/bin/pip install -r scripts/requirements-geometry.txt
/tmp/civicpulse-geometry-venv/bin/python scripts/prepare-geometry-repair.py ../civicpulse-web
/tmp/civicpulse-geometry-venv/bin/python -m unittest discover -s tests -p 'test_geometry_repair.py'
npm test
npm run import:web -- --web-root ../civicpulse-web
npm run test:db -- --web-data
```

The generator refuses changed source bytes, unexpected invalid feature IDs,
wrong Shapely version, invalid/type-changing output, boundary changes, and area
drift. It rechecks source bytes after generation. The artifact records the GEOS
version too; when upgrading tooling, regenerate and review the artifact diff.

The Node importer checks the **whole source-file hash before applying either
repair**, then replaces only the two geometry members in memory. It attaches
`payload.importProvenance` with the source path/hash, artifact path/hash, method,
and repaired feature IDs. It never rewrites input files or silently replaces
existing database drafts. Unknown source bytes stop the import for human review.

To inspect new or original source data without applying the reviewed repair:

```sh
npm run import:web -- --raw-geometry
npm run test:db -- --web-data --raw-geometry
```

The raw database audit reports invalid source records rather than treating those
known rejections as test failures. The normal derived audit fails if **any**
publication blocker remains. Both modes create/drop only an isolated local test
database; neither calls the hosted API. See [local test setup](../README.md#development).

## Eventual authorized import

Once the lead authorizes production draft creation, provide the existing CLI
variables (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `CIVICPULSE_ACCESS_TOKEN`)
using a real editor/admin session and run `npm run import:web -- --apply`.
Do not reuse a test UUID, forge a JWT, or use a service-role key. The CLI creates
missing drafts, skips identical drafts, and reports different existing drafts as
conflicts without overwriting them. It never publishes.

Admin review/publication follows dependency order: organizations → calendars →
events, layers → maps. A repaired elementary layer must publish before
`school-elementary`. Publish only the exact reviewed revision. Public-site
activation and refresh behavior must be coordinated with Web-Dev; see the
[handoff](web-integration-handoff.md#publication-reaching-resident-facing-pages).

## Private-event derived normalization (local privacy checkpoint)

`scripts/private-events.mjs` normalizes only the reviewed Mobilize snapshot,
SHA-256 `bc7f96e0faff7b3bf69058a3ef5d8826ea8ba71141bc874f8075af6b38d5c740`.
The 81 approved occurrence IDs and transformation metadata are recorded in
`data/import-repairs/private-events.json`. Both `address` and `location` become
exactly `Private location — see organizer for details`; only ADR allowlisted
fields survive (`sourceCity` is removed). IDs and other allowed values remain
unchanged. Coordinates must already be absent/null; unexpected coordinates or
an unreviewed source hash/ID stop import. No event provenance object is added.

Original bytes remain in web `src/data/mobilize-events.json`; captured supporting
evidence remains in web `data/sources/mobilize-bibb/`. This importer never writes
those files. These raw inputs are evidence, not public downloads/build artifacts;
only normalized validated records may enter public output. Repository storage is
not itself access control: review evidence access before introducing real private
details. API stores only hash/IDs/transformation metadata in the repair manifest.

The additive privacy migration rejects unsafe publication with SQLSTATE `22023`,
without silently changing the saved reviewed payload. Staff drafts/history may
retain original details. Unknown keys (even null), nested values, wrong boolean
or string types, non-null coordinates and noncanonical placeholders are rejected.
Private events create no GeoJSON features. Public prose and source links remain
editorial responsibility, not automatic PII detection.

URL checks currently accept HTTP(S) ASCII hostnames or bracketed IPv6 with valid
ports, and reject userinfo, whitespace, controls, backslashes and encoded authority.
Exact URL-edge-case alignment with Web-Dev remains a review item; no browser/client
signature changes are introduced. Privacy SQL regressions pass in a disposable
PostGIS database, alongside security and publication tests. The 81-record adapter
check passes. The plain-tsx adapter blocker was resolved by Web-Dev; the fresh
full-source audit below includes this privacy change.

### Reproducible privacy import audit — 2026-10-16

- API tested commit: `7ad292b8dca96d4dc5abbe16b9a7cc08d251beb1` (clean).
- Web source commit: `b41f9cc539972d4f3f3bae2fc851060ac3e4d0c5`.
- Runtime: Node `v26.11.1`, pinned tsx `4.23.15`; disposable local PostGIS
  container `civicpulse-api-db-test`, with no network.
- Command from API checkout: `npm run test:db -- --web-data`.
- Result: exit 0, **935 imported and published**, **zero source issues**;
  permission/publication/PostGIS, generation/outbox/manifest and private-event
  rejection SQL markers all passed. The harness drops its test database afterward.

The web checkout had unrelated UI/documentation/test edits; `git diff HEAD --
src/data public/data src/lib/content-source.mjs` was empty, covering the importer
source data, map catalog dependencies and source-selector helper. The plain-Node
adapter selects local source when Astro import metadata is absent; no hosted
content is fetched. For reproduction, use these two exact commits in sibling
checkouts and the pinned API dependencies, with the disposable container running.
This is a fresh observed result, not reuse of the pre-privacy 935-record audit.

This checkpoint does not close shared URL edge-case parity/actual-publish corpus,
hostile web snapshot validation, machine grants, leases/fences or production
rollout review. No production content was written.
