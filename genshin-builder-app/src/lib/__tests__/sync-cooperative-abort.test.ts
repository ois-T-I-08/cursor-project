import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  SyncLeaseOwnershipLostError,
  throwIfSyncAborted,
} from "@/lib/sync-distributed-lock";

const fetchCharacters = vi.hoisted(() => vi.fn());
const fetchWeapons = vi.hoisted(() => vi.fn());
const fetchMaterials = vi.hoisted(() => vi.fn());
const syncUpgradeData = vi.hoisted(() => vi.fn());
const characterUpsert = vi.hoisted(() => vi.fn());
const characterDeleteMany = vi.hoisted(() => vi.fn());
const weaponUpsert = vi.hoisted(() => vi.fn());
const weaponDeleteMany = vi.hoisted(() => vi.fn());
const materialUpsert = vi.hoisted(() => vi.fn());
const materialDeleteMany = vi.hoisted(() => vi.fn());
const syncLogCreate = vi.hoisted(() => vi.fn());
const userProgressFindMany = vi.hoisted(() => vi.fn());

vi.mock("@/lib/api", () => ({
  gameDataProvider: {
    name: "test-provider",
    fetchCharacters,
    fetchWeapons,
    fetchMaterials,
  },
}));

vi.mock("@/lib/sync-upgrade", () => ({
  syncUpgradeData,
}));

vi.mock("@/lib/db", () => ({
  prisma: {
    $transaction: async (fn: (tx: unknown) => Promise<unknown>) =>
      fn({
        character: {
          upsert: characterUpsert,
          deleteMany: characterDeleteMany,
        },
        weapon: {
          upsert: weaponUpsert,
          deleteMany: weaponDeleteMany,
        },
        material: {
          upsert: materialUpsert,
          deleteMany: materialDeleteMany,
        },
        userProgress: {
          findMany: userProgressFindMany,
        },
      }),
    syncLog: {
      create: syncLogCreate,
    },
  },
}));

import { syncMasterData } from "@/lib/sync";

describe("throwIfSyncAborted", () => {
  it("is a no-op when signal is missing or not aborted", () => {
    expect(() => throwIfSyncAborted(undefined)).not.toThrow();
    expect(() => throwIfSyncAborted(new AbortController().signal)).not.toThrow();
  });

  it("throws SyncLeaseOwnershipLostError without abort reason details", () => {
    const controller = new AbortController();
    controller.abort("secret-reason");
    expect(() => throwIfSyncAborted(controller.signal)).toThrow(
      SyncLeaseOwnershipLostError,
    );
    try {
      throwIfSyncAborted(controller.signal);
    } catch (error) {
      expect((error as Error).message).not.toContain("secret-reason");
      expect((error as Error).message).not.toMatch(/[0-9a-f-]{36}/i);
    }
  });
});

describe("syncMasterData cooperative abort", () => {
  beforeEach(() => {
    fetchCharacters.mockReset();
    fetchWeapons.mockReset();
    fetchMaterials.mockReset();
    syncUpgradeData.mockReset();
    characterUpsert.mockReset();
    characterDeleteMany.mockReset();
    weaponUpsert.mockReset();
    weaponDeleteMany.mockReset();
    materialUpsert.mockReset();
    materialDeleteMany.mockReset();
    syncLogCreate.mockReset();
    userProgressFindMany.mockReset();
    userProgressFindMany.mockResolvedValue([]);
    syncUpgradeData.mockResolvedValue({
      characterUpgrades: 0,
      weaponUpgrades: 0,
      levelExpSegments: 0,
      expMaterials: 0,
      apiCalls: 0,
      skippedCharacterUpgrades: 0,
      skippedWeaponUpgrades: 0,
      errors: [],
    });
  });

  it("runs to completion when signal is omitted", async () => {
    fetchCharacters.mockResolvedValue([
      { id: "c1", name: "A", element: "Anemo", weaponType: "Sword", rarity: 5 },
    ]);
    fetchWeapons.mockResolvedValue([]);
    fetchMaterials.mockResolvedValue([]);

    const result = await syncMasterData({ fullUpgrade: false });
    expect(result.characters).toBe(1);
    expect(characterUpsert).toHaveBeenCalled();
    expect(syncUpgradeData).toHaveBeenCalled();
    expect(syncLogCreate).toHaveBeenCalled();
  });

  it("stops before any phase write when aborted at start", async () => {
    const controller = new AbortController();
    controller.abort();
    fetchCharacters.mockResolvedValue([{ id: "c1" }]);
    fetchWeapons.mockResolvedValue([]);
    fetchMaterials.mockResolvedValue([]);

    await expect(
      syncMasterData({ signal: controller.signal }),
    ).rejects.toBeInstanceOf(SyncLeaseOwnershipLostError);
    expect(fetchCharacters).not.toHaveBeenCalled();
    expect(characterUpsert).not.toHaveBeenCalled();
    expect(syncUpgradeData).not.toHaveBeenCalled();
  });

  it("does not start weapons phase after characters when aborted", async () => {
    const controller = new AbortController();
    fetchCharacters.mockResolvedValue([
      { id: "c1", name: "A", element: "Anemo", weaponType: "Sword", rarity: 5 },
    ]);
    fetchWeapons.mockResolvedValue([
      { id: "w1", name: "W", weaponType: "Sword", rarity: 5 },
    ]);
    fetchMaterials.mockResolvedValue([]);
    characterUpsert.mockImplementation(async () => {
      controller.abort();
    });

    await expect(
      syncMasterData({ signal: controller.signal }),
    ).rejects.toBeInstanceOf(SyncLeaseOwnershipLostError);
    expect(weaponUpsert).not.toHaveBeenCalled();
    expect(syncUpgradeData).not.toHaveBeenCalled();
  });

  it("does not start upgrade phase after materials when aborted", async () => {
    const controller = new AbortController();
    fetchCharacters.mockResolvedValue([]);
    fetchWeapons.mockResolvedValue([]);
    fetchMaterials.mockResolvedValue([
      { id: "m1", name: "M", type: "t", rarity: 1 },
    ]);
    materialUpsert.mockImplementation(async () => {
      controller.abort();
    });

    await expect(
      syncMasterData({ signal: controller.signal }),
    ).rejects.toBeInstanceOf(SyncLeaseOwnershipLostError);
    expect(syncUpgradeData).not.toHaveBeenCalled();
    expect(syncLogCreate).not.toHaveBeenCalled();
  });

  it("forwards signal into syncUpgradeData", async () => {
    const controller = new AbortController();
    fetchCharacters.mockResolvedValue([]);
    fetchWeapons.mockResolvedValue([]);
    fetchMaterials.mockResolvedValue([]);

    await syncMasterData({
      fullUpgrade: true,
      signal: controller.signal,
    });
    expect(syncUpgradeData).toHaveBeenCalledWith(
      expect.objectContaining({
        fullUpgrade: true,
        signal: controller.signal,
      }),
    );
  });
});
