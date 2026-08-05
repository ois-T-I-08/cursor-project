# Cross-platform account identity and sync architecture

Status: Proposed

Date: 2026-08-06

Scope: design, audit, API contracts, and disabled foundation implementation status

Related: `ACCOUNT_SYNC_THREAT_MODEL.md`, `../adr/0001-cross-platform-account-identity.md`

## 1. Scope and evidence labels

This document defines the intended identity, authentication, ownership, and synchronization boundaries shared by the Next.js Web application and the Flutter application. It does **not** authorize runtime authentication, a database migration, a Prisma change, an OAuth provider, secrets, deployment, or user-data synchronization.

The following labels keep observed behavior separate from design:

- **FACT**: verified in the repository at base `92edeec1c83a2ad08b1fc1be011f56a8142a1aa8`.
- **INFERENCE**: an expected consequence that is not explicitly guaranteed by code or platform configuration.
- **PROPOSAL**: a future contract. It is not implemented by this change.

### 1.1 Disabled foundation implementation (2026-08-06)

The separately authorized `feature/account-schema-session` implementation adds only the disabled provider-neutral foundation. This ADR remains Proposed, and this status does not authorize runtime login or production/staging rollout.

| Design item | Foundation implementation | Runtime state |
|---|---|---|
| Canonical `Account` | Prisma model, additive PostgreSQL migration, server-generated UUID, active-account repository | Empty table; no automatic account creation |
| `AuthIdentity` | Provider-neutral model and `(provider, providerSubject)` uniqueness | No Google, Apple, email, Passkey, or provider adapter |
| `WebSession` | Opaque 256-bit token generation, SHA-256 hash-at-rest, revocation, rotation, account-version fencing, expiry, bounded last-seen writes, cleanup, metadata-only listing | No public route issues a token or Cookie |
| `AnonymousIdentity` | Expand-only model with hashed secret, expiry/revoke/claim fields | No legacy mapping, backfill, Cookie issuance, or claim |
| Web Cookie | Internal `__Host-gb_session` builder/parser/deletion primitives | Existing `gb_user_id` Cookie is unchanged |
| `AuthContext` | Central server-only `unauthenticated` / `legacyAnonymous` / `account` union; account state derives only from a resolved session | Existing consumer routes still use legacy behavior |
| Ownership boundary | Server-owned-field rejection helper and account-scoped session repository operations | No account-owned consumer repository or API cutover |
| Feature gates | `ACCOUNT_IDENTITY_ENABLED=false`, `WEB_ACCOUNT_SESSION_ENABLED=false`; both exact `true` values are required for issuance/rotation | CI and examples remain false |
| Audit | Token-free minimal interface and call points with non-reversible short correlations | No durable account audit table until retention/access policy is approved |
| Verification | Unit security tests, PostgreSQL concurrency/FK/rollback tests, migration interruption/retry test, disposable-Postgres CI | Production/staging databases are not used |

The design proposal preferred a keyed token hash. This foundation cannot add or change a secret, so it hashes the 256-bit random opaque token with SHA-256. The token's entropy prevents practical offline guessing, but selecting and rotating a server-held hash key remains a release blocker before runtime login.

Not implemented here: login UI/routes, OAuth/OIDC, Passkey/WebAuthn, Flutter authentication, anonymous claim, account data sync, Daily Plan account connection, deletion/export jobs, deployment, and feature enablement. The next reviewed PR may implement the Web anonymous-session preparation or a Web login adapter, but neither is enabled by this foundation.

## 2. Identity vocabulary

These identifiers are not interchangeable.

| Identifier | Issuer | Meaning | May authorize account data? |
|---|---|---|---|
| `Account.id` | server | Immutable canonical Genshin Builder account | Yes, but only after a valid server session resolves to it |
| `WebSession.id` | server | One browser login session | Yes, through its opaque cookie token |
| `DeviceSession.id` | server | One Flutter installation/login session | Yes, through valid access/refresh tokens |
| `deviceId` | server per installation | User-visible device/session label key; not a hardware fingerprint | No by itself |
| `AnonymousIdentity.id` | server | Pre-account browser owner behind an opaque anonymous-session secret | Only for that anonymous principal |
| `gb_user_id` | current Web Server Action | Legacy random browser cookie and current `UserProgress.userId` | **Never** as production account authentication |
| Flutter `localUserId` | Flutter app | Device-local UUID stored in Drift `app_settings` | No |
| Flutter `clientScope` | Flutter app | First 12 hex characters of SHA-256(`localUserId`) | No; cache/rate partition only |
| HoYoLAB UID / game UID | HoYoverse | Game profile identifier | No |
| HoYoLAB Cookie | HoYoverse | Third-party credential stored on device | No; never send to Genshin Builder auth/sync |

## 3. Current identity audit

### 3.1 Web

| Area | Verified current state |
|---|---|
| Anonymous cookie | **FACT:** `gb_user_id` is read by `src/lib/user.ts` and first created by `src/lib/actions/progress.ts::ensureUserId()` when progress is saved. |
| Generation | **FACT:** `crypto.randomUUID()`; there is no signature, server-side session row, rotation, or revocation. |
| Attributes | **FACT:** `httpOnly: true`, `sameSite: "lax"`, `secure` only when `NODE_ENV === "production"`, `path: "/"`, max age five years. No `Domain` is set. |
| Database use | **FACT:** `UserProgress.userId`; uniqueness is `(userId, characterId)`. Character, weapon, talent, artifact, completion, and memo fields share this owner key. |
| Authorization | **FACT:** progress Server Actions read the cookie and filter/upsert by that value. There is no authenticated consumer account or consumer session model. |
| Input boundary | **FACT:** `characterId` existence is checked and numeric/text/artifact inputs are clamped or sanitized before upsert. |
| CSRF | **FACT:** the progress code has no application-specific CSRF token or explicit Origin check. **FACT (framework):** Next.js Server Actions compare Origin with Host / forwarded Host and only accept POST; SameSite=Lax adds a browser control. This is defense-in-depth, not a replacement for the proposed mutation contract. |
| Owner-secret exposure | **FACT:** `/settings` renders the raw `gb_user_id` in the page. Although the cookie is httpOnly, the same value is visible to page JavaScript and screenshots. |
| Cookie loss | **FACT:** reads without the cookie return no user-specific progress; a later save issues a new UUID. Old rows remain orphaned because no recovery/link exists. |
| Browser sharing | **FACT:** no cross-browser or cross-device sharing exists. OS/browser profile cookie copying is outside the application contract. |
| Bookmarks | **FACT:** `gb_material_bookmarks` is unscoped browser `localStorage`; it does not use `gb_user_id`. |
| Export/delete | **FACT:** the settings UI says export/import is planned. There is no account export or account deletion. Individual progress rows can be deleted. |
| Logging | **FACT:** progress error handlers log raw caught `Error` objects; user-facing messages are generic. Whether a driver error contains user-supplied identifiers is not guaranteed. |

**INFERENCE:** possession of the current cookie value is the only ownership evidence for legacy progress. Its entropy makes blind guessing unlikely, but it lacks server-side lifecycle, proof-of-possession rotation, and safe account-claim semantics. It must be replaced by a server-held anonymous identity before account launch.

### 3.2 Flutter

| Area | Verified current state |
|---|---|
| Device-local identity | **FACT:** `localUserIdProvider` loads `local_user_id` from Drift `app_settings`; if absent it creates `Uuid().v4()`. |
| `clientScope` | **FACT:** `dailyPlanSafeUserScope` is the first 12 hex characters of SHA-256(`localUserId`). It scopes WorkManager names, local proposal keys, and the daily-plan request/cache. |
| Remote API auth | **FACT:** `BackendDailyPlanEnrichApi` sends JSON with no `Authorization` header. `clientScope` is a request field, not a credential. Other current public consumer clients are also not a remote account session. |
| Secure Storage | **FACT:** `flutter_secure_storage` stores HoYoLAB Cookie, UID, region, nickname, optional HoYoLAB app-version override, and an optional SQLCipher key. Android encrypted shared preferences are requested. |
| HoYoLAB save order | **FACT:** the Cookie is persisted only after token verification and game-role discovery succeed. Disconnect deletes Cookie, UID, region, and nickname. |
| Drift ownership | **FACT:** `user_progress`, growth goals, material inventory, saved teams, growth events, daily-plan completions, and evaluation history use the local `userId`. **FACT:** bookmarks and `app_settings` are device-global tables without an owner column. |
| Cloud sync | **FACT:** `LocalOnlyCloudSync` reports a local anonymous `UserAccount`; push/pull are no-op/disabled and no remote identity exists. |
| Proposal persistence | **FACT:** a validated adopted proposal is stored in `app_settings` under a key containing hashed user scope and local date. The proposal fingerprint is rechecked. |
| Reinstall | **FACT:** the app has no account recovery or server restore flow. The accepted mobile ADR says Android backup remains disabled. **INFERENCE:** exact secure-storage persistence after reinstall is platform-dependent and must not be relied on. |
| Multiple devices | **FACT:** no linking, device list, cursor, remote merge, or revoke flow exists. Each installation generates its own local identity. |
| Logout/unlink | **FACT:** HoYoLAB disconnect exists. There is no Genshin Builder account logout because no remote account exists. |
| Local encryption | **FACT:** the accepted v1 ADR keeps user progress/goals/bookmarks in plaintext Drift and keeps credentials in Secure Storage; it requires reconsideration when cloud sync is introduced. |

### 3.3 Server

| Area | Verified current state |
|---|---|
| Account models | **FACT:** Prisma has `UserProgress` but no `User`, `Account`, `AuthIdentity`, consumer `Session`, or device-session model. |
| User-specific boundary | **FACT:** progress is a Server Action keyed by `gb_user_id`. The current `/api/daily-plan/enrich` is unauthenticated and uses `clientScope` only inside a hashed process-local cache key. |
| Public APIs | **FACT:** build recommendations, team templates/recommendations, weapon details, abyss statistics, and daily-plan enrichment are public/read or public computation boundaries. Team-recommendation jobs are retrieved by UUID job ID, not account ownership. |
| Admin/sync APIs | **FACT:** admin routes use environment-backed Bearer secrets with timing-safe comparison and fail closed if missing. Master sync uses a separate Bearer secret; missing secrets are unavailable in production but allowed in non-production. |
| Rate limits | **FACT:** daily-plan/admin and sync limits are process-local maps (daily default 10/min/IP-scope; sync 5/min/key). Not every public route has an explicit route-level limiter; multi-instance global enforcement does not exist. |
| Audit | **FACT:** guide automation/admin has dedicated audit models. There is no consumer account/session/merge/sync/deletion audit trail. |
| Log/privacy | **FACT:** bearer-auth helpers do not log token bodies and API error envelopes are generally generic. **FACT:** some routes/actions log raw caught errors. |
| Account deletion/export | **FACT:** absent. |

## 4. Current and proposed data ownership

`Account` below means the server-derived account from a valid session, never an ID accepted from the request body.

| data | current owner key | Flutter storage | Web storage | server storage | sensitive | sync required | conflict risk | deletion behavior | proposed canonical owner |
|---|---|---|---|---|---|---|---|---|---|
| キャラクター育成状況 | Flutter `localUserId`; Web `gb_user_id` | Drift `user_progress` | Cookie selects server row | Prisma `UserProgress` | Medium (behavior/profile) | Yes | High: same character edited on two devices | Flutter uninstall loses local recovery; Web cookie loss orphans rows; row delete exists | `Account.id`; anonymous rows use `AnonymousIdentity.id` until confirmed claim |
| 武器育成状況 | Embedded in character progress under same keys | Drift `user_progress` | Same `UserProgress` aggregate | `UserProgress.weapon*` | Medium | Yes | High: aggregate overwrite | Same as character progress | `Account.id` |
| 天賦目標 | Local progress/goal `userId`; Web progress owner | Drift `user_progress`, `growth_goals` | `UserProgress.talent*` | `UserProgress` current values; no goal model | Medium | Yes | High | Local/account data deletion; legacy Web rows otherwise orphan | `Account.id` |
| 聖遺物評価 | Local progress `userId`; Web progress owner | Drift progress/artifact state | `UserProgress.artifacts`, score type | JSON in `UserProgress` | Medium | Yes, user opt-in | High: structured aggregate | Same as progress | `Account.id` |
| ブックマーク | No owner column on Flutter; no Web owner key | Drift `material_bookmarks` device-global | `gb_material_bookmarks` localStorage | None | Low/Medium | Yes, after owner migration | Medium: duplicate/source-key edits | Uninstall/browser storage clear deletes; account delete currently irrelevant | `Account.id`; device-only mode remains available before login |
| 編成 | Flutter `SavedTeams.userId`; Web consumer unavailable | Drift `saved_teams` | None | Imported/public templates and compute jobs are not personal saved teams | Medium | Yes | High: member/order edits | Local deletion only; jobs expire operationally | Saved team: `Account.id`; templates: `Global`; jobs: `Account.id` or ephemeral session |
| 今日の計画 | Flutter plan `userId`; Web has read-only empty foundation | Derived in memory; completions/eval in Drift | No persisted plan | No account plan | Medium | Yes for shared view/adoption | High: date/timezone and simultaneous adoption | Local history pruning; no account delete | `Account.id` + account timezone/local-date contract |
| DailyPlanProposal | Hashed local scope + date; server request `clientScope` | Serialized in Drift `app_settings` after adoption | None | Process-local TTL cache only | Medium | Yes for common proposal | High: stale source and double adoption | Local clear/staleness; process cache expires | `Account.id`; proposal is immutable, adoption is separate state |
| ガチャ履歴 | No personal pull-history model found; current feature is global banner schedule | Bundled/remote banner history, not user pulls | No personal history | Public/global source only | Future personal history: High | Only if personal pull history is later added | High: imports/dedup | Current global data unaffected by account delete | Current banner history: `Global`; future personal pulls: `Account.id` |
| HoYoLAB関連設定 | HoYoLAB UID/region and device settings | Secure Storage plus device settings/cache | None | No account link | High when UID/profile-linked | Only non-secret preference if explicitly selected | Medium: selected role differs by device | `disconnect()` removes secure session; caches need separate purge verification | Device-local by default; optional account preference excludes UID/raw response unless separately consented |
| Cookie / credential | HoYoLAB/OS credential; Web admin env secrets; legacy browser cookie | Secure Storage | httpOnly `gb_user_id`; admin credentials are operator supplied | Environment secrets; no consumer token rows | Critical | **Never** sync HoYoLAB/admin credentials; auth refresh token has its own protocol | Not mergeable | Revoke/delete session and secure item; never include in export | Session/device, not account data; server stores only hashes where possible |
| アプリ設定 | Device/global key; local user ID is one value | Drift `app_settings` | Mostly browser/UI state; no account settings model | None | Low/Medium | Selected allowlist only | Medium | Device reset; no account cascade | Split `AccountPreference` from `DevicePreference`; denylist credentials and debug settings |
| 通知設定 | Device-local user scope and OS schedule | Drift settings + OS notification scheduler | None | None | Medium (behavior/time) | Usually no; optional schedule preference only | Medium across timezones/devices | Disconnect/account logout must cancel account-scoped work; current local cleanup is feature-specific | `DeviceSession.id`, with optional account default |
| キャッシュ | Cache/source-specific key; some HoYo caches keyed by UID | Drift/disk/process caches | localStorage/process/RSC cache | Prisma external cache + process maps | May become High if user-derived | No direct sync | High: cross-account cache leakage | TTL/purge; current account cascade absent | `Global` for master; `Account.id`/session in every user-derived cache key |
| AI生成結果 | Request/job/client scope; not canonical account | Validated proposal locally | No consumer AI result | Process cache, team jobs, published recommendation records | Medium; raw prompts can be High | Only validated account artifact | High: stale/cross-owner | TTL/expiry; no account cascade today | Personal proposal/job: `Account.id`; public recommendation: `Global`; never persist raw AI response |
| 公開ビルド推薦 | Character/publication identity | Read-only fetched content/cache | Public read | Prisma recommendation/revision/source/audit models | Low/public | No user sync | Low; publication revision conflict only | Retained by editorial policy, not account deletion | `Global/Editorial`, never a consumer `Account.id` |

## 5. Authentication option comparison

External references in this section are official sources, accessed **2026-08-06**. Cost values are architectural estimates; vendor pricing is unresolved and must be checked at provider selection time.

| Criterion | Google OIDC | Sign in with Apple | Email magic link | Passkey | Recommended combination |
|---|---|---|---|---|---|
| Web | Strong official OIDC support | Supported; requires Services ID, associated Apple app ID, domains/return URLs | Universal browser support | WebAuthn secure-context support | Passkey primary; optional linked Google/Apple; email only verification/recovery |
| Android | Credential Manager / OAuth support | Browser-based provider flow possible but weaker platform affinity | App/universal link needed | Credential Manager + Digital Asset Links | Passkey + Google is natural; provider-neutral server remains canonical |
| iOS | Official SDK/browser flow | Native first-party support | Universal link needed | AuthenticationServices / associated domains | Passkey + Apple; if Google/social login is offered, satisfy App Review 4.8 |
| Minors | Provider and target-audience terms must be checked; may expose account/profile data | Private email relay helps minimization, but age/consent still unresolved | Collects email; parental-consent/target-audience decision required | Can minimize profile collection, but recovery/guardian design remains | Keep anonymous mode; do not declare child targeting until legal/policy decision and neutral age handling |
| Implementation | Medium | Medium/High across app+web | Medium server/email-delivery burden | High server ceremonies + app/web association | Highest; stage behind provider-neutral models |
| Secrets | Web client credential/config; mobile is a public client | Private key/client-secret lifecycle for web/server | Mail provider keys and signing/HMAC keys | RP signing/session infrastructure; private passkey stays in authenticator | Central secret inventory/rotation; no secret in Flutter bundle |
| Recovery | Google account recovery | Apple account recovery | Email account possession; phishing/mail compromise dependent | Multiple synced passkeys or another linked method/recovery codes | Require at least two recoverable authenticators before removing last fallback |
| Duplicate accounts | Same provider `sub` is stable; email must not auto-merge | Relay email and subject grouping complicate email matching | Case/alias/recycled-address risks | Multiple credentials can safely link to one account | Unique `(provider, subject)`; linking requires reauth; never auto-merge by email |
| Provider lock-in | Medium | Medium/High for Apple ecosystem config | Mail delivery vendor can be swapped with effort | Low protocol lock-in; RP ID/domain is a deliberate anchor | Low at account model; adapters are replaceable |
| Cost | Protocol generally no per-login fee; operations/support still cost | Developer program and operations; exact cost outside this ADR | Delivery, bounce, reputation, abuse cost | Engineering/operations cost | Defer vendor pricing decision |
| Local development | Loopback/registered redirect setup | More difficult because registered HTTPS domains/app association are central | Mail sink can make local testing straightforward | `localhost` is allowed by WebAuthn; native associations still need fixtures | Contract fixtures + fake provider; never weaken production redirects |
| Staging | Separate exact redirect/client configuration | Separate registered return URLs/keys/Services ID strategy | Separate domain and mail stream | Stable RP-ID plan is critical; avoid credentials stranded by domain change | Separate issuer/audience/keys and exact allowlists |
| Privacy | Stable provider subject; request minimal scopes | Hide My Email/private relay available | Direct email collection and delivery metadata | Server stores public key/opaque credential ID; minimal profile data | Collect no profile beyond recovery and display needs |
| Store concerns | On iOS, third-party/social primary login invokes App Review 4.8 equivalent-login requirements | Token revocation is required during account deletion | Deletion and email disclosure still apply | Association files and recovery UX must be production-ready | Apple/Google in-app deletion requirements are release gates |
| Recommendation | High as optional linked identity | High on iOS / required companion when policy applies | Medium for verification/recovery; Low as sole high-assurance auth | **Highest primary authenticator** | **Recommended target**, not authorized for implementation in this PR |

### Recommendation

1. Build provider-neutral account/session/ownership primitives first.
2. Make passkeys the preferred authenticator after a separate compatibility prototype for the final Web RP ID, Android Digital Asset Links, and Apple associated domains.
3. Permit multiple `AuthIdentity` records per account. Add Google and Apple as optional linked identities in separate provider PRs; do not derive `Account.id` from email or provider subject.
4. Use email only for address verification or controlled recovery, with short-lived single-use links, generic responses, rate limits, and phishing-aware messaging. NIST SP 800-63B-4 explicitly does not treat email as an out-of-band authenticator; this service should not claim an assurance level based on email magic links.
5. Preserve useful anonymous mode. Account creation and sync must be opt-in.

### Official sources

- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect) — OIDC setup, credentials, redirect URIs, and ID-token validation.
- [Google OAuth 2.0 for iOS & desktop apps](https://developers.google.com/identity/protocols/oauth2/native-app) — installed apps are public clients, system browser, state, and PKCE.
- [Sign in with Apple](https://developer.apple.com/documentation/SigninwithApple) and [Web configuration](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web) — native/Web support and Services ID/domain association.
- [Sign in with Apple environment](https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple) and [private email relay](https://developer.apple.com/help/account/capabilities/configure-private-email-relay-service/) — private key, return URL, and mail-domain requirements.
- [Apple App Review Guidelines 4.8](https://developer.apple.com/app-store/review/guidelines/) — equivalent login-service obligations for third-party/social primary login.
- [W3C WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/), [Android passkeys](https://developer.android.com/identity/passkeys), and [Apple passkeys](https://developer.apple.com/passkeys/) — RP-scoped public-key credentials and platform support.
- [RFC 9700 OAuth 2.0 Security BCP](https://www.rfc-editor.org/rfc/rfc9700.html) and [RFC 8252 OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252.html) — exact redirects, PKCE, external user-agent, and native-app security.
- [NIST SP 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html) — authenticator/replay guidance and email limitation.
- [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) and [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) — in-app and Web deletion paths, associated-data deletion, confirmation, and provider revocation.
- [Google Play Families policy](https://support.google.com/googleplay/android-developer/answer/17122218?hl=en-GB) — child-targeted authentication/device-data disclosure and SDK constraints.
- [Next.js authentication guide](https://nextjs.org/docs/app/guides/authentication) and [Next.js data-security guide](https://nextjs.org/docs/app/guides/data-security) — server cookies, database sessions, and Server Action Origin/Host comparison.

## 6. Target architecture

### 6.1 Trust boundary

```text
Web browser -- __Host-gb_session (opaque) --> Next.js auth/session boundary
Flutter app -- short access token ----------> Next.js account API boundary
            -- rotating opaque refresh -----> refresh boundary only
                                             |
                                             v
                                      canonical Account.id
                                             |
                   account-owned data + revisions + audit metadata

gb_user_id / clientScope / deviceId / HoYoLAB UID are never accepted as Account.id.
```

Every data-access function receives a server-built `AuthContext { accountId, sessionId, sessionKind, assurance, requestId }`. Repositories do not accept an owner ID directly from a Web form or Flutter JSON body.

### 6.2 Web session

1. Login starts on an exact allowlisted same-origin path. Generate high-entropy `state`, OIDC `nonce` where applicable, and PKCE where the adapter requires it; store only bounded, expiring challenge state server-side.
2. Callback validates issuer, audience/client ID, exact redirect URI, state, nonce, PKCE, signature, time claims, and provider subject.
3. Resolve unique `AuthIdentity(provider, providerSubject)` to `Account.id`. Never auto-link by email.
4. Rotate any pre-auth session ID, create `WebSession`, and send a random opaque token in `__Host-gb_session` with `HttpOnly; Secure; SameSite=Lax; Path=/` and no `Domain`. Store only a keyed hash of the token.
5. Proposed bounds: 24-hour idle expiry and 30-day absolute expiry; rotate after login, reauthentication, identity linking, and privilege/security changes.
6. State-changing route handlers require the DB session, exact Origin/Host allowlist, JSON Content-Type, and a session-bound CSRF token (double-submit or signed synchronizer token). Server Actions keep framework checks and call the same authorization service.
7. Browser JavaScript never receives a refresh token or long-lived bearer token. It may receive a non-secret session summary and CSRF value.

### 6.3 Flutter device session

1. Use a system authentication surface and Authorization Code + PKCE; do not use an embedded WebView for Genshin Builder authentication.
2. After provider/passkey verification, the server creates a `DeviceSession` and server-generated opaque `deviceId`. Do not derive it from Android ID, advertising ID, IMEI, IDFV, HoYoLAB UID, or `localUserId`.
3. Return a short-lived access token (proposal: 10 minutes) and a high-entropy opaque refresh token. Access-token claims contain opaque `sub=Account.id`, `sid=DeviceSession.id`, issuer, audience, `iat`, `exp`, and `jti`; never profile data.
4. Store refresh token and any access token only in Secure Storage. Keep access token in memory when practical. Do not place either in Drift, logs, analytics, crash reports, URLs, notification payloads, or `clientScope`.
5. Rotate the refresh token on every successful refresh. Store token hashes and a family generation. Reuse of an already-rotated token revokes the whole family and requires login.
6. Validate active `DeviceSession` on refresh and on high-impact calls; account deletion/revoke blocks immediately. A short access-token lifetime bounds cache/revocation lag.
7. A device list displays user-supplied/sanitized label, platform family, created/last-used approximate time, and current-device marker. It never exposes refresh hashes, IP history, or a hardware fingerprint.

### 6.4 Multiple devices and lifecycle

- Each login creates or deliberately renews one `DeviceSession`; a configurable per-account ceiling (proposal: 10 active devices) prevents unbounded token families.
- “Log out this device” revokes the current device session and clears only Genshin Builder auth credentials. It does **not** disconnect HoYoLAB unless the user separately requests that action.
- “Log out all devices” requires recent reauthentication, revokes every Web/Device session, and bumps `Account.sessionVersion`.
- Removing another device is idempotent and requires recent reauthentication. The current device cannot be accidentally removed through the generic row action; use the explicit logout flow.
- Losing/reinstalling a device does not recover its anonymous local data automatically. After login, server data can be pulled; unuploaded local data remains a separate, explicit first-sync candidate.

## 7. Anonymous Web upgrade

The legacy cookie cannot safely be the claim credential for the final system. Introduce a preparatory anonymous-session release before account login is exposed.

### 7.1 Preparation release

1. On a same-origin visit with `gb_user_id`, validate its UUID shape and locate only the matching legacy data.
2. Create `AnonymousIdentity` with a new 256-bit random claim secret. Store its hash server-side and send the secret in `__Host-gb_anon` (`HttpOnly; Secure; SameSite=Lax; Path=/`; short rolling and bounded absolute expiry).
3. Link the legacy `UserProgress.userId` to that server anonymous identity internally. Do not return either owner ID to JavaScript. Stop rendering raw `gb_user_id` in settings.
4. All new anonymous writes resolve through `__Host-gb_anon`; legacy cookie is dual-read only during a bounded migration window.

### 7.2 Confirmed claim flow

1. **Anonymous use:** data remains owned by the server-resolved `AnonymousIdentity`.
2. **Login/account creation:** create the account session without moving data.
3. **Detection:** server reads `__Host-gb_anon`; client cannot submit source owner or target account IDs.
4. **Preview:** calculate per-dataset counts/conflicts and a `previewHash`; create `AccountMergeAttempt(PREVIEWED)` with short expiry.
5. **Confirmation:** show source counts, target counts, conflict policy, excluded data, and irreversible effects. Require an explicit action plus recent account authentication.
6. **Atomic transfer:** under a transaction/serializable lock, revalidate anonymous secret, attempt state, target account from session, preview hash, source revision, and “not previously consumed”. Copy/merge into staging or execute a bounded transaction; switch ownership only after all datasets validate.
7. **No partial state:** on any failure, leave source rows and old anonymous session intact, delete staged rows, and mark the attempt failed. Never delete source first.
8. **Commit/audit:** record counts/hashes, policies, actor session, result, and request ID without data bodies or tokens. Mark source consumed with a unique constraint.
9. **Invalidate:** revoke every session/secret for the source anonymous identity and expire both anonymous cookies. A replay returns the already-committed result for the same idempotency key or `409 anonymousAlreadyClaimed` otherwise.
10. **Rollback:** keep a short-lived encrypted ownership manifest/snapshot sufficient for an operator-controlled compensating rollback. Rollback must verify that target records have not since changed; otherwise stop for manual resolution. Retention duration is unresolved.

Logging in alone never claims data. An account that already has data receives a conflict-aware preview; another account cannot claim a consumed anonymous identity.

## 8. Flutter first sync

### 8.1 Preconditions

- The user is logged in and explicitly selects “この端末のデータを同期”.
- A current `DeviceSession` exists; `deviceId` and `Account.id` come from the token/session, never the payload.
- The application displays dataset names, upload/download counts, conflicts, and excluded sensitive data before commit.
- HoYoLAB Cookie, HoYoLAB authentication material, Secure Storage contents, DB key, auth access/refresh tokens, raw HoYoLAB responses, logs, caches, and notification payloads are excluded.
- The SQLCipher strategy ADR is revisited before production cloud sync because local account data currently remains plaintext.

### 8.2 Versioned record envelope

```json
{
  "schemaVersion": 1,
  "dataset": "characterProgress",
  "recordId": "opaque-stable-id",
  "revision": 7,
  "updatedAt": "server-or-device-observed-ISO-8601",
  "deletedAt": null,
  "operationId": "uuid",
  "baseRevision": 6,
  "payload": {}
}
```

`ownerId`, `accountId`, `deviceId`, and session IDs are never accepted inside record payloads. The server adds ownership. Device timestamps help UX and conflict detection but do not alone determine truth; the server assigns `serverRevision` and `serverReceivedAt`.

### 8.3 Preview, commit, resume

1. Flutter scans allowlisted datasets and builds a deterministic manifest: schema version, dataset counts, record/content hashes, tombstone counts, and current local cursor. No bodies are uploaded in a dry-run unless needed for bounded validation.
2. `POST /api/sync/preview` returns upload/download/conflict counts, unsupported/excluded records, chunk size, server cursor/revision, expiry, and `previewToken` bound to account+device+manifest hash.
3. User confirms. Flutter sends chunks with a stable `syncRunId`, `chunkIndex`, `chunkHash`, and per-operation UUID. Proposed bound: at most 200 records or 256 KiB per chunk, whichever comes first.
4. The server transactionally validates each chunk, deduplicates operations, applies accepted records to staging, and returns the next cursor. Replaying an identical committed chunk returns the same result; a changed body with the same key is `409 idempotencyMismatch`.
5. Network failure uses exponential backoff with jitter and honors `Retry-After`. Retry only timeout, 429, and bounded 5xx. Do not retry validation/auth/ownership conflicts automatically.
6. Resume reads `GET /api/sync/status?syncRunId=...`; it never guesses the next chunk. Expired preview requires a new preview and confirmation if counts/conflicts changed.
7. Finalization verifies all chunk hashes and the unchanged preview/source bases, then atomically promotes staging and advances `SyncCursor`. Until finalization, canonical account data is unchanged.
8. Rollback before finalize discards staging. After finalize, rollback is a compensating operation from bounded encrypted snapshots and is allowed only before later revisions; otherwise conflicts require user choice.

### 8.4 Conflict policy

- Character/weapon/talent/artifact aggregate: optimistic compare-and-swap by base revision; do not silently last-write-win. Present local/server summaries and “keep local / keep server / edit” choices.
- Bookmarks: union by stable bookmark/source key; conflicting quantity or deletion is explicit.
- Saved teams: stable team ID and per-team revision; duplicate names do not imply identity.
- Goals/material inventory: record-level compare-and-swap; quantity conflicts are explicit.
- Completion/evaluation history: immutable event/compound key dedup where possible; tombstones win only when their base revision is current.
- App/notification settings: only a documented allowlist; most remain device-local.
- Tombstones carry record ID, deletion revision, and `deletedAt`; retain long enough for the maximum offline window (proposal: 90 days, unresolved) before compaction behind all active cursors.

## 9. Daily Plan cross-platform boundary

Canonical flow:

```text
account-owned source data
  -> server candidate extraction
  -> DeepSeek or deterministic fallback
  -> strict validation
  -> immutable account-scoped proposal persistence
  -> Web/Flutter read
  -> explicit adoption
  -> source revision + fingerprint compare-and-swap
  -> atomic account-data write
```

Required invariants:

- Proposal owner is derived from `AuthContext.accountId`; `clientScope` is removed from authenticated persistence and may remain only as a legacy anonymous cache partition during rollout.
- `sourceRevision` is a server account-data revision/cursor. `proposalFingerprint` is a SHA-256 hash of canonicalized candidate IDs, relevant progress/goals, rule version, date/timezone, and source revision.
- Persist only the validated proposal, model identifier, prompt/schema/rules versions, bounded token/latency metadata, hashes, source, and timestamps. Do not persist raw model response, raw prompt, API key, Cookie, UID, or hidden reasoning.
- Proposal is immutable and expires at the earlier of a bounded TTL or local-day boundary. A source-revision change makes it stale immediately.
- Read returns the same account proposal on Web and Flutter. Device-specific presentation is not persisted.
- Adoption is explicit, one-time, and idempotent. A unique adoption constraint plus compare-and-swap makes simultaneous Web/Flutter attempts yield one success and one identical replay/`409 alreadyAdopted`.
- Adoption revalidates proposal owner, expiry, source revision, fingerprint, task IDs, budgets, and current record revisions inside one transaction. Any failure writes nothing.
- Audit stores proposal ID/hash, source revision, actor session/device, result, request ID, and changed-record counts, not data bodies.

## 10. Proposed data models

Names and scalar types are conceptual. No SQL or Prisma migration is included.

### `Account`

- **Purpose / PK:** canonical user principal; opaque server-generated `id` (UUID-class identifier).
- **Unique:** no email-based account uniqueness. Optional public handle, if ever added, is a separate normalized unique field.
- **FK:** parent of identities, sessions, devices, sync cursors, proposals, and account-owned data.
- **Lifecycle:** `status` (`ACTIVE`, `LOCKED`, `DELETION_PENDING`, `DELETED`), `sessionVersion`, `createdAt`, `updatedAt`, `lastAuthenticatedAt`, `deletionRequestedAt`, `deletedAt`.
- **Revocation/rotation:** bump `sessionVersion` for global logout/security events; `Account.id` never rotates or is overwritten.
- **Audit/retention/cascade:** content cascades through an audited deletion job; minimal pseudonymous security events may be retained under a documented policy. Provider revocation occurs before identity removal where required.
- **Indexes:** `status`, `deletionRequestedAt`; do not expose existence through public lookup.

### `AuthIdentity`

- **Purpose / PK:** credential/provider binding; opaque `id`.
- **Unique:** `(provider, providerSubject)`; passkey `credentialId` is separately unique. Normalized email is not a cross-provider merge key.
- **FK:** required `accountId`; restrict account reassignment except an audited, reauthenticated linking workflow.
- **Fields:** provider, subject/credential public material, email verification metadata if necessary, `createdAt`, `lastUsedAt`, `revokedAt`, `metadataVersion`.
- **Expiry/revocation/rotation:** provider tokens are not stored unless the adapter strictly needs a revocation token; encrypt at rest and retain minimally. Passkey counters/backup flags update on use; compromised credentials revoke individually.
- **Retention/cascade:** removed on account deletion after provider revocation; a tombstoned subject hash may be temporarily retained only for abuse prevention if policy permits.
- **Indexes:** `accountId`, `(provider, providerSubject)`, credential ID.

### `WebSession`

- **Purpose / PK:** one browser session; opaque `id`.
- **Unique:** keyed `tokenHash`; never store or log the raw cookie.
- **FK:** `accountId`; optional `replacedBySessionId` self-reference.
- **Expiry:** `idleExpiresAt`, `absoluteExpiresAt`; proposed 24 hours/30 days.
- **Revocation/rotation:** `revokedAt`, `revocationReason`, `rotationCounter`, and session/account version. Rotate at authentication and security boundaries.
- **Audit fields:** created/last-used/rotated/revoked timestamps, coarse client label, keyed/truncated network risk signal if approved, request ID. No full request headers.
- **Retention/cascade:** active rows cascade/revoke on account deletion; revoked metadata retained for a short abuse window then purged.
- **Indexes:** `tokenHash`, `(accountId, revokedAt)`, `idleExpiresAt`, `absoluteExpiresAt`.

### `DeviceSession`

- **Purpose / PK:** one Flutter installation token family; opaque `id`.
- **Unique:** server-generated `(accountId, deviceId)` and current `refreshTokenHash`; device ID is not hardware-derived.
- **FK:** `accountId`; optional `replacedBySessionId`.
- **Expiry:** short access-token expiry; `refreshExpiresAt` proposed 30 days idle/90 days absolute, subject to product decision.
- **Revocation/rotation:** current/previous token hash, family ID, generation, replay-detected timestamp, revoked timestamp/reason. Every refresh rotates; previous-token reuse revokes family.
- **Audit fields:** sanitized label/platform, app version, created/last-used/rotated/revoked timestamps; no raw token, Cookie, UID, or precise device fingerprint.
- **Retention/cascade:** revoke immediately on logout/account deletion; purge expired metadata after abuse/audit window.
- **Indexes:** `refreshTokenHash`, `(accountId, revokedAt)`, `deviceId`, expiry, family ID.

### `AnonymousIdentity`

- **Purpose / PK:** server-side owner for anonymous browser data; opaque `id`.
- **Unique:** `claimSecretHash`; temporary unique legacy mapping to `gb_user_id` during migration; unique consumed source prevents double claim.
- **FK:** optional `claimedAccountId`; optional `mergeAttemptId` after commit.
- **Expiry:** rolling/absolute anonymous-session expiry; claim preview expiry is separate.
- **Revocation/rotation:** rotate claim secret on privilege boundary/suspicion; revoke on successful claim; legacy cookie alone cannot rotate or claim.
- **Audit fields:** created/last-used/claimed/revoked timestamps and reason; do not store browser fingerprint.
- **Retention/cascade:** anonymous data follows product retention; successful claim removes/re-hashes legacy mapping after rollback window.
- **Indexes:** secret hash, legacy mapping, claimed/revoked/expiry timestamps.

### `AccountMergeAttempt`

- **Purpose / PK:** durable state machine for anonymous-account transfer; opaque `id`.
- **Unique:** `(targetAccountId, idempotencyKey)` and a uniqueness/lock preventing two commits for one source anonymous identity.
- **FK:** `sourceAnonymousIdentityId`, `targetAccountId`, initiating session/device.
- **Fields:** state, preview hash, source/target revisions, per-dataset counts/conflict policy hashes, confirmedAt, committedAt, failedAt, rolledBackAt, safe error code.
- **Expiry/revocation:** preview expires quickly (proposal: 15 minutes); confirmation is invalid after reauth/source revision/session changes.
- **Audit/retention:** request IDs and count/hash metadata only; retain per security/privacy policy, then pseudonymize.
- **Cascade/indexes:** restrict deletion during active attempt; index source/state, target/state, expiry, idempotency key.

### `SyncCursor`

- **Purpose / PK:** per account/device/dataset progress and compaction safety; opaque `id`.
- **Unique:** `(accountId, deviceSessionId, dataset)`.
- **FK:** `accountId`, `deviceSessionId`; cursor never grants access.
- **Fields:** schema version, server revision/cursor, last committed operation/chunk, manifest hash, `updatedAt`, `lastSuccessfulSyncAt`.
- **Expiry/revocation:** invalid when device is revoked; stale cursors expire after the offline-support window and force a new full preview.
- **Audit/retention/cascade:** cascade on account deletion; retain enough to deduplicate operations and protect tombstone compaction.
- **Indexes:** account+dataset revision, device session, expiry/last sync.

Supporting implementation models will likely be required: immutable `AccountAuditEvent`, `SyncRun`/staging rows, proposal/adoption records, and a deletion/export job. Their exact retention and payload minimization are unresolved.

## 11. Proposed API contracts

These are contracts only; no route is added by this design PR.

### 11.1 Global rules

- HTTPS only outside loopback development. Exact allowlisted origins/redirects; no open redirects.
- JSON routes require `Content-Type: application/json` and `Accept: application/json`; unsupported media type is `415`.
- Success envelope: `{ "ok": true, "data": ..., "requestId": "..." }`.
- Error envelope: `{ "ok": false, "error": { "code": "stableCode", "message": "safe localized message", "retryable": false }, "requestId": "..." }`.
- IDs in the body are resource IDs only. Owner/account/session/device identity is derived from auth context.
- Mutation idempotency uses an `Idempotency-Key` header (UUID-class, 24-hour bounded store unless endpoint says otherwise). Same key+same canonical body replays the response; same key+different body is `409 idempotencyMismatch`.
- Web mutations require session cookie + exact Origin/Host + session-bound CSRF header. Flutter bearer calls do not use browser CSRF but require issuer/audience/session checks.
- Distributed account/IP/session rate limits fail closed for high-risk operations; return `Retry-After` without revealing account existence.
- Logs contain request ID, route template, safe error code, account/session keyed hash where needed, latency, and result. Never tokens, cookies, authorization headers, magic links, provider payloads, HoYoLAB identifiers, raw AI text, or sync record bodies.

### 11.2 Endpoint matrix

| Endpoint | Authentication / authorization / CSRF | Content-Type and input | Response | Idempotency / rate | Errors, audit, privacy, retry |
|---|---|---|---|---|---|
| `POST /api/auth/login/{method}/start` | Anonymous or existing session for link mode; link mode requires recent reauth. Web Origin+CSRF; Flutter PKCE channel binding. | JSON: method, platform, exact `returnPath`, PKCE challenge where native, intent=`login|link`. No account ID/email enumeration response. | Challenge/transaction ID and exact authorize URL, or passkey creation/request options; short expiry. | Idempotency optional; 5/min/IP + 3/min/email/provider hint using privacy-preserving keys. | `invalidMethod`, `invalidRedirect`, `rateLimited`, `temporarilyUnavailable`. Audit start outcome only. Retry 429/503 per header. |
| `POST /api/auth/login/{method}/complete` | Valid one-time transaction, state/nonce/PKCE/provider assertion; rotates pre-auth session. | JSON provider callback/assertion fields with strict method schema; provider redirect callback may use documented form encoding only. | Web sets session cookie and returns safe account summary; Flutter returns short access + opaque refresh token once. | Transaction is single-use; exact callback replay returns safe terminal status, not new tokens. | Generic `authenticationFailed`; collision=`identityAlreadyLinked`. Audit provider code and result, not tokens/assertion. Do not auto-retry. |
| `POST /api/auth/logout` | Current Web/Device session. Web CSRF+Origin; Flutter bearer. | JSON `{ scope: "current"|"all" }`; `all` requires recent reauth. | `{ revokedSessionCount }`; expires cookie/returns clear-token instruction. | Naturally idempotent; 10/min/session. | Generic success even if already revoked; audit scope/result. Retry only safe network failure with same key. |
| `GET /api/account` | Valid Web/Device session; account status active. No CSRF. | No body; reject unexpected Content-Type/body. | Minimal account summary, auth methods (masked), sync state, deletion eligibility; no provider subject/token. | Cache `private, no-store`; 60/min/session. | `unauthenticated`, `accountLocked`, `deletionPending`. Safe retry for 429/5xx. |
| `POST /api/account/claim-anonymous` | Valid account session + recent reauth + valid server anonymous cookie on Web. CSRF+Origin. Flutter cannot submit a Web anonymous owner ID. | JSON `{ attemptId, previewHash, confirm: true }`; source/target IDs forbidden. | Committed dataset counts, conflicts resolved, terminal attempt state. | Required idempotency; 3 previews/claims per account/hour. | `anonymousNotFound`, `previewExpired`, `sourceChanged`, `anonymousAlreadyClaimed`, `conflict`, `temporarilyUnavailable`. High-value audit; no row bodies. Retry same key only when marked retryable. |
| `GET /api/devices` | Valid account session; no CSRF. | No body. | Sanitized active/recent device summaries and current marker. | 30/min/account; no shared cache. | No token hashes/IPs. `unauthenticated`. Retry 429/5xx. |
| `DELETE /api/devices/{id}` | Account session, target belongs to account; recent reauth. Web CSRF+Origin. Current device uses logout endpoint. | No body; path ID opaque and strictly parsed. | Generic revoked/already-revoked result. | Idempotent; 10/hour/account. | `notFound` for absent/other-account target (same response), `cannotDeleteCurrent`. Audit target session ID hash. Retry safely. |
| `POST /api/sync/preview` | Valid DeviceSession; Web may later use session with equivalent scope. CSRF for Web. | JSON manifest only: schema/datasets/counts/hashes/tombstones/cursor/dryRun. Account/device IDs forbidden. | Bounded preview token, counts, conflicts, exclusions, chunk limits, revisions, expiry. | Required key; 10/hour/device plus bytes/account/day. | `unsupportedSchema`, `cursorExpired`, `manifestInvalid`, `rateLimited`. Audit counts/hashes only. Retry same key on retryable errors. |
| `POST /api/sync/commit` | Same active DeviceSession and account as preview; preview token bound server-side. | JSON run ID, preview token, chunk index/hash, operations; max records/bytes. | Per-chunk accepted/conflict counts, next expected chunk, status/cursor; final call returns server revision. | Required run/chunk/operation idempotency; byte and write quotas. | `previewExpired`, `chunkOutOfOrder`, `hashMismatch`, `idempotencyMismatch`, `conflict`, `sessionRevoked`. Never log payload. Retry exact chunk only for timeout/429/5xx. |
| `GET /api/sync/status` | Active DeviceSession owning run. No CSRF. | Query `syncRunId`; no body. | Terminal/in-progress state, received chunk indexes, counts, safe conflicts, cursor/expiry. | 60/min/device while active, then lower; no-store. | Other-account run is `notFound`. Poll with bounded backoff and server hint; stop on terminal/auth errors. |
| `GET /api/daily-plan/proposal` | Valid account session; owner derived from session. No CSRF. | Query local date/timezone and optional known fingerprint; strict allowlist. | Current validated immutable proposal, source revision/fingerprint/expiry/adoption state, or empty state. | No mutation; 60/min/account; ETag may be account+proposal scoped, otherwise no-store. | `notFound`, `stale`, `rateLimited`. No raw AI response. Safe retry. |
| `POST /api/daily-plan/proposal/adopt` | Valid account session; Web CSRF+Origin, Flutter bearer; proposal ownership enforced. | JSON proposal ID, fingerprint, expected source revision, explicit confirm. No owner or arbitrary record patch. | Adopted revision, changed record IDs/counts, terminal adoption status. | Required key; unique one-time adoption; 10/day/account. | `expired`, `staleFingerprint`, `sourceChanged`, `alreadyAdopted`, `conflict`. Audit hashes/counts. Retry same key only. |

Account deletion/export need separate reviewed contracts before account launch: deletion must support both in-app initiation and a discoverable Web path, require reauthentication/confirmation, revoke all sessions immediately, revoke provider tokens where required, delete associated content through an auditable job, and disclose any legally retained minimal metadata. Export must be authenticated, asynchronous, encrypted/short-lived, rate-limited, and exclude credentials, secrets, internal abuse signals, raw third-party responses, and other users’ data.

## 12. Logout, revoke, deletion, and privacy

- Logout is session revocation, not data deletion and not HoYoLAB disconnect.
- HoYoLAB unlink deletes only device-held HoYoLAB session material and its derived private caches; it does not revoke Genshin Builder login.
- Account deletion requires recent reauthentication, plain-language scope preview, explicit confirmation, immediate session/device revocation, provider revocation, async content deletion, and completion notice. Both Flutter and Web provide entry points before store submission.
- Deletion covers synced progress, goals, bookmarks, saved teams, plans/proposals/adoptions, sync staging/cursors/tombstones, exports, and user-derived caches. Global master data and public editorial recommendations are not account data.
- Security/audit retention must be purpose-limited, time-bounded, pseudonymized after deletion, documented in privacy disclosures, and approved before implementation.
- Never collect a hardware identifier for device sessions. Avoid full IP/User-Agent retention; use coarse or keyed short-lived risk signals only after a privacy decision.
- Data export and deletion must use the same ownership map and automated inventory tests so newly added datasets cannot be silently omitted.

## 13. Planned migrations (not executed)

1. **Expand:** add account/identity/session/anonymous/audit tables and nullable account/anonymous owner columns; no behavior switch.
2. **Anonymous preparation:** backfill legacy `UserProgress.userId` mappings to `AnonymousIdentity`; issue anonymous secrets; dual-read while still writing legacy-compatible ownership.
3. **Account sessions:** enable provider-neutral test/fake authentication in isolated environments, then separately approved production providers.
4. **Claim:** enable preview/confirm/transactional claim behind a flag; retain legacy source until rollback window ends.
5. **Account-owned reads:** server authorization repository becomes the only consumer-data access path.
6. **Flutter local schema:** add stable record IDs/revisions/tombstones/owner state and migration tests. Revisit SQLCipher before cloud sync.
7. **Sync expand:** staging, cursor, operation dedup, conflict records; dry-run and internal accounts first.
8. **Daily Plan:** add immutable proposal/adoption persistence and source revisions.
9. **Contract:** stop accepting legacy owner keys, remove raw ID display, expire legacy cookie, and only later remove legacy columns after orphan/reconciliation metrics are zero.

Every migration uses expand/backfill/verify/dual-read/cutover/contract. Rollback before contract re-enables the prior read path without deleting source data. No implementation PR may combine irreversible cleanup with first enablement.

## 14. Implementation test plan

| Area | Required tests |
|---|---|
| Web session | fixation rotation, cookie flags/prefix, idle/absolute expiry, DB revocation, missing/expired/locked state, no token in HTML/JS/log |
| Flutter auth | system-browser/PKCE state, token secure storage, 10-minute access expiry behavior, refresh success/failure, restart/reinstall behavior |
| Rotation/replay | every refresh invalidates predecessor; concurrent refresh has one winner; predecessor reuse revokes family; all-device revoke |
| CSRF | missing/wrong token, Origin/Host mismatch, proxy allowlist, SameSite behavior, content-type rejection, Server Action authorization reuse |
| Anonymous claim | preview only, explicit confirm, source revision change, no cookie, forged owner ID, different account, successful atomic transfer, rollback |
| Duplicate claim | concurrent commits, same idempotency replay, different key after consumption, duplicate provider identity and link collision |
| Cross-account denial | every object ID (device, sync run, proposal, export, deletion job) returns indistinguishable not-found/forbidden and never leaks metadata |
| Sync | dry-run, manifest/hash validation, chunk retry/resume/order, operation dedup, cursor expiry, quotas, staging cleanup, atomic finalize |
| Conflict/tombstone | stale base revision, explicit resolution, offline delete/update races, retention/compaction only after cursors, clock skew |
| Daily proposal | account-scoped read, same artifact Web/Flutter, expiry, no raw AI persistence, deterministic fallback validation |
| Adoption | explicit confirmation, stale fingerprint/source revision, one-time CAS, simultaneous Web/Flutter, all-or-nothing writes |
| Logout/revoke | current/all/other device, cookie expiry, Secure Storage clear, access-token bounded lag, HoYoLAB remains independently linked |
| Account deletion/export | reauth, immediate revocation, complete dataset inventory, provider revoke, cache/job cleanup, retention disclosure, other-account denial |
| Security gates | secret scan, log-capture scan for Cookie/token/UID/owner IDs, dependency audit, redirect allowlist, rate-limit distributed behavior, backup/encryption verification |

## 15. Nine-PR implementation sequence

The design PR is not one of these implementation PRs. Branch names are proposals. Each base assumes its predecessor is reviewed and merged; do not stack unrelated unreviewed migrations.

| # | branch | base | migration | endpoints | Web changes | Flutter changes | tests | rollout | rollback | risk |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `feature/account-schema-server-session` | `feature/web-app-foundation` after design merge | Expand-only Account/AuthIdentity/WebSession/DeviceSession/Anonymous/Audit | Internal session repository only; no public login | Server-only auth context and fake adapter in test | None | constraints, expiry, token-hash, no-secret logs | Disabled feature flag; migrate empty tables | Disable reads and revert expand migration if proven safe | High: foundational schema |
| 2 | `feature/web-account-session-ui` | PR 1 | None or session index follow-up | login start/complete, logout, account GET | Login/account UI, CSRF, session cookie, no legacy claim | None | fixation, callback, cookie, CSRF, enumeration | Internal/staging allowlist, then percentage | Disable login; revoke test sessions; anonymous remains | High: auth surface |
| 3 | `feature/flutter-device-auth` | PR 2 | Device-session fields/indexes only if omitted | native login complete/refresh/logout/devices | Device management read foundation | System-browser PKCE/passkey adapter, Secure Storage, token rotation | refresh replay/restart/revoke | Internal devices; short expiry; kill switch | Revoke all device sessions; app returns local-only | High: mobile credential lifecycle |
| 4 | `feature/anonymous-account-upgrade` | PR 3 | Legacy mapping/merge attempt; dual-owner expand/backfill | claim preview/commit | Stop raw ID display; explicit merge UI | No automatic mobile merge | atomic/duplicate/cross-account/rollback | Preparation cookie first; observe; then enable claim | Disable claim; keep anonymous source/dual-read | Critical: ownership transfer |
| 5 | `feature/account-read-apis` | PR 4 | Account owner indexes/backfill verification | read-only progress/bookmarks/teams/account export inventory | Read through auth DAL; anonymous fallback | Read-only account client and diff preview | IDOR/cache/account-state contract | Shadow compare old/new; opt-in reads | Route reads to legacy/local; no source deletion | High: broad read authorization |
| 6 | `feature/bidirectional-account-sync` | PR 5 | SyncRun/staging/cursor/revision/tombstone + Flutter Drift migration | sync preview/commit/status | Sync status/conflict visibility | Explicit preview/confirm/chunk/resume/conflict UI | idempotency/conflict/tombstone/offline/rollback | Dataset allowlist one at a time; internal accounts | Kill writes; discard staging; retain local data | Critical: data loss/corruption |
| 7 | `feature/account-daily-plan-proposal` | PR 6 | Proposal/adoption/source revision | proposal GET/adopt POST; generation internal | Shared proposal read/adopt UI | Replace local-only adoption only after parity | stale/simultaneous/atomic/fallback/privacy | Read-only first, then adoption flag | Disable adoption; local deterministic plan remains | High: concurrent writes |
| 8 | `feature/account-management-deletion` | PR 7 | deletion/export jobs and retention metadata | devices revoke, deletion/export request/status | Account/security/delete/export UI and Web deletion path | In-app delete/export/device UI | complete inventory/provider revoke/reauth | Staff accounts, dry-run inventory, store review checklist | Pause new jobs; resume idempotently; never restore deleted secrets | Critical: compliance/irreversibility |
| 9 | `feature/account-security-release-gates` | PR 8 | Only proven index/retention hardening | No new product endpoint | CSP/log redaction/rate dashboards/recovery drills | backup/encryption/secure-storage release checks | threat suite, pentest, secret/log/dependency scans, load/rate | Gradual production gate with alerts and incident playbook | Global auth/sync kill switches; revoke token families | High: release assurance |

## 16. Unresolved decisions

- Final authentication broker/library and whether it is managed or self-hosted.
- Initial production method set, passkey recovery, recovery-code support, and requirements before removing the last linked method.
- Production Web RP ID and staging/local associated-domain strategy.
- Whether the app targets children/minors; neutral age screen, parental consent, provider terms, privacy disclosures, and data-safety declarations.
- Exact session idle/absolute durations, device ceiling, token signing/opaque access choice, key rotation, and distributed revocation cache.
- Legacy anonymous-data retention, claim rollback window, orphan cleanup, and acceptable proof for old rows.
- Dataset-by-dataset conflict UI and whether personal gacha pull history will exist at all.
- Tombstone/offline window, sync quota, chunk size, and encrypted staging/snapshot retention.
- SQLCipher/default local encryption decision before cloud sync.
- Account deletion/audit/legal retention periods and provider-specific revocation artifacts.
- Data-export format, encryption/delivery, and operational SLA.
- Daily-plan account timezone/day-boundary rules, proposal TTL, and source-revision granularity.
- Distributed rate-limit store, privacy-preserving keys, alert thresholds, and incident owner.
