import { createHash } from "node:crypto";
import type { PublicBuildRecommendation } from "./visual-schemas";

/**
 * 公開レスポンスの ETag。
 * row.updatedAt（working draft 保存で動く）ではなく公開内容の指紋を使う。
 */
export function buildPublicRecommendationEtag(
  characterId: string,
  data: PublicBuildRecommendation,
): string {
  const fingerprint = createHash("sha256")
    .update(
      JSON.stringify({
        schemaVersion: data.schemaVersion,
        investmentPriority: data.investmentPriority ?? null,
        gameVersion: data.gameVersion ?? null,
        weapons: data.weapons,
        artifactRecommendations: data.artifactRecommendations,
        mainStats: data.mainStats,
        recommendedStats: data.recommendedStats,
        targets: data.targets,
        sources: data.sources.map((s) => s.id),
        publishedAt: data.publishedAt,
        updatedAt: data.updatedAt,
      }),
    )
    .digest("hex")
    .slice(0, 20);
  return `"br-${characterId}-${fingerprint}"`;
}
