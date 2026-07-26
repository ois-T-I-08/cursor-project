import type { NormalizedTranscript, TranscriptSegment } from "./types";

export interface TranscriptChunk {
  chunkIndex: number;
  startSegmentIndex: number;
  endSegmentIndex: number;
  text: string;
  segments: TranscriptSegment[];
}

export function chunkTranscript(
  transcript: NormalizedTranscript,
  options: { maxChars?: number; overlapSegments?: number } = {},
): TranscriptChunk[] {
  const maxChars = options.maxChars ?? 6_000;
  const overlapSegments = Math.max(0, options.overlapSegments ?? 2);
  const chunks: TranscriptChunk[] = [];
  let start = 0;

  while (start < transcript.segments.length) {
    let end = start;
    let size = 0;
    while (end < transcript.segments.length) {
      const nextLen = Buffer.byteLength(transcript.segments[end]!.text, "utf8") + (end > start ? 1 : 0);
      if (end > start && size + nextLen > maxChars) break;
      size += nextLen;
      end += 1;
      if (size >= maxChars) break;
    }
    if (end === start) end = start + 1;
    const segments = transcript.segments.slice(start, end);
    chunks.push({
      chunkIndex: chunks.length,
      startSegmentIndex: start,
      endSegmentIndex: end - 1,
      text: segments.map((s) => s.text).join("\n"),
      segments,
    });
    if (end >= transcript.segments.length) break;
    start = Math.max(start + 1, end - overlapSegments);
  }
  return chunks;
}
