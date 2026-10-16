# Existing-target admin MVP: bounded hosted plan

**Application completed under explicit Lead instruction; postchecks below.** The original pre-application evidence and approved plan are preserved here. Only the two specified guards were applied. Content/Auth/browser QA is a separate next step.

2026-10-16. User accepts existing unused site/project for synthetic testing. This plan is prepared for Security/Lead clearance; it does not itself authorize hosted migrations or content writes. No separate backend, automated delivery pipeline or 935-record import is required.

## Read-only hosted evidence

Connected Supabase tools inspected project `drzcrodqflzkzzbqsags`: ACTIVE_HEALTHY, PostgreSQL17.11.0.003. Migration history contains exactly `20261016195541_civicpulse_content_api` and `20261016195619_restrict_platform_trigger_execution`. Public and draft counts are both0. There is one staff membership: initial user `fb169f7b-5947-444c-93d0-999ba21bd8ec`, admin, email confirmed, password set, not deleted, no ban timestamp. Password/session values were not read or printed. Browser login is unverified and requires the user to sign in normally.

Read-only public `/auth/v1/settings` returns email enabled, signup enabled, email autoconfirm false, phone disabled. Site URL/redirect allowlist were not available through these connector calls and remain unverified. Existing password sign-in does not require adding OAuth. Invite/reset flows need correct [Auth redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls); no Auth/signup/identity change is included in this plan. Advisor reports only [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), not a new grant/RLS finding.

Hosted public cms_role/save_draft/publish/withdraw are invoker wrappers, empty search_path, postgres-owned, anon denied and authenticated EXECUTE allowed; internal write functions are definer, same owner/search_path, authenticated EXECUTE allowed, with live role checks. All six civicpulse tables have RLS; authenticated has no direct INSERT/UPDATE/DELETE. Public content/cms_drafts/cms_history views are security_invoker; anon cannot read drafts/history. Existing wrapper argument names match frozen Web v1. Private-address/URL helper and publication manifest are absent.

Browser-safe URL/key plus PUBLIC_CONTENT_SOURCE=local were handed to Web through `/tmp/civicpulse-mvp-public.env`, mode0600, not Git/chat. Web alone writes Web config. No service-role key is needed. Resident pages stay static/local; admin publish changes the public API, not the resident build.

## Exact minimal delta and application route

Apply ONLY these unchanged reviewed files in this order:

| Logical migration | SHA256 | Effect |
| --- | --- | --- |
| `20261016204146_private_event_publication_validation.sql` | `e0724ebcf95c054eb8dea07b906eeef62fd5b0c0f7ddb04e66f6cb065290c7e3` | Adds private-event validation; renames original validator to validate_publication_v1 and installs guarded wrapper; no content rewrite |
| `20261016210355_private_event_source_url_v1.sql` | `4befbfb36f802839b5c42e94e80c08165a4a8b62c066604a7377e2a116485ac0` | Adds strict shared URL predicate; replaces private validator with final reviewed implementation |

Dependencies: only original v1 and platform trigger restriction. Explicitly omit `20261016203213_publication_generation_manifest`, `20261016215623_delivery_identity_status_foundation`, `20261016220416_delivery_dispatch_leases`, `20261016221834_receipt_manifest_structure`. Source helper code is not a migration. Never run blanket db push/migration up against this checkout.

After scoped Security/Lead clearance, API-Dev uses connected `supabase_apply_migration` on exactly project `drzcrodqflzkzzbqsags`, first name `private_event_publication_validation`, then `private_event_source_url_v1`; each query is byte-for-byte the corresponding hashed file. Before each, reread remote migration list/catalog, confirm unchanged preconditions and hash. First requires existing validate_publication and absent validate_publication_v1/private helper; second requires first completed and URL helper absent. No users, roles, policies, content rows or unrelated functions are changed. Block publication/browser write QA until BOTH succeed.

The tool records generated migration versions. Capture each returned/listed remote version and name, check exact applied statement bytes/hash through migration history where available, and record the original-to-hosted mapping. Reconcile local filenames to actual remote versions by an API-owned rename-only commit, updating the subset harness names; SQL bytes remain unchanged. Verify remote versions preserve base-before-first-guard-before-second-guard ordering before renaming. If ordering/recorded bytes or history differ, stop for explicit reconciliation; do not fabricate success, delete history, rerun the rename migration, or mark omitted delivery migrations applied. Future broad migration application remains gated even after this bookkeeping.

Failure/recovery: migration transaction failure stops immediately; inspect catalog/history before retry, never assume timeout means rollback. If first committed but second failed, retain stronger private guard, halt publication QA and diagnose/retry ONLY the URL migration once state is known. Never automatically restore privacy-open v1, drop the guards or erase existing data. No down migration is proposed. Any corrective DDL needs a bounded reviewed follow-up.

## Local proof and immediate hosted postchecks

`node scripts/test-mvp-db.mjs` creates/drops a disposable local database, applies only the four named migrations and runs actual anon/authenticated/admin/editor/nonstaff checks. One backend prepares and executes public.publish before guard DDL, then reuses that prepared call after DDL: unsafe private event rejects22023, no public event appears. This demonstrates the warmed session path locally; no claim about finishing transactions already in progress during DDL. Schedule the hosted upgrade before interactive write QA.

The same run checks helper/validator postgres ownership, INVOKER flags, empty search_path, no PUBLIC/anon/authenticated EXECUTE; reuses the private-event publication suite and exact URL corpus plus boundary fixtures (20 accepts,81 rejects including raw NUL represented separately). For the v1-only subset, test-local content/GeoJSON snapshots replace unavailable delivery manifest/outbox observers; this proves content/history/features safety, not delivery behavior. Explicit assertions require delivery schema/manifest absent. Local run passed after two harness-only corrections (replacement-string dollar escaping, leftover delivery-only assertion); migration bytes were untouched.

Immediately after hosted application: list migrations, verify exactly two additions; inspect four validator/helper signatures/owners/ACL/search_path and original public RPC signatures/grants; verify all existing RLS/security_invoker/direct-write restrictions unchanged; recheck draft/public counts and initial admin membership; rerun security advisor. No content mutation is part of this postcheck phase. Anonymous HTTP content read should remain successful and draft/write access denied. Hosted warm-session/publication mutation QA follows only the separately coordinated synthetic-content step.

## Bounded browser QA and retention proposal

After guard postchecks and coordinated authorization, the user signs into `/admin` with existing account privately. Verify role admin, page reload/session refresh/logout, then use one run-specific namespace (UUID) with exact three planned keys: organization, calendar, event. Precheck each(kind,id) absent in drafts and published content; stop on collision. Record every successful returned draft/public revision. Create/publish organization then calendar; event uses clearly synthetic public text, example.org provenance, explicit timezone, canonical private placeholders, no coordinates and sample=false because v1 intentionally rejects sample=true. No real/private addresses or mass import. Save a deliberately invalid synthetic private draft and verify publication rejects22023 while the previous public revision stays unchanged; save/review sanitized content again. Exercise stale-revision40001 without automatic overwrite. Role-denial coverage remains local unless a separate editor/nonstaff test identity is explicitly authorized; do not change the existing admin membership.

If withdrawing QA artifacts is authorized, withdraw only exact created published revisions in event→calendar→organization order after confirming ownership ledger and current revision; collision/concurrent change stops cleanup. No delete RPC exists: withdraw retains draft/history. Retaining clearly labeled synthetic drafts/history is the default proposed outcome. No broad-prefix delete, destructive cleanup or user/data reset is authorized. Resident refresh remains disabled and is a separate milestone from successful API publication.

## Completed hosted application and postchecks

Security independently cleared frozen plan/harness `f415c0646d3cddcd008665d541918a18068b7b7e`; Lead then explicitly instructed these two connected migrations only. Both `supabase_apply_migration` calls on `drzcrodqflzkzzbqsags` returned `{success:true}` after their respective catalog/history/hash prechecks. Stored history has one statement per migration:

| Original version | Hosted/reconciled version | Stored bytes | Stored SHA256 |
| --- | --- | --- | --- |
| `20261016204146` | `20261016231409` | 4514 | `e0724ebcf95c054eb8dea07b906eeef62fd5b0c0f7ddb04e66f6cb065290c7e3` |
| `20261016210355` | `20261016231420` | 4979 | `4befbfb36f802839b5c42e94e80c08165a4a8b62c066604a7377e2a116485ac0` |

Database `encode(sha256(convert_to(array_to_string(statements,E'\n'),'UTF8')),'hex')` exactly matches each approved local file hash. History is original base→trigger restriction→private guard→URL guard, with exactly four entries. Rename-only commit `4a9a4c5` reconciles local filenames (100% identical SQL). Subset harness now follows the reconciled names. Delivery migrations remain local/unapplied; do not use blanket push or infer their approval from local filename order.

API postchecks: all four helpers/validators postgres-owned, INVOKER, empty search_path, no PUBLIC/anon/authenticated EXECUTE. Original public RPC argument signatures/invoker ACLs and internal definer write boundaries unchanged. All six internal tables retain RLS and authenticated direct-write denial; three public views retain security_invoker and staff-view anon denial. Public/draft counts remain0; one unchanged confirmed/password-set admin, no ban/deletion. Delivery schema and manifest remain absent. Advisor returns only the preexisting leaked-password-protection warning. Security independently repeated hosted catalog/history/hash/count checks and reported no confirmed regression.

Anonymous HTTP using only the browser publishable key, no user token: `/rest/v1/content?select=kind,id&limit=1` returned200 with0 rows; draft/history reads and `/rest/v1/rpc/cms_role` returned401/code42501. No write RPC was invoked by these postchecks. No content, Auth setting, identity/member or site deployment change occurred in this application phase. Real authenticated browser/session and synthetic write QA remain pending coordination.
