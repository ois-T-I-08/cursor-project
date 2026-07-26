# Team recommendation

## Data flow and privacy

HoYoLAB Cookie, UID, device/account identifiers and raw responses remain in Flutter Secure Storage/data adapters. Flutter sends only character ID, element/rarity/ownership, level/ascension/constellation, classified talents, weapon ID and levels, available artifact set IDs/stats, `inputQuality` and `defaultedFields`.

Quality meanings:

- `exact`: every transmitted combat field came from the current normalized source.
- `partial`: optional combat fields are absent, such as artifact set ID.
- `defaulted`: an explicit documented default was used.
- `unsupported`: a safe recommendation may be shown without inventing missing combat fields.

The current HoYoLAB relic model retains localized set name but no stable set ID. The client deliberately sends no set in that case and marks `artifactSets`; localized-name conversion is prohibited.

## Candidate generation

The attacker remains fixed. The other three members are treated as a set for deduplication. Sources and hard caps are AZA.GG observed teams (10), bounded co-occurrence candidates (20), and bounded element/role rules (20), sliced to `TEAM_RECOMMENDATION_MAX_CANDIDATES` (default 20). There is no full roster Cartesian search and no combat simulator.

Common rules require four distinct members, attacker inclusion, an elemental reaction or mono composition, and apply small explicit constraints for Nilou, Chevreuse, Gorou, Faruzan and Kujou Sara. Unknown characters still receive bounded rule candidates.

Ranking combines configurable AZA usage 35%, current build 25%, sustain 15%, energy 10%, and accessibility 15%. A result distinguishes `observed`, `ruleBased`, and `manual`. Response `engine` is always `"aza+rules"`.

## Job and fallback

`POST /api/team-recommendations` validates the DTO and returns an unpredictable UUIDv4 Job capability. `GET /api/team-recommendations/jobs/{jobId}` returns queued/running/completed/failed/expired without persisting the submitted build. Identical non-expired requests reuse the request hash, and concurrent enqueue within one process shares a Promise. Expired Job rows are deleted during enqueue.

When abyss statistics cannot be loaded, the API still returns rule-based candidates and may set `warning: "abyssUnavailable"`. An error in this feature must not affect `/api/abyss/statistics`, app startup, saved teams or domain calculations.

Initial background work is process-local, capped at eight active Jobs by default, and is not a durable distributed queue.

## Database

`TeamSimulationJob` stores job status and result JSON only. The former `TeamSimulationCache` table (gcsim run cache) was removed.
