# SQLite migration archive

These migrations are retained only as the history of the original local SQLite
database. Prisma must not deploy this directory to PostgreSQL.

- The original `prisma/dev.db` is intentionally not removed.
- PostgreSQL migrations live in `prisma/migrations`.
- Master data can be recreated with `POST /api/sync`.
- Anonymous `UserProgress` rows must be exported and imported explicitly if
  they need to be retained; migration must never discard them implicitly.
