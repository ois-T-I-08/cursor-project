/**
 * Visual-analysis auto-approve/publish switch (normal ops: "true").
 * Only the literal string "true" enables; anything else fails closed.
 *
 * Distinct env from `YOUTUBE_AUTO_PUBLISH_ENABLED`, but runtime auto-publish
 * also requires Safety Switch emergency OFF and
 * `youtubeAutomationFlags().autoPublishEnabled` (see `evaluateVisualAutoPublishGate`).
 * Canary callers use skipAutoPublish and never reach this gate.
 */
export function isVisualAutoPublishEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return env.BUILD_GUIDE_VISUAL_AUTO_PUBLISH === "true";
}
