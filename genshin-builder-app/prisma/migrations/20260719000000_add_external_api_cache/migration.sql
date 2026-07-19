-- CreateTable
CREATE TABLE "ExternalApiCache" (
    "cacheKey" TEXT NOT NULL PRIMARY KEY,
    "source" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "sampleSize" INTEGER NOT NULL,
    "payload" TEXT NOT NULL,
    "fetchedAt" DATETIME NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL
);
