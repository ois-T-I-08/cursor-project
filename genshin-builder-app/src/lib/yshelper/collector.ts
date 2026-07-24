import { createHash, randomUUID, timingSafeEqual } from "node:crypto";

import { UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import { prisma } from "@/lib/db";
import {
  releaseSyncLease,
  tryAcquireSyncLease,
} from "@/lib/sync-distributed-lock";
import {
  configuredYshelperAdapter,
  YshelperAdapterNotConfiguredError,
} from "./adapter";
import {
  YshelperClientConfigurationError,
  YshelperHttpClient,
} from "./client";
import { hashBattleStats } from "./hash";
import { YshelperSchemaError } from "./schema";
import {
  PrismaBattleStatsStore,
  type BattleStatsStore,
} from "./store";
import {
  BATTLE_CONTENT_TYPES,
  type BattleContentType,
  type BattleValidationIssue,
  type BattleValidationState,
  type YshelperAdapter,
  type YshelperTransport,
} from "./types";
import {
  publishableBattleStats,
  validateBattleStats,
} from "./validate";

const COLLECTOR_LOCK_KEY = "yshelper-battle-statistics";
const COLLECTOR_LEASE_MS = 10 * 60_000;
const DAY_MS = 86_400_000;

export interface BattleStatsCollectItemResult {
  contentType: BattleContentType;
  status:
    | "published"
    | "duplicate"
    | "suspicious"
    | "invalid"
    | "stale"
    | "failed";
  revision?: number;
  payloadHash?: string;
  recordCount: number;
  errorCode?: string;
}

export interface BattleStatsCollectResult {
  status: "success" | "skipped" | "invalid" | "failed";
  reason?: "not_due" | "disabled";
  nextEligibleAt?: string;
  items: BattleStatsCollectItemResult[];
}

export class BattleStatsCollectorAlreadyRunningError extends Error {
  constructor() {
    super("battle_stats_collector_already_running");
    this.name = "BattleStatsCollectorAlreadyRunningError";
  }
}

export class BattleStatsCollectorService {
  constructor(
    private readonly store: BattleStatsStore,
    private readonly transport: YshelperTransport,
    private readonly adapter: YshelperAdapter,
    private readonly options: {
      now?: () => Date;
      intervalDays?: number;
      enabledContentTypes?: () => BattleContentType[];
      log?: (
        event: string,
        details: Record<string, string | number | boolean | undefined>,
      ) => void;
    } = {},
  ) {}

  async collect(): Promise<BattleStatsCollectResult> {
    const now = (this.options.now ?? (() => new Date()))();
    const contentTypes = (
      this.options.enabledContentTypes ?? enabledContentTypes
    )();
    const previousRun = await this.store.findLastSuccessfulRun();
    const runId = await this.store.createRun(
      contentTypes,
      previousRun?.id ?? null,
      previousRun?.finishedAt ?? null,
      now,
    );

    if (contentTypes.length === 0) {
      await this.store.finishRun(runId, {
        status: "skipped",
        finishedAt: now,
        recordCount: 0,
        validationState: "pending",
        validationErrors: [],
        errorCode: "disabled",
      });
      return { status: "skipped", reason: "disabled", items: [] };
    }

    const intervalDays =
      this.options.intervalDays ?? readIntervalDays(process.env);
    const nextEligibleAt = previousRun
      ? new Date(previousRun.finishedAt.getTime() + intervalDays * DAY_MS)
      : null;
    if (nextEligibleAt && nextEligibleAt.getTime() > now.getTime()) {
      await this.store.finishRun(runId, {
        status: "skipped",
        finishedAt: now,
        recordCount: 0,
        validationState: "pending",
        validationErrors: [],
        errorCode: "not_due",
      });
      return {
        status: "skipped",
        reason: "not_due",
        nextEligibleAt: nextEligibleAt.toISOString(),
        items: [],
      };
    }

    const knownCharacterIds = await this.store.knownCharacterIds();
    const items: BattleStatsCollectItemResult[] = [];
    const allIssues: BattleValidationIssue[] = [];
    const hashes: string[] = [];
    const versions: string[] = [];
    let responseStatus: number | undefined;
    const started = Date.now();

    for (const contentType of contentTypes) {
      try {
        const raw = await this.transport.fetch(contentType);
        const normalized = this.adapter.adapt(contentType, raw);
        const previous = await this.store.loadPublished(contentType);
        const validation = validateBattleStats(
          normalized,
          knownCharacterIds,
          previous,
        );
        const publicValue = publishableBattleStats(validation.value);
        const payloadHash = hashBattleStats(publicValue);
        const saved = await this.store.saveSnapshot(
          runId,
          validation.value,
          payloadHash,
          validation.state,
          validation.issues,
          now,
        );
        const recordCount =
          validation.value.teams.length + validation.value.characters.length;
        allIssues.push(...validation.issues);
        hashes.push(payloadHash);
        versions.push(validation.value.sourceVersion);
        items.push({
          contentType,
          status:
            validation.state === "valid"
              ? saved.published
                ? saved.duplicate
                  ? "duplicate"
                  : "published"
                : "suspicious"
              : validation.state,
          revision: saved.revision,
          payloadHash,
          recordCount,
        });
        this.log("battle_stats_collect_item", {
          sourceApiVersion: normalized.sourceVersion,
          itemCount: recordCount,
          invalidField: validation.issues[0]?.field,
          durationMs: Date.now() - started,
          cacheState: saved.duplicate ? "duplicate" : "new_snapshot",
          fallbackUsed: false,
        });
      } catch (error) {
        const failure = safeFailure(error);
        responseStatus ??= failure.responseStatus;
        items.push({
          contentType,
          status: "failed",
          recordCount: 0,
          errorCode: failure.code,
        });
        this.log("battle_stats_collect_failed", {
          invalidField: failure.code,
          durationMs: Date.now() - started,
          cacheState: "unchanged",
          fallbackUsed: true,
        });
      }
    }

    const hasFailure = items.some((item) => item.status === "failed");
    const validationState = hasFailure
      ? "invalid"
      : aggregateValidationState(items);
    const status = hasFailure
      ? "failed"
      : validationState === "valid"
        ? "success"
        : "invalid";
    await this.store.finishRun(runId, {
      status,
      finishedAt: now,
      responseStatus,
      sourceVersion: versions.length > 0 ? [...new Set(versions)].join(",") : undefined,
      payloadHash: combinedHash(hashes),
      recordCount: items.reduce((sum, item) => sum + item.recordCount, 0),
      validationState,
      validationErrors: allIssues,
      errorCode: hasFailure ? "partial_or_total_failure" : undefined,
      errorDetail: hasFailure
        ? items
            .filter((item) => item.errorCode)
            .map((item) => `${item.contentType}:${item.errorCode}`)
            .join(",")
        : undefined,
    });
    return { status, items };
  }

  private log(
    event: string,
    details: Record<string, string | number | boolean | undefined>,
  ): void {
    (this.options.log ?? defaultLog)(event, details);
  }
}

let activeCollector: Promise<BattleStatsCollectResult> | null = null;

export async function runBattleStatsCollectorExclusive(
  serviceFactory: () => BattleStatsCollectorService = defaultService,
): Promise<BattleStatsCollectResult> {
  if (
    serviceFactory === defaultService &&
    readEnabledContentTypes(process.env).length === 0
  ) {
    return { status: "skipped", reason: "disabled", items: [] };
  }
  if (activeCollector) throw new BattleStatsCollectorAlreadyRunningError();
  const service = serviceFactory();
  const ownerToken = randomUUID();
  const current = (async () => {
    const acquired = await tryAcquireSyncLease(
      COLLECTOR_LOCK_KEY,
      ownerToken,
      COLLECTOR_LEASE_MS,
      Date.now(),
      prisma,
    );
    if (!acquired) throw new BattleStatsCollectorAlreadyRunningError();
    try {
      return await service.collect();
    } finally {
      await releaseSyncLease(COLLECTOR_LOCK_KEY, ownerToken, prisma).catch(
        () => false,
      );
    }
  })();
  activeCollector = current;
  try {
    return await current;
  } finally {
    if (activeCollector === current) activeCollector = null;
  }
}

export function authorizeYshelperCollector(request: Request): boolean {
  const configured = process.env.YSHELPER_COLLECT_SECRET;
  const authorization = request.headers.get("authorization");
  if (
    !configured ||
    !authorization?.startsWith("Bearer ") ||
    authorization.includes(",")
  ) {
    return false;
  }
  const supplied = authorization.slice("Bearer ".length);
  if (!supplied || supplied.trim() !== supplied || /\s/.test(supplied)) {
    return false;
  }
  const expectedBytes = Buffer.from(configured);
  const suppliedBytes = Buffer.from(supplied);
  return expectedBytes.length === suppliedBytes.length &&
    timingSafeEqual(expectedBytes, suppliedBytes);
}

export function resetBattleStatsCollectorForTest(): void {
  activeCollector = null;
}

function defaultService(): BattleStatsCollectorService {
  const contentTypes = readEnabledContentTypes(process.env);
  const adapter: YshelperAdapter =
    contentTypes.length === 0
      ? {
          name: "disabled",
          adapt: () => {
            throw new YshelperAdapterNotConfiguredError();
          },
        }
      : configuredYshelperAdapter();
  return new BattleStatsCollectorService(
    new PrismaBattleStatsStore(),
    new YshelperHttpClient(),
    adapter,
    { enabledContentTypes: () => contentTypes },
  );
}

export function readEnabledContentTypes(
  env: Readonly<Record<string, string | undefined>>,
): BattleContentType[] {
  return BATTLE_CONTENT_TYPES.filter((contentType) => {
    const key =
      contentType === "abyss"
        ? "YSHELPER_ABYSS_ENABLED"
        : "YSHELPER_STYGIAN_ENABLED";
    return env[key]?.trim().toLowerCase() === "true";
  });
}

function enabledContentTypes(): BattleContentType[] {
  return readEnabledContentTypes(process.env);
}

export function readIntervalDays(
  env: Readonly<Record<string, string | undefined>>,
): number {
  const parsed = Number(env.YSHELPER_SYNC_INTERVAL_DAYS);
  return Number.isSafeInteger(parsed) && parsed >= 1 && parsed <= 90
    ? parsed
    : 14;
}

function aggregateValidationState(
  items: BattleStatsCollectItemResult[],
): BattleValidationState {
  if (items.some((item) => item.status === "invalid")) return "invalid";
  if (items.some((item) => item.status === "suspicious")) return "suspicious";
  if (items.some((item) => item.status === "stale")) return "stale";
  return "valid";
}

function combinedHash(hashes: string[]): string | undefined {
  if (hashes.length === 0) return undefined;
  if (hashes.length === 1) return hashes[0];
  return `sha256:${createHash("sha256")
    .update([...hashes].sort().join("|"))
    .digest("hex")}`;
}

function safeFailure(error: unknown): {
  code: string;
  responseStatus?: number;
} {
  if (error instanceof UpstreamFetchError) {
    return { code: `upstream_${error.code}`, responseStatus: error.status };
  }
  if (error instanceof YshelperSchemaError) {
    return { code: "invalid_response" };
  }
  if (
    error instanceof YshelperAdapterNotConfiguredError ||
    error instanceof YshelperClientConfigurationError
  ) {
    return { code: "not_configured" };
  }
  return { code: "internal_error" };
}

function defaultLog(
  event: string,
  details: Record<string, string | number | boolean | undefined>,
): void {
  console.info("battle_statistics", { event, ...details });
}
