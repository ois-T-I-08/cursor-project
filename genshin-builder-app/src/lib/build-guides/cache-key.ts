import { createHash } from "node:crypto";

export function buildGuideCacheKey(input: {
  videoId: string;
  transcriptHash: string;
  characterDataVersion: string;
  promptVersion: string;
  schemaVersion: string;
  modelIdentifier: string;
  characterId?: string;
  mergedVideoIds?: string[];
}): string {
  const payload = {
    videoId: input.videoId,
    transcriptHash: input.transcriptHash,
    characterDataVersion: input.characterDataVersion,
    promptVersion: input.promptVersion,
    schemaVersion: input.schemaVersion,
    modelIdentifier: input.modelIdentifier,
    characterId: input.characterId ?? "",
    mergedVideoIds: [...(input.mergedVideoIds ?? [])].sort(),
  };
  return createHash("sha256").update(JSON.stringify(payload), "utf8").digest("hex");
}

export function buildManifestHash(characterId: string, videoIds: string[]): string {
  return createHash("sha256")
    .update(JSON.stringify({ characterId, videoIds: [...videoIds].sort() }), "utf8")
    .digest("hex");
}
