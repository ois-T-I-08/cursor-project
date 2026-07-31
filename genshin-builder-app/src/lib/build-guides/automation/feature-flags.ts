import "server-only";

export type YoutubeAutomationFlags = Readonly<{
  enabled: boolean;
  discoveryEnabled: boolean;
  transcriptEnabled: boolean;
  analysisEnabled: boolean;
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
  const pipelineEnabled = enabled(env.YOUTUBE_GUIDE_AUTOMATION_ENABLED);
  return Object.freeze({
    enabled: pipelineEnabled,
    discoveryEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_DISCOVERY_ENABLED),
    transcriptEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_TRANSCRIPT_ENABLED),
    analysisEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_ANALYSIS_ENABLED),
    autoPublishEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_AUTO_PUBLISH_ENABLED),
    maintenanceEnabled:
      pipelineEnabled && enabled(env.YOUTUBE_GUIDE_MAINTENANCE_ENABLED),
  });
}
