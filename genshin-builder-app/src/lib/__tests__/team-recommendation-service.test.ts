import { describe, expect, it, vi } from "vitest";
import { TeamRecommendationService } from "@/lib/team-recommendations/service";
import type { TeamRecommendationSettings } from "@/lib/team-recommendations/settings";
import type { SimulationStore } from "@/lib/team-recommendations/store";
import type { JobStatus, TeamRecommendationJob, TeamRecommendationRequest, TeamRecommendationResult } from "@/lib/team-recommendations/types";
import type { AbyssStatistics } from "@/lib/abyss/types";

const now = new Date("2026-07-20T00:00:00Z");
const request: TeamRecommendationRequest = {
  attackerId: "10000089", mode: "spiralAbyss", half: "upper", ownedOnly: true, enemy: "single", preference: "damage",
  characters: [
    build("10000089", "11513"), build("10000087", "14514"), build("10000025", "11401"), build("10000054", "14401"),
  ],
};

describe("TeamRecommendationService", () => {
  it("completes an AZA/rule recommendation job", async () => {
    const store = new MemoryStore();
    const service = createService(store);
    const queued = await service.enqueue(request);
    await service.waitForLocalJob(queued.jobId);
    const completed = await service.get(queued.jobId);
    expect(completed?.status).toBe("completed");
    expect(completed?.result?.recommendations[0]).toMatchObject({ simulationStatus: "observed", isStale: false, isCached: false });
    expect(completed?.result).not.toHaveProperty("gcsim");
    expect(completed?.result).not.toHaveProperty("warning");
  });

  it("falls back to rule recommendations when AZA load fails", async () => {
    const store = new MemoryStore();
    const service = new TeamRecommendationService(
      store,
      async () => { throw new Error("aza down"); },
      settings(),
      { now: () => now, log: () => undefined },
    );
    const job = await service.enqueue(request);
    await service.waitForLocalJob(job.jobId);
    const result = await service.get(job.jobId);
    expect(result?.status).toBe("completed");
    expect(result?.result?.recommendations.length).toBeGreaterThan(0);
    expect(result?.result?.recommendations.every((item) => item.simulationStatus === "ruleBased")).toBe(true);
  });

  it("deduplicates identical active/completed requests", async () => {
    const store = new MemoryStore();
    const service = createService(store);
    const [first, concurrent] = await Promise.all([service.enqueue(request), service.enqueue(request)]);
    expect(concurrent.jobId).toBe(first.jobId);
    await service.waitForLocalJob(first.jobId);
    const second = await service.enqueue(request);
    expect(second.jobId).toBe(first.jobId);
    expect(store.createdJobs).toBe(1);
  });

  it("bounds process-local active jobs", async () => {
    let finishAbyss: (() => void) | undefined;
    const store = new MemoryStore();
    const service = new TeamRecommendationService(
      store,
      () => new Promise<AbyssStatistics>((resolve) => {
        finishAbyss = () => resolve(abyss());
      }),
      settings({ maxActiveJobs: 1 }),
      { now: () => now, log: () => undefined },
    );
    const first = await service.enqueue(request);
    await vi.waitFor(() => expect(store.jobs.get(first.jobId)?.job.status).toBe("running"));
    await expect(service.enqueue({ ...request, preference: "built" })).rejects.toThrow("jobCapacityExceeded");
    finishAbyss?.();
    await service.waitForLocalJob(first.jobId);
  });

  it("logs only safe job metadata", async () => {
    const events: unknown[] = [];
    const service = new TeamRecommendationService(new MemoryStore(), async () => abyss(), settings(), {
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

function createService(store: MemoryStore) {
  return new TeamRecommendationService(store, async () => abyss(), settings(), { now: () => now, log: () => undefined });
}
function settings(overrides: Partial<TeamRecommendationSettings> = {}): TeamRecommendationSettings {
  return { maxCandidates: 20, maxActiveJobs: 8, jobTtlSeconds: 86400, ...overrides };
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
  createdJobs = 0;
  async deleteExpiredJobs(current: Date) { for (const [id, row] of this.jobs) if (row.expiresAt <= current) this.jobs.delete(id); }
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
  private row(jobId: string) { const row = this.jobs.get(jobId); if (!row) throw new Error("missing job"); return row; }
}
