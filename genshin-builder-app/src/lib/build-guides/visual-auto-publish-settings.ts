/**
 * Fail-closed kill switch for auto-approving and publishing visual-analysis
 * recommendations. Distinct from YOUTUBE_AUTO_PUBLISH_ENABLED (transcript pipeline).
 */
export function isVisualAutoPublishEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return env.BUILD_GUIDE_VISUAL_AUTO_PUBLISH === "true";
}
