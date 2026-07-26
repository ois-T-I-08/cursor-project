import { afterEach, describe, expect, it } from "vitest";

import { createBattleStatsManifestGet } from "@/app/api/battle-statistics/manifest/route";
import { createBattleStatsBundleGet } from "@/app/api/battle-statistics/bundle/route";
import { createBattleStatsTeamsGet } from "@/app/api/battle-statistics/teams/route";
import { createYshelperCollectPost } from "@/app/api/internal/yshelper/collect/route";
import { encodeCursor } from "@/lib/yshelper/publication";
import { resetBattleStatsRateLimitForTest } from "@/lib/yshelper/rate-limit";
import { resetSyncRateLimitForTest } from "@/lib/sync-rate-limit";

describe("battle statistics routes", () => {
  afterEach(() => {
    resetBattleStatsRateLimitForTest();
    resetSyncRateLimitForTest();
  });

  it("retires the HTTP collect route without fetching upstream", async () => {
    const post = createYshelperCollectPost();
    const response = await post(
      new Request("https://example.test/api/internal/yshelper/collect", {
        method: "POST",
      }),
    );
    const body = await response.json();
    expect(response.status).toBe(410);
    expect(body.error.code).toBe("collector_moved");
    expect(JSON.stringify(body)).not.toContain("YSHELPER_API");
  });

  it("returns ETag and 304 without a response body", async () => {
    const loader = async () => ({
      data: {
        schemaVersion: 1 as const,
        abyss: null,
        stygian: null,
      },
      etag: '"sha256-fixture"',
    });
    const get = createBattleStatsManifestGet(loader);
    const initial = await get(
      new Request("https://example.test/api/v1/battle-statistics/manifest"),
    );
    expect(initial.status).toBe(200);
    expect(initial.headers.get("etag")).toBe('"sha256-fixture"');

    const unchanged = await get(
      new Request("https://example.test/api/v1/battle-statistics/manifest", {
        headers: { "if-none-match": '"sha256-fixture"' },
      }),
    );
    expect(unchanged.status).toBe(304);
    expect(await unchanged.text()).toBe("");
  });

  it("validates bundle revision and forwards a bounded page", async () => {
    let received: Record<string, unknown> | undefined;
    const get = createBattleStatsBundleGet(async (input) => {
      received = input;
      return {
        schemaVersion: 1,
        source: "YShelper" as const,
        contentType: input.contentType,
        sourceVersion: "fixture",
        seasonId: "season",
        revision: input.revision,
        payloadHash: `sha256:${"0".repeat(64)}`,
        sourceUpdatedAt: "2026-07-24T00:00:00.000Z",
        sampleSize: null,
        metadata: {},
        page: input.page,
        pageCount: 1,
        teams: [],
        characters: [],
      };
    });
    const response = await get(
      new Request(
        "https://example.test/api/battle-statistics/bundle?type=abyss&revision=2&page=3",
      ),
    );
    expect(response.status).toBe(200);
    expect(received).toEqual({
      contentType: "abyss",
      revision: 2,
      page: 3,
    });

    resetBattleStatsRateLimitForTest();
    const missingRevision = await get(
      new Request(
        "https://example.test/api/battle-statistics/bundle?type=abyss",
      ),
    );
    expect(missingRevision.status).toBe(400);
  });

  it("uses opaque cursors and rejects unbounded team queries", async () => {
    let received: Record<string, unknown> | undefined;
    const get = createBattleStatsTeamsGet(async (input) => {
      received = input;
      return {
        revision: 1,
        seasonId: "season",
        items: [],
        nextCursor: null,
      };
    });
    const cursor = encodeCursor("clabcdefghi");
    const response = await get(
      new Request(
        `https://example.test/api/battle-statistics/teams?type=stygian&limit=100&cursor=${cursor}&characterId=10000001`,
      ),
    );
    expect(response.status).toBe(200);
    expect(received).toMatchObject({
      contentType: "stygian",
      limit: 100,
      cursor: "clabcdefghi",
      characterId: "10000001",
    });

    resetBattleStatsRateLimitForTest();
    const tooLarge = await get(
      new Request(
        "https://example.test/api/battle-statistics/teams?type=abyss&limit=101",
      ),
    );
    expect(tooLarge.status).toBe(400);
  });
});
