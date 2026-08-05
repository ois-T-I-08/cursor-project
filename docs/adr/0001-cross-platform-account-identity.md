# ADR 0001: Cross-platform account identity and session boundary

Status: **Proposed**

Date: 2026-08-06

Decision owners: Product, Web, Mobile, Security, Privacy (approval pending)

Related: `../architecture/CROSS_PLATFORM_IDENTITY.md`, `../architecture/ACCOUNT_SYNC_THREAT_MODEL.md`

## Context

Genshin Builder currently has three unrelated identifiers:

- Web progress is keyed by an anonymous `gb_user_id` cookie and Prisma `UserProgress.userId`.
- Flutter data is keyed by a device-local UUID in Drift. A truncated SHA-256 scope is sent to the unauthenticated Daily Plan enrichment API for cache partitioning.
- HoYoLAB has its own Cookie and game UID in Flutter Secure Storage.

None is a revocable, cross-platform Genshin Builder account. The repository has no consumer Account/AuthIdentity/WebSession/DeviceSession model, no account deletion/export, and no safe anonymous-account claim. Adding sync directly to any current identifier would turn a cache/local key or third-party credential into an authorization boundary and create cross-account data-loss risk.

## Decision

Adopt a provider-neutral server identity architecture with these invariants:

1. The server generates one immutable, opaque canonical `Account.id`. It is never derived from email, provider subject, HoYoLAB UID, game UID, browser ID, Flutter `localUserId`, or `clientScope`.
2. Authentication adapters create/link unique `AuthIdentity(provider, providerSubject)` records. Provider email is an attribute, not an automatic merge key. Identity linking requires reauthentication and collision handling.
3. Web uses a DB-backed, revocable `WebSession` with a random opaque `__Host-` httpOnly Secure SameSite cookie. Browser JavaScript receives no refresh token or long-lived bearer token.
4. Flutter uses one revocable `DeviceSession` per installation/login, short-lived access tokens, rotating opaque refresh tokens in Secure Storage, and token-family replay detection. Device ID is server-generated and not a hardware fingerprint.
5. HoYoLAB Cookie/UID/region stay device-local and outside Genshin Builder authentication, synchronization, export, AI, logs, and analytics.
6. `gb_user_id` is legacy ownership only. Before account login is exposed, the server upgrades the browser to a hashed-secret `AnonymousIdentity`. Claim requires server detection, preview, recent reauthentication, explicit user confirmation, an idempotent atomic transfer, audit, rollback evidence, and old anonymous-session revocation.
7. `clientScope` remains a non-secret best-effort local/cache scope only. Authenticated APIs derive account and device from the validated session and reject owner fields in client payloads.
8. Account-owned data uses server revisions, strict authorization, tombstones, idempotency, conflict detection, and staged atomic sync finalization. Initial Flutter upload is explicit, previewed, confirmed, resumable, and excludes credentials.
9. Daily Plan becomes an immutable account-scoped validated proposal. Web and Flutter read the same proposal and adopt it explicitly using source revision and fingerprint compare-and-swap in one transaction. Raw AI responses are not persisted.
10. Account launch requires session/device revoke, all-device logout, in-app and Web deletion initiation, complete associated-data deletion/export inventory, minimal audit retention, distributed abuse controls, and security release gates.

### Authentication method direction

The target is passkey-first with multiple linked authenticators. Google and Apple can be optional adapters in separately reviewed PRs. Email may support verification or controlled recovery but is not the sole high-assurance authenticator. Anonymous use remains available.

This ADR does not select an authentication vendor, create provider configuration, add secrets, or authorize a production authentication implementation.

## Alternatives considered

### A. Use `gb_user_id` as the common account

Rejected. It is unsigned, unrotated, non-revocable, browser-specific, and currently rendered in settings. Possession is not adequate proof for a production account, and it cannot model sessions/devices/recovery.

### B. Use Flutter `localUserId` or `clientScope`

Rejected. The local UUID is an installation data key and the scope is a 48-bit truncated hash used for cache/notification names. Neither has authentication, server issuance, revocation, or cross-device proof.

### C. Use HoYoLAB Cookie or UID as Genshin Builder authentication

Rejected. The Cookie is a third-party credential with high compromise impact, must remain in Secure Storage, and is not a stable or authorized first-party account mechanism. UID is a game profile identifier, not proof of current user control.

### D. Provider subject as primary key

Rejected. It couples data ownership to one provider, complicates multiple identities and provider migration, and encourages unsafe email/subject merges. A separate canonical account keeps providers replaceable.

### E. Stateless Web JWT and long-lived mobile bearer tokens

Rejected. Immediate per-session/device revoke, refresh replay detection, all-device logout, deletion, and audit would be weaker or require reintroducing server state. Long-lived browser/mobile bearer exposure increases theft impact.

### F. Email magic link only

Rejected as the target. It is operationally accessible but depends on mailbox security, delivery/reputation, phishing resistance, and recovery semantics. It can be a bounded verification/recovery mechanism after separate review.

### G. Passkey only with no recovery/linking

Rejected. It minimizes passwords and provider data but risks lockout when credential sync/transfer is unavailable. The account must support multiple authenticators and an approved recovery policy.

### H. Automatic last-write-wins sync

Rejected. Character aggregates, goals, inventory, teams, and plan adoption can lose meaningful edits. Server revisions and explicit conflicts are required; only proven commutative/immutable datasets may auto-merge.

### I. Automatic anonymous merge on login

Rejected. Shared browsers and stale cookies can attach another person’s data. Login creates a session only; claim is a separate preview/confirmation transaction.

## Consequences

### Positive

- One authorization model serves Web, Android, iOS, multiple devices, logout, revoke, deletion, export, sync, and Daily Plan.
- Provider lock-in is contained in `AuthIdentity` adapters.
- Legacy anonymous and Flutter local data can remain useful until the user opts in.
- HoYoLAB credentials stay isolated from first-party identity.
- Session/device-level incident response and token replay handling become possible.
- Ownership, cache, audit, deletion, and sync tests can share one canonical account context.

### Costs and risks

- This is a multi-PR program with high concurrency, migration, privacy, and operational complexity.
- Passkey and native provider support require stable production/staging domains and app associations.
- Anonymous claim and first sync need user-facing conflict/rollback flows, not just backend tables.
- Distributed rate limiting, idempotency, audit, staging, export, deletion, and key management add infrastructure.
- Flutter local encryption must be reconsidered before cloud sync.
- Multiple provider identities create recovery/support and duplicate-account processes.
- Account features trigger App Store/Google Play deletion and privacy obligations, including a Web deletion path for Google Play.

## Rollout

Use expand/backfill/dual-read/cutover/contract stages and the nine implementation PRs in the architecture document.

1. Add disabled provider-neutral schema and authorization services.
2. Issue server-managed anonymous sessions while retaining legacy reads; stop exposing raw `gb_user_id`.
3. Enable Web sessions for staff/staging without anonymous auto-claim.
4. Enable Flutter device sessions and revocation for internal accounts.
5. Enable anonymous preview/claim behind a separate kill switch, retaining source data through a rollback window.
6. Add read-only account APIs, then dataset-by-dataset sync preview/dry-run.
7. Enable staged sync commit for internal accounts and one dataset at a time.
8. Add account Daily Plan read before adoption.
9. Complete deletion/export, distributed abuse controls, security/privacy gates, incident drills, and store disclosures before broad rollout.

Metrics use counts, rates, safe error codes, revisions, and latency only. They must not include tokens, owner IDs, HoYoLAB data, raw user records, or AI responses.

## Rollback

- Every behavior change has an independent kill switch: login, claim, account reads, sync preview, sync commit, proposal read, adoption, deletion/export.
- Before contract cleanup, rollback returns reads to legacy/local sources and revokes newly issued sessions without deleting anonymous/Flutter data.
- Failed anonymous claim keeps source ownership intact; a committed claim uses a bounded ownership manifest for a guarded compensating rollback only if target revisions have not advanced.
- Failed sync discards staging. Finalized sync can use a bounded compensating snapshot only before later revisions; otherwise stop for conflict resolution.
- Provider outages disable new login/linking, not existing validated sessions unless compromise requires mass revocation.
- No first-enable PR removes legacy columns, source rows, local data, or tombstones. Irreversible cleanup is a later, metrics-gated contract PR.
- Account deletion itself is not silently rolled back. It requires deliberate confirmation, immediate revocation, idempotent deletion status, and legally/privacy-approved retention behavior.

## Security and privacy requirements

- Central `AuthContext` and account-scoped repositories; no route constructs an owner from request JSON.
- Strict schemas, CSRF/Origin controls, exact redirects, OAuth state/nonce/PKCE, passkey challenge validation, session fixation prevention, refresh rotation/replay detection, and distributed rate limits.
- Tokens, Cookies, credentials, raw provider/AI/sync bodies, and HoYoLAB identifiers are forbidden from logs/audit/analytics.
- Account deletion/export use an automated owned-data inventory and include derived caches/jobs/staging.
- Device labels and risk data avoid hardware fingerprints and unnecessary precise IP/User-Agent retention.
- Child/minor target-audience, parental consent, provider terms, and data-safety decisions are release blockers, not defaults inferred by engineering.

## Unresolved decisions

- Authentication broker/library/vendor and key-management system.
- Initial method set, passkey recovery, recovery codes, and identity-link/unlink rules.
- Production RP ID, associated domains, native deep links, and staging isolation.
- Session/token durations, signing versus opaque access token, device ceiling, and risk signals.
- Anonymous rollback/orphan retention and conflict rules per dataset.
- Sync offline/tombstone window, quotas, encryption, staging retention, and Flutter SQLCipher decision.
- Account export/deletion SLA, audit/legal retention, and backup handling.
- Minor/child audience and consent policy.
- Daily Plan timezone, proposal TTL, and source revision granularity.

The ADR remains **Proposed** until these decisions have owners and the Product, Web, Mobile, Security, and Privacy reviewers accept the release gates.
