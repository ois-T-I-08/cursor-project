const WINDOW_MS = 60_000;
const MAX_REQUESTS = 5;

interface RateWindow {
  startedAt: number;
  count: number;
}

const windows = new Map<string, RateWindow>();

export function allowSyncRequest(
  key: string,
  now = Date.now(),
): boolean {
  const current = windows.get(key);
  if (!current || now - current.startedAt >= WINDOW_MS) {
    windows.set(key, { startedAt: now, count: 1 });
    pruneExpired(now);
    return true;
  }
  if (current.count >= MAX_REQUESTS) return false;
  current.count++;
  return true;
}

export function syncRateLimitKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  const first = forwarded?.split(",", 1)[0]?.trim();
  return first && first.length <= 64 ? first : "unknown";
}

function pruneExpired(now: number): void {
  if (windows.size < 100) return;
  for (const [key, value] of windows) {
    if (now - value.startedAt >= WINDOW_MS) windows.delete(key);
  }
}

export function resetSyncRateLimitForTest(): void {
  windows.clear();
}
