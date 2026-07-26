-- CreateTable
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
    "lastFetchedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "GuideVideo" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "videoId" TEXT NOT NULL,
    "channelId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "publishedAt" DATETIME,
    "thumbnailUrl" TEXT NOT NULL DEFAULT '',
    "metadataHash" TEXT NOT NULL DEFAULT '',
    "sourceUrl" TEXT NOT NULL,
    "analysisStatus" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideVideo_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES "GuideChannel" ("channelId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "GuideAnalysisJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "videoId" TEXT NOT NULL,
    "transcriptHash" TEXT NOT NULL,
    "inputFormat" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL DEFAULT '',
    "promptVersion" TEXT NOT NULL DEFAULT '',
    "schemaVersion" TEXT NOT NULL DEFAULT '',
    "characterDataVersion" TEXT NOT NULL DEFAULT '',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "segmentCount" INTEGER NOT NULL DEFAULT 0,
    "charCount" INTEGER NOT NULL DEFAULT 0,
    "usagePayload" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "completedAt" DATETIME,
    CONSTRAINT "GuideAnalysisJob_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "GuideAnalysisResult" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "cacheKey" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "transcriptHash" TEXT NOT NULL,
    "characterId" TEXT NOT NULL DEFAULT '',
    "modelIdentifier" TEXT NOT NULL,
    "promptVersion" TEXT NOT NULL,
    "schemaVersion" TEXT NOT NULL,
    "characterDataVersion" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "rawAiOutput" TEXT NOT NULL DEFAULT '',
    "validatedPayload" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "generatedAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideAnalysisResult_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
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

-- CreateTable
CREATE TABLE "GuideAnalysisSourceVideo" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "manifestId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "GuideAnalysisSourceVideo_manifestId_fkey" FOREIGN KEY ("manifestId") REFERENCES "GuideAnalysisSourceManifest" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "GuideAnalysisSourceVideo_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "GuideExtractedClaim" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "videoId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "claimKey" TEXT NOT NULL,
    "claimPayload" TEXT NOT NULL,
    "confidence" REAL NOT NULL DEFAULT 0,
    "evidencePayload" TEXT NOT NULL DEFAULT '',
    "status" TEXT NOT NULL DEFAULT 'extracted',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "GuideExtractedClaim_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
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

-- CreateTable
CREATE TABLE "RecommendationSourceContribution" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "recommendationId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "fieldPath" TEXT NOT NULL,
    "valuePayload" TEXT NOT NULL,
    "inclusion" TEXT NOT NULL DEFAULT 'included',
    "reason" TEXT NOT NULL DEFAULT '',
    CONSTRAINT "RecommendationSourceContribution_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "RecommendationSourceContribution_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "CharacterBuildRecommendationEvidence" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "recommendationId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "fieldPath" TEXT NOT NULL DEFAULT '',
    "snippet" TEXT NOT NULL,
    "startMs" INTEGER,
    "endMs" INTEGER,
    "segmentIndex" INTEGER,
    CONSTRAINT "CharacterBuildRecommendationEvidence_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "CharacterBuildRecommendationEvidence_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo" ("videoId") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
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

-- CreateTable
CREATE TABLE "GuideAdminAuditLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "GuideImportLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "source" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateIndex
CREATE UNIQUE INDEX "GuideChannel_channelId_key" ON "GuideChannel"("channelId");

-- CreateIndex
CREATE INDEX "GuideChannel_enabled_permissionStatus_idx" ON "GuideChannel"("enabled", "permissionStatus");

-- CreateIndex
CREATE UNIQUE INDEX "GuideVideo_videoId_key" ON "GuideVideo"("videoId");

-- CreateIndex
CREATE INDEX "GuideVideo_channelId_publishedAt_idx" ON "GuideVideo"("channelId", "publishedAt");

-- CreateIndex
CREATE INDEX "GuideVideo_analysisStatus_idx" ON "GuideVideo"("analysisStatus");

-- CreateIndex
CREATE INDEX "GuideAnalysisJob_videoId_status_idx" ON "GuideAnalysisJob"("videoId", "status");

-- CreateIndex
CREATE INDEX "GuideAnalysisJob_transcriptHash_idx" ON "GuideAnalysisJob"("transcriptHash");

-- CreateIndex
CREATE INDEX "GuideAnalysisJob_createdAt_idx" ON "GuideAnalysisJob"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "GuideAnalysisResult_cacheKey_key" ON "GuideAnalysisResult"("cacheKey");

-- CreateIndex
CREATE INDEX "GuideAnalysisResult_videoId_characterId_status_idx" ON "GuideAnalysisResult"("videoId", "characterId", "status");

-- CreateIndex
CREATE INDEX "GuideAnalysisResult_status_idx" ON "GuideAnalysisResult"("status");

-- CreateIndex
CREATE UNIQUE INDEX "GuideAnalysisSourceManifest_manifestHash_key" ON "GuideAnalysisSourceManifest"("manifestHash");

-- CreateIndex
CREATE INDEX "GuideAnalysisSourceManifest_characterId_status_idx" ON "GuideAnalysisSourceManifest"("characterId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "GuideAnalysisSourceVideo_manifestId_videoId_key" ON "GuideAnalysisSourceVideo"("manifestId", "videoId");

-- CreateIndex
CREATE INDEX "GuideAnalysisSourceVideo_videoId_idx" ON "GuideAnalysisSourceVideo"("videoId");

-- CreateIndex
CREATE INDEX "GuideExtractedClaim_videoId_characterId_idx" ON "GuideExtractedClaim"("videoId", "characterId");

-- CreateIndex
CREATE INDEX "GuideExtractedClaim_characterId_claimKey_idx" ON "GuideExtractedClaim"("characterId", "claimKey");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendation_characterId_status_idx" ON "CharacterBuildRecommendation"("characterId", "status");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendation_status_publishedAt_idx" ON "CharacterBuildRecommendation"("status", "publishedAt");

-- CreateIndex
CREATE INDEX "RecommendationSourceContribution_recommendationId_inclusion_idx" ON "RecommendationSourceContribution"("recommendationId", "inclusion");

-- CreateIndex
CREATE INDEX "RecommendationSourceContribution_videoId_idx" ON "RecommendationSourceContribution"("videoId");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendationEvidence_recommendationId_idx" ON "CharacterBuildRecommendationEvidence"("recommendationId");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendationEvidence_videoId_idx" ON "CharacterBuildRecommendationEvidence"("videoId");

-- CreateIndex
CREATE INDEX "GuideRecommendationRevision_recommendationId_createdAt_idx" ON "GuideRecommendationRevision"("recommendationId", "createdAt");

-- CreateIndex
CREATE INDEX "GuideAdminAuditLog_createdAt_idx" ON "GuideAdminAuditLog"("createdAt");

-- CreateIndex
CREATE INDEX "GuideImportLog_createdAt_idx" ON "GuideImportLog"("createdAt");
