# Pre-release validation checklist

Target branch: `release/pre-release-validation`  
Base: `main`

Do **not** record secrets, keystore passwords, HoYoLAB cookies, tokens, or device account credentials in this file.

## Build identity (fill when signing is available)

| Field | Value |
|-------|--------|
| Target commit | |
| applicationId | `io.github.oisti08.genshinbuilder` |
| versionCode / versionName | from `pubspec.yaml` / Flutter |
| Build datetime | |
| APK size / SHA-256 | *blocked until local release signing exists* |
| AAB size / SHA-256 | *blocked until local release signing exists* |
| APK signature verify | *not run* |
| Device / Android version | |
| Reviewer / date | |

## Automated gates

| Gate | Status | Notes |
|------|--------|--------|
| Mobile tests | 571 passed (local) | |
| Domain parity (3) | passed | |
| `flutter analyze` | 0 errors / 0 warnings | info only |
| Web tests | 111 passed (local) | includes cooperative abort |
| Web lint | passed | |
| Web production build | passed | |
| Secret Guard | passed (local) | |
| Genshin Mobile CI | | fill after push |
| Genshin Web CI | | fill after push |

## Feature gates

### P1-8C — 23:00 incomplete Daily Plan notification

| Check | Pass? | Notes |
|-------|-------|--------|
| Completion persistence (per user / localDate / itemKey) | code | device E2E pending |
| Checkbox UI complete / incomplete | code | device E2E pending |
| WorkManager unique one-off to next local 23:00 | code | device E2E pending |
| Catch-up after 23:00 when unevaluated | code | device E2E pending |
| `targetLocalDate` preserved on delayed run | unit | device E2E pending |
| Settings toggle independent of P1-8B | code | |
| Permission request only from settings | code | |
| Logout / OFF cancels P1-8C work only | code | device E2E pending |
| Notification tap → Daily Plan | code | device E2E pending |
| No secrets in notification body/payload/logs | unit | |

### Distributed sync lease + cooperative abort

| Check | Pass? | Notes |
|-------|-------|--------|
| `renewSyncLease` owner+unexpired | unit | |
| Heartbeat ≈ TTL/3 (120s default) | unit | |
| Ownership loss aborts shared signal | unit | |
| Default runner checks signal before later phases / writes | unit | |
| `fullUpgrade` does not open replacement TX after ownership loss | code | |
| Release only matching owner token | unit | |
| Timer cleared in `finally` | unit | |
| API/Action map ownership loss to safe 409 | unit | |

### Release signing & install (human)

| Check | Pass? | Notes |
|-------|-------|--------|
| `android/key.properties` present locally (not committed) | | Required for APK/AAB |
| keystore ignored by git | yes | |
| Signed release APK | | |
| Signed release AAB | | |
| Fresh install → schema v9 | | Device required |
| Upgrade install schema v8 → v9 | | Device required |
| Upgrade install schema v7 → v9 | | Device required |

## Device migration paths (do not mark pass without running)

### A. Fresh install → schema v9

1. Uninstall any previous build.
2. Install signed release APK.
3. Confirm first launch, DB create, home / characters / daily plan / teams.
4. Record Pass/Fail: ____

### B. schema v8 → v9

1. Prepare a v8 data set (progress, goals, teams, events, inventory, bookmarks, upgrades).
2. Install release APK over it.
3. Confirm: no DB wipe; tables `daily_plan_completions` / `daily_plan_eval_history` exist; user data retained; no duplicate rows; relaunch stable.
4. Record Pass/Fail: ____

### C. schema v7 → v9

1. Prepare v7 DB including legacy `local` user id rows where applicable.
2. Install release APK over it.
3. Confirm: legacy user id → UUID; growth/progress/team/inventory/events retained; new daily-plan tables created; no DB delete on failure paths; downgrade still rejected without wiping.
4. Record Pass/Fail: ____

## 23:00 notification E2E (do not mark pass without running)

| Scenario | Pass? | Observed delay | Notes |
|----------|-------|----------------|-------|
| Permission allowed | | | |
| Permission denied (no dialog from worker) | | | |
| Incomplete items → notify | | | |
| All complete → no notify | | | |
| Empty plan → no notify | | | |
| Foreground | | | |
| Background | | | |
| Process killed | | | |
| Device reboot | | | |
| Doze / battery optimization | | | |
| Logout → no further notify | | | |
| Settings OFF → cancel | | | |
| User switch | | | |
| Delayed run same night (e.g. 23:30) uses target date | | | |
| Delayed run next day 00:01 uses previous target date | | | |
| No same-day double notify | | | |
| Tap opens Daily Plan | | | |

## Known limitations

- WorkManager does not guarantee exact 23:00; delayed runs use `targetLocalDate` from registration.
- In-flight Prisma queries cannot be forcibly cancelled; after ownership loss is observed, no new phase or replacement transaction is started. An in-flight transaction rolls back if the abort check throws inside it.
- Completion / eval history can grow over time; optional prune (>90 days) is not mandatory in v1.
- Release APK/AAB verification remains incomplete until upload signing files exist locally.

## Go / no-go

Public release is **not** approved until signed APK/AAB, device install, migration paths A–C, and 23:00 notification checks above are completed and recorded.
