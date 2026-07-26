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
