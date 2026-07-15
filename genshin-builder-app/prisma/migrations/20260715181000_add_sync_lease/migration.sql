-- CreateTable
CREATE TABLE "SyncLease" (
    "lockKey" TEXT NOT NULL PRIMARY KEY,
    "ownerToken" TEXT NOT NULL,
    "acquiredAt" DATETIME NOT NULL,
    "expiresAt" DATETIME NOT NULL
);
