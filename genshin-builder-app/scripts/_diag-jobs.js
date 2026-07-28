const { PrismaClient } = require("@prisma/client");

async function main() {
  const prisma = new PrismaClient();
  try {
    const jobs = await prisma.guideVisualAnalysisJob.findMany({
      orderBy: { createdAt: "desc" },
      take: 5,
      select: {
        videoId: true,
        status: true,
        errorCode: true,
        attempts: true,
        createdAt: true,
        completedAt: true,
        modelIdentifier: true,
        rangesPayload: true,
      },
    });
    console.log(JSON.stringify(jobs, null, 2));
  } catch (e) {
    console.error(e.message);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

main();
