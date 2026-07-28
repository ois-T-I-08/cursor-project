# SQLite migration archive

These migrations are retained only as the history of the original local SQLite
database. Prisma must not deploy this directory to PostgreSQL.

## Why archived

- The `feature/youtube-build-guide-recommendations` branch developed against SQLite.
- No shared PostgreSQL environment had these migrations applied at the time of the
  PostgreSQL cutover (`integration/postgres-build-guides`).
- Therefore SQLite history was archived and a single PostgreSQL baseline was
  created from the full current schema (including build-guide models).

## Notes

- PostgreSQL migrations live in `prisma/migrations`.
- Master data can be recreated with `POST /api/sync`.
- Do not run `prisma migrate deploy` against this archive directory.
- Do not delete this archive; it documents the pre-PostgreSQL history.
