import Link from "next/link";
import type { Character } from "@/types/character";
import { ELEMENT_INFO, WEAPON_TYPE_INFO } from "@/lib/constants";
import CharacterAvatar from "./CharacterAvatar";
import ElementBadge from "./ElementBadge";

/** 一覧カードに表示する育成状況のサマリー */
export interface CardProgress {
  level: number;
  constellation: number;
  weaponName: string;
  weaponLevel: number;
  /** [通常攻撃, 元素スキル, 元素爆発] */
  talents: [number, number, number];
  /** 合計聖遺物スコア */
  score: number;
  isCompleted: boolean;
}

/**
 * キャラクター一覧用のカード
 * 育成状況が登録されていれば、一覧だけで進捗が分かるよう詳細を表示する。
 */
export default function CharacterCard({
  character,
  progress,
}: {
  character: Character;
  progress: CardProgress | null;
}) {
  const elementColor = ELEMENT_INFO[character.element].color;

  return (
    <Link
      href={`/characters/${character.id}`}
      className="group relative overflow-hidden rounded-xl border border-white/10 bg-[#1e2a3a] p-4 transition-all hover:-translate-y-0.5 hover:border-white/25 hover:shadow-lg"
    >
      {/* 上部の元素カラーライン */}
      <span
        className="absolute inset-x-0 top-0 h-0.5"
        style={{ backgroundColor: elementColor }}
      />

      {/* 育成完了マーク */}
      {progress?.isCompleted && (
        <span
          className="absolute right-2 top-2 rounded-full bg-emerald-500/15 px-1.5 py-0.5 text-xs font-medium text-emerald-400"
          title="育成完了"
        >
          ✓
        </span>
      )}

      <CharacterAvatar character={character} size={64} className="mx-auto mb-2" />

      <p className="text-center text-sm font-bold">{character.name}</p>
      <p className="mt-0.5 text-center text-xs text-amber-400">
        {"★".repeat(character.rarity)}
      </p>

      <div className="mt-1.5 flex items-center justify-center gap-1.5">
        <ElementBadge element={character.element} />
        <span className="text-xs text-gray-500">
          {WEAPON_TYPE_INFO[character.weaponType].label}
        </span>
      </div>

      {/* 育成状況サマリー */}
      {progress ? (
        <div className="mt-2 space-y-0.5 border-t border-white/10 pt-2 text-center text-xs">
          <p className="text-gray-300">
            <span className="font-medium text-accent">Lv.{progress.level}</span>
            <span className="mx-1 text-gray-600">/</span>
            {progress.constellation}凸
          </p>
          {progress.weaponName && (
            <p className="truncate text-gray-400" title={progress.weaponName}>
              {progress.weaponName}{" "}
              <span className="text-gray-500">Lv.{progress.weaponLevel}</span>
            </p>
          )}
          <p className="text-gray-400">
            天賦 {progress.talents.join("/")}
          </p>
          <p className="text-gray-400">
            スコア <span className="text-accent">{progress.score}</span>
          </p>
        </div>
      ) : (
        <p className="mt-2 border-t border-white/10 pt-2 text-center text-xs text-gray-600">
          未登録
        </p>
      )}
    </Link>
  );
}
