# Verification — 2026-10-16

## Deployed

Project `drzcrodqflzkzzbqsags` (CivicPulse), PostgreSQL 17:

- `20261016195541_civicpulse_content_api`
- `20261016195619_restrict_platform_trigger_execution`

Local migration filenames match hosted migration history. The initial admin is
`fb169f7b-5947-444c-93d0-999ba21bd8ec`; the Auth user was verified before assignment.
No real content has been imported or published on the hosted project yet. Hosted
test fixtures were created within a transaction and rolled back.

## Passed

- Node client/import tests: refreshed user tokens, API errors, pagination, event
  merge behavior, invalid memberships, and safe rerun/conflict handling.
- Local PostgreSQL 16 / PostGIS database suite: anonymous and ordinary-user denial,
  editor draft access, admin-only publishing, prevention of self-promotion and
  direct table writes, revision conflicts, publication snapshots, reference
  integrity, geometry bounds, GeoJSON pagination, failed-publication rollback,
  withdrawal cleanup, and immediate membership revocation.
- The same SQL permission/publication/PostGIS suite passed on hosted PostgreSQL 17
  with the real Supabase Auth schema. This tests database behavior; it does not
  simulate interactive Auth login in a browser.
- Hosted HTTP smoke test with a publishable key: public content read succeeded;
  anonymous draft reads and writes were rejected.
- `git diff --check`.

## Existing web-data audit

935 records inventoried: 7 organizations, 20 calendars, 867 deduplicated events,
24 layers, and 17 maps. In an isolated database, 933 records published successfully.
Two records were rejected:

| Record | Reason |
| --- | --- |
| `layer/school-zones-elementary` | Feature 5: ring self-intersection at approximately longitude -83.6851205356295, latitude 32.8153025000676 |
| `map/school-elementary` | Its required elementary school-zone layer could not publish |

This was the original-source audit. A full layer inspection subsequently found
the second invalid feature, `school-zones-elementary:10` (Porter). The two
reviewed, hash-gated derived repairs are documented in [import-data.md](import-data.md);
original source bytes remain untouched. See the follow-up validation below.

## Supabase advisors

After resolving the platform trigger's excessive execution grants, the security
advisor reported no database findings. The remaining Auth warning is
[leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Enable it in the project's Auth settings if supported by the plan.

Performance advisor findings were informational unused-index notices on the new,
empty schema. The spatial, foreign-key, and audit lookup indexes are intentional.

## Remaining integration

The Astro CMS UI and the public site's API consumption have not been implemented
in `civicpulse-web`. Hosted Auth redirect/provider settings still need to match
that UI. Existing web content remains unchanged. The import CLI needs an actual
staff session access token before `--apply`; it never uses a service-role key.

## Derived import follow-up

- Reviewed repairs: Hartley `school-zones-elementary:5` and Porter `:10` only.
- Tooling: Shapely 2.1.2 / GEOS 3.14.1. Both outputs are valid Polygons with
  exact boundary equality, zero Hausdorff distance, and relative area drift below
  `1e-12`. Original file SHA-256 remains unchanged.
- `npm test`: 9 tests passed, including rejection of changed source bytes and
  preservation of every non-geometry feature field.
- Independent Python geometry test passed for both original/derived pairs.
- `npm run test:db -- --web-data`: **935 records published locally, zero blockers**;
  permission/publication/PostGIS checks also passed. Disposable database removed.
- The API client/types exported successfully to `/tmp/civicpulse-api-client` with
  checksum manifest for standalone Web-Dev consumption.
- No deployed schema/RPC changes and no production content writes in this follow-up.
