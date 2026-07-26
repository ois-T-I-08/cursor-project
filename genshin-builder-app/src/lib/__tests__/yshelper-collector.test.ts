import { afterEach, describe, expect, it, vi } from "vitest";

import { CanonicalV1YshelperAdapter } from "@/lib/yshelper/adapter";
import { UpstreamFetchError } from "@/lib/api/safe-json-fetch";
import {
  BattleStatsCollectorService,
  readEnabledContentTypes,
  readIntervalDays,
  runBattleStatsCollectorExclusive,
} from "@/lib/yshelper/collector";
import { YshelperSchemaError } from "@/lib/yshelper/schema";
import type {
  BattleStatsRunSummary,
  BattleStatsSnapshotWriteResult,
  BattleStatsStore,
} from "@/lib/yshelper/store";
import type {
  BattleContentType,
  BattleValidationIssue,
  BattleValidationState,
  NormalizedBattleStats,
  YshelperAdapter,
  YshelperTransport,
} from "@/lib/yshelper/types";
import { yshelperCanonicalFixture } from "./fixtures/yshelper-canonical-v1";

describe("BattleStatsCollectorService", () => {
  afterEach(() => vi.restoreAllMocks());

  it("skips before 14 days without calling upstream", async () => {
    const store = new FakeStore();
    store.lastSuccessfulRun = {
      id: "previous",
      finishedAt: new Date("2026-07-20T00:00:00.000Z"),
    };
    const transport = new FakeTransport();
    const service = createService(store, transport, new Date("2026-07-24T00:00:00.000Z"));

    await expect(service.collect()).resolves.toMatchObject({
      status: "skipped",
      reason: "not_due",
      nextEligibleAt: "2026-08-03T00:00:00.000Z",
    });
    expect(transport.calls).toBe(0);
    expect(store.finished.at(-1)?.status).toBe("skipped");
  });

  it("collects enabled content after 14 days and publishes valid snapshots", async () => {
    const store = new FakeStore();
    store.lastSuccessfulRun = {
      id: "previous",
      finishedAt: new Date("2026-07-01T00:00:00.000Z"),
    };
    const transport = new FakeTransport();
    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
    ).collect();

    expect(result.status).toBe("success");
    expect(transport.calls).toBe(2);
    expect(store.saved).toHaveLength(2);
    expect(store.saved.every((item) => item.state === "valid")).toBe(true);
    expect(result.items.every((item) => item.status === "published")).toBe(true);
  });

  it("records suspicious data but does not publish it", async () => {
    const store = new FakeStore();
    const transport = new FakeTransport(
      yshelperCanonicalFixture({
        teams: [],
        characters: [{ characterId: "19999999", usageRate: 0.5 }],
      }),
    );
    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
      ["abyss"],
    ).collect();

    expect(result.status).toBe("invalid");
    expect(result.items[0].status).toBe("suspicious");
    expect(store.saved[0]).toMatchObject({
      state: "suspicious",
      published: false,
    });
  });

  it("keeps the last published value when the upstream fails", async () => {
    const store = new FakeStore();
    store.published.set(
      "abyss",
      new CanonicalV1YshelperAdapter().adapt(
        "abyss",
        yshelperCanonicalFixture(),
      ),
    );
    const transport: YshelperTransport = {
      fetch: vi.fn(async () => {
        throw new Error("private upstream response");
      }),
    };
    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
      ["abyss"],
    ).collect();

    expect(result.status).toBe("failed");
    expect(store.saved).toEqual([]);
    expect(store.published.get("abyss")?.seasonId).toBe("2026-07");
    expect(store.finished.at(-1)?.errorDetail).toBe(
      "abyss:internal_error",
    );
  });

  it("does not create a duplicate snapshot for the same payload", async () => {
    const store = new FakeStore();
    let now = new Date("2026-07-01T00:00:00.000Z");
    const service = new BattleStatsCollectorService(
      store,
      new FakeTransport(),
      new CanonicalV1YshelperAdapter(),
      {
        now: () => now,
        intervalDays: 1,
        enabledContentTypes: () => ["abyss"],
        log: () => undefined,
      },
    );
    expect((await service.collect()).items[0].status).toBe("published");
    now = new Date("2026-07-03T00:00:00.000Z");
    expect((await service.collect()).items[0].status).toBe("duplicate");
    expect(store.saved.filter((item) => !item.duplicate)).toHaveLength(1);
  });

  it("uses 14 days for missing or invalid configuration", () => {
    expect(readIntervalDays({})).toBe(14);
    expect(readIntervalDays({ YSHELPER_SYNC_INTERVAL_DAYS: "0" })).toBe(14);
    expect(readIntervalDays({ YSHELPER_SYNC_INTERVAL_DAYS: "14" })).toBe(14);
  });

  it("keeps collection disabled unless a content type is explicitly true", () => {
    expect(readEnabledContentTypes({})).toEqual([]);
    expect(
      readEnabledContentTypes({
        YSHELPER_ABYSS_ENABLED: "false",
        YSHELPER_STYGIAN_ENABLED: "TRUE",
      }),
    ).toEqual(["stygian"]);
  });

  it("does not call upstream when kill switches stay false", async () => {
    const previousAbyss = process.env.YSHELPER_ABYSS_ENABLED;
    const previousStygian = process.env.YSHELPER_STYGIAN_ENABLED;
    delete process.env.YSHELPER_ABYSS_ENABLED;
    delete process.env.YSHELPER_STYGIAN_ENABLED;
    try {
      await expect(runBattleStatsCollectorExclusive()).resolves.toEqual({
        status: "skipped",
        reason: "disabled",
        items: [],
      });
    } finally {
      if (previousAbyss === undefined) delete process.env.YSHELPER_ABYSS_ENABLED;
      else process.env.YSHELPER_ABYSS_ENABLED = previousAbyss;
      if (previousStygian === undefined) {
        delete process.env.YSHELPER_STYGIAN_ENABLED;
      } else {
        process.env.YSHELPER_STYGIAN_ENABLED = previousStygian;
      }
    }
  });

  it("keeps stygian published when abyss upstream fails", async () => {
    const store = new FakeStore();
    const adapter = new CanonicalV1YshelperAdapter();
    store.published.set(
      "abyss",
      adapter.adapt("abyss", yshelperCanonicalFixture()),
    );
    store.published.set(
      "stygian",
      adapter.adapt("stygian", yshelperCanonicalFixture()),
    );
    const transport: YshelperTransport = {
      fetch: vi.fn(async (contentType) => {
        if (contentType === "abyss") {
          throw new UpstreamFetchError("httpStatus", 500);
        }
        return yshelperCanonicalFixture();
      }),
    };

    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
    ).collect();

    expect(result.status).toBe("failed");
    expect(result.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          contentType: "abyss",
          status: "failed",
          errorCode: "upstream_httpStatus",
        }),
        expect.objectContaining({
          contentType: "stygian",
          status: "published",
        }),
      ]),
    );
    expect(store.published.get("abyss")?.seasonId).toBe("2026-07");
    expect(store.published.get("stygian")?.contentType).toBe("stygian");
    expect(
      store.saved.filter((item) => item.contentType === "abyss"),
    ).toHaveLength(0);
  });

  it("keeps abyss published when stygian upstream fails", async () => {
    const store = new FakeStore();
    const adapter = new CanonicalV1YshelperAdapter();
    store.published.set(
      "abyss",
      adapter.adapt("abyss", yshelperCanonicalFixture()),
    );
    const transport: YshelperTransport = {
      fetch: vi.fn(async (contentType) => {
        if (contentType === "stygian") {
          throw new UpstreamFetchError("timeout");
        }
        return yshelperCanonicalFixture();
      }),
    };

    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
    ).collect();

    expect(result.status).toBe("failed");
    expect(result.items.find((item) => item.contentType === "abyss")?.status).toBe(
      "published",
    );
    expect(
      result.items.find((item) => item.contentType === "stygian"),
    ).toMatchObject({
      status: "failed",
      errorCode: "upstream_timeout",
    });
    expect(store.published.get("abyss")?.seasonId).toBe("2026-07");
  });

  it("does not save a snapshot when native schema adaptation fails", async () => {
    const store = new FakeStore();
    const transport = new FakeTransport();
    const adapter: YshelperAdapter = {
      name: "failing",
      adapt: () => {
        throw new YshelperSchemaError("$.result[0].unresolvedCharacter");
      },
    };
    const result = await new BattleStatsCollectorService(
      store,
      transport,
      adapter,
      {
        now: () => new Date("2026-07-24T00:00:00.000Z"),
        enabledContentTypes: () => ["abyss"],
        log: () => undefined,
      },
    ).collect();

    expect(result.status).toBe("failed");
    expect(result.items[0]).toMatchObject({
      status: "failed",
      errorCode: "invalid_response:$.result[0].unresolvedCharacter",
      recordCount: 0,
    });
    expect(store.saved).toEqual([]);
    expect(store.published.size).toBe(0);
  });

  it("does not publish an empty invalid payload", async () => {
    const store = new FakeStore();
    store.published.set(
      "abyss",
      new CanonicalV1YshelperAdapter().adapt(
        "abyss",
        yshelperCanonicalFixture(),
      ),
    );
    const transport = new FakeTransport(
      yshelperCanonicalFixture({ teams: [], characters: [] }),
    );
    const result = await createService(
      store,
      transport,
      new Date("2026-07-24T00:00:00.000Z"),
      ["abyss"],
    ).collect();

    expect(result.status).toBe("invalid");
    expect(result.items[0].status).toBe("invalid");
    expect(store.saved[0]?.published).toBe(false);
    expect(store.published.get("abyss")?.seasonId).toBe("2026-07");
  });

  it("keeps the previous manifest when snapshot persistence fails", async () => {
    const store = new FakeStore();
    store.published.set(
      "abyss",
      new CanonicalV1YshelperAdapter().adapt(
        "abyss",
        yshelperCanonicalFixture(),
      ),
    );
    store.failNextSave = true;
    const result = await createService(
      store,
      new FakeTransport(),
      new Date("2026-07-24T00:00:00.000Z"),
      ["abyss"],
    ).collect();

    expect(result.status).toBe("failed");
    expect(result.items[0]).toMatchObject({
      status: "failed",
      errorCode: "internal_error",
    });
    expect(store.saved).toEqual([]);
    expect(store.published.get("abyss")?.seasonId).toBe("2026-07");
  });
});

class FakeTransport implements YshelperTransport {
  constructor(
    private readonly payload: Record<string, unknown> =
      yshelperCanonicalFixture(),
  ) {}

  calls = 0;

  async fetch(): Promise<Record<string, unknown>> {
    this.calls++;
    return structuredClone(this.payload);
  }
}

class FakeStore implements BattleStatsStore {
  lastSuccessfulRun: BattleStatsRunSummary | null = null;
  known = new Set(["10000001", "10000002", "10000003", "10000004"]);
  published = new Map<BattleContentType, NormalizedBattleStats>();
  finished: Array<Record<string, unknown>> = [];
  failNextSave = false;
  saved: Array<{
    contentType: BattleContentType;
    hash: string;
    state: BattleValidationState;
    published: boolean;
    duplicate: boolean;
  }> = [];
  private hashes = new Map<string, BattleStatsSnapshotWriteResult>();
  private revision = 0;
  private runCount = 0;

  async findLastSuccessfulRun() {
    return this.lastSuccessfulRun;
  }

  async createRun() {
    return `run-${++this.runCount}`;
  }

  async finishRun(
    runId: string,
    input: {
      status: string;
      finishedAt: Date;
      responseStatus?: number;
      sourceVersion?: string;
      payloadHash?: string;
      recordCount: number;
      validationState: BattleValidationState | "pending";
      validationErrors: BattleValidationIssue[];
      errorCode?: string;
      errorDetail?: string;
    },
  ) {
    this.finished.push({ runId, ...input });
    if (input.status === "success") {
      this.lastSuccessfulRun = { id: runId, finishedAt: input.finishedAt };
    }
  }

  async knownCharacterIds() {
    return this.known;
  }

  async loadPublished(contentType: BattleContentType) {
    return this.published.get(contentType) ?? null;
  }

  async saveSnapshot(
    _runId: string,
    value: NormalizedBattleStats,
    payloadHash: string,
    validationState: BattleValidationState,
  ) {
    if (this.failNextSave) {
      this.failNextSave = false;
      throw new Error("simulated_snapshot_persistence_failure");
    }
    const key = `${value.contentType}:${value.seasonId}:${payloadHash}`;
    const existing = this.hashes.get(key);
    if (existing) {
      this.saved.push({
        contentType: value.contentType,
        hash: payloadHash,
        state: validationState,
        published: existing.published,
        duplicate: true,
      });
      return { ...existing, duplicate: true };
    }
    const result = {
      snapshotId: `snapshot-${++this.revision}`,
      revision: this.revision,
      duplicate: false,
      published: validationState === "valid",
    };
    this.hashes.set(key, result);
    if (result.published) this.published.set(value.contentType, value);
    this.saved.push({
      contentType: value.contentType,
      hash: payloadHash,
      state: validationState,
      published: result.published,
      duplicate: false,
    });
    return result;
  }
}

function createService(
  store: FakeStore,
  transport: YshelperTransport,
  now: Date,
  contentTypes: BattleContentType[] = ["abyss", "stygian"],
) {
  return new BattleStatsCollectorService(
    store,
    transport,
    new CanonicalV1YshelperAdapter(),
    {
      now: () => now,
      enabledContentTypes: () => contentTypes,
      log: () => undefined,
    },
  );
}
