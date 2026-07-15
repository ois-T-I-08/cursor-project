import { randomUUID } from "node:crypto";

import { prisma } from "@/lib/db";
import {
  acquireSyncLease,
  MASTER_SYNC_LOCK_KEY,
  releaseSyncLease,
  SyncLeaseUnavailableError,
} from "@/lib/sync-distributed-lock";
import { syncMasterData, type SyncResult } from "@/lib/sync";

export class SyncAlreadyRunningError extends Error {
  constructor() {
    super("Master-data sync is already running");
    this.name = "SyncAlreadyRunningError";
  }
}

let activeSync: Promise<SyncResult> | null = null;
type SyncRunner = (options: { fullUpgrade: boolean }) => Promise<SyncResult>;

/** Shares process-local and DB-backed leases across instances. */
export async function runSyncExclusive(
  fullUpgrade: boolean,
  runner: SyncRunner = syncMasterData,
): Promise<SyncResult> {
  if (activeSync) {
    throw new SyncAlreadyRunningError();
  }

  let resolveCurrent!: (result: SyncResult) => void;
  let rejectCurrent!: (error: unknown) => void;
  const current = new Promise<SyncResult>((resolve, reject) => {
    resolveCurrent = resolve;
    rejectCurrent = reject;
  });
  activeSync = current;

  const ownerToken = randomUUID();
  void (async () => {
    try {
      await acquireSyncLease(
        MASTER_SYNC_LOCK_KEY,
        ownerToken,
        undefined,
        Date.now(),
        prisma,
      );
      resolveCurrent(await runner({ fullUpgrade }));
    } catch (error) {
      if (error instanceof SyncLeaseUnavailableError) {
        rejectCurrent(new SyncAlreadyRunningError());
      } else {
        rejectCurrent(error);
      }
    } finally {
      await releaseSyncLease(MASTER_SYNC_LOCK_KEY, ownerToken, prisma).catch(
        () => false,
      );
      if (activeSync === current) {
        activeSync = null;
      }
    }
  })();

  return current;
}

export function resetSyncExecutionForTest(): void {
  activeSync = null;
}
