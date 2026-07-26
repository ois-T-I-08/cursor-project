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
import { videoVisualAnalysisResultSchema } from "./visual-schemas";

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

    const fetchImpl = this.options.fetchImpl ?? fetch;
    const sleep =
      this.options.sleep ??
      ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    const random = this.options.random ?? Math.random;

    let lastError = new GeminiError("requestFailed", true);
    for (let attempt = 1; attempt <= settings.maxAttempts; attempt++) {
      try {
        const completion = await this.request(fetchImpl, settings, input);
        if (!completion.content.trim()) throw new GeminiError("emptyResponse", true);
        let decoded: unknown;
        try {
          decoded = JSON.parse(stripJsonFence(completion.content)) as unknown;
        } catch {
          throw new GeminiError("invalidJson", false);
        }
        const result = videoVisualAnalysisResultSchema.parse(decoded);
        return {
          result,
          rawContent: completion.content,
          modelIdentifier: settings.model,
          usage: completion.usage,
          attempts: attempt,
        };
      } catch (error) {
        lastError =
          error instanceof GeminiError
            ? error
            : error instanceof z.ZodError
              ? new GeminiError("invalidResult", false)
              : new GeminiError("requestFailed", true);
        if (!lastError.retryable || attempt === settings.maxAttempts) break;
        await sleep(Math.min(8_000, 500 * 2 ** (attempt - 1)) + Math.floor(random() * 100));
      }
    }
    throw lastError;
  }

  private async request(
    fetchImpl: typeof fetch,
    settings: ReturnType<typeof geminiVideoSettings>,
    input: VideoVisualAnalysisInput,
  ): Promise<{ content: string; usage: Record<string, number> }> {
    const endpoint = `${GEMINI_HOST}/v1beta/models/${encodeURIComponent(settings.model)}:generateContent`;
    const url = new URL(endpoint);
    if (url.origin !== GEMINI_HOST) throw new GeminiError("invalidGeminiHost", false);

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
                {
                  file_data: {
                    file_uri: input.youtubeUrl,
                  },
                },
                {
                  text: buildVisualUserPrompt({
                    videoId: input.videoId,
                    title: input.title,
                    targetCharacterIds: input.targetCharacterIds,
                    durationSeconds: input.durationSeconds,
                    requestedRanges: input.requestedRanges,
                  }),
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            temperature: 0.1,
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
  const expected = `https://www.youtube.com/watch?v=${videoId}`;
  if (youtubeUrl !== expected && !youtubeUrl.includes(`v=${videoId}`)) {
    throw new GeminiError("youtubeUrlMismatch", false);
  }
}

function stripJsonFence(value: string): string {
  const trimmed = value.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced?.[1]?.trim() ?? trimmed;
}
