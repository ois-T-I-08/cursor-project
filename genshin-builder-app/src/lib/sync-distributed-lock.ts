import type { PrismaClient } from "@prisma/client";

export const MASTER_SYNC_LOCK_KEY = "master-sync";
export const DEFAULT_SYNC_LEASE_MS = 5 * 60 * 1000;

export class SyncLeaseUnavailableError extends Error {
  constructor() {
    super("Distributed sync lease is already held");
    this.name = "SyncLeaseUnavailableError";
  }
}

type SyncLeaseDb = Pick<PrismaClient, "$transaction" | "syncLease">;

export async function tryAcquireSyncLease(
  lockKey: string,
  ownerToken: string,
  leaseMs = DEFAULT_SYNC_LEASE_MS,
  now = Date.now(),
  db: SyncLeaseDb,
): Promise<boolean> {
  const nowDate = new Date(now);
  const expiresAt = new Date(now + leaseMs);

  return db.$transaction(async (tx) => {
    const existing = await tx.syncLease.findUnique({ where: { lockKey } });
    if (!existing) {
      try {
        await tx.syncLease.create({
          data: {
            lockKey,
            ownerToken,
            acquiredAt: nowDate,
            expiresAt,
          },
        });
        return true;
      } catch {
        return false;
      }
    }

    if (existing.expiresAt.getTime() > now && existing.ownerToken !== ownerToken) {
      return false;
    }

    if (existing.expiresAt.getTime() <= now) {
      const stolen = await tx.syncLease.updateMany({
        where: {
          lockKey,
          expiresAt: { lte: nowDate },
        },
        data: {
          ownerToken,
          acquiredAt: nowDate,
          expiresAt,
        },
      });
      return stolen.count === 1;
    }

    return existing.ownerToken === ownerToken;
  });
}

export async function acquireSyncLease(
  lockKey: string,
  ownerToken: string,
  leaseMs = DEFAULT_SYNC_LEASE_MS,
  now = Date.now(),
  db: SyncLeaseDb,
): Promise<void> {
  const acquired = await tryAcquireSyncLease(
    lockKey,
    ownerToken,
    leaseMs,
    now,
    db,
  );
  if (!acquired) {
    throw new SyncLeaseUnavailableError();
  }
}

export async function releaseSyncLease(
  lockKey: string,
  ownerToken: string,
  db: SyncLeaseDb,
): Promise<boolean> {
  const result = await db.syncLease.deleteMany({
    where: { lockKey, ownerToken },
  });
  return result.count === 1;
}
