import type { NextConfig } from "next";
import { execSync } from "node:child_process";

/** Secret-free commit SHA for admin build provenance (build-time embed). */
function resolveBuildCommitSha(): string {
  const fromEnv =
    process.env.VERCEL_GIT_COMMIT_SHA ||
    process.env.GIT_COMMIT_SHA ||
    process.env.GITHUB_SHA ||
    "";
  if (fromEnv.trim()) return fromEnv.trim();
  try {
    return execSync("git rev-parse HEAD", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "unknown";
  }
}

const genshinBuildCommitSha = resolveBuildCommitSha();
const genshinBuildBuiltAt = new Date().toISOString();

const nextConfig: NextConfig = {
  // Inlined at build time into the Next bundle. Not arbitrary env dump — SHA + timestamp only.
  env: {
    GENSIN_BUILD_COMMIT_SHA: genshinBuildCommitSha,
    GENSIN_BUILD_BUILT_AT: genshinBuildBuiltAt,
  },
  images: {
    // キャラクター・武器・素材のアイコンを外部APIから直接表示する
    remotePatterns: [
      {
        protocol: "https",
        hostname: "gi.yatta.moe",
      },
    ],
  },
};

export default nextConfig;
