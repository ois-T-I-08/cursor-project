# PostgreSQL migration operations (Web)

## Current policy

- Prisma `provider = postgresql`
- Active migrations: `genshin-builder-app/prisma/migrations`
- SQLite history archive: `genshin-builder-app/prisma/migrations-sqlite-archive`
- Baseline: `20260728220000_postgresql_baseline` (full schema including build guides)

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

## Forbidden

- `prisma migrate reset` on shared staging/production
- Editing already-applied migration files
- Using `prisma db push` as a production migration path
- Deploying `migrations-sqlite-archive`
- Connecting agent automation to production databases

## Rollback

1. Restore DB snapshot taken before `migrate deploy`
2. Redeploy the app revision that matches that schema
3. Record the incident; do not invent forward-fix SQL under pressure
