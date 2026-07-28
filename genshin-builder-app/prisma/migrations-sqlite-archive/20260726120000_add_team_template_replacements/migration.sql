-- 外部原本、承認済みテンプレート、AI出力、公開結果を別テーブルへ保存する。
CREATE TABLE "ImportedTeam" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "source" TEXT NOT NULL,
    "sourceTeamId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "archetype" TEXT NOT NULL DEFAULT '',
    "teamHash" TEXT NOT NULL,
    "sourceUrl" TEXT NOT NULL DEFAULT '',
    "sourceUpdatedAt" DATETIME,
    "fetchedAt" DATETIME NOT NULL,
    "rawPayload" TEXT NOT NULL,
    "normalizedPayload" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "approvalStatus" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);
CREATE UNIQUE INDEX "ImportedTeam_source_sourceTeamId_key" ON "ImportedTeam"("source", "sourceTeamId");
CREATE INDEX "ImportedTeam_teamHash_idx" ON "ImportedTeam"("teamHash");
CREATE INDEX "ImportedTeam_approvalStatus_idx" ON "ImportedTeam"("approvalStatus");

CREATE TABLE "ImportedTeamMember" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "importedTeamId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "sourceRole" TEXT NOT NULL DEFAULT '',
    "normalizedRole" TEXT NOT NULL,
    "slotIndex" INTEGER NOT NULL,
    CONSTRAINT "ImportedTeamMember_importedTeamId_fkey" FOREIGN KEY ("importedTeamId") REFERENCES "ImportedTeam" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ImportedTeamMember_importedTeamId_slotIndex_key" ON "ImportedTeamMember"("importedTeamId", "slotIndex");
CREATE INDEX "ImportedTeamMember_characterId_idx" ON "ImportedTeamMember"("characterId");

CREATE TABLE "TeamTemplate" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "importedTeamId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "archetype" TEXT NOT NULL DEFAULT '',
    "teamHash" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "sourceUrl" TEXT NOT NULL DEFAULT '',
    "manualOverride" TEXT NOT NULL DEFAULT '',
    "publishedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "TeamTemplate_importedTeamId_fkey" FOREIGN KEY ("importedTeamId") REFERENCES "ImportedTeam" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "TeamTemplate_importedTeamId_key" ON "TeamTemplate"("importedTeamId");
CREATE INDEX "TeamTemplate_status_updatedAt_idx" ON "TeamTemplate"("status", "updatedAt");
CREATE UNIQUE INDEX "TeamTemplate_teamHash_key" ON "TeamTemplate"("teamHash");

CREATE TABLE "TeamTemplateMember" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "templateId" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "sourceRole" TEXT NOT NULL DEFAULT '',
    "normalizedRole" TEXT NOT NULL,
    "slotIndex" INTEGER NOT NULL,
    CONSTRAINT "TeamTemplateMember_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "TeamTemplateMember_templateId_slotIndex_key" ON "TeamTemplateMember"("templateId", "slotIndex");
CREATE INDEX "TeamTemplateMember_characterId_idx" ON "TeamTemplateMember"("characterId");

CREATE TABLE "CharacterTeamProfile" (
    "characterId" TEXT NOT NULL PRIMARY KEY,
    "payload" TEXT NOT NULL,
    "dataVersion" TEXT NOT NULL,
    "gameVersion" TEXT NOT NULL,
    "isLeak" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);
CREATE INDEX "CharacterTeamProfile_dataVersion_idx" ON "CharacterTeamProfile"("dataVersion");

CREATE TABLE "TeamReplacementJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "templateId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "cacheHits" INTEGER NOT NULL DEFAULT 0,
    "successCount" INTEGER NOT NULL DEFAULT 0,
    "failureCount" INTEGER NOT NULL DEFAULT 0,
    "usagePayload" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "completedAt" DATETIME,
    CONSTRAINT "TeamReplacementJob_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "TeamReplacementJob_templateId_status_idx" ON "TeamReplacementJob"("templateId", "status");
CREATE INDEX "TeamReplacementJob_createdAt_idx" ON "TeamReplacementJob"("createdAt");

CREATE TABLE "TeamReplacementResult" (
    "cacheKey" TEXT NOT NULL PRIMARY KEY,
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
    "generatedAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "TeamReplacementResult_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "TeamTemplate" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "TeamReplacementResult_templateId_replacedCharacterId_generatedAt_idx" ON "TeamReplacementResult"("templateId", "replacedCharacterId", "generatedAt");
CREATE INDEX "TeamReplacementResult_status_idx" ON "TeamReplacementResult"("status");

CREATE TABLE "TeamReplacementCandidate" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "resultKey" TEXT NOT NULL,
    "characterId" TEXT NOT NULL,
    "compatibilityScore" INTEGER NOT NULL,
    "category" TEXT NOT NULL,
    "confidence" REAL NOT NULL,
    "reasons" TEXT NOT NULL,
    "tradeoffs" TEXT NOT NULL,
    "requiredChanges" TEXT NOT NULL,
    "teamEvaluation" TEXT NOT NULL,
    "deterministicPenalty" INTEGER NOT NULL DEFAULT 0,
    "finalScore" INTEGER NOT NULL,
    "sortOrder" INTEGER NOT NULL,
    CONSTRAINT "TeamReplacementCandidate_resultKey_fkey" FOREIGN KEY ("resultKey") REFERENCES "TeamReplacementResult" ("cacheKey") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "TeamReplacementCandidate_resultKey_characterId_key" ON "TeamReplacementCandidate"("resultKey", "characterId");
CREATE INDEX "TeamReplacementCandidate_resultKey_sortOrder_idx" ON "TeamReplacementCandidate"("resultKey", "sortOrder");

CREATE TABLE "TeamImportLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "source" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "detail" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "TeamImportLog_createdAt_idx" ON "TeamImportLog"("createdAt");
