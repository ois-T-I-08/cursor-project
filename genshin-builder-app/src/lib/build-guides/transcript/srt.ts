import type { NormalizedTranscript, TranscriptSegment } from "./types";

function parseTimestamp(value: string): number | null {
  const match = value.trim().match(/^(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})$/);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  const millis = Number(match[4]!.padEnd(3, "0"));
  if (![hours, minutes, seconds, millis].every(Number.isFinite)) return null;
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
}

export function parseSrtTranscript(raw: string): NormalizedTranscript {
  const body = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/^\uFEFF/, "");
  const blocks = body.split(/\n{2,}/);
  const segments: TranscriptSegment[] = [];
  let index = 0;

  for (const block of blocks) {
    const lines = block
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
    if (lines.length < 2) continue;

    let timingIdx = 0;
    if (/^\d+$/.test(lines[0]!)) timingIdx = 1;
    const timingLine = lines[timingIdx];
    if (!timingLine?.includes("-->")) continue;

    const [startRaw, endRaw] = timingLine.split("-->").map((part) => part.trim());
    const startMs = parseTimestamp(startRaw ?? "");
    const endMs = parseTimestamp(endRaw ?? "");
    const text = lines
      .slice(timingIdx + 1)
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
    format: "srt",
    segments,
    normalizedText,
    charCount: Buffer.byteLength(normalizedText, "utf8"),
  };
}
