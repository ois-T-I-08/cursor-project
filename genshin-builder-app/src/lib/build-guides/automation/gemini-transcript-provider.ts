import "server-only";

import { z } from "zod";
import {
  TRANSCRIPT_ANALYSIS_JSON_SCHEMA,
  TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
} from "./analysis-schema";
import {
  classifyProviderHttpStatus,
  SafeProviderError,
  toSafeProviderError,
} from "./provider-error";
import type {
  TranscriptAnalysisCompletion,
  TranscriptAnalysisInput,
  TranscriptAnalysisProvider,
} from "./transcript-analysis-provider";

const GEMINI_ORIGIN = "https://generativelanguage.googleapis.com";
const PROVIDER_ID = "gemini-transcript-strict-v1";
const MAX_RESPONSE_BYTES = 2_097_152;

const envelopeSchema = z
  .object({
    candidates: z
      .array(
        z
          .object({
            content: z
              .object({
                parts: z.array(z.object({ text: z.string().optional() })).optional(),
              })
              .optional(),
          })
          .strict(),
      )
      .min(1),
    usageMetadata: z.record(z.string(), z.number()).optional(),
  })
  .passthrough();

export class GeminiTranscriptAnalysisProvider
  implements TranscriptAnalysisProvider
{
  readonly providerId = PROVIDER_ID;
  readonly supportsStrictSchema = true as const;
  private readonly fetchImpl: typeof fetch;
  private readonly apiKey: string | undefined;
  private readonly model: string;
  private readonly timeoutMs: number;

  constructor(
    options: {
      fetchImpl?: typeof fetch;
      apiKey?: string;
      model?: string;
      timeoutMs?: number;
    } = {},
  ) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.apiKey =
      options.apiKey?.trim() || process.env.GEMINI_API_KEY?.trim() || undefined;
    this.model =
      options.model?.trim() ||
      process.env.YOUTUBE_GUIDE_TRANSCRIPT_GEMINI_MODEL?.trim() ||
      "gemini-2.5-flash";
    this.timeoutMs = Math.min(120_000, Math.max(5_000, options.timeoutMs ?? 30_000));
  }

  async analyze(
    input: TranscriptAnalysisInput,
  ): Promise<TranscriptAnalysisCompletion> {
    if (!this.apiKey) {
      throw new SafeProviderError(this.providerId, "AUTH_NOT_CONFIGURED", false);
    }
    if (!/^[A-Za-z0-9._-]{1,100}$/.test(this.model)) {
      throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
    }
    const url = new URL(
      `/v1beta/models/${encodeURIComponent(this.model)}:generateContent`,
      GEMINI_ORIGIN,
    );
    if (url.origin !== GEMINI_ORIGIN) {
      throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(url.toString(), {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "x-goog-api-key": this.apiKey,
          "User-Agent": "genshin-builder/1.0 (transcript-analysis)",
        },
        cache: "no-store",
        signal: controller.signal,
        body: JSON.stringify({
          system_instruction: {
            parts: [
              {
                text:
                  "Extract only claims directly supported by the supplied transcript segments. " +
                  "Use only the expected character and allowed entity identifiers. " +
                  "Every claim must cite exact segment ids and an exact text excerpt.",
              },
            ],
          },
          contents: [
            {
              role: "user",
              parts: [
                {
                  text: JSON.stringify({
                    schemaVersion: TRANSCRIPT_ANALYSIS_SCHEMA_VERSION,
                    videoId: input.videoId,
                    expectedCharacterId: input.characterId,
                    language: input.language,
                    allowedEntityIds: input.allowedEntityIds,
                    chunks: input.chunks,
                  }),
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            responseJsonSchema: TRANSCRIPT_ANALYSIS_JSON_SCHEMA,
          },
        }),
      });
      if (!response.ok) {
        throw classifyProviderHttpStatus(this.providerId, response.status);
      }
      const raw = await response.text();
      if (Buffer.byteLength(raw, "utf8") > MAX_RESPONSE_BYTES) {
        throw new SafeProviderError(
          this.providerId,
          "RESPONSE_TOO_LARGE",
          false,
        );
      }
      let decoded: unknown;
      try {
        decoded = JSON.parse(raw) as unknown;
      } catch {
        throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
      }
      const envelope = envelopeSchema.safeParse(decoded);
      if (!envelope.success) {
        throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
      }
      const content =
        envelope.data.candidates[0]?.content?.parts
          ?.map((part) => part.text ?? "")
          .join("") ?? "";
      let value: unknown;
      try {
        value = JSON.parse(content) as unknown;
      } catch {
        throw new SafeProviderError(this.providerId, "INVALID_RESPONSE", false);
      }
      return {
        value,
        modelIdentifier: this.model,
        attempts: 1,
        usage: envelope.data.usageMetadata ?? {},
      };
    } catch (error) {
      throw toSafeProviderError(this.providerId, error);
    } finally {
      clearTimeout(timeout);
    }
  }
}
