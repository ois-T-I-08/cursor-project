import { beforeEach, describe, expect, it } from "vitest";

import {
  resetSyncExecutionForTest,
  runSyncExclusive,
  SyncAlreadyRunningError,
} from "@/lib/sync-execution";
import type { SyncResult } from "@/lib/sync";

describe("runSyncExclusive", () => {
  beforeEach(() => resetSyncExecutionForTest());

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
  });

  it("always releases the lock after failure", async () => {
    await expect(
      runSyncExclusive(false, async () => {
        throw new Error("DB failure");
      }),
    ).rejects.toThrow("DB failure");

    await expect(
      runSyncExclusive(false, async () => result()),
    ).resolves.toEqual(result());
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
