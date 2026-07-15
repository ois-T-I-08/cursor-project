"use client";

import Image from "next/image";
import { useMemo } from "react";
import type { ProgressPayload } from "@/lib/actions/progress";
import CultivationBookmarkButton from "@/components/bookmark/CultivationBookmarkButton";
import type { BookmarkCharacterSource } from "@/types/bookmark";
import {
  formatSubStatValue,
  type WeaponDetail,
} from "@/lib/api/amber-details";
import { LEVEL_MARKS, LEVEL_MAX } from "@/lib/level-config";
import { getRangeLevelRequirements } from "@/lib/material-requirements";
import type { UpgradeDataCache } from "@/lib/repository/upgrade-data";
import type { MaterialInfo } from "@/lib/repository/materials";
import type { WeaponOption } from "@/lib/repository/weapons";
import Accordion from "@/components/ui/Accordion";
import LevelSlider from "@/components/ui/LevelSlider";
import WeaponPicker from "./WeaponPicker";
import LevelMaterialsPanel from "./LevelMaterialsPanel";

const inputClass =
  "rounded-lg border border-white/10 bg-[#151d2a] px-2 py-1.5 text-sm text-gray-200 focus:border-accent focus:outline-none";

/**
 * 武器セクション（アコーディオン）
 * 概要: 武器画像・名前・レベル・精錬・メインステータス
 * 詳細: 武器変更・レベル(10刻み)/精錬変更・レベル別ステータス・武器効果
 */
export default function WeaponSection({
  characterName,
  bookmarkCharacter,
  progress,
  weapons,
  weaponDetail,
  materialLookup,
  upgradeCache,
  onWeaponChange,
  onChange,
}: {
  characterName: string;
  bookmarkCharacter: BookmarkCharacterSource;
  progress: ProgressPayload;
  weapons: WeaponOption[];
  weaponDetail: WeaponDetail | null;
  materialLookup: MaterialInfo[];
  upgradeCache: UpgradeDataCache;
  onWeaponChange: (weaponId: string) => void;
  onChange: (patch: Partial<ProgressPayload>) => void;
}) {
  const selected = weapons.find((w) => w.id === progress.weaponId) ?? null;
  const weaponRarity = weaponDetail?.rarity ?? selected?.rarity ?? 4;

  const materialMap = useMemo(
    () => new Map(materialLookup.map((m) => [m.id, m])),
    [materialLookup],
  );

  const weaponBookmarkContext = useMemo(() => {
    if (!progress.weaponId) return null;
    return {
      kind: "weapon-level" as const,
      targetId: progress.weaponId,
      targetName: selected?.name ?? characterName,
      character: bookmarkCharacter,
    };
  }, [progress.weaponId, selected?.name, characterName, bookmarkCharacter]);

  // 現在の武器レベルに対応する実ステータス（レベル変更で自動反映）
  const levelStat =
    weaponDetail?.levelStats.find((s) => s.level === progress.weaponLevel) ??
    null;

  // 精錬ランクに対応する武器効果説明（R1=index0）
  const effectDesc =
    weaponDetail?.effectDescriptions[
      Math.min(
        progress.weaponRefinement - 1,
        weaponDetail.effectDescriptions.length - 1,
      )
    ] ?? null;

  const summary = selected ? (
    <div className="flex items-center gap-3 text-sm text-gray-300">
      {(weaponDetail?.iconUrl ?? selected.iconUrl) && (
        <Image
          src={weaponDetail?.iconUrl ?? selected.iconUrl}
          alt={selected.name}
          width={36}
          height={36}
          className="rounded bg-[#151d2a]"
          unoptimized
        />
      )}
      <span className="font-medium">{selected.name}</span>
      <span className="text-gray-500">
        Lv.{progress.weaponLevel} / R{progress.weaponRefinement}
      </span>
      {weaponDetail?.subStatName && levelStat && (
        <span className="hidden text-xs text-gray-500 sm:inline">
          {weaponDetail.subStatName}{" "}
          {formatSubStatValue(weaponDetail.subStatProp, levelStat.subStatValue)}
        </span>
      )}
    </div>
  ) : (
    <p className="text-sm text-gray-500">武器未設定</p>
  );

  return (
    <Accordion title="武器" summary={summary}>
      <div className="space-y-4">
        {/* 武器・レベル・精錬の変更 */}
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-52 flex-1">
            <label
              htmlFor="weapon-select"
              className="mb-1 block text-xs text-gray-400"
            >
              武器
            </label>
            <WeaponPicker
              id="weapon-select"
              weapons={weapons}
              value={progress.weaponId}
              onChange={onWeaponChange}
            />
          </div>
          <div>
            <label
              htmlFor="weapon-refinement"
              className="mb-1 block text-xs text-gray-400"
            >
              精錬ランク
            </label>
            <select
              id="weapon-refinement"
              value={progress.weaponRefinement}
              onChange={(e) =>
                onChange({ weaponRefinement: Number(e.target.value) })
              }
              className={inputClass}
            >
              {[1, 2, 3, 4, 5].map((r) => (
                <option key={r} value={r}>
                  R{r}
                </option>
              ))}
            </select>
          </div>
        </div>

        {progress.weaponId && (
          <div className="space-y-3">
            <LevelSlider
              id="weapon-level"
              label="武器レベル"
              value={progress.weaponLevel}
              onChange={(weaponLevel) => onChange({ weaponLevel })}
              headerExtra={
                weaponBookmarkContext ? (
                  <CultivationBookmarkButton
                    ctx={weaponBookmarkContext}
                    marks={LEVEL_MARKS}
                    max={LEVEL_MAX}
                    currentLevel={progress.weaponLevel}
                    getRequirements={(from, to) =>
                      getRangeLevelRequirements(
                        from,
                        to,
                        weaponDetail?.promotes ?? [],
                        "weapon",
                        weaponRarity,
                        upgradeCache,
                        (id) =>
                          materialMap.get(id)?.name ?? `素材 #${id}`,
                      )
                    }
                    materialLookup={materialLookup}
                  />
                ) : null
              }
            />
            <LevelMaterialsPanel
              currentLevel={progress.weaponLevel}
              promotes={weaponDetail?.promotes ?? []}
              materials={materialLookup}
              kind="weapon"
              weaponRarity={weaponRarity}
              upgradeCache={upgradeCache}
              bookmarkContext={weaponBookmarkContext ?? undefined}
            />
          </div>
        )}

        {/* 武器性能（レベルに応じて自動反映） */}
        {weaponDetail && (
          <div className="space-y-3 rounded-lg bg-[#151d2a] p-4">
            <div className="flex items-center gap-3">
              <Image
                src={weaponDetail.iconUrl}
                alt={weaponDetail.name}
                width={48}
                height={48}
                className="rounded bg-[#1e2a3a]"
                unoptimized
              />
              <div>
                <p className="font-bold">{weaponDetail.name}</p>
                <p className="text-xs text-gray-400">
                  <span className="text-amber-400">
                    {"★".repeat(weaponDetail.rarity)}
                  </span>{" "}
                  ・ {weaponDetail.weaponTypeLabel}
                </p>
              </div>
            </div>

            <dl className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3">
              <div className="rounded bg-[#1e2a3a] p-2">
                <dt className="text-xs text-gray-500">
                  基礎攻撃力（Lv.{progress.weaponLevel}）
                </dt>
                <dd className="font-medium">
                  {levelStat?.baseAttack ?? weaponDetail.baseAttack}
                </dd>
              </div>
              {weaponDetail.subStatName && (
                <div className="rounded bg-[#1e2a3a] p-2">
                  <dt className="text-xs text-gray-500">
                    {weaponDetail.subStatName}（Lv.{progress.weaponLevel}）
                  </dt>
                  <dd className="font-medium">
                    {levelStat
                      ? formatSubStatValue(
                          weaponDetail.subStatProp,
                          levelStat.subStatValue,
                        )
                      : weaponDetail.subStatValue}
                  </dd>
                </div>
              )}
            </dl>

            {effectDesc && (
              <div>
                <h3 className="text-xs font-bold text-accent">
                  {weaponDetail.effectName}（R{progress.weaponRefinement}）
                </h3>
                <p className="mt-1 whitespace-pre-line text-xs leading-relaxed text-gray-300">
                  {effectDesc}
                </p>
              </div>
            )}
          </div>
        )}
      </div>
    </Accordion>
  );
}
