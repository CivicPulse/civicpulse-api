# Live admin MVP browser QA — 2026-10-16

Controlled run `1ade89ae-0a43-4818-a715-a2e2a8fc0531`, project `drzcrodqflzkzzbqsags`. Web-Dev owns browser writes/ledger; API-Dev performs independent read-only SQL. User signed into live `https://www.civpulse.org/admin/` as the existing administrator. Web reports production artifact `bb7213e1-4891-479d-9c90-97fdf66d598b`, source `d74a4a02564f283e8b831d1f12290e9945350fd1`. No session/password/token transfer occurred. Resident source stays local and automatic refresh is disabled.

Exact retained keys are:

- organization: `admin-mvp-1ade89ae-0a43-4818-a715-a2e2a8fc0531-organization`
- calendar: `admin-mvp-1ade89ae-0a43-4818-a715-a2e2a8fc0531-calendar`
- event: `admin-mvp-1ade89ae-0a43-4818-a715-a2e2a8fc0531-event`

API prechecks twice confirmed all three absent in drafts/public; baseline total published count0. No second fixture set was created. SQL hashes below use SHA256 of PostgreSQL JSONB payload text, not browser JSON serialization.

## Confirmed checkpoints

| Record | Draft revisions observed | Published revision | Public payload SHA256 |
| --- | --- | --- | --- |
| organization | 1 | 1 | `ba0eb15ac37a3fc6800666f832cad583e7371a85b5f82d0776ccb7faf5a7bce8` |
| calendar | 1 | 1 | `36364cdb9377b5392d9e8abed52aa25f6af00c6afa03edfb84359375fb1a9fd2` |
| event | 1 through5 | 1 | `791e12c8884a4c30e1f7835b4a386b7f107245fd6e2c280a6a44e5dff482bf0c` |

Organization/calendar/event revision1 each have exactly one save and publish audit action: sequences20/21,22/23,24/25. All actors match the initial admin. Initial draft and public hashes matched for each. Event public payload has both canonical private-location placeholders, no coordinates, and no associated geometry; feature count remains0 throughout observed checkpoints.

Web saved invalid synthetic event address as draft2, then observed the canonical-placeholder rejection on publication. API independently confirmed public revision1/hash unchanged, only save2 audit sequence26, no publish2 or feature mutation. Draft2 hash was `d1612afa47e266fc4ee7dd9512f9d2e69bf7d79270585a5d055bb3f7ef2620ed`. The deployed guard raises22023 for that message; the browser's exact response code was not independently captured, so this report distinguishes source/code mapping from observed HTTP evidence.

Web then saved a valid draft3 and second-tab synthetic variations4/5. SQL confirms saves27/28/29 and latest draft5 hash `fe11411c5d5ba1f180586faf8e5ac385412937b4d152b27cc5f56d4492afb115`. Public event remains baseline revision1/hash. A first-tab stale-save attempt produced no visible outcome; independent SQL shows no revision6/save6. This proves no committed change at the checkpoint, not an observed40001 response. Browser stale-conflict handling remains UNVERIFIED.

Web reports successful signed-in reload, five-kind initial empty lists, dirty/invalid JSON publication disabling and organization unknown-field preservation. These are attributed browser observations, not API-Dev browser tests. Editor/nonstaff browser roles and real session expiry remain untested; no identity/member/Auth changes were made. Existing disposable actual-role tests remain separate evidence.

## Final retained state and unverified outcomes

Web attempted exact event published-revision1 withdrawal and accepted its confirmation once, but the automation timed out. Immediate and subsequent read-only checkpoints still show event public1, no withdrawal audit, totalpublic3 and unchanged draft5. The request outcome remains UNKNOWN; no successful withdrawal is claimed. Lead then instructed finalization with no new mutations, retries or cleanup. Calendar/organization withdrawals were not attempted. All three safe synthetic publications remain at revision1, with retained drafts organization1/calendar1/event5 and ten history entries (seven saves, three publishes, zero withdrawals), sequence20 through29. Features remain0 and staff count1; Security independently confirmed this final aggregate baseline. No destructive cleanup, Auth/member change or API-side fixture write occurred.

Concrete UI feedback issues reported by Web: publish success notice disappears during selectDraft refresh (SQL proves known success, no retry); a cross-tab session event reset the editor and stale-save feedback did not appear. Read-only source inspection shows refreshRole increments authRun and clears editor on every auth event, while save result/error handlers discard responses after an authRun change. This is a plausible cause for lost feedback, not proof of the exact failed request. No backend/schema cause is inferred. Web owns local UX remediation and later frozen-artifact testing; v1 API signatures and reviewed-payload publication gate stay unchanged.

This checkpoint confirms live authenticated creation/publication and private-address rejection state preservation. It does not close exact browser HTTP22023 capture, stale40001/conflict UX, withdrawal completion, editor/nonstaff browser roles, session expiry or resident-site content refresh. API remains available for read-only verification during separately coordinated tests of the next frozen Web artifact.
