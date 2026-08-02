-- Build Guide recommendations (YouTube metadata + Gemini visual OCR)
-- Video files / frames / audio are NEVER persisted.

CREATE TABLE "GuideChannel" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "channelId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "customUrl" TEXT NOT NULL DEFAULT '',
    "thumbnailUrl" TEXT NOT NULL DEFAULT '',
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "permissionStatus" TEXT NOT NULL DEFAULT 'unknown',
    "attributionRequired" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT NOT NULL DEFAULT '',
    "dailyAnalysisLimit" INTEGER NOT NULL DEFAULT 20,
    "lastFetchedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE TABLE "GuideVideo" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "videoId" TEXT NOT NULL,
    "channelId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "publishedAt" DATETIME,
    "thumbnailUrl" TEXT NOT NULL DEFAULT '',
    "durationSeconds" INTEGER,
    "privacyStatus" TEXT NOT NULL DEFAULT 'unknown',
    "metadataHash" TEXT NOT NULL DEFAULT '',
    "sourceUrl" TEXT NOT NULL,
    "analysisStatus" TEXT NOT NULL DEFAULT 'pending',
    "lastAnalyzedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVideo_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES "GuideChannel" ("channelId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideVisualAnalysisJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "videoId" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "providerId" TEXT NOT NULL DEFAULT '',
    "modelIdentifier" TEXT NOT NULL DEFAULT '',
    "promptVersion" TEXT NOT NULL DEFAULT '',
    "schemaVersion" TEXT NOT NULL DEFAULT '',
    "gameDataVersion" TEXT NOT NULL DEFAULT '',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "tokenUsage" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "rangesPayload" TEXT NOT NULL DEFAULT '',
    "startedAt" DATETIME,
    "completedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVisualAnalysisJob_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideVisualAnalysisResult" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "cacheKey" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL,
    "promptVersion" TEXT NOT NULL,
    "schemaVersion" TEXT NOT NULL,
    "gameDataVersion" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "rawAiOutput" TEXT NOT NULL DEFAULT '',
    "validatedPayload" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "generatedAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVisualAnalysisResult_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideVisualEvidence" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "analysisResultId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "startSeconds" REAL NOT NULL,
    "endSeconds" REAL NOT NULL,
    "evidenceType" TEXT NOT NULL,
    "normalizedPayload" TEXT NOT NULL DEFAULT '{}',
    "exactVisibleText" TEXT NOT NULL DEFAULT '',
    "confidence" REAL NOT NULL DEFAULT 0,
    "validationStatus" TEXT NOT NULL DEFAULT 'pending',
    "approvalStatus" TEXT NOT NULL DEFAULT 'pending_review',
    "exclusionCode" TEXT NOT NULL DEFAULT '',
    "purposeSummary" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVisualEvidence_analysisResultId_fkey" FOREIGN KEY ("analysisResultId") REFERENCES "GuideVisualAnalysisResult" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "GuideVisualEvidence_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideVisualVisibleText" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "evidenceId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'other',
    "confidence" REAL NOT NULL DEFAULT 0,
    CONSTRAINT "GuideVisualVisibleText_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideVisualExtractedClaim" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "evidenceId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "claimKey" TEXT NOT NULL,
    "claimPayload" TEXT NOT NULL,
    "purpose" TEXT NOT NULL DEFAULT 'unknown',
    "confidence" REAL NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'extracted',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVisualExtractedClaim_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "GuideVisualExtractedClaim_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideAnalysisSourceManifest" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "characterId" TEXT NOT NULL,
    "videoIdsPayload" TEXT NOT NULL,
    "manifestHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "mergePayload" TEXT NOT NULL DEFAULT '',
    "conflictPayload" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE TABLE "GuideAnalysisSourceVideo" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "manifestId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "GuideAnalysisSourceVideo_manifestId_fkey" FOREIGN KEY ("manifestId") REFERENCES "GuideAnalysisSourceManifest" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "GuideAnalysisSourceVideo_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "CharacterBuildRecommendation" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "characterId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending_review',
    "origin" TEXT NOT NULL DEFAULT 'single_video',
    "manifestId" TEXT,
    "contextPayload" TEXT NOT NULL DEFAULT '{}',
    "mainStatsPayload" TEXT NOT NULL DEFAULT '[]',
    "priorityPayload" TEXT NOT NULL DEFAULT '[]',
    "targetsPayload" TEXT NOT NULL DEFAULT '[]',
    "overallConfidence" REAL NOT NULL DEFAULT 0,
    "notes" TEXT NOT NULL DEFAULT '',
    "adminNotes" TEXT NOT NULL DEFAULT '',
    "publishedAt" DATETIME,
    "lastVerifiedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "CharacterBuildRecommendation_manifestId_fkey" FOREIGN KEY ("manifestId") REFERENCES "GuideAnalysisSourceManifest" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE "RecommendationVisualContribution" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "recommendationId" TEXT NOT NULL,
    "evidenceId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "startSeconds" REAL NOT NULL,
    "endSeconds" REAL NOT NULL,
    "exactVisibleText" TEXT NOT NULL,
    "contributionRole" TEXT NOT NULL DEFAULT 'supporting',
    "decision" TEXT NOT NULL DEFAULT 'adopted',
    "decisionSummary" TEXT NOT NULL DEFAULT '',
    "usedInPublishedResult" BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT "RecommendationVisualContribution_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "RecommendationVisualContribution_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "RecommendationVisualContribution_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideRecommendationRevision" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "recommendationId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "actor" TEXT NOT NULL DEFAULT 'admin',
    "beforePayload" TEXT NOT NULL DEFAULT '',
    "afterPayload" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "GuideRecommendationRevision_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "GuideAdminAuditLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "GuideImportLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "source" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "GuideVisualUsageLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "channelId" TEXT NOT NULL DEFAULT '',
    "videoId" TEXT NOT NULL DEFAULT '',
    "providerId" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL,
    "success" BOOLEAN NOT NULL,
    "tokenUsage" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX "GuideChannel_channelId_key" ON "GuideChannel"("channelId");
CREATE INDEX "GuideChannel_enabled_permissionStatus_idx" ON "GuideChannel"("enabled", "permissionStatus");
CREATE UNIQUE INDEX "GuideVideo_videoId_key" ON "GuideVideo"("videoId");
CREATE INDEX "GuideVideo_channelId_publishedAt_idx" ON "GuideVideo"("channelId", "publishedAt");
CREATE INDEX "GuideVideo_analysisStatus_idx" ON "GuideVideo"("analysisStatus");
CREATE INDEX "GuideVideo_privacyStatus_idx" ON "GuideVideo"("privacyStatus");
CREATE INDEX "GuideVisualAnalysisJob_videoId_status_idx" ON "GuideVisualAnalysisJob"("videoId", "status");
CREATE INDEX "GuideVisualAnalysisJob_requestHash_idx" ON "GuideVisualAnalysisJob"("requestHash");
CREATE INDEX "GuideVisualAnalysisJob_createdAt_idx" ON "GuideVisualAnalysisJob"("createdAt");
CREATE UNIQUE INDEX "GuideVisualAnalysisResult_cacheKey_key" ON "GuideVisualAnalysisResult"("cacheKey");
CREATE INDEX "GuideVisualAnalysisResult_videoId_status_idx" ON "GuideVisualAnalysisResult"("videoId", "status");
CREATE INDEX "GuideVisualAnalysisResult_status_idx" ON "GuideVisualAnalysisResult"("status");
CREATE INDEX "GuideVisualEvidence_videoId_startSeconds_idx" ON "GuideVisualEvidence"("videoId", "startSeconds");
CREATE INDEX "GuideVisualEvidence_analysisResultId_idx" ON "GuideVisualEvidence"("analysisResultId");
CREATE INDEX "GuideVisualEvidence_approvalStatus_validationStatus_idx" ON "GuideVisualEvidence"("approvalStatus", "validationStatus");
CREATE INDEX "GuideVisualVisibleText_evidenceId_idx" ON "GuideVisualVisibleText"("evidenceId");
CREATE INDEX "GuideVisualExtractedClaim_videoId_characterId_idx" ON "GuideVisualExtractedClaim"("videoId", "characterId");
CREATE INDEX "GuideVisualExtractedClaim_evidenceId_idx" ON "GuideVisualExtractedClaim"("evidenceId");
CREATE INDEX "GuideVisualExtractedClaim_characterId_claimKey_idx" ON "GuideVisualExtractedClaim"("characterId", "claimKey");
CREATE UNIQUE INDEX "GuideAnalysisSourceManifest_manifestHash_key" ON "GuideAnalysisSourceManifest"("manifestHash");
CREATE INDEX "GuideAnalysisSourceManifest_characterId_status_idx" ON "GuideAnalysisSourceManifest"("characterId", "status");
CREATE UNIQUE INDEX "GuideAnalysisSourceVideo_manifestId_videoId_key" ON "GuideAnalysisSourceVideo"("manifestId", "videoId");
CREATE INDEX "GuideAnalysisSourceVideo_videoId_idx" ON "GuideAnalysisSourceVideo"("videoId");
CREATE INDEX "CharacterBuildRecommendation_characterId_status_idx" ON "CharacterBuildRecommendation"("characterId", "status");
CREATE INDEX "CharacterBuildRecommendation_status_publishedAt_idx" ON "CharacterBuildRecommendation"("status", "publishedAt");
CREATE INDEX "RecommendationVisualContribution_recommendationId_usedInPublishedResult_idx" ON "RecommendationVisualContribution"("recommendationId", "usedInPublishedResult");
CREATE INDEX "RecommendationVisualContribution_evidenceId_idx" ON "RecommendationVisualContribution"("evidenceId");
CREATE INDEX "RecommendationVisualContribution_videoId_idx" ON "RecommendationVisualContribution"("videoId");
CREATE INDEX "GuideRecommendationRevision_recommendationId_createdAt_idx" ON "GuideRecommendationRevision"("recommendationId", "createdAt");
CREATE INDEX "GuideAdminAuditLog_createdAt_idx" ON "GuideAdminAuditLog"("createdAt");
CREATE INDEX "GuideImportLog_createdAt_idx" ON "GuideImportLog"("createdAt");
CREATE INDEX "GuideVisualUsageLog_createdAt_idx" ON "GuideVisualUsageLog"("createdAt");
CREATE INDEX "GuideVisualUsageLog_channelId_createdAt_idx" ON "GuideVisualUsageLog"("channelId", "createdAt");
CREATE INDEX "GuideVisualUsageLog_videoId_createdAt_idx" ON "GuideVisualUsageLog"("videoId", "createdAt");
