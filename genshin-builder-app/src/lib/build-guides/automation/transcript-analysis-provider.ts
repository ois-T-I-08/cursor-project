import type { TranscriptChunk } from "./transcript-normalize";

export type TranscriptAnalysisInput = Readonly<{
  videoId: string;
  characterId: string;
  language: string;
  chunks: readonly TranscriptChunk[];
  allowedEntityIds: readonly string[];
}>;

export type TranscriptAnalysisCompletion = Readonly<{
  value: unknown;
  modelIdentifier: string;
  attempts: number;
  usage: Readonly<Record<string, number>>;
}>;

export interface TranscriptAnalysisProvider {
  readonly providerId: string;
  readonly supportsStrictSchema: true;
  analyze(
    input: TranscriptAnalysisInput,
  ): Promise<TranscriptAnalysisCompletion>;
}

export class DeterministicTranscriptAnalysisProvider
  implements TranscriptAnalysisProvider
{
  readonly providerId = "deterministic-transcript-analysis-test-v1";
  readonly supportsStrictSchema = true as const;

  constructor(private readonly value: unknown) {}

  async analyze(): Promise<TranscriptAnalysisCompletion> {
    return {
      value: structuredClone(this.value),
      modelIdentifier: "deterministic",
      attempts: 1,
      usage: {},
    };
  }
}
