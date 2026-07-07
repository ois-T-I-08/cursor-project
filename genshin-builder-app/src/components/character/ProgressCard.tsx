import Link from "next/link";
import { calcTotalScore, getScoreType } from "@/lib/artifact-score";
import type { CharacterWithProgress } from "@/types/character";
import CharacterAvatar from "./CharacterAvatar";
import ElementBadge from "./ElementBadge";

/** 更新日時を「7/6 21:30」のような短い形式にする */
function formatDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * ホーム画面「最近編集したキャラクター」用のカード
 * 一覧カードと同様、育成状況の要点を表示する。
 */
export default function ProgressCard({
  item,
}: {
  item: CharacterWithProgress;
}) {
  const { character, progress } = item;
  const { normalAttack, elementalSkill, elementalBurst } = progress.talents;
  const score = calcTotalScore(progress.artifacts, getScoreType(character));

  return (
    <Link
      href={`/characters/${character.id}`}
      className="flex items-center gap-4 rounded-xl border border-white/10 bg-[#1e2a3a] p-4 transition-colors hover:bg-[#253447]"
    >
      <CharacterAvatar character={character} size={48} />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="truncate font-bold">{character.name}</p>
          <ElementBadge element={character.element} />
          {progress.isCompleted && (
            <span className="rounded-full bg-emerald-500/15 px-2 py-0.5 text-xs font-medium text-emerald-400">
              育成完了
            </span>
          )}
        </div>
        <p className="mt-0.5 truncate text-xs text-gray-400">
          Lv.{progress.level} ・ {progress.constellation}凸 ・ 天賦{" "}
          {normalAttack}/{elementalSkill}/{elementalBurst}
        </p>
        {progress.weaponName && (
          <p className="truncate text-xs text-gray-500">
            {progress.weaponName} Lv.{progress.weaponLevel}
          </p>
        )}
        <p className="text-xs text-gray-500">
          スコア <span className="text-accent">{score}</span>
        </p>
      </div>

      <time className="shrink-0 text-xs text-gray-500">
        {formatDate(progress.updatedAt)}
      </time>
    </Link>
  );
}
