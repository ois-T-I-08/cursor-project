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

## Replacement PRs (opened)

1. [#20](https://github.com/ois-T-I-08/cursor-project/pull/20) sync lease renewal (web)
2. [#21](https://github.com/ois-T-I-08/cursor-project/pull/21) remote JSON URL hardening
3. [#22](https://github.com/ois-T-I-08/cursor-project/pull/22) Daily Plan completion / notifications
4. [#23](https://github.com/ois-T-I-08/cursor-project/pull/23) ley-line / resin domain (UI/calendar follow-up still needed)

Legal / consent: [#19](https://github.com/ois-T-I-08/cursor-project/pull/19)

Close comments: docs/PR_CLOSE_COMMENTS.md. Owner must approve before Close of #4-#6.
