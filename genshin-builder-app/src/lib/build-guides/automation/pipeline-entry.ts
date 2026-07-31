import "server-only";

import { prisma } from "@/lib/db";
import { fetchArtifactSets } from "@/lib/api/amber-details";
import { readYoutubeAutomationControl } from "./automation-control";
import { discoverApprovedChannelVideos } from "./discovery-service";
import { youtubeAutomationFlags } from "./feature-flags";
import { GeminiTranscriptAnalysisProvider } from "./gemini-transcript-provider";
import { automationHash } from "./idempotency";
import { refreshPublishedSourceAvailability } from "./maintenance";
import { runYoutubeGuidePipeline } from "./pipeline-runner";
import { deleteExpiredTranscripts } from "./transcript-store";
import { YoutubeGuideClient } from "../youtube-client";
import { YouTubeOAuthTranscriptProvider } from "./youtube-oauth-transcript-provider";

const STAT_KEYS = [
  "hp",
  "atk",
  "def",
  "em",
  "critRate",
  "critDmg",
  "er",
  "healing",
  "elemDmg",
  "physDmg",
] as const;

export async function runDefaultYoutubeGuidePipeline(input: {
  pipelineRunId: string;
  trigger: "schedule" | "workflow_dispatch" | "admin";
  dryRun: boolean;
}) {
  const flags = youtubeAutomationFlags();
  const summary = await runYoutubeGuidePipeline({
    ...input,
    flags,
    discover: () => discoverApprovedChannelVideos(),
    transcriptProvider: new YouTubeOAuthTranscriptProvider(),
    analysisProvider: new GeminiTranscriptAnalysisProvider(),
    loadKnownEntityIds: async () => {
      const [weapons, artifactSets] = await Promise.all([
        prisma.weapon.findMany({ select: { id: true } }),
        fetchArtifactSets(),
      ]);
      return new Set([
        ...weapons.map(({ id }) => id),
        ...artifactSets.map(({ id }) => id),
        ...STAT_KEYS,
      ]);
    },
  });
  if (!flags.enabled || !flags.maintenanceEnabled || input.dryRun) {
    return summary;
  }
  const maintenanceControl = await readYoutubeAutomationControl();
  if (maintenanceControl.emergencyStopped) {
    return {
      ...summary,
      maintenance: {
        status: "stopped" as const,
        checked: 0,
        unavailable: 0,
        transcriptsDeleted: 0,
      },
    };
  }

  let transcriptsDeleted = 0;
  let checked = 0;
  let unavailable = 0;
  let status: "completed" | "retryable" = "completed";
  try {
    transcriptsDeleted = await deleteExpiredTranscripts({ now: new Date() });
    const beforeAvailability = await readYoutubeAutomationControl();
    if (beforeAvailability.emergencyStopped) {
      return {
        ...summary,
        maintenance: {
          status: "stopped" as const,
          checked: 0,
          unavailable: 0,
          transcriptsDeleted,
        },
      };
    }
    const publishedSources =
      await prisma.recommendationVisualContribution.findMany({
        where: {
          usedInPublishedResult: true,
          recommendation: { status: "published" },
        },
        select: { videoId: true },
        distinct: ["videoId"],
      });
    if (publishedSources.length > 0) {
      const availability = await refreshPublishedSourceAvailability({
        videoIds: publishedSources.map(({ videoId }) => videoId),
        client: new YoutubeGuideClient(),
        now: new Date(),
      });
      checked = availability.checked;
      unavailable = availability.unavailable;
    }
  } catch {
    // Provider and storage details are deliberately not copied to API/audit.
    status = "retryable";
  }
  const maintenance = {
    status,
    checked,
    unavailable,
    transcriptsDeleted,
  } as const;
  await prisma.guideAdminAuditLog.upsert({
    where: {
      actionKey: automationHash("youtube-maintenance-v1", {
        pipelineRunId: input.pipelineRunId,
      }),
    },
    create: {
      actionKey: automationHash("youtube-maintenance-v1", {
        pipelineRunId: input.pipelineRunId,
      }),
      pipelineRunId: input.pipelineRunId,
      actor: "system:youtube-automation",
      action: "youtubeGuideMaintenance",
      status,
      detail: JSON.stringify(maintenance),
    },
    update: {},
  });
  return { ...summary, maintenance };
}
