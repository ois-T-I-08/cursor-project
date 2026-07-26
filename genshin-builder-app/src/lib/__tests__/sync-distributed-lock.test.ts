import { describe, expect, it } from "vitest";

import {
  acquireSyncLease,
  DEFAULT_SYNC_LEASE_MS,
  MASTER_SYNC_LOCK_KEY,
  releaseSyncLease,
  renewSyncLease,
  tryAcquireSyncLease,
} from "@/lib/sync-distributed-lock";

type LeaseRow = {
  lockKey: string;
  ownerToken: string;
  acquiredAt: Date;
  expiresAt: Date;
};

type UpdateWhere = {
  lockKey: string;
  ownerToken?: string;
  expiresAt?: { lte?: Date; gt?: Date };
};

function createLeaseDb() {
  const rows = new Map<string, LeaseRow>();

  const matchesWhere = (current: LeaseRow, where: UpdateWhere): boolean => {
    if (current.lockKey !== where.lockKey) return false;
    if (where.ownerToken !== undefined && current.ownerToken !== where.ownerToken) {
      return false;
    }
    if (where.expiresAt?.lte !== undefined && current.expiresAt > where.expiresAt.lte) {
      return false;
    }
    if (where.expiresAt?.gt !== undefined && current.expiresAt <= where.expiresAt.gt) {
      return false;
    }
    return true;
  };

  const db = {
    syncLease: {
      findUnique: async ({ where }: { where: { lockKey: string } }) =>
        rows.get(where.lockKey) ?? null,
      create: async ({
        data,
      }: {
        data: LeaseRow;
      }) => {
        if (rows.has(data.lockKey)) {
          throw new Error("unique violation");
        }
        rows.set(data.lockKey, { ...data });
      },
      updateMany: async ({
        where,
        data,
      }: {
        where: UpdateWhere;
        data: Partial<LeaseRow>;
      }) => {
        const current = rows.get(where.lockKey);
        if (!current || !matchesWhere(current, where)) {
          return { count: 0 };
        }
        rows.set(where.lockKey, {
          ...current,
          ...data,
          lockKey: current.lockKey,
        } as LeaseRow);
        return { count: 1 };
      },
      deleteMany: async ({
        where,
      }: {
        where: { lockKey: string; ownerToken: string };
      }) => {
        const current = rows.get(where.lockKey);
        if (!current || current.ownerToken !== where.ownerToken) {
          return { count: 0 };
        }
        rows.delete(where.lockKey);
        return { count: 1 };
      },
    },
    $transaction: async <T>(callback: (tx: typeof db) => Promise<T>) =>
      callback(db),
  };

  return { db, rows };
}

describe("sync distributed lease", () => {
  it("allows only one active holder across instances", async () => {
    const { db } = createLeaseDb();
    const now = Date.now();

    expect(
      await tryAcquireSyncLease(
        MASTER_SYNC_LOCK_KEY,
        "owner-a",
        DEFAULT_SYNC_LEASE_MS,
        now,
        db,
      ),
    ).toBe(true);
    expect(
      await tryAcquireSyncLease(
        MASTER_SYNC_LOCK_KEY,
        "owner-b",
        DEFAULT_SYNC_LEASE_MS,
        now,
        db,
      ),
    ).toBe(false);
  });

  it("releases only for the matching owner token", async () => {
    const { db, rows } = createLeaseDb();
    const now = Date.now();

    await acquireSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", DEFAULT_SYNC_LEASE_MS, now, db);
    expect(await releaseSyncLease(MASTER_SYNC_LOCK_KEY, "owner-b", db)).toBe(false);
    expect(rows.has(MASTER_SYNC_LOCK_KEY)).toBe(true);
    expect(await releaseSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", db)).toBe(true);
    expect(rows.has(MASTER_SYNC_LOCK_KEY)).toBe(false);
  });

  it("recovers after TTL expiry", async () => {
    const { db } = createLeaseDb();
    const startedAt = Date.now();

    await acquireSyncLease(
      MASTER_SYNC_LOCK_KEY,
      "owner-a",
      1_000,
      startedAt,
      db,
    );
    expect(
      await tryAcquireSyncLease(
        MASTER_SYNC_LOCK_KEY,
        "owner-b",
        DEFAULT_SYNC_LEASE_MS,
        startedAt + 2_000,
        db,
      ),
    ).toBe(true);
  });

  it("lets the correct owner renew and extend expiresAt", async () => {
    const { db, rows } = createLeaseDb();
    const startedAt = Date.now();
    await acquireSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", 10_000, startedAt, db);
    const before = rows.get(MASTER_SYNC_LOCK_KEY)!.expiresAt.getTime();

    expect(
      await renewSyncLease(
        MASTER_SYNC_LOCK_KEY,
        "owner-a",
        10_000,
        startedAt + 4_000,
        db,
      ),
    ).toBe(true);
    const after = rows.get(MASTER_SYNC_LOCK_KEY)!.expiresAt.getTime();
    expect(after).toBe(startedAt + 4_000 + 10_000);
    expect(after).toBeGreaterThan(before);
  });

  it("rejects renewal from another owner", async () => {
    const { db } = createLeaseDb();
    const now = Date.now();
    await acquireSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", 10_000, now, db);
    expect(
      await renewSyncLease(MASTER_SYNC_LOCK_KEY, "owner-b", 10_000, now + 1_000, db),
    ).toBe(false);
  });

  it("rejects renewal after expiry", async () => {
    const { db } = createLeaseDb();
    const startedAt = Date.now();
    await acquireSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", 1_000, startedAt, db);
    expect(
      await renewSyncLease(
        MASTER_SYNC_LOCK_KEY,
        "owner-a",
        10_000,
        startedAt + 2_000,
        db,
      ),
    ).toBe(false);
  });

  it("does not release another owner's lease", async () => {
    const { db, rows } = createLeaseDb();
    const startedAt = Date.now();
    await acquireSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", 1_000, startedAt, db);
    await tryAcquireSyncLease(
      MASTER_SYNC_LOCK_KEY,
      "owner-b",
      10_000,
      startedAt + 2_000,
      db,
    );
    expect(await releaseSyncLease(MASTER_SYNC_LOCK_KEY, "owner-a", db)).toBe(false);
    expect(rows.get(MASTER_SYNC_LOCK_KEY)?.ownerToken).toBe("owner-b");
  });
});
