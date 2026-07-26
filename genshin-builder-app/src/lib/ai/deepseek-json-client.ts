import "server-only";

import { z } from "zod";

const DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions";
export const DEEPSEEK_ALLOWED_MODELS = new Set([
  "deepseek-v4-flash",
  "deepseek-v4-pro",
]);

const responseEnvelopeSchema = z.object({
  choices: z
    .array(
      z.object({
        message: z.object({ content: z.string().nullable() }),
        finish_reason: z.string().nullable().optional(),
      }),
    )
    .min(1),
  usage: z
    .object({
      prompt_tokens: z.number().int().nonnegative().optional(),
      completion_tokens: z.number().int().nonnegative().optional(),
      total_tokens: z.number().int().nonnegative().optional(),
      prompt_cache_hit_tokens: z.number().int().nonnegative().optional(),
      prompt_cache_miss_tokens: z.number().int().nonnegative().optional(),
    })
    .optional(),
});

export interface DeepSeekJsonSettings {
  apiKey: string;
  model: string;
  timeoutMs: number;
  maxAttempts: number;
  maxTokens: number;
  userAgent: string;
  maxPromptBytes?: number;
  maxResponseBytes?: number;
}

export interface DeepSeekJsonClientOptions {
  fetchImpl?: typeof fetch;
  sleep?: (milliseconds: number) => Promise<void>;
  random?: () => number;
}

export interface DeepSeekJsonCompletion {
  content: string;
  finishReason?: string | null;
  usage: Record<string, number>;
  modelIdentifier: string;
  attempts: number;
}

/**
 * Fixed-host DeepSeek chat completions client (JSON mode, thinking disabled).
 * Callers supply system/user prompts and parse/validate the JSON payload.
 */
export class DeepSeekJsonClient {
  private readonly fetchImpl: typeof fetch;
  private readonly sleep: (milliseconds: number) => Promise<void>;
  private readonly random: () => number;

  constructor(options: DeepSeekJsonClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.sleep =
      options.sleep ??
      ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.random = options.random ?? Math.random;
  }

  async completeJson(input: {
    settings: DeepSeekJsonSettings;
    systemPrompt: string;
    userContent: string;
  }): Promise<DeepSeekJsonCompletion> {
    const maxPromptBytes = input.settings.maxPromptBytes ?? 131_072;
    if (Buffer.byteLength(input.userContent, "utf8") > maxPromptBytes) {
      throw new DeepSeekError("promptTooLarge", false);
    }

    let lastError = new DeepSeekError("requestFailed", true);
    for (let attempt = 1; attempt <= input.settings.maxAttempts; attempt++) {
      try {
        const response = await this.request(input.settings, input.systemPrompt, input.userContent);
        if (!response.content.trim()) throw new DeepSeekError("emptyResponse", true);
        if (response.finishReason === "length") {
          throw new DeepSeekError("responseTruncated", false);
        }
        return {
          content: response.content,
          finishReason: response.finishReason,
          usage: response.usage,
          modelIdentifier: input.settings.model,
          attempts: attempt,
        };
      } catch (error) {
        lastError =
          error instanceof DeepSeekError
            ? error
            : new DeepSeekError("requestFailed", true);
        if (!lastError.retryable || attempt === input.settings.maxAttempts) break;
        const delay = Math.min(4_000, 400 * 2 ** (attempt - 1));
        await this.sleep(delay + Math.floor(this.random() * 100));
      }
    }
    throw lastError;
  }

  private async request(
    settings: DeepSeekJsonSettings,
    systemPrompt: string,
    userContent: string,
  ): Promise<{
    content: string;
    finishReason?: string | null;
    usage: Record<string, number>;
  }> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), settings.timeoutMs);
    const maxResponseBytes = settings.maxResponseBytes ?? 2_097_152;
    try {
      const response = await this.fetchImpl(DEEPSEEK_ENDPOINT, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${settings.apiKey}`,
          "Content-Type": "application/json",
          Accept: "application/json",
          "User-Agent": settings.userAgent,
        },
        body: JSON.stringify({
          model: settings.model,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userContent },
          ],
          response_format: { type: "json_object" },
          thinking: { type: "disabled" },
          max_tokens: settings.maxTokens,
        }),
        signal: controller.signal,
        cache: "no-store",
      });
      if (!response.ok) {
        const retryable = [429, 500, 503].includes(response.status);
        throw new DeepSeekError(`http${response.status}`, retryable);
      }
      const raw = await response.text();
      if (Buffer.byteLength(raw, "utf8") > maxResponseBytes) {
        throw new DeepSeekError("responseTooLarge", false);
      }
      const envelope = responseEnvelopeSchema.parse(JSON.parse(raw) as unknown);
      const usage = envelope.usage ?? {};
      return {
        content: envelope.choices[0]?.message.content ?? "",
        finishReason: envelope.choices[0]?.finish_reason,
        usage: Object.fromEntries(
          Object.entries(usage).filter(
            (entry): entry is [string, number] => typeof entry[1] === "number",
          ),
        ),
      };
    } catch (error) {
      if (error instanceof DeepSeekError) throw error;
      if (error instanceof DOMException && error.name === "AbortError") {
        throw new DeepSeekError("timeout", true);
      }
      if (error instanceof z.ZodError || error instanceof SyntaxError) {
        throw new DeepSeekError("invalidEnvelope", false);
      }
      throw new DeepSeekError("networkError", true);
    } finally {
      clearTimeout(timeout);
    }
  }
}

export class DeepSeekError extends Error {
  constructor(
    public readonly code: string,
    public readonly retryable: boolean,
  ) {
    super(code);
    this.name = "DeepSeekError";
  }
}

export function clampEnvNumber(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  const value = Number(raw);
  return Number.isFinite(value) ? Math.min(max, Math.max(min, Math.round(value))) : fallback;
}

export function assertAllowedDeepSeekModel(model: string): void {
  if (!DEEPSEEK_ALLOWED_MODELS.has(model)) {
    throw new DeepSeekError("unsupportedModel", false);
  }
}
