# Close comment drafts (owner must approve before Close)

## PR #1 — Obsolete / Close

Already **Closed** on GitHub. Historical comment:

```text
Closing as obsolete.

This PR targeted an early static web / setup layout that does not match the current Next.js + Flutter monorepo. Mobile already has AGENTS.md and the current toolchain docs live under genshin-builder-app / genshin-builder-mobile.

No merge to main. Owner approval recorded in docs/GITHUB_HYGIENE.md (2026-07-26).
```

## PR #4 — After salvage PRs exist

Replacement PRs:
- Sync lease renewal (web): https://github.com/ois-T-I-08/cursor-project/pull/20
- Daily Plan completion / notifications (mobile): https://github.com/ois-T-I-08/cursor-project/pull/22

```text
Closing after salvage.

Required still-missing pieces were ported to main-based PRs:
- #20 sync lease renewal / cooperative abort (web only)
- #22 Daily Plan completion + 23:00 notifications (mobile only)

This stacked branch will not be rebased onto current main. Sync lease was compared with PR #16 to avoid regression.

See docs/GITHUB_HYGIENE.md and docs/PR_SALVAGE_PLAN.md.
```

## PR #5 — After salvage PRs exist

Replacement PR:
- Domain + tests: https://github.com/ois-T-I-08/cursor-project/pull/23
- UI / calendar: follow-up (not opened yet)

```text
Closing after salvage.

Ley-line / resin planning domain work was ported without stacking on #4:
- #23 domain models, assets, validators, and tests

Flutter UI and calendar/event integration remain separate follow-ups. Do not merge this stacked PR.

See docs/GITHUB_HYGIENE.md and docs/PR_SALVAGE_PLAN.md.
```

## PR #6 — After salvage PRs exist

Replacement PR:
- remote JSON URL hardening: https://github.com/ois-T-I-08/cursor-project/pull/21

Already on main (do not reintroduce): PostCSS pin path, CI `validate_config_json`, streaming maxBytes.

```text
Closing after salvage.

Security hardening unique to this stacked branch was ported where still needed:
- #21 remote JSON HTTPS / no-redirect / no-credentials URL guards

Items already present on main / later work were not re-introduced (PostCSS, CI config validation, streaming size limits).

See docs/GITHUB_HYGIENE.md and docs/PR_SALVAGE_PLAN.md.
```
