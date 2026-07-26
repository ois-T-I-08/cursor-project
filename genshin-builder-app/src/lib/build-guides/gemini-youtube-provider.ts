import "server-only";

import { z } from "zod";
import { GEMINI_PROVIDER_ID } from "./versions";
import { GeminiError, geminiVideoSettings } from "./gemini-settings";
import {
  buildVisualUserPrompt,
  VISUAL_SYSTEM_PROMPT,
} from "./visual-prompts";
import type {
  VideoVisualAnalysisInput,
  VideoVisualAnalysisProvider,
} from "./visual-provider";
import {
  videoVisualAnalysisResultSchema,
  type VideoVisualAnalysisResult,
} from "./visual-schemas";

const GEMINI_HOST = "https://generativelanguage.googleapis.com";

const envelopeSchema = z.object({
  candidates: z
    .array(
      z.object({
        content: z
          .object({
            parts: z
              .array(z.object({ text: z.string().optional() }))
              .optional(),
          })
          .optional(),
        finishReason: z.string().optional(),
      }),
    )
    .min(1),
  usageMetadata: z
    .object({
      promptTokenCount: z.number().optional(),
      candidatesTokenCount: z.number().optional(),
      totalTokenCount: z.number().optional(),
    })
    .optional(),
});

type ClipWindow = {
  startSeconds: number;
  endSeconds: number;
  reason: string;
};

export class GeminiYouTubeVisualAnalysisProvider
  implements VideoVisualAnalysisProvider
{
  readonly providerId = GEMINI_PROVIDER_ID;

  constructor(
    private readonly options: {
      fetchImpl?: typeof fetch;
      sleep?: (ms: number) => Promise<void>;
      random?: () => number;
    } = {},
  ) {}

  async analyze(input: VideoVisualAnalysisInput) {
    const settings = geminiVideoSettings();
    assertSafeYoutubeUrl(input.youtubeUrl, input.videoId);
    if (
      input.durationSeconds != null &&
      input.durationSeconds > settings.maxDurationSeconds
    ) {
      throw new GeminiError("videoTooLong", false);
    }

    const clips: Array<ClipWindow | null> =
      input.analysisMode === "clipped_detail" &&
      input.requestedRanges &&
      input.requestedRanges.length > 0
        ? input.requestedRanges
        : [null];

    const fetchImpl = this.options.fetchImpl ?? fetch;
    const sleep =
      this.options.sleep ??
      ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    const random = this.options.random ?? Math.random;

    const partialResults: VideoVisualAnalysisResult[] = [];
    const rawParts: string[] = [];
    const usageTotals: Record<string, number> = {};
    let attemptsUsed = 0;

    for (const clip of clips) {
      let lastError = new GeminiError("requestFailed", true);
      let succeeded = false;
      for (let attempt = 1; attempt <= settings.maxAttempts; attempt++) {
        attemptsUsed = Math.max(attemptsUsed, attempt);
        try {
          const completion = await this.request(fetchImpl, settings, input, clip);
          if (!completion.content.trim()) {
            throw new GeminiError("emptyResponse", true);
          }
          let decoded: unknown;
          try {
            decoded = JSON.parse(stripJsonFence(completion.content)) as unknown;
          } catch {
            throw new GeminiError("invalidJson", false);
          }
          const result = videoVisualAnalysisResultSchema.parse(decoded);
          partialResults.push(result);
          rawParts.push(completion.content);
          for (const [key, value] of Object.entries(completion.usage)) {
            usageTotals[key] = (usageTotals[key] ?? 0) + value;
          }
          succeeded = true;
          break;
        } catch (error) {
          lastError =
            error instanceof GeminiError
              ? error
              : error instanceof z.ZodError
                ? new GeminiError("invalidResult", false)
                : new GeminiError("requestFailed", true);
          if (!lastError.retryable || attempt === settings.maxAttempts) break;
          await sleep(
            Math.min(8_000, 500 * 2 ** (attempt - 1)) +
              Math.floor(random() * 100),
          );
        }
      }
      if (!succeeded) throw lastError;
    }

    return {
      result: mergeVisualResults(input.videoId, partialResults),
      rawContent: rawParts.join("\n---\n").slice(0, 200_000),
      modelIdentifier: settings.model,
      usage: usageTotals,
      attempts: attemptsUsed,
    };
  }

  private async request(
    fetchImpl: typeof fetch,
    settings: ReturnType<typeof geminiVideoSettings>,
    input: VideoVisualAnalysisInput,
    clip: ClipWindow | null,
  ): Promise<{ content: string; usage: Record<string, number> }> {
    const endpoint = `${GEMINI_HOST}/v1beta/models/${encodeURIComponent(settings.model)}:generateContent`;
    const url = new URL(endpoint);
    if (url.origin !== GEMINI_HOST) throw new GeminiError("invalidGeminiHost", false);

    const videoPart = buildVideoPart({
      youtubeUrl: input.youtubeUrl,
      fps: input.fps,
      clip,
    });

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), settings.timeoutMs);
    try {
      const response = await fetchImpl(url.toString(), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "x-goog-api-key": settings.apiKey,
          "User-Agent": "genshin-builder/1.0 (build-guide-gemini-visual)",
        },
        body: JSON.stringify({
          system_instruction: {
            parts: [{ text: VISUAL_SYSTEM_PROMPT }],
          },
          contents: [
            {
              role: "user",
              parts: [
                videoPart,
                {
                  text: buildVisualUserPrompt({
                    videoId: input.videoId,
                    title: input.title,
                    targetCharacterIds: input.targetCharacterIds,
                    durationSeconds: input.durationSeconds,
                    requestedRanges: clip
                      ? [clip]
                      : input.requestedRanges,
                  }),
                },
              ],
            },
          ],
          // Gemini 3.6 Flash: do not send deprecated sampling params
          // (temperature / top_p / top_k / candidate_count / thinking_budget).
          generationConfig: {
            responseMimeType: "application/json",
          },
        }),
        signal: controller.signal,
        cache: "no-store",
      });
      if (!response.ok) {
        const retryable = [429, 500, 503].includes(response.status);
        throw new GeminiError(`http${response.status}`, retryable);
      }
      const raw = await response.text();
      if (Buffer.byteLength(raw, "utf8") > 4_000_000) {
        throw new GeminiError("responseTooLarge", false);
      }
      const envelope = envelopeSchema.parse(JSON.parse(raw) as unknown);
      const text =
        envelope.candidates[0]?.content?.parts
          ?.map((part) => part.text ?? "")
          .join("") ?? "";
      const usageMeta = envelope.usageMetadata ?? {};
      return {
        content: text,
        usage: Object.fromEntries(
          Object.entries(usageMeta).filter(
            (entry): entry is [string, number] => typeof entry[1] === "number",
          ),
        ),
      };
    } catch (error) {
      if (error instanceof GeminiError) throw error;
      if (error instanceof DOMException && error.name === "AbortError") {
        throw new GeminiError("timeout", true);
      }
      if (error instanceof z.ZodError || error instanceof SyntaxError) {
        throw new GeminiError("invalidEnvelope", false);
      }
      throw new GeminiError("networkError", true);
    } finally {
      clearTimeout(timeout);
    }
  }
}

/** Exported for unit tests — builds the Gemini Part for YouTube video input. */
export function buildVideoPart(input: {
  youtubeUrl: string;
  fps: number;
  clip: ClipWindow | null;
}): Record<string, unknown> {
  const videoMetadata: Record<string, unknown> = {
    fps: input.fps,
  };
  if (input.clip) {
    videoMetadata.start_offset = `${input.clip.startSeconds}s`;
    videoMetadata.end_offset = `${input.clip.endSeconds}s`;
  }
  return {
    file_data: {
      file_uri: input.youtubeUrl,
      mime_type: "video/*",
    },
    video_metadata: videoMetadata,
  };
}

function mergeVisualResults(
  videoId: string,
  results: VideoVisualAnalysisResult[],
): VideoVisualAnalysisResult {
  if (results.length === 1) return results[0]!;
  const evidences = results.flatMap((r) => r.evidences);
  const unresolved = results.flatMap((r) => r.unresolvedEntities);
  const characters = [
    ...new Set(results.flatMap((r) => r.detectedCharacterIds)),
  ];
  return videoVisualAnalysisResultSchema.parse({
    videoId,
    relevant: results.some((r) => r.relevant) || evidences.length > 0,
    detectedCharacterIds: characters,
    evidences,
    unresolvedEntities: unresolved.slice(0, 50),
    analysisSummary: results
      .map((r) => r.analysisSummary)
      .filter(Boolean)
      .join(" | ")
      .slice(0, 1000),
  });
}

function assertSafeYoutubeUrl(youtubeUrl: string, videoId: string): void {
  let parsed: URL;
  try {
    parsed = new URL(youtubeUrl);
  } catch {
    throw new GeminiError("invalidYoutubeUrl", false);
  }
  if (parsed.protocol !== "https:") throw new GeminiError("invalidYoutubeUrl", false);
  const host = parsed.hostname.toLowerCase();
  if (host !== "www.youtube.com" && host !== "youtube.com" && host !== "youtu.be") {
    throw new GeminiError("invalidYoutubeHost", false);
  }
  if (youtubeUrl !== `https://www.youtube.com/watch?v=${videoId}` && !youtubeUrl.includes(`v=${videoId}`)) {
    throw new GeminiError("youtubeUrlMismatch", false);
  }
}

function stripJsonFence(value: string): string {
  const trimmed = value.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced?.[1]?.trim() ?? trimmed;
}
