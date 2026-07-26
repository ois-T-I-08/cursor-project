import type { NormalizedTranscript, TranscriptSegment } from "./types";

function parseTimestamp(value: string): number | null {
  const match = value.trim().match(/^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$/);
  if (!match) return null;
  const hours = Number(match[1] ?? 0);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  const millis = Number((match[4] ?? "0").padEnd(3, "0"));
  if (![hours, minutes, seconds, millis].every(Number.isFinite)) return null;
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
}

export function parseVttTranscript(raw: string): NormalizedTranscript {
  const body = raw
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/^\uFEFF?WEBVTT[^\n]*\n+/i, "");

  const blocks = body.split(/\n{2,}/);
  const segments: TranscriptSegment[] = [];
  let index = 0;

  for (const block of blocks) {
    const lines = block
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.startsWith("NOTE"));
    if (lines.length === 0) continue;

    let timingLine = lines[0]!;
    let textLines = lines.slice(1);
    if (!timingLine.includes("-->") && lines[1]?.includes("-->")) {
      timingLine = lines[1]!;
      textLines = lines.slice(2);
    }
    if (!timingLine.includes("-->")) continue;

    const [startRaw, endPart] = timingLine.split("-->");
    const endRaw = (endPart ?? "").trim().split(/\s+/)[0] ?? "";
    const startMs = parseTimestamp(startRaw ?? "");
    const endMs = parseTimestamp(endRaw);
    const text = textLines
      .join(" ")
      .replace(/<[^>]+>/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (!text) continue;
    segments.push({ index, startMs, endMs, text });
    index += 1;
  }

  const normalizedText = segments.map((s) => s.text).join("\n");
  return {
    format: "vtt",
    segments,
    normalizedText,
    charCount: Buffer.byteLength(normalizedText, "utf8"),
  };
}
