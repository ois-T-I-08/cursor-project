import { beforeEach, describe, expect, it, vi } from "vitest";

import { UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import type {
  CharacterUpgradeData,
  LevelUpMaterialData,
  WeaponUpgradeData,
} from "@/lib/api/upgrade-types";

const prismaMock = vi.hoisted(() => {
  const characterUpgradeRows = new Map<string, CharacterUpgradeData>();
  const weaponUpgradeRows = new Map<string, WeaponUpgradeData>();
  let transactionShouldFail = false;

  const tx = {
    material: {
      updateMany: vi.fn(async () => ({ count: 1 })),
    },
    levelExpSegment: {
      upsert: vi.fn(async () => ({})),
    },
    characterUpgrade: {
      upsert: vi.fn(
        async ({
          where,
          create,
        }: {
          where: { characterId: string };
          create: {
            characterId: string;
            promotes: string;
            talents: string;
          };
        }) => {
          characterUpgradeRows.set(where.characterId, {
            characterId: create.characterId,
            promotes: JSON.parse(create.promotes),
            talents: JSON.parse(create.talents),
          });
        },
      ),
      deleteMany: vi.fn(
        async ({
          where,
        }: {
          where: { characterId: { notIn: string[] } };
        }) => {
          characterDeleteManyCalled = true;
          const keep = new Set(where.characterId.notIn);
          for (const key of [...characterUpgradeRows.keys()]) {
            if (!keep.has(key)) {
              characterUpgradeRows.delete(key);
            }
          }
          return { count: 1 };
        },
      ),
    },
    weaponUpgrade: {
      upsert: vi.fn(
        async ({
          where,
          create,
        }: {
          where: { weaponId: string };
          create: {
            weaponId: string;
            promotes: string;
            levelUpItemIds: string;
          };
        }) => {
          weaponUpgradeRows.set(where.weaponId, {
            weaponId: create.weaponId,
            promotes: JSON.parse(create.promotes),
            levelUpItemIds: JSON.parse(create.levelUpItemIds),
          });
        },
      ),
      deleteMany: vi.fn(
        async ({
          where,
        }: {
          where: { weaponId: { notIn: string[] } };
        }) => {
          weaponDeleteManyCalled = true;
          const keep = new Set(where.weaponId.notIn);
          for (const key of [...weaponUpgradeRows.keys()]) {
            if (!keep.has(key)) {
              weaponUpgradeRows.delete(key);
            }
          }
          return { count: 1 };
        },
      ),
    },
  };

  let characterDeleteManyCalled = false;
  let weaponDeleteManyCalled = false;

  return {
    characterUpgradeRows,
    weaponUpgradeRows,
    characterDeleteManyCalled: () => characterDeleteManyCalled,
    weaponDeleteManyCalled: () => weaponDeleteManyCalled,
    resetDeleteManyFlags: () => {
      characterDeleteManyCalled = false;
      weaponDeleteManyCalled = false;
    },
    setTransactionShouldFail: (value: boolean) => {
      transactionShouldFail = value;
    },
    tx,
    prisma: {
      character: {
        findMany: vi.fn(async () => [{ id: "10000002" }, { id: "10000003" }]),
      },
      weapon: {
        findMany: vi.fn(async () => [{ id: "weapon-1" }]),
      },
      material: {
        count: vi.fn(async () => 6),
      },
      levelExpSegment: {
        count: vi.fn(async () => 32),
      },
      characterUpgrade: {
        count: vi.fn(async () => characterUpgradeRows.size),
        findMany: vi.fn(async () =>
          [...characterUpgradeRows.keys()].map((characterId) => ({
            characterId,
          })),
        ),
      },
      weaponUpgrade: {
        count: vi.fn(async () => weaponUpgradeRows.size),
        findMany: vi.fn(async () =>
          [...weaponUpgradeRows.keys()].map((weaponId) => ({ weaponId })),
        ),
      },
      $transaction: vi.fn(
        async (
          callback: (transaction: typeof tx) => Promise<void>,
        ) => {
          if (transactionShouldFail) {
            throw new Error("transaction failed");
          }
          await callback(tx);
        },
      ),
    },
  };
});

const fetchMocks = vi.hoisted(() => ({
  fetchLevelUpMaterialsFromApi: vi.fn(),
  fetchCharacterUpgradeFromApi: vi.fn(),
  fetchWeaponUpgradeFromApi: vi.fn(),
}));

vi.mock("@/lib/db", () => ({
  prisma: prismaMock.prisma,
}));

vi.mock("@/lib/api/amber-upgrade", async (importOriginal) => {
  const original =
    await importOriginal<typeof import("@/lib/api/amber-upgrade")>();
  return {
    ...original,
    fetchLevelUpMaterialsFromApi: fetchMocks.fetchLevelUpMaterialsFromApi,
    fetchCharacterUpgradeFromApi: fetchMocks.fetchCharacterUpgradeFromApi,
    fetchWeaponUpgradeFromApi: fetchMocks.fetchWeaponUpgradeFromApi,
  };
});

import { syncUpgradeData } from "@/lib/sync-upgrade";

const expMaterials: LevelUpMaterialData[] = [
  {
    materialId: "104001",
    name: "wanderer",
    exp: 1000,
    targetType: "character",
  },
  {
    materialId: "104002",
    name: "adventurer",
    exp: 2000,
    targetType: "character",
  },
  {
    materialId: "104003",
    name: "hero",
    exp: 5000,
    targetType: "character",
  },
  {
    materialId: "104011",
    name: "whetstone",
    exp: 400,
    targetType: "weapon",
  },
  {
    materialId: "104012",
    name: "grit",
    exp: 1000,
    targetType: "weapon",
  },
  {
    materialId: "104013",
    name: "ingot",
    exp: 2000,
    targetType: "weapon",
  },
];

function characterUpgrade(id: string): CharacterUpgradeData {
  return {
    characterId: id,
    promotes: [
      {
        promoteLevel: 0,
        unlockMaxLevel: 20,
        costItems: {},
        coinCost: 0,
      },
    ],
    talents: [],
  };
}

function weaponUpgrade(id: string): WeaponUpgradeData {
  return {
    weaponId: id,
    promotes: [
      {
        promoteLevel: 0,
        unlockMaxLevel: 20,
        costItems: {},
        coinCost: 0,
      },
    ],
    levelUpItemIds: ["104011", "104012", "104013"],
  };
}

describe("syncUpgradeData fullUpgrade", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.characterUpgradeRows.clear();
    prismaMock.weaponUpgradeRows.clear();
    prismaMock.resetDeleteManyFlags();
    prismaMock.setTransactionShouldFail(false);
    prismaMock.characterUpgradeRows.set(
      "legacy-character",
      characterUpgrade("legacy-character"),
    );
    prismaMock.weaponUpgradeRows.set(
      "legacy-weapon",
      weaponUpgrade("legacy-weapon"),
    );

    fetchMocks.fetchLevelUpMaterialsFromApi.mockResolvedValue(expMaterials);
    fetchMocks.fetchCharacterUpgradeFromApi.mockImplementation(
      async (characterId: string) => characterUpgrade(characterId),
    );
    fetchMocks.fetchWeaponUpgradeFromApi.mockImplementation(
      async (weaponId: string) => weaponUpgrade(weaponId),
    );
  });

  it("replaces upgrade rows only after all upstream fetches succeed", async () => {
    const result = await syncUpgradeData({ fullUpgrade: true });

    expect(result.errors).toEqual([]);
    expect(prismaMock.characterDeleteManyCalled()).toBe(true);
    expect(prismaMock.characterUpgradeRows.has("10000002")).toBe(true);
    expect(prismaMock.characterUpgradeRows.has("legacy-character")).toBe(
      false,
    );
    expect(prismaMock.weaponUpgradeRows.has("weapon-1")).toBe(true);
    expect(prismaMock.weaponUpgradeRows.has("legacy-weapon")).toBe(false);
  });

  it.each([
    ["first", () => fetchMocks.fetchLevelUpMaterialsFromApi.mockRejectedValueOnce(new UpstreamFetchError("httpStatus", 500))],
    [
      "middle",
      () =>
        fetchMocks.fetchCharacterUpgradeFromApi.mockImplementation(
          async (characterId: string) => {
            if (characterId === "10000002") {
              throw new UpstreamFetchError("httpStatus", 502);
            }
            return characterUpgrade(characterId);
          },
        ),
    ],
    [
      "last",
      () =>
        fetchMocks.fetchWeaponUpgradeFromApi.mockRejectedValueOnce(
          new UpstreamFetchError("invalidData"),
        ),
    ],
  ])(
    "keeps existing rows when %s upstream fetch fails",
    async (_label, arrange) => {
      arrange();

      const result = await syncUpgradeData({ fullUpgrade: true });

      expect(result.errors).toHaveLength(1);
      expect(result.errors[0]).toMatch(/^fullUpgrade:/);
      expect(prismaMock.characterDeleteManyCalled()).toBe(false);
      expect(prismaMock.weaponDeleteManyCalled()).toBe(false);
      expect(prismaMock.characterUpgradeRows.has("legacy-character")).toBe(
        true,
      );
      expect(prismaMock.weaponUpgradeRows.has("legacy-weapon")).toBe(true);
      expect(prismaMock.prisma.$transaction).not.toHaveBeenCalled();
    },
  );

  it("does not delete when validated incoming character ids are empty", async () => {
    prismaMock.prisma.character.findMany.mockResolvedValueOnce([]);

    const result = await syncUpgradeData({ fullUpgrade: true });

    expect(result.errors).toEqual([]);
    expect(prismaMock.characterDeleteManyCalled()).toBe(false);
    expect(prismaMock.characterUpgradeRows.has("legacy-character")).toBe(true);
  });

  it("rolls back and preserves existing rows when transaction fails", async () => {
    prismaMock.setTransactionShouldFail(true);

    const result = await syncUpgradeData({ fullUpgrade: true });

    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toBe("fullUpgrade:unavailable");
    expect(prismaMock.characterUpgradeRows.has("legacy-character")).toBe(true);
    expect(prismaMock.weaponUpgradeRows.has("legacy-weapon")).toBe(true);
  });

  it("is idempotent when rerun with the same upstream payload", async () => {
    await syncUpgradeData({ fullUpgrade: true });
    const second = await syncUpgradeData({ fullUpgrade: true });

    expect(second.errors).toEqual([]);
    expect(prismaMock.characterUpgradeRows.size).toBe(2);
    expect(prismaMock.weaponUpgradeRows.size).toBe(1);
  });
});

describe("syncUpgradeData incremental", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    prismaMock.characterUpgradeRows.clear();
    prismaMock.weaponUpgradeRows.clear();
    prismaMock.resetDeleteManyFlags();
    prismaMock.setTransactionShouldFail(false);
    prismaMock.characterUpgradeRows.set(
      "existing-character",
      characterUpgrade("existing-character"),
    );

    fetchMocks.fetchLevelUpMaterialsFromApi.mockResolvedValue(expMaterials);
    fetchMocks.fetchCharacterUpgradeFromApi.mockImplementation(
      async (characterId: string) => characterUpgrade(characterId),
    );
    fetchMocks.fetchWeaponUpgradeFromApi.mockImplementation(
      async (weaponId: string) => weaponUpgrade(weaponId),
    );
  });

  it("never prunes existing rows on partial incremental fetch failure", async () => {
    fetchMocks.fetchCharacterUpgradeFromApi.mockRejectedValueOnce(
      new UpstreamFetchError("httpStatus", 500),
    );

    const result = await syncUpgradeData({ fullUpgrade: false });

    expect(result.errors).toContain("characterUpgrades:httpStatus");
    expect(prismaMock.characterDeleteManyCalled()).toBe(false);
    expect(prismaMock.characterUpgradeRows.has("existing-character")).toBe(
      true,
    );
  });
});
