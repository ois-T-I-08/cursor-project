BEGIN;

ALTER TABLE "GuideProviderCircuit"
  RENAME COLUMN "halfOpenProbeAt" TO "probeAcquiredAt";

ALTER TABLE "GuideProviderCircuit"
  RENAME COLUMN "version" TO "stateVersion";

ALTER TABLE "GuideProviderCircuit"
  ADD COLUMN "probeOwner" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "probeToken" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "probeExpiresAt" TIMESTAMP(3);

-- A probe created by the previous implementation had no expiry or owner.
-- Re-open it so the next worker must acquire a new, fenced probe.
UPDATE "GuideProviderCircuit"
SET
  "state" = 'open',
  "openUntil" = CURRENT_TIMESTAMP,
  "probeOwner" = '',
  "probeAcquiredAt" = NULL,
  "probeExpiresAt" = NULL,
  "stateVersion" = "stateVersion" + 1,
  "updatedAt" = CURRENT_TIMESTAMP
WHERE "state" = 'half_open';

CREATE INDEX "GuideProviderCircuit_state_probeExpiresAt_idx"
  ON "GuideProviderCircuit"("state", "probeExpiresAt");

COMMIT;
