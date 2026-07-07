"use server";

/**
 * 育成状況の保存・削除を行う Server Action
 *
 * 詳細画面の各セクションから自動保存（デバウンス付き）で呼ばれる。
 * 初回保存時に匿名ユーザーIDを発行してCookieへ保存する
 * （Cookieの書き込みは Server Action / Route Handler でのみ可能なため、ここで行う）。
 */

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { prisma } from "@/lib/db";
import {
  generateUserId,
  USER_ID_COOKIE,
  USER_ID_COOKIE_MAX_AGE,
} from "@/lib/user";
import { ARTIFACT_SLOT_KEYS } from "@/lib/constants";
import type { ArtifactState, CharacterProgress } from "@/types/character";
import { createEmptyArtifactPiece } from "@/types/character";

export interface ActionResult {
  ok: boolean;
  message: string;
}

/** 保存時にクライアントから受け取るデータ（updatedAt などは除く） */
export type ProgressPayload = Omit<CharacterProgress, "characterId" | "updatedAt">;

/** ユーザーIDを取得し、なければ発行してCookieへ保存する */
async function ensureUserId(): Promise<string> {
  const cookieStore = await cookies();
  const existing = cookieStore.get(USER_ID_COOKIE)?.value;
  if (existing) return existing;

  const userId = generateUserId();
  cookieStore.set(USER_ID_COOKIE, userId, {
    httpOnly: true,
    sameSite: "lax",
    maxAge: USER_ID_COOKIE_MAX_AGE,
    path: "/",
  });
  return userId;
}

import {
  clampInt,
  CHARACTER_LEVEL_MAX,
  snapWeaponLevel,
} from "@/lib/input-limits";

/** 聖遺物データを検証・正規化する（不正な形は空の状態にする） */
function sanitizeArtifacts(input: unknown): ArtifactState {
  const src = (input ?? {}) as Record<string, unknown>;
  const result = {} as ArtifactState;

  for (const slot of ARTIFACT_SLOT_KEYS) {
    const piece = (src[slot] ?? {}) as Record<string, unknown>;
    const substatsSrc = Array.isArray(piece.substats) ? piece.substats : [];

    result[slot] = {
      ...createEmptyArtifactPiece(),
      setId: String(piece.setId ?? "").slice(0, 20),
      mainStat: String(piece.mainStat ?? "").slice(0, 30),
      level: clampInt(piece.level, 0, 20),
      substats: substatsSrc.slice(0, 4).map((s) => {
        const sub = (s ?? {}) as Record<string, unknown>;
        const value = Number(sub.value);
        return {
          stat: String(sub.stat ?? "").slice(0, 30),
          value: Number.isFinite(value) ? Math.max(0, Math.min(9999, value)) : 0,
        };
      }),
    };
  }
  return result;
}

/** 育成状況を保存する（既存データがあれば更新、なければ新規作成） */
export async function saveProgress(
  characterId: string,
  payload: ProgressPayload,
): Promise<ActionResult> {
  try {
    // キャラクターの存在を確認（不正なIDでの保存を防ぐ）
    const character = await prisma.character.findUnique({
      where: { id: characterId },
    });
    if (!character) {
      return { ok: false, message: "キャラクターが見つかりません。" };
    }

    const userId = await ensureUserId();

    const data = {
      level: clampInt(payload.level, 1, CHARACTER_LEVEL_MAX),
      ascension: clampInt(payload.ascension, 0, 6),
      constellation: clampInt(payload.constellation, 0, 6),
      talentNormal: clampInt(payload.talents?.normalAttack, 1, 10),
      talentSkill: clampInt(payload.talents?.elementalSkill, 1, 10),
      talentBurst: clampInt(payload.talents?.elementalBurst, 1, 10),
      weaponId: String(payload.weaponId ?? "").slice(0, 20),
      weaponName: String(payload.weaponName ?? "").slice(0, 100),
      weaponLevel: snapWeaponLevel(payload.weaponLevel),
      weaponRefinement: clampInt(payload.weaponRefinement, 1, 5),
      artifacts: JSON.stringify(sanitizeArtifacts(payload.artifacts)),
      isCompleted: payload.isCompleted === true,
      memo: String(payload.memo ?? "").slice(0, 1000),
    };

    await prisma.userProgress.upsert({
      where: { userId_characterId: { userId, characterId } },
      create: { userId, characterId, ...data },
      update: data,
    });

    revalidatePath("/");
    revalidatePath(`/characters/${characterId}`);
    return { ok: true, message: "保存しました。" };
  } catch (error) {
    console.error("育成状況の保存に失敗しました:", error);
    return {
      ok: false,
      message: "保存に失敗しました。時間をおいて再度お試しください。",
    };
  }
}

/** 育成状況を削除する（管理をやめる） */
export async function deleteProgress(characterId: string): Promise<ActionResult> {
  try {
    const cookieStore = await cookies();
    const userId = cookieStore.get(USER_ID_COOKIE)?.value;
    if (!userId) return { ok: false, message: "削除対象がありません。" };

    await prisma.userProgress.deleteMany({ where: { userId, characterId } });

    revalidatePath("/");
    revalidatePath(`/characters/${characterId}`);
    return { ok: true, message: "削除しました。" };
  } catch (error) {
    console.error("育成状況の削除に失敗しました:", error);
    return { ok: false, message: "削除に失敗しました。" };
  }
}
