const { PrismaClient } = require("@prisma/client");

async function main() {
  const prisma = new PrismaClient();
  try {
    for (const table of [
      "CharacterBuildRecommendation",
      "GuideChannel",
      "RecommendationSourceContribution",
      "CharacterBuildRecommendationEvidence",
    ]) {
      const cols = await prisma.$queryRawUnsafe(`PRAGMA table_info('${table}')`);
      console.log(table, cols.map((c) => c.name).join(","));
    }
  } catch (e) {
    console.error("ERR", e.message);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

main();
