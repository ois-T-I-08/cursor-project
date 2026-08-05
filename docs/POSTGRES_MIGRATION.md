# PostgreSQL migration operations (Web)

## Current policy

- Prisma `provider = postgresql`
- Active migrations: `genshin-builder-app/prisma/migrations`
- SQLite history archive: `genshin-builder-app/prisma/migrations-sqlite-archive`
- Baseline: `20260728220000_postgresql_baseline` (full schema including build guides)
- Account/session expand migration: `20260806120000_add_account_session_foundation`

## Why SQLite was archived

The YouTube build-guide feature branch developed against SQLite. There was no
verified shared PostgreSQL environment that already had those migrations
applied. Cutting over uses a single PostgreSQL baseline instead of replaying
SQLite SQL.

## Local / CI

```bash
cd genshin-builder-app
cp .env.example .env   # edit DATABASE_URL / DIRECT_URL to local Postgres
npm ci
npx prisma generate
npx prisma validate
npx prisma migrate deploy
npx prisma migrate status
RUN_BUILD_GUIDE_DB_TEST=true RUN_REPLACEMENT_DB_TEST=true npm test
```

CI uses a disposable `postgres:16` service container and the same migrate path.

### Account/session foundation verification

This migration creates empty `Account`, `AuthIdentity`, `WebSession`, and `AnonymousIdentity` tables only. It does not update, backfill, or re-key `UserProgress.userId` / `gb_user_id`, and it does not alter a legacy column.

Run only against a disposable local PostgreSQL database named `genshin_test`:

```bash
cd genshin-builder-app
CI_DISPOSABLE_DATABASE=true npm run test:migration:account-session
npx prisma migrate deploy
npx prisma migrate status
RUN_ACCOUNT_SESSION_DB_TEST=true npm test -- account-session-postgres-db.test.ts
```

The migration test starts from the current PostgreSQL base, seeds a legacy `UserProgress` row, verifies the row is unchanged after upgrade, injects an interruption before `COMMIT`, proves all new DDL rolled back, and applies the same migration again successfully. The script refuses non-loopback hosts and database names other than `genshin_test`.

`ACCOUNT_IDENTITY_ENABLED` and `WEB_ACCOUNT_SESSION_ENABLED` remain false in CI. Migration/model tests do not require enabling runtime account behavior; integration tests inject an isolated test-only feature state and never issue a session to a real user.

## Forbidden

- `prisma migrate reset` on shared staging/production
- Editing already-applied migration files
- Using `prisma db push` as a production migration path
- Deploying `migrations-sqlite-archive`
- Connecting agent automation to production databases

## Rollback

Before applying anywhere beyond disposable CI/local databases, capture and verify a snapshot. This PR does not apply the migration to staging or production.

1. If migration execution is interrupted before `COMMIT`, PostgreSQL rolls back all four tables, indexes, checks, and foreign keys. Fix the cause and rerun `prisma migrate deploy`.
2. If a completed deployment must be rolled back, disable both account flags, restore the pre-migration snapshot, and redeploy the matching app revision.
3. Do not delete the new tables with ad-hoc SQL on a shared database. Once runtime rows exist, rollback requires a separately reviewed forward migration and retention/export decisions.
4. Record the incident; do not invent a destructive forward-fix under pressure.
