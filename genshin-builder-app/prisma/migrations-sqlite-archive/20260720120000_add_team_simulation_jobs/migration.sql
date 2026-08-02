-- AddTable: 正規化済み戦闘入力のJobメタデータのみを保存する。
CREATE TABLE "TeamSimulationJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "requestHash" TEXT NOT NULL,
    "attackerId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "result" TEXT NOT NULL DEFAULT '',
    "errorCode" TEXT NOT NULL DEFAULT '',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "expiresAt" DATETIME NOT NULL
);

CREATE INDEX "TeamSimulationJob_requestHash_status_idx" ON "TeamSimulationJob"("requestHash", "status");
CREATE INDEX "TeamSimulationJob_expiresAt_idx" ON "TeamSimulationJob"("expiresAt");

-- AddTable: gcsimバージョンを含む最終正常結果キャッシュ。
CREATE TABLE "TeamSimulationCache" (
    "cacheKey" TEXT NOT NULL PRIMARY KEY,
    "gcsimVersion" TEXT NOT NULL,
    "attackerId" TEXT NOT NULL,
    "payload" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" DATETIME NOT NULL,
    "updatedAt" DATETIME NOT NULL
);

CREATE INDEX "TeamSimulationCache_attackerId_idx" ON "TeamSimulationCache"("attackerId");
CREATE INDEX "TeamSimulationCache_expiresAt_idx" ON "TeamSimulationCache"("expiresAt");
