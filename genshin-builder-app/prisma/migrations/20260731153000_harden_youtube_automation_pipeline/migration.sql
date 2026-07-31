-- Forward-only hardening for fenced workers and atomic automatic publication.
-- The original automation migration remains immutable.

BEGIN;

ALTER TABLE "GuidePipelineItem"
  ADD COLUMN "activeRunId" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "lastRunId" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "characterId" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "transcriptId" TEXT,
  ADD COLUMN "stateVersion" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "leaseOwner" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "leaseVersion" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "canonicalAnalysisPayload" TEXT NOT NULL DEFAULT '{}',
  ADD COLUMN "validationHash" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "snapshotPayload" TEXT NOT NULL DEFAULT '{}',
  ADD COLUMN "policyHash" TEXT NOT NULL DEFAULT '';

UPDATE "GuidePipelineItem"
SET
  "activeRunId" = "runId",
  "lastRunId" = "runId"
WHERE "activeRunId" = '' OR "lastRunId" = '';

CREATE INDEX "GuidePipelineItem_characterId_status_idx"
  ON "GuidePipelineItem"("characterId", "status");
CREATE INDEX "GuidePipelineItem_activeRunId_status_idx"
  ON "GuidePipelineItem"("activeRunId", "status");
CREATE INDEX "GuidePipelineItem_transcriptId_idx"
  ON "GuidePipelineItem"("transcriptId");

ALTER TABLE "GuidePipelineItem"
  ADD CONSTRAINT "GuidePipelineItem_transcriptId_fkey"
  FOREIGN KEY ("transcriptId") REFERENCES "GuideTranscript"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

COMMIT;
