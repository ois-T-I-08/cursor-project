import "server-only";

const DEFAULT_WINDOW_MS = 60_000;
const DEFAULT_MAX_REQUESTS = 10;

/** スコープ別上限。構造化編集は overview / master / save / preview が連続するため緩和。 */
const SCOPE_LIMITS: Record<string, { windowMs: number; max: number }> = {
  "build-guides": { windowMs: 60_000, max: 120 },
  "team-templates": { windowMs: 60_000, max: 10 },
};

type WindowState = { startedAt: number; count: number };

const buckets = new Map<string, Map<string, WindowState>>();

/**
 * Per-scope IP rate limit.
 * Scope isolates team-templates vs build-guides counters.
 */
export function allowAdminRequest(
  request: Request,
  scope: string,
  now = Date.now(),
): boolean {
  const limits = SCOPE_LIMITS[scope] ?? {
    windowMs: DEFAULT_WINDOW_MS,
    max: DEFAULT_MAX_REQUESTS,
  };
  const forwarded = request.headers.get("x-forwarded-for");
  const first = forwarded?.split(",", 1)[0]?.trim();
  const key = first && first.length <= 64 ? first : "unknown";
  let windows = buckets.get(scope);
  if (!windows) {
    windows = new Map();
    buckets.set(scope, windows);
  }
  const current = windows.get(key);
  if (!current || now - current.startedAt >= limits.windowMs) {
    windows.set(key, { startedAt: now, count: 1 });
    if (windows.size > 100) prune(windows, now, limits.windowMs);
    return true;
  }
  if (current.count >= limits.max) return false;
  current.count++;
  return true;
}

function prune(
  windows: Map<string, WindowState>,
  now: number,
  windowMs: number,
): void {
  for (const [key, value] of windows) {
    if (now - value.startedAt >= windowMs) windows.delete(key);
  }
}

export function resetAdminRateLimitForTest(scope?: string): void {
  if (scope) {
    buckets.delete(scope);
    return;
  }
  buckets.clear();
}
