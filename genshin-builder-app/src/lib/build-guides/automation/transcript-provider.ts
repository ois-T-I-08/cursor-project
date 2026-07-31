import type { SafeProviderError } from "./provider-error";

export type TranscriptTrack = Readonly<{
  trackId: string;
  language: string;
  trackKind: "manual" | "asr";
  isDraft: boolean;
}>;

export type TranscriptSegmentInput = Readonly<{
  startSeconds: number;
  durationSeconds: number;
  text: string;
}>;

export type TranscriptDocument = Readonly<{
  providerId: string;
  videoId: string;
  language: string;
  trackKind: "manual" | "asr";
  sourceTrackId: string;
  segments: readonly TranscriptSegmentInput[];
  fetchedAt: Date;
}>;

export interface TranscriptProvider {
  readonly providerId: string;
  listTracks(videoId: string): Promise<readonly TranscriptTrack[]>;
  fetchTrack(videoId: string, track: TranscriptTrack): Promise<TranscriptDocument>;
}

export type TranscriptFetchOutcome =
  | { ok: true; document: TranscriptDocument }
  | {
      ok: false;
      blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE";
      error: SafeProviderError;
    };

/**
 * Deterministic selection: requested language, manual before ASR, then track id.
 * An unavailable transcript is terminal for this item and never falls back to
 * scraping, cookies, or media download.
 */
export async function fetchPreferredTranscript(
  provider: TranscriptProvider,
  videoId: string,
  preferredLanguages: readonly string[] = ["ja", "en"],
): Promise<TranscriptFetchOutcome> {
  try {
    const tracks = await provider.listTracks(videoId);
    const languageRank = new Map(
      preferredLanguages.map((language, index) => [language.toLowerCase(), index]),
    );
    const selected = [...tracks]
      .filter((track) => !track.isDraft)
      .sort((left, right) => {
        const leftLanguage = languageRank.get(left.language.toLowerCase()) ?? 999;
        const rightLanguage = languageRank.get(right.language.toLowerCase()) ?? 999;
        return (
          leftLanguage - rightLanguage ||
          Number(left.trackKind === "asr") - Number(right.trackKind === "asr") ||
          left.trackId.localeCompare(right.trackId)
        );
      })[0];
    if (!selected) {
      const { SafeProviderError } = await import("./provider-error");
      return {
        ok: false,
        blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE",
        error: new SafeProviderError(
          provider.providerId,
          "TRANSCRIPT_UNAVAILABLE",
          false,
        ),
      };
    }
    return { ok: true, document: await provider.fetchTrack(videoId, selected) };
  } catch (error) {
    const { toSafeProviderError } = await import("./provider-error");
    return {
      ok: false,
      blockCode: "BLOCKED_TRANSCRIPT_UNAVAILABLE",
      error: toSafeProviderError(provider.providerId, error),
    };
  }
}

