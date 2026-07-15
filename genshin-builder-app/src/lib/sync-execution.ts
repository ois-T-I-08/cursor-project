import { syncMasterData, type SyncResult } from "@/lib/sync";

export class SyncAlreadyRunningError extends Error {
  constructor() {
    super("Master-data sync is already running");
    this.name = "SyncAlreadyRunningError";
  }
}

let activeSync: Promise<SyncResult> | null = null;

/** Shares one in-process lock across the API route and Server Action. */
export async function runSyncExclusive(
  fullUpgrade: boolean,
): Promise<SyncResult> {
  if (activeSync) {
    throw new SyncAlreadyRunningError();
  }

  const current = syncMasterData({ fullUpgrade });
  activeSync = current;
  try {
    return await current;
  } finally {
    if (activeSync === current) {
      activeSync = null;
    }
  }
}
