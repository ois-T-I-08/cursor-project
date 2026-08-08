import "server-only";

/**
 * Computed YouTube guide automation flags (process env, fail-closed).
 *
 * `enabled` means: master enable for the **subtitle automation pipeline**
 * (`YOUTUBE_AUTOMATION_ENABLED && YOUTUBE_GUIDE_ENABLED`).
 * It is NOT “Safety Switch mechanism on/off”. The Safety Switch /
 * Global AI Emergency state is `GuideAutomationControl.emergencyStopped`
 * (+ monotonic `version`). Audit 2A: that flag gates all external AI calls
 * (YouTube + Gemini + DeepSeek daily-plan/team/guide) and auto-publish.
 *
 * Precedence:
 *   Global AI Emergency (emergencyStopped, fail-closed on missing/read error)
 *     → feature master / env kill switches (incl. `enabled`, DEEPSEEK_*)
 *       → per-stage work / quality
 *         → autoPublishEnabled (auto-publish only)
 *           → maintenanceEnabled (post-pipeline retention only)
 * Manual publish: blocked during emergency unless break-glass override.
 */
export type YoutubeAutomationFlags = Readonly<{
  /** Master enable for subtitle automation pipeline (not Safety Switch itself). */
  enabled: boolean;
  guideEnabled: boolean;
  discoveryEnabled: boolean;
  transcriptEnabled: boolean;
  analysisEnabled: boolean;
  geminiAnalysisEnabled: boolean;
  deepseekAnalysisEnabled: boolean;
  autoPublishEnabled: boolean;
  maintenanceEnabled: boolean;
}>;

function enabled(value: string | undefined): boolean {
  return value === "true";
}

/**
 * Every stage is opt-in and also requires the umbrella switch. Missing,
 * misspelled, or differently-cased values therefore fail closed.
 */
export function youtubeAutomationFlags(
  env: Readonly<Record<string, string | undefined>> = process.env,
): YoutubeAutomationFlags {
  const pipelineEnabled = enabled(env.YOUTUBE_AUTOMATION_ENABLED);
  const guideEnabled = enabled(env.YOUTUBE_GUIDE_ENABLED);
  const geminiAnalysisEnabled = enabled(env.GEMINI_VIDEO_ANALYSIS_ENABLED);
  const deepseekAnalysisEnabled = enabled(
    env.DEEPSEEK_GUIDE_ANALYSIS_ENABLED,
  );
  return Object.freeze({
    // Master pipeline enable — see type JSDoc (not Safety Switch mechanism).
    enabled: pipelineEnabled && guideEnabled,
    guideEnabled,
    discoveryEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_DISCOVERY_ENABLED),
    transcriptEnabled: pipelineEnabled,
    analysisEnabled:
      pipelineEnabled && (geminiAnalysisEnabled || deepseekAnalysisEnabled),
    geminiAnalysisEnabled: pipelineEnabled && geminiAnalysisEnabled,
    deepseekAnalysisEnabled: pipelineEnabled && deepseekAnalysisEnabled,
    autoPublishEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_AUTO_PUBLISH_ENABLED),
    maintenanceEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_MAINTENANCE_ENABLED),
  });
}
