# API and CMS integration

Base URL: `https://drzcrodqflzkzzbqsags.supabase.co/rest/v1`.
Send `apikey: <publishable key>` on every request. Staff requests additionally send
`Authorization: Bearer <Supabase Auth access token>`.

## Content and lifecycle

| Kind | Payload contract |
| --- | --- |
| `organization` | Existing organization object: `id`, `name`, optional `color` |
| `calendar` | Existing calendar object: `id`, `name`, `organizationId`, optional source calendar/color |
| `event` | Existing `CommunityEvent` from civicpulse-web, preserving source metadata and calendar IDs |
| `layer` | Existing layer metadata plus `geojson: FeatureCollection`; event-locations instead uses `dynamic: "events"` |
| `map` | Existing map object with ordered `layers` IDs |

Payload JSON preserves heterogeneous source fields without flattening or dropping
upstream attributes. Required publication fields and cross-record references are
validated in PostgreSQL. Incomplete drafts can be saved; publishing rejects missing
fields, invalid memberships, sample events, invalid dates, and invalid geometry.
Coordinates use `[longitude, latitude]`, SRID 4326. Virtual/private-address events
must not contain coordinates. Private street addresses must never be imported as
public payload text; the current web sources use public signup placeholders.

Each draft starts at revision 1. Saving increments it. Publishing copies that
revision into a separate snapshot; later saves do not affect the public version.
There is no destructive content-delete API. Withdraw removes the public snapshot
and spatial features while retaining the draft and audit history. Referenced
content cannot be withdrawn until its dependents have been withdrawn or changed.

## Read endpoints

| Endpoint | Access | Response |
| --- | --- | --- |
| `GET /content?kind=eq.event&order=id.asc&limit=100&offset=0` | Public | Published rows (`kind`, `id`, `revision`, `payload`, `published_at`) |
| `GET /cms_drafts?kind=eq.event&order=id.asc&limit=100` | Staff | Draft rows including last editor and update time |
| `GET /cms_history?kind=eq.event&id=eq.ID&order=sequence.desc&limit=50` | Staff | Save/publish/withdraw history with payload snapshots |
| `POST /rpc/cms_role` body `{}` | Signed in | `"admin"`, `"editor"`, or `null` |
| `POST /rpc/layer_geojson` | Public | Paginated GeoJSON FeatureCollection |

Use explicit pagination; Supabase caps table responses at 1,000 rows. For draft
lists, request only metadata to avoid downloading full layer geometry:
`select=kind,id,revision,updated_at,name:payload->>name,title:payload->>title`.
Fetch the selected document's full payload when opening its editor.

Published layer payloads omit `geojson`; fetch features through `layer_geojson`:

```json
{
  "p_layer_id": "polling-places",
  "p_limit": 500,
  "p_offset": 0,
  "p_west": -83.8,
  "p_south": 32.7,
  "p_east": -83.5,
  "p_north": 33.0
}
```

Bounds are optional but must include all four values if used. Limits are 1–1,000.
The response includes `nextOffset`; fetch the next page until it is null. Bounds
use exact PostGIS intersection. Split antimeridian-spanning bounds into two calls.
Pagination is not a multi-request snapshot: if publication changes mid-download,
restart the download for a consistent export.

`event-locations` returns one feature per geocoded published event. Its properties
contain the event payload; group by venue in the web client if desired. Other
layers preserve source feature properties and IDs. The API does not silently
repair invalid polygons; an admin must review and correct rejected geometries.

## Write RPCs

All bodies below use POST with `Content-Type: application/json`.

```js
// Save new or edited draft. Use 0 only for a record that does not exist yet.
await supabase.rpc('save_draft', {
  p_kind: 'organization', p_id: 'example',
  p_payload: { id: 'example', name: 'Example organization' },
  p_expected_revision: 0,
}); // returns 1

// Admin: publish precisely the version displayed in the review screen.
await supabase.rpc('publish', {
  p_kind: 'organization', p_id: 'example', p_expected_revision: 1,
});

// Admin: remove the current publication, retaining the draft.
await supabase.rpc('withdraw', {
  p_kind: 'organization', p_id: 'example', p_expected_revision: 1,
});
```

Publish organizations before calendars, calendars before events, and layers before
maps. Updating a calendar's organization is rejected when it would invalidate
published events. Write functions lock the editorial catalog during the
transaction; this favors correctness for a small editorial team over high-volume
parallel writes. Spatial indexes serve public reads independently.

| SQL error code | UI behavior |
| --- | --- |
| `42501` | Access denied; refresh membership or ask an admin |
| `40001` | Revision conflict; reload and compare, never automatically overwrite |
| `22023`, `22007`, `22008`, `23514` | Show validation error; keep the draft |
| `23503` | Publish required dependencies first, or resolve existing references |
| `P0002` | Record or published layer not found |

`src/client.mjs` provides the same operations using standard Fetch. Pass
`accessToken: async () => currentAccessToken` so it uses refreshed sessions.
It never needs a service-role key.

## Astro integration boundary

The website continues to own pages, forms, styling, Supabase Auth session handling,
and review UX. This API project owns database state and publication rules.
The current website can stay static while browser-side admin components use
Supabase Auth and these RPCs; server-rendered session routes are another option
but require an Astro adapter/deployment change in that repository.

Minimum CMS flow: sign in → list drafts → edit/save → admin review → publish or
withdraw. Compare draft and published revision to label unpublished changes. Hide
admin actions for editors, but rely on the database for security. Render source
content as text or sanitize it before displaying HTML; upstream GeoJSON/event
properties are not trusted markup.

Resident-facing pages must remain usable while the API is offline. The agreed
delivery direction is a validated static content export, followed by an Astro
build/deployment that preserves the last successful site on failure. Dynamic
browser enhancements must have static fallbacks. The existing API has no durable
build trigger, complete export manifest, or deployment-status contract yet; see
[publishing gaps and architect coordination](publishing-architecture-gaps.md).
No v1 signature changes or hosted deployment changes accompany that proposal.
