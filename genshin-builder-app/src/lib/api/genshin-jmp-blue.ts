/**
 * genshin.jmp.blue（旧 genshin.dev）用のデータ取得プロバイダー。
 *
 * このファイルの責務は「外部APIのレスポンスを正規化済みの型に変換すること」のみ。
 * APIの仕様変更やプロバイダー乗り換え時は、このファイルだけ修正すればよい。
 */

import type {
  GameDataProvider,
  MasterCharacter,
  MasterMaterial,
  MasterWeapon,
} from "./types";

const BASE_URL = "https://genshin.jmp.blue";

/** API側の元素表記（PYRO等）→ アプリ内部の表記（pyro等） */
const ELEMENT_MAP: Record<string, string> = {
  PYRO: "pyro",
  HYDRO: "hydro",
  ELECTRO: "electro",
  CRYO: "cryo",
  ANEMO: "anemo",
  GEO: "geo",
  DENDRO: "dendro",
};

/** API側の武器種表記（SWORD / Sword等）→ アプリ内部の表記 */
const WEAPON_TYPE_MAP: Record<string, string> = {
  SWORD: "sword",
  CLAYMORE: "claymore",
  POLEARM: "polearm",
  BOW: "bow",
  CATALYST: "catalyst",
};

/** /characters/all のレスポンス1件分（必要な項目のみ定義） */
interface ApiCharacter {
  id: string;
  name: string;
  vision_key: string;
  weapon_type: string;
  rarity: number;
  nation: string;
}

/** /weapons/all のレスポンス1件分（必要な項目のみ定義） */
interface ApiWeapon {
  id: string;
  name: string;
  type: string;
  rarity: number;
}

/** タイムアウト付きでJSONを取得する共通ヘルパー */
async function fetchJson<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    // マスターデータは頻繁に変わらないため、Next.js のキャッシュを1時間有効にする
    next: { revalidate: 3600 },
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) {
    throw new Error(`API request failed: ${path} (${res.status})`);
  }
  return (await res.json()) as T;
}

/**
 * 素材APIのレスポンスは種類ごとに構造が異なるため、
 * JSONを再帰的に走査して「id と name を持つオブジェクト」または
 * 「キー: { name: ... } 形式のエントリ」を素材として抽出する。
 */
function extractMaterials(
  node: unknown,
  category: string,
  collected: Map<string, MasterMaterial>,
  keyAsId?: string,
): void {
  if (Array.isArray(node)) {
    for (const item of node) extractMaterials(item, category, collected);
    return;
  }
  if (node === null || typeof node !== "object") return;

  const obj = node as Record<string, unknown>;
  const id =
    typeof obj.id === "string"
      ? obj.id
      : typeof obj.name === "string" && keyAsId
        ? keyAsId
        : undefined;

  if (id && typeof obj.name === "string") {
    if (!collected.has(id)) {
      collected.set(id, {
        id,
        name: obj.name,
        category,
        rarity: typeof obj.rarity === "number" ? obj.rarity : null,
        iconUrl: `${BASE_URL}/materials/${category}/${id}`,
      });
    }
    return;
  }

  // 子要素を走査（キー名を仮のIDとして引き継ぐ）
  for (const [key, value] of Object.entries(obj)) {
    if (key === "id") continue;
    extractMaterials(value, category, collected, key);
  }
}

export const genshinJmpBlueProvider: GameDataProvider = {
  name: "genshin.jmp.blue",

  async fetchCharacters(): Promise<MasterCharacter[]> {
    const characters = await fetchJson<ApiCharacter[]>("/characters/all");

    return characters
      .filter((c) => c.id && c.name)
      .map((c) => ({
        id: c.id,
        name: c.name,
        element: ELEMENT_MAP[c.vision_key?.toUpperCase()] ?? "anemo",
        weaponType: WEAPON_TYPE_MAP[c.weapon_type?.toUpperCase()] ?? "sword",
        rarity: c.rarity === 4 ? 4 : 5,
        region: c.nation ?? "Unknown",
        iconUrl: `${BASE_URL}/characters/${c.id}/icon-big`,
        scoreType: "atk",
      }));
  },

  async fetchWeapons(): Promise<MasterWeapon[]> {
    const weapons = await fetchJson<ApiWeapon[]>("/weapons/all");

    return weapons
      .filter((w) => w.id && w.name)
      .map((w) => ({
        id: w.id,
        name: w.name,
        weaponType: WEAPON_TYPE_MAP[w.type?.toUpperCase()] ?? "sword",
        rarity: w.rarity,
        iconUrl: `${BASE_URL}/weapons/${w.id}/icon`,
      }));
  },

  async fetchMaterials(): Promise<MasterMaterial[]> {
    const categories = await fetchJson<string[]>("/materials");
    const collected = new Map<string, MasterMaterial>();

    // カテゴリごとに取得。1つ失敗しても他のカテゴリの同期は続行する
    const results = await Promise.allSettled(
      categories.map(async (category) => {
        const data = await fetchJson<unknown>(`/materials/${category}`);
        extractMaterials(data, category, collected);
      }),
    );

    const failed = results.filter((r) => r.status === "rejected");
    if (failed.length === categories.length) {
      throw new Error("すべての素材カテゴリの取得に失敗しました");
    }

    return [...collected.values()];
  },
};
