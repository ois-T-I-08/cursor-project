import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { readControlMock } = vi.hoisted(() => ({
  readControlMock: vi.fn(),
}));

vi.mock("@/lib/build-guides/automation/automation-control", () => ({
  readYoutubeAutomationControl: readControlMock,
  assertAutomationMayProceed: (control: { emergencyStopped: boolean }) => {
    if (control.emergencyStopped) throw new Error("EMERGENCY_STOPPED");
  },
}));

import {
  assertGlobalAiEmergencyAllowsExternalCall,
  evaluateManualPublishGate,
} from "@/lib/ai/global-ai-emergency";
import {
  DeepSeekError,
  DeepSeekJsonClient,
} from "@/lib/ai/deepseek-json-client";
import {
  enrichDailyPlan,
  resetDailyPlanCacheForTest,
} from "@/lib/daily-plan/enrich-daily-plan";
import { DeepSeekDailyPlanClient } from "@/lib/daily-plan/deepseek-client";
import type { DailyPlanEnrichRequest } from "@/lib/daily-plan/types";
import { evaluateVisualAutoPublishGate } from "@/lib/build-guides/automation/safety-gates";
import { DeepSeekReplacementClient } from "@/lib/team-recommendations/replacements/deepseek-client";

const settings = {
  apiKey: "test-key",
  model: "deepseek-v4-flash",
  timeoutMs: 50,
  maxAttempts: 3,
  maxTokens: 256,
  userAgent: "genshin-builder-test",
};

function dailyRequest(): DailyPlanEnrichRequest {
  return {
    clientScope: "0123456789ab",
    proposalFingerprint: "f".repeat(64),
    date: "2026-08-02",
    timezone: "UTC+09:00",
    weekday: 7,
    currentResin: 100,
    maxResin: 200,
    availableMinutes: 60,
    candidates: [
      {
        taskId: "wd_freedom",
        type: "weekdayMaterial",
        title: "自由の導き",
        characterIds: ["10000002"],
        materialIds: ["104301"],
        estimatedResinCost: 40,
        estimatedMinutes: 20,
        availableToday: true,
        requiresResin: true,
        bookmarked: true,
        existingPriority: 95,
        reasonFacts: ["今日開放"],
      },
    ],
  };
}

describe("Audit 2A — Global AI Emergency & Manual Publish", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetDailyPlanCacheForTest();
    readControlMock.mockResolvedValue({
      emergencyStopped: false,
      reason: "",
      version: 1,
    });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("final DeepSeek gate blocks provider fetch when emergencyStopped", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 9,
    });
    const fetchImpl = vi.fn();
    const client = new DeepSeekJsonClient({
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
    ).rejects.toMatchObject({
      code: "EMERGENCY_STOPPED",
      retryable: false,
    });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("Case A: emergency ON + Daily-plan feature ON → provider fetch 0 + deterministic fallback", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 10,
    });
    const fetchImpl = vi.fn();
    const client = new DeepSeekDailyPlanClient({
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
    });
    await expect(
      client.evaluate(dailyRequest(), {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
        DEEPSEEK_API_KEY: "test-key",
        DEEPSEEK_MODEL: "deepseek-v4-flash",
      }),
    ).rejects.toMatchObject({ code: "EMERGENCY_STOPPED", retryable: false });
    expect(fetchImpl).not.toHaveBeenCalled();

    const result = await enrichDailyPlan(dailyRequest(), {
      env: {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
        DEEPSEEK_API_KEY: "test-key",
      },
      client,
      now: new Date("2026-08-02T03:00:00.000Z"),
    });
    expect(result.source).toBe("deterministic_fallback");
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("Team DeepSeek: emergency ON → evaluate blocked before fetch", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 15,
    });
    vi.stubEnv("DEEPSEEK_ENABLED", "true");
    vi.stubEnv("DEEPSEEK_API_KEY", "test-only-secret");
    vi.stubEnv("DEEPSEEK_MODEL", "deepseek-v4-flash");
    const fetchImpl = vi.fn();
    const client = new DeepSeekReplacementClient({
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
    });
    await expect(client.evaluate({} as never)).rejects.toMatchObject({
      code: "EMERGENCY_STOPPED",
      retryable: false,
    });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("Case C: Daily-plan feature OFF + manual/force → no DeepSeek evaluate", async () => {
    const evaluate = vi.fn();
    const result = await enrichDailyPlan(
      { ...dailyRequest(), force: true },
      {
        env: {
          DEEPSEEK_ENABLED: "true",
          DEEPSEEK_DAILY_PLAN_ENABLED: "false",
        },
        client: { evaluate } as never,
        now: new Date("2026-08-02T03:00:00.000Z"),
      },
    );
    expect(result.source).toBe("deterministic_fallback");
    expect(evaluate).not.toHaveBeenCalled();
  });

  it("Case D/retry: emergency ON → DeepSeek retries are 0 (non-retryable)", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 11,
    });
    const fetchImpl = vi.fn();
    const client = new DeepSeekJsonClient({
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
      random: () => 0,
    });
    await expect(
      client.completeJson({
        settings: { ...settings, maxAttempts: 3 },
        systemPrompt: "system",
        userContent: "{}",
      }),
    ).rejects.toMatchObject({ code: "EMERGENCY_STOPPED", retryable: false });
    expect(fetchImpl).toHaveBeenCalledTimes(0);
  });

  it("Case E: mid-batch re-check — second item sees emergency ON before fetch", async () => {
    let version = 1;
    readControlMock.mockImplementation(async () => ({
      emergencyStopped: version >= 2,
      reason: version >= 2 ? "flipped" : "",
      version,
    }));
    const fetchImpl = vi.fn(async () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"ok":true}' }, finish_reason: "stop" }],
          usage: {},
        }),
      ),
    );
    const client = new DeepSeekJsonClient({
      fetchImpl: fetchImpl as typeof fetch,
      sleep: async () => {},
      random: () => 0,
    });

    await client.completeJson({
      settings,
      systemPrompt: "system",
      userContent: "{}",
    });
    expect(fetchImpl).toHaveBeenCalledTimes(1);

    version = 2;
    await expect(
      client.completeJson({
        settings,
        systemPrompt: "system",
        userContent: "{}",
      }),
    ).rejects.toMatchObject({ code: "EMERGENCY_STOPPED" });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("manual publish: emergency ON without override → blocked", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 12,
    });
    await expect(evaluateManualPublishGate({})).resolves.toEqual({
      allowed: false,
      reason: "emergencyStoppedPublishBlocked",
    });
  });

  it("manual publish: emergency ON with break-glass reason → allowed + overrideUsed", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 13,
    });
    const gate = await evaluateManualPublishGate({
      overrideReason: "need hotfix publish for broken guide",
      overrideActor: "ops-oncall",
    });
    expect(gate).toMatchObject({
      allowed: true,
      overrideUsed: true,
      actor: "ops-oncall",
      controlVersion: 13,
    });
  });

  it("auto-publish gate: emergency ON → denied (no override path)", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "audit-2a",
      version: 14,
    });
    const gate = await evaluateVisualAutoPublishGate({
      BUILD_GUIDE_VISUAL_AUTO_PUBLISH: "true",
      YOUTUBE_AUTOMATION_ENABLED: "true",
      YOUTUBE_GUIDE_ENABLED: "true",
      YOUTUBE_AUTO_PUBLISH_ENABLED: "true",
    });
    expect(gate).toEqual({ allowed: false, reason: "EMERGENCY_STOPPED" });
  });

  it("assertGlobalAiEmergencyAllowsExternalCall fails closed on stopped", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: true,
      reason: "CONTROL_READ_FAILED",
      version: -1,
    });
    await expect(assertGlobalAiEmergencyAllowsExternalCall()).rejects.toThrow(
      "EMERGENCY_STOPPED",
    );
  });

  it("parent precedence: emergency OFF + feature OFF → enrich skips AI", async () => {
    readControlMock.mockResolvedValue({
      emergencyStopped: false,
      reason: "",
      version: 1,
    });
    const evaluate = vi.fn();
    const result = await enrichDailyPlan(dailyRequest(), {
      env: {
        DEEPSEEK_ENABLED: "false",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
      },
      client: { evaluate } as never,
      now: new Date("2026-08-02T03:00:00.000Z"),
    });
    expect(evaluate).not.toHaveBeenCalled();
    expect(result.source).toBe("deterministic_fallback");
  });
});
