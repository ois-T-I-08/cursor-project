/**
 * ユーザー育成状況のリポジトリ（DB読み取り層）
 */

import type { UserProgress } from "@prisma/client";
import { prisma } from "@/lib/db";
import type {
  ArtifactState,
  CharacterProgress,
  CharacterWithProgress,
} from "@/types/character";
import { createEmptyArtifactState } from "@/types/character";
import { toCharacter } from "./characters";

/** DBに保存されたJSON文字列を聖遺物データに復元する */
function parseArtifacts(json: string): ArtifactState {
  const empty = createEmptyArtifactState();
  if (!json) return empty;
  try {
    const parsed = JSON.parse(json) as Partial<ArtifactState>;
    return { ...empty, ...parsed };
  } catch {
    return empty;
  }
}

/** DBの行を画面用の型へ変換する */
function toProgress(row: UserProgress): CharacterProgress {
  return {
    characterId: row.characterId,
    level: row.level,
    ascension: row.ascension,
    constellation: row.constellation,
    talents: {
      normalAttack: row.talentNormal,
      elementalSkill: row.talentSkill,
      elementalBurst: row.talentBurst,
    },
    weaponId: row.weaponId,
    weaponName: row.weaponName,
    weaponLevel: row.weaponLevel,
    weaponRefinement: row.weaponRefinement,
    artifacts: parseArtifacts(row.artifacts),
    isCompleted: row.isCompleted,
    memo: row.memo,
    updatedAt: row.updatedAt.toISOString(),
  };
}

/** 指定キャラクターの育成状況を取得する（未登録なら null） */
export async function getProgress(
  userId: string,
  characterId: string,
): Promise<CharacterProgress | null> {
  try {
    const row = await prisma.userProgress.findUnique({
      where: { userId_characterId: { userId, characterId } },
    });
    return row ? toProgress(row) : null;
  } catch (error) {
    console.error("育成状況のDB取得に失敗しました:", error);
    return null;
  }
}

/** ユーザーの全育成状況を characterId をキーにして取得する（一覧画面用） */
export async function getProgressMap(
  userId: string,
): Promise<Map<string, CharacterProgress>> {
  try {
    const rows = await prisma.userProgress.findMany({ where: { userId } });
    return new Map(rows.map((row) => [row.characterId, toProgress(row)]));
  } catch (error) {
    console.error("育成状況のDB取得に失敗しました:", error);
    return new Map();
  }
}

/** 最近編集した育成状況をキャラクター情報付きで取得する（ホーム画面用） */
export async function getRecentProgress(
  userId: string,
  limit = 4,
): Promise<CharacterWithProgress[]> {
  try {
    const rows = await prisma.userProgress.findMany({
      where: { userId },
      include: { character: true },
      orderBy: { updatedAt: "desc" },
      take: limit,
    });
    return rows.map((row) => ({
      character: toCharacter(row.character),
      progress: toProgress(row),
    }));
  } catch (error) {
    console.error("育成状況のDB取得に失敗しました:", error);
    return [];
  }
}
