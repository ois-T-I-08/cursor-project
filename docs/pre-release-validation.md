# Pre-release validation checklist

Target branch: `integration/postgres-build-guides`
Base for integration PR: `feature/youtube-build-guide-recommendations`
Related Draft PR to main: `#25` (remains Draft; not merged by this work)
Last local validation: `2026-07-28` (Windows host; **no local Docker/Postgres**; no production mutation)

Do **not** record secrets, keystore passwords, HoYoLAB cookies, tokens, or device account credentials in this file.

## Build identity (fill when signing is available)

| Field | Value |
|-------|--------|
| Target commit | `b3e54e673bd71e510b7c47faf8ed3cd3e0848586` |
| applicationId | `io.github.oisti08.genshinbuilder` |
| versionCode / versionName | from `pubspec.yaml` / Flutter (unchanged by this branch) |
| Build datetime | |
| APK size / SHA-256 | *blocked until local release signing exists* |
| AAB size / SHA-256 | *blocked until local release signing exists* |
| APK signature verify | *not run* |
| Device / Android version | *not run (no device session in this integration)* |
| Reviewer / date | |

## Automated gates

| Gate | Status | Notes |
|------|--------|--------|
| Mobile format | passed | 436 files, 0 changed |
| Mobile codegen | passed | build_runner |
| Mobile tests | 756 passed | 0 failed |
| Domain parity (3) | passed | included in full suite; GitHub Domain Golden Parity CI also SUCCESS |
| `flutter analyze` | passed | 0 issues |
| Android debug APK | passed | `build/app/outputs/flutter-apk/app-debug.apk` (gitignored; not signed) |
| Web tests | 334 passed / 2 skipped | skips are env-gated DB suites without local Postgres |
| Web typecheck / lint | passed | 0 errors / 0 warnings |
| Web production build | passed | Next.js 16.2.12 / Turbopack |
| Prisma generate / validate | passed | Prisma 6.19.3 / provider postgresql |
| Prisma migration status / deploy | **blocked locally** (no Docker/Postgres); **CI passed** on `postgres:16` (`migrate deploy` + DB integration) | baseline `20260728220000_postgresql_baseline` |
| Production dependency audit | passed | `npm audit --omit=dev`: 0 vulnerabilities |
| Secret logging guards | code + CI secret guard | |
| Genshin Mobile CI | passed | PR #27 GitHub Actions SUCCESS |
| Genshin Web CI | passed | `postgres:16` service; `migrate deploy` success; DB integration (`RUN_*_DB_TEST`) success |

## PostgreSQL cutover

| Item | Value |
|------|--------|
| Provider | postgresql |
| Active migrations | 1 baseline (full schema incl. build guides) |
| SQLite archive | `prisma/migrations-sqlite-archive` |
| Ops doc | `docs/POSTGRES_MIGRATION.md` |
| Staging doc | `docs/STAGING_SETUP.md` |

## Staging / Android / device

| Check | Status |
|-------|--------|
| Staging deploy | **blocked** — no identifiable non-production host/DB in-repo |
| Signed AAB | **blocked** — no local `android/key.properties` / keystore |
| Device fresh install / v7→v9 / v8→v9 | **blocked** — not executed |
| Live YouTube / Gemini / DeepSeek | **OFF** (intentional) |

## Go / No-Go

| Question | Answer |
|----------|--------|
| Merge integration PR into feature? | After CI green + owner review |
| Merge PR #25 into main? | **No** — keep Draft |
| Production migrate/deploy? | **No** |
| Enable guide kill switches? | **No** until staging smoke + owner approval |

## Owner next actions (max 5)

1. Install Docker Desktop or local Postgres 16 for local migrate/smoke.
2. Create/identify staging Postgres + web host that is not production.
3. Review and merge `integration/postgres-build-guides` → feature after CI.
4. Provide release keystore only if AAB is required next.
5. Keep PR #25 Draft until staging smoke passes.
