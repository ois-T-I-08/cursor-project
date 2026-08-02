-- Additive forward migration for the durable YouTube guide automation pipeline.
-- Existing published recommendations and migrations are intentionally untouched.

ALTER TABLE "GuideVideo"
  ADD COLUMN "language" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "discoveredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "discoveryReason" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "availabilityStatus" TEXT NOT NULL DEFAULT 'available',
  ADD COLUMN "unavailableSince" TIMESTAMP(3);

ALTER TABLE "GuideVisualAnalysisResult"
  ADD COLUMN "inputKind" TEXT NOT NULL DEFAULT 'visual',
  ADD COLUMN "transcriptId" TEXT,
  ADD COLUMN "analysisIdempotencyKey" TEXT;

ALTER TABLE "CharacterBuildRecommendation"
  ADD COLUMN "automationKey" TEXT,
  ADD COLUMN "publicationKey" TEXT,
  ADD COLUMN "verificationMode" TEXT NOT NULL DEFAULT 'manual',
  ADD COLUMN "qualityScore" DOUBLE PRECISION NOT NULL DEFAULT 0,
  ADD COLUMN "validationPayload" TEXT NOT NULL DEFAULT '{}';

ALTER TABLE "GuideRecommendationRevision"
  ADD COLUMN "actionKey" TEXT,
  ADD COLUMN "pipelineRunId" TEXT,
  ADD COLUMN "publicationKey" TEXT,
  ADD COLUMN "snapshotHash" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "etag" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "validationPayload" TEXT NOT NULL DEFAULT '{}';

ALTER TABLE "GuideAdminAuditLog"
  ADD COLUMN "actionKey" TEXT,
  ADD COLUMN "pipelineRunId" TEXT,
  ADD COLUMN "actor" TEXT NOT NULL DEFAULT 'admin';

CREATE TABLE "GuidePipelineRun" (
  "id" TEXT NOT NULL,
  "pipelineRunId" TEXT NOT NULL,
  "idempotencyKey" TEXT NOT NULL,
  "trigger" TEXT NOT NULL,
  "mode" TEXT NOT NULL DEFAULT 'dry_run',
  "status" TEXT NOT NULL DEFAULT 'running',
  "dryRun" BOOLEAN NOT NULL DEFAULT true,
  "policyVersion" TEXT NOT NULL,
  "policyHash" TEXT NOT NULL,
  "summaryPayload" TEXT NOT NULL DEFAULT '{}',
  "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuidePipelineRun_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GuidePipelineItem" (
  "id" TEXT NOT NULL,
  "runId" TEXT NOT NULL,
  "videoId" TEXT NOT NULL,
  "discoveryKey" TEXT NOT NULL,
  "analysisIdempotencyKey" TEXT,
  "publicationKey" TEXT,
  "status" TEXT NOT NULL DEFAULT 'DISCOVERED',
  "resumeStatus" TEXT NOT NULL DEFAULT '',
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "maxAttempts" INTEGER NOT NULL DEFAULT 3,
  "nextRetryAt" TIMESTAMP(3),
  "metadataHash" TEXT NOT NULL DEFAULT '',
  "transcriptHash" TEXT NOT NULL DEFAULT '',
  "analyzerVersion" TEXT NOT NULL DEFAULT '',
  "promptVersion" TEXT NOT NULL DEFAULT '',
  "schemaVersion" TEXT NOT NULL DEFAULT '',
  "blockCode" TEXT NOT NULL DEFAULT '',
  "safeErrorCode" TEXT NOT NULL DEFAULT '',
  "qualityPayload" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuidePipelineItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GuidePipelineEvent" (
  "id" TEXT NOT NULL,
  "actionKey" TEXT NOT NULL,
  "runId" TEXT NOT NULL,
  "itemId" TEXT,
  "actor" TEXT NOT NULL DEFAULT 'system:youtube-automation',
  "fromStatus" TEXT NOT NULL DEFAULT '',
  "toStatus" TEXT NOT NULL,
  "safeCode" TEXT NOT NULL DEFAULT '',
  "detailPayload" TEXT NOT NULL DEFAULT '{}',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "GuidePipelineEvent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GuideTranscript" (
  "id" TEXT NOT NULL,
  "videoId" TEXT NOT NULL,
  "identityKey" TEXT NOT NULL,
  "transcriptHash" TEXT NOT NULL,
  "providerId" TEXT NOT NULL,
  "language" TEXT NOT NULL,
  "trackKind" TEXT NOT NULL,
  "sourceTrackId" TEXT NOT NULL DEFAULT '',
  "segmentCount" INTEGER NOT NULL,
  "fetchedAt" TIMESTAMP(3) NOT NULL,
  "retentionExpiresAt" TIMESTAMP(3),
  "deletedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuideTranscript_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GuideTranscriptSegment" (
  "id" TEXT NOT NULL,
  "transcriptId" TEXT NOT NULL,
  "segmentIndex" INTEGER NOT NULL,
  "segmentKey" TEXT NOT NULL,
  "startSeconds" DOUBLE PRECISION NOT NULL,
  "durationSeconds" DOUBLE PRECISION NOT NULL,
  "text" TEXT NOT NULL,
  "textHash" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "GuideTranscriptSegment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GuidePipelineLease" (
  "lockKey" TEXT NOT NULL,
  "leaseOwner" TEXT NOT NULL,
  "leaseAcquiredAt" TIMESTAMP(3) NOT NULL,
  "leaseExpiresAt" TIMESTAMP(3) NOT NULL,
  "leaseVersion" INTEGER NOT NULL DEFAULT 1,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuidePipelineLease_pkey" PRIMARY KEY ("lockKey")
);

CREATE TABLE "GuideProviderCircuit" (
  "providerId" TEXT NOT NULL,
  "state" TEXT NOT NULL DEFAULT 'closed',
  "failureCount" INTEGER NOT NULL DEFAULT 0,
  "lastErrorCode" TEXT NOT NULL DEFAULT '',
  "openedAt" TIMESTAMP(3),
  "openUntil" TIMESTAMP(3),
  "halfOpenProbeAt" TIMESTAMP(3),
  "version" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuideProviderCircuit_pkey" PRIMARY KEY ("providerId")
);

CREATE TABLE "GuideAutomationControl" (
  "id" TEXT NOT NULL,
  "emergencyStopped" BOOLEAN NOT NULL DEFAULT false,
  "reason" TEXT NOT NULL DEFAULT '',
  "version" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "GuideAutomationControl_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "GuideVisualAnalysisResult_analysisIdempotencyKey_key"
  ON "GuideVisualAnalysisResult"("analysisIdempotencyKey");
CREATE UNIQUE INDEX "CharacterBuildRecommendation_automationKey_key"
  ON "CharacterBuildRecommendation"("automationKey");
CREATE UNIQUE INDEX "CharacterBuildRecommendation_publicationKey_key"
  ON "CharacterBuildRecommendation"("publicationKey");
CREATE UNIQUE INDEX "GuideRecommendationRevision_actionKey_key"
  ON "GuideRecommendationRevision"("actionKey");
CREATE UNIQUE INDEX "GuideAdminAuditLog_actionKey_key"
  ON "GuideAdminAuditLog"("actionKey");
CREATE UNIQUE INDEX "GuidePipelineRun_pipelineRunId_key"
  ON "GuidePipelineRun"("pipelineRunId");
CREATE UNIQUE INDEX "GuidePipelineRun_idempotencyKey_key"
  ON "GuidePipelineRun"("idempotencyKey");
CREATE UNIQUE INDEX "GuidePipelineItem_discoveryKey_key"
  ON "GuidePipelineItem"("discoveryKey");
CREATE UNIQUE INDEX "GuidePipelineItem_analysisIdempotencyKey_key"
  ON "GuidePipelineItem"("analysisIdempotencyKey");
CREATE UNIQUE INDEX "GuidePipelineItem_publicationKey_key"
  ON "GuidePipelineItem"("publicationKey");
CREATE UNIQUE INDEX "GuidePipelineItem_runId_videoId_key"
  ON "GuidePipelineItem"("runId", "videoId");
CREATE UNIQUE INDEX "GuidePipelineEvent_actionKey_key"
  ON "GuidePipelineEvent"("actionKey");
CREATE UNIQUE INDEX "GuideTranscript_identityKey_key"
  ON "GuideTranscript"("identityKey");
CREATE UNIQUE INDEX "GuideTranscript_transcriptHash_key"
  ON "GuideTranscript"("transcriptHash");
CREATE UNIQUE INDEX "GuideTranscript_videoId_language_transcriptHash_key"
  ON "GuideTranscript"("videoId", "language", "transcriptHash");
CREATE UNIQUE INDEX "GuideTranscriptSegment_segmentKey_key"
  ON "GuideTranscriptSegment"("segmentKey");
CREATE UNIQUE INDEX "GuideTranscriptSegment_transcriptId_segmentIndex_key"
  ON "GuideTranscriptSegment"("transcriptId", "segmentIndex");

CREATE INDEX "GuideVisualAnalysisResult_transcriptId_idx"
  ON "GuideVisualAnalysisResult"("transcriptId");
CREATE INDEX "GuideRecommendationRevision_pipelineRunId_idx"
  ON "GuideRecommendationRevision"("pipelineRunId");
CREATE INDEX "GuideRecommendationRevision_publicationKey_idx"
  ON "GuideRecommendationRevision"("publicationKey");
CREATE INDEX "GuideAdminAuditLog_pipelineRunId_idx"
  ON "GuideAdminAuditLog"("pipelineRunId");
CREATE INDEX "GuidePipelineRun_status_startedAt_idx"
  ON "GuidePipelineRun"("status", "startedAt");
CREATE INDEX "GuidePipelineRun_createdAt_idx"
  ON "GuidePipelineRun"("createdAt");
CREATE INDEX "GuidePipelineItem_status_nextRetryAt_idx"
  ON "GuidePipelineItem"("status", "nextRetryAt");
CREATE INDEX "GuidePipelineItem_videoId_status_idx"
  ON "GuidePipelineItem"("videoId", "status");
CREATE INDEX "GuidePipelineEvent_runId_createdAt_idx"
  ON "GuidePipelineEvent"("runId", "createdAt");
CREATE INDEX "GuidePipelineEvent_itemId_createdAt_idx"
  ON "GuidePipelineEvent"("itemId", "createdAt");
CREATE INDEX "GuideTranscript_videoId_fetchedAt_idx"
  ON "GuideTranscript"("videoId", "fetchedAt");
CREATE INDEX "GuideTranscript_retentionExpiresAt_idx"
  ON "GuideTranscript"("retentionExpiresAt");
CREATE INDEX "GuideTranscriptSegment_transcriptId_startSeconds_idx"
  ON "GuideTranscriptSegment"("transcriptId", "startSeconds");
CREATE INDEX "GuidePipelineLease_leaseExpiresAt_idx"
  ON "GuidePipelineLease"("leaseExpiresAt");
CREATE INDEX "GuideProviderCircuit_state_openUntil_idx"
  ON "GuideProviderCircuit"("state", "openUntil");

ALTER TABLE "GuideVisualAnalysisResult"
  ADD CONSTRAINT "GuideVisualAnalysisResult_transcriptId_fkey"
  FOREIGN KEY ("transcriptId") REFERENCES "GuideTranscript"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "GuidePipelineItem"
  ADD CONSTRAINT "GuidePipelineItem_runId_fkey"
  FOREIGN KEY ("runId") REFERENCES "GuidePipelineRun"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GuidePipelineItem"
  ADD CONSTRAINT "GuidePipelineItem_videoId_fkey"
  FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GuidePipelineEvent"
  ADD CONSTRAINT "GuidePipelineEvent_runId_fkey"
  FOREIGN KEY ("runId") REFERENCES "GuidePipelineRun"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GuidePipelineEvent"
  ADD CONSTRAINT "GuidePipelineEvent_itemId_fkey"
  FOREIGN KEY ("itemId") REFERENCES "GuidePipelineItem"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GuideTranscript"
  ADD CONSTRAINT "GuideTranscript_videoId_fkey"
  FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GuideTranscriptSegment"
  ADD CONSTRAINT "GuideTranscriptSegment_transcriptId_fkey"
  FOREIGN KEY ("transcriptId") REFERENCES "GuideTranscript"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
