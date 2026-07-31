import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import {
  claimProviderCircuitPermission,
  recordProviderFailure,
  recordProviderSuccess,
} from "@/lib/build-guides/automation/circuit-breaker";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const providerId = "phase2-circuit-provider";

describe.runIf(runDbTests)("YouTube automation Phase 2 PostgreSQL", () => {
  beforeAll(cleanup);
  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("opens persistently, grants one half-open probe, and closes on success", async () => {
    const now = new Date("2026-07-31T00:00:00.000Z");
    for (let count = 0; count < 3; count++) {
      await recordProviderFailure({
        providerId,
        safeErrorCode: "UPSTREAM_5XX",
        opensCircuit: true,
        now: new Date(now.getTime() + count),
        threshold: 3,
        openSeconds: 60,
      });
    }
    const blocked = await claimProviderCircuitPermission({
      providerId,
      now: new Date(now.getTime() + 59_999),
    });
    expect(blocked).toMatchObject({ allowed: false, state: "open" });

    const probeTime = new Date(now.getTime() + 60_002);
    const permissions = await Promise.all([
      claimProviderCircuitPermission({ providerId, now: probeTime }),
      claimProviderCircuitPermission({ providerId, now: probeTime }),
    ]);
    expect(permissions.filter(({ allowed, probe }) => allowed && probe)).toHaveLength(1);
    expect(permissions.filter(({ allowed }) => !allowed)).toHaveLength(1);

    await recordProviderSuccess({ providerId, now: probeTime });
    await expect(
      claimProviderCircuitPermission({
        providerId,
        now: new Date(probeTime.getTime() + 1),
      }),
    ).resolves.toMatchObject({ allowed: true, probe: false, state: "closed" });
  });

  it("reopens immediately when a half-open probe fails", async () => {
    const now = new Date("2026-07-31T02:00:00.000Z");
    await recordProviderFailure({
      providerId,
      safeErrorCode: "RATE_LIMITED",
      opensCircuit: true,
      now,
      threshold: 1,
      openSeconds: 1,
    });
    const probeAt = new Date(now.getTime() + 1_001);
    await expect(
      claimProviderCircuitPermission({ providerId, now: probeAt }),
    ).resolves.toMatchObject({ allowed: true, state: "half_open" });
    await recordProviderFailure({
      providerId,
      safeErrorCode: "TIMEOUT",
      opensCircuit: true,
      now: probeAt,
      threshold: 3,
      openSeconds: 60,
    });
    await expect(
      claimProviderCircuitPermission({
        providerId,
        now: new Date(probeAt.getTime() + 1),
      }),
    ).resolves.toMatchObject({ allowed: false, state: "open" });
  });
});

async function cleanup(): Promise<void> {
  await prisma.guideProviderCircuit.deleteMany({ where: { providerId } });
}
