const WINDOW_MS = 60_000;
const MAX_REQUESTS = 120;
const windows = new Map<string, { startedAt: number; count: number }>();

export function allowBattleStatsPublicRequest(
  request: Request,
  now = Date.now(),
): boolean {
  const forwarded = request.headers.get("x-forwarded-for");
  const address = forwarded?.split(",", 1)[0]?.trim();
  const key = address && address.length <= 64 ? address : "unknown";
  const current = windows.get(key);
  if (!current || now - current.startedAt >= WINDOW_MS) {
    windows.set(key, { startedAt: now, count: 1 });
    prune(now);
    return true;
  }
  if (current.count >= MAX_REQUESTS) return false;
  current.count++;
  return true;
}

export function resetBattleStatsRateLimitForTest(): void {
  windows.clear();
}

function prune(now: number): void {
  if (windows.size < 1_000) return;
  for (const [key, value] of windows) {
    if (now - value.startedAt >= WINDOW_MS) windows.delete(key);
  }
}
