# Staging setup (Build Guide / PostgreSQL)

This repository does **not** currently ship a managed staging project ID,
Neon branch, or Vercel project binding in-tree. Do not invent cloud resources
from this document alone.

## Safety

- Never point these steps at production.
- Confirm staging URL / DB / project IDs with the owner before any deploy.
- Keep kill switches OFF until explicitly approved:

```text
YOUTUBE_GUIDE_ENABLED=false
GEMINI_VIDEO_ANALYSIS_ENABLED=false
DEEPSEEK_GUIDE_ANALYSIS_ENABLED=false
```

## Required environment variables (dummy examples only)

| Name | Staging purpose |
|------|-----------------|
| `DATABASE_URL` | Pooled Postgres URL for the app |
| `DIRECT_URL` | Direct Postgres URL for Prisma Migrate |
| `BUILD_GUIDE_ADMIN_SECRET` | Admin Bearer for `/api/admin/build-guides` |
| `SYNC_API_SECRET` | Existing sync admin secret (separate value) |
| `GENSHIN_BUILDER_API_BASE_URL` | HTTPS origin Flutter uses |

Do not commit real values. Register them in the host's secret store.

## Migration procedure (staging only)

1. Take a DB backup / snapshot (host-specific).
2. Confirm target is staging: `npx prisma migrate status`
3. Apply: `npx prisma migrate deploy`
4. Re-check: `npx prisma migrate status`
5. Smoke test (below)
6. If failed: restore snapshot, then re-open an incident note

## Smoke tests

```bash
# 503 when admin secret unset (isolated preview only; do not unset shared staging)
# 401 without Bearer
# 403 with wrong Bearer
# 200 overview with correct Bearer
# draft save / approve / publish / unpublish
# 409 on stale expectedUpdatedAt
# public GET /api/build-recommendations/:characterId → 200 + ETag
# If-None-Match → 304
# draft edits do not change public ETag / published targets
# adminNotes / adminWorkingDraft absent from public JSON
```

## Rollback

1. Restore the pre-migration DB snapshot.
2. Redeploy the previous web artifact that matches that schema.
3. Do not `migrate reset` on shared staging.

## Owner actions still required

1. Create or identify a staging Postgres + web host that is not production.
2. Register secrets in that host.
3. Approve first `migrate deploy`.
4. Approve enabling YouTube / Gemini / DeepSeek (optional, later).
