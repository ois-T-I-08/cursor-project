import "server-only";

import { z } from "zod";
import { prisma } from "@/lib/db";
import { getPublishedBuildRecommendation } from "./store";
import { publicBuildRecommendationSchema } from "./visual-schemas";

const sourceV2Schema = publicBuildRecommendationSchema.shape.sources.element.extend({
  availability: z.enum(["available", "unavailable", "unknown"]),
  unavailableSince: z.string().datetime().nullable(),
});

const evidenceV2Schema = z.strictObject({
  fieldPath: z.string(),
  videoId: z.string(),
  timestampStart: z.number().nonnegative(),
  timestampEnd: z.number().nonnegative(),
});

export const publicBuildRecommendationV2Schema = z.strictObject({
  ...publicBuildRecommendationSchema.shape,
  schemaVersion: z.literal(2),
  verificationMode: z.enum(["manual_review", "automatic_strict"]),
  sources: z.array(sourceV2Schema),
  evidence: z.array(evidenceV2Schema),
});

export type PublicBuildRecommendationV2 = z.infer<
  typeof publicBuildRecommendationV2Schema
>;

/**
 * Versioned API strategy (B): v1 remains byte-for-byte contract-compatible.
 * v2 adds verification and source availability while omitting evidence text.
 */
export async function getPublishedBuildRecommendationV2(
  characterId: string,
): Promise<PublicBuildRecommendationV2 | null> {
  const legacy = await getPublishedBuildRecommendation(characterId);
  if (!legacy) return null;
  const row = await prisma.characterBuildRecommendation.findFirst({
    where: { characterId, status: "published" },
    orderBy: { publishedAt: "desc" },
    select: {
      verificationMode: true,
      contributions: {
        where: {
          usedInPublishedResult: true,
          decision: { in: ["adopted", "partially_adopted"] },
        },
        select: {
          videoId: true,
          video: {
            select: {
              availabilityStatus: true,
              unavailableSince: true,
            },
          },
        },
      },
    },
  });
  if (!row) return null;
  const availabilityByVideoId = new Map(
    row.contributions.map((contribution) => [
      contribution.videoId,
      {
        availability: normalizeAvailability(
          contribution.video.availabilityStatus,
        ),
        unavailableSince:
          contribution.video.unavailableSince?.toISOString() ?? null,
      },
    ]),
  );
  return publicBuildRecommendationV2Schema.parse({
    ...legacy,
    schemaVersion: 2,
    verificationMode:
      row.verificationMode === "automatic_strict"
        ? "automatic_strict"
        : "manual_review",
    sources: legacy.sources.map((source) => ({
      ...source,
      ...(availabilityByVideoId.get(source.videoId) ?? {
        availability: "unknown" as const,
        unavailableSince: null,
      }),
    })),
    evidence: legacy.evidence.map((evidence) => ({
      fieldPath: evidence.fieldPath,
      videoId: evidence.videoId,
      timestampStart: evidence.startSeconds,
      timestampEnd: evidence.endSeconds,
    })),
  });
}

function normalizeAvailability(
  value: string,
): "available" | "unavailable" | "unknown" {
  if (value === "available" || value === "unavailable") return value;
  return "unknown";
}
