# Pre-release validation checklist

Target branch: `feature/youtube-build-guide-recommendations`
Related Draft PR to main: `#25` (remains Draft; not merged by this work)
Last staging validation: `2026-08-02` (Vercel staging tip `fc7b762` + Neon staging; kill switches OFF; Tier A gate-only smoke **PASS**; **no production mutation**)
Last local validation: `2026-08-01` (Windows host; **no local Docker/Postgres**; no production mutation)

Do **not** record secrets, keystore passwords, HoYoLAB cookies, tokens, Bearer values, DB URLs, Neon project IDs, connection hosts, smoke character IDs, or device account credentials in this file.

## Build identity (fill when signing is available)

| Field | Value |
|-------|--------|
| Target commit | `fc7b7621f0012e1dd18aa7da1fc164feadc00dd1` |
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
| Prisma migration status / deploy | **blocked locally** (no Docker/Postgres); **CI passed** on `postgres:16` (`migrate deploy` + DB integration); **staging Neon baseline applied** `2026-07-29` | baseline `20260728220000_postgresql_baseline` |
| Production dependency audit | passed | `npm audit --omit=dev`: 0 vulnerabilities |
| Secret logging guards | code + CI secret guard | |
| Genshin Mobile CI | passed | PR #27 GitHub Actions SUCCESS |
| Genshin Web CI | passed | `postgres:16` service; `migrate deploy` success; DB integration (`RUN_*_DB_TEST`) success |
| Node.js runtime | passed | engines / deploy runtime **24.x**; Node 20 deprecation warning resolved |

## PostgreSQL cutover

| Item | Value |
|------|--------|
| Provider | postgresql |
| Active migrations | 1 baseline (full schema incl. build guides) |
| SQLite archive | `prisma/migrations-sqlite-archive` |
| Ops doc | `docs/POSTGRES_MIGRATION.md` |
| Staging doc | `docs/STAGING_SETUP.md` |

## Staging validation (`2026-07-29`)

- Deployed commit: `778fc74b1798013414b26ff27f38df70e63952d0`
- Vercel Project: `ois/staging`
- Staging URL: https://staging-sable.vercel.app
- Deployment: READY (Node.js 24.x)
- PostgreSQL: Neon staging baseline applied
- Smoke summary: **22 passed / 0 failed**
- Kill switches: remained disabled during smoke
- Production impact: none
- PR #25: remains OPEN / Draft

| Gate | Status | Notes |
|------|--------|-------|
| Staging deployment | passed | ois/staging, Node 24, READY |
| PostgreSQL baseline | passed | Neon staging |
| Public unpublished API | passed | 404 |
| Admin auth | passed | 401 / 403 / authenticated 200 |
| Publish flow | passed | approve → publish → public 200 |
| ETag / 304 | passed | |
| Optimistic lock | passed | stale update 409 |
| Published snapshot retention | passed | draft edit did not change ETag |
| Revision restore | passed | |
| Unpublish | passed | public API returned 404 |
| Public data leakage | passed | admin-only fields absent |
| YouTube URL validation | passed | invalid host rejected, youtu.be accepted |
| Smoke total | passed | 22 passed / 0 failed |
| Staging DB backup | not verified | keep incomplete |
| Admin secret unset 503 | not run | shared staging secret was not removed |

Also verified on staging (included in smoke / deploy checks):

| Check | Status | Notes |
|-------|--------|-------|
| GET `/` | passed | 200 |
| GET `/admin/guides` | passed | 200 |

## Staging / Android / device

| Check | Status |
|-------|--------|
| Staging deploy | **passed** — `ois/staging` READY @ `778fc74` (`2026-07-29`) |
| Staging Postgres baseline | **passed** — Neon staging (`2026-07-29`) |
| Staging smoke (build-guide admin/public) | **passed** — 22 / 0 (`2026-07-29`) |
| Staging DB backup / snapshot | **not verified** — no clear evidence of backup/snapshot |
| Admin secret unset → 503 | **not run** — shared staging secret was not removed |
| Local Docker / PostgreSQL smoke | **blocked** — not executed |
| Signed AAB | **blocked** — no local `android/key.properties` / keystore |
| Device fresh install | **blocked** — not executed |
| Device schema v7 / v8 → current migration | **blocked** — not executed |
| Notification device check | **blocked** — not executed |
| Light / dark theme | **blocked** — not executed |
| Larger text / a11y | **blocked** — not executed |
| Production DB backup / rollback | **blocked** — not executed |
| Production deploy | **blocked** — not executed |
| Live YouTube / Gemini / DeepSeek | **OFF** (intentional; kill switches remained disabled) |
| Feature ↔ main merge (abyss #35/#37) | **done** — hardened `abyss-aza-ingest-staging.yml` from main; pushed on feature |
| YouTube GHA `actions/checkout` | **fixed on feature** — required for job summary script |
| Local Web typecheck/lint | **passed** (`2026-08-01`) |
| Local Vitest | **374 passed / 46 skipped** (DB suites need disposable Postgres) |
| Local Flutter analyze + guide tests | **passed** (34 focused tests) |
| Staging `/api/v2/build-recommendations/*` | **JSON notFound** — route on tip `fc7b762`; no published guide |
| Staging `/api/build-recommendations/*` | **JSON notFound** — route present; no published guide for sample id |
| Staging YouTube pipeline admin route | **real Next API** — tip redeployed; Bearer admin works |
| Staging automation migrate (`20260731120000`+) | **applied** on Neon staging |
| Staging Tier A gate-only dry-run | **PASS** — `scripts/gate-only-smoke.mjs`; flags OFF; `skipped=true`; no automation row growth |
| Staging Tier B provider dry-run | **not run** — needs owner approval + OAuth / stage flags |

## Go / No-Go

| Question | Answer |
|----------|--------|
| Merge PR #25 into main? | **No** — keep Draft |
| Production migrate/deploy? | **No** |
| Enable guide kill switches? | **No** until remaining release gates + owner approval |
| Production impact from staging smoke? | **None** |

## Owner next actions (max 5)

1. Approve Tier B only if wanted: staging-only `YOUTUBE_OAUTH_ACCESS_TOKEN` (+ existing API keys), then set guide/automation/discovery(/gemini) `true` with auto-publish/maintenance still `false`; redeploy; re-smoke.
2. After #25 merges to main, set GitHub `environment: staging` vars/secrets and enable GHA gradually (repo var still gates the job).
3. Provide release keystore only if signed AAB is required next; run device install / migration / theme / notification checks.
4. Keep kill switches `false` and PR #25 Draft until production backup/rollback plan and remaining gates are ready.
5. On any doubt: emergency stop ON + all YouTube/Gemini flags `false` (see `docs/YOUTUBE_GUIDE_AUTOMATION.md`).
