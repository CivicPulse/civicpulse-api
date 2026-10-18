# Matching-version local runtime recipe — proposed, not executed

API candidate remains `be555d9a13ee1c0ca1640c32acbd4d0109175afc` / draft PR5.
Parent recommendation SHA256
`39021d316090507e2f19bc167da17e3ef0f441c67323af2a7e220768fc18b417`.
This owned draft neither starts a new image nor authorizes hosted operations.

## Pinned candidate and bounded preparation

- Platform linux/amd64, image
  `docker.io/supabase/postgres@sha256:e85bc10ac5b141223b289e1e8dc8d448cf3df92501917149db0366b9c5aaf053`.
- Expected config digest `sha256:c4be96218454e68421a29c712e1a83c7a9fe186208c725d8bb2ebb474e2042f2`.
- Published build source `d8666db883fd1bc3bc06654c8db1f8dc39812b82`;
  release ref `cf90815413819eb057a9916c1598692c160ebeb4` is distinct.
- After lead accepts recipe, pull this exact manifest, inspect platform/config
  digest, and create one randomly named labelled **stopped** container for reading
  image files. No image code execution for this first filesystem inspection.
  Copy out only /etc/passwd, entrypoint, PostgreSQL config/includes and init script
  inventory into a private temp directory. No host bind or published port.
- Inspect writes, config include paths, postgres UID/GID, initialization migrations,
  and inherited image volumes before choosing runtime flags. Report required
  writable paths before execution if the following candidate layout is insufficient.
  Do not suppress image init migrations or disable preloads to force startup.

## Candidate runtime envelope (must resolve paths before execution)

Use a separate randomly named rootless Podman container labelled with a unique
fixture UUID, exact digest and `--platform linux/amd64 --pull=never`,
`--network none --read-only --read-only-tmpfs=false --cap-drop ALL`,
`--security-opt no-new-privileges --user postgres --pids-limit 256`,
`--memory 2g --cpus 2 --shm-size 128m --no-healthcheck`.
No host binds, ports, persistent named volumes, privileged mode or host namespaces.

Proposed explicit tmpfs:

| Path | Bound | Mode / ownership | Purpose |
| --- | --- | --- | --- |
| /var/lib/postgresql/data | 1GiB | 0700 actual postgres UID/GID | fresh database only |
| /var/run/postgresql | 16MiB | 0750 actual postgres UID/GID | Unix socket/lock |
| /tmp | 64MiB | 1777 | bounded initialization scratch |

Use nodev,nosuid,noexec for each where compatible; no root-filesystem write.
Stock image command points at `/etc/postgresql`, not PGDATA. Its templates and
`/etc/postgresql-custom` includes may need rendering/writes; metadata alone does
not establish that non-root readonly startup works. Do not mount an empty tmpfs
over configuration and lose image defaults. If needed, propose bounded tmpfs
copies of exact image config with recorded hashes and explicit write requirements
for review, preserving settings. No blanket writable root/root-user fallback.

Only synthetic local fixture password values may be passed to entrypoint; no host
credential/env inheritance. Unix socket stays inside the network-none container.
Allow 120 seconds startup, 15 minutes per SQL lane and 45 minutes overall; resource
or readiness failure stops and preserves a bounded diagnostic report. No resizing
or alternate image without reporting. Verify final server PID/readiness (not init
server), immutable image identity, networknone, readonly root, allowed tmpfs only,
nonroot process and absence of host binds/ports before any tests.

## Runtime admission assertions

From local Unix socket, record version(), server_version_num (require 170011),
installed/available PostGIS versions (require extension3.3.7), extension schema,
postgis_full_version(), loaded/scripts versions and GEOS/PROJ. A separate disposable
database may install the image's available PostGIS extension for this assertion;
no hosted extensions are touched. Mismatch stops rather than relabeling evidence.
Record all role flags/memberships (no password columns), current/session_user,
encoding/collation/locale provider, shared/session preloads and relevant supautils
settings. Distinguish image-managed postgres from bootstrap owner and superuser.
No role widening merely to make tests pass; initialization collisions are reported.

## Harness adaptation and sequential lanes

Existing populated-upgrade harness hardcodes generic PostGIS16 and container;
full SQL runner accepts a container but has no equivalent strict image admission.
Implement a separate fixed-digest adapter/guard, not a generic DB URL or bypass.
Pass only the verified random container to existing concurrent test functions.
Use a clean archive of be555d9 and preserve exact SQL/test bytes; any adaptation
must be separately diffed, tested and frozen. Never replace shared test container.

1. Populated four-hosted-migration baseline then all13 exact missing migrations,
   sequentially. Preserve row/catalog comparisons and prepared warm v1 calls.
   Use actual guarded session identities for source/baseline/claim/deploy/status
   scenarios, not owner-seeded receipt authority.
2. Full security/publication/privacy/URL/manifest/status/dispatch/build/deployment
   SQL and actual-role denials; existing claim, dispatch and three deployment
   concurrency tests. Run after upgrade lane, not overlapping cluster-wide roles.
3. Existing status upgrade unique/ambiguous/missing acknowledgment controls.
4. Existing geometry/GeoJSON/bbox/invalid polygon checks and full reviewed Web
   import graph using a separately pinned clean Web archive and source provenance.
   Record actual counts and privacy results; do not assume historical935 applies.
   No sibling mutation or hosted request; only the disposable database receives
   test imports. Preserve raw source snapshots and hash-gated derived repairs.

Report each command, archive/adapter/source hashes, actual versions, roles,
geometry library versions and results. Label managed-role mismatch separately;
version match is not hosted build/config/pooler parity. No provider acquisition,
TLS identity, credentials, bootstrap or deployment authority follows.

## Cleanup and handoff

Remove only exact created containers after inspecting UUID label, digest, mounts
and network. Never select containers by broad prefix. Tmpfs data disappears on
removal; retain bounded reports in a private temp directory, no credential values.
If cleanup is unknown, inspect exact objects before any retry. Existing shared
containers and repo source remain untouched. Send concrete startup/path disposition
through lead before new image execution; Security reviews metadata independently.

## Proposed execution stage after artifact inspection (HELD)

Artifact inspection at recipe commit `01f8bdb` found OS postgres UID100/GID101,
concrete readable config, and no init-script config-file writes. Inventory is
`/tmp/civicpulse-runtime-inspection-4id5i8u2/inventory.json`, SHA256
`7730d54c1a4b03edb391b1322d3eff74896862ceb747b5d7002caa54f515e578`.
The stopped inspection container was removed without start/exec. This amendment
is proposed for focused review; it does not extend the earlier inspection approval.

The proposed argv (NAME and UUID are generated once and recorded before create;
all other values fixed) is:

```text
podman create --pull=never --platform linux/amd64
  --name NAME --label org.civicpulse.rehearsal=UUID
  --network none --read-only --read-only-tmpfs=false
  --user 100:101 --cap-drop ALL --security-opt no-new-privileges
  --pids-limit 256 --memory 2g --cpus 2 --shm-size 128m --no-healthcheck
  --tmpfs /var/lib/postgresql/data:rw,nodev,nosuid,noexec,size=1g,uid=100,gid=101,mode=0700
  --tmpfs /var/run/postgresql:rw,nodev,nosuid,noexec,size=16m,uid=100,gid=101,mode=03775
  --tmpfs /tmp:rw,nodev,nosuid,noexec,size=64m,mode=1777
  --env POSTGRES_PASSWORD=local-disposable-runtime-only
  docker.io/supabase/postgres@sha256:e85bc10ac5b141223b289e1e8dc8d448cf3df92501917149db0366b9c5aaf053
```

No command/entrypoint override: preserve `docker-entrypoint.sh`, image
`POSTGRES_USER=supabase_admin`, default database, initdb ICU arguments and
`postgres -D /etc/postgresql`. Preserve every image init script and preload,
including final `ALTER ROLE postgres NOSUPERUSER ...`. No extra config tmpfs or
rendering currently justified. Socket mode matches entrypoint chmod03775. The
synthetic password is intentionally public test data, has no hosted meaning, and
is confined to this network-none container. Do not inherit host DB env values.

After create, separately inspect exact ID/digest/label/platform/created state,
readonly flag, user100:101, security options, limits, three exact tmpfs, no bind
mounts/published ports. Stop on unexpected inherited mounts. Only after this gate
passes may the separately approved stage issue `podman start EXACT_ID` once.
Readiness: bounded120s, inspect running/nonroot identity and final PID1 command
`postgres -D /etc/postgresql`, then socket pg_isready plus SQL connection. A
successful temporary initialization server is insufficient. Inspect logs for
completion and successful terminal demotion, not merely socket availability.
Failure retains bounded logs and stops; never disable preloads/init or elevate OS
user to get past it. The key helper/preload runtime may reveal additional paths;
report exact errors before any runtime-envelope change.

### Setup administrator versus production migration identity

Use the image-created **supabase_admin** only as the explicitly privileged local
harness administrator. Do not create another superuser or promote postgres.
Record before/after role flags and membership edges. Assert postgres.rolsuper=false,
supabase_admin.rolsuper=true; record postgres CREATEDB/CREATEROLE/BYPASSRLS rather
than changing them. No fixture grants to anon/authenticated/service_role beyond
reviewed setup/migrations. Image managed roles are retained, not recreated with
simpler attributes. Existing bootstrap duplicate-role handling must also assert
that those roles match the intended test identity and do not inherit administrator.

Use separate connection lanes, never one owner connection for everything:

1. `psql -X -U supabase_admin` over the local socket: create only random fixture
   databases owned by postgres, minimal synthetic Auth fixtures in those databases,
   and test-only NOLOGIN machine identities/registry setup as needed. This lane may
   perform owner-seeded *test setup*, never substitute provider receipt admission.
   Setup Auth schema/table/uid can be created under SET ROLE postgres, with catalog
   assertions; do not replace the managed postgres database's real Auth objects.
2. `psql -X -U postgres` fresh direct connection: assert current_user=session_user
   ='postgres' and rolsuper=false, then execute each unchanged production migration.
   Extensions use the image's supported supautils behavior. Do not catch permission
   errors and rerun as supabase_admin, ALTER OWNER afterward to disguise origin,
   or add privileges. Any incompatibility is a reported migration finding.
3. `psql -X -U supabase_admin` test orchestration: privileged setup assertions and
   test fixture mutation only; before each guarded RPC use the existing actual
   SET SESSION AUTHORIZATION target boundary and assert session_user=current_user
   equals the intended NOLOGIN staff/machine identity and rolsuper=false. RESET
   returns to the explicitly recorded administrator. Original test scripts rely on
   superuser initial login for this switch: it must not be mistaken for postgres
   production migration permission. Negative cases must execute after switching.

Temporary pg_temp test assertion functions may belong to the harness administrator;
production public/civicpulse/civicpulse_delivery functions and tables must retain
postgres ownership. Catalog checks before/after suites assert proowner/relowner,
SECURITY DEFINER flags, empty search_path, ACLs/RLS and absence of accidental
administrator ownership. Test-only identity diagnostic statements can prove
session_user/current_user before RPC; production function owners plus definer
catalog establish internal owner identity without altering production functions.

The warmed-upgrade lane needs explicit adaptation: keep the original prepared
publish call in its harness connection under authenticated session authorization,
perform production DDL through separate direct postgres connections, then reuse
the warmed call. Preserve transactional row/manifest rollback assertions; do not
run migration placeholders under the harness superuser. Concurrent helpers must
likewise separate fixture setup identity from actual machine session identity.
Freeze and review these adaptations, rather than reporting untouched harness
compatibility. Existing stock scripts cannot yet be claimed to pass this lane.

Before any suite, assert PG170011 and loaded PostGIS3.3.7 in a random postgres-owned
database, record full dependencies, extension placement, locale and preloads. Fail
closed on startup/version/permission/ownership drift. Full role/geometry/upgrade
lanes remain sequential and separately evidenced; no hosted/pooler equivalence.
