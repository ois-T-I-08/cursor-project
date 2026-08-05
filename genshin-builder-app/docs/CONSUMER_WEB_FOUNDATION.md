# Consumer Web application foundation

## Scope and information architecture

The consumer Web application follows the same five top-level destinations as the Flutter application while keeping Web and Flutter UI implementations separate.

| Category | Web route | Current scope |
|---|---|---|
| 今日 | `/today` | Read-only proposal presentation contract and recent real progress |
| キャラ | `/characters` | Existing character list and detail UI |
| 育成 | `/growth` | Safe unavailable state and route foundation |
| 編成 | `/teams` | Safe unavailable state and route foundation |
| その他 | `/more` | Settings and application information links |

`/` redirects to `/today`. The `(consumer)` route group is not present in URLs. `/settings` and `/characters/[id]` retain their existing URLs inside the consumer layout.

The application areas remain separate:

- **Consumer Web:** `(consumer)` routes, responsive application shell, anonymous-cookie read paths.
- **Admin:** `/admin/*`, its own layout, operator-supplied Bearer credentials, no consumer shell reuse.
- **Public information:** public build recommendation and template APIs; no consumer session dependency.
- **API:** `/api/*` route handlers; consumer UI does not call admin routes.
- **Flutter-only:** local daily-plan generation/adoption, Drift storage, HoYoLAB-derived local state, notifications and device workflows.

## Responsive shell and accessibility

- Mobile uses a five-item bottom navigation with safe-area padding.
- Tablet uses a compact icon-and-label sidebar from `48rem`.
- Wide desktop expands the same sidebar at `80rem`; the information hierarchy does not change.
- Active destinations use visible text, icon color/background, and `aria-current="page"`.
- Landmarks, a skip link, visible focus, minimum 44px controls, wrapping labels, reduced-motion handling, and horizontal overflow protection are included.
- Theme tokens default to light and follow `prefers-color-scheme: dark`. Existing dark-only character/settings components are isolated in a legacy dark surface until they are migrated to tokens.

## Daily-plan contract and Today

The Web parser reuses `DailyPlanProposal` schema version 1 and `shared/domain-golden/daily-plan-proposal-v1.json`. The strict Zod boundary rejects unknown fields, unknown enum values, invalid IDs and SHA-256 fingerprints, missing required fields, duplicate recommendations/priorities, recommendation/deferred overlap, unsafe display markup, and unsupported schema versions.

The presentation layer derives `primaryTask`, at most two `secondaryTasks`, collapsed remaining recommendations, and collapsed deferred tasks without exposing task IDs, priority, category, input hash, or proposal fingerprint. AI reasons are inside closed `details` elements. Deterministic fallback is labeled in natural Japanese.

There is no authenticated server-side read endpoint that can retrieve a Flutter proposal for the current browser. Therefore `/today` currently renders the empty state plus real recent Web progress. It does not invoke `/api/daily-plan/enrich`, DeepSeek, adoption, persistence, or user-data writes.

## API client foundation

`src/lib/consumer-api/client.ts` is server-only and GET/read-only. It provides:

- HTTPS base URL validation, with HTTP permitted only for loopback development;
- same-origin `/api/*` URL resolution without URL credentials;
- JSON Content-Type and response-size checks;
- bounded timeout plus caller `AbortSignal` support;
- safe mappings for 401, 403, 404, 409, 429 and 5xx;
- malformed JSON and strict Zod failure handling;
- sanitized `X-Request-Id` preservation;
- explicit `cache: "no-store"`, omitted browser credentials, and redirect rejection.

It is intentionally not connected to a page until an authenticated consumer read API exists. It accepts no Bearer token or Cookie option, so secrets cannot be passed through a Client Component.

## Authentication findings

- Web consumer identity is the existing `gb_user_id` httpOnly, SameSite=Lax cookie. It is issued only by the existing progress Server Action on first write.
- There is no production account login, server session, or cross-device identity.
- Flutter does not share `gb_user_id`; its daily-plan request uses an anonymized `clientScope` for proposal caching/rate boundaries, not Web account authentication.
- Admin and synchronization routes use separate environment-backed Bearer secrets and are not consumer authentication.
- An unissued or missing consumer cookie is a supported unauthenticated state and yields no user-specific progress.

Because no safe Web/Flutter shared identity exists, this foundation adds no consumer write API, proposal adoption, account sync, or hardcoded user.

## Explicitly not included

No Prisma schema or migration, DeepSeek execution, feature-flag change, secret change, production/staging deployment, proposal adoption, task persistence, account sync, character/growth/team editing expansion, PWA, offline queue, or conflict resolution is included.
