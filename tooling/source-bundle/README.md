# CivicPulse source tooling: local test-only bundle

This private package contains reviewed run-v2/path-v2 helpers and the connected source-evidence extension plus their transitive modules, declarations and regression tests. It is not a provider adapter or source authorization mechanism. Keep it outside browser/public/build inputs, separately from hosted v1/M2a vendors. Web's agreed future location is `tools/vendor/civicpulse-source-tooling-local/`; importing into Web remains a separately assigned task.

Public package exports are `civicpulse-source-tooling-local/run-facts-v2` (decode/assert, `RunTargetV2`, `InProgressRunFactsV2`, `RunNumericIdentityV2`) and `civicpulse-source-tooling-local/workflow-path-v2` (assert, `WorkflowPathPolicyV2`, `WorkflowPathObservationV2`). The additional server-only `civicpulse-source-tooling-local/source-evidence` export provides bounded lossless response/config projections, policy canonicalization, membership/page assembly and exact source evidence JSON text; see `SOURCE-EVIDENCE.md`. It is not an authenticated adapter. Internal modules and the legacy decoder are present only as transitive/test files, not package exports. The three unchanged focused suites cover parser, path and run facts. The consumption suite checks public export resolution, blocks internal package subpaths and compares installed dependency metadata/license.

## Trust bootstrap and reproducible consumption

Use Node 22.12+ and npm on a POSIX filesystem. Aggregate boundary tests require the measured 512MiB V8 heap / 1GiB container budget; smaller tested heaps OOM. See `SOURCE-EVIDENCE.md` for exact resource evidence. Export/verification require the immediate parent mode0700 owned by the current user and the artifact root owned by that user; ownership checks fail closed where getuid is unavailable. Obtain THREE values from the independently reviewed handoff, outside this artifact: full source commit, SHA256 of `verify-bundle.mjs`, and SHA256 of `manifest.json`. A hash printed by the exporter or contained in this directory is not independent authentication. Never default to values read from the artifact. Match the expected source commit after manifest verification.

Create a fresh owner-controlled private temporary parent (`mktemp -d`, mode0700), with no concurrent/untrusted writer. The artifact is a directory only, not an archive. Copy/export into a new child directory `bundle` (mode0755); every preinstall payload file and manifest is regular0644, link count1, and every declared directory0755. Preserve these modes. The verifier rejects root/ancestor symlinks, hardlinked files, extra/missing files or directories (including preexisting node_modules), symlinks, special files, unsafe paths and unexpected modes. Normal directory link counts are allowed. These checks do not solve races with a hostile process that can write the parent/artifact; secure exclusive ownership is a precondition through install/import/test. A failed copy/export remains unusable until full verification succeeds.

Before executing ANY artifact code, use trusted host hashing tools to compare the verifier's bytes with the independent expected verifier digest. For example from the artifact directory, after setting the three values explicitly from the reviewed handoff:

```sh
printf '%s  verify-bundle.mjs\n' "$EXPECTED_VERIFIER_SHA256" | sha256sum --check --strict
node verify-bundle.mjs . "$EXPECTED_MANIFEST_SHA256"
# Confirm printed source commit equals the independently expected source commit.
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

Stop on ANY failure; run these steps with shell fail-fast handling. The verifier uses Node builtins only, hashes the manifest before parsing it and imports no bundle modules. The manifest external digest covers itself; `files` covers every OTHER preinstall file with SHA256, bytes, filesystem mode, original Git mode and source path. `directories` is the exact derived directory inventory. All source blobs must have Git mode100644. Manifest formatting is deterministic JSON, two-space indentation and one trailing newline, without timestamps or destination paths.

The minimal lock v3 installs only `lossless-json` exactly4.3.2 from `https://registry.npmjs.org/lossless-json/-/lossless-json-4.3.2.tgz`, integrity `sha512-TWT1oIGJKaHkme0nDFoW9Tsv0/IZxy6P8rzD03hZpk7de04PWGfl/uMj/WcENrJLNF4P+QGGByPjap6qx++bDQ==`. Its upstream repository is `https://github.com/josdejong/lossless-json.git`; MIT notice is `LOSSLESS-JSON-LICENSE.md`. The API repository's own license is included unchanged as `LICENSE`. No dependency installation scripts run. `--offline` may be added to npm ci only when that exact integrity-checked tarball is already cached; no cache success is assumed. No package publication occurs.

`node_modules` is permitted only as generated installation output AFTER successful preinstall verification. Do not relax the preinstall verifier for existing installations; use a fresh artifact for each verification/install. npm test executes only the five explicitly named bundled test files. No sibling checkout is needed. Public import resolution can use this private package's self-reference within the isolated directory; later Web integration must preserve the reviewed standalone install boundary rather than rely on ambient dependencies.

Passing tests proves local structure/equality and artifact consistency only. Provider origin/compatibility/freshness, enrollment, observer/source admission, claims and deployment remain unimplemented or independently gated.

The additive `civicpulse-source-tooling-local/terminal-run` export provides
`decodeGitHubTerminalRun(rawJson)` and `assertGitHubTerminalRun(actual, target,
pathPolicy, endpoint)` plus `TerminalRun`. The decoder projects exactly eleven
string fields into the existing private terminal evidence shape, including five
lossless numeric identities, unchanged raw_path and completed lifecycle/conclusion.
It uses the same fixed raw parser limits; no provider authentication, freshness,
source authorization or uploader permission follows. Comparator errors are
`invalid_github_terminal_run` or `github_terminal_run_mismatch`, without raw body
or parser cause. Existing run/path/source-evidence exports and dependency pin remain.
Terminal output is safe to JSON.stringify; arbitrary full policy JSON still uses
the separate lossless text assembly contract. Do not native-parse that policy.
