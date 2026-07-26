import { randomUUID } from "node:crypto";

import { prisma } from "@/lib/db";
import {
  acquireSyncLease,
  DEFAULT_SYNC_LEASE_MS,
  DEFAULT_SYNC_LEASE_RENEW_INTERVAL_MS,
  MASTER_SYNC_LOCK_KEY,
  releaseSyncLease,
  renewSyncLease,
  SyncLeaseOwnershipLostError,
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
type SyncRunner = (options: {
  fullUpgrade: boolean;
  signal: AbortSignal;
}) => Promise<SyncResult>;

type LeaseHeartbeatOptions = {
  leaseMs?: number;
  renewIntervalMs?: number;
  now?: () => number;
  setIntervalFn?: typeof setInterval;
  clearIntervalFn?: typeof clearInterval;
};

/** Shares process-local and DB-backed leases across instances. */
export async function runSyncExclusive(
  fullUpgrade: boolean,
  runner: SyncRunner = (options) =>
    syncMasterData({
      fullUpgrade: options.fullUpgrade,
      signal: options.signal,
    }),
  heartbeat: LeaseHeartbeatOptions = {},
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
  const leaseMs = heartbeat.leaseMs ?? DEFAULT_SYNC_LEASE_MS;
  const renewIntervalMs =
    heartbeat.renewIntervalMs ?? DEFAULT_SYNC_LEASE_RENEW_INTERVAL_MS;
  const nowFn = heartbeat.now ?? Date.now;
  const setIntervalFn = heartbeat.setIntervalFn ?? setInterval;
  const clearIntervalFn = heartbeat.clearIntervalFn ?? clearInterval;

  void (async () => {
    const abort = new AbortController();
    let renewTimer: ReturnType<typeof setInterval> | undefined;
    let ownershipLost = false;

    const stopRenewal = () => {
      if (renewTimer !== undefined) {
        clearIntervalFn(renewTimer);
        renewTimer = undefined;
      }
    };

    const markOwnershipLost = () => {
      if (ownershipLost) return;
      ownershipLost = true;
      abort.abort();
      stopRenewal();
    };

    try {
      await acquireSyncLease(
        MASTER_SYNC_LOCK_KEY,
        ownerToken,
        leaseMs,
        nowFn(),
        prisma,
      );

      renewTimer = setIntervalFn(() => {
        void (async () => {
          try {
            const renewed = await renewSyncLease(
              MASTER_SYNC_LOCK_KEY,
              ownerToken,
              leaseMs,
              nowFn(),
              prisma,
            );
            if (!renewed) {
              markOwnershipLost();
            }
          } catch {
            markOwnershipLost();
          }
        })();
      }, renewIntervalMs);

      if (typeof renewTimer === "object" && "unref" in renewTimer) {
        renewTimer.unref();
      }

      const result = await runner({
        fullUpgrade,
        signal: abort.signal,
      });
      if (ownershipLost || abort.signal.aborted) {
        throw new SyncLeaseOwnershipLostError();
      }
      resolveCurrent(result);
    } catch (error) {
      if (error instanceof SyncLeaseUnavailableError) {
        rejectCurrent(new SyncAlreadyRunningError());
      } else {
        rejectCurrent(error);
      }
    } finally {
      stopRenewal();
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
