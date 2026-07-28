/**
 * One-off local repair: DBs that applied the transcript-era Guide migration
 * before it was rewritten to the visual OCR schema.
 * Does not print secrets. Safe when Guide* rows are empty/unused.
 */
const { PrismaClient } = require("@prisma/client");

async function hasColumn(prisma, table, column) {
  const cols = await prisma.$queryRawUnsafe(`PRAGMA table_info('${table}')`);
  return cols.some((c) => c.name === column);
}

async function hasTable(prisma, table) {
  const rows = await prisma.$queryRawUnsafe(
    `SELECT name FROM sqlite_master WHERE type='table' AND name='${table}'`,
  );
  return rows.length > 0;
}

async function main() {
  const prisma = new PrismaClient();
  try {
    await prisma.$executeRawUnsafe(`PRAGMA foreign_keys=OFF`);

    for (const table of [
      "CharacterBuildRecommendationEvidence",
      "RecommendationSourceContribution",
      "GuideExtractedClaim",
      "GuideAnalysisJob",
      "GuideAnalysisResult",
    ]) {
      await prisma.$executeRawUnsafe(`DROP TABLE IF EXISTS "${table}"`);
    }

    if (!(await hasColumn(prisma, "GuideChannel", "dailyAnalysisLimit"))) {
      await prisma.$executeRawUnsafe(
        `ALTER TABLE "GuideChannel" ADD COLUMN "dailyAnalysisLimit" INTEGER NOT NULL DEFAULT 20`,
      );
    }
    if (!(await hasColumn(prisma, "GuideVideo", "durationSeconds"))) {
      await prisma.$executeRawUnsafe(
        `ALTER TABLE "GuideVideo" ADD COLUMN "durationSeconds" INTEGER`,
      );
    }
    if (!(await hasColumn(prisma, "GuideVideo", "privacyStatus"))) {
      await prisma.$executeRawUnsafe(
        `ALTER TABLE "GuideVideo" ADD COLUMN "privacyStatus" TEXT NOT NULL DEFAULT 'unknown'`,
      );
    }
    if (!(await hasColumn(prisma, "GuideVideo", "lastAnalyzedAt"))) {
      await prisma.$executeRawUnsafe(
        `ALTER TABLE "GuideVideo" ADD COLUMN "lastAnalyzedAt" DATETIME`,
      );
    }

    const createStatements = [
      `CREATE TABLE IF NOT EXISTS "GuideVisualAnalysisJob" (
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
)`,
      `CREATE TABLE IF NOT EXISTS "GuideVisualAnalysisResult" (
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
)`,
      `CREATE TABLE IF NOT EXISTS "GuideVisualEvidence" (
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
)`,
      `CREATE TABLE IF NOT EXISTS "GuideVisualVisibleText" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "evidenceId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'other',
    "confidence" REAL NOT NULL DEFAULT 0,
    CONSTRAINT "GuideVisualVisibleText_evidenceId_fkey" FOREIGN KEY ("evidenceId") REFERENCES "GuideVisualEvidence" ("id") ON DELETE CASCADE ON UPDATE CASCADE
)`,
      `CREATE TABLE IF NOT EXISTS "GuideVisualExtractedClaim" (
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
)`,
      `CREATE TABLE IF NOT EXISTS "RecommendationVisualContribution" (
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
)`,
      `CREATE TABLE IF NOT EXISTS "GuideVisualUsageLog" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "channelId" TEXT NOT NULL DEFAULT '',
    "videoId" TEXT NOT NULL DEFAULT '',
    "providerId" TEXT NOT NULL,
    "modelIdentifier" TEXT NOT NULL,
    "success" BOOLEAN NOT NULL,
    "tokenUsage" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)`,
    ];

    for (const sql of createStatements) {
      await prisma.$executeRawUnsafe(sql);
    }

    const indexStatements = [
      'CREATE UNIQUE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_cacheKey_key" ON "GuideVisualAnalysisResult"("cacheKey")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_videoId_status_idx" ON "GuideVisualAnalysisResult"("videoId", "status")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_status_idx" ON "GuideVisualAnalysisResult"("status")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisJob_videoId_status_idx" ON "GuideVisualAnalysisJob"("videoId", "status")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisJob_requestHash_idx" ON "GuideVisualAnalysisJob"("requestHash")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualEvidence_videoId_startSeconds_idx" ON "GuideVisualEvidence"("videoId", "startSeconds")',
      'CREATE INDEX IF NOT EXISTS "GuideVisualEvidence_analysisResultId_idx" ON "GuideVisualEvidence"("analysisResultId")',
    ];
    for (const sql of indexStatements) {
      await prisma.$executeRawUnsafe(sql);
    }

    await prisma.$executeRawUnsafe(`PRAGMA foreign_keys=ON`);

    const ok =
      (await hasTable(prisma, "GuideVisualAnalysisJob")) &&
      (await hasColumn(prisma, "GuideVideo", "durationSeconds")) &&
      (await hasColumn(prisma, "GuideChannel", "dailyAnalysisLimit"));
    console.log(
      JSON.stringify({
        repaired: ok,
        guideVisualAnalysisJob: await hasTable(prisma, "GuideVisualAnalysisJob"),
        guideVideoDuration: await hasColumn(prisma, "GuideVideo", "durationSeconds"),
        channelDailyLimit: await hasColumn(prisma, "GuideChannel", "dailyAnalysisLimit"),
      }),
    );
  } catch (e) {
    console.error("REPAIR_FAILED", e && e.message ? e.message : String(e));
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

main();
