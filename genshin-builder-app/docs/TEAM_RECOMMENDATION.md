# Team recommendation

## Data flow and privacy

HoYoLAB Cookie, UID, device/account identifiers and raw responses remain in Flutter Secure Storage/data adapters. Flutter sends only character ID, element/rarity/ownership, level/ascension/constellation, classified talents, weapon ID and levels, available artifact set IDs/stats, `inputQuality` and `defaultedFields`.

Quality meanings:

- `exact`: every transmitted combat field came from the current normalized source.
- `partial`: optional combat fields are absent, such as artifact set ID.
- `defaulted`: an explicit documented default was used.
- `unsupported`: a safe recommendation may be shown, but gcsim must not infer the missing build.

The current HoYoLAB relic model retains localized set name but no stable set ID. The client deliberately sends no set in that case and marks `artifactSets`; localized-name conversion is prohibited.

## Candidate generation

The attacker remains fixed. The other three members are treated as a set for deduplication. Sources and hard caps are AZA.GG observed teams (10), bounded co-occurrence candidates (20), bounded element/role rules (20), and final gcsim candidates (20). There is no full roster Cartesian search.

Common rules require four distinct members, attacker inclusion, an elemental reaction or mono composition, and apply small explicit constraints for Nilou, Chevreuse, Gorou, Faruzan and Kujou Sara. Unknown characters still receive bounded rule candidates; unsupported gcsim mappings are shown as observed/rule-based rather than assigned fabricated performance.

Ranking combines configurable performance 35%, AZA usage 20%, current build 15%, sustain 10%, energy 10%, and accessibility 10%. A result distinguishes `simulated`, `observed`, `ruleBased`, and `manual`; no gcsim result is required to display a recommendation.

## Job, cache, and fallback

`POST /api/team-recommendations` validates the DTO and returns an unpredictable UUIDv4 Job capability. `GET /api/team-recommendations/jobs/{jobId}` returns queued/running/completed/failed/expired without persisting the submitted build. Identical non-expired requests reuse the request hash, and concurrent enqueue within one process shares a Promise. Expired Job rows are deleted during enqueue; result caches retain last success for one additional cache TTL as stale fallback and are then purged. Only successful simulations update `TeamSimulationCache`.

Fallback order is current gcsim result, last successful stale simulation, AZA.GG observed/rule result, then pure rule result. `GCSIM_ENABLED=false` skips the runner. An error in this feature must not affect `/api/abyss/statistics`, app startup, saved teams or domain calculations.

Initial background work is process-local, capped at eight active Jobs by default, and is not a durable distributed queue. A production topology that can terminate request processes must move `GcsimRunner` behind a worker/queue before enabling the kill switch.

## Migration and pre-production checks

Migration `20260720120000_add_team_simulation_jobs` only creates two tables and indexes; it does not alter/drop existing data. Review with `npx prisma validate`, `npx prisma generate`, and migration SQL. Do not run `db push`, `migrate reset`, or apply to production during feature development.

Before production: apply migration to staging, install and verify the fixed binary, test first Job/cache hit/stale/kill switch, inspect concurrency and CPU, confirm logs contain no Cookie/UID/Config, exercise unsupported/new characters, and verify the theoretical-value warning and credits. Re-evaluate a durable distributed worker when instances or duplicate simulations increase.
