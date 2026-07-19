import { AzaAbyssStatisticsProvider } from "@/lib/api/abyss/aza-provider";
import { AbyssStatisticsError } from "@/lib/api/abyss/errors";
import type { AbyssStatisticsProvider } from "@/lib/api/abyss/provider";
import { PrismaAbyssStatisticsCacheStore } from "./cache-store";
import type { AbyssStatisticsCacheStore } from "./cache-store";
import type { AbyssStatistics, AbyssStatisticsErrorCode } from "./types";

const DEFAULT_TTL_SECONDS = 21_600;

type LogDetails = Partial<{
  sourceApiVersion: string;
  scheduleId: number;
  itemCount: number;
  missingField: string;
  invalidField: string;
  durationMs: number;
  cacheState: string;
  fallbackUsed: boolean;
}>;
type Logger = (event: string, details: LogDetails) => void;

export class AbyssStatisticsService {
  // processLocalSingleFlight: 同一Node.jsプロセス内の同時更新だけを共有する。
  // 複数インスタンス間の排他は運用上の更新頻度を確認してから再評価する。
  private inFlight: Promise<AbyssStatistics> | null = null;

  constructor(
    private readonly provider: AbyssStatisticsProvider,
    private readonly cache: AbyssStatisticsCacheStore,
    private readonly options: {
      now?: () => Date;
      ttlSeconds?: number;
      enabled?: () => boolean;
      log?: Logger;
    } = {},
  ) {}

  async load(): Promise<AbyssStatistics> {
    const now = (this.options.now ?? (() => new Date()))();
    const cached = await this.readCache();

    if (!(this.options.enabled ?? isFeatureEnabled)()) {
      this.log("feature_disabled", {
        cacheState: cached === null ? "missing" : "available",
        fallbackUsed: cached !== null,
      });
      if (cached !== null) {
        return stale(cached, "featureDisabled");
      }
      throw new AbyssStatisticsError("featureDisabled");
    }

    if (cached !== null && Date.parse(cached.metadata.expiresAt) > now.getTime()) {
      this.log("cache_hit", {
        cacheState: "fresh",
        itemCount: cached.characters.length + cached.teams.length,
        fallbackUsed: false,
      });
      return fresh(cached);
    }

    this.log(cached === null ? "cache_miss" : "cache_expired", {
      cacheState: cached === null ? "missing" : "expired",
      fallbackUsed: false,
    });
    if (this.inFlight !== null) {
      this.log("request_deduplicated", {
        cacheState: "refreshing",
        fallbackUsed: false,
      });
      return this.inFlight;
    }

    this.inFlight = this.refresh(cached, now);
    try {
      return await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }

  private async refresh(
    cached: AbyssStatistics | null,
    startedAt: Date,
  ): Promise<AbyssStatistics> {
    const started = Date.now();
    try {
      const snapshot = await this.provider.fetchStatistics();
      const ttlSeconds = this.options.ttlSeconds ?? readTtlSeconds();
      const value: AbyssStatistics = {
        ...snapshot,
        metadata: {
          ...snapshot.metadata,
          fetchedAt: startedAt.toISOString(),
          expiresAt: new Date(
            startedAt.getTime() + ttlSeconds * 1_000,
          ).toISOString(),
          isStale: false,
        },
      };
      await this.writeCache(value);
      this.log("fetch_success", {
        durationMs: Date.now() - started,
        sourceApiVersion: value.version.sourceApiVersion,
        scheduleId: value.version.scheduleId,
        itemCount: value.characters.length + value.teams.length,
        cacheState: "refreshed",
        fallbackUsed: false,
      });
      return value;
    } catch (error) {
      const safeError = error instanceof AbyssStatisticsError
        ? error
        : new AbyssStatisticsError("unknownError");
      this.log("fetch_failed", {
        durationMs: Date.now() - started,
        invalidField: safeError.code,
        cacheState: cached === null ? "missing" : "expired",
        fallbackUsed: cached !== null,
      });
      if (cached !== null) return stale(cached, safeError.code);
      throw safeError;
    }
  }

  private async readCache(): Promise<AbyssStatistics | null> {
    try {
      return await this.cache.read();
    } catch {
      this.log("cache_read_failed", {
        cacheState: "read_failed",
        fallbackUsed: false,
      });
      return null;
    }
  }

  private async writeCache(value: AbyssStatistics): Promise<void> {
    try {
      await this.cache.write(value);
    } catch {
      this.log("cache_write_failed", {
        cacheState: "write_failed",
        fallbackUsed: false,
      });
    }
  }

  private log(event: string, details: LogDetails): void {
    const logger = this.options.log ?? defaultLogger;
    logger(event, details);
  }
}

let defaultService: AbyssStatisticsService | undefined;

export function getAbyssStatisticsService(): AbyssStatisticsService {
  defaultService ??= new AbyssStatisticsService(
    new AzaAbyssStatisticsProvider(),
    new PrismaAbyssStatisticsCacheStore(),
  );
  return defaultService;
}

function fresh(value: AbyssStatistics): AbyssStatistics {
  return {
    ...value,
    metadata: {
      ...value.metadata,
      isStale: false,
      warningCode: undefined,
      upstreamErrorCode: undefined,
    },
  };
}

function stale(
  value: AbyssStatistics,
  code: Exclude<AbyssStatisticsErrorCode, "staleCache">,
): AbyssStatistics {
  return {
    ...value,
    metadata: {
      ...value.metadata,
      isStale: true,
      warningCode: "staleCache",
      upstreamErrorCode: code,
    },
  };
}

function isFeatureEnabled(): boolean {
  return process.env.AZA_ABYSS_ENABLED?.trim().toLowerCase() !== "false";
}

function readTtlSeconds(): number {
  const value = process.env.AZA_CACHE_TTL_SECONDS?.trim();
  if (!value) return DEFAULT_TTL_SECONDS;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 300 && parsed <= 86_400
    ? parsed
    : DEFAULT_TTL_SECONDS;
}

function defaultLogger(event: string, details: LogDetails): void {
  console.info("abyss_statistics", { event, ...details });
}
