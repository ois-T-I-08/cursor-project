import { createHash } from "node:crypto";
import { automationHash } from "./idempotency";
import { YOUTUBE_AUTOMATION_POLICY } from "./quality-policy";
import type {
  TranscriptDocument,
  TranscriptSegmentInput,
} from "./transcript-provider";

export type NormalizedTranscriptSegment = Readonly<{
  index: number;
  segmentKey: string;
  startSeconds: number;
  durationSeconds: number;
  text: string;
  textHash: string;
}>;

export type NormalizedTranscript = Readonly<{
  providerId: string;
  videoId: string;
  language: string;
  trackKind: "manual" | "asr";
  sourceTrackId: string;
  transcriptHash: string;
  segments: readonly NormalizedTranscriptSegment[];
  fetchedAt: Date;
}>;

export type TranscriptChunk = Readonly<{
  chunkIndex: number;
  segmentIds: readonly string[];
  text: string;
}>;

export class TranscriptValidationError extends Error {
  constructor(public readonly safeCode: string) {
    super(safeCode);
    this.name = "TranscriptValidationError";
  }
}

export function parseWebVtt(value: string): TranscriptSegmentInput[] {
  if (Buffer.byteLength(value, "utf8") > YOUTUBE_AUTOMATION_POLICY.maxTranscriptBytes) {
    throw new TranscriptValidationError("TRANSCRIPT_RESPONSE_TOO_LARGE");
  }
  const lines = value.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").split("\n");
  const segments: TranscriptSegmentInput[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]?.trim() ?? "";
    if (!line || line === "WEBVTT" || line.startsWith("NOTE")) continue;
    const timingLine = line.includes("-->")
      ? line
      : (lines[index + 1]?.trim() ?? "");
    if (!timingLine.includes("-->")) continue;
    if (timingLine !== line) index += 1;
    const match = timingLine.match(
      /^(\d{2}:)?\d{2}:\d{2}(?:\.\d{1,3})?\s+-->\s+(\d{2}:)?\d{2}:\d{2}(?:\.\d{1,3})?/,
    );
    if (!match) throw new TranscriptValidationError("TRANSCRIPT_INVALID_TIMING");
    const [startRaw, endRaw] = timingLine.split("-->").map((part) => part.trim().split(/\s+/)[0] ?? "");
    const startSeconds = parseVttTime(startRaw);
    const endSeconds = parseVttTime(endRaw);
    const textLines: string[] = [];
    while (++index < lines.length && lines[index]?.trim()) {
      textLines.push(lines[index]!.trim());
    }
    const text = normalizeTranscriptText(textLines.join(" "));
    if (!text) continue;
    segments.push({
      startSeconds,
      durationSeconds: endSeconds - startSeconds,
      text,
    });
  }
  return segments;
}

export function normalizeTranscript(
  document: TranscriptDocument,
): NormalizedTranscript {
  if (document.segments.length === 0) {
    throw new TranscriptValidationError("TRANSCRIPT_EMPTY");
  }
  if (document.segments.length > YOUTUBE_AUTOMATION_POLICY.maxTranscriptSegments) {
    throw new TranscriptValidationError("TRANSCRIPT_TOO_MANY_SEGMENTS");
  }
  let previousStart = -1;
  const segments = document.segments.map((segment, index) => {
    const startSeconds = roundMillis(segment.startSeconds);
    const durationSeconds = roundMillis(segment.durationSeconds);
    const text = normalizeTranscriptText(segment.text);
    if (
      !Number.isFinite(startSeconds) ||
      !Number.isFinite(durationSeconds) ||
      startSeconds < 0 ||
      durationSeconds <= 0 ||
      startSeconds < previousStart
    ) {
      throw new TranscriptValidationError("TRANSCRIPT_INVALID_TIMING");
    }
    if (!text) throw new TranscriptValidationError("TRANSCRIPT_EMPTY_SEGMENT");
    previousStart = startSeconds;
    const textHash = sha256(text);
    return Object.freeze({
      index,
      segmentKey: automationHash("youtube-transcript-segment-v1", {
        videoId: document.videoId,
        sourceTrackId: document.sourceTrackId,
        index,
        startSeconds,
        textHash,
      }),
      startSeconds,
      durationSeconds,
      text,
      textHash,
    });
  });
  const transcriptHash = automationHash(
    "youtube-transcript-content-v1",
    segments.map(({ startSeconds, durationSeconds, textHash }) => ({
      startSeconds,
      durationSeconds,
      textHash,
    })),
  );
  return Object.freeze({
    providerId: document.providerId,
    videoId: document.videoId,
    language: document.language.toLowerCase(),
    trackKind: document.trackKind,
    sourceTrackId: document.sourceTrackId,
    transcriptHash,
    segments,
    fetchedAt: new Date(document.fetchedAt),
  });
}

export function chunkTranscript(
  transcript: NormalizedTranscript,
  maxCharacters: number = YOUTUBE_AUTOMATION_POLICY.chunkMaxCharacters,
  overlapSegments: number = YOUTUBE_AUTOMATION_POLICY.chunkOverlapSegments,
): TranscriptChunk[] {
  if (maxCharacters < 100 || overlapSegments < 0) {
    throw new TranscriptValidationError("TRANSCRIPT_INVALID_CHUNK_CONFIG");
  }
  const chunks: TranscriptChunk[] = [];
  let cursor = 0;
  while (cursor < transcript.segments.length) {
    const start = cursor;
    const selected: NormalizedTranscriptSegment[] = [];
    let length = 0;
    while (cursor < transcript.segments.length) {
      const segment = transcript.segments[cursor]!;
      const line = `${segment.segmentKey}\t${segment.startSeconds}\t${segment.text}`;
      if (selected.length > 0 && length + line.length + 1 > maxCharacters) break;
      selected.push(segment);
      length += line.length + 1;
      cursor += 1;
    }
    chunks.push({
      chunkIndex: chunks.length,
      segmentIds: selected.map((segment) => segment.segmentKey),
      text: selected
        .map(
          (segment) =>
            `${segment.segmentKey}\t${segment.startSeconds}\t${segment.text}`,
        )
        .join("\n"),
    });
    if (cursor >= transcript.segments.length) break;
    cursor = Math.max(start + 1, cursor - overlapSegments);
  }
  return chunks;
}

export function normalizeTranscriptText(value: string): string {
  return value
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/\s+/g, " ")
    .trim();
}

function parseVttTime(value: string): number {
  const parts = value.split(":");
  if (parts.length !== 2 && parts.length !== 3) {
    throw new TranscriptValidationError("TRANSCRIPT_INVALID_TIMING");
  }
  const seconds = Number(parts.at(-1));
  const minutes = Number(parts.at(-2));
  const hours = parts.length === 3 ? Number(parts[0]) : 0;
  const total = hours * 3600 + minutes * 60 + seconds;
  if (
    !Number.isFinite(total) ||
    hours < 0 ||
    minutes < 0 ||
    minutes >= 60 ||
    seconds < 0 ||
    seconds >= 60
  ) {
    throw new TranscriptValidationError("TRANSCRIPT_INVALID_TIMING");
  }
  return roundMillis(total);
}

function roundMillis(value: number): number {
  return Math.round(value * 1_000) / 1_000;
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
