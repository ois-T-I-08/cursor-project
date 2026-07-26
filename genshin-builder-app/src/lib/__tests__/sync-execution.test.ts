import { beforeEach, describe, expect, it, vi } from "vitest";

const acquireSyncLease = vi.hoisted(() =>
  vi.fn().mockResolvedValue(undefined),
);
const releaseSyncLease = vi.hoisted(() => vi.fn().mockResolvedValue(true));
const renewSyncLease = vi.hoisted(() => vi.fn().mockResolvedValue(true));

vi.mock("@/lib/sync-distributed-lock", () => ({
  MASTER_SYNC_LOCK_KEY: "master-sync",
  DEFAULT_SYNC_LEASE_MS: 360_000,
  DEFAULT_SYNC_LEASE_RENEW_INTERVAL_MS: 120_000,
  SyncLeaseUnavailableError: class SyncLeaseUnavailableError extends Error {
    constructor() {
      super("Distributed sync lease is already held");
      this.name = "SyncLeaseUnavailableError";
    }
  },
  SyncLeaseOwnershipLostError: class SyncLeaseOwnershipLostError extends Error {
    constructor() {
      super("Distributed sync lease ownership was lost");
      this.name = "SyncLeaseOwnershipLostError";
    }
  },
  acquireSyncLease,
  releaseSyncLease,
  renewSyncLease,
  tryAcquireSyncLease: vi.fn(),
}));

import {
  resetSyncExecutionForTest,
  runSyncExclusive,
  SyncAlreadyRunningError,
} from "@/lib/sync-execution";
import { SyncLeaseOwnershipLostError } from "@/lib/sync-distributed-lock";
import type { SyncResult } from "@/lib/sync";

describe("runSyncExclusive", () => {
  beforeEach(() => {
    resetSyncExecutionForTest();
    acquireSyncLease.mockClear();
    releaseSyncLease.mockClear();
    renewSyncLease.mockClear();
    acquireSyncLease.mockResolvedValue(undefined);
    releaseSyncLease.mockResolvedValue(true);
    renewSyncLease.mockResolvedValue(true);
  });

  it("rejects a concurrent request and allows the next request after success",
      async () => {
    let resolve!: (result: SyncResult) => void;
    const pending = new Promise<SyncResult>((done) => {
      resolve = done;
    });
    let runs = 0;
    const runner = async () => {
      runs++;
      return pending;
    };

    const first = runSyncExclusive(false, runner);
    await expect(
      runSyncExclusive(false, runner),
    ).rejects.toBeInstanceOf(SyncAlreadyRunningError);
    resolve(result());
    await expect(first).resolves.toEqual(result());

    await expect(
      runSyncExclusive(false, async () => result()),
    ).resolves.toEqual(result());
    expect(runs).toBe(1);
    expect(acquireSyncLease).toHaveBeenCalled();
    expect(releaseSyncLease).toHaveBeenCalled();
  });

  it("always releases the distributed lease after failure", async () => {
    await expect(
      runSyncExclusive(false, async () => {
        throw new Error("DB failure");
      }),
    ).rejects.toThrow("DB failure");

    await expect(
      runSyncExclusive(false, async () => result()),
    ).resolves.toEqual(result());
    expect(releaseSyncLease.mock.calls.length).toBeGreaterThanOrEqual(1);
  });

  it("renews the lease on an interval and stops the timer after completion", async () => {
    const timers: Array<{
      delay: number;
      fire: () => void;
    }> = [];
    const setIntervalFn = ((handler: TimerHandler, delay?: number) => {
      const id = timers.length + 1;
      timers.push({
        delay: delay ?? 0,
        fire: () => {
          if (typeof handler === "function") {
            handler();
          }
        },
      });
      return id as unknown as ReturnType<typeof setInterval>;
    }) as typeof setInterval;
    const clearIntervalFn = vi.fn();

    let resolveRunner!: (value: SyncResult) => void;
    const runnerDone = new Promise<SyncResult>((resolve) => {
      resolveRunner = resolve;
    });

    const pending = runSyncExclusive(
      false,
      async () => runnerDone,
      {
        renewIntervalMs: 1_000,
        leaseMs: 3_000,
        setIntervalFn,
        clearIntervalFn,
      },
    );

    await vi.waitFor(() => {
      expect(timers.length).toBe(1);
    });
    expect(timers[0]?.delay).toBe(1_000);

    timers[0]?.fire();
    await vi.waitFor(() => {
      expect(renewSyncLease).toHaveBeenCalled();
    });

    resolveRunner(result());
    await expect(pending).resolves.toEqual(result());
    expect(clearIntervalFn).toHaveBeenCalled();
    expect(releaseSyncLease).toHaveBeenCalled();
  });

  it("aborts and fails when renewal reports ownership loss", async () => {
    renewSyncLease.mockResolvedValue(false);
    const timers: Array<() => void> = [];
    const setIntervalFn = ((handler: TimerHandler) => {
      timers.push(() => {
        if (typeof handler === "function") handler();
      });
      return 1 as unknown as ReturnType<typeof setInterval>;
    }) as typeof setInterval;

    let sawAbort = false;
    const pending = runSyncExclusive(
      false,
      async ({ signal }) => {
        await new Promise<void>((resolve) => {
          const check = () => {
            if (signal.aborted) {
              sawAbort = true;
              resolve();
              return;
            }
            setTimeout(check, 5);
          };
          check();
        });
        return result();
      },
      {
        renewIntervalMs: 10,
        setIntervalFn,
        clearIntervalFn: vi.fn(),
      },
    );

    await vi.waitFor(() => {
      expect(timers.length).toBe(1);
    });
    timers[0]?.();

    await expect(pending).rejects.toBeInstanceOf(SyncLeaseOwnershipLostError);
    expect(sawAbort).toBe(true);
    expect(releaseSyncLease).toHaveBeenCalled();
  });

  it("maps lease conflicts to SyncAlreadyRunningError without owner token details", async () => {
    const { SyncLeaseUnavailableError } = await import(
      "@/lib/sync-distributed-lock"
    );
    acquireSyncLease.mockRejectedValueOnce(new SyncLeaseUnavailableError());

    await expect(
      runSyncExclusive(false, async () => result()),
    ).rejects.toSatisfy((error: unknown) => {
      expect(error).toBeInstanceOf(SyncAlreadyRunningError);
      expect((error as Error).message).not.toMatch(/owner|token|[0-9a-f-]{20,}/i);
      return true;
    });
  });
});

function result(): SyncResult {
  return {
    provider: "test",
    characters: 0,
    weapons: 0,
    materials: 0,
    characterUpgrades: 0,
    weaponUpgrades: 0,
    levelExpSegments: 0,
    expMaterials: 0,
    upgradeApiCalls: 0,
    skippedCharacterUpgrades: 0,
    skippedWeaponUpgrades: 0,
    errors: [],
  };
}
