import "server-only";

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseCharacterTeamProfileCollection } from "./validation";

export async function loadLocalCharacterProfiles(): Promise<
  ReturnType<typeof parseCharacterTeamProfileCollection>
> {
  const path = resolve(
    process.cwd(),
    "data",
    "team-templates",
    "character-profiles.json",
  );
  const content = await readFile(path, "utf8");
  if (Buffer.byteLength(content, "utf8") > 2_097_152) {
    throw new Error("characterProfileSourceTooLarge");
  }
  return parseCharacterTeamProfileCollection(JSON.parse(content) as unknown);
}
