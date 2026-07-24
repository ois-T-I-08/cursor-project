-- AlterTable
ALTER TABLE "Material" ADD COLUMN "expTarget" TEXT;
ALTER TABLE "Material" ADD COLUMN "expValue" INTEGER;

-- CreateTable
CREATE TABLE "CharacterUpgrade" (
    "characterId" TEXT NOT NULL PRIMARY KEY,
    "promotes" TEXT NOT NULL,
    "talents" TEXT NOT NULL,
    "syncedAt" DATETIME NOT NULL,
    CONSTRAINT "CharacterUpgrade_characterId_fkey" FOREIGN KEY ("characterId") REFERENCES "Character" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "WeaponUpgrade" (
    "weaponId" TEXT NOT NULL PRIMARY KEY,
    "promotes" TEXT NOT NULL,
    "levelUpItemIds" TEXT NOT NULL DEFAULT '[]',
    "syncedAt" DATETIME NOT NULL,
    CONSTRAINT "WeaponUpgrade_weaponId_fkey" FOREIGN KEY ("weaponId") REFERENCES "Weapon" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "LevelExpSegment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "targetType" TEXT NOT NULL,
    "rarity" INTEGER NOT NULL DEFAULT 0,
    "fromLevel" INTEGER NOT NULL,
    "toLevel" INTEGER NOT NULL,
    "expRequired" INTEGER NOT NULL,
    "moraRequired" INTEGER NOT NULL,
    "syncedAt" DATETIME NOT NULL
);

-- CreateIndex
CREATE UNIQUE INDEX "LevelExpSegment_targetType_rarity_fromLevel_toLevel_key" ON "LevelExpSegment"("targetType", "rarity", "fromLevel", "toLevel");
