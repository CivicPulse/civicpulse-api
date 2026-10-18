# Connected observer lossless consumer

Local implementation of parent integrated contract
`c9da0fb59ce76f2bbf3f0c1baa53cab1e3530d8b7792aaaf02e76d3b28346910`.
This adds `civicpulse-source-tooling-local/source-evidence` to the existing private
server-only bundle. It neither changes legacy run/path APIs nor authorizes any
source, provider, credential, live receipt or deployment. Frozen Security review
and independently pinned bundle digests are required before Web consumes it.
See [bundle trust/install recipe](source-tooling-bundle.md) and
[connected driver](delivery-observer-fixture.md).

The same iterative duplicate-rejecting scanner and exact lossless-json 4.3.2
remain in use. No raw provider JSON is parsed natively. Native JSON.parse is used
only for already constructed closed projections containing strings, booleans,
null and empty referenced-workflow arrays, never full policy bodies.

## Public export

- `decodeGitHubSourceResponse(rawJson, endpoint)` returns JSON **text**. Repository,
  workflow, run/attempt and ref projections have the existing SQL evidence keys;
  every provider numeric identity becomes an exact canonical decimal string.
  Run projection additionally retains actor_id, triggering_actor_id and requires
  own-present empty referenced_workflows, in_progress/main/null and allowed event.
  Classic/list/detail/effective policy bodies preserve all unknown fields and
  numeric tokens as JSON numbers. Endpoint selects a fixed structural projection,
  not an authenticated origin.
- `projectGitHubSourceResponse` adds typed `facts` and `canonical_json`. Repository
  facts include owner_type for org-scope eligibility (not a new SQL key). List and
  detail facts include exact ID/source/source_type/enforcement/bypass presence;
  detail requires explicit bypass_actors and projects actor IDs losslessly.
  Effective facts expose contributor ID/source. `json` is still the full policy
  body or SQL projection, never a rounded object.
- `canonicalizeGitHubPolicyJson(text)` sorts object keys by UTF-8 bytes, preserves
  array order and validated numeric lexemes, and performs no Unicode/number
  normalization. Use it for deterministic equality, not provider authentication.
- `projectGitHubSourceConfig(config_json)` returns bounded known source/provider
  strings, allowed_events, full `protection_json` and canonical config text.
  Do not native-parse and reserialize config. Challenge typed fields are separate
  from its one `config_json` text field in the fixture wire.
- `assembleGitHubProtectionEvidence({classic_json,list_pages,detail_json,
  effective_pages}, {repository_full_name,owner,owner_type,scope})` validates
  complete page transcripts, distinct list IDs, increasing numeric detail order,
  exact membership/source/shared fields, explicit bypass metadata, active effective
  contributors and full-page empty probes. Each page is `{page,next_page,json}`;
  next_page is the already validated next integer or null. It preserves duplicate
  effective elements and nested arrays, sorts effective elements by lossless
  canonical JSON, and returns complete policy JSON text.
- `assembleGitHubSourceEvidence(parts)` accepts exactly the eleven SQL evidence
  fields other than schema_version, each as JSON text; adds schema_version 1 and
  returns bounded complete text. `requests` must be an array of at most 256 rows.
  SQL performs the existing exact field/value/context validation. A serializer
  result is not an authenticated or approved observation.
- `inspectGitHubSourceResponseBudget(raw)` returns preflight `{tokens,bytes}` so
  the adapter can reject cumulative excess **before retaining** the next response.
  The adapter owns cumulative actual read/body accounting across both rounds and
  file reads; a per-round protection builder is not a substitute for that counter.

Errors are `invalid_github_source_evidence` without parser cause/body. Expected
policy mismatch is a consumer comparison failure, not an excuse to rewrite input.
Types include exact `SourceRequestAudit`/`SourceAcquisitionAudit` sidecar shapes.

## Private audit and acquisition responsibilities

SQL `requests` remains `{endpoint_key,page,status,github_request_id}`. Detail reads
map to rulesets_before/after with page 1; list pages use actual page; duplicate
coarse key/page rows are allowed. Preserve acquisition order. For every row the
adapter retains a one-to-one private request_index with phase/operation/scope,
configured repository ID/owner ID/full name, ruleset ID/null, actual page/per_page
or null for detail, includes_parents, constructed path/query, next page, body hash
and request ID. The sidecar binds challenge/config/source and the exact evidence
text digest; it is not sent as extra SQL keys. It contains no auth headers.

The Web adapter still owns fixed endpoint construction, Link syntax and scope
validation, actual HTTP status/redirect/credential checks, global counters,
immutable sidecar retention, A/B/enrollment equality and zero record calls on
incomplete evidence. This API package verifies supplied body/page structure and
membership; it cannot establish that a supplied next-page value came from a Link
header or prove HTTPS acquisition. Repository parent-inclusive list/detail is the
runtime profile; org scope is an explicit operator context, never an inferred
applicability scan or fallback credential. Missing bypass visibility fails closed.

## Precision and resource profile

Individual upstream responses retain inclusive 1MiB / depth64 / 32768 lexical
tokens / 65536 raw-string UTF-8 bytes, duplicate rejection at every nesting.
The separate fixed aggregate config/evidence/challenge-body profile is inclusive
8MiB / depth72 / **262144 tokens** / the same 65536 string limit. No public caller
can override scanner bounds. The observation additionally limits 256 actual reads,
8MiB cumulative decoded bodies and 262144 cumulative upstream tokens. This does
not promise that 256 maximally dense responses fit. Fixed config/evidence wrappers
around a deepest valid upstream response are covered by regression tests.
Encoded NDJSON has a separate cap; its aggregate JSON-text field is not subjected
to the raw string-token cap for an upstream JSON body. See driver recipe.

PostgreSQL JSONB preserves numeric values but may change spelling (e.g. 1e-400 to
expanded decimal). Raw A/B canonical equality preserves spellings. Comparing raw
policy against config_json intentionally **fails closed** on lexical differences,
even where SQL would consider the values equal. Do not normalize numbers to force
agreement or infer an original-policy artifact authority path. SQL precision tests
are numeric-semantic evidence, separate from ordinary-spelling adapter positives.
Large identity strings retain their full 20 digits; no safe-integer restriction.

Measured Node **22.23.2**, immutable image
`sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5`
(local image ID `6e6261159fd399ebe5a3d556b7d89da9c85c873f3f270918aad6c8107da8b411`):
128MiB and 256MiB V8 heaps failed with OOM on the accepted at-byte workload.
The passing measured lane uses **512MiB V8 heap / 1GiB container / 120s timeout**,
network disabled, read-only root and private tmpfs. Initial sequential retained-input
run: token at/over 57/16ms, byte-at 1277ms, retained assembly 2781ms, config 1356ms;
peak RSS 492580KiB. Over-byte and over-token cases invoked the dependency parser
zero times. These are measured execution requirements, not 128MiB support or a
production capacity approval. The pinned dependency's per-character string
allocation remains unchanged. `scripts/test-source-resource.mjs` reproduces the
resource operations; run it with the stated heap and container limits.

Reproduce the resource lane without mounting shared source into the container:

```sh
tar -cf - src/server node_modules/lossless-json scripts/test-source-resource.mjs package.json |
  podman run --rm -i --pull=never --network=none --read-only --cap-drop=all \
    --security-opt=no-new-privileges --memory=1g \
    --tmpfs /work:rw,nosuid,nodev,size=64m -w /work \
    docker.io/library/node@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5 \
    sh -c 'tar --no-same-owner -xf - -C /work && exec node --max-old-space-size=512 scripts/test-source-resource.mjs'
```

Final repeated resource run after fixed-wrapper preflight: 60/17ms token at/over,
1251ms byte-at, 2539ms retained assembly, 1599ms config, peak RSS 465576KiB;
nine public projection tests passed on the same Node22 lane. Both over-limit
cases still invoked the dependency parser zero times. Figures are developer
measurements; independent frozen review remains separate.
