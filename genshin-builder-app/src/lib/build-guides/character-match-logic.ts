export interface CharacterHint {
  id: string;
  name: string;
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
 * 「名前」表記を最優先し、なければタイトル内の最長名一致を使う。
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
    const quoted = match[1]?.trim().toLowerCase();
    if (!quoted) continue;
    const id = byName.get(quoted);
    if (id) return id;
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
  return best?.id ?? null;
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
