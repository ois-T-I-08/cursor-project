# ADR 0001: Local database encryption (SQLCipher) strategy

Status: **Proposed** (no destructive migration until accepted)  
Date: 2026-07-26  
Related: Issue #11, `docs/DB_ENCRYPTION.md`

## Context

The Flutter app currently uses Drift/SQLite. Encryption is opt-in via build flags and is **off by default**. Sensitive items (HoYoLAB cookies) already live in Secure Storage, not in the plaintext DB. User progress and master data sit in the local DB.

## Decision drivers

- Encrypt data-at-rest that would harm users if device backup/forensics exposed it
- Avoid forcing a one-way migration before key management and rollback are proven
- Keep Android backup disabled (already a release requirement)
- Prefer boring, maintainable libraries

## Current state

- Plaintext SQLite via Drift is the default
- Optional SQLCipher path is documented in `DB_ENCRYPTION.md` but plaintext→encrypted migration is **not implemented**
- Secure Storage holds cookies / secrets
- Android backup is disabled in release hardening

## Data classification

| Data | Location today | Needs DB encryption? |
|------|----------------|----------------------|
| HoYoLAB cookies / tokens | Secure Storage | No (already encrypted at rest by platform) |
| User progress / goals | SQLite | Nice-to-have |
| Master data (Amber) | SQLite | Low (public game data) |
| Battle statistics cache | SQLite | Low |
| Sync leases / settings | SQLite | Low–medium |

## Options

1. **Keep plaintext DB + Secure Storage for secrets** (status quo)
2. **Opt-in SQLCipher** with explicit migration UX
3. **Force SQLCipher for all installs** (rejected until migration proven)

## Proposed direction (not yet accepted)

Pursue option 2 only after acceptance criteria below. Do **not** ship a forced migration in the same change as feature work.

### Key management

- Generate a random DB key on first encrypted open
- Store key in Secure Storage (Android Keystore / iOS Keychain)
- Never log the key; never put it in dart-define for production users

### Migration

1. Detect plaintext DB on upgrade
2. Copy into encrypted DB in a temp file
3. Verify row counts / checksums
4. Atomically replace; keep plaintext backup until N successful launches
5. On failure: keep plaintext, surface user-facing error, do not delete source

### Rollback / reinstall / device change

- Rollback: feature flag off → continue plaintext if migration not finalized
- Reinstall: new empty encrypted DB; no cloud restore of progress
- Device change: no automatic DB transfer (local-first policy)

### Android backup

- Keep `android:allowBackup="false"` and related excludes
- Encrypted DB does not justify enabling backup

### Performance / maintenance

- Measure cold start and large sync write costs on mid-tier devices
- Prefer actively maintained SQLCipher Flutter bindings; pin versions
- Alternative: continue Secure Storage-only for secrets if threat model stays cookie-centric

## Consequences

- Accepting this ADR does **not** authorize a production migration PR by itself
- A separate implementation PR must include migration tests, failure drills, and rollback docs
- Until accepted, do not run destructive DB resets or force-encrypt existing installs
