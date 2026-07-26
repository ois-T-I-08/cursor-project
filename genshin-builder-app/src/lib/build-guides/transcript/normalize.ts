import { parseSrtTranscript } from "./srt";
import { parseTxtTranscript } from "./txt";
import type { NormalizedTranscript, TranscriptFormat } from "./types";
import { parseVttTranscript } from "./vtt";

export class TranscriptError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "TranscriptError";
  }
}

export function detectTranscriptFormat(raw: string, hint?: TranscriptFormat): TranscriptFormat {
  if (hint) return hint;
  const trimmed = raw.trimStart();
  if (/^WEBVTT/i.test(trimmed)) return "vtt";
  if (
    /^\d+\s*\n\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}/m.test(
      raw,
    )
  ) {
    return "srt";
  }
  if (/\d{1,2}:\d{2}:\d{2}\.\d{1,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}\.\d{1,3}/.test(raw)) {
    return "vtt";
  }
  return "txt";
}

export function normalizeTranscript(
  raw: string,
  options: { format?: TranscriptFormat; maxBytes?: number } = {},
): NormalizedTranscript {
  const maxBytes = options.maxBytes ?? guideTranscriptMaxBytes();
  if (Buffer.byteLength(raw, "utf8") > maxBytes) {
    throw new TranscriptError("transcriptTooLarge");
  }
  if (!raw.trim()) throw new TranscriptError("transcriptEmpty");

  const format = detectTranscriptFormat(raw, options.format);
  const parsed =
    format === "vtt"
      ? parseVttTranscript(raw)
      : format === "srt"
        ? parseSrtTranscript(raw)
        : parseTxtTranscript(raw);

  if (parsed.segments.length === 0) throw new TranscriptError("transcriptEmpty");
  if (parsed.charCount > maxBytes) throw new TranscriptError("transcriptTooLarge");
  return parsed;
}

export function guideTranscriptMaxBytes(): number {
  const value = Number(process.env.GUIDE_TRANSCRIPT_MAX_BYTES);
  if (Number.isFinite(value)) {
    return Math.min(2_000_000, Math.max(1_000, Math.round(value)));
  }
  return 500_000;
}
