"use client";

import { useMemo, useState } from "react";
import type { Character, Element, Rarity, WeaponType } from "@/types/character";
import { ELEMENT_OPTIONS, WEAPON_TYPE_OPTIONS } from "@/lib/constants";
import CharacterCard, { type CardProgress } from "./CharacterCard";

/** 一覧の1件分（キャラクター + 育成状況サマリー） */
export interface CharacterListItem {
  character: Character;
  progress: CardProgress | null;
}

/** フィルターの状態。空文字は「すべて」を表す */
interface Filters {
  search: string;
  element: Element | "";
  weaponType: WeaponType | "";
  rarity: Rarity | "";
}

const INITIAL_FILTERS: Filters = {
  search: "",
  element: "",
  weaponType: "",
  rarity: "",
};

const selectClass =
  "rounded-lg border border-white/10 bg-[#1e2a3a] px-3 py-2 text-sm text-gray-200 focus:border-accent focus:outline-none";

/**
 * キャラクター一覧（Client Component）
 * 名前検索・元素・武器種・レアリティで絞り込みできる。
 */
export default function CharacterList({
  items,
}: {
  items: CharacterListItem[];
}) {
  const [filters, setFilters] = useState<Filters>(INITIAL_FILTERS);

  /** フィルター条件に一致するキャラクターだけを抽出する */
  const filtered = useMemo(() => {
    return items.filter(({ character: c }) => {
      if (filters.search && !c.name.includes(filters.search)) return false;
      if (filters.element && c.element !== filters.element) return false;
      if (filters.weaponType && c.weaponType !== filters.weaponType)
        return false;
      if (filters.rarity && c.rarity !== filters.rarity) return false;
      return true;
    });
  }, [items, filters]);

  /** 1項目だけ更新するヘルパー */
  const update = <K extends keyof Filters>(key: K, value: Filters[K]) =>
    setFilters((prev) => ({ ...prev, [key]: value }));

  return (
    <div className="space-y-4">
      {/* フィルターバー */}
      <div className="flex flex-wrap gap-2">
        <input
          type="search"
          value={filters.search}
          onChange={(e) => update("search", e.target.value)}
          placeholder="キャラクター名で検索..."
          className={`${selectClass} min-w-48 flex-1 sm:flex-none`}
          aria-label="キャラクター名で検索"
        />

        <select
          value={filters.element}
          onChange={(e) => update("element", e.target.value as Filters["element"])}
          className={selectClass}
          aria-label="元素で絞り込み"
        >
          <option value="">全元素</option>
          {ELEMENT_OPTIONS.map(({ value, label }) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>

        <select
          value={filters.weaponType}
          onChange={(e) =>
            update("weaponType", e.target.value as Filters["weaponType"])
          }
          className={selectClass}
          aria-label="武器種で絞り込み"
        >
          <option value="">全武器種</option>
          {WEAPON_TYPE_OPTIONS.map(({ value, label }) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>

        <select
          value={filters.rarity}
          onChange={(e) =>
            update(
              "rarity",
              e.target.value === "" ? "" : (Number(e.target.value) as Rarity),
            )
          }
          className={selectClass}
          aria-label="レアリティで絞り込み"
        >
          <option value="">全レアリティ</option>
          <option value="5">★5</option>
          <option value="4">★4</option>
        </select>
      </div>

      {/* 件数表示 */}
      <p className="text-xs text-gray-500">
        {filtered.length} / {items.length} 体を表示
      </p>

      {/* キャラクターグリッド */}
      {filtered.length > 0 ? (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          {filtered.map(({ character, progress }) => (
            <CharacterCard
              key={character.id}
              character={character}
              progress={progress}
            />
          ))}
        </div>
      ) : (
        <p className="rounded-xl border border-white/10 bg-[#1e2a3a] p-8 text-center text-sm text-gray-500">
          条件に一致するキャラクターが見つかりませんでした
        </p>
      )}
    </div>
  );
}
