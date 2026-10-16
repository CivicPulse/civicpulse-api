# Web-Dev handoff — deployed contract v1

API-Dev owns this repository. **No schema/RPC changes are needed or planned for
this handoff.** Detailed payloads, endpoint tables, and validation codes remain in
[API docs](api.md); staff setup and deployment are in [operations](operations.md).

## Configuration and standalone consumption

- Canonical browser names: `PUBLIC_SUPABASE_URL=https://drzcrodqflzkzzbqsags.supabase.co`
  and `PUBLIC_SUPABASE_PUBLISHABLE_KEY` (obtain the publishable key from the project;
  no credential values are included here).
- CLI names remain `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
  `CIVICPULSE_ACCESS_TOKEN`. No service-role key is required in Web-Dev.
- HTTP base: `https://drzcrodqflzkzzbqsags.supabase.co/rest/v1`.
- Optional Fetch client: [`src/client.mjs`](../src/client.mjs), named exports
  `createCivicPulseClient` and `ApiError`.
- Supabase-generated types: [`src/database.types.ts`](../src/database.types.ts),
  named exports `Database`, `Json`, `Tables`, and other generated helpers.

**There is no published package.** Vendor a checksum-recorded snapshot into the
web repository; do not import from `../../civicpulse-api` in shipping code:

```sh
# Run in an API checkout (a downloaded/pinned checkout is equally suitable):
node scripts/export-web-client.mjs /tmp/civicpulse-api-client
# Web-Dev: copy that directory's three files into src/vendor/civicpulse-api/
# and commit them alongside the web app. Record the API commit when it is committed.
```

The export contains `client.mjs`, `database.types.ts`, and `manifest.json` with
SHA-256 hashes. It has no runtime dependency and needs no install/build step.
A standalone web checkout and CI use those committed files; deployment does not
need the API repo. Refresh the snapshot explicitly from a pinned API revision,
review changes, and update all three files together. For TypeScript CMS code,
prefer `createClient<Database>` from Web-Dev's pinned `@supabase/supabase-js` and
use the RPCs below; the optional `.mjs` Fetch client has no declaration file.

## Auth and permissions

Web-Dev owns Supabase Auth login/logout, redirect handling, and session refresh.
Reuse one browser Supabase client. Its authenticated queries carry the current
user access token. If using the Fetch helper, pass
`accessToken: async () => (await supabase.auth.getSession()).data.session?.access_token`;
this retrieves a browser token, **not a trusted server authorization decision**.
Server routes must validate the user with `getUser()`/verified claims and must
not trust an unverified cookie/session object. Never cache staff responses publicly.
See [Supabase sessions](https://supabase.com/docs/guides/auth/sessions).

After login and on auth changes call `supabase.rpc('cms_role')` / `api.role()`:
`"editor"`, `"admin"`, or `null` for a signed-in non-staff user. Signed-out callers
cannot execute this RPC. The generated return type currently says `string`; handle
runtime `null` explicitly. A `null` role is access denied, not an empty CMS.
Editors and admins can read all drafts/history and save drafts; only admins may
publish/withdraw. Ordinary users have public reads only. Membership is checked
live in PostgreSQL, independent of user-editable metadata. Role discovery guides
UI controls; it does not replace database permission enforcement.

## Operations to bind

The content key is **`(kind, id)`**, not `id` alone. Kinds are `organization`,
`calendar`, `event`, `layer`, `map`. Preserve unknown payload fields when editing.

| UI action | Existing operation |
| --- | --- |
| Public list | `api.listPublished(kind, {limit:100, offset:0})` or `content` query |
| Published detail | `supabase.from('content').select('*').eq('kind', kind).eq('id', id).maybeSingle()`; Fetch helper has no detail method |
| Draft list | `api.listDrafts(kind, page)`; use projected metadata for large layer lists as below |
| Draft detail | `api.getDraft(kind,id)` returns row or `null`; Supabase equivalent uses `cms_drafts` and both equality filters |
| Save | `api.saveDraft(kind,payload,expectedRevision)` → new revision number |
| Publish (admin) | `api.publish(kind,id,reviewedDraftRevision)` → published revision number |
| Withdraw (admin) | `api.withdraw(kind,id,currentPublishedRevision)` → no useful body |
| History | `cms_history` filtered by both key fields, ordered `sequence.desc`, paginated |
| Map features | `api.layerGeoJSON(id,{limit:500,offset:0,bounds})`; follow `nextOffset` until null |

Exact REST detail form (URL-encode each ID value):
`GET /content?select=*&kind=eq.event&id=eq.ID&limit=1` → array of zero/one rows.
Exact list form:
`GET /content?select=*&kind=eq.event&order=kind.asc,id.asc&limit=100&offset=0`.
Draft metadata list:
`GET /cms_drafts?select=kind,id,revision,updated_at,name:payload->>name,title:payload->>title&kind=eq.layer&order=id.asc&limit=100&offset=0`.

RPC argument names and bodies are in [write RPCs](api.md#write-rpcs). New drafts use
expected revision `0`; subsequent saves use the revision fetched by the editor.
After success, update the local revision from the result. On `40001`, keep unsaved
form values, refetch the latest draft, and offer comparison/reload; do not retry
with the new revision automatically. An edited draft leaves the live snapshot
unchanged. Publish only the draft revision actually reviewed. Withdraw uses the
**published** revision, which can differ from the draft revision.

## Errors and validation

PostgREST failures have `{code, message, details, hint}` (details/hint may be null).
Supabase JS returns `{data,error}`; check `error` before using data. The Fetch client
throws `ApiError` with `status`, `code`, `message`, and `detail` (the original error
object). Network failures can be ordinary Fetch errors. Never assume all failures
have JSON fields or classify permission solely by HTTP status.

Map known cases from the [SQL code table](api.md#write-rpcs): `40001` conflict;
`42501` denied; `23503` dependency/membership; `P0002` missing; `22023`/`22007`/
`22008`/`23514` validation. Publication requires sourced non-sample events,
explicit-timezone start/end, valid calendar/organization membership, no coordinates
for private/virtual events, and valid two-dimensional WGS84 layer geometry.
Dates, coordinates, required-field messages, calendar membership, and feature
ordinal errors can be shown near known controls. **There is no structured
field-path error schema or validation/preflight RPC.** Use a visible form-level
fallback with the server message for unknown cases; do not make brittle message
parsing part of the contract. Incomplete drafts may save but fail publication.

## Publication reaching resident-facing pages

The confirmed delivery requirement is **Astro static output that remains usable
while the API is offline**. Publish/withdraw should trigger a rebuilt/deployed
site; export/build/deploy failure must retain the last successful site. Truly
dynamic browser features always require static fallbacks, never API-only access
to resident-facing content.

The existing database changes atomically on publish/withdraw. Refetch CMS rows
after success, but label that as “Published to API; website update pending” until
a future deployment-status contract confirms success. There is currently **no
automatic rebuild webhook, stable export manifest, or deployment-status endpoint**.
The lead selected trusted GitHub Actions for eventual orchestration; its workflow,
secrets, and environment are not configured yet. CP-Architect owns the additive
contract; see [publishing gaps and agreed direction](publishing-architecture-gaps.md).

Do not switch resident pages to live-only API fetching or replace existing static
content with empty API results. Hosted content remains intentionally unimported.
The initial import/publication and public-site activation require lead coordination.
Current ordered pagination is not a consistent multi-request snapshot; the agreed
future generation/manifest validation must be implemented before relying on it
for concurrent automated exports. No ad hoc browser build hook or secret URL.

## Import readiness / outstanding setup

The [derived repair and import procedure](import-data.md) preserves source bytes,
feature IDs/properties, and provenance. Only elementary features `:5` (Hartley)
and `:10` (Porter) receive hash-gated, boundary-equivalent derived repairs.
No production content writes are authorized in this work.

Remaining setup: configure hosted Auth redirects/provider for the CMS, obtain the
publishable key, complete architect-approved static rebuild delivery, and authorize the initial
staff-token draft import plus admin-reviewed publication. Initial admin membership
already exists. Auth's leaked-password-protection warning remains documented in
[verification](verification.md). API contract is ready for UI integration; report
any required contract additions to API-Dev/team lead before changing it.
