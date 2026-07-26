# ADR 0001: Local database encryption (SQLCipher) strategy

Status: **Accepted** (v1.0)  
Date: 2026-07-26  
Related: Issue #11, `docs/DB_ENCRYPTION.md`  
Owner decision: 2026-07-26

## Context

The Flutter app uses Drift/SQLite. Sensitive items (HoYoLAB cookies / tokens) already live in platform Secure Storage. User progress, master data, and statistics caches sit in the local DB. Android application backup is disabled.

## Decision (v1.0)

```text
v1.0:
- User progress, master data and statistics cache remain in Drift/SQLite.
- HoYoLAB cookies, tokens, database keys and other secrets must use platform Secure Storage.
- Android application backup remains disabled.
- Forced plaintext-to-SQLCipher migration is not implemented or enabled.
```

### Adopted option

**Option 1:** Keep plaintext Drift/SQLite for non-secret local data. Store secrets exclusively in platform Secure Storage.

### Rejected for v1.0

**Option 2 / 3:** Forced or default-on SQLCipher migration for all installs. Not implemented and not exposed as a production user setting.

## Data classification

| Data | Location | DB encryption required in v1.0? |
|------|----------|----------------------------------|
| HoYoLAB cookies / tokens | Secure Storage | No (platform secure storage) |
| Optional DB encryption key material | Secure Storage (if present) | N/A — unused for forced encryption |
| User progress / goals / bookmarks | Drift/SQLite | No (plaintext accepted for v1.0) |
| Master data (Amber) | Drift/SQLite | No |
| Statistics cache | Drift/SQLite | No |

## Dependencies

Do not casually remove SQLCipher-related libraries if they are still required to open the current plaintext Drift/SQLite stack. Do not publish unverified encryption toggles to end users.

## Revisit Option 2 (SQLCipher) when any of the following becomes true

* Cloud sync is introduced
* Personal data beyond current progress is stored in the DB
* DB backup or export is introduced
* Cross-device sync is introduced
* More sensitive data is stored locally
* The threat model changes materially

Any future SQLCipher work requires a separate implementation PR with migration tests, failure drills, and rollback docs. No destructive DB reset or forced encrypt of existing installs is authorized by this ADR alone.

## Consequences

- Issue #11 acceptance criteria for v1.0 are met by this Accepted ADR + Option 1
- Production users must not be offered an untested “encrypt database” switch
- Android `allowBackup=false` (and related excludes) remain mandatory
