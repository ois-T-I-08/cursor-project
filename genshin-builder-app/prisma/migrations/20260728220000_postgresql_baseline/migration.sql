-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "Character" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "element" TEXT NOT NULL,
    "weaponType" TEXT NOT NULL,
    "rarity" INTEGER NOT NULL,
    "region" TEXT NOT NULL,
    "iconUrl" TEXT NOT NULL,
    "scoreType" TEXT NOT NULL DEFAULT 'atk',
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Character_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Weapon" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "weaponType" TEXT NOT NULL,
    "rarity" INTEGER NOT NULL,
    "iconUrl" TEXT NOT NULL,
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Weapon_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Material" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "rarity" INTEGER,
    "iconUrl" TEXT NOT NULL,
    "expValue" INTEGER,
    "expTarget" TEXT,
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Material_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharacterUpgrade" (
    "characterId" TEXT NOT NULL,
    "promotes" TEXT NOT NULL,
    "talents" TEXT NOT NULL,
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CharacterUpgrade_pkey" PRIMARY KEY ("characterId")
);

-- CreateTable
CREATE TABLE "WeaponUpgrade" (
    "weaponId" TEXT NOT NULL,
    "promotes" TEXT NOT NULL,
    "levelUpItemIds" TEXT NOT NULL DEFAULT '[]',
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WeaponUpgrade_pkey" PRIMARY KEY ("weaponId")
);

-- CreateTable
CREATE TABLE "LevelExpSegment" (
    "id" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "rarity" INTEGER NOT NULL DEFAULT 0,
    "fromLevel" INTEGER NOT NULL,
    "toLevel" INTEGER NOT NULL,
    "expRequired" INTEGER NOT NULL,
    "moraRequired" INTEGER NOT NULL,
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LevelExpSegment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserProgress" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "level" INTEGER NOT NULL DEFAULT 1,
    "ascension" INTEGER NOT NULL DEFAULT 0,
    "constellation" INTEGER NOT NULL DEFAULT 0,
    "talentNormal" INTEGER NOT NULL DEFAULT 1,
    "talentSkill" INTEGER NOT NULL DEFAULT 1,
    "talentBurst" INTEGER NOT NULL DEFAULT 1,
    "weaponId" TEXT NOT NULL DEFAULT '',
    "weaponName" TEXT NOT NULL DEFAULT '',
    "weaponLevel" INTEGER NOT NULL DEFAULT 1,
    "weaponRefinement" INTEGER NOT NULL DEFAULT 1,
    "artifacts" TEXT NOT NULL DEFAULT '',
    "isCompleted" BOOLEAN NOT NULL DEFAULT false,
    "memo" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserProgress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncLog" (
    "id" SERIAL NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SyncLease" (
    "lockKey" TEXT NOT NULL,
    "ownerToken" TEXT NOT NULL,
    "acquiredAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SyncLease_pkey" PRIMARY KEY ("lockKey")
);

-- CreateTable
CREATE TABLE "ExternalApiCache" (
    "cacheKey" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "sampleSize" INTEGER NOT NULL,
    "payload" TEXT NOT NULL,
    "fetchedAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ExternalApiCache_pkey" PRIMARY KEY ("cacheKey")
);

-- CreateTable
CREATE TABLE "TeamSimulationJob" (
    "id" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "attackerId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "result" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TeamSimulationJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamSimulationCache" (
    "cacheKey" TEXT NOT NULL,
    "gcsimVersion" TEXT NOT NULL,
    "attackerId" TEXT NOT NULL,
    "payload" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TeamSimulationCache_pkey" PRIMARY KEY ("cacheKey")
);

-- CreateTable
CREATE TABLE "ImportedTeam" (
    "id" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "sourceTeamId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "archetype" TEXT NOT NULL DEFAULT '',
    "teamHash" TEXT NOT NULL,
    "sourceUrl" TEXT NOT NULL DEFAULT '',
    "sourceUpdatedAt" TIMESTAMP(3),
    "fetchedAt" TIMESTAMP(3) NOT NULL,
    "rawPayload" TEXT NOT NULL,
    "normalizedPayload" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "approvalStatus" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ImportedTeam_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ImportedTeamMember" (
    "id" TEXT NOT NULL,
    "importedTeamId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "sourceRole" TEXT NOT NULL DEFAULT '',
    "normalizedRole" TEXT NOT NULL,
    "slotIndex" INTEGER NOT NULL,

    CONSTRAINT "ImportedTeamMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamTemplate" (
    "id" TEXT NOT NULL,
    "importedTeamId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "archetype" TEXT NOT NULL DEFAULT '',
    "teamHash" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "sourceUrl" TEXT NOT NULL DEFAULT '',
    "manualOverride" TEXT NOT NULL DEFAULT '',
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TeamTemplate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamTemplateMember" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "sourceRole" TEXT NOT NULL DEFAULT '',
    "normalizedRole" TEXT NOT NULL,
    "slotIndex" INTEGER NOT NULL,

    CONSTRAINT "TeamTemplateMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharacterTeamProfile" (
    "characterId" TEXT NOT NULL,
    "payload" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "gameVersion" TEXT NOT NULL,
    "isLeak" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CharacterTeamProfile_pkey" PRIMARY KEY ("characterId")
);

-- CreateTable
CREATE TABLE "TeamReplacementJob" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "cacheHits" INTEGER NOT NULL DEFAULT 0,
    "successCount" INTEGER NOT NULL DEFAULT 0,
    "failureCount" INTEGER NOT NULL DEFAULT 0,
    "usagePayload" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "TeamReplacementJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamReplacementResult" (
    "cacheKey" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "replacedCharacterId" TEXT NOT NULL,
    "teamHash" TEXT NOT NULL,
    "gameDataVersion" TEXT NOT NULL,
    "characterDataVersion" TEXT NOT NULL,
    "promptVersion" TEXT NOT NULL,
    "rulesVersion" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "slotAnalysis" TEXT NOT NULL,
    "rawAiOutput" TEXT NOT NULL DEFAULT '',
    "validatedPayload" TEXT NOT NULL,
    "errorCode" TEXT NOT NULL DEFAULT '',
    "generatedAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TeamReplacementResult_pkey" PRIMARY KEY ("cacheKey")
);

-- CreateTable
CREATE TABLE "TeamReplacementCandidate" (
    "id" TEXT NOT NULL,
    "resultKey" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "compatibilityScore" INTEGER NOT NULL,
    "category" TEXT NOT NULL,
    "confidence" DOUBLE PRECISION NOT NULL,
    "reasons" TEXT NOT NULL,
    "tradeoffs" TEXT NOT NULL,
    "requiredChanges" TEXT NOT NULL,
    "teamEvaluation" TEXT NOT NULL,
    "deterministicPenalty" INTEGER NOT NULL DEFAULT 0,
    "finalScore" INTEGER NOT NULL,
    "sortOrder" INTEGER NOT NULL,

    CONSTRAINT "TeamReplacementCandidate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamImportLog" (
    "id" SERIAL NOT NULL,
    "source" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TeamImportLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideChannel" (
    "id" TEXT NOT NULL,
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
    "lastFetchedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideChannel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVideo" (
    "id" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "channelId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "publishedAt" TIMESTAMP(3),
    "thumbnailUrl" TEXT NOT NULL DEFAULT '',
    "durationSeconds" INTEGER,
    "privacyStatus" TEXT NOT NULL DEFAULT 'unknown',
    "metadataHash" TEXT NOT NULL DEFAULT '',
    "sourceUrl" TEXT NOT NULL,
    "analysisStatus" TEXT NOT NULL DEFAULT 'pending',
    "lastAnalyzedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideVideo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualAnalysisJob" (
    "id" TEXT NOT NULL,
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
    "startedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideVisualAnalysisJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualAnalysisResult" (
    "id" TEXT NOT NULL,
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
    "generatedAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideVisualAnalysisResult_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualEvidence" (
    "id" TEXT NOT NULL,
    "analysisResultId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "startSeconds" DOUBLE PRECISION NOT NULL,
    "endSeconds" DOUBLE PRECISION NOT NULL,
    "evidenceType" TEXT NOT NULL,
    "normalizedPayload" TEXT NOT NULL DEFAULT '{}',
    "exactVisibleText" TEXT NOT NULL DEFAULT '',
    "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "validationStatus" TEXT NOT NULL DEFAULT 'pending',
    "approvalStatus" TEXT NOT NULL DEFAULT 'pending_review',
    "exclusionCode" TEXT NOT NULL DEFAULT '',
    "purposeSummary" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideVisualEvidence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualVisibleText" (
    "id" TEXT NOT NULL,
    "evidenceId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'other',
    "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0,

    CONSTRAINT "GuideVisualVisibleText_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualExtractedClaim" (
    "id" TEXT NOT NULL,
    "evidenceId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "claimKey" TEXT NOT NULL,
    "claimPayload" TEXT NOT NULL,
    "purpose" TEXT NOT NULL DEFAULT 'unknown',
    "confidence" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'extracted',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideVisualExtractedClaim_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideAnalysisSourceManifest" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "videoIdsPayload" TEXT NOT NULL,
    "manifestHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "mergePayload" TEXT NOT NULL DEFAULT '',
    "conflictPayload" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GuideAnalysisSourceManifest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideAnalysisSourceVideo" (
    "id" TEXT NOT NULL,
    "manifestId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "GuideAnalysisSourceVideo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CharacterBuildRecommendation" (
    "id" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending_review',
    "origin" TEXT NOT NULL DEFAULT 'single_video',
    "manifestId" TEXT,
    "contextPayload" TEXT NOT NULL DEFAULT '{}',
    "mainStatsPayload" TEXT NOT NULL DEFAULT '[]',
    "priorityPayload" TEXT NOT NULL DEFAULT '[]',
    "targetsPayload" TEXT NOT NULL DEFAULT '[]',
    "structuredPayload" TEXT NOT NULL DEFAULT '{}',
    "overallConfidence" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "notes" TEXT NOT NULL DEFAULT '',
    "adminNotes" TEXT NOT NULL DEFAULT '',
    "publishedAt" TIMESTAMP(3),
    "lastVerifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CharacterBuildRecommendation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RecommendationVisualContribution" (
    "id" TEXT NOT NULL,
    "recommendationId" TEXT NOT NULL,
    "evidenceId" TEXT NOT NULL,
    "videoId" TEXT NOT NULL,
    "startSeconds" DOUBLE PRECISION NOT NULL,
    "endSeconds" DOUBLE PRECISION NOT NULL,
    "exactVisibleText" TEXT NOT NULL,
    "contributionRole" TEXT NOT NULL DEFAULT 'supporting',
    "decision" TEXT NOT NULL DEFAULT 'adopted',
    "decisionSummary" TEXT NOT NULL DEFAULT '',
    "usedInPublishedResult" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "RecommendationVisualContribution_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideRecommendationRevision" (
    "id" TEXT NOT NULL,
    "recommendationId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "actor" TEXT NOT NULL DEFAULT 'admin',
    "beforePayload" TEXT NOT NULL DEFAULT '',
    "afterPayload" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideRecommendationRevision_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideAdminAuditLog" (
    "id" SERIAL NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideAdminAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideImportLog" (
    "id" SERIAL NOT NULL,
    "source" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideImportLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GuideVisualUsageLog" (
    "id" SERIAL NOT NULL,
    "channelId" TEXT NOT NULL DEFAULT '',
    "videoId" TEXT NOT NULL DEFAULT '',
    "providerId" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL,
    "success" BOOLEAN NOT NULL,
    "tokenUsage" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideVisualUsageLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LevelExpSegment_targetType_rarity_fromLevel_toLevel_key" ON "LevelExpSegment"("targetType", "rarity", "fromLevel", "toLevel");

-- CreateIndex
CREATE INDEX "UserProgress_userId_idx" ON "UserProgress"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "UserProgress_userId_characterId_key" ON "UserProgress"("userId", "characterId");

-- CreateIndex
CREATE INDEX "TeamSimulationJob_requestHash_status_idx" ON "TeamSimulationJob"("requestHash", "status");

-- CreateIndex
CREATE INDEX "TeamSimulationJob_expiresAt_idx" ON "TeamSimulationJob"("expiresAt");

-- CreateIndex
CREATE INDEX "TeamSimulationCache_attackerId_idx" ON "TeamSimulationCache"("attackerId");

-- CreateIndex
CREATE INDEX "TeamSimulationCache_expiresAt_idx" ON "TeamSimulationCache"("expiresAt");

-- CreateIndex
CREATE INDEX "ImportedTeam_teamHash_idx" ON "ImportedTeam"("teamHash");

-- CreateIndex
CREATE INDEX "ImportedTeam_approvalStatus_idx" ON "ImportedTeam"("approvalStatus");

-- CreateIndex
CREATE UNIQUE INDEX "ImportedTeam_source_sourceTeamId_key" ON "ImportedTeam"("source", "sourceTeamId");

-- CreateIndex
CREATE INDEX "ImportedTeamMember_characterId_idx" ON "ImportedTeamMember"("characterId");

-- CreateIndex
CREATE UNIQUE INDEX "ImportedTeamMember_importedTeamId_slotIndex_key" ON "ImportedTeamMember"("importedTeamId", "slotIndex");

-- CreateIndex
CREATE UNIQUE INDEX "TeamTemplate_importedTeamId_key" ON "TeamTemplate"("importedTeamId");

-- CreateIndex
CREATE INDEX "TeamTemplate_status_updatedAt_idx" ON "TeamTemplate"("status", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "TeamTemplate_teamHash_key" ON "TeamTemplate"("teamHash");

-- CreateIndex
CREATE INDEX "TeamTemplateMember_characterId_idx" ON "TeamTemplateMember"("characterId");

-- CreateIndex
CREATE UNIQUE INDEX "TeamTemplateMember_templateId_slotIndex_key" ON "TeamTemplateMember"("templateId", "slotIndex");

-- CreateIndex
CREATE INDEX "CharacterTeamProfile_dataVersion_idx" ON "CharacterTeamProfile"("dataVersion");

-- CreateIndex
CREATE INDEX "TeamReplacementJob_templateId_status_idx" ON "TeamReplacementJob"("templateId", "status");

-- CreateIndex
CREATE INDEX "TeamReplacementJob_createdAt_idx" ON "TeamReplacementJob"("createdAt");

-- CreateIndex
CREATE INDEX "TeamReplacementResult_templateId_replacedCharacterId_genera_idx" ON "TeamReplacementResult"("templateId", "replacedCharacterId", "generatedAt");

-- CreateIndex
CREATE INDEX "TeamReplacementResult_status_idx" ON "TeamReplacementResult"("status");

-- CreateIndex
CREATE INDEX "TeamReplacementCandidate_resultKey_sortOrder_idx" ON "TeamReplacementCandidate"("resultKey", "sortOrder");

-- CreateIndex
CREATE UNIQUE INDEX "TeamReplacementCandidate_resultKey_characterId_key" ON "TeamReplacementCandidate"("resultKey", "characterId");

-- CreateIndex
CREATE INDEX "TeamImportLog_createdAt_idx" ON "TeamImportLog"("createdAt");

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
CREATE INDEX "GuideVideo_privacyStatus_idx" ON "GuideVideo"("privacyStatus");

-- CreateIndex
CREATE INDEX "GuideVisualAnalysisJob_videoId_status_idx" ON "GuideVisualAnalysisJob"("videoId", "status");

-- CreateIndex
CREATE INDEX "GuideVisualAnalysisJob_requestHash_idx" ON "GuideVisualAnalysisJob"("requestHash");

-- CreateIndex
CREATE INDEX "GuideVisualAnalysisJob_createdAt_idx" ON "GuideVisualAnalysisJob"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "GuideVisualAnalysisResult_cacheKey_key" ON "GuideVisualAnalysisResult"("cacheKey");

-- CreateIndex
CREATE INDEX "GuideVisualAnalysisResult_videoId_status_idx" ON "GuideVisualAnalysisResult"("videoId", "status");

-- CreateIndex
CREATE INDEX "GuideVisualAnalysisResult_status_idx" ON "GuideVisualAnalysisResult"("status");

-- CreateIndex
CREATE INDEX "GuideVisualEvidence_videoId_startSeconds_idx" ON "GuideVisualEvidence"("videoId", "startSeconds");

-- CreateIndex
CREATE INDEX "GuideVisualEvidence_analysisResultId_idx" ON "GuideVisualEvidence"("analysisResultId");

-- CreateIndex
CREATE INDEX "GuideVisualEvidence_approvalStatus_validationStatus_idx" ON "GuideVisualEvidence"("approvalStatus", "validationStatus");

-- CreateIndex
CREATE INDEX "GuideVisualVisibleText_evidenceId_idx" ON "GuideVisualVisibleText"("evidenceId");

-- CreateIndex
CREATE INDEX "GuideVisualExtractedClaim_videoId_characterId_idx" ON "GuideVisualExtractedClaim"("videoId", "characterId");

-- CreateIndex
CREATE INDEX "GuideVisualExtractedClaim_evidenceId_idx" ON "GuideVisualExtractedClaim"("evidenceId");

-- CreateIndex
CREATE INDEX "GuideVisualExtractedClaim_characterId_claimKey_idx" ON "GuideVisualExtractedClaim"("characterId", "claimKey");

-- CreateIndex
CREATE UNIQUE INDEX "GuideAnalysisSourceManifest_manifestHash_key" ON "GuideAnalysisSourceManifest"("manifestHash");

-- CreateIndex
CREATE INDEX "GuideAnalysisSourceManifest_characterId_status_idx" ON "GuideAnalysisSourceManifest"("characterId", "status");

-- CreateIndex
CREATE INDEX "GuideAnalysisSourceVideo_videoId_idx" ON "GuideAnalysisSourceVideo"("videoId");

-- CreateIndex
CREATE UNIQUE INDEX "GuideAnalysisSourceVideo_manifestId_videoId_key" ON "GuideAnalysisSourceVideo"("manifestId", "videoId");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendation_characterId_status_idx" ON "CharacterBuildRecommendation"("characterId", "status");

-- CreateIndex
CREATE INDEX "CharacterBuildRecommendation_status_publishedAt_idx" ON "CharacterBuildRecommendation"("status", "publishedAt");

-- CreateIndex
CREATE INDEX "RecommendationVisualContribution_recommendationId_usedInPub_idx" ON "RecommendationVisualContribution"("recommendationId", "usedInPublishedResult");

-- CreateIndex
CREATE INDEX "RecommendationVisualContribution_evidenceId_idx" ON "RecommendationVisualContribution"("evidenceId");

-- CreateIndex
CREATE INDEX "RecommendationVisualContribution_videoId_idx" ON "RecommendationVisualContribution"("videoId");

-- CreateIndex
CREATE INDEX "GuideRecommendationRevision_recommendationId_createdAt_idx" ON "GuideRecommendationRevision"("recommendationId", "createdAt");

-- CreateIndex
CREATE INDEX "GuideAdminAuditLog_createdAt_idx" ON "GuideAdminAuditLog"("createdAt");

-- CreateIndex
CREATE INDEX "GuideImportLog_createdAt_idx" ON "GuideImportLog"("createdAt");

-- CreateIndex
CREATE INDEX "GuideVisualUsageLog_createdAt_idx" ON "GuideVisualUsageLog"("createdAt");

-- CreateIndex
CREATE INDEX "GuideVisualUsageLog_channelId_createdAt_idx" ON "GuideVisualUsageLog"("channelId", "createdAt");

-- CreateIndex
CREATE INDEX "GuideVisualUsageLog_videoId_createdAt_idx" ON "GuideVisualUsageLog"("videoId", "createdAt");

-- AddForeignKey
ALTER TABLE "CharacterUpgrade" ADD CONSTRAINT "CharacterUpgrade_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WeaponUpgrade" ADD CONSTRAINT "WeaponUpgrade_weaponId_fkey" FOREIGN KEY ("weaponId") REFERENCES "Weapon"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserProgress" ADD CONSTRAINT "UserProgress_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ImportedTeamMember" ADD CONSTRAINT "ImportedTeamMember_importedTeamId_fkey" FOREIGN KEY ("importedTeamId") REFERENCES "ImportedTeam"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamTemplate" ADD CONSTRAINT "TeamTemplate_importedTeamId_fkey" FOREIGN KEY ("importedTeamId") REFERENCES "ImportedTeam"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamTemplateMember" ADD CONSTRAINT "TeamTemplateMember_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamReplacementJob" ADD CONSTRAINT "TeamReplacementJob_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamReplacementResult" ADD CONSTRAINT "TeamReplacementResult_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamReplacementCandidate" ADD CONSTRAINT "TeamReplacementCandidate_resultKey_fkey" FOREIGN KEY ("resultKey") REFERENCES "TeamReplacementResult"("cacheKey") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVideo" ADD CONSTRAINT "GuideVideo_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES "GuideChannel"("channelId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualAnalysisJob" ADD CONSTRAINT "GuideVisualAnalysisJob_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualAnalysisResult" ADD CONSTRAINT "GuideVisualAnalysisResult_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualEvidence" ADD CONSTRAINT "GuideVisualEvidence_analysisResultId_fkey" FOREIGN KEY ("analysisResultId") REFERENCES "GuideVisualAnalysisResult"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualEvidence" ADD CONSTRAINT "GuideVisualEvidence_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualVisibleText" ADD CONSTRAINT "GuideVisualVisibleText_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualExtractedClaim" ADD CONSTRAINT "GuideVisualExtractedClaim_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideVisualExtractedClaim" ADD CONSTRAINT "GuideVisualExtractedClaim_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideAnalysisSourceVideo" ADD CONSTRAINT "GuideAnalysisSourceVideo_manifestId_fkey" FOREIGN KEY ("manifestId") REFERENCES "GuideAnalysisSourceManifest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideAnalysisSourceVideo" ADD CONSTRAINT "GuideAnalysisSourceVideo_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CharacterBuildRecommendation" ADD CONSTRAINT "CharacterBuildRecommendation_manifestId_fkey" FOREIGN KEY ("manifestId") REFERENCES "GuideAnalysisSourceManifest"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecommendationVisualContribution" ADD CONSTRAINT "RecommendationVisualContribution_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecommendationVisualContribution" ADD CONSTRAINT "RecommendationVisualContribution_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RecommendationVisualContribution" ADD CONSTRAINT "RecommendationVisualContribution_videoId_fkey" FOREIGN KEY ("videoId") REFERENCES "GuideVideo"("videoId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GuideRecommendationRevision" ADD CONSTRAINT "GuideRecommendationRevision_recommendationId_fkey" FOREIGN KEY ("recommendationId") REFERENCES "CharacterBuildRecommendation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
