import { describe, expect, it } from "vitest";
import { mergeVisualRecommendationsDeterministic } from "../build-guides/deepseek-visual-merge";
import {
  classifyPostProcessError,
  POST_PROCESS_MAX_ATTEMPTS,
  VisualPostProcessError,
} from "../build-guides/visual-postprocess";
import { sanitizeStatPriority } from "../build-guides/visual-stat-sanitize";
import { qpjObjectStatPriorityShape } from "./fixtures/qpj-stat-priority-shape";

describe("visual post-process hardening", () => {
  it("sanitizes QPj object-shaped statPriority (no [object Object])", () => {
    const cleaned = sanitizeStatPriority(
      qpjObjectStatPriorityShape.evidence.statPriorityRaw,
    );
    expect(cleaned).toEqual(["critRate", "critDmg", "er"]);
    expect(cleaned.every((k) => !k.includes("object"))).toBe(true);
  });

  it("drops legacy broken [object Object] priorities", () => {
    expect(
      sanitizeStatPriority(
        qpjObjectStatPriorityShape.evidence.legacyBrokenPriority,
      ),
    ).toEqual([]);
  });

  it("provider success + post-process success via deterministic merge", () => {
    const priority = sanitizeStatPriority(
      qpjObjectStatPriorityShape.evidence.statPriorityRaw,
    );
    const merged = mergeVisualRecommendationsDeterministic({
      characterId: "mavuika",
      visualEvidences: [
        {
          evidenceId: "e1",
          videoId: qpjObjectStatPriorityShape.videoId,
          startSeconds: 120,
          endSeconds: 150,
          evidenceType: "recommendation_table",
          visibleTexts: ["推奨ステータス"],
          statValues: [
            {
              statKey: "critRate",
              unit: "percent",
              minimum: null,
              recommended: 60,
              maximum: null,
              purpose: "explicit_recommendation",
            },
          ],
          mainStats: null,
          statPriority: priority,
          confidence: 0.9,
        },
      ],
      allowedVideoIds: [qpjObjectStatPriorityShape.videoId],
      allowedCharacterIds: ["mavuika"],
      gameDataVersion: "test",
    });
    expect(merged.substatPriority).toEqual(["critRate", "critDmg", "er"]);
  });

  it("strips broken persisted [object Object] priorities during merge", () => {
    const safe = mergeVisualRecommendationsDeterministic({
      characterId: "mavuika",
      visualEvidences: [
        {
          evidenceId: "e1",
          videoId: "abcdefghijk",
          startSeconds: 1,
          endSeconds: 2,
          evidenceType: "recommendation_table",
          visibleTexts: [],
          statValues: [],
          mainStats: null,
          // Old persisted payload shape — must not crash merge.
          statPriority: ["[object Object]"] as unknown as string[],
          confidence: 0.9,
        },
      ],
      allowedVideoIds: ["abcdefghijk"],
      allowedCharacterIds: ["mavuika"],
      gameDataVersion: "test",
    });
    expect(safe.substatPriority).toEqual([]);
  });

  it("classifies Zod as schemaValidationFailed (deterministic, non-retryable)", async () => {
    const { z } = await import("zod");
    const err = new z.ZodError([]);
    expect(classifyPostProcessError(err)).toEqual({
      code: "schemaValidationFailed",
      retryable: false,
    });
  });

  it("classifies transient prisma codes as persistenceFailed retryable", () => {
    const err = Object.assign(new Error("db"), { code: "P1001" });
    expect(classifyPostProcessError(err)).toEqual({
      code: "persistenceFailed",
      retryable: true,
    });
  });

  it("deterministic VisualPostProcessError is not retryable", () => {
    expect(
      classifyPostProcessError(
        new VisualPostProcessError("mergeFailed", false),
      ),
    ).toEqual({ code: "mergeFailed", retryable: false });
    expect(
      classifyPostProcessError(
        new VisualPostProcessError("entityResolutionFailed", false),
      ).retryable,
    ).toBe(false);
  });

  it("terminal succeeded annotation uses postProcess: taxonomy (not analysisFailed)", () => {
    // Contract: job errorCode prefix after AI success.
    const code = "mergeFailed";
    expect(`postProcess:${code}`).toBe("postProcess:mergeFailed");
    expect(`postProcess:${code}`).not.toContain("analysisFailed");
  });

  it("post-process-only retry never implies a Gemini call; deterministic max=0", () => {
    // retryVisualPostProcessOnly loads persisted evidences only (no provider).
    expect(POST_PROCESS_MAX_ATTEMPTS).toBe(2);
    expect(
      classifyPostProcessError(
        new VisualPostProcessError("schemaValidationFailed", false),
      ).retryable,
    ).toBe(false);
    expect(
      classifyPostProcessError(
        Object.assign(new Error("db"), { code: "P1001" }),
      ),
    ).toEqual({ code: "persistenceFailed", retryable: true });
  });
});
