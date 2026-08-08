import { describe, expect, it, vi } from "vitest";
import {
  runSequentialPendingGenshinBatch,
  shouldStopStockPendingBatch,
} from "../build-guides/pending-genshin-batch";

const selected = [
  { videoId: "vidAAAAAAA1", title: "t1", characterId: "c1" },
  { videoId: "vidBBBBBBB2", title: "t2", characterId: "c2" },
  { videoId: "vidCCCCCCC3", title: "t3", characterId: "c3" },
];

describe("shouldStopStockPendingBatch", () => {
  it("stops on 429 / emergency / cooldown", () => {
    expect(shouldStopStockPendingBatch("http429")).toBe(true);
    expect(shouldStopStockPendingBatch("emergencyStopped")).toBe(true);
    expect(shouldStopStockPendingBatch("geminiProviderCoolingDown")).toBe(true);
  });

  it("does not stop the whole batch on videoTooLargeForFullDiscovery", () => {
    // After long-form integration this should be rare; if it occurs, continue.
    expect(shouldStopStockPendingBatch("videoTooLargeForFullDiscovery")).toBe(
      false,
    );
  });
});

describe("runSequentialPendingGenshinBatch", () => {
  it("A: >80k production item passes allowLongform:true into analyze", async () => {
    const analyze = vi.fn(async () => ({
      status: "validated",
      evidenceCount: 1,
      recommendationIds: ["r1"],
    }));
    await runSequentialPendingGenshinBatch({
      selected: [selected[0]!],
      assertEmergencyAllowsWork: async () => undefined,
      analyze,
    });
    expect(analyze).toHaveBeenCalledWith(
      expect.objectContaining({
        videoId: "vidAAAAAAA1",
        allowLongform: true,
      }),
    );
  });

  it("B: short items also use allowLongform:true (pipeline decides short vs long)", async () => {
    const analyze = vi.fn(
      async (_input: {
        videoId: string;
        targetCharacterIds?: string[];
        allowLongform: true;
      }) => ({ status: "validated" }),
    );
    await runSequentialPendingGenshinBatch({
      selected: [selected[0]!],
      assertEmergencyAllowsWork: async () => undefined,
      analyze,
    });
    expect(analyze.mock.calls[0]?.[0]?.allowLongform).toBe(true);
  });

  it("C: long-form success continues to next item", async () => {
    const order: string[] = [];
    const analyze = vi.fn(async (input: { videoId: string }) => {
      order.push(input.videoId);
      return { status: "validated", recommendationIds: [`r-${input.videoId}`] };
    });
    const results = await runSequentialPendingGenshinBatch({
      selected,
      assertEmergencyAllowsWork: async () => undefined,
      analyze,
    });
    expect(order).toEqual(["vidAAAAAAA1", "vidBBBBBBB2", "vidCCCCCCC3"]);
    expect(results.filter((r) => r.ok)).toHaveLength(3);
  });

  it("D: 429 aborts remainder of batch", async () => {
    const analyze = vi.fn(async (input: { videoId: string }) => {
      if (input.videoId === "vidAAAAAAA1") {
        const err = new Error("http429") as Error & { code: string };
        err.code = "http429";
        throw err;
      }
      return { status: "validated" };
    });
    const results = await runSequentialPendingGenshinBatch({
      selected,
      assertEmergencyAllowsWork: async () => undefined,
      analyze,
    });
    expect(analyze).toHaveBeenCalledTimes(1);
    expect(results).toHaveLength(1);
    expect(results[0]?.error).toBe("http429");
  });

  it("E: Emergency ON starts no new items after gate trip", async () => {
    let calls = 0;
    const results = await runSequentialPendingGenshinBatch({
      selected,
      assertEmergencyAllowsWork: async () => {
        calls += 1;
        if (calls === 1) return;
        throw new Error("EMERGENCY_STOPPED");
      },
      analyze: async () => ({ status: "validated" }),
    });
    expect(results.filter((r) => r.ok)).toHaveLength(1);
    expect(results.some((r) => r.error === "emergencyStopped")).toBe(true);
    expect(results.length).toBe(2);
  });
});
