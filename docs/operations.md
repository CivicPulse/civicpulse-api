# Operations

## Hosted project

CivicPulse: `drzcrodqflzkzzbqsags`, region `us-west-2`. Database schema changes live
in `supabase/migrations`. PostGIS is installed in `extensions`; internal content
and staff tables live in the non-exposed `civicpulse` schema. Expose only `public`
through the Data API. Do not add `civicpulse` or `extensions` to exposed schemas.

RLS is enabled on every internal table. Public views use `security_invoker`.
Clients have read grants only; checked write implementations use narrowly scoped
security-definer functions in the private schema. Public wrappers are invokers.
Every privileged entry point checks an authenticated UUID and database membership.
User-editable metadata is never consulted for authorization.

## Staff

Create or invite users through Supabase Auth, then assign membership using the SQL
editor as the project operator. Do not create a public signup-to-admin trigger.
The initial admin UUID supplied by the project owner is
`fb169f7b-5947-444c-93d0-999ba21bd8ec`.

```sql
-- Substitute a real Auth user UUID. Assign only an intended staff user.
insert into civicpulse.members(user_id,role)
values ('AUTH_USER_UUID', 'editor')
on conflict(user_id) do update set role=excluded.role;

-- Revoke editorial access immediately:
delete from civicpulse.members where user_id='AUTH_USER_UUID';
```

Membership management intentionally remains an operator action; there is no
browser endpoint to promote oneself or other users. Deleting an Auth user removes
their membership and nulls historical actor references, preserving content.

Configure hosted Auth redirect URLs for the CMS origin and local development,
disable open signups, and configure the chosen login provider/email delivery.
Local `supabase/config.toml` is not automatically applied to hosted Auth settings.
Never paste passwords, access tokens, service-role keys, or database passwords
into tracked files. The publishable key is suitable for the frontend; staff access
tokens are short-lived user credentials. CLI imports use those user credentials.

## Migrations

```sh
npm run supabase -- link --help
npm run supabase -- db push --help
# Then link to the intended project and inspect a dry run before pushing changes.
```

Check the installed CLI help for available flags. Do not reset the hosted database.
If applying an initial migration through the connected Supabase tool, it records
remote migration history with a generated timestamp. Reconcile the local filename
with that recorded version before subsequent CLI pushes; do not apply the same
DDL twice. Run security/performance advisors after deploying changes.

## Data safety

Imports are opt-in and create drafts only. A rerun never overwrites edits. Publish
records in dependency order after reviewing sources. SQL transactions make
publication, dependency updates, feature replacement, and audit history atomic.
Failed publication leaves the prior public version intact.

The history table preserves each draft save and publication. It is an editorial
audit trail, not a replacement for database backups. Large GeoJSON revisions retain
full source payloads and can grow storage substantially; establish a retention
policy and backup schedule before sustained large dataset ingestion.

Known source audit results and deployment verification are recorded in
`docs/verification.md`. Invalid source geometry must be reviewed rather than
silently fixed by an import. Broader indicators, scheduled source ingestion,
notifications, and the Astro CMS interface are separate work from this API.
