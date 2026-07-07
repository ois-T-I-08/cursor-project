"use client";

import type { AvatarStats, WeaponDetail } from "@/lib/api/amber-details";
import type { ArtifactSetInfo } from "@/lib/api/amber-details";
import type { ProgressPayload } from "@/lib/actions/progress";
import {
  computeStats,
  PERCENT_STATS,
  STAT_LABELS,
  type StatKey,
} from "@/lib/stats";
import { ELEMENT_INFO } from "@/lib/constants";
import type { Character } from "@/types/character";

/** 表示順 */
const STAT_ORDER: StatKey[] = [
  "hp",
  "atk",
  "def",
  "em",
  "critRate",
  "critDmg",
  "er",
  "healing",
  "incomingHealing",
  "shield",
  "elemDmg",
  "physDmg",
];

/**
 * キャラクター詳細ステータスパネル
 * 現在の入力内容（レベル・突破・武器・聖遺物・セット効果）から
 * ステータスを自動計算して表示する。入力が変わると自動で再計算される。
 */
export default function StatusPanel({
  character,
  avatarStats,
  progress,
  weaponDetail,
  artifactSets,
}: {
  character: Character;
  avatarStats: AvatarStats;
  progress: ProgressPayload;
  weaponDetail: WeaponDetail | null;
  artifactSets: ArtifactSetInfo[];
}) {
  // 装備中セットの2セット効果（2つ以上装備しているもの）を集める
  const setCounts = new Map<string, number>();
  for (const piece of Object.values(progress.artifacts)) {
    if (piece.setId) {
      setCounts.set(piece.setId, (setCounts.get(piece.setId) ?? 0) + 1);
    }
  }
  const setById = new Map(artifactSets.map((s) => [s.id, s]));
  const activeSetEffects = [...setCounts.entries()]
    .filter(([, count]) => count >= 2)
    .map(([setId]) => setById.get(setId)?.effects[0])
    .filter((e): e is string => Boolean(e));

  // 武器レベル（10刻み）に対応するステータスを選ぶ
  const weaponLevelStat =
    weaponDetail?.levelStats.find((s) => s.level === progress.weaponLevel) ??
    weaponDetail?.levelStats[0] ??
    null;

  const stats = computeStats({
    avatarStats,
    element: character.element,
    level: progress.level,
    ascension: progress.ascension,
    weaponLevelStat,
    weaponSubStatProp: weaponDetail?.subStatProp ?? null,
    artifacts: progress.artifacts,
    activeSetEffects,
  });

  const elementLabel = ELEMENT_INFO[character.element].label;

  return (
    <div className="rounded-xl border border-accent/30 bg-[#151d2a] p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-bold text-accent">詳細ステータス</h2>
        <p className="text-xs text-gray-500">入力内容から自動計算</p>
      </div>

      <dl className="grid grid-cols-2 gap-1.5 sm:grid-cols-3">
        {STAT_ORDER.map((key) => (
          <div
            key={key}
            className="flex items-center justify-between rounded-lg bg-[#1e2a3a] px-3 py-2"
          >
            <dt className="text-xs text-gray-400">
              {key === "elemDmg"
                ? `${elementLabel}元素ダメージ`
                : STAT_LABELS[key]}
            </dt>
            <dd className="text-sm font-bold">
              {stats[key].toLocaleString()}
              {PERCENT_STATS.has(key) && "%"}
            </dd>
          </div>
        ))}
      </dl>

      <p className="mt-2 text-xs text-gray-600">
        ※ 基礎値（レベル・突破）+ 武器 + 聖遺物 + 2セット効果の合算値。条件付き効果（4セット効果・武器効果など）は含みません。
      </p>
    </div>
  );
}
