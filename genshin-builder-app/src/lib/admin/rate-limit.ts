import "server-only";

const WINDOW_MS = 60_000;
const MAX_REQUESTS = 10;

type WindowState = { startedAt: number; count: number };

const buckets = new Map<string, Map<string, WindowState>>();

/**
 * Per-scope IP rate limit (default 10 req / 60s).
 * Scope isolates team-templates vs build-guides counters.
 */
export function allowAdminRequest(
  request: Request,
  scope: string,
  now = Date.now(),
): boolean {
  const forwarded = request.headers.get("x-forwarded-for");
  const first = forwarded?.split(",", 1)[0]?.trim();
  const key = first && first.length <= 64 ? first : "unknown";
  let windows = buckets.get(scope);
  if (!windows) {
    windows = new Map();
    buckets.set(scope, windows);
  }
  const current = windows.get(key);
  if (!current || now - current.startedAt >= WINDOW_MS) {
    windows.set(key, { startedAt: now, count: 1 });
    if (windows.size > 100) prune(windows, now);
    return true;
  }
  if (current.count >= MAX_REQUESTS) return false;
  current.count++;
  return true;
}

function prune(windows: Map<string, WindowState>, now: number): void {
  for (const [key, value] of windows) {
    if (now - value.startedAt >= WINDOW_MS) windows.delete(key);
  }
}

export function resetAdminRateLimitForTest(scope?: string): void {
  if (scope) {
    buckets.delete(scope);
    return;
  }
  buckets.clear();
}
