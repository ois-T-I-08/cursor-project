import type { Metadata } from "next";
import { calcTotalScore, getScoreType } from "@/lib/artifact-score";
import { getAllCharacters } from "@/lib/repository/characters";
import { getProgressMap } from "@/lib/repository/progress";
import { getUserId } from "@/lib/user";
import CharacterList, {
  type CharacterListItem,
} from "@/components/character/CharacterList";
import ConsumerPage from "@/components/consumer/ConsumerPage";

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
    <ConsumerPage
      title="キャラ"
      description="キャラクターごとの育成状況を確認します。登録済みの内容だけを表示し、未登録の進捗を補いません。"
    >
      <div className="legacy-dark-surface rounded-2xl bg-[#0f1419] p-3 text-[#e8e6e3] sm:p-5">
        <CharacterList items={items} />
      </div>
    </ConsumerPage>
  );
}
