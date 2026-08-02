import { describe, expect, it, vi } from "vitest";

import { enrichDailyPlan } from "@/lib/daily-plan/enrich-daily-plan";
import { parseDailyPlanEnrichRequest } from "@/lib/daily-plan/validation";

describe("parseDailyPlanEnrichRequest", () => {
  it("accepts a minimal valid payload", () => {
    const parsed = parseDailyPlanEnrichRequest({
      weekday: 2,
      currentResin: 120,
      maxResin: 200,
      items: [
        {
          id: "wd_a",
          type: "weekdayMaterial",
          title: "天光",
          priority: 90,
          reasons: ["今日開放"],
          characterIds: ["10000002"],
          materialIds: ["104301"],
        },
      ],
    });
    expect(parsed.items).toHaveLength(1);
    expect(parsed.weekday).toBe(2);
  });

  it("rejects unknown item types", () => {
    expect(() =>
      parseDailyPlanEnrichRequest({
        weekday: 1,
        items: [
          {
            id: "x",
            type: "unknown",
            title: "x",
            priority: 1,
            reasons: [],
            characterIds: [],
            materialIds: [],
          },
        ],
      }),
    ).toThrow();
  });
});

describe("enrichDailyPlan", () => {
  it("pass-through when DeepSeek is disabled", async () => {
    const result = await enrichDailyPlan(
      {
        weekday: 3,
        items: [
          {
            id: "a",
            type: "weekdayMaterial",
            title: "A",
            priority: 90,
            reasons: ["r"],
            characterIds: [],
            materialIds: [],
          },
          {
            id: "b",
            type: "growthGoal",
            title: "B",
            priority: 50,
            reasons: ["r"],
            characterIds: [],
            materialIds: [],
          },
        ],
      },
      { env: { DEEPSEEK_DAILY_PLAN_ENABLED: "false" } },
    );
    expect(result.enriched).toBe(false);
    expect(result.orderedItemIds).toEqual(["a", "b"]);
  });

  it("allowlists ids and appends missing ones", async () => {
    const completeJson = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        orderedItemIds: ["b", "invented", "a", "a"],
        reasonsByItemId: {
          b: ["樹脂に余裕があるので週ボスを優先"],
          invented: ["無視される"],
        },
      }),
      modelIdentifier: "deepseek-v4-flash",
      usage: {},
      attempts: 1,
    });

    const result = await enrichDailyPlan(
      {
        weekday: 1,
        currentResin: 160,
        maxResin: 200,
        items: [
          {
            id: "a",
            type: "weekdayMaterial",
            title: "A",
            priority: 90,
            reasons: ["local"],
            characterIds: [],
            materialIds: [],
          },
          {
            id: "b",
            type: "weeklyBoss",
            title: "B",
            priority: 85,
            reasons: ["local"],
            characterIds: [],
            materialIds: [],
          },
        ],
      },
      {
        env: {
          DEEPSEEK_DAILY_PLAN_ENABLED: "true",
          DEEPSEEK_DAILY_PLAN_API_KEY: "test-key",
          DEEPSEEK_DAILY_PLAN_MODEL: "deepseek-v4-flash",
        },
        client: { completeJson } as never,
      },
    );

    expect(result.enriched).toBe(true);
    expect(result.orderedItemIds).toEqual(["b", "a"]);
    expect(result.reasonsByItemId.b?.[0]).toContain("週ボス");
    expect(result.reasonsByItemId.invented).toBeUndefined();
    expect(completeJson).toHaveBeenCalledOnce();
  });

  it("fail-closed to pass-through on DeepSeek errors", async () => {
    const result = await enrichDailyPlan(
      {
        weekday: 1,
        items: [
          {
            id: "a",
            type: "growthGoal",
            title: "A",
            priority: 50,
            reasons: [],
            characterIds: [],
            materialIds: [],
          },
        ],
      },
      {
        env: {
          DEEPSEEK_DAILY_PLAN_ENABLED: "true",
          DEEPSEEK_DAILY_PLAN_API_KEY: "test-key",
        },
        client: {
          completeJson: vi.fn().mockRejectedValue(new Error("boom")),
        } as never,
      },
    );
    expect(result.enriched).toBe(false);
    expect(result.orderedItemIds).toEqual(["a"]);
  });
});
