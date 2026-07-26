# Google Play Data Safety — declaration draft

Date: 2026-07-26  
Owner: ois-T-I-08  
Scope: Current Flutter release intent for Genshin Builder Mobile  
Source of truth for Console entry: this document + live code audit on the same date.

## Summary answers (transfer into Play Console)

| Console question (approx.) | Draft answer |
|----------------------------|--------------|
| Does your app collect or share any of the required user data types? | **Yes** (collects) |
| Is all user data encrypted in transit? | **Yes** (HTTPS for operator API and HoYoLAB) |
| Do you share user data with third parties? | **No** (operator does not sell/share; optional HoYoLAB traffic goes to HoYoverse as the user’s chosen service) |
| Do you sell user data? | **No** |
| Is data used for advertising? | **No** |
| Is data used for analytics / fraud prevention SDKs? | **No** (no Crashlytics / Firebase Analytics / ads SDKs in the app) |

### Data types — Personal info / User IDs

| Field | Value |
|-------|-------|
| Data type | Personal info → **User IDs** (and related account identifiers when HoYoLAB is linked) |
| Collected | **Yes** |
| Shared | **No** (not shared by the developer to other companies for their purposes) |
| Collection | **Optional** (HoYoLAB linking is user-initiated) |
| Purpose | **App functionality** |
| Processing | **Ephemeral where applicable** for network calls; on-device Secure Storage for session material |
| Encrypted in transit | **Yes** |
| Users can request deletion | On-device: unlink HoYoLAB (clears cookies/session). Local progress delete from Settings. No operator cloud copy of progress exists today |

Do **not** label HoYoLAB cookies / auth material as “Password” in Console.  
If Console offers a separate “Other personal info” / credentials-like category beyond User IDs, prefer documenting **User IDs** plus an explicit note that session cookies are stored only on-device for HoYoLAB API access — confirm against the current Play Console taxonomy at submit time.

## Why “collects = Yes”

- Manual progress, bookmarks, and settings stay on-device and are **not** uploaded to the operator server as a cloud backup today.
- When the user enables HoYoLAB linking, **UID / region / nickname and auth cookies** leave the device toward **HoYoLAB / HoYoverse** for app functionality.
- Linking is optional; core manual features work without it.
- Operator Next.js APIs must not receive or persist HoYoLAB cookies.

## Code / package audit (this repo)

| Check | Result |
|-------|--------|
| Crashlytics / Firebase Analytics / AdMob | **Not present** in `pubspec.yaml` / Android Gradle |
| Android `allowBackup` | **Disabled** (`false` + extraction excludes) |
| Permissions | `INTERNET`, notifications-related (`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`) — no contacts/location/microphone |
| WebView password capture | App JS only checks cookie **presence** flags; does not post password fields to Flutter |
| Cookie / token logging | Services document “never log cookie bodies”; exceptions stringify retcodes without bodies |

## External hosting logs — do not guess

Operator hosting (e.g. Vercel) and GitHub Actions may retain **access logs** (IP, User-Agent, request metadata) under the host’s default retention.  
**Not verified in this repository** whether long-term IP analytics is enabled.

Action for owner before Play submit:

1. Review Vercel (or current host) log retention / analytics toggles
2. Review Next.js production logging for request bodies (must never log cookies)
3. If IPs are retained for security/ops, disclose under Data Safety + Privacy Policy as required by Console guidance
4. Do **not** claim “we do not store IPs” without host settings evidence

## Privacy Policy / Terms alignment checklist

- [ ] Privacy Policy states optional HoYoLAB linking and on-device Secure Storage
- [ ] Privacy Policy states no operator cloud backup of progress (current)
- [ ] Privacy Policy does not claim “no data collection”
- [ ] Terms link from Settings remains HTTPS
- [ ] HoYoLAB pre-link disclosure version `2026-07-26` matches in-app copy

## Console checklist (copy/paste)

```text
Collects user data: Yes
Shares user data: No
Data type: Personal info / User IDs
Collection: Optional
Purpose: App functionality
Processing: Ephemeral where applicable
Encrypted in transit: Yes
Data sale: No
Advertising: No
Analytics: No
```
