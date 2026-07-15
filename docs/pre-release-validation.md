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
| APK size / SHA-256 | *blocked: release signing not configured locally* |
| AAB size / SHA-256 | *blocked: release signing not configured locally* |
| APK signature verify | *not run* |
| Device / Android version | |
| Reviewer / date | |

## Automated gates

| Gate | Status | Notes |
|------|--------|--------|
| Mobile tests | | Record count from local/CI run |
| Domain parity (3) | | |
| `flutter analyze` | 0 errors / 0 warnings expected | |
| Web tests | | |
| Web lint | | |
| Web production build | | |
| Secret Guard | | No keystore / key.properties / cookie literals |
| Genshin Mobile CI | | |
| Genshin Web CI | | |

## Feature gates

### P1-8C — 23:00 incomplete Daily Plan notification

| Check | Pass? | Notes |
|-------|-------|--------|
| Completion persistence (per user / localDate / itemKey) | | |
| Checkbox UI complete / incomplete | | |
| WorkManager unique one-off to next local 23:00 | | |
| Catch-up after 23:00 when unevaluated | | |
| `targetLocalDate` preserved on delayed run | | |
| Settings toggle independent of P1-8B | | |
| Permission request only from settings | | |
| Logout / OFF cancels P1-8C work only | | |
| Notification tap → Daily Plan | | |
| No secrets in notification body/payload/logs | | |

### Distributed sync lease renewal

| Check | Pass? | Notes |
|-------|-------|--------|
| `renewSyncLease` owner+unexpired | | |
| Heartbeat ≈ TTL/3 (120s default) | | |
| Ownership loss aborts further work | | |
| Release only matching owner token | | |
| Timer cleared in `finally` | | |

### Release signing & install

| Check | Pass? | Notes |
|-------|-------|--------|
| `android/key.properties` present locally (not committed) | | Required for APK/AAB |
| keystore ignored by git | | |
| Signed release APK | | |
| Signed release AAB | | |
| Fresh install | | Device required |
| Upgrade install | | Device required |
| v7 → v8 (and v8 → v9) migration on device | | Preserve progress/goals/teams/events/inventory |

## Known limitations

- WorkManager does not guarantee exact 23:00; delayed runs use `targetLocalDate` from registration.
- Default sync runner does not cooperatively abort mid-phase on ownership loss; renewal prevents steal while the process lives. Ownership-loss abort is enforced via `AbortSignal` for runners that observe it, and after the runner returns.
- Completion / eval history can grow over time; optional prune (>90 days) is not mandatory in v1.
- Release APK/AAB verification remains incomplete until upload signing files exist locally.

## Go / no-go

Public release is **not** approved until signed APK/AAB, device install, migration, and 23:00 notification checks above are completed and recorded.
