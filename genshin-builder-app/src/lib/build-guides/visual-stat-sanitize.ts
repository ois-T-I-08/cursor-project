import { guideStatKeySchema, STAT_KEYS, type GuideStatKey } from "./visual-schemas";

const STAT_KEY_SET = new Set<string>(STAT_KEYS);

/**
 * Normalize statPriority lists from provider / persisted payloads.
 * Rejects String(object) → "[object Object]" (QPj post-process root cause).
 */
export function sanitizeStatPriority(raw: unknown): GuideStatKey[] {
  if (!Array.isArray(raw)) return [];
  const out: GuideStatKey[] = [];
  for (const item of raw.slice(0, 20)) {
    let candidate: unknown = item;
    if (item && typeof item === "object" && !Array.isArray(item)) {
      const rec = item as Record<string, unknown>;
      candidate = rec.statKey ?? rec.key ?? rec.stat ?? "";
    }
    if (typeof candidate !== "string" && typeof candidate !== "number") continue;
    const key = String(candidate).trim();
    if (!key || key === "[object Object]") continue;
    const parsed = guideStatKeySchema.safeParse(key);
    if (!parsed.success) {
      if (!STAT_KEY_SET.has(key)) continue;
      // Unreachable if STAT_KEYS matches schema; keep fail-closed.
      continue;
    }
    if (!out.includes(parsed.data)) out.push(parsed.data);
  }
  return out.slice(0, 10);
}
