import type { VideoVisualAnalysisResult } from "./visual-schemas";

export type VideoVisualAnalysisInput = {
  videoId: string;
  youtubeUrl: string;
  channelId: string;
  title: string;
  publishedAt: string | null;
  durationSeconds: number | null;
  targetCharacterIds: string[];
  requestedRanges?: {
    startSeconds: number;
    endSeconds: number;
    reason: string;
  }[];
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
