"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { ProgressPayload } from "@/lib/actions/progress";
import { deleteProgress, saveProgress } from "@/lib/actions/progress";
import type {
  ArtifactSetInfo,
  AvatarDetail,
  WeaponDetail,
} from "@/lib/api/amber-details";
import type { ScoreType } from "@/lib/artifact-score";
import type { WeaponOption } from "@/lib/repository/weapons";
import type { Character, CharacterProgress } from "@/types/character";
import { createEmptyArtifactState } from "@/types/character";
import CharacterAvatar from "@/components/character/CharacterAvatar";
import ElementBadge from "@/components/character/ElementBadge";
import CultivationBookmarkButton from "@/components/bookmark/CultivationBookmarkButton";
import LevelSlider from "@/components/ui/LevelSlider";
import { WEAPON_TYPE_INFO } from "@/lib/constants";
import { LEVEL_MARKS, LEVEL_MAX } from "@/lib/level-config";
import { getAscensionForLevel } from "@/lib/level-progression";
import { getRangeLevelRequirements } from "@/lib/material-requirements";
import { snapWeaponLevel } from "@/lib/input-limits";
import type { CharacterUpgradeData } from "@/lib/api/upgrade-types";
import type { MaterialInfo } from "@/lib/repository/materials";
import type { UpgradeDataCache } from "@/lib/repository/upgrade-data";
import WeaponSection from "./WeaponSection";
import ArtifactSection from "./ArtifactSection";
import ConstellationSection from "./ConstellationSection";
import TalentSection from "./TalentSection";
import StatusPanel from "./StatusPanel";
import LevelMaterialsPanel from "./LevelMaterialsPanel";

type SaveStatus = "idle" | "pending" | "saved" | "error";

/** 保存ステータスの表示文言 */
const SAVE_STATUS_LABEL: Record<SaveStatus, string> = {
  idle: "",
  pending: "保存中...",
  saved: "保存済み",
  error: "保存に失敗しました",
};

const AUTOSAVE_DELAY_MS = 800;

function toPayload(p: CharacterProgress | null): ProgressPayload {
  return {
    level: p?.level ?? 1,
    ascension: p?.ascension ?? 0,
    constellation: p?.constellation ?? 0,
    talents: {
      normalAttack: p?.talents.normalAttack ?? 1,
      elementalSkill: p?.talents.elementalSkill ?? 1,
      elementalBurst: p?.talents.elementalBurst ?? 1,
    },
    weaponId: p?.weaponId ?? "",
    weaponName: p?.weaponName ?? "",
    weaponLevel: snapWeaponLevel(p?.weaponLevel ?? 1),
    weaponRefinement: p?.weaponRefinement ?? 1,
    artifacts: p?.artifacts ?? createEmptyArtifactState(),
    isCompleted: p?.isCompleted ?? false,
    memo: p?.memo ?? "",
  };
}

/**
 * キャラクター詳細画面のエディタ本体（Client Component）
 *
 * 育成状況の状態をここで一元管理し、変更があるとデバウンス付きで
 * Server Action へ自動保存する（リアルタイム保存）。
 * キャラクターアイコンをクリックすると詳細ステータス（自動計算）を表示する。
 */
export default function DetailEditor({
  character,
  initialProgress,
  weapons,
  avatarDetail,
  artifactSets,
  initialWeaponDetail,
  scoreType,
  materialLookup,
  characterUpgrade,
  upgradeCache,
}: {
  character: Character;
  initialProgress: CharacterProgress | null;
  weapons: WeaponOption[];
  avatarDetail: AvatarDetail | null;
  artifactSets: ArtifactSetInfo[];
  initialWeaponDetail: WeaponDetail | null;
  scoreType: ScoreType;
  materialLookup: MaterialInfo[];
  characterUpgrade: CharacterUpgradeData | null;
  upgradeCache: UpgradeDataCache;
}) {
  const characterPromotes = characterUpgrade?.promotes ?? [];
  const materialMap = useMemo(
    () => new Map(materialLookup.map((m) => [m.id, m])),
    [materialLookup],
  );
  const bookmarkCharacter = useMemo(
    () => ({
      characterId: character.id,
      characterName: character.name,
      characterIconUrl: character.iconUrl ?? null,
      characterEmoji: character.emoji,
    }),
    [character.id, character.name, character.iconUrl, character.emoji],
  );
  const characterBookmarkContext = useMemo(
    () => ({
      kind: "character-level" as const,
      targetId: character.id,
      targetName: character.name,
      character: bookmarkCharacter,
    }),
    [character.id, character.name, bookmarkCharacter],
  );
  const talentUpgradesByKind = new Map(
    (characterUpgrade?.talents ?? []).map((t) => [t.kind, t.upgrades]),
  );
  const [progress, setProgress] = useState<ProgressPayload>(() =>
    toPayload(initialProgress),
  );
  const [weaponDetail, setWeaponDetail] = useState<WeaponDetail | null>(
    initialWeaponDetail,
  );
  const [showStatus, setShowStatus] = useState(false);
  const [status, setStatus] = useState<SaveStatus>("idle");
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const router = useRouter();

  /** 変更を反映し、デバウンス付きで自動保存する */
  const update = useCallback(
    (patch: Partial<ProgressPayload>) => {
      setProgress((prev) => {
        const next = { ...prev, ...patch };

        if (timerRef.current) clearTimeout(timerRef.current);
        setStatus("pending");
        timerRef.current = setTimeout(async () => {
          const result = await saveProgress(character.id, next);
          setStatus(result.ok ? "saved" : "error");
        }, AUTOSAVE_DELAY_MS);

        return next;
      });
    },
    [character.id],
  );

  // アンマウント時にタイマーを破棄する
  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  /** 武器を切り替えたとき: 保存データを更新し、性能詳細を取得し直す */
  const handleWeaponChange = useCallback(
    async (weaponId: string) => {
      const weapon = weapons.find((w) => w.id === weaponId) ?? null;
      update({ weaponId, weaponName: weapon?.name ?? "" });

      if (!weaponId) {
        setWeaponDetail(null);
        return;
      }
      try {
        const res = await fetch(`/api/weapons/${weaponId}`);
        setWeaponDetail(res.ok ? ((await res.json()) as WeaponDetail) : null);
      } catch {
        setWeaponDetail(null);
      }
    },
    [weapons, update],
  );

  async function handleDelete() {
    if (!confirm("このキャラクターの育成データを削除しますか？")) return;
    const result = await deleteProgress(character.id);
    if (result.ok) {
      setProgress(toPayload(null));
      setWeaponDetail(null);
      setStatus("idle");
      router.refresh();
    }
  }

  return (
    <div className="space-y-4">
      {/* 1. キャラクターレベル（最上部） */}
      <section className="rounded-xl border border-white/10 bg-[#1e2a3a] p-4">
        <div className="flex flex-wrap items-center gap-4">
          <button
            type="button"
            onClick={() => setShowStatus((v) => !v)}
            title="クリックで詳細ステータスを表示"
            aria-pressed={showStatus}
            className={`rounded-full transition-transform hover:scale-105 ${
              showStatus ? "ring-2 ring-accent" : ""
            }`}
          >
            <CharacterAvatar character={character} size={72} />
          </button>
          <div className="min-w-0 flex-1">
            <h1 className="text-xl font-bold">{character.name}</h1>
            <div className="mt-1 flex flex-wrap items-center gap-2 text-sm text-gray-400">
              <span className="text-amber-400">
                {"★".repeat(character.rarity)}
              </span>
              <ElementBadge element={character.element} />
              <span>{WEAPON_TYPE_INFO[character.weaponType].label}</span>
            </div>
            <p className="mt-0.5 text-xs text-gray-500">
              アイコンをクリックすると詳細ステータスを表示します
            </p>
          </div>
          <p
            className={`text-xs ${
              status === "error"
                ? "text-red-400"
                : status === "saved"
                  ? "text-emerald-400"
                  : "text-gray-500"
            }`}
            role="status"
          >
            {SAVE_STATUS_LABEL[status]}
          </p>
        </div>

        <div className="mt-4 space-y-4">
          <LevelSlider
            id="character-level"
            label="キャラクターレベル"
            value={progress.level}
            onChange={(level) => {
              update({
                level,
                ascension: getAscensionForLevel(level, characterPromotes),
              });
            }}
            headerExtra={
              <CultivationBookmarkButton
                ctx={characterBookmarkContext}
                marks={LEVEL_MARKS}
                max={LEVEL_MAX}
                currentLevel={progress.level}
                getRequirements={(from, to) =>
                  getRangeLevelRequirements(
                    from,
                    to,
                    characterPromotes,
                    "character",
                    5,
                    upgradeCache,
                    (id) =>
                      materialMap.get(id)?.name ?? `素材 #${id}`,
                  )
                }
                materialLookup={materialLookup}
              />
            }
          />
          <p className="text-xs text-gray-500">
            突破段階: {progress.ascension}/6（レベルに連動）
          </p>
          <LevelMaterialsPanel
            currentLevel={progress.level}
            promotes={characterPromotes}
            materials={materialLookup}
            kind="character"
            upgradeCache={upgradeCache}
            bookmarkContext={characterBookmarkContext}
          />
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={progress.isCompleted}
              onChange={(e) => update({ isCompleted: e.target.checked })}
              className="size-4 accent-[#d4a853]"
            />
            育成完了
          </label>
        </div>
      </section>

      {/* 詳細ステータス（アイコンクリックで表示） */}
      {showStatus &&
        (avatarDetail?.stats ? (
          <StatusPanel
            character={character}
            avatarStats={avatarDetail.stats}
            progress={progress}
            weaponDetail={weaponDetail}
            artifactSets={artifactSets}
          />
        ) : (
          <p className="rounded-xl border border-white/10 bg-[#1e2a3a] p-4 text-sm text-gray-500">
            ステータス計算用データを取得できませんでした。
          </p>
        ))}

      {/* 2. 武器 */}
      <WeaponSection
        characterName={character.name}
        bookmarkCharacter={bookmarkCharacter}
        progress={progress}
        weapons={weapons}
        weaponDetail={weaponDetail}
        materialLookup={materialLookup}
        upgradeCache={upgradeCache}
        onWeaponChange={handleWeaponChange}
        onChange={update}
      />

      {/* 3. 聖遺物 */}
      <ArtifactSection
        artifacts={progress.artifacts}
        artifactSets={artifactSets}
        scoreType={scoreType}
        onChange={(artifacts) => update({ artifacts })}
      />

      {/* 4. 命ノ星座 */}
      <ConstellationSection
        constellation={progress.constellation}
        constellations={avatarDetail?.constellations ?? []}
        onChange={(constellation) => update({ constellation })}
      />

      {/* 5. スキル・天賦 */}
      <TalentSection
        characterId={character.id}
        characterName={character.name}
        bookmarkCharacter={bookmarkCharacter}
        talents={progress.talents}
        talentInfos={avatarDetail?.talents ?? []}
        talentUpgradesByKind={talentUpgradesByKind}
        materialLookup={materialLookup}
        constellation={progress.constellation}
        onChange={(talents) => update({ talents })}
      />

      {/* メモ・削除 */}
      <section className="space-y-3 rounded-xl border border-white/10 bg-[#1e2a3a] p-4">
        <div>
          <label htmlFor="memo" className="mb-1 block text-xs text-gray-400">
            メモ
          </label>
          <textarea
            id="memo"
            rows={3}
            maxLength={1000}
            value={progress.memo}
            onChange={(e) => update({ memo: e.target.value })}
            placeholder="ビルド方針・厳選中の聖遺物など"
            className="w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2 text-sm text-gray-200 focus:border-accent focus:outline-none"
          />
        </div>

        {initialProgress && (
          <button
            type="button"
            onClick={handleDelete}
            className="rounded-lg border border-red-400/50 px-4 py-2 text-sm text-red-400 transition-colors hover:bg-red-500/10"
          >
            育成データを削除
          </button>
        )}
      </section>
    </div>
  );
}
