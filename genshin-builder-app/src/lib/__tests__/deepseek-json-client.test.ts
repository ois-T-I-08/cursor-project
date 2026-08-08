import { describe, expect, it, vi } from "vitest";

import {
  DeepSeekJsonClient,
  type DeepSeekJsonSettings,
} from "@/lib/ai/deepseek-json-client";

const settings: DeepSeekJsonSettings = {
  apiKey: "test-key",
  model: "deepseek-v4-flash",
  timeoutMs: 50,
  maxAttempts: 2,
  maxTokens: 256,
  userAgent: "genshin-builder-test",
};

function envelope(content: string): string {
  return JSON.stringify({
    choices: [
      {
        message: { content },
        finish_reason: "stop",
      },
    ],
    usage: { total_tokens: 12 },
  });
}

describe("DeepSeekJsonClient", () => {
  it("uses JSON mode, disables thinking, and returns bounded metadata", async () => {
    let sentBody: Record<string, unknown> | undefined;
    const fetchImpl = vi.fn(async (_url: unknown, init?: RequestInit) => {
      sentBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(envelope('{"ok":true}'), { status: 200 });
    });
    const client = new DeepSeekJsonClient({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
      random: () => 0,
    });

    const result = await client.completeJson({
      settings,
      systemPrompt: "system",
      userContent: '{"candidate":"safe"}',
    });

    expect(result.content).toBe('{"ok":true}');
    expect(result.usage.total_tokens).toBe(12);
    expect(sentBody?.response_format).toEqual({ type: "json_object" });
    expect(sentBody?.thinking).toEqual({ type: "disabled" });
  });

  it("rejects malformed and oversized provider responses without retry", async () => {
    const malformedFetch = vi.fn(async () => new Response("not-json"));
    const malformed = new DeepSeekJsonClient({
      skipEmergencyGate: true,
      fetchImpl: malformedFetch as typeof fetch,
      sleep: async () => {},
    });
    await expect(
      malformed.completeJson({
        settings,
        systemPrompt: "system",
        userContent: "{}",
      }),
    ).rejects.toMatchObject({ code: "invalidEnvelope", retryable: false });
    expect(malformedFetch).toHaveBeenCalledOnce();

    const oversized = new DeepSeekJsonClient({
      skipEmergencyGate: true,
      fetchImpl: (async () =>
        new Response(envelope('{"value":"too large"}'))) as typeof fetch,
      sleep: async () => {},
    });
    await expect(
      oversized.completeJson({
        settings: { ...settings, maxResponseBytes: 16 },
        systemPrompt: "system",
        userContent: "{}",
      }),
    ).rejects.toMatchObject({ code: "responseTooLarge", retryable: false });
  });

  it("retries empty, 429, and 5xx responses only up to maxAttempts", async () => {
    for (const testCase of [
      {
        name: "empty",
        response: () => new Response(envelope(""), { status: 200 }),
        code: "emptyResponse",
      },
      {
        name: "429",
        response: () => new Response("rate limited", { status: 429 }),
        code: "http429",
      },
      {
        name: "500",
        response: () => new Response("failed", { status: 500 }),
        code: "http500",
      },
    ]) {
      const fetchImpl = vi.fn(async () => testCase.response());
      const client = new DeepSeekJsonClient({
        skipEmergencyGate: true,
        fetchImpl: fetchImpl as typeof fetch,
        sleep: async () => {},
        random: () => 0,
      });
      await expect(
        client.completeJson({
          settings,
          systemPrompt: "system",
          userContent: "{}",
        }),
        testCase.name,
      ).rejects.toMatchObject({ code: testCase.code, retryable: true });
      expect(fetchImpl, testCase.name).toHaveBeenCalledTimes(2);
    }
  });

  it("classifies timeout without exposing the aborted error", async () => {
    const fetchImpl = vi.fn(
      async (_url: unknown, init?: RequestInit): Promise<Response> =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            reject(new DOMException("aborted", "AbortError"));
          });
        }),
    );
    const client = new DeepSeekJsonClient({
      skipEmergencyGate: true,
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
    });

    await expect(
      client.completeJson({
        settings: { ...settings, timeoutMs: 5, maxAttempts: 1 },
        systemPrompt: "system",
        userContent: "{}",
      }),
    ).rejects.toMatchObject({ code: "timeout", retryable: true });
  });
});
