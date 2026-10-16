# Product

<!-- impeccable:product-schema 1 -->

## Platform
web

## Stack
Supabase PostgreSQL with PostGIS, Supabase Auth, and the Supabase Data API.
This repository is API-only. Astro CMS/admin UI belongs in the neighboring
`civicpulse-web` project, which currently deploys to Cloudflare Pages.

## Users
Invited editors prepare drafts; admins review and publish. CivPulse web consumes
published community information for residents.

## Product Purpose
Store and manage the existing CivPulse events, organizations, calendars, maps,
and geographic layers without requiring edits to the website's source data.

## Capabilities and Constraints
- First release covers existing web data, not the wider civic-indicator catalog.
- Preserve existing IDs, source attribution, source check dates, and GeoJSON properties.
- Editors save drafts; only admins publish or withdraw published content.
- Draft changes must leave the previous published version available.
- Use Supabase Auth identities and database-enforced authorization.
- PostGIS provides indexed geographic queries.
- Resident-facing static content remains usable while the API is offline.
- Publish/withdraw should drive a new static build/deployment; failures preserve
  the last successful site. Dynamic browser features require static fallbacks.
- Trusted GitHub Actions delivery is selected; CP-Architect owns its additive
  generation/outbox/manifest/status contract before implementation.

## Evidence on Hand
`../civicpulse-web/src/data`, `../civicpulse-web/src/lib/events.ts`, and
`../civicpulse-web/public/data` define the existing content contract.
`docs/datasouces.md` describes future civic indicators.

## Open Decisions
Supabase project: `drzcrodqflzkzzbqsags` (CivicPulse). Initial admin Auth UUID:
`fb169f7b-5947-444c-93d0-999ba21bd8ec`.
CMS visual design and implementation will be handled in civicpulse-web.
