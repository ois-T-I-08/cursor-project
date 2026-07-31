import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import {
  claimProviderCircuitPermission,
  recordProviderFailure,
  recordProviderSuccess,
  type CircuitPermit,
} from "@/lib/build-guides/automation/circuit-breaker";

const runDbTests =
  process.env.RUN_YOUTUBE_AUTOMATION_DB_TEST === "true" ||
  process.env.RUN_BUILD_GUIDE_DB_TEST === "true";
const providerPrefix = "phase2-circuit-provider";

describe.runIf(runDbTests)("YouTube automation Phase 2 PostgreSQL", () => {
  beforeEach(cleanup);
  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it("opens persistently, grants one fenced half-open probe, and closes on success", async () => {
    const providerId = `${providerPrefix}-success`;
    const now = new Date("2026-07-31T00:00:00.000Z");
    await openCircuit(providerId, now, 3, 60);

    const blocked = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "blocked-worker",
      now: new Date(now.getTime() + 59_999),
    });
    expect(blocked).toMatchObject({ allowed: false, state: "open" });
    if (blocked.allowed) throw new Error("expectedOpenCircuit");
    expect(blocked.retryAt.getTime()).toBeGreaterThan(
      new Date(now.getTime() + 59_999).getTime(),
    );

    const probeTime = new Date(now.getTime() + 60_002);
    const permissions = await Promise.all([
      claimProviderCircuitPermission({
        providerId,
        probeOwner: "probe-worker-a",
        now: probeTime,
      }),
      claimProviderCircuitPermission({
        providerId,
        probeOwner: "probe-worker-b",
        now: probeTime,
      }),
    ]);
    const winner = permissions.find(({ allowed, probe }) => allowed && probe);
    expect(winner?.permit).toMatchObject({
      state: "half_open",
      probeToken: 1,
    });
    expect(permissions.filter(({ allowed }) => !allowed)).toHaveLength(1);

    expect(
      await recordProviderSuccess({
        permit: requirePermit(winner),
        now: new Date(probeTime.getTime() + 1),
      }),
    ).toBe("recorded");
    await expect(
      claimProviderCircuitPermission({
        providerId,
        probeOwner: "closed-worker",
        now: new Date(probeTime.getTime() + 2),
      }),
    ).resolves.toMatchObject({ allowed: true, probe: false, state: "closed" });
  });

  it("reopens immediately with a future retry when a half-open probe fails", async () => {
    const providerId = `${providerPrefix}-reopen`;
    const now = new Date("2026-07-31T02:00:00.000Z");
    await openCircuit(providerId, now, 1, 1);
    const probeAt = new Date(now.getTime() + 1_001);
    const probe = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "probe-worker",
      now: probeAt,
    });
    expect(probe).toMatchObject({ allowed: true, state: "half_open" });
    expect(
      await recordProviderFailure({
        permit: requirePermit(probe),
        safeErrorCode: "TIMEOUT",
        opensCircuit: true,
        now: new Date(probeAt.getTime() + 1),
        threshold: 3,
        openSeconds: 60,
      }),
    ).toBe("recorded");
    const blocked = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "blocked-worker",
      now: new Date(probeAt.getTime() + 2),
    });
    expect(blocked).toMatchObject({ allowed: false, state: "open" });
    if (blocked.allowed) throw new Error("expectedOpenCircuit");
    expect(blocked.retryAt.getTime()).toBeGreaterThan(
      new Date(probeAt.getTime() + 2).getTime(),
    );
  });

  it("closes a half-open probe on a non-circuit failure without counting it", async () => {
    const providerId = `${providerPrefix}-non-circuit`;
    const now = new Date("2026-07-31T03:00:00.000Z");
    await openCircuit(providerId, now, 1, 1);
    const probeAt = new Date(now.getTime() + 1_001);
    const probe = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "probe-worker",
      now: probeAt,
    });
    expect(
      await recordProviderFailure({
        permit: requirePermit(probe),
        safeErrorCode: "TRANSCRIPT_NOT_FOUND",
        opensCircuit: false,
        now: new Date(probeAt.getTime() + 1),
      }),
    ).toBe("recorded");

    await expect(
      prisma.guideProviderCircuit.findUniqueOrThrow({ where: { providerId } }),
    ).resolves.toMatchObject({
      state: "closed",
      failureCount: 0,
      probeOwner: "",
      probeAcquiredAt: null,
      probeExpiresAt: null,
    });
  });

  it("reclaims an abandoned probe after expiry and rejects the stale owner result", async () => {
    const providerId = `${providerPrefix}-reclaim`;
    const now = new Date("2026-07-31T04:00:00.000Z");
    await openCircuit(providerId, now, 1, 1);
    const firstProbeAt = new Date(now.getTime() + 1_001);
    const first = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "crashed-worker",
      probeTtlMs: 1_000,
      now: firstProbeAt,
    });
    const active = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "waiting-worker",
      probeTtlMs: 1_000,
      now: new Date(firstProbeAt.getTime() + 999),
    });
    expect(active.allowed).toBe(false);
    if (active.allowed) throw new Error("expectedActiveProbe");
    expect(active.retryAt.getTime()).toBe(firstProbeAt.getTime() + 1_000);

    const reclaimAt = new Date(firstProbeAt.getTime() + 1_001);
    const reclaimed = await Promise.all([
      claimProviderCircuitPermission({
        providerId,
        probeOwner: "reclaimer-a",
        probeTtlMs: 1_000,
        now: reclaimAt,
      }),
      claimProviderCircuitPermission({
        providerId,
        probeOwner: "reclaimer-b",
        probeTtlMs: 1_000,
        now: reclaimAt,
      }),
    ]);
    const reclaimedWinner = reclaimed.find(({ allowed }) => allowed);
    expect(reclaimed.filter(({ allowed }) => allowed)).toHaveLength(1);
    expect(requirePermit(reclaimedWinner).probeToken).toBeGreaterThan(
      requirePermit(first).probeToken,
    );

    const resultAt = new Date(reclaimAt.getTime() + 1);
    await expect(
      recordProviderSuccess({
        permit: requirePermit(first),
        now: resultAt,
      }),
    ).resolves.toBe("stale");
    await expect(
      recordProviderSuccess({
        permit: requirePermit(reclaimedWinner),
        now: resultAt,
      }),
    ).resolves.toBe("recorded");
  });

  it("rejects a late closed result after another request opens the circuit", async () => {
    const providerId = `${providerPrefix}-closed-stale`;
    const now = new Date("2026-07-31T05:00:00.000Z");
    const first = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "closed-worker-a",
      now,
    });
    const second = await claimProviderCircuitPermission({
      providerId,
      probeOwner: "closed-worker-b",
      now,
    });
    expect(
      await recordProviderFailure({
        permit: requirePermit(first),
        safeErrorCode: "UPSTREAM_5XX",
        opensCircuit: true,
        threshold: 1,
        openSeconds: 60,
        now: new Date(now.getTime() + 1),
      }),
    ).toBe("recorded");
    expect(
      await recordProviderSuccess({
        permit: requirePermit(second),
        now: new Date(now.getTime() + 2),
      }),
    ).toBe("stale");
    await expect(
      prisma.guideProviderCircuit.findUniqueOrThrow({ where: { providerId } }),
    ).resolves.toMatchObject({ state: "open", failureCount: 1 });
  });
});

async function openCircuit(
  providerId: string,
  now: Date,
  threshold: number,
  openSeconds: number,
): Promise<void> {
  for (let count = 0; count < threshold; count++) {
    const failureAt = new Date(now.getTime() + count);
    const permission = await claimProviderCircuitPermission({
      providerId,
      probeOwner: `opening-worker-${count}`,
      now: failureAt,
    });
    expect(permission.allowed).toBe(true);
    expect(
      await recordProviderFailure({
        permit: requirePermit(permission),
        safeErrorCode: "UPSTREAM_5XX",
        opensCircuit: true,
        now: failureAt,
        threshold,
        openSeconds,
      }),
    ).toBe("recorded");
  }
}

function requirePermit(
  permission:
    | Awaited<ReturnType<typeof claimProviderCircuitPermission>>
    | undefined,
): CircuitPermit {
  if (!permission?.allowed) throw new Error("expectedCircuitPermit");
  return permission.permit;
}

async function cleanup(): Promise<void> {
  await prisma.guideProviderCircuit.deleteMany({
    where: { providerId: { startsWith: providerPrefix } },
  });
}
