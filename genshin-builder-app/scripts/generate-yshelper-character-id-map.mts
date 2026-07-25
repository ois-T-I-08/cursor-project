/**
 * Regenerate or check YSHELPER_CHARACTER_ID_BY_NAME from Project Amber EN avatars.
 *
 *   npm run yshelper:generate-character-map
 *   npm run yshelper:check-character-map
 *
 * Does not enable YShelper collection, does not write DB, does not persist
 * Amber response bodies.
 */
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { fetchJsonObject } from "../src/lib/api/safe-json-fetch";
import {
  AMBER_EN_AVATAR_ORIGIN,
  AMBER_EN_AVATAR_PATH,
  buildCharacterIdMapFromAmberData,
  CharacterIdMapGenerateError,
  diffCharacterIdMaps,
  parseCharacterIdMapSource,
  renderCharacterIdMapSource,
} from "../src/lib/yshelper/character-id-map-generate";

const TIMEOUT_MS = 20_000;
const MAX_BYTES = 4 * 1024 * 1024;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MAP_PATH = path.join(ROOT, "src/lib/yshelper/character-id-map.ts");

async function main(): Promise<void> {
  const checkOnly = process.argv.includes("--check");
  const url = new URL(AMBER_EN_AVATAR_PATH, AMBER_EN_AVATAR_ORIGIN);
  if (url.origin !== AMBER_EN_AVATAR_ORIGIN || url.protocol !== "https:") {
    throw new CharacterIdMapGenerateError("amber_origin_rejected");
  }

  let previousSource: string | null = null;
  try {
    previousSource = readFileSync(MAP_PATH, "utf8");
  } catch {
    previousSource = null;
  }
  const previous = previousSource
    ? parseCharacterIdMapSource(previousSource)
    : null;

  const payload = await fetchJsonObject(url.toString(), {
    timeoutMs: TIMEOUT_MS,
    maxBytes: MAX_BYTES,
    retries: 0,
    requireJsonContentType: true,
    headers: {
      Accept: "application/json",
      "User-Agent": "genshin-builder/yshelper-character-map",
    },
  });

  const { map, count } = buildCharacterIdMapFromAmberData(payload, previous);
  const nextSource = renderCharacterIdMapSource(map);
  const previousMap = previous ?? {};
  const diff = diffCharacterIdMaps(previousMap, map);

  console.info("yshelper_character_map", {
    mode: checkOnly ? "check" : "generate",
    count,
    previousCount: Object.keys(previousMap).length,
    added: diff.added.length,
    removed: diff.removed.length,
    changed: diff.changed.length,
  });

  if (checkOnly) {
    if (previousSource === null || previous === null) {
      console.error("yshelper_character_map_missing");
      process.exit(1);
    }
    // Semantic map equality (names → ids). Formatting-only drift does not fail
    // check; run generate to refresh the committed source layout.
    if (
      diff.added.length > 0 ||
      diff.removed.length > 0 ||
      diff.changed.length > 0
    ) {
      console.error("yshelper_character_map_drift", {
        added: diff.added.length,
        removed: diff.removed.length,
        changed: diff.changed.length,
      });
      process.exit(1);
    }
    console.info("yshelper_character_map_ok", { count });
    return;
  }

  writeFileSync(MAP_PATH, nextSource, "utf8");
  console.info("yshelper_character_map_written", { count });
}

main().catch((error: unknown) => {
  const code =
    error instanceof CharacterIdMapGenerateError
      ? error.code
      : error instanceof Error
        ? error.name
        : "unknown";
  console.error("yshelper_character_map_failed", { code });
  process.exit(1);
});
