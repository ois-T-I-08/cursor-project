-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Character" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "element" TEXT NOT NULL,
    "weaponType" TEXT NOT NULL,
    "rarity" INTEGER NOT NULL,
    "region" TEXT NOT NULL,
    "iconUrl" TEXT NOT NULL,
    "scoreType" TEXT NOT NULL DEFAULT 'atk',
    "syncedAt" DATETIME NOT NULL
);
INSERT INTO "new_Character" ("element", "iconUrl", "id", "name", "rarity", "region", "syncedAt", "weaponType") SELECT "element", "iconUrl", "id", "name", "rarity", "region", "syncedAt", "weaponType" FROM "Character";
DROP TABLE "Character";
ALTER TABLE "new_Character" RENAME TO "Character";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
