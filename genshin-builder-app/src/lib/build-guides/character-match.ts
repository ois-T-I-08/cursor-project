import "server-only";

import { prisma } from "@/lib/db";
import {
  resolveCharacterCandidates,
  type CharacterHint,
} from "./character-match-logic";

export type { CharacterHint };
export { resolveCharacterCandidates };

export async function loadCharacterHints(): Promise<CharacterHint[]> {
  const rows = await prisma.character.findMany({
    select: { id: true, name: true },
    orderBy: { id: "asc" },
  });
  return rows;
}

export async function assertKnownCharacterId(characterId: string): Promise<boolean> {
  const count = await prisma.character.count({ where: { id: characterId } });
  return count > 0;
}
