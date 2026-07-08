"use client";

import Image from "next/image";
import { useCallback, useMemo } from "react";
import MaterialRowWithBookmark from "@/components/bookmark/MaterialRowWithBookmark";
import {
  buildBookmarkEntries,
  formatMora,
  makeItemSourceKey,
  makeItemSourceLabel,
} from "@/lib/bookmark-utils";
import type { MaterialInfo } from "@/lib/repository/materials";
import {
  getNextTalentRequirements,
  getTalentUpgradeInfos,
  type TalentLevelUpgrade,
} from "@/lib/talent-progression";
import { useMaterialBookmarks } from "@/contexts/MaterialBookmarkContext";
import type { CultivationBookmarkContext } from "@/types/bookmark";
import { MORA_MATERIAL_ID } from "@/types/bookmark";

function MaterialRow({
  name,
  iconUrl,
  count,
}: {
  name: string;
  iconUrl: string | null;
  count: number;
}) {
  return (
    <li className="flex items-center gap-2 text-sm text-gray-200">
      {iconUrl ? (
        <Image
          src={iconUrl}
          alt=""
          width={28}
          height={28}
          className="shrink-0 rounded bg-[#151d2a]"
          unoptimized
        />
      ) : (
        <span className="flex size-7 shrink-0 items-center justify-center rounded bg-[#151d2a] text-[10px] text-gray-500">
          ?
        </span>
      )}
      <span className="min-w-0 flex-1 truncate">{name}</span>
      <span className="shrink-0 tabular-nums text-accent">×{count}</span>
    </li>
  );
}

/**
 * 天賦レベルスライダー下の素材表示
 */
export default function TalentMaterialsPanel({
  currentLevel,
  maxLevel,
  upgrades,
  materials,
  bookmarkContext,
}: {
  currentLevel: number;
  maxLevel: number;
  upgrades: TalentLevelUpgrade[];
  materials: MaterialInfo[];
  bookmarkContext?: CultivationBookmarkContext;
}) {
  const { toggleEntry, isBookmarked } = useMaterialBookmarks();

  const materialMap = useMemo(
    () => new Map(materials.map((m) => [m.id, m])),
    [materials],
  );

  const nextStage = useMemo(
    () => getNextTalentRequirements(currentLevel, maxLevel, upgrades),
    [currentLevel, maxLevel, upgrades],
  );

  const upgradeInfos = useMemo(
    () => getTalentUpgradeInfos(upgrades),
    [upgrades],
  );

  const makeToggle = useCallback(
    (
      materialId: string,
      name: string,
      count: number,
      iconUrl: string | null,
      isMora = false,
    ) => {
      if (!bookmarkContext) return undefined;
      const sourceKey = makeItemSourceKey(bookmarkContext, "next", materialId);
      const entry = buildBookmarkEntries(
        [{ materialId, name, count, iconUrl, isMora }],
        sourceKey,
        makeItemSourceLabel(bookmarkContext, name),
        materials,
        bookmarkContext.character,
      )[0];
      return () => toggleEntry(entry);
    },
    [bookmarkContext, materials, toggleEntry],
  );

  if (upgrades.length === 0) {
    return (
      <p className="text-xs text-gray-500">
        天賦強化データを取得できませんでした
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {nextStage ? (
        <div className="rounded-lg bg-[#1e2a3a] p-3">
          <h4 className="text-xs font-bold text-accent">
            Lv.{nextStage.fromLevel} → Lv.{nextStage.toLevel} に必要な素材
          </h4>
          <ul className="mt-2 space-y-1.5">
            {nextStage.materials.map(({ materialId, count }) => {
              const mat = materialMap.get(materialId);
              const name = mat?.name ?? `素材 #${materialId}`;
              const iconUrl = mat?.iconUrl ?? null;
              const sourceKey = bookmarkContext
                ? makeItemSourceKey(bookmarkContext, "next", materialId)
                : "";
              return bookmarkContext ? (
                <MaterialRowWithBookmark
                  key={materialId}
                  materialId={materialId}
                  name={name}
                  iconUrl={iconUrl}
                  count={count}
                  bookmarked={isBookmarked(sourceKey, materialId)}
                  onToggleBookmark={makeToggle(
                    materialId,
                    name,
                    count,
                    iconUrl,
                  )}
                />
              ) : (
                <MaterialRow
                  key={materialId}
                  name={name}
                  iconUrl={iconUrl}
                  count={count}
                />
              );
            })}
            {nextStage.mora > 0 &&
              (bookmarkContext ? (
                <MaterialRowWithBookmark
                  materialId={MORA_MATERIAL_ID}
                  name="モラ"
                  iconUrl={null}
                  count={nextStage.mora}
                  isMora
                  bookmarked={isBookmarked(
                    makeItemSourceKey(
                      bookmarkContext,
                      "next",
                      MORA_MATERIAL_ID,
                    ),
                    MORA_MATERIAL_ID,
                  )}
                  onToggleBookmark={makeToggle(
                    MORA_MATERIAL_ID,
                    "モラ",
                    nextStage.mora,
                    null,
                    true,
                  )}
                />
              ) : (
                <li className="flex items-center gap-2 text-sm text-gray-200">
                  <span className="flex size-7 shrink-0 items-center justify-center rounded bg-[#151d2a] text-sm">
                    🪙
                  </span>
                  <span className="flex-1">モラ</span>
                  <span className="tabular-nums text-accent">
                    ×{formatMora(nextStage.mora)}
                  </span>
                </li>
              ))}
            {nextStage.materials.length === 0 && nextStage.mora === 0 && (
              <li className="text-xs text-gray-500">追加素材は不要です</li>
            )}
          </ul>
        </div>
      ) : (
        <div className="rounded-lg bg-[#1e2a3a] p-3">
          <p className="text-xs text-emerald-400/80">最大レベルに到達しています</p>
        </div>
      )}

      {upgradeInfos.length > 0 && (
        <details className="rounded-lg bg-[#1e2a3a] p-3">
          <summary className="cursor-pointer text-xs font-bold text-gray-300">
            レベルごとの必要素材
          </summary>
          <div className="mt-3 space-y-3">
            {upgradeInfos.map((info) => (
              <div
                key={info.level}
                className="border-t border-white/5 pt-3 first:border-0 first:pt-0"
              >
                <p className="text-xs font-medium text-gray-300">
                  Lv.{info.level} 強化
                </p>
                <ul className="mt-1.5 space-y-1">
                  {info.materials.map(({ materialId, count }) => {
                    const mat = materialMap.get(materialId);
                    return (
                      <MaterialRow
                        key={materialId}
                        name={mat?.name ?? `素材 #${materialId}`}
                        iconUrl={mat?.iconUrl ?? null}
                        count={count}
                      />
                    );
                  })}
                  <li className="flex items-center gap-2 text-sm text-gray-200">
                    <span className="flex size-7 shrink-0 items-center justify-center rounded bg-[#151d2a] text-sm">
                      🪙
                    </span>
                    <span className="flex-1">モラ</span>
                    <span className="tabular-nums text-accent">
                      ×{formatMora(info.mora)}
                    </span>
                  </li>
                </ul>
              </div>
            ))}
          </div>
        </details>
      )}
    </div>
  );
}
