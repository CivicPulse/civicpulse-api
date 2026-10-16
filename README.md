# CivicPulse API

Supabase backend for [CivPulse](https://www.civpulse.org/). This repository contains
Postgres/PostGIS migrations, authorization, the Data API contract, and import tooling.
The Astro CMS/admin interface belongs in `civicpulse-web`.

## Development

Requires Node 22.6+ and a container runtime for database tests.

```sh
npm ci
npm test
npm run supabase -- start
```

The CLI creates a local Supabase stack. Config disables public signup; invite staff
through the Supabase Auth dashboard. Hosted Auth settings must be configured separately.
No secret or service-role key belongs in the Astro frontend.

For lightweight database tests, start a disposable PostGIS container:

```sh
podman run -d --name civicpulse-api-db-test --network none \
  -e POSTGRES_PASSWORD=local-test-only docker.io/postgis/postgis:16-3.5
npm run test:db
# Optional source-data audit, also runs the security checks:
npm run test:db -- --web-data
podman stop civicpulse-api-db-test
```

The harness creates and drops its own database. It tests real PostgreSQL RLS,
permissions, publishing transactions, reference integrity, revision conflicts,
and spatial queries. A minimal Auth schema substitutes for Supabase Auth locally;
this is not an Auth service integration test. The optional audit reports source
records that cannot publish; it does not change source files or hosted data.

## Import existing web data

```sh
npm run import:web -- --web-root ../civicpulse-web
# After signing in as invited staff, supply environment variables from .env.example:
npm run import:web -- --web-root ../civicpulse-web --apply
```

The default is a read-only inventory. `--apply` creates **drafts only**. Existing,
identical drafts are skipped; different drafts are reported as conflicts and never
overwritten (exit 2). Interrupted imports can be rerun. Environment variables must
be exported by your shell; the scripts do not automatically load `.env`.

The importer preserves source IDs, calendar memberships, provenance, feature
properties, and event metadata. It follows the web app's Mobilize replacement
rules and imports the authoritative TypeScript map catalog. It does not use the
obsolete static event-locations GeoJSON: that layer is generated from published events.
The reviewed elementary-zone snapshot receives two hash-gated derived geometry
repairs; original bytes remain untouched. See [repair evidence](docs/import-data.md).

## Architecture and deployment

- [Web-Dev handoff](docs/web-integration-handoff.md)
- [Static publishing boundary and gaps](docs/publishing-architecture-gaps.md)
- [Reviewed derived import procedure](docs/import-data.md)
- [API and CMS integration](docs/api.md)
- [Operations and deployment](docs/operations.md)
- [Confirmed product scope](PRODUCT.md)
- [Future civic data sources](docs/datasouces.md)

Drafts and published snapshots are separate. Editors save drafts; admins publish
an exact reviewed revision. Public clients only see published content. PostgreSQL
checks live staff membership, so revoked roles stop working without waiting for a
JWT refresh. PostGIS stores published feature geometries with a GiST spatial index.

Project: `drzcrodqflzkzzbqsags` (CivicPulse). Never point test scripts at a hosted
project. The hosted API is `https://drzcrodqflzkzzbqsags.supabase.co/rest/v1/`.
