import { createHash } from "node:crypto";

export function hashTranscript(normalizedText: string): string {
  return createHash("sha256").update(normalizedText, "utf8").digest("hex");
}
