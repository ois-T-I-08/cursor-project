import { randomUUID } from "node:crypto";
import type { AbyssStatistics } from "@/lib/abyss/types";
import { teamRecommendationRequestHash } from "./cache-key";
import { TeamCandidateGenerator } from "./candidate-generator";
import { TeamRecommendationScorer, worstInputQuality } from "./scorer";
import type { TeamRecommendationSettings } from "./settings";
import type { SimulationStore } from "./store";
import type { TeamCandidate, TeamRecommendation, TeamRecommendationJob, TeamRecommendationRequest } from "./types";

type SafeLog = (event: string, details: Partial<{ jobId: string; attackerId: string; durationMs: number; candidateCount: number; status: string }>) => void;

export class TeamRecommendationService {
  private readonly activeJobs = new Map<string, Promise<void>>();
  private readonly enqueueFlights = new Map<string, Promise<TeamRecommendationJob>>();
  private pendingEnqueues = 0;
  constructor(
    private readonly store: SimulationStore,
    private readonly loadAbyss: () => Promise<AbyssStatistics>,
    private readonly settings: TeamRecommendationSettings,
    private readonly options: { now?: () => Date; log?: SafeLog } = {},
    private readonly candidates = new TeamCandidateGenerator(),
    private readonly scorer = new TeamRecommendationScorer(),
  ) {}

  enqueue(request: TeamRecommendationRequest): Promise<TeamRecommendationJob> {
    const requestHash = teamRecommendationRequestHash(request);
    const existingFlight = this.enqueueFlights.get(requestHash);
    if (existingFlight) return existingFlight;
    const flight = this.enqueueOnce(request, requestHash).finally(() => this.enqueueFlights.delete(requestHash));
    this.enqueueFlights.set(requestHash, flight);
    return flight;
  }

  private async enqueueOnce(request: TeamRecommendationRequest, requestHash: string): Promise<TeamRecommendationJob> {
    const now = this.now();
    await this.store.deleteExpiredJobs(now);
    const existing = await this.store.findReusableJob(requestHash, now);
    if (existing) return existing;
    if (this.activeJobs.size + this.pendingEnqueues >= this.settings.maxActiveJobs) {
      throw new Error("jobCapacityExceeded");
    }
    this.pendingEnqueues += 1;
    const jobId = randomUUID();
    try {
      await this.store.createJob({
        jobId,
        requestHash,
        attackerId: request.attackerId,
        expiresAt: new Date(now.getTime() + this.settings.jobTtlSeconds * 1_000),
      });
      const work = this.process(jobId, request)
        .catch(() => this.log("job_worker_failed", { jobId, attackerId: request.attackerId, status: "failed" }))
        .finally(() => this.activeJobs.delete(jobId));
      this.activeJobs.set(jobId, work);
      void work;
      this.log("job_queued", { jobId, attackerId: request.attackerId, status: "queued" });
      return { jobId, status: "queued" };
    } finally {
      this.pendingEnqueues -= 1;
    }
  }

  get(jobId: string): Promise<TeamRecommendationJob | null> {
    return this.store.readJob(jobId, this.now());
  }

  async waitForLocalJob(jobId: string): Promise<void> {
    await this.activeJobs.get(jobId);
  }

  private async process(jobId: string, request: TeamRecommendationRequest): Promise<void> {
    const started = Date.now();
    try {
      await this.store.setJobStatus(jobId, "running");
      let abyssTeams: AbyssStatistics["teams"] = [];
      let abyssError: string | undefined;
      try {
        abyssTeams = (await this.loadAbyss()).teams;
      } catch (error) {
        abyssError = error instanceof Error ? error.message : "abyssLoadFailed";
      }
      const candidates = this.candidates.generate({ request, abyssTeams }).slice(0, this.settings.maxCandidates);
      if (candidates.length === 0) {
        await this.store.failJob(jobId, "noCandidates");
        return;
      }
      const recommendations = candidates
        .map((candidate) => this.toRecommendation(request, candidate))
        .sort((a, b) => b.score - a.score);
      const warning = abyssError || abyssTeams.length === 0 ? "abyssUnavailable" as const : undefined;
      await this.store.completeJob(jobId, {
        attackerId: request.attackerId,
        generatedAt: this.now().toISOString(),
        engine: "aza+rules",
        recommendations,
        ...(warning ? { warning } : {}),
      });
      this.log("job_completed", {
        jobId,
        attackerId: request.attackerId,
        durationMs: Date.now() - started,
        candidateCount: recommendations.length,
        status: "completed",
      });
    } catch {
      await this.store.failJob(jobId, "internalError");
      this.log("job_failed", {
        jobId,
        attackerId: request.attackerId,
        durationMs: Date.now() - started,
        status: "failed",
      });
    }
  }

  private toRecommendation(request: TeamRecommendationRequest, candidate: TeamCandidate): TeamRecommendation {
    const builds = request.characters.filter((build) => candidate.members.includes(build.characterId));
    const reasons = [
      candidate.observedByAza ? "AZA.GGの深境螺旋で使用実績があります" : "元素反応と役割の共通ルールから生成しました",
    ];
    if (candidate.hasSustain) reasons.push("回復またはシールド役を含みます");
    return {
      members: candidate.members,
      score: this.scorer.score({ candidate, request }),
      simulationStatus: candidate.observedByAza ? "observed" : "ruleBased",
      sourceTypes: candidate.sourceTypes,
      rotationConfidence: candidate.rotationConfidence,
      observedByAza: candidate.observedByAza,
      inputQuality: worstInputQuality(builds),
      reasons,
      alternatives: alternativesFor(request, candidate),
    };
  }

  private now(): Date {
    return (this.options.now ?? (() => new Date()))();
  }
  private log(event: string, details: Parameters<SafeLog>[1]): void {
    (this.options.log ?? defaultLog)(event, details);
  }
}

function defaultLog(event: string, details: Parameters<SafeLog>[1]): void {
  console.info("team_recommendation", { event, ...details });
}

function alternativesFor(request: TeamRecommendationRequest, candidate: TeamCandidate): Record<string, string[]> {
  const byId = new Map(request.characters.map((build) => [build.characterId, build]));
  const alternatives: Record<string, string[]> = {};
  for (const memberId of candidate.members) {
    if (memberId === candidate.attackerId) continue;
    const member = byId.get(memberId);
    if (!member) continue;
    const matches = request.characters
      .filter((build) => build.characterId !== candidate.attackerId && !candidate.members.includes(build.characterId))
      .filter((build) => build.element === member.element && (!request.ownedOnly || build.isOwned))
      .sort((a, b) => Number(b.isOwned) - Number(a.isOwned) || b.level - a.level || a.characterId.localeCompare(b.characterId))
      .slice(0, 2)
      .map((build) => build.characterId);
    if (matches.length > 0) alternatives[memberId] = matches;
  }
  return alternatives;
}
