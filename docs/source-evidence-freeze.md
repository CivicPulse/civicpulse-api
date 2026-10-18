# Connected observer review freeze

Implementation/source commit: **83b95c956451a4a96ecf478d996d0e46576e0af4**.
This is a local review candidate, not independent approval or hosted authority.
Status correction 88e829f was independently passed separately; this increment
changes no SQL migration, production RPC, grant or browser vendor.

- [Exact driver wire and real SQL recipe](delivery-observer-fixture.md).
- [Public lossless package interface, sidecar, lexical and resource limits](source-evidence-consumer.md).
- New public export: `civicpulse-source-tooling-local/source-evidence`.
- Existing `run-facts-v2` and `workflow-path-v2` exports remain unchanged.

## Independent pins to review

These values live outside the artifact. Security must verify them against the
frozen commit before Web consumes the bundle; self-reported bundle hashes alone
are not authenticity.

| item | SHA-256 |
|---|---|
| manifest.json | `fb2d058d9a176c47d00c406da264b37b58123ab281732dda1cee66a66de9654a` |
| verify-bundle.mjs | `5cdd0480688f70ba74b74bc364c4a1dffcacab16a1ed6eaed189a2ddc2d164d1` |

Pristine preinstall directory:
`/tmp/civicpulse-observer-bundle-yZIZIwkO/pristine`.
The sibling `bundle` was installed/tested and must not be treated as preinstall
input. Both exports had identical manifest digests. Inventory is 22 regular
payload files plus manifest; one unchanged integrity-locked MIT dependency,
lossless-json 4.3.2. No internal parser export or caller override is public.

Reproduce from the pinned API source, using a fresh mode0700 owner-controlled
parent with no concurrent writer:

```sh
node scripts/export-source-tooling.mjs 83b95c956451a4a96ecf478d996d0e46576e0af4 /PRIVATE/NEW/bundle
```

Before executing any artifact code, compare verifier bytes to the independent
pin above. Then verify the manifest with the independent digest, confirm exact
source/entrypoints, install with `npm ci --offline --ignore-scripts --no-audit
--no-fund` when the exact tarball is cached (omit only --offline otherwise), and
run the allowlisted `npm test`. No package publication or sibling checkout needed.
Follow the full trust-order/inventory checks in [the bundle recipe](source-tooling-bundle.md).

## Developer evidence

- `npm test`: **75/75**, Node26.11.1, including unchanged legacy suites and all
  17 package-inventory/adversarial checks. Initial sandbox EPERM spawning Git was
  rerun under the narrowly approved local test command; it was not a code failure.
- `node scripts/test-delivery-fixture.mjs`: exit0. Fresh network-none container,
  real registered sessions/open-record/approval/claim/heartbeat/transitions, seven
  records and generation8, two consumed observations, ready without live authority.
  Actual PostgreSQL JSONB retained large actor/ruleset IDs and high-precision/
  underflow numeric semantics. No source acquisition authenticity is claimed.
- Complete standalone bundle: exact-tree verification exit0; offline no-script
  install added one dependency; **48/48** tests passed on Node26 and independently
  executed developer Node22.23.2 container lane (not independent Security review).
- Node22 source resource lane: nine focused cases pass; final measured budget and
  at/over results are in the consumer doc. 512MiB V8 heap / 1GiB container required
  by this measured lane. 128/256MiB heap OOM results remain explicitly recorded.

Web still owns fixed HTTP/Link acquisition, cumulative read accounting, complete
private sidecar binding, source A/B/config comparison, real artifact build/reader
and zero record calls when acquisition fails. The API fixture accepts supplied
synthetic evidence through real SQL; it cannot prove HTTPS origin or three-origin
bytes. Equivalent-but-differently-spelled policy numbers intentionally fail
lexical adapter comparison; SQL numeric semantics tests are a separate boundary.
No provider request, credential, hosted mutation, remote push or deployment ran.
