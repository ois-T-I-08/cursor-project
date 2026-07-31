import "server-only";

export type YoutubeAutomationFlags = Readonly<{
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
