# Account and synchronization threat model

Status: Proposed release gate

Date: 2026-08-06

System: Genshin Builder Web + Flutter + Next.js account/sync services

Related: `CROSS_PLATFORM_IDENTITY.md`

## 1. Scope and assets

This threat model covers the proposed canonical account, Web and device sessions, anonymous upgrade, account-owned data APIs, Flutter synchronization, Daily Plan proposal/adoption, logout/revocation, export, and deletion. It also records current-state blockers found during the code audit.

Protected assets:

- canonical `Account.id` and all account-owned progress, goals, inventory, bookmarks, teams, plans, proposals, and history;
- Web opaque session tokens, Flutter access/refresh tokens, passkey/provider identities, login challenges, and anonymous claim secrets;
- sync manifests, staged records, revisions, tombstones, idempotency records, cursors, exports, deletion jobs, and audit events;
- HoYoLAB Cookie/UID/region and database key on Flutter, which remain outside Genshin Builder authentication and sync;
- provider secrets, AI keys, admin/sync Bearer secrets, and operational configuration on the server.

Trust zones:

1. untrusted browser JavaScript and network input;
2. Flutter UI/Drift as a potentially compromised client, with Secure Storage as a stronger but not infallible local boundary;
3. Next.js authentication/authorization/data-access layer;
4. database, distributed rate/idempotency store, audit, and encrypted staging/export storage;
5. external identity, email, AI, and HoYoLAB providers.

Assumptions that must be validated before production:

- TLS terminates only at approved infrastructure and forwarded Host/IP headers are normalized by a trusted proxy.
- Production and staging have distinct issuer/audience, redirect allowlists, keys, cookies, and databases.
- Database transactions/locking can provide the isolation required by claim, sync finalize, and proposal adoption.
- Observability can redact request headers/bodies before application logging and third-party telemetry.
- A user device and browser can be compromised; server authorization cannot trust client owner IDs, timestamps, revisions, or UI confirmations without server state.

## 2. Threat register

Risk uses `Critical`, `High`, `Medium`, or `Low` for the proposed account release. “Residual” is the risk remaining after the mitigation.

| Threat | Risk | Affected component | Required mitigation | Test requirement | Residual risk |
|---|---|---|---|---|---|
| Session fixation | High | Web login/anonymous upgrade | Rotate pre-auth and anonymous session IDs at login/claim; issue a fresh opaque `__Host-` cookie; bind callback challenge to the initiating browser; invalidate predecessors | Pre-set attacker session, complete login, prove token/session ID changed and old token cannot read account | Low: same-device malware can act within a valid session |
| CSRF | High | Web logout, claim, sync, adopt, deletion/linking | `SameSite=Lax`, exact Origin/Host, session-bound CSRF token, JSON Content-Type, no GET mutations; keep Next.js Server Action checks and call the same authz service | Missing/wrong/replayed token, cross-origin form/fetch, proxy Host cases, simple-content-type attacks | Low: same-origin script/XSS bypasses CSRF controls |
| XSS token theft/action abuse | High | Web UI/session | HttpOnly session cookie; no long-lived bearer in JS; strict output escaping/sanitization; CSP/Trusted Types evaluation; never render legacy owner/session token; reauth high-risk actions | Stored/reflected payload corpus, DOM scan for token/owner values, CSP report tests, action attempted from injected same-origin script | Medium: XSS can still act as user until session revoked |
| Refresh-token replay | Critical | Flutter refresh endpoint/device session | High-entropy opaque refresh tokens, hashed at rest, rotate every use, token-family generation, atomic single winner, reuse detection revokes family, alerts | Sequential and concurrent predecessor reuse, intercepted response replay, family revoke, no token in logs | Low/Medium: attacker with current token can win a race and force reauth |
| Stolen device | High | Flutter Secure Storage/DeviceSession/local Drift | Platform Secure Storage, device session list/revoke, short access TTL, optional local biometric gate for high-risk actions, no hardware ID, local encryption decision before sync | Revoke while offline, expired access, refresh denial, app restart, secure clear, local DB inspection under release config | Medium: unlocked rooted/jailbroken device can expose local data/session |
| Anonymous claim hijack | Critical | Legacy `gb_user_id`, `AnonymousIdentity`, claim flow | Do not claim with `gb_user_id`; first issue server-held anonymous secret; never accept source/target owner IDs; explicit preview+reauth+confirmation; atomic consumed uniqueness; revoke source | Guessed/copied legacy ID, missing anonymous secret, different browser/account, concurrent claims, source change, rollback | Low/Medium during legacy preparation window; possession of migrated anonymous secret remains bearer proof |
| Account enumeration | High | Login, magic link, recovery, account GET | Generic status/timing, uniform work where practical, privacy-preserving distributed rate limits, no “email exists”, no public account lookup | Existing/non-existing/provider-linked identifiers have same status/envelope and statistically bounded timing | Low: provider UI or mail delivery side channels remain |
| OAuth state/nonce failure | Critical | Provider callback | One-time high-entropy state, OIDC nonce, PKCE for native/public flows, short challenge expiry, session/channel binding, exact issuer/audience/time/signature validation | Missing/wrong/replayed state/nonce/verifier, mix-up issuer, expired challenge, concurrent starts | Low with audited standards library |
| Redirect URI abuse | Critical | Login start/callback/deep links | Exact pre-registered redirect URIs; server maps small return-path allowlist; no client-supplied absolute URL; HTTPS/app association; external system browser | Scheme/host/userinfo/port/path variants, encoded traversal, open redirect chain, unclaimed app link | Low: domain/app-association compromise remains |
| Duplicate provider identity/account | High | `AuthIdentity`, linking/recovery | Unique `(provider, subject)`/credential ID; never auto-merge by email; linking requires active session and reauth of both identities; collision is safe 409; audited recovery | Concurrent create/link, Apple relay email, Google/Apple same email, recycled email, unlink last method | Low/Medium: support-assisted recovery remains social-engineering target |
| IDOR | Critical | Every account/device/sync/proposal/export/deletion object | Resolve account from session; repository requires `AuthContext`; never mass-assign owner; scope every query by account; same not-found response for foreign ID | Cross-account matrix for every route and nested object, sequential/UUID guessing, revoked/deleted account | Low if centralized authz cannot be bypassed |
| Cross-account cache leak | Critical | Daily Plan, team jobs, API/cache/CDN | Include canonical account+authorization revision in private cache key; `private, no-store` for sensitive responses; never use `clientScope` as account scope; purge on revoke/delete; prevent CDN storage | Two accounts with identical inputs, cache warm/cold, logout/login switch, proxy/CDN headers, process reuse | Low; misconfigured external CDN remains a release gate |
| Sync replay | High | Sync preview/commit/staging | Preview bound to account+device+manifest+expiry; run/chunk/operation idempotency; hash canonical body; dedup retention; monotonic cursor; revoked device denial | Identical replay, same key changed body, old preview after account change, cross-device/run chunk injection | Low/Medium after dedup retention expires; force full preview then |
| Stale write | High | Sync records/Daily Plan adoption | Compare-and-swap base/server revision, source fingerprint, proposal expiry, conflict response; server time/revision authoritative; no silent last-write-win for aggregates | Offline edit race, clock skew, stale fingerprint, simultaneous Web/Flutter adoption, tombstone/update race | Medium: user must resolve legitimate semantic conflicts |
| Mass assignment | Critical | Account/claim/sync/adopt JSON | Strict schemas reject unknown fields; DTO allowlists; owner/account/session/device/status/revision server-managed; repository accepts domain commands not ORM input | Fuzz unknown/nested prototype/owner fields, overlong arrays, duplicate JSON keys policy, ORM-input type exclusion | Low with strict parser and review |
| Log/telemetry leakage | Critical | App/server logs, crash/analytics, audit, provider/AI clients | Central redaction before logging; never log Authorization/Cookie/magic link/PKCE/refresh/HoYoLAB/owner IDs/raw AI/sync bodies; safe error codes; keyed IDs only where needed; retention limits | Capture logs for success/error/timeouts and scan seeded canary secrets/UIDs/body fragments; verify third-party telemetry | Low/Medium: infrastructure logs need separate validation |
| Brute force/abuse | High | Login/magic link/passkey challenge, claim, refresh, sync/AI | Distributed per-account/device/IP/risk quotas, exponential backoff, `Retry-After`, generic response, mail/AI byte/cost budgets, anomaly alert; process-local maps are insufficient | Multi-instance bypass, IPv6 rotation, account spray, mail flood, large body, AI/sync cost exhaustion | Medium: botnets/shared NAT require tuned risk controls |
| Incomplete logout | High | Web/Device sessions, caches, Secure Storage | Explicit current/all/device revoke; account session version; expire cookie and clear Secure Storage; reject refresh immediately; short access TTL; purge account caches; HoYoLAB unlink stays separate | Old Web cookie, old/current refresh, access until/after expiry, offline device, cached sensitive response, all-device flow | Low/Medium during short access-token TTL |
| Incomplete deletion | Critical | All datasets/providers/caches/jobs/backups | Central data inventory, reauth+confirmation, immediate session revoke, provider revoke, idempotent deletion job, referential constraints, cache/export/staging cleanup, documented retention, completion status | Seed every owned dataset and derived cache/job, delete, prove inaccessible/removed or explicitly retained; retry partial provider outage | Medium: backup/legal-retention erasure depends on infrastructure policy |

## 3. Additional checklist threats

| Threat | Risk | Required control and test |
|---|---|---|
| HoYoLAB credential boundary regression | Critical | Cookie/UID/region stay in Secure Storage and never enter app authentication, sync, export, AI, analytics, or logs. Tests seed canary Cookie values and scan all outgoing account/sync requests and logs. Save only after verification+role discovery; disconnect purges derived private caches. |
| Local plaintext account data | High before cloud sync | Revisit mobile ADR 0001 before production sync. Decide SQLCipher or explicitly accepted residual risk; test Android backup state, database-at-rest behavior, key loss, migration failure, and rollback. Never place credentials in Drift even if encrypted. |
| Supply-chain compromise | High | Lockfiles, minimal auth/crypto dependencies, provenance/SBOM and vulnerability/license scan, reviewed update automation, release signing, no abandoned custom crypto. `npm audit --omit=dev`, Flutter dependency audit, and secret scan are release evidence, not the only control. |
| Provider/AI outage or malformed response | Medium | Fail closed for authentication; deterministic fallback for Daily Plan; strict bounded schemas; no raw response persistence. Contract, timeout, retry-budget, and circuit-breaker tests. |
| Export-link theft | High | Separate encrypted one-time short-lived download secret, reauth, no URL analytics/referrer leakage, no credentials/other users/internal risk fields, automatic deletion. Test replay, expiry, cross-account and referer/log scans. |

## 4. Current audit findings

Severity here means impact on safely releasing common accounts/sync, not necessarily an exploitable production account vulnerability today.

### BLOCKER

1. **No canonical consumer account or revocable session exists.** Current `gb_user_id` progress ownership, Flutter local UUID, and `clientScope` cannot authorize shared account data. Account/sync endpoints must not ship until server account/session/authz primitives exist.
2. **Legacy anonymous ownership is not safe for direct claim.** `gb_user_id` is unsigned, five-year, unrotated, non-revocable, and rendered in `/settings`. A server-managed `AnonymousIdentity` preparation phase is required before an account-claim feature.
3. **Deletion/export lifecycle is absent.** Account launch must include an owned-data inventory and reviewed deletion design; app-store account deletion paths are release gates.

### HIGH

1. **Raw legacy owner ID is rendered to the Web page.** Remove it before anonymous upgrade and never treat it as a secret/account credential.
2. **Raw caught errors are logged in progress actions and some routes.** Centralize safe logging and prove canary tokens, owner IDs, sync bodies, and HoYoLAB data are absent.
3. **Current rate limits are process-local and incomplete across public computation routes.** They do not provide distributed brute-force, mail, refresh, sync-byte, or AI-cost control required by accounts.
4. **Current Daily Plan cache is keyed by client-supplied `clientScope`.** This is acceptable only as an unauthenticated best-effort cache partition; account persistence/read must use server-derived `Account.id` and private cache semantics.
5. **Flutter user data is plaintext under the accepted v1 ADR.** Cloud sync changes the threat/privacy profile and triggers the ADR’s mandatory reconsideration.

### MEDIUM

1. Flutter bookmarks and `app_settings` are device-global, while several other Drift tables use local `userId`; owner migration must classify each key before sync.
2. Web bookmarks are unscoped localStorage and disappear with browser storage; they require an explicit, conflict-aware account migration.
3. Team-recommendation job reads currently rely on UUID job IDs rather than account ownership. Do not reuse this capability-style pattern for account data.
4. Current user-data audit is limited to non-account operational domains; merge/sync/adopt/revoke/delete require a minimal separate audit model.
5. Full development-dependency audit reports high-severity `brace-expansion` denial-of-service advisories through the ESLint toolchain, while `npm audit --omit=dev` reports zero production vulnerabilities. Update and verify the lint dependency chain in a separate supply-chain PR rather than applying an unreviewed audit fix here.

### LOW / POSITIVE CONTROLS

1. HoYoLAB Cookie/UID/region are isolated in `flutter_secure_storage`, the Cookie is saved only after verification and role discovery, and disconnect deletes session items.
2. Flutter `clientScope` hashes the local UUID and current Daily Plan validation rejects malformed/unknown data and rechecks proposal fingerprints.
3. Admin/sync Bearer comparisons are timing-safe, missing production secrets fail closed, and user-facing errors are generally generic.
4. The current consumer API client omits credentials, rejects redirects, bounds response size/time, and validates JSON contracts; authenticated account clients must be separate and explicit.

## 5. Security verification gates

No implementation may progress to broad production rollout until all applicable gates are evidenced:

- threat register tests mapped to test IDs and CI jobs;
- session/refresh/anonymous/sync/adoption concurrency tests against the real database isolation level;
- cross-account authorization matrix for every endpoint and data-access function;
- multi-instance distributed rate-limit and idempotency tests;
- canary-secret log, telemetry, HTML, local DB, export, cache, and crash-report scans;
- exact redirect/Origin/RP-ID/app-link/associated-domain review for production and staging;
- provider deletion/revocation and outage drills;
- account data inventory test that fails when a new owner-bearing model lacks export/deletion policy;
- mobile backup/encryption/Secure Storage behavior verified on supported Android/iOS versions;
- dependency vulnerability/provenance/license review and signed release artifacts;
- incident playbooks for credential replay, mass revocation, account-claim error, sync corruption, provider compromise, and deletion backlog;
- documented residual-risk acceptance by the product/security owner.

## 6. Audit event minimization

Allowed audit fields: event type/version, timestamp, outcome/safe reason, request ID, actor account/session/device internal ID or keyed hash, target internal ID, source/server revisions, proposal/manifest hash, dataset counts, bytes, and operator action ID.

Forbidden audit/log fields: raw session/refresh/access/anonymous tokens, Cookie or Authorization headers, magic links/codes, PKCE verifier, passkey assertion bodies, provider ID/access/refresh tokens, provider subject/email unless an encrypted narrowly approved recovery record requires it, HoYoLAB Cookie/UID/raw response, complete sync records, memo text, AI prompt/raw response, export contents, secrets, or full device fingerprints.

Audit data is not a hidden backup of deleted user content. Retention, access control, pseudonymization, deletion exceptions, and incident access must be approved before schema implementation.
