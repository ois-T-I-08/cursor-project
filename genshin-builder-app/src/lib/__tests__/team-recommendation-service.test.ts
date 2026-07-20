import { describe, expect, it, vi } from "vitest";
import { TeamRecommendationService } from "@/lib/team-recommendations/service";
import type { GcsimRunner } from "@/lib/team-recommendations/gcsim-runner";
import type { TeamRecommendationSettings } from "@/lib/team-recommendations/settings";
import type { SimulationCacheEntry, SimulationStore } from "@/lib/team-recommendations/store";
import type { GcsimRunResult, JobStatus, TeamRecommendationJob, TeamRecommendationRequest, TeamRecommendationResult } from "@/lib/team-recommendations/types";
import type { AbyssStatistics } from "@/lib/abyss/types";

const now = new Date("2026-07-20T00:00:00Z");
const request: TeamRecommendationRequest = {
  attackerId: "10000089", mode: "spiralAbyss", half: "upper", ownedOnly: true, enemy: "single", preference: "damage",
  characters: [
    build("10000089", "11513"), build("10000087", "14514"), build("10000025", "11401"), build("10000054", "14401"),
  ],
};
const run: GcsimRunResult = { estimatedDps: 70000, iterations: 1000, reactions: {}, endingEnergy: [40, 60, 50, 70] };

describe("TeamRecommendationService", () => {
  it("completes a gcsim job and stores only successful cache values", async () => {
    const store = new MemoryStore();
    const runner = { run: vi.fn(async () => run) };
    const service = createService(store, runner, true);
    const queued = await service.enqueue(request);
    await service.waitForLocalJob(queued.jobId);
    const completed = await service.get(queued.jobId);
    expect(completed?.status).toBe("completed");
    expect(completed?.result?.recommendations[0]).toMatchObject({ simulationStatus: "simulated", estimatedDps: 70000, isStale: false });
    expect(store.cacheWrites).toBe(1);
  });

  it("uses observed/rule recommendations when kill switch is off without calling runner", async () => {
    const store = new MemoryStore();
    const runner = { run: vi.fn(async () => run) };
    const service = createService(store, runner, false);
    const job = await service.enqueue(request);
    await service.waitForLocalJob(job.jobId);
    expect(runner.run).not.toHaveBeenCalled();
    const result = await service.get(job.jobId);
    expect(result?.result?.warning).toBe("gcsimUnavailable");
    expect(result?.result?.recommendations[0].simulationStatus).toBe("observed");
  });

  it("uses stale last-success cache after gcsim failure and never overwrites it", async () => {
    const store = new MemoryStore({ value: run, expiresAt: new Date(now.getTime() - 1000) });
    const runner = { run: vi.fn(async () => { throw new Error("upstream body must not escape"); }) };
    const service = createService(store, runner, true);
    const job = await service.enqueue(request);
    await service.waitForLocalJob(job.jobId);
    const result = await service.get(job.jobId);
    expect(result?.result?.warning).toBe("staleSimulation");
    expect(result?.result?.recommendations[0]).toMatchObject({ estimatedDps: 70000, isCached: true, isStale: true });
    expect(store.cacheWrites).toBe(0);
  });

  it("deduplicates identical active/completed requests", async () => {
    const store = new MemoryStore();
    const service = createService(store, { run: async () => run }, false);
    const [first, concurrent] = await Promise.all([service.enqueue(request), service.enqueue(request)]);
    expect(concurrent.jobId).toBe(first.jobId);
    await service.waitForLocalJob(first.jobId);
    const second = await service.enqueue(request);
    expect(second.jobId).toBe(first.jobId);
    expect(store.createdJobs).toBe(1);
  });

  it("bounds process-local active jobs", async () => {
    let finishRun: (() => void) | undefined;
    const runner = {
      run: vi.fn(() => new Promise<GcsimRunResult>((resolve) => {
        finishRun = () => resolve(run);
      })),
    };
    const store = new MemoryStore();
    const service = new TeamRecommendationService(
      store,
      runner,
      async () => abyss(),
      settings(true, { maxActiveJobs: 1 }),
      { now: () => now, log: () => undefined },
    );
    const first = await service.enqueue(request);
    await vi.waitFor(() => expect(runner.run).toHaveBeenCalled());
    await expect(service.enqueue({ ...request, preference: "built" })).rejects.toThrow("jobCapacityExceeded");
    finishRun?.();
    await service.waitForLocalJob(first.jobId);
  });

  it("purges caches only after one additional stale-retention TTL", async () => {
    const store = new MemoryStore();
    const service = createService(store, { run: async () => run }, false);
    const job = await service.enqueue(request);
    await service.waitForLocalJob(job.jobId);
    expect(store.cacheCleanupBefore?.toISOString()).toBe("2026-07-19T00:00:00.000Z");
  });

  it("logs only safe job metadata", async () => {
    const events: unknown[] = [];
    const service = new TeamRecommendationService(new MemoryStore(), { run: async () => run }, async () => abyss(), settings(false), {
      now: () => now,
      log: (event, details) => events.push({ event, ...details }),
    });
    const job = await service.enqueue(request);
    await service.waitForLocalJob(job.jobId);
    const serialized = JSON.stringify(events).toLowerCase();
    expect(serialized).not.toMatch(/cookie|uid|database_url|config_file|secret/);
    expect(serialized).toContain("attackerid");
  });
});

function createService(store: MemoryStore, runner: GcsimRunner, enabled: boolean) {
  return new TeamRecommendationService(store, runner, async () => abyss(), settings(enabled), { now: () => now, log: () => undefined });
}
function settings(enabled: boolean, overrides: Partial<TeamRecommendationSettings> = {}): TeamRecommendationSettings {
  return { enabled, maxCandidates: 20, maxConcurrency: 2, maxActiveJobs: 8, timeoutMs: 1000, iterations: 1000, cacheTtlSeconds: 86400, jobTtlSeconds: 86400, maxConfigBytes: 65536, maxOutputBytes: 2097152, durationSeconds: 90, ...overrides };
}
function build(characterId: string, weaponId: string): TeamRecommendationRequest["characters"][number] {
  return { characterId, element: "hydro", rarity: 5, isOwned: true, level: 90, ascension: 6, constellation: 0,
    talents: { normal: 9, skill: 9, burst: 9 }, weapon: { weaponId, level: 90, ascension: 6, refinement: 1 }, artifacts: { sets: [], stats: {} }, inputQuality: "exact", defaultedFields: [] };
}
function abyss(): AbyssStatistics {
  return {
    version: { scheduleId: 1, periodStart: now.toISOString(), periodEnd: now.toISOString(), sourceApiVersion: "5.6" },
    metadata: { source: "AZA.GG", fetchedAt: now.toISOString(), expiresAt: new Date(now.getTime() + 1000).toISOString(), sourceUpdatedAt: now.toISOString(), isStale: false, sampleSize: 1, referenceSampleSize: 1, collectionProgress: 1 },
    characters: [], teams: [{ half: "upper", members: request.characters.map((value) => value.characterId), usageRate: 0.1, ownershipRate: 0.2, usageAmongOwnersRate: 0.5 }],
  };
}

class MemoryStore implements SimulationStore {
  readonly jobs = new Map<string, { job: TeamRecommendationJob; hash: string; expiresAt: Date }>();
  cacheWrites = 0;
  createdJobs = 0;
  cacheCleanupBefore: Date | null = null;
  constructor(private readonly cached: SimulationCacheEntry | null = null) {}
  async deleteExpiredJobs(current: Date) { for (const [id, row] of this.jobs) if (row.expiresAt <= current) this.jobs.delete(id); }
  async deleteStaleCaches(expiredBefore: Date) { this.cacheCleanupBefore = expiredBefore; }
  async findReusableJob(requestHash: string, current: Date) {
    return [...this.jobs.values()].find((row) => row.hash === requestHash && row.expiresAt > current && ["queued", "running", "completed"].includes(row.job.status))?.job ?? null;
  }
  async createJob(input: { jobId: string; requestHash: string; attackerId: string; expiresAt: Date }) {
    this.createdJobs += 1; this.jobs.set(input.jobId, { job: { jobId: input.jobId, status: "queued" }, hash: input.requestHash, expiresAt: input.expiresAt });
  }
  async setJobStatus(jobId: string, status: JobStatus) { this.row(jobId).job = { jobId, status }; }
  async completeJob(jobId: string, result: TeamRecommendationResult) { this.row(jobId).job = { jobId, status: "completed", result }; }
  async failJob(jobId: string, errorCode: NonNullable<TeamRecommendationJob["errorCode"]>) { this.row(jobId).job = { jobId, status: "failed", errorCode }; }
  async readJob(jobId: string, current: Date) { const row = this.jobs.get(jobId); return !row ? null : row.expiresAt <= current ? { jobId, status: "expired" as const } : row.job; }
  async readCache() { return this.cached; }
  async writeCache() { this.cacheWrites += 1; }
  private row(jobId: string) { const row = this.jobs.get(jobId); if (!row) throw new Error("missing job"); return row; }
}
