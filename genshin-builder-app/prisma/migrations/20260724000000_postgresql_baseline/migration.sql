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
CREATE TABLE "BattleStatsSyncRun" (
    "id" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMP(3),
    "lastSuccessfulAt" TIMESTAMP(3),
    "previousSuccessfulRunId" TEXT,
    "attemptedContentTypes" JSONB NOT NULL,
    "responseStatus" INTEGER,
    "sourceVersion" TEXT,
    "payloadHash" TEXT,
    "recordCount" INTEGER NOT NULL DEFAULT 0,
    "validationState" TEXT NOT NULL,
    "validationErrors" JSONB NOT NULL,
    "errorCode" TEXT,
    "errorDetail" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BattleStatsSyncRun_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BattleStatsSnapshot" (
    "id" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "seasonId" TEXT NOT NULL,
    "revision" INTEGER NOT NULL,
    "schemaVersion" INTEGER NOT NULL,
    "payloadHash" TEXT NOT NULL,
    "sourceVersion" TEXT,
    "sourceUpdatedAt" TIMESTAMP(3) NOT NULL,
    "fetchedAt" TIMESTAMP(3) NOT NULL,
    "validatedAt" TIMESTAMP(3) NOT NULL,
    "publishedAt" TIMESTAMP(3),
    "validationState" TEXT NOT NULL,
    "sampleSize" INTEGER,
    "metadata" JSONB NOT NULL,
    "syncRunId" TEXT NOT NULL,

    CONSTRAINT "BattleStatsSnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BattleTeamUsage" (
    "id" TEXT NOT NULL,
    "snapshotId" TEXT NOT NULL,
    "teamKey" TEXT NOT NULL,
    "usageRate" DOUBLE PRECISION NOT NULL,
    "usageCount" INTEGER,
    "rank" INTEGER,
    "side" TEXT,
    "stageKey" TEXT,
    "scopeKey" TEXT NOT NULL,
    "sampleSize" INTEGER,
    "isResolved" BOOLEAN NOT NULL DEFAULT true,
    "sourceMetadata" JSONB NOT NULL,

    CONSTRAINT "BattleTeamUsage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BattleTeamMember" (
    "id" TEXT NOT NULL,
    "teamUsageId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "slot" INTEGER NOT NULL,
    "displayOrder" INTEGER NOT NULL,

    CONSTRAINT "BattleTeamMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BattleCharacterUsage" (
    "id" TEXT NOT NULL,
    "snapshotId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "usageRate" DOUBLE PRECISION NOT NULL,
    "usageCount" INTEGER,
    "rank" INTEGER,
    "side" TEXT,
    "scopeKey" TEXT NOT NULL,
    "ownershipRate" DOUBLE PRECISION,
    "usageAmongOwnersRate" DOUBLE PRECISION,
    "sampleSize" INTEGER,
    "isResolved" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "BattleCharacterUsage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BattleStatsManifest" (
    "contentType" TEXT NOT NULL,
    "publishedSnapshotId" TEXT NOT NULL,
    "revision" INTEGER NOT NULL,
    "payloadHash" TEXT NOT NULL,
    "schemaVersion" INTEGER NOT NULL,
    "seasonId" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BattleStatsManifest_pkey" PRIMARY KEY ("contentType")
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
CREATE INDEX "BattleStatsSyncRun_source_status_startedAt_idx" ON "BattleStatsSyncRun"("source", "status", "startedAt");

-- CreateIndex
CREATE INDEX "BattleStatsSyncRun_previousSuccessfulRunId_idx" ON "BattleStatsSyncRun"("previousSuccessfulRunId");

-- CreateIndex
CREATE INDEX "BattleStatsSnapshot_contentType_seasonId_publishedAt_idx" ON "BattleStatsSnapshot"("contentType", "seasonId", "publishedAt");

-- CreateIndex
CREATE INDEX "BattleStatsSnapshot_syncRunId_idx" ON "BattleStatsSnapshot"("syncRunId");

-- CreateIndex
CREATE UNIQUE INDEX "BattleStatsSnapshot_source_contentType_seasonId_payloadHash_key" ON "BattleStatsSnapshot"("source", "contentType", "seasonId", "payloadHash");

-- CreateIndex
CREATE UNIQUE INDEX "BattleStatsSnapshot_contentType_revision_key" ON "BattleStatsSnapshot"("contentType", "revision");

-- CreateIndex
CREATE INDEX "BattleTeamUsage_snapshotId_usageRate_idx" ON "BattleTeamUsage"("snapshotId", "usageRate");

-- CreateIndex
CREATE INDEX "BattleTeamUsage_snapshotId_side_stageKey_idx" ON "BattleTeamUsage"("snapshotId", "side", "stageKey");

-- CreateIndex
CREATE UNIQUE INDEX "BattleTeamUsage_snapshotId_teamKey_scopeKey_key" ON "BattleTeamUsage"("snapshotId", "teamKey", "scopeKey");

-- CreateIndex
CREATE INDEX "BattleTeamMember_characterId_teamUsageId_idx" ON "BattleTeamMember"("characterId", "teamUsageId");

-- CreateIndex
CREATE UNIQUE INDEX "BattleTeamMember_teamUsageId_characterId_key" ON "BattleTeamMember"("teamUsageId", "characterId");

-- CreateIndex
CREATE UNIQUE INDEX "BattleTeamMember_teamUsageId_slot_key" ON "BattleTeamMember"("teamUsageId", "slot");

-- CreateIndex
CREATE INDEX "BattleCharacterUsage_snapshotId_usageRate_idx" ON "BattleCharacterUsage"("snapshotId", "usageRate");

-- CreateIndex
CREATE INDEX "BattleCharacterUsage_characterId_snapshotId_idx" ON "BattleCharacterUsage"("characterId", "snapshotId");

-- CreateIndex
CREATE UNIQUE INDEX "BattleCharacterUsage_snapshotId_characterId_scopeKey_key" ON "BattleCharacterUsage"("snapshotId", "characterId", "scopeKey");

-- CreateIndex
CREATE UNIQUE INDEX "BattleStatsManifest_publishedSnapshotId_key" ON "BattleStatsManifest"("publishedSnapshotId");

-- AddForeignKey
ALTER TABLE "CharacterUpgrade" ADD CONSTRAINT "CharacterUpgrade_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WeaponUpgrade" ADD CONSTRAINT "WeaponUpgrade_weaponId_fkey" FOREIGN KEY ("weaponId") REFERENCES "Weapon"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserProgress" ADD CONSTRAINT "UserProgress_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleStatsSyncRun" ADD CONSTRAINT "BattleStatsSyncRun_previousSuccessfulRunId_fkey" FOREIGN KEY ("previousSuccessfulRunId") REFERENCES "BattleStatsSyncRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleStatsSnapshot" ADD CONSTRAINT "BattleStatsSnapshot_syncRunId_fkey" FOREIGN KEY ("syncRunId") REFERENCES "BattleStatsSyncRun"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleTeamUsage" ADD CONSTRAINT "BattleTeamUsage_snapshotId_fkey" FOREIGN KEY ("snapshotId") REFERENCES "BattleStatsSnapshot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleTeamMember" ADD CONSTRAINT "BattleTeamMember_teamUsageId_fkey" FOREIGN KEY ("teamUsageId") REFERENCES "BattleTeamUsage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleCharacterUsage" ADD CONSTRAINT "BattleCharacterUsage_snapshotId_fkey" FOREIGN KEY ("snapshotId") REFERENCES "BattleStatsSnapshot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BattleStatsManifest" ADD CONSTRAINT "BattleStatsManifest_publishedSnapshotId_fkey" FOREIGN KEY ("publishedSnapshotId") REFERENCES "BattleStatsSnapshot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
