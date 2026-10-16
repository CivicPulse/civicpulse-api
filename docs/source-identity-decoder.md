# Pure GitHub run identity decoder (local only)

Implements only the six-field decoder/comparator in the accepted parent
[local source handoff](../../docs/architecture-source-local-handoff.md).
`src/server/github-run-identity.mjs` exports `decodeGitHubRunIdentity(rawJson)` and
`assertGitHubRunIdentity(actual,expected)`; `.d.mts` declares RunIdentityFacts.
Neither reads configuration, environment, clock, files, database or network.
There is no observer, credential loader, RPC, approval or delivery-state writer.
The server-only files are not included by the browser/vendor export script.

The decoder projects exactly id, run_attempt, workflow_id, repository_id,
head_repository_id and path into a plain object of strings. IDs must be upstream
positive canonical JSON number tokens (20 digits maximum, attempt 10); all token
bytes survive without Number conversion. Path follows the exact ASCII workflow
path grammar. Unknown upstream fields are ignored only after bounded full parsing.
The comparator validates exact own string data fields on plain/null-prototype
objects, snapshots descriptors without invoking getters, requires the expected
repository IDs to agree, then compares every string exactly. Successful void
comparison proves equality with supplied facts, not authenticated origin or approval.

## Parser provenance and boundaries

Runtime dependency **lossless-json 4.3.2**, exact package.json/lockfile pin, MIT:
[official source](https://github.com/josdejong/lossless-json), installed from the
npm registry tarball recorded in package-lock.json. Tarball integrity is
`sha512-TWT1oIGJKaHkme0nDFoW9Tsv0/IZxy6P8rzD03hZpk7de04PWGfl/uMj/WcENrJLNF4P+QGGByPjap6qx++bDQ==`.
No install scripts were run. The installed ESM parse/LosslessNumber implementation
was inspected: number tokens are retained as strings, including ignored huge
numbers. The decoder uses an actual LosslessNumber instance check and its `.value`,
never valueOf/Number/parseFloat or regex rewriting of input.

Dependency behavior requires a supplement: its duplicate callback runs only for
unequal duplicate values. `src/server/github-run-json.mjs` therefore performs an
iterative forward token walk first, validates JSON token/container states, and
rejects every duplicate decoded key via a Set per object. This covers equal values,
escaped-equivalent names and prototype-named keys at any depth. Native JSON.parse
is used only on exactly delimited and escape-validated string literals, never on
the response body or numeric tokens. The pinned lossless parser then handles the
bounded, duplicate-free body. The extra scan is deliberate overhead for strict
contract and bounded recursive-parser input; no ID range is narrowed.

Inclusive limits from the parent contract:

- Entire raw string: 1,048,576 Node UTF-8 bytes, including whitespace; reject an
  excessive code-unit length before byte counting.
- Simultaneously open containers: 64, root included.
- Lexical tokens: 32,768; each punctuation/string/number/literal counts once.
- Raw string token: 65,536 UTF-8 bytes including quotes and original escapes,
  checked during the scan before decoding, for keys and values alike.

The scanner is iterative and stops on a limit failure before dependency parsing;
there is no separate member cap. Strings preserve JSON surrogate-code-unit
semantics, including lone surrogates in ignored metadata. Required paths remain
ASCII. These bounds do not undo memory already allocated by the caller; a future
HTTP adapter needs its own streamed/decompressed-byte cap. No transport-byte or
wall-clock guarantee is claimed.

All malformed/limit/parser/facts errors expose only code/message
`invalid_github_run_identity`, without cause, raw provider text or partial result.
Valid but differing facts produce `github_run_identity_mismatch`. No result is
called verified, authorized or approved. This is not the complete ADR0004 evidence
schema, and cannot establish source, current-main/config, historical review or
production authority.

## Verification

`node --test tests/github-run-identity.test.mjs` exercises the actual decoder and
comparator with synthetic unauthenticated bodies: adjacent IDs around 2^53,
20/10-digit maxima and overflow, every malformed required-field form, duplicate
keys/equal values/escaped equivalents/nesting, safe prototype handling, exact
path mismatch, unknown huge numbers, invalid escapes and valid/lone surrogates.
At/over byte/string/depth controls and 32,767/32,769-token valid bodies exercise
the exact limits. An internal injectable-parser test seam proves rejected input
never reaches dependency parsing; the public decoder has no parser override.
Full `npm test` also covers the existing client/import fixtures. No database
migration, hosted call, real GitHub response/credential or authority enrollment is
part of these tests. Independent frozen Security review remains separate.
