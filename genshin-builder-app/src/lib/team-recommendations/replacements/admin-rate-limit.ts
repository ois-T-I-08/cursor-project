import "server-only";

const WINDOW_MS = 60_000;
const MAX_REQUESTS = 10;
const windows = new Map<string, { startedAt: number; count: number }>();

export function allowTemplateAdminRequest(request: Request, now = Date.now()): boolean {
  const forwarded = request.headers.get("x-forwarded-for");
  const first = forwarded?.split(",", 1)[0]?.trim();
  const key = first && first.length <= 64 ? first : "unknown";
  const current = windows.get(key);
  if (!current || now - current.startedAt >= WINDOW_MS) {
    windows.set(key, { startedAt: now, count: 1 });
    if (windows.size > 100) prune(now);
    return true;
  }
  if (current.count >= MAX_REQUESTS) return false;
  current.count++;
  return true;
}

function prune(now: number): void {
  for (const [key, value] of windows) {
    if (now - value.startedAt >= WINDOW_MS) windows.delete(key);
  }
}

export function resetTemplateAdminRateLimitForTest(): void {
  windows.clear();
}
