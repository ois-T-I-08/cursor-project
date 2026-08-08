import "server-only";

export type BuildProvenance = {
  commitSha: string;
  builtAt: string;
  /** Coarse host: LOCAL | VERCEL */
  runtime: "LOCAL" | "VERCEL";
  /** e.g. development | production | preview | vercel:production */
  environment: string;
  /** Optional package version when available at build/runtime. */
  appVersion: string | null;
};

/**
 * Secret-free build provenance for admin diagnostics.
 * Prefers platform commit metadata (Vercel) over build-time embed from next.config;
 * builtAt comes from build-time embed (GENSIN_BUILD_BUILT_AT).
 * Does not dump env values, cookies, or tokens.
 */
export function getBuildProvenance(): BuildProvenance {
  const onVercel = process.env.VERCEL === "1";

  const commitSha =
    (process.env.VERCEL_GIT_COMMIT_SHA || "").trim() ||
    (process.env.GIT_COMMIT_SHA || "").trim() ||
    (process.env.GENSIN_BUILD_COMMIT_SHA || "").trim() ||
    "unknown";

  const builtAt = (process.env.GENSIN_BUILD_BUILT_AT || "").trim() || "unknown";

  let environment: string;
  if (onVercel) {
    const vercelEnv = (process.env.VERCEL_ENV || "").trim() || "unknown";
    environment = `vercel:${vercelEnv}`;
  } else {
    environment = (process.env.NODE_ENV || "development").trim();
  }

  const appVersion =
    (process.env.npm_package_version || "").trim() ||
    (process.env.GENSIN_APP_VERSION || "").trim() ||
    null;

  return {
    commitSha,
    builtAt,
    runtime: onVercel ? "VERCEL" : "LOCAL",
    environment,
    appVersion,
  };
}
