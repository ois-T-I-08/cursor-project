import { createHash } from "node:crypto";

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`)
    .join(",")}}`;
}

export function automationHash(namespace: string, value: unknown): string {
  return createHash("sha256")
    .update(`${namespace}\0${stable(value)}`, "utf8")
    .digest("hex");
}

export function discoveryIdempotencyKey(input: {
  videoId: string;
  metadataHash: string;
}): string {
  return automationHash("youtube-discovery-v1", input);
}

export function transcriptIdentityKey(input: {
  videoId: string;
  language: string;
  providerId: string;
  sourceTrackId: string;
  transcriptHash: string;
}): string {
  return automationHash("youtube-transcript-v1", input);
}

export function analysisIdempotencyKey(input: {
  videoId: string;
  metadataHash: string;
  transcriptHash: string;
  analyzerVersion: string;
  promptVersion: string;
  schemaVersion: string;
}): string {
  return automationHash("youtube-analysis-v1", input);
}

export function publicationKey(input: {
  characterId: string;
  analysisKeys: string[];
  policyVersion: string;
  schemaVersion: string;
}): string {
  return automationHash("youtube-publication-v1", {
    ...input,
    analysisKeys: [...input.analysisKeys].sort(),
  });
}

export function actionKey(input: {
  publicationKey: string;
  action: string;
}): string {
  return automationHash("youtube-action-v1", input);
}
