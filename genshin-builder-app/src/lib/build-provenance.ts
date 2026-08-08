import "server-only";

import { BUILD_PROVENANCE_EMBEDDED } from "@/lib/generated/build-provenance.generated";

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
 * Prefers platform commit metadata (Vercel) over embedded SHA; builtAt is build-time.
 * Does not dump env values, cookies, or tokens.
 */
export function getBuildProvenance(): BuildProvenance {
  const onVercel = process.env.VERCEL === "1";
  const embeddedSha = String(BUILD_PROVENANCE_EMBEDDED.commitSha);
  const embeddedBuiltAt = String(BUILD_PROVENANCE_EMBEDDED.builtAt);

  const commitSha =
    (process.env.VERCEL_GIT_COMMIT_SHA || "").trim() ||
    (process.env.GIT_COMMIT_SHA || "").trim() ||
    embeddedSha ||
    "unknown";

  const builtAt =
    embeddedBuiltAt && embeddedBuiltAt !== "unknown"
      ? embeddedBuiltAt
      : (process.env.GENSIN_BUILD_BUILT_AT || "").trim() || "unknown";

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
