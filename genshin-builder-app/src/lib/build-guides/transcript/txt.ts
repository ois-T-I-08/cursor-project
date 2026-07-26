import type { NormalizedTranscript, TranscriptSegment } from "./types";

export function parseTxtTranscript(raw: string): NormalizedTranscript {
  const lines = raw
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const segments: TranscriptSegment[] = lines.map((text, index) => ({
    index,
    startMs: null,
    endMs: null,
    text,
  }));
  const normalizedText = segments.map((s) => s.text).join("\n");
  return {
    format: "txt",
    segments,
    normalizedText,
    charCount: Buffer.byteLength(normalizedText, "utf8"),
  };
}
