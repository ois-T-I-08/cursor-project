import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { parseDailyPlanProposal } from "@/lib/daily-plan/validation";

const FIXTURE_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../../shared/domain-golden/daily-plan-proposal-v1.json",
);

function fixture(): Record<string, unknown> {
  return JSON.parse(readFileSync(FIXTURE_PATH, "utf8")) as Record<
    string,
    unknown
  >;
}

describe("daily-plan cross-platform contract", () => {
  it("parses the shared schema v1 fixture", () => {
    const parsed = parseDailyPlanProposal(fixture());
    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.recommendations.map((item) => item.taskId)).toEqual([
      "wd_freedom",
      "goal_level",
    ]);
    expect(parsed.proposalFingerprint).toBe("f".repeat(64));
  });

  it("fails closed on a schema version mismatch", () => {
    expect(() =>
      parseDailyPlanProposal({ ...fixture(), schemaVersion: 2 }),
    ).toThrow();
  });

  it("rejects unknown fields", () => {
    expect(() => parseDailyPlanProposal({ ...fixture(), unexpected: true })).toThrow();
  });

  it("rejects an invalid task ID", () => {
    const value = fixture();
    const recommendations = structuredClone(value.recommendations) as Array<Record<string, unknown>>;
    recommendations[0] = { ...recommendations[0], taskId: "invalid task id" };
    expect(() => parseDailyPlanProposal({ ...value, recommendations })).toThrow();
  });

  it("rejects an invalid proposal fingerprint", () => {
    expect(() =>
      parseDailyPlanProposal({ ...fixture(), proposalFingerprint: "not-a-sha256" }),
    ).toThrow();
  });

  it("rejects an unknown enum value", () => {
    expect(() => parseDailyPlanProposal({ ...fixture(), source: "unknown" })).toThrow();
  });

  it("rejects a missing required field", () => {
    const value = fixture();
    delete value.generatedAt;
    expect(() => parseDailyPlanProposal(value)).toThrow();
  });
});
