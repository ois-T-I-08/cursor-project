import type {
  TranscriptDocument,
  TranscriptProvider,
  TranscriptTrack,
} from "./transcript-provider";

export class DeterministicTranscriptProvider implements TranscriptProvider {
  readonly providerId = "deterministic-transcript-test-v1";

  constructor(
    private readonly documents: ReadonlyMap<string, TranscriptDocument>,
  ) {}

  async listTracks(videoId: string): Promise<readonly TranscriptTrack[]> {
    const document = this.documents.get(videoId);
    if (!document) return [];
    return [
      {
        trackId: document.sourceTrackId,
        language: document.language,
        trackKind: document.trackKind,
        isDraft: false,
      },
    ];
  }

  async fetchTrack(
    videoId: string,
    track: TranscriptTrack,
  ): Promise<TranscriptDocument> {
    const document = this.documents.get(videoId);
    if (!document || document.sourceTrackId !== track.trackId) {
      throw new Error("deterministicTranscriptMissing");
    }
    return {
      ...document,
      fetchedAt: new Date(document.fetchedAt),
      segments: document.segments.map((segment) => ({ ...segment })),
    };
  }
}
