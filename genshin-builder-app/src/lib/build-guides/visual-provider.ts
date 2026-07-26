import type { VideoVisualAnalysisResult } from "./visual-schemas";

export type VideoVisualAnalysisMode = "full_discovery" | "clipped_detail";

export type VideoVisualAnalysisInput = {
  videoId: string;
  youtubeUrl: string;
  channelId: string;
  title: string;
  publishedAt: string | null;
  durationSeconds: number | null;
  targetCharacterIds: string[];
  /** Clipped analysis windows. Empty/undefined = full discovery pass. */
  requestedRanges?: {
    startSeconds: number;
    endSeconds: number;
    reason: string;
  }[];
  analysisMode: VideoVisualAnalysisMode;
  /** Frame sampling rate sent via Gemini video_metadata.fps */
  fps: number;
  gameDataVersion: string;
};

export interface VideoVisualAnalysisProvider {
  readonly providerId: string;
  analyze(input: VideoVisualAnalysisInput): Promise<{
    result: VideoVisualAnalysisResult;
    rawContent: string;
    modelIdentifier: string;
    usage: Record<string, number>;
    attempts: number;
  }>;
}
