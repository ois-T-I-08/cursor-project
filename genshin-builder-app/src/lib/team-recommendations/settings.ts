export const GCSIM_VERSION = "v2.43.4";
export const GCSIM_COMMIT_SHA = "24042de8ba3243693e97cd7efe22292762b08331";
// gcsim v2.43.4には独立したConfig schema versionがないため、tag契約として記録する。
export const GCSIM_CONFIG_SCHEMA_VERSION = "unversioned-v2.43.4";
export const GCSIM_RESULT_SCHEMA_VERSION = "4.2";
export const ROTATION_TEMPLATE_VERSION = "rotation-v1";

export const GCSIM_BINARY_SHA256: Readonly<Record<string, string>> = {
  "linux-x64": "c0ea87f2acee0eea1f4df8a7fb39d4c1de4b2ec179520a6e090d66147b641344",
  "win32-x64": "d866d1faa029b7f9ab808759116d39b015edbe09cbba3ac38314f5e0f551dd6a",
  "darwin-x64": "32e04c351668be1e22f4615d4e9129b6dc497eb6d5a5233c84bd6984e6fe542a",
  "darwin-arm64": "4598bfe8c86d4aab76cd5d7c2e88642410e282309737ea5595a532c68282e8ec",
};

export interface TeamRecommendationSettings {
  enabled: boolean;
  maxCandidates: number;
  maxConcurrency: number;
  maxActiveJobs: number;
  timeoutMs: number;
  iterations: number;
  cacheTtlSeconds: number;
  jobTtlSeconds: number;
  maxConfigBytes: number;
  maxOutputBytes: number;
  durationSeconds: number;
}

export function readTeamRecommendationSettings(
  env: NodeJS.ProcessEnv = process.env,
): TeamRecommendationSettings {
  return {
    enabled: env.GCSIM_ENABLED?.trim().toLowerCase() === "true",
    maxCandidates: boundedInt(env.GCSIM_MAX_CANDIDATES, 20, 1, 20),
    maxConcurrency: boundedInt(env.GCSIM_MAX_CONCURRENCY, 2, 1, 4),
    maxActiveJobs: boundedInt(env.GCSIM_MAX_ACTIVE_JOBS, 8, 1, 32),
    timeoutMs: boundedInt(env.GCSIM_TIMEOUT_SECONDS, 30, 5, 120) * 1_000,
    iterations: boundedInt(env.GCSIM_ITERATIONS, 1_000, 50, 5_000),
    cacheTtlSeconds: boundedInt(env.GCSIM_CACHE_TTL_SECONDS, 86_400, 300, 604_800),
    jobTtlSeconds: boundedInt(env.GCSIM_JOB_TTL_SECONDS, 86_400, 300, 604_800),
    maxConfigBytes: boundedInt(env.GCSIM_MAX_CONFIG_BYTES, 65_536, 4_096, 262_144),
    maxOutputBytes: boundedInt(env.GCSIM_MAX_OUTPUT_BYTES, 2_097_152, 65_536, 8_388_608),
    durationSeconds: boundedInt(env.GCSIM_DURATION_SECONDS, 90, 30, 180),
  };
}

function boundedInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
}
