import type { AbyssStatisticsErrorCode } from "@/lib/abyss/types";

export class AbyssStatisticsError extends Error {
  constructor(
    readonly code: Exclude<AbyssStatisticsErrorCode, "staleCache">,
    readonly upstreamStatus?: number,
  ) {
    super(`abyss_statistics_${code}`);
    this.name = "AbyssStatisticsError";
  }
}
