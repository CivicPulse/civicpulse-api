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


## Syntax correction proposal after failed create (HELD)

The f3c9531 attempt failed during create with `unknown mount option "uid=100"`.
Exact-name reconciliation confirmed absence; no image code/SQL ran. This was
mount-parser compatibility, not a PostgreSQL or migration failure.

Installed local client/engine: Podman5.8.7, API5.8.7, commit
`c593b672bf3db1173aebea565ebf1a724ea196dc`, Linux/amd64, rootless=true,
ServiceIsRemote=false, configured connections empty. Installed
`/usr/share/man/man1/podman-create.1.gz` documents `--mount type=tmpfs`
`U`/`chown` as setting tmpfs uid/gid from the container user, non-recursively;
`tmpfs-size`, `tmpfs-mode` and `notmpcopyup` are documented too. See also
[official create documentation](https://docs.podman.io/en/latest/markdown/podman-create.1.html).
No create/run syntax experiments were used.

Replace only the three mount arguments in the preceding full argv with:

```text
--mount type=tmpfs,destination=/var/lib/postgresql/data,tmpfs-size=1073741824,tmpfs-mode=0700,U=true,notmpcopyup
--mount type=tmpfs,destination=/var/run/postgresql,tmpfs-size=16777216,tmpfs-mode=03775,U=true,notmpcopyup
--mount type=tmpfs,destination=/tmp,tmpfs-size=67108864,tmpfs-mode=1777,notmpcopyup
```

This explicitly requests mount-root ownership100:101 from unchanged `--user100:101`
for PGDATA/socket; `/tmp` remains the default root-owned sticky scratch mount.
It does not recursively chown anything or touch a host bind/persistent volume.
`notmpcopyup` explicitly selects empty ephemeral mounts: the old --tmpfs spelling
must not accidentally be replaced by --mount's default image-directory copy-up.
No config path is shadowed. Require resolved rw/nodev/nosuid/noexec on all three
mounts in created config; stop if the engine defaults differ, rather than silently
accepting executable or device-capable scratch. All other reviewed argv, bounds,
entrypoint/init/preloads/managed-role demotion and cleanup remain unchanged.

### Configured versus effective ownership admission

Before start, inspect the exact created container and OCI mount specification:
require three exact tmpfs destinations/byte sizes/modes, uid100/gid101 for the two
owned mounts, no copy-up, rw/nodev/nosuid/noexec, plus all earlier image/user/network/
resource/security invariants. This checks configured intent ONLY: an unstarted
tmpfs is not yet mounted, and container inspect is not an effective stat result.
If the supported inspection output cannot expose resolved ownership/options,
report that gap before start rather than claiming the check passed.

After the separately authorized one start, permit ONLY these explicit non-mutating
in-container diagnostic commands (same default OS user100:101, no user override):

```text
podman exec EXACT_ID stat -c '%u:%g %a %n' /var/lib/postgresql/data /var/run/postgresql /tmp
podman exec EXACT_ID cat /proc/1/status /proc/1/cmdline /proc/1/mountinfo
```

These run only while the container is running, within the120s admission deadline.
They do not replace or wrap the stock entrypoint, perform chown/chmod, or run test
suites. Require effective PGDATA100:101 mode700, socket100:101 mode3775, scratch
0:0 mode1777, and tmpfs mountinfo rw/nodev/nosuid/noexec for all three. Record
observations once early and again after final readiness to catch init changes.
Assert PID1 Uid/Gid100/101, no effective capabilities and NoNewPrivs1. If init exits
before diagnostics, capture bounded logs/exit state and stop; do not restart.

Final PID/ready socket checks and PG/PostGIS/role admission remain as previously
reviewed, but SQL admission waits for effective filesystem checks to pass. Neither
configured nor effective mount admission constitutes managed role or version proof.
No adapted suite is authorized by this syntax proposal. Any discrepancy halts for
read-only diagnosis and exact owned-container cleanup. No root/mode widening,
privilege fallback, provider call or hosted operation.


## Explicit noexec and ownership-intent correction (HELD)

Supersedes only the preceding replacement mount argv and created ownership gate.
The b7a7667 attempt created a stopped container but inspect lacked noexec on all
three mounts. It was removed without start/exec. This is a prestart configuration
failure, not SQL/runtime failure. Evidence:
`/tmp/civicpulse-runtime-admission-v2-zeaxxepv/inspect.json` and `gate.json`.

Exact replacement arguments now request noexec explicitly:

```text
--mount type=tmpfs,destination=/var/lib/postgresql/data,tmpfs-size=1073741824,tmpfs-mode=0700,U=true,notmpcopyup,noexec
--mount type=tmpfs,destination=/var/run/postgresql,tmpfs-size=16777216,tmpfs-mode=03775,U=true,notmpcopyup,noexec
--mount type=tmpfs,destination=/tmp,tmpfs-size=67108864,tmpfs-mode=1777,notmpcopyup,noexec
```

Installed5.8.7 create manual documents tmpfs U/chown, size, mode, copy-up and
noexec filesystem semantics. Its tmpfs default wording did not describe observed
--mount resolution, so no default-exec inference is used. The upstream
[shared mount-option parser](https://github.com/containers/podman/blob/main/pkg/specgenutil/volumes.go)
explicitly accepts bare noexec for memory mounts; this corroborates spelling,
not exact installed binary behavior (installed commit source fetch unavailable).
No guessed create/run trial was performed. The approved future create must itself
prove resolved noexec, nodev, nosuid, sizes and modes before start; unsupported
syntax or missing flags means stop and reconcile, never substitute exec.

Created-state checks require Config.User100:101 plus U on PGDATA/socket as
**configured ownership intent**. Numeric uid/gid and OCIConfigPath may not exist
before mounting; null unstarted OCIConfigPath is not a failure or effective-owner
proof. Require exact image/label/created state, no binds/ports, readonly root,
nonroot user, cap-drop/NNP/resource bounds, unchanged entrypoint/init/preloads,
and three exact tmpfs configured paths/sizes/modes and noexec/nosuid/nodev flags.
Retain the exact original argv proving notmpcopyup even if inspect normalizes it.
No start if these observable configured invariants fail.

After the separately gated single start, the already specified stat/proc/mountinfo
diagnostics are mandatory **before SQL**. Require effective PGDATA100:101/700,
socket100:101/3775, scratch0:0/1777; tmpfs rw/noexec/nosuid/nodev; PID1uid100/gid101,
zero effective capabilities and NoNewPrivs1. Record early and final-ready values.
All readiness/timeouts/role-demotion/admission/cleanup restrictions remain intact.
No root fallback, widened modes, init changes or additional diagnostic command.
Runtime execution remains held for exact revision review and lead instruction.

## Single-file disposable key proposal (HELD)

The 369b4ca attempt passed created-config gates, started once, then exited1 during
the temporary server's pgsodium preload: writing
`/etc/postgresql-custom/pgsodium_root.key` failed on readonly root and the server
reported invalid secret key. No admission SQL or final managed demotion ran.
Exact container was removed/absence verified. Socket path warning remains open.

A separately authorized stopped-only inspection copied the helper without running
it. SHA256 `359296e6e9d3ceb2f110e10f4f7c43d878b3bf339b4cd67a6c1b9b02d2044e43`.
Evidence `/tmp/civicpulse-key-inspection-xq4xir6a/`: helper, stopped inspect and
33-entry config-directory metadata inventory; no key file present in image.
Tar-header ownership is transport metadata, not an effective running stat claim.
Inspection container a6b8b44c... was never started, removed and confirmed absent.

Helper semantics: fixed KEY_FILE above; if not a regular file, generate32 random
bytes as64 hex characters without newline and write it; then cat that file.
It needs no directory write if the file already exists. Preserve helper bytes,
original preloads/init and all other config files. Do not execute the helper as a
diagnostic because its stdout is key material.

Propose the installed documented Podman **mount secret** mechanism, not a host
bind or whole-directory tmpfs. Add exactly one argument to the reviewed argv:

```text
--secret SECRET_NAME,type=mount,target=/etc/postgresql-custom/pgsodium_root.key,uid=100,gid=101,mode=0400
```

SECRET_NAME is a new recorded UUID-based local name, absent precheck required.
Podman5.8.7 installed create manual supports absolute target paths and numeric
uid/gid/mode for mount secrets. No secret mutation after container creation.
The engine stores a temporary secret resource: this is an explicit additional
owned resource to review, not a claim it is automatically removed with tmpfs.
No production secret, external account, host bind or persistent data volume.

After exact recipe approval only, generate `secrets.token_hex(32)` in the host
process and pass its64 ASCII bytes directly to `podman secret create NAME -`
through subprocess stdin, no shell interpolation, newline, file, env or logging.
Record only returned ID/name and metadata (never inspect --showsecret). No key
bytes or key hash in the report. Fail/unknown result uses exact-name metadata
reconciliation, never duplicate retry. All ordinary image/container checks remain.

Created-state gate additionally checks one exact secret reference/name/ID, target,
uid100/gid101/mode0400; no other secrets/mounts, no config-directory shadowing.
Before start record `podman diff EXACT_ID`; only an explicitly reported single key
mount placeholder and its necessary metadata, if visible, may differ from baseline.
Unexpected config-file changes stop. Do not claim diff proves mounted secret bytes:
engine-managed mount content can be absent from overlay diff.

After the gated single start, extend the already approved stat diagnostic ONLY by
adding `/etc/postgresql-custom/pgsodium_root.key`. Require a regular file,100:101,
0400 and64 bytes; use `stat -c '%F %u:%g %a %s %n'` for this one path. Do not cat,
read, hash, trace or invoke the key helper. Record its mountinfo entry read-only and
no whole-directory overlay; keep root readonly and all3tmpfs noexec/nodev/nosuid.
Retain bounded before/after container diff and metadata; no secret output. If the
engine cannot provide these protections, halt rather than loosen permissions.

Cleanup always handles both exact owned resources: close/stop only the recorded
container if needed, verify ID/label/image, remove it, verify absence, then remove
only the recorded secret ID after metadata name/ID check and verify absence.
If create/start/cleanup result is unknown, inspect those exact IDs first. Never
prune secrets or remove by prefix. Preserve failures and report residual resources.
No runtime attempt, key generation, or secret creation has occurred for this proposal.

Socket warning: Podman reported missing `/var/run/postgresql` while parsing user
volumes after start. It may reflect a canonical-path alias but this has NOT been
established. Do not silently switch mount paths. Before next runtime approval,
resolve image `/var/run` link metadata through a separately permitted stopped-only
metadata read (or equivalent exact published image-source evidence), then require
one intended effective socket tmpfs in mountinfo and stat through its configured
path. Report if a canonical target amendment is required; this proposal does not
change socket path, modes or admit missing proof. No SQL until all effective gates.

## Combined canonical socket + single-file key recipe (HELD)

Stopped image metadata inspection conclusively records `/var/run` as symlink
`../run`, `/run` directory0755/root, `/run/postgresql` directory0755/100:101.
Evidence `/tmp/civicpulse-socket-inspection-mqlvur3t/canonical-metadata.json`.
`podman cp` dereferenced the requested root link; a streamed export retained ONLY
these three metadata headers (no file contents), preserving the link itself.
The sole labelled inspection container was never started and was removed/absence
verified. No key was generated or read.

The ONE combined proposal now uses the full original constrained argv with these
four replacement/additional arguments; all other flags/entrypoint/config remain:

```text
--mount type=tmpfs,destination=/var/lib/postgresql/data,tmpfs-size=1073741824,tmpfs-mode=0700,U=true,notmpcopyup,noexec
--mount type=tmpfs,destination=/run/postgresql,tmpfs-size=16777216,tmpfs-mode=03775,U=true,notmpcopyup,noexec
--mount type=tmpfs,destination=/tmp,tmpfs-size=67108864,tmpfs-mode=1777,notmpcopyup,noexec
--secret SECRET_NAME,type=mount,target=/etc/postgresql-custom/pgsodium_root.key,uid=100,gid=101,mode=0400
```

This changes socket mount destination to the proven canonical directory only.
The image config/entrypoint still uses `/var/run/postgresql`, reaching the same
mount through its original symlink; do not rewrite either. Created checks expect
`/run/postgresql`, same size/mode/U/flags. Effective diagnostics stat BOTH socket
spellings with `%d:%i` as well as owner/mode and require identical device/inode;
mountinfo must show exactly one socket tmpfs at canonical `/run/postgresql` with
rw/noexec/nodev/nosuid. No alternate socket or wider `/run` mount is permitted.

Single-secret generation/metadata/mode0400/read-only-file mount/container-diff and
exact container-then-secret cleanup remain exactly the preceding proposal; no
whole-directory overlay. Effective key stat includes regular-file type, size64,
owner100:101/mode400, never values/hash. Poststart diagnostic augmentation is
explicit: stat both socket paths for device/inode equality and the one key path
for metadata only; prior proc checks unchanged. All filesystem/process admission
must pass before SQL, with same120s bound, no privilege/init/preload fallback.
This combined recipe awaits Security and lead approval before secret/create/start.

## Explicit bounded POSIX shared memory amendment (HELD)

The dd5e5f64/v4 admission attempt loaded pgsodium and vault keys, then failed
opening a PostgreSQL POSIX shared-memory segment with readonly-filesystem error.
No final runtime/effective mountinfo/SQL admission was obtained. Exact container
and synthetic secret were removed with absence checks. Evidence is retained in
`/tmp/civicpulse-runtime-admission-v4-4f1g1yj9` (no key values or hashes).

Installed Podman5.8.7 create manual states read-only plus read-only-tmpfs=false
marks /dev and /dev/shm readonly; shm-size sets capacity, not writability. The
retained config/shared-memory error supports this cause, not direct failed-run
mountinfo proof. Preserve PostgreSQL config and dynamic shared-memory selection.

Add ONE exact mount argument to the complete combined canonical-socket/key argv:

```text
--mount type=tmpfs,destination=/dev/shm,tmpfs-size=134217728,tmpfs-mode=1777,rw,notmpcopyup,noexec,nodev,nosuid
```

Installed --mount tmpfs size/mode/copyup and common read-write/noexec/nodev/nosuid
options are used. Keep --shm-size128m, --read-only-tmpfs=false, readonly root,
user100:101, cap-dropALL/NNP/networknone and all other mounts/resources unchanged.
No writable whole /dev,/run or alternate memory mode; no hostIPC/user change.

Created gate requires exactly FOUR explicit tmpfs targets: earlier three plus
this sole /dev/shm134217728/mode1777/rw/noexec/nodev/nosuid, no copyup, and no
additional unnamed shared-memory volume. If engine representation conflicts or
omits flags, halt before start. Effective poststart diagnostic explicitly adds
`/dev/shm` to stat (root0:0/mode1777 directory) and requires exactly one canonical
mountinfo entry, tmpfs rw/noexec/nodev/nosuid, size131072k or equivalent134217728
bytes. Retain actual flags/size rather than infer them from --shm-size. All existing
key/socket/PID1/capability/NNP/readiness gates precede SQL and remain mandatory.
No retry on failure. This amendment needs exact Security/lead approval before
another secret/create/start; full adapted suites and hosted actions remain excluded.
