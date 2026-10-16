# Frozen local server-tooling consumption recipe

The directory-only `civicpulse-source-tooling-local-v1` artifact is separate from browser/v1/M2a bundles. API/Web/Security agreed the shape and trust bootstrap on 2026-10-16. See the exported [consumer recipe](../tooling/source-bundle/README.md) for entrypoints, types, exact dependency/license provenance and fail-fast install/test steps. Actual frozen package review remains Security-owned; no Web integration or source authority is granted by this recipe.

Export from an independently reviewed full API commit containing this tooling:

```sh
node scripts/export-source-tooling.mjs FULL_40_HEX_SOURCE_COMMIT /private/temp/parent/new-bundle
```

The parent must exist, be mode0700/current-user-owned and have no untrusted concurrent writer or symlink ancestor. The destination must not exist. These POSIX ownership checks fail closed without getuid. The exporter reads only a fixed allowlist of Git mode100644 blobs at the requested commit; it never copies working-tree code, node_modules or secrets. All source modules/tests retain identical bytes. The package templates, dependency notice, verifier, API license and recipe come from that same pinned commit. Source commit identifies code AND recipe/templates. Minimal lock provenance is the repository's independently reviewed lossless-json4.3.2 pin; the consumer test checks its installed upstream metadata and exact MIT license bytes.

The exporter prints source commit, external manifest SHA256 and external verifier SHA256. Record these three values separately in the reviewed handoff; consumers must not treat exporter/self-reported values as approval. `manifest.json` specifies format, source commit, two public import/type entrypoints, dependency provenance, exact directory modes and file records (`sha256`, `bytes`, `mode`, `git_mode`, `source_path`). It does not hash itself: its independently pinned digest covers all manifest bytes. The verifier itself is a hashed payload file but must be independently hash-checked BEFORE execution, breaking the self-trust cycle.

Verifier root mode0755, directories0755 and files0644 are exact, including rejection of special permission bits. Files must be regular and have link count1. Root and ancestor symlinks, payload symlinks, hardlinks, FIFO/special files, unexpected paths/directories and preexisting node_modules reject. Directory link counts are not restricted. This is a preinstall check for an isolated artifact, not race protection in a shared writable parent, a post-install node_modules auditor or a dependency authenticity substitute. npm checks the pinned dependency integrity and ignores scripts; tests then compare installed MIT notice/version/provenance and resolve the public exports.

Developer validation: `node --test --test-isolation=none tests/source-tooling-bundle.test.mjs`, full `npm test`, then a real frozen export in a new private temp directory, independent digest verification, `npm ci --offline --ignore-scripts --no-audit --no-fund` with a populated cache and `npm test` from the bundle. Run a second export of the same commit and compare manifest bytes to establish deterministic packaging. No remote registry publication, browser exports or runtime enable flags are introduced.
