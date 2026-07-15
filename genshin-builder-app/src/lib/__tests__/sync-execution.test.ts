import { beforeEach, describe, expect, it, vi } from "vitest";

const acquireSyncLease = vi.hoisted(() =>
  vi.fn().mockResolvedValue(undefined),
);
const releaseSyncLease = vi.hoisted(() => vi.fn().mockResolvedValue(true));

vi.mock("@/lib/sync-distributed-lock", () => ({
  MASTER_SYNC_LOCK_KEY: "master-sync",
  DEFAULT_SYNC_LEASE_MS: 300_000,
  SyncLeaseUnavailableError: class SyncLeaseUnavailableError extends Error {
    constructor() {
      super("Distributed sync lease is already held");
      this.name = "SyncLeaseUnavailableError";
    }
  },
  acquireSyncLease,
  releaseSyncLease,
  tryAcquireSyncLease: vi.fn(),
}));

import {
  resetSyncExecutionForTest,
  runSyncExclusive,
  SyncAlreadyRunningError,
} from "@/lib/sync-execution";
import type { SyncResult } from "@/lib/sync";

describe("runSyncExclusive", () => {
  beforeEach(() => {
    resetSyncExecutionForTest();
    acquireSyncLease.mockClear();
    releaseSyncLease.mockClear();
    acquireSyncLease.mockResolvedValue(undefined);
    releaseSyncLease.mockResolvedValue(true);
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
