import type { PrismaClient } from "@prisma/client";

export const MASTER_SYNC_LOCK_KEY = "master-sync";
export const DEFAULT_SYNC_LEASE_MS = 360_000;
/** Heartbeat interval ≈ TTL / 3 so ownership is renewed before expiry. */
export const DEFAULT_SYNC_LEASE_RENEW_INTERVAL_MS = 120_000;

export class SyncLeaseUnavailableError extends Error {
  constructor() {
    super("Distributed sync lease is already held");
    this.name = "SyncLeaseUnavailableError";
  }
}

export class SyncLeaseOwnershipLostError extends Error {
  constructor() {
    super("Distributed sync lease ownership was lost");
    this.name = "SyncLeaseOwnershipLostError";
  }
}

/** Cooperative stop for sync phases. Does not expose abort reasons or tokens. */
export function throwIfSyncAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw new SyncLeaseOwnershipLostError();
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

    // Same owner re-acquire: extend expiry so long runs stay protected.
    const extended = await tx.syncLease.updateMany({
      where: { lockKey, ownerToken },
      data: { expiresAt },
    });
    return extended.count === 1;
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

/**
 * Extends expiresAt only when lockKey + ownerToken match and the lease is
 * still unexpired. Returns false when ownership is lost (stolen or missing).
 */
export async function renewSyncLease(
  lockKey: string,
  ownerToken: string,
  leaseMs = DEFAULT_SYNC_LEASE_MS,
  now = Date.now(),
  db: SyncLeaseDb,
): Promise<boolean> {
  const nowDate = new Date(now);
  const expiresAt = new Date(now + leaseMs);

  const result = await db.syncLease.updateMany({
    where: {
      lockKey,
      ownerToken,
      expiresAt: { gt: nowDate },
    },
    data: { expiresAt },
  });
  return result.count === 1;
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
