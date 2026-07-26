import { createHash } from "node:crypto";

export function buildVisualRequestHash(input: {
  videoId: string;
  videoMetadataHash: string;
  videoPublishedAt: string | null;
  videoDuration: number | null;
  providerId: string;
  modelIdentifier: string;
  visualPromptVersion: string;
  visualSchemaVersion: string;
  gameDataVersion: string;
  requestedRanges?: Array<{ startSeconds: number; endSeconds: number }>;
}): string {
  const payload = {
    videoId: input.videoId,
    videoMetadataHash: input.videoMetadataHash,
    videoPublishedAt: input.videoPublishedAt ?? "",
    videoDuration: input.videoDuration ?? null,
    providerId: input.providerId,
    modelIdentifier: input.modelIdentifier,
    visualPromptVersion: input.visualPromptVersion,
    visualSchemaVersion: input.visualSchemaVersion,
    gameDataVersion: input.gameDataVersion,
    requestedRanges: (input.requestedRanges ?? [])
      .map((r) => `${r.startSeconds}-${r.endSeconds}`)
      .sort(),
  };
  return createHash("sha256").update(JSON.stringify(payload), "utf8").digest("hex");
}

export function buildManifestHash(characterId: string, videoIds: string[]): string {
  return createHash("sha256")
    .update(JSON.stringify({ characterId, videoIds: [...videoIds].sort() }), "utf8")
    .digest("hex");
}
