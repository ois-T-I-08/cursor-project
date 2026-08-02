import { createHash } from "node:crypto";

/**
 * 公開レスポンスの ETag。
 * row.updatedAt（working draft 保存で動く）ではなく公開内容の指紋を使う。
 */
export function buildPublicRecommendationEtag(
  characterId: string,
  data: unknown,
): string {
  const fingerprint = createHash("sha256")
    .update(
      JSON.stringify({
        characterId,
        data,
      }),
    )
    .digest("hex")
    .slice(0, 20);
  return `"br-${characterId}-${fingerprint}"`;
}

/** GET の If-None-Match は weak comparison とリスト形式を受け付ける。 */
export function matchesPublicRecommendationEtag(
  ifNoneMatch: string | null,
  etag: string,
): boolean {
  if (!ifNoneMatch) return false;
  const expected = etag.replace(/^W\//, "");
  return ifNoneMatch.split(",").some((candidate) => {
    const value = candidate.trim();
    return value === "*" || value.replace(/^W\//, "") === expected;
  });
}
