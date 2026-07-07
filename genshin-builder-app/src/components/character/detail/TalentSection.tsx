"use client";

import Image from "next/image";
import type { TalentInfo } from "@/lib/api/amber-details";
import type { ProgressPayload } from "@/lib/actions/progress";
import Accordion from "@/components/ui/Accordion";

type Talents = ProgressPayload["talents"];
type ActiveTalentKey = keyof Talents;

import { clampInt, getTalentLevelMax } from "@/lib/input-limits";

/** アクティブスキルの種類 → 育成データのキーと表示名 */
const ACTIVE_TALENTS: Array<{
  kind: "normal" | "skill" | "burst";
  key: ActiveTalentKey;
  label: string;
}> = [
  { kind: "normal", key: "normalAttack", label: "通常攻撃" },
  { kind: "skill", key: "elementalSkill", label: "元素スキル" },
  { kind: "burst", key: "elementalBurst", label: "元素爆発" },
];

const inputClass =
  "w-20 rounded-lg border border-white/10 bg-[#151d2a] px-2 py-1.5 text-sm text-gray-200 focus:border-accent focus:outline-none";

/**
 * スキル・天賦セクション（アコーディオン）
 * 概要: 通常攻撃・元素スキル・元素爆発のスキル名とレベル
 * 詳細: レベル入力・スキル説明・固有天賦（パッシブ）一覧
 */
export default function TalentSection({
  talents,
  talentInfos,
  constellation = 0,
  onChange,
}: {
  talents: Talents;
  talentInfos: TalentInfo[];
  /** 命ノ星座（将来 Lv.13 対応用） */
  constellation?: number;
  onChange: (talents: Talents) => void;
}) {
  const talentMax = getTalentLevelMax(constellation);

  function clampTalent(value: number): number {
    return clampInt(value, 1, talentMax);
  }
  const infoByKind = new Map(
    talentInfos
      .filter((t) => t.kind !== "passive")
      .map((t) => [t.kind, t] as const),
  );
  const passives = talentInfos.filter((t) => t.kind === "passive");

  const summary = (
    <div className="space-y-0.5 text-sm text-gray-300">
      {ACTIVE_TALENTS.map(({ kind, key, label }) => {
        const info = infoByKind.get(kind);
        return (
          <p key={key} className="truncate">
            <span className="text-xs text-gray-500">{label}:</span>{" "}
            {info?.name ?? label}{" "}
            <span className="text-accent">Lv.{talents[key]}</span>
          </p>
        );
      })}
    </div>
  );

  return (
    <Accordion title="スキル・天賦" summary={summary}>
      <div className="space-y-3">
        {/* アクティブスキル: レベル入力 + 説明 */}
        {ACTIVE_TALENTS.map(({ kind, key, label }) => {
          const info = infoByKind.get(kind);
          return (
            <div key={key} className="rounded-lg bg-[#151d2a] p-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  {info?.iconUrl && (
                    <Image
                      src={info.iconUrl}
                      alt=""
                      width={28}
                      height={28}
                      className="opacity-90"
                      unoptimized
                    />
                  )}
                  <div>
                    <p className="text-xs text-gray-500">{label}</p>
                    <h3 className="text-sm font-bold">{info?.name ?? label}</h3>
                  </div>
                </div>
                <label className="flex items-center gap-2 text-xs text-gray-400">
                  レベル (1-{talentMax})
                  <input
                    type="number"
                    min={1}
                    max={talentMax}
                    value={talents[key]}
                    onChange={(e) =>
                      onChange({
                        ...talents,
                        [key]: clampTalent(Number(e.target.value)),
                      })
                    }
                    className={inputClass}
                  />
                </label>
              </div>
              {info?.description && (
                <details className="mt-2">
                  <summary className="cursor-pointer text-xs text-accent">
                    スキル説明を表示
                  </summary>
                  <p className="mt-2 whitespace-pre-line text-xs leading-relaxed text-gray-300">
                    {info.description}
                  </p>
                </details>
              )}
            </div>
          );
        })}

        {/* 固有天賦・パッシブ天賦 */}
        {passives.length > 0 && (
          <div>
            <h3 className="mb-2 text-sm font-bold text-gray-400">
              固有天賦・パッシブ天賦
            </h3>
            <div className="space-y-2">
              {passives.map((p) => (
                <div key={p.name} className="rounded-lg bg-[#151d2a] p-3">
                  <div className="flex items-center gap-2">
                    {p.iconUrl && (
                      <Image
                        src={p.iconUrl}
                        alt=""
                        width={24}
                        height={24}
                        className="opacity-90"
                        unoptimized
                      />
                    )}
                    <h4 className="text-sm font-bold">{p.name}</h4>
                  </div>
                  <p className="mt-1 whitespace-pre-line text-xs leading-relaxed text-gray-300">
                    {p.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </Accordion>
  );
}
