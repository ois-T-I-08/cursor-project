const { PrismaClient } = require("@prisma/client");

async function main() {
  const prisma = new PrismaClient();
  try {
    const rows = await prisma.$queryRawUnsafe(
      "SELECT name, sql FROM sqlite_master WHERE tbl_name='GuideVisualAnalysisResult'",
    );
    console.log(JSON.stringify(rows, null, 2));

    await prisma.$executeRawUnsafe(
      'CREATE UNIQUE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_cacheKey_key" ON "GuideVisualAnalysisResult"("cacheKey")',
    );
    await prisma.$executeRawUnsafe(
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_videoId_status_idx" ON "GuideVisualAnalysisResult"("videoId", "status")',
    );
    await prisma.$executeRawUnsafe(
      'CREATE INDEX IF NOT EXISTS "GuideVisualAnalysisResult_status_idx" ON "GuideVisualAnalysisResult"("status")',
    );

    const after = await prisma.$queryRawUnsafe(
      "SELECT name, sql FROM sqlite_master WHERE tbl_name='GuideVisualAnalysisResult'",
    );
    console.log("AFTER", JSON.stringify(after, null, 2));
  } catch (e) {
    console.error("ERR", e.message);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

main();
