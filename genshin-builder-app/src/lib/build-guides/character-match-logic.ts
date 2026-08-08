export interface CharacterHint {
  id: string;
  name: string;
}

/**
 * Deterministic short-name → official master name.
 * Only unambiguous nicknames. Do not add speculative / AI aliases.
 */
export const CHARACTER_TITLE_ALIASES: Readonly<Record<string, string>> = {
  召使: "アルレッキーノ",
  心海: "珊瑚宮心海",
  万葉: "楓原万葉",
};

/**
 * Multi-character / artifact-meta titles — never force a single primary.
 * Applied only when no clear 「quoted」 primary was resolved.
 */
export function isAmbiguousMultiCharacterTitle(title: string): boolean {
  return /おすすめキャラ|評価が変わるキャラ|装備すべきキャラ|避けるべきキャラ|乗り換え必須キャラ|残すべき聖遺物|残す基準|おすすめキャラと/.test(
    title,
  );
}

function resolveOfficialNameToId(
  officialName: string,
  byName: Map<string, string>,
): string | null {
  return byName.get(officialName.trim().toLowerCase()) ?? null;
}

/** Resolve a quoted or bare token via official name or deterministic alias. */
export function resolveCharacterTokenToId(
  token: string,
  hints: CharacterHint[],
): string | null {
  const trimmed = token.trim();
  if (!trimmed) return null;
  const byName = new Map(
    hints
      .filter((h) => h.name.trim().length > 0)
      .map((h) => [h.name.trim().toLowerCase(), h.id] as const),
  );
  const direct = byName.get(trimmed.toLowerCase());
  if (direct) return direct;
  const aliasedOfficial = CHARACTER_TITLE_ALIASES[trimmed];
  if (aliasedOfficial) {
    return resolveOfficialNameToId(aliasedOfficial, byName);
  }
  // Case-insensitive alias keys (Japanese typically unchanged)
  for (const [alias, official] of Object.entries(CHARACTER_TITLE_ALIASES)) {
    if (alias.toLowerCase() === trimmed.toLowerCase()) {
      return resolveOfficialNameToId(official, byName);
    }
  }
  return null;
}

export function resolveCharacterCandidates(
  title: string,
  description: string,
  hints: CharacterHint[],
): { matchedIds: string[]; unresolved: string[] } {
  const haystack = `${title}\n${description}`.toLowerCase();
  const matchedIds: string[] = [];
  for (const hint of hints) {
    const name = hint.name.trim().toLowerCase();
    const id = hint.id.toLowerCase();
    if (!name && !id) continue;
    if ((name && haystack.includes(name)) || haystack.includes(id)) {
      matchedIds.push(hint.id);
    }
  }
  return { matchedIds: [...new Set(matchedIds)], unresolved: [] };
}

/**
 * 動画タイトルから「主対象キャラ」を1人に絞る。
 * 「名前」表記を最優先（公式名 → deterministic alias）、なければ最長公式名一致。
 * 複数キャラ聖遺物メタタイトルは primary を返さない。
 */
export function resolvePrimaryCharacterFromTitle(
  title: string,
  hints: CharacterHint[],
): string | null {
  const byName = new Map(
    hints
      .filter((h) => h.name.trim().length > 0)
      .map((h) => [h.name.trim().toLowerCase(), h.id] as const),
  );

  for (const match of title.matchAll(/「([^」]{1,40})」/g)) {
    const quoted = match[1]?.trim();
    if (!quoted) continue;
    const id = resolveCharacterTokenToId(quoted, hints);
    if (id) return id;
  }

  if (isAmbiguousMultiCharacterTitle(title)) {
    return null;
  }

  const haystack = title.toLowerCase();
  let best: { id: string; len: number } | null = null;
  for (const hint of hints) {
    const name = hint.name.trim().toLowerCase();
    if (name.length < 2) continue;
    if (!haystack.includes(name)) continue;
    if (!best || name.length > best.len) {
      best = { id: hint.id, len: name.length };
    }
  }
  if (best) return best.id;

  // Bare alias match (non-quoted) — only when a single alias hits uniquely.
  const aliasHits: string[] = [];
  for (const [alias, official] of Object.entries(CHARACTER_TITLE_ALIASES)) {
    if (!haystack.includes(alias.toLowerCase())) continue;
    const id = resolveOfficialNameToId(official, byName);
    if (id) aliasHits.push(id);
  }
  const unique = [...new Set(aliasHits)];
  if (unique.length === 1) return unique[0] ?? null;

  return null;
}

/** 育成ガイド寄りのタイトルか（ガチャ優先度・評価のみは除外） */
export function isCharacterBuildGuideTitle(title: string): boolean {
  if (!/おすすめ武器|聖遺物|目標ステータス|育成|ビルド|ステータスガイド|完全解説|最新解説|最新ガイド|正しい育成/.test(title)) {
    return false;
  }
  if (
    /ガチャ優先度|引くべき／スルー|引くべき\/スルー|武器ガチャのオススメ度/.test(title) &&
    !/おすすめ武器・聖遺物|目標ステータス|ステータスガイド/.test(title)
  ) {
    return false;
  }
  return true;
}
