import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import {
  acquirePipelineLease,
  releasePipelineLease,
  renewPipelineLease,
} from "@/lib/build-guides/automation/lease-store";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const channelId = "UCYTPIPELINEPHASE100001";
const videoId = "ytPhase1Vid";

describe.runIf(runDbTests)("YouTube automation Phase 1 PostgreSQL", () => {
  beforeAll(async () => {
    await cleanup();
    await prisma.guideChannel.create({
      data: {
        channelId,
        title: "Pipeline Phase 1",
        enabled: true,
        permissionStatus: "approved_for_processing",
      },
    });
    await prisma.guideVideo.create({
      data: {
        videoId,
        channelId,
        title: "【原神】Phase 1",
        privacyStatus: "public",
        metadataHash: "meta-phase-1",
        sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
      },
    });
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("enforces run and discovery idempotency with database UNIQUE constraints", async () => {
    const createRun = () =>
      prisma.guidePipelineRun.create({
        data: {
          pipelineRunId: "phase1-run",
          idempotencyKey: "phase1-run-key",
          trigger: "test",
          policyVersion: "v1",
          policyHash: "hash",
        },
      });
    const results = await Promise.allSettled([createRun(), createRun()]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);

    const run = await prisma.guidePipelineRun.findUniqueOrThrow({
      where: { pipelineRunId: "phase1-run" },
    });
    const createItem = () =>
      prisma.guidePipelineItem.create({
        data: {
          runId: run.id,
          videoId,
          discoveryKey: "phase1-discovery-key",
        },
      });
    const itemResults = await Promise.allSettled([createItem(), createItem()]);
    expect(itemResults.filter((result) => result.status === "fulfilled")).toHaveLength(1);
  });

  it("allows only one owner and reacquires only an expired lease", async () => {
    const now = new Date("2026-07-31T00:00:00.000Z");
    const [first, competing] = await Promise.all([
      acquirePipelineLease({
        lockKey: "phase1:item",
        leaseOwner: "worker-a",
        now,
        ttlMs: 60_000,
      }),
      acquirePipelineLease({
        lockKey: "phase1:item",
        leaseOwner: "worker-b",
        now,
        ttlMs: 60_000,
      }),
    ]);
    expect([first, competing].filter(Boolean)).toHaveLength(1);
    const held = first ?? competing;
    expect(held).not.toBeNull();

    const blocked = await acquirePipelineLease({
      lockKey: "phase1:item",
      leaseOwner: "worker-c",
      now: new Date(now.getTime() + 59_999),
      ttlMs: 60_000,
    });
    expect(blocked).toBeNull();

    const reacquired = await acquirePipelineLease({
      lockKey: "phase1:item",
      leaseOwner: "worker-c",
      now: new Date(now.getTime() + 60_000),
      ttlMs: 60_000,
    });
    expect(reacquired?.leaseOwner).toBe("worker-c");
    expect(reacquired?.leaseVersion).toBe(2);
  });

  it("renews and releases with owner plus leaseVersion compare-and-set", async () => {
    const now = new Date("2026-07-31T02:00:00.000Z");
    const lease = await acquirePipelineLease({
      lockKey: "phase1:renew",
      leaseOwner: "worker-a",
      now,
      ttlMs: 60_000,
    });
    expect(lease).not.toBeNull();
    const renewed = await renewPipelineLease({
      lease: lease!,
      now: new Date(now.getTime() + 1_000),
      ttlMs: 60_000,
    });
    expect(renewed?.leaseVersion).toBe(2);
    expect(await releasePipelineLease({ lease: lease! })).toBe(false);
    expect(await releasePipelineLease({ lease: renewed! })).toBe(true);
  });
});

async function cleanup(): Promise<void> {
  await prisma.guidePipelineLease.deleteMany({
    where: { lockKey: { startsWith: "phase1:" } },
  });
  await prisma.guidePipelineRun.deleteMany({
    where: { pipelineRunId: "phase1-run" },
  });
  await prisma.guideVideo.deleteMany({ where: { videoId } });
  await prisma.guideChannel.deleteMany({ where: { channelId } });
}
