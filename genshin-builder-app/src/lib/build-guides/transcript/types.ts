export type TranscriptFormat = "txt" | "vtt" | "srt";

export interface TranscriptSegment {
  index: number;
  startMs: number | null;
  endMs: number | null;
  text: string;
}

export interface NormalizedTranscript {
  format: TranscriptFormat;
  segments: TranscriptSegment[];
  normalizedText: string;
  charCount: number;
}
