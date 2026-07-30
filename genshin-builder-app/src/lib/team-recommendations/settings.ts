export interface TeamRecommendationSettings {
  maxCandidates: number;
  maxActiveJobs: number;
  jobTtlSeconds: number;
}

export function readTeamRecommendationSettings(
  env: NodeJS.ProcessEnv = process.env,
): TeamRecommendationSettings {
  return {
    maxCandidates: boundedInt(env.TEAM_RECOMMENDATION_MAX_CANDIDATES, 20, 1, 20),
    maxActiveJobs: boundedInt(env.TEAM_RECOMMENDATION_MAX_ACTIVE_JOBS, 8, 1, 32),
    jobTtlSeconds: boundedInt(env.TEAM_RECOMMENDATION_JOB_TTL_SECONDS, 86_400, 300, 604_800),
  };
}

function boundedInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
}
