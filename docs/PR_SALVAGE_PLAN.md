# PR #4 / #5 / #6 salvage plan (2026-07-26)

Do **not** rebase or merge stacked PRs #4–#6 onto main. Close only after replacement PRs exist and owner approves.

## Comparison vs `origin/main`

| Owner item | On main? | Salvage target |
|------------|----------|----------------|
| Daily Plan completion | **No** | `salvage/daily-plan-completion-notifications` (mobile only) |
| WorkManager / 23:00 notification / tap routing / permission | **Partial** (`notification_tap_router` exists; daily-plan pack missing) | same mobile PR |
| Sync lease renewal / heartbeat / cooperative abort | **No** (`renewSyncLease` absent) | `salvage/sync-lease-renewal` (web only) — compare with PR #16 before merge |
| Device validation docs | Check `docs/pre-release-validation.md` on #4 | optional docs-only follow-up |
| Resin / ley-line domain + tests | **No** | `salvage/ley-line-resin-domain` |
| Ley-line Flutter UI | **No** | separate UI PR after domain |
| Calendar / event integration | **No** | third PR if still needed |
| remote_json HTTPS / no redirect / no credentials | **Missing** (maxBytes streaming exists) | `salvage/remote-json-url-hardening` |
| SQL COUNT startup helpers | **Partial** (exp counts; not full character/weapon/material counts from #6) | include with hardening or tiny follow-up |
| PostCSS / CI validate_config | **Present** on main | do not reintroduce |
| last-known-good (ley-line repo) | Tied to #5 configs | ship with ley-line domain PR |

## Replacement PR order

1. `salvage/sync-lease-renewal` (web)
2. `salvage/remote-json-url-hardening` (mobile security)
3. `salvage/daily-plan-completion-notifications` (mobile)
4. `salvage/ley-line-resin-domain` then UI / calendar

Close comments: `docs/PR_CLOSE_COMMENTS.md` (fill replacement links after PRs open).
