import { describe, expect, it } from "vitest";

import {
  acquireSyncLease,
  DEFAULT_SYNC_LEASE_MS,
  MASTER_SYNC_LOCK_KEY,
  releaseSyncLease,
  tryAcquireSyncLease,
} from "@/lib/sync-distributed-lock";

type LeaseRow = {
  lockKey: string;
  ownerToken: string;
  acquiredAt: Date;
  expiresAt: Date;
};

function createLeaseDb() {
  const rows = new Map<string, LeaseRow>();

  const syncLease = {
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
        where: { lockKey: string; expiresAt: { lte: Date } };
        data: Partial<LeaseRow>;
      }) => {
        const current = rows.get(where.lockKey);
        if (!current || current.expiresAt > where.expiresAt.lte) {
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
  };
  const db = {
    syncLease,
    $transaction: async <T>(
      callback: (tx: { syncLease: typeof syncLease }) => Promise<T>,
    ) => callback({ syncLease }),
  };

  return {
    db: db as unknown as Parameters<typeof tryAcquireSyncLease>[4],
    rows,
  };
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
});
