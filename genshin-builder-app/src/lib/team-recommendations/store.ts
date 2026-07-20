import { prisma } from "@/lib/db";
import { GCSIM_VERSION } from "./settings";
import type { GcsimRunResult, JobStatus, TeamRecommendationJob, TeamRecommendationResult } from "./types";

export interface SimulationCacheEntry {
  value: GcsimRunResult;
  expiresAt: Date;
}

export interface SimulationStore {
  deleteExpiredJobs(now: Date): Promise<void>;
  deleteStaleCaches(expiredBefore: Date): Promise<void>;
  findReusableJob(requestHash: string, now: Date): Promise<TeamRecommendationJob | null>;
  createJob(input: { jobId: string; requestHash: string; attackerId: string; expiresAt: Date }): Promise<void>;
  setJobStatus(jobId: string, status: JobStatus): Promise<void>;
  completeJob(jobId: string, result: TeamRecommendationResult): Promise<void>;
  failJob(jobId: string, errorCode: NonNullable<TeamRecommendationJob["errorCode"]>): Promise<void>;
  readJob(jobId: string, now: Date): Promise<TeamRecommendationJob | null>;
  readCache(cacheKey: string): Promise<SimulationCacheEntry | null>;
  writeCache(input: { cacheKey: string; attackerId: string; value: GcsimRunResult; expiresAt: Date }): Promise<void>;
}

export class PrismaSimulationStore implements SimulationStore {
  async deleteExpiredJobs(now: Date): Promise<void> {
    await prisma.teamSimulationJob.deleteMany({ where: { expiresAt: { lte: now } } });
  }
  async deleteStaleCaches(expiredBefore: Date): Promise<void> {
    await prisma.teamSimulationCache.deleteMany({ where: { expiresAt: { lte: expiredBefore } } });
  }
  async findReusableJob(requestHash: string, now: Date): Promise<TeamRecommendationJob | null> {
    const row = await prisma.teamSimulationJob.findFirst({
      where: { requestHash, expiresAt: { gt: now }, status: { in: ["queued", "running", "completed"] } },
      orderBy: { createdAt: "desc" },
    });
    return row ? rowToJob(row) : null;
  }
  async createJob(input: { jobId: string; requestHash: string; attackerId: string; expiresAt: Date }): Promise<void> {
    await prisma.teamSimulationJob.create({ data: { id: input.jobId, requestHash: input.requestHash, attackerId: input.attackerId, status: "queued", expiresAt: input.expiresAt } });
  }
  async setJobStatus(jobId: string, status: JobStatus): Promise<void> {
    await prisma.teamSimulationJob.update({ where: { id: jobId }, data: { status } });
  }
  async completeJob(jobId: string, result: TeamRecommendationResult): Promise<void> {
    await prisma.teamSimulationJob.update({ where: { id: jobId }, data: { status: "completed", result: JSON.stringify(result), errorCode: "" } });
  }
  async failJob(jobId: string, errorCode: NonNullable<TeamRecommendationJob["errorCode"]>): Promise<void> {
    await prisma.teamSimulationJob.update({ where: { id: jobId }, data: { status: "failed", errorCode, result: "" } });
  }
  async readJob(jobId: string, now: Date): Promise<TeamRecommendationJob | null> {
    const row = await prisma.teamSimulationJob.findUnique({ where: { id: jobId } });
    if (!row) return null;
    if (row.expiresAt <= now) {
      if (row.status !== "expired") await prisma.teamSimulationJob.update({ where: { id: jobId }, data: { status: "expired" } });
      return { jobId, status: "expired" };
    }
    return rowToJob(row);
  }
  async readCache(cacheKey: string): Promise<SimulationCacheEntry | null> {
    const row = await prisma.teamSimulationCache.findUnique({ where: { cacheKey } });
    if (!row) return null;
    try {
      const value = parseCachedRun(JSON.parse(row.payload));
      return value ? { value, expiresAt: row.expiresAt } : null;
    } catch { return null; }
  }
  async writeCache(input: { cacheKey: string; attackerId: string; value: GcsimRunResult; expiresAt: Date }): Promise<void> {
    await prisma.teamSimulationCache.upsert({
      where: { cacheKey: input.cacheKey },
      create: { cacheKey: input.cacheKey, gcsimVersion: GCSIM_VERSION, attackerId: input.attackerId, payload: JSON.stringify(input.value), expiresAt: input.expiresAt },
      update: { gcsimVersion: GCSIM_VERSION, attackerId: input.attackerId, payload: JSON.stringify(input.value), expiresAt: input.expiresAt },
    });
  }
}

type JobRow = { id: string; status: string; result: string; errorCode: string };
function rowToJob(row: JobRow): TeamRecommendationJob {
  const status = isJobStatus(row.status) ? row.status : "failed";
  if (status === "completed" && row.result) {
    try { return { jobId: row.id, status, result: JSON.parse(row.result) as TeamRecommendationResult }; } catch { return { jobId: row.id, status: "failed", errorCode: "internalError" }; }
  }
  return { jobId: row.id, status, ...(row.errorCode ? { errorCode: safeErrorCode(row.errorCode) } : {}) };
}
function isJobStatus(value: string): value is JobStatus { return ["queued", "running", "completed", "failed", "expired"].includes(value); }
function safeErrorCode(value: string): NonNullable<TeamRecommendationJob["errorCode"]> {
  return ["invalidRequest", "noCandidates", "simulationFailed", "internalError"].includes(value) ? value as NonNullable<TeamRecommendationJob["errorCode"]> : "internalError";
}
function parseCachedRun(value: unknown): GcsimRunResult | null {
  if (!value || typeof value !== "object") return null;
  const run = value as Partial<GcsimRunResult>;
  return typeof run.estimatedDps === "number" && Number.isFinite(run.estimatedDps) && Number.isInteger(run.iterations)
    && run.reactions !== null && typeof run.reactions === "object" && Array.isArray(run.endingEnergy) ? run as GcsimRunResult : null;
}
