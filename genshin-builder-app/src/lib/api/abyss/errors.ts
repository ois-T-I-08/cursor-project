import type { AbyssStatisticsErrorCode } from "@/lib/abyss/types";

export class AbyssStatisticsError extends Error {
  constructor(
    readonly code: Exclude<AbyssStatisticsErrorCode, "staleCache">,
    readonly upstreamStatus?: number,
    /** Safe diagnostic token for server logs only (never returned to clients). */
    readonly diagnostic?: string,
  ) {
    super(`abyss_statistics_${code}`);
    this.name = "AbyssStatisticsError";
  }
}
