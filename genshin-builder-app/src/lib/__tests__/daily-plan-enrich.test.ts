import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  enrichDailyPlan,
  resetDailyPlanCacheForTest,
} from "@/lib/daily-plan/enrich-daily-plan";
import { validateAndFinalizeDailyPlan } from "@/lib/daily-plan/final-validator";
import type {
  DailyPlanEnrichRequest,
  DailyPlanAiResult,
} from "@/lib/daily-plan/types";
import {
  parseDailyPlanAiResponse,
  parseDailyPlanEnrichRequest,
} from "@/lib/daily-plan/validation";

const NOW = new Date("2026-08-02T03:00:00.000Z");

function request(
  overrides: Partial<DailyPlanEnrichRequest> = {},
): DailyPlanEnrichRequest {
  return {
    clientScope: "0123456789ab",
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
        currentLevel: 6,
        targetLevel: 9,
        estimatedResinCost: 40,
        estimatedMinutes: 20,
        availableToday: true,
        requiresResin: true,
        bookmarked: true,
        existingPriority: 95,
        reasonFacts: ["今日開放", "不足12個"],
      },
      {
        taskId: "goal_level",
        type: "characterLevel",
        title: "キャラクターをLv.90へ",
        characterIds: ["10000003"],
        materialIds: ["104003"],
        currentLevel: 80,
        targetLevel: 90,
        estimatedResinCost: 80,
        estimatedMinutes: 30,
        availableToday: true,
        requiresResin: true,
        bookmarked: false,
        existingPriority: 82,
        reasonFacts: ["目標との差10"],
      },
      {
        taskId: "goal_talent_locked",
        type: "talent",
        title: "天賦をLv.9へ",
        characterIds: ["10000004"],
        materialIds: ["104399"],
        currentLevel: 6,
        targetLevel: 9,
        estimatedResinCost: 20,
        estimatedMinutes: 20,
        availableToday: false,
        requiresResin: true,
        bookmarked: false,
        existingPriority: 90,
        reasonFacts: ["本日は対象素材の開放日ではない"],
      },
    ],
    ...overrides,
  };
}

function aiResult(
  overrides: Partial<DailyPlanAiResult> = {},
): DailyPlanAiResult {
  return {
    summary: "今日は曜日素材を優先すると効率的です",
    recommendations: [
      {
        taskId: "goal_level",
        priority: 1,
        category: "do_today",
        reason: "目標との差が大きいため",
        suggestedMinutes: 30,
      },
      {
        taskId: "wd_freedom",
        priority: 2,
        category: "do_today",
        reason: "今日開放されているため",
        suggestedMinutes: 20,
      },
    ],
    deferredTaskIds: ["goal_talent_locked"],
    warnings: [],
    ...overrides,
  };
}

describe("daily-plan strict validation", () => {
  it("accepts a bounded structured request", () => {
    const parsed = parseDailyPlanEnrichRequest(request());
    expect(parsed.candidates).toHaveLength(3);
    expect(parsed.date).toBe("2026-08-02");
  });

  it("rejects unknown fields and duplicate task ids", () => {
    expect(() =>
      parseDailyPlanEnrichRequest({ ...request(), unexpected: true }),
    ).toThrow();
    const duplicate = request();
    duplicate.candidates = [duplicate.candidates[0]!, duplicate.candidates[0]!];
    expect(() => parseDailyPlanEnrichRequest(duplicate)).toThrow();
  });

  it("strictly rejects extra AI fields", () => {
    expect(() =>
      parseDailyPlanAiResponse({ ...aiResult(), chainOfThought: "secret" }),
    ).toThrow();
  });
});

describe("deterministic final validation", () => {
  it("rejects unavailable tasks and enforces resin/time budgets", () => {
    const result = validateAndFinalizeDailyPlan(
      aiResult({
        recommendations: [
          {
            taskId: "goal_talent_locked",
            priority: 1,
            category: "do_today",
            reason: "モデル知識でおすすめ",
            suggestedMinutes: 20,
          },
          {
            taskId: "goal_level",
            priority: 2,
            category: "do_today",
            reason: "目標との差が大きいため",
            suggestedMinutes: 30,
          },
          {
            taskId: "wd_freedom",
            priority: 3,
            category: "do_today",
            reason: "今日開放されているため",
            suggestedMinutes: 20,
          },
        ],
      }),
      request({ currentResin: 40, availableMinutes: 30 }),
      "a".repeat(64),
      "deepseek-v4-flash",
      NOW,
    );
    expect(result.recommendations.map((item) => item.taskId)).toEqual([
      "wd_freedom",
    ]);
    expect(result.deferredTaskIds).toEqual(
      expect.arrayContaining(["goal_level", "goal_talent_locked"]),
    );
    expect(result.source).toBe("deepseek");
  });

  it("removes markup from AI reasons by falling back to structured facts", () => {
    const result = validateAndFinalizeDailyPlan(
      aiResult({
        recommendations: [
          {
            taskId: "wd_freedom",
            priority: 1,
            category: "do_today",
            reason: "[こちら](https://example.com)を参照",
            suggestedMinutes: 20,
          },
        ],
      }),
      request(),
      "b".repeat(64),
      "deepseek-v4-flash",
      NOW,
    );
    expect(result.recommendations[0]?.reason).toBe("今日開放");
  });

  it("keeps deterministic uncertainty warnings on successful AI output", () => {
    const result = validateAndFinalizeDailyPlan(
      aiResult(),
      request({ currentResin: null, availableMinutes: null }),
      "c".repeat(64),
      "deepseek-v4-flash",
      NOW,
    );
    expect(result.warnings).toEqual(
      expect.arrayContaining([
        "樹脂残量を取得できないため、樹脂予算は最終確認してください",
        "利用可能時間が未設定のため、所要時間は目安です",
      ]),
    );
  });
});

describe("enrichDailyPlan", () => {
  beforeEach(() => resetDailyPlanCacheForTest());

  it("uses deterministic fallback unless both feature flags are true", async () => {
    const evaluate = vi.fn();
    const result = await enrichDailyPlan(request(), {
      env: {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "false",
      },
      client: { evaluate } as never,
      now: NOW,
    });
    expect(result.source).toBe("deterministic_fallback");
    expect(evaluate).not.toHaveBeenCalled();
    expect(result.recommendations[0]?.taskId).toBe("wd_freedom");
  });

  it("uses the shared DeepSeek wrapper result and caches by input", async () => {
    const evaluate = vi.fn().mockResolvedValue({
      result: aiResult(),
      modelIdentifier: "deepseek-v4-flash",
      usage: { total_tokens: 123 },
      attempts: 1,
    });
    const options = {
      env: {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
        DEEPSEEK_API_KEY: "test-key",
        DEEPSEEK_MODEL: "deepseek-v4-flash",
      },
      client: { evaluate } as never,
      now: NOW,
    };

    const first = await enrichDailyPlan(request(), options);
    const second = await enrichDailyPlan(request(), options);
    expect(first.source).toBe("deepseek");
    expect(second).toEqual(first);
    expect(evaluate).toHaveBeenCalledOnce();
    expect(first.inputHash).toMatch(/^[a-f0-9]{64}$/);
  });

  it("force bypasses cache without changing the cache identity", async () => {
    const evaluate = vi.fn().mockResolvedValue({
      result: aiResult(),
      modelIdentifier: "deepseek-v4-flash",
      usage: {},
      attempts: 1,
    });
    const options = {
      env: {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
        DEEPSEEK_API_KEY: "test-key",
      },
      client: { evaluate } as never,
      now: NOW,
    };
    const first = await enrichDailyPlan(request(), options);
    const regenerated = await enrichDailyPlan(request({ force: true }), options);
    expect(evaluate).toHaveBeenCalledTimes(2);
    expect(regenerated.inputHash).toBe(first.inputHash);
  });

  it("fails closed to the deterministic plan on DeepSeek errors", async () => {
    const result = await enrichDailyPlan(request(), {
      env: {
        DEEPSEEK_ENABLED: "true",
        DEEPSEEK_DAILY_PLAN_ENABLED: "true",
        DEEPSEEK_API_KEY: "test-key",
      },
      client: { evaluate: vi.fn().mockRejectedValue(new Error("boom")) } as never,
      now: NOW,
    });
    expect(result.source).toBe("deterministic_fallback");
    expect(result.warnings).toContain(
      "AI提案を利用できなかったため、通常ルールで提案しました",
    );
  });
});
