import type { AbyssStatisticsSnapshot } from "@/lib/abyss/types";

export interface AbyssStatisticsProvider {
  readonly name: string;
  fetchStatistics(): Promise<AbyssStatisticsSnapshot>;
}
