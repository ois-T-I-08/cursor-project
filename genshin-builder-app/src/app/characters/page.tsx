import type { Metadata } from "next";
import { calcTotalScore, getScoreType } from "@/lib/artifact-score";
import { getAllCharacters } from "@/lib/repository/characters";
import { getProgressMap } from "@/lib/repository/progress";
import { getUserId } from "@/lib/user";
import CharacterList, {
  type CharacterListItem,
} from "@/components/character/CharacterList";

export const metadata: Metadata = {
  title: "キャラクター一覧",
};

// DBの内容を毎回反映する（育成状況の変更を即座に表示するため）
export const dynamic = "force-dynamic";

/**
 * キャラクター一覧画面（Server Component）
 * マスターデータとユーザーの育成状況を結合し、
 * 一覧だけで育成状況が分かるカードを表示する。
 */
export default async function CharactersPage() {
  const [characters, userId] = await Promise.all([
    getAllCharacters(),
    getUserId(),
  ]);
  const progressMap = userId ? await getProgressMap(userId) : new Map();

  const items: CharacterListItem[] = characters.map((character) => {
    const progress = progressMap.get(character.id) ?? null;
    return {
      character,
      // カード表示に必要な項目だけを渡す
      progress: progress
        ? {
            level: progress.level,
            constellation: progress.constellation,
            weaponName: progress.weaponName,
            weaponLevel: progress.weaponLevel,
            talents: [
              progress.talents.normalAttack,
              progress.talents.elementalSkill,
              progress.talents.elementalBurst,
            ] as [number, number, number],
            score: calcTotalScore(
              progress.artifacts,
              getScoreType(character),
            ),
            isCompleted: progress.isCompleted,
          }
        : null,
    };
  });

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-bold">キャラクター一覧</h1>
      <CharacterList items={items} />
    </div>
  );
}
