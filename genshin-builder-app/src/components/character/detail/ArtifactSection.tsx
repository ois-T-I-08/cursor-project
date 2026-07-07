"use client";

import type { ArtifactSetInfo } from "@/lib/api/amber-details";
import {
  calcPieceScore,
  calcTotalScore,
  SCORE_TYPE_LABEL,
  type ScoreType,
} from "@/lib/artifact-score";
import {
  ARTIFACT_SLOT_INFO,
  ARTIFACT_SLOT_KEYS,
  MAIN_STAT_OPTIONS,
  SUB_STAT_OPTIONS,
} from "@/lib/constants";
import type {
  ArtifactPiece,
  ArtifactSlotKey,
  ArtifactState,
} from "@/types/character";
import Accordion from "@/components/ui/Accordion";

const inputClass =
  "rounded-lg border border-white/10 bg-[#151d2a] px-2 py-1.5 text-sm text-gray-200 focus:border-accent focus:outline-none";

/** 装備中セットの件数を数える（セット効果表示用） */
function countSets(artifacts: ArtifactState): Map<string, number> {
  const counts = new Map<string, number>();
  for (const piece of Object.values(artifacts)) {
    if (piece.setId) {
      counts.set(piece.setId, (counts.get(piece.setId) ?? 0) + 1);
    }
  }
  return counts;
}

/**
 * 聖遺物セクション（アコーディオン）
 * 概要: 使用セット・セット数・合計スコア・各部位レベル
 * 詳細: 部位ごとのセット/メインステ/サブステ/レベル入力・スコア表示・セット効果
 */
export default function ArtifactSection({
  artifacts,
  artifactSets,
  scoreType,
  onChange,
}: {
  artifacts: ArtifactState;
  artifactSets: ArtifactSetInfo[];
  /** このキャラクターの推奨スコア計算タイプ */
  scoreType: ScoreType;
  onChange: (artifacts: ArtifactState) => void;
}) {
  const totalScore = calcTotalScore(artifacts, scoreType);
  const setCounts = countSets(artifacts);
  const setById = new Map(artifactSets.map((s) => [s.id, s]));

  function updatePiece(slot: ArtifactSlotKey, patch: Partial<ArtifactPiece>) {
    onChange({ ...artifacts, [slot]: { ...artifacts[slot], ...patch } });
  }

  function updateSubstat(
    slot: ArtifactSlotKey,
    index: number,
    stat: string,
    value: number,
  ) {
    // 4枠を常に確保し、指定枠だけ書き換える
    const substats = [0, 1, 2, 3].map(
      (i) => artifacts[slot].substats[i] ?? { stat: "", value: 0 },
    );
    substats[index] = { stat, value };
    updatePiece(slot, { substats: substats.filter((s) => s.stat !== "") });
  }

  // 概要: セット表示（例: "深林の記憶 ×4"）
  const setSummary = [...setCounts.entries()]
    .filter(([, count]) => count >= 2)
    .map(([setId, count]) => {
      const name = setById.get(setId)?.name ?? "不明なセット";
      return `${name} ×${count >= 4 ? 4 : 2}`;
    });

  const summary = (
    <div className="space-y-1 text-sm text-gray-300">
      <div className="flex flex-wrap items-center gap-2">
        <span>
          {setSummary.length > 0 ? setSummary.join(" / ") : "セット未設定"}
        </span>
        <span className="rounded-full bg-[#151d2a] px-2 py-0.5 text-xs text-accent">
          スコア {totalScore}
        </span>
      </div>
      <p className="text-xs text-gray-500">
        {ARTIFACT_SLOT_KEYS.map(
          (slot) =>
            `${ARTIFACT_SLOT_INFO[slot].label}Lv${artifacts[slot].level}`,
        ).join(" ・ ")}
      </p>
    </div>
  );

  return (
    <Accordion title="聖遺物" summary={summary}>
      <div className="space-y-4">
        {/* 各部位の入力 */}
        <div className="grid gap-3 lg:grid-cols-2">
          {ARTIFACT_SLOT_KEYS.map((slot) => {
            const piece = artifacts[slot];
            const pieceScore = calcPieceScore(piece, scoreType);
            return (
              <div key={slot} className="rounded-lg bg-[#151d2a] p-3">
                <div className="mb-2 flex items-center justify-between">
                  <h3 className="text-sm font-bold">
                    {ARTIFACT_SLOT_INFO[slot].label}
                  </h3>
                  <span className="text-xs text-accent">
                    スコア {pieceScore}
                  </span>
                </div>

                <div className="space-y-2">
                  {/* セット・レベル */}
                  <div className="flex gap-2">
                    <select
                      value={piece.setId}
                      onChange={(e) =>
                        updatePiece(slot, { setId: e.target.value })
                      }
                      aria-label={`${ARTIFACT_SLOT_INFO[slot].label}のセット`}
                      className={`${inputClass} min-w-0 flex-1`}
                    >
                      <option value="">セット未設定</option>
                      {artifactSets.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                        </option>
                      ))}
                    </select>
                    <input
                      type="number"
                      min={0}
                      max={20}
                      value={piece.level}
                      onChange={(e) =>
                        updatePiece(slot, { level: Number(e.target.value) })
                      }
                      aria-label={`${ARTIFACT_SLOT_INFO[slot].label}のレベル`}
                      title="強化レベル (0-20)"
                      className={`${inputClass} w-16`}
                    />
                  </div>

                  {/* メインステータス */}
                  <select
                    value={piece.mainStat}
                    onChange={(e) =>
                      updatePiece(slot, { mainStat: e.target.value })
                    }
                    aria-label={`${ARTIFACT_SLOT_INFO[slot].label}のメインステータス`}
                    className={`${inputClass} w-full`}
                  >
                    <option value="">メインステータス未設定</option>
                    {MAIN_STAT_OPTIONS[slot].map((stat) => (
                      <option key={stat} value={stat}>
                        {stat}
                      </option>
                    ))}
                  </select>

                  {/* サブステータス4つ */}
                  {[0, 1, 2, 3].map((i) => {
                    const sub = piece.substats[i] ?? { stat: "", value: 0 };
                    return (
                      <div key={i} className="flex gap-2">
                        <select
                          value={sub.stat}
                          onChange={(e) =>
                            updateSubstat(slot, i, e.target.value, sub.value)
                          }
                          aria-label={`サブステータス${i + 1}`}
                          className={`${inputClass} min-w-0 flex-1`}
                        >
                          <option value="">サブステ{i + 1}</option>
                          {SUB_STAT_OPTIONS.map((stat) => (
                            <option key={stat} value={stat}>
                              {stat}
                            </option>
                          ))}
                        </select>
                        <input
                          type="number"
                          min={0}
                          step={0.1}
                          value={sub.stat ? sub.value : ""}
                          disabled={!sub.stat}
                          onChange={(e) =>
                            updateSubstat(
                              slot,
                              i,
                              sub.stat,
                              Number(e.target.value),
                            )
                          }
                          aria-label={`サブステータス${i + 1}の数値`}
                          placeholder="数値"
                          className={`${inputClass} w-20 disabled:opacity-40`}
                        />
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>

        {/* セット効果 */}
        {[...setCounts.entries()]
          .filter(([, count]) => count >= 2)
          .map(([setId, count]) => {
            const set = setById.get(setId);
            if (!set) return null;
            return (
              <div key={setId} className="rounded-lg bg-[#151d2a] p-3">
                <h3 className="text-sm font-bold text-accent">{set.name}</h3>
                {set.effects[0] && (
                  <p className="mt-1 text-xs text-gray-300">
                    <span className="font-medium text-gray-400">2セット:</span>{" "}
                    {set.effects[0]}
                  </p>
                )}
                {count >= 4 && set.effects[1] && (
                  <p className="mt-1 text-xs text-gray-300">
                    <span className="font-medium text-gray-400">4セット:</span>{" "}
                    {set.effects[1]}
                  </p>
                )}
              </div>
            );
          })}

        {/* 合計スコア */}
        <div className="flex items-center justify-between rounded-lg border border-accent/30 bg-[#151d2a] p-3">
          <span className="text-sm font-bold">合計聖遺物スコア</span>
          <span className="text-lg font-bold text-accent">{totalScore}</span>
        </div>
        <p className="text-xs text-gray-500">
          スコア計算: {SCORE_TYPE_LABEL[scoreType]}
          （会心率×2 + 会心ダメージ +{" "}
          {
            {
              atk: "攻撃力%",
              hp: "HP%",
              def: "防御力%",
              em: "元素熟知÷4",
            }[scoreType]
          }
          ）。このキャラクターの推奨タイプで自動計算しています。
        </p>
      </div>
    </Accordion>
  );
}
