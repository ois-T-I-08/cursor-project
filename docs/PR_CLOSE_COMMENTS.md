# Close comment drafts (owner must approve before Close)

## PR #1 — Obsolete / Close

```text
Closing as obsolete.

This PR targeted an early static web / setup layout that does not match the current Next.js + Flutter monorepo. Mobile already has AGENTS.md and the current toolchain docs live under genshin-builder-app / genshin-builder-mobile.

No merge to main. Owner approval recorded in docs/GITHUB_HYGIENE.md (2026-07-26).
```

## PR #4 — After salvage PR exists

```text
Closing after salvage.

Required still-missing pieces (if any) were ported to a new main-based PR. This stacked branch will not be rebased onto current main directly (Daily Plan / notifications / sync lease must not regress against PR #16 / main).

See docs/GITHUB_HYGIENE.md and the replacement PR link.
```

## PR #5 — After salvage PR exists

```text
Closing after salvage.

Ley-line / resin planning domain work must not merge while stacked on #4. Domain, UI, and calendar integration (if still needed) land as separate main-based PRs.

See docs/GITHUB_HYGIENE.md and the replacement PR link(s).
```

## PR #6 — After salvage PR exists

```text
Closing after salvage.

Security hardening items already present on main / #14 / #16 were not re-introduced. Remaining unique hardening, if any, lives in a new main-based PR.

See docs/GITHUB_HYGIENE.md and the replacement PR link.
```
