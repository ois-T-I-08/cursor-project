-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_UserProgress" (
    "id" TEXT NOT NULL PRIMARY KEY,
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
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "UserProgress_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
INSERT INTO "new_UserProgress" ("ascension", "characterId", "createdAt", "id", "isCompleted", "level", "memo", "talentBurst", "talentNormal", "talentSkill", "updatedAt", "userId", "weaponLevel", "weaponName") SELECT "ascension", "characterId", "createdAt", "id", "isCompleted", "level", "memo", "talentBurst", "talentNormal", "talentSkill", "updatedAt", "userId", "weaponLevel", "weaponName" FROM "UserProgress";
DROP TABLE "UserProgress";
ALTER TABLE "new_UserProgress" RENAME TO "UserProgress";
CREATE INDEX "UserProgress_userId_idx" ON "UserProgress"("userId");
CREATE UNIQUE INDEX "UserProgress_userId_characterId_key" ON "UserProgress"("userId", "characterId");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
