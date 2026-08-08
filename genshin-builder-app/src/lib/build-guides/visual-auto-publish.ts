import "server-only";

import { prisma } from "@/lib/db";
import { fetchArtifactSets } from "@/lib/api/amber-details";
import {
  setRecommendationStatus,
  setVisualEvidenceStatus,
} from "@/lib/build-guides/store";
import { isVisualAutoPublishEnabled } from "@/lib/build-guides/visual-auto-publish-settings";
import { evaluateVisualAutoPublishGate } from "@/lib/build-guides/automation/safety-gates";
import {
  applyEntityMatchesToArtifactMentions,
  applyEntityMatchesToWeaponMentions,
  resolveEntitiesWithDeepSeek,
} from "@/lib/build-guides/deepseek-entity-resolve";
import {
  buildMasterNameMaps,
  promoteResolvedGearMentionsForAutoPublish,
  type GearMentionArtifact,
  type GearMentionWeapon,
  type GearPromotionResult,
  type MasterNameEntry,
} from "@/lib/build-guides/visual-gear-promote";

export { isVisualAutoPublishEnabled };
export { evaluateVisualAutoPublishGate };

export type VisualAutoPublishResult = Readonly<{
  evidenceApproved: number;
  recommendationsApproved: number;
  recommendationsPublished: number;
  gearPromotedWeapons: number;
  gearPromotedArtifacts: number;
  skipped: Array<{ recommendationId: string; reason: string }>;
}>;

function safeReason(error: unknown): string {
  if (error instanceof Error && typeof error.message === "string") {
    const message = error.message.slice(0, 200);
    if (message.startsWith("structuredPublishBlocked:")) {
      return "structuredPublishBlocked";
    }
    if (/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/.test(message)) {
      return message;
    }
  }
  return "autoPublishFailed";
}

function safeJsonObject(raw: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (parsed != null && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    /* ignore */
  }
  return {};
}

async function approveValidatedEvidence(
  evidenceIds: readonly string[],
): Promise<number> {
  let evidenceApproved = 0;
  for (const evidenceId of evidenceIds) {
    const evidence = await prisma.guideVisualEvidence.findUnique({
      where: { id: evidenceId },
      select: { id: true, validationStatus: true, approvalStatus: true },
    });
    if (!evidence) continue;
    if (evidence.validationStatus !== "validated") continue;
    if (evidence.approvalStatus === "approved") {
      evidenceApproved += 1;
      continue;
    }
    if (evidence.approvalStatus === "rejected") continue;
    await setVisualEvidenceStatus({
      evidenceId: evidence.id,
      approvalStatus: "approved",
    });
    evidenceApproved += 1;
  }
  return evidenceApproved;
}

async function loadGearMasterMaps() {
  const [weaponRows, artifactSets] = await Promise.all([
    prisma.weapon.findMany({ select: { id: true, name: true } }),
    fetchArtifactSets().catch(() => []),
  ]);
  const weapons = buildMasterNameMaps(weaponRows);
  const sets = buildMasterNameMaps(
    artifactSets.map((s) => ({ id: s.id, name: s.name })),
  );
  return {
    weaponsById: weapons.byId,
    weaponsByName: weapons.byName,
    setsById: sets.byId,
    setsByName: sets.byName,
  };
}

function extractEvidenceMentions(
  evidences: Array<{ videoId: string; normalizedPayload: string }>,
): {
  weapons: GearMentionWeapon[];
  artifacts: GearMentionArtifact[];
} {
  const weapons: GearMentionWeapon[] = [];
  const artifacts: GearMentionArtifact[] = [];
  for (const evidence of evidences) {
    const payload = safeJsonObject(evidence.normalizedPayload);
    for (const item of Array.isArray(payload.weaponMentions)
      ? payload.weaponMentions
      : []) {
      if (!item || typeof item !== "object") continue;
      const map = item as Record<string, unknown>;
      weapons.push({
        exactVisibleText:
          typeof map.exactVisibleText === "string" ? map.exactVisibleText : null,
        normalizedWeaponId:
          typeof map.normalizedWeaponId === "string"
            ? map.normalizedWeaponId
            : null,
        videoId: evidence.videoId,
        confidence: typeof map.confidence === "number" ? map.confidence : null,
      });
    }
    for (const item of Array.isArray(payload.artifactSetMentions)
      ? payload.artifactSetMentions
      : []) {
      if (!item || typeof item !== "object") continue;
      const map = item as Record<string, unknown>;
      artifacts.push({
        exactVisibleText:
          typeof map.exactVisibleText === "string" ? map.exactVisibleText : null,
        normalizedArtifactSetId:
          typeof map.normalizedArtifactSetId === "string"
            ? map.normalizedArtifactSetId
            : null,
        videoId: evidence.videoId,
        confidence: typeof map.confidence === "number" ? map.confidence : null,
      });
    }
  }
  return { weapons, artifacts };
}

/**
 * Promote resolved gear mentions on a recommendation when visual auto-publish is ON.
 */
export async function applyGearPromotionToRecommendation(
  recommendationId: string,
): Promise<GearPromotionResult | null> {
  const gate = await evaluateVisualAutoPublishGate();
  if (!gate.allowed) return null;

  const row = await prisma.characterBuildRecommendation.findUnique({
    where: { id: recommendationId },
    select: {
      id: true,
      structuredPayload: true,
      contributions: {
        select: {
          videoId: true,
          evidence: { select: { normalizedPayload: true, videoId: true } },
        },
      },
    },
  });
  if (!row) return null;

  const evidences = row.contributions.map((c) => ({
    videoId: c.evidence.videoId || c.videoId,
    normalizedPayload: c.evidence.normalizedPayload,
  }));
  const mentions = extractEvidenceMentions(evidences);
  const masters = await loadGearMasterMaps();
  const enriched = await enrichMentionsWithDeepSeekResolve({
    weapons: mentions.weapons,
    artifacts: mentions.artifacts,
    weaponsAllowlist: [...masters.weaponsById.values()],
    setsAllowlist: [...masters.setsById.values()],
  });
  const result = promoteResolvedGearMentionsForAutoPublish({
    structured: safeJsonObject(row.structuredPayload),
    evidenceWeapons: enriched.weapons,
    evidenceArtifacts: enriched.artifacts,
    ...masters,
  });

  await prisma.characterBuildRecommendation.update({
    where: { id: row.id },
    data: { structuredPayload: JSON.stringify(result.structured) },
  });
  return result;
}

async function enrichMentionsWithDeepSeekResolve(input: {
  weapons: GearMentionWeapon[];
  artifacts: GearMentionArtifact[];
  weaponsAllowlist: MasterNameEntry[];
  setsAllowlist: MasterNameEntry[];
}): Promise<{
  weapons: GearMentionWeapon[];
  artifacts: GearMentionArtifact[];
}> {
  const unresolvedWeapons = input.weapons.filter(
    (m) =>
      !(m.normalizedWeaponId || m.weaponId) &&
      (m.exactVisibleText || m.displayName),
  );
  const unresolvedArtifacts = input.artifacts.filter(
    (m) =>
      !(m.normalizedArtifactSetId || m.setId) &&
      (m.exactVisibleText || m.displayName),
  );

  let weapons = input.weapons;
  let artifacts = input.artifacts;

  if (unresolvedWeapons.length > 0) {
    const matches = await resolveEntitiesWithDeepSeek({
      kind: "weapon",
      queries: unresolvedWeapons.map((m) => ({
        query: String(m.exactVisibleText || m.displayName),
      })),
      allowedEntities: input.weaponsAllowlist,
    });
    weapons = applyEntityMatchesToWeaponMentions({
      mentions: weapons,
      matches,
    });
  }

  if (unresolvedArtifacts.length > 0) {
    const matches = await resolveEntitiesWithDeepSeek({
      kind: "artifact_set",
      queries: unresolvedArtifacts.map((m) => ({
        query: String(m.exactVisibleText || m.displayName),
      })),
      allowedEntities: input.setsAllowlist,
    });
    artifacts = applyEntityMatchesToArtifactMentions({
      mentions: artifacts,
      matches,
    });
  }

  return { weapons, artifacts };
}

/**
 * Suggestion-only resolve for admin UI (does not mutate publishable fields).
 */
export async function suggestPendingGearResolutions(input: {
  recommendationId: string;
}): Promise<{
  recommendationId: string;
  weaponSuggestions: Array<{
    query: string;
    entityId: string | null;
    displayName: string | null;
    confidence: number;
  }>;
  artifactSuggestions: Array<{
    query: string;
    entityId: string | null;
    displayName: string | null;
    confidence: number;
    pieces: 2 | 4 | null;
  }>;
}> {
  const row = await prisma.characterBuildRecommendation.findUnique({
    where: { id: input.recommendationId },
    select: {
      id: true,
      structuredPayload: true,
      contributions: {
        select: {
          videoId: true,
          evidence: { select: { normalizedPayload: true, videoId: true } },
        },
      },
    },
  });
  if (!row) throw new Error("recommendationNotFound");

  const structured = safeJsonObject(row.structuredPayload);
  const pendingRaw = structured.pendingMentions;
  const pending =
    pendingRaw != null && typeof pendingRaw === "object" && !Array.isArray(pendingRaw)
      ? (pendingRaw as Record<string, unknown>)
      : {};
  const pendingWeapons = Array.isArray(pending.weapons) ? pending.weapons : [];
  const pendingArtifacts = Array.isArray(pending.artifactSets)
    ? pending.artifactSets
    : [];
  const evidenceMentions = extractEvidenceMentions(
    row.contributions.map((c) => ({
      videoId: c.evidence.videoId || c.videoId,
      normalizedPayload: c.evidence.normalizedPayload,
    })),
  );

  const weaponQueries = [
    ...pendingWeapons.map((item) => {
      const map = item as Record<string, unknown>;
      return String(map.displayName || map.exactVisibleText || "").trim();
    }),
    ...evidenceMentions.weapons.map((m) =>
      String(m.exactVisibleText || m.displayName || "").trim(),
    ),
  ].filter(Boolean);
  const artifactQueries = [
    ...pendingArtifacts.map((item) => {
      const map = item as Record<string, unknown>;
      return String(map.displayName || map.exactVisibleText || "").trim();
    }),
    ...evidenceMentions.artifacts.map((m) =>
      String(m.exactVisibleText || m.displayName || "").trim(),
    ),
  ].filter(Boolean);

  const masters = await loadGearMasterMaps();
  const weaponMatches = await resolveEntitiesWithDeepSeek({
    kind: "weapon",
    queries: [...new Set(weaponQueries)].map((query) => ({ query })),
    allowedEntities: [...masters.weaponsById.values()],
  });
  const artifactMatches = await resolveEntitiesWithDeepSeek({
    kind: "artifact_set",
    queries: [...new Set(artifactQueries)].map((query) => ({ query })),
    allowedEntities: [...masters.setsById.values()],
  });

  return {
    recommendationId: row.id,
    weaponSuggestions: weaponMatches.map((m) => ({
      query: m.query,
      entityId: m.entityId,
      displayName: m.entityId
        ? (masters.weaponsById.get(m.entityId)?.name ?? null)
        : null,
      confidence: m.confidence,
    })),
    artifactSuggestions: artifactMatches.map((m) => ({
      query: m.query,
      entityId: m.entityId,
      displayName: m.entityId
        ? (masters.setsById.get(m.entityId)?.name ?? null)
        : null,
      confidence: m.confidence,
      pieces: m.pieces === 2 || m.pieces === 4 ? m.pieces : null,
    })),
  };
}

/**
 * Approve validated evidence and recommendations. Optionally publish.
 * Per-recommendation failures are skipped so the batch can continue.
 */
export async function autoPublishVisualRecommendations(input: {
  evidenceIds: readonly string[];
  recommendationIds: readonly string[];
  /** When false, stop after approve (一括採用). Default true. */
  publish?: boolean;
}): Promise<VisualAutoPublishResult> {
  const gate = await evaluateVisualAutoPublishGate();
  if (!gate.allowed) {
    return {
      evidenceApproved: 0,
      recommendationsApproved: 0,
      recommendationsPublished: 0,
      gearPromotedWeapons: 0,
      gearPromotedArtifacts: 0,
      skipped: input.recommendationIds.map((recommendationId) => ({
        recommendationId,
        reason: gate.reason,
      })),
    };
  }

  const shouldPublish = input.publish !== false;
  const evidenceApproved = await approveValidatedEvidence(input.evidenceIds);

  let recommendationsApproved = 0;
  let recommendationsPublished = 0;
  let gearPromotedWeapons = 0;
  let gearPromotedArtifacts = 0;
  const skipped: Array<{ recommendationId: string; reason: string }> = [];

  for (const recommendationId of input.recommendationIds) {
    try {
      const promotion = await applyGearPromotionToRecommendation(
        recommendationId,
      );
      if (promotion) {
        gearPromotedWeapons += promotion.promotedWeapons;
        gearPromotedArtifacts += promotion.promotedArtifacts;
      }

      const existing = await prisma.characterBuildRecommendation.findUnique({
        where: { id: recommendationId },
        select: { id: true, status: true, updatedAt: true },
      });
      if (!existing) {
        skipped.push({ recommendationId, reason: "recommendationNotFound" });
        continue;
      }

      if (existing.status === "rejected") {
        skipped.push({ recommendationId, reason: "rejected" });
        continue;
      }

      if (existing.status === "published") {
        recommendationsApproved += 1;
        recommendationsPublished += 1;
        continue;
      }

      const approved =
        existing.status === "approved"
          ? existing
          : await setRecommendationStatus({
              recommendationId: existing.id,
              status: "approved",
              expectedUpdatedAt: existing.updatedAt.toISOString(),
            });
      recommendationsApproved += 1;

      if (!shouldPublish) {
        continue;
      }

      // Re-evaluate Safety Switch before each publish (mid-batch emergency stop).
      const publishGate = await evaluateVisualAutoPublishGate();
      if (!publishGate.allowed) {
        skipped.push({
          recommendationId,
          reason: publishGate.reason,
        });
        break;
      }

      await setRecommendationStatus({
        recommendationId: approved.id,
        status: "published",
        expectedUpdatedAt: approved.updatedAt.toISOString(),
      });
      recommendationsPublished += 1;
    } catch (error) {
      skipped.push({
        recommendationId,
        reason: safeReason(error),
      });
    }
  }

  await prisma.guideAdminAuditLog.create({
    data: {
      actor: "system",
      action: shouldPublish ? "visual_auto_publish" : "visual_auto_approve",
      status: "ok",
      detail: JSON.stringify({
        evidenceApproved,
        recommendationsApproved,
        recommendationsPublished,
        gearPromotedWeapons,
        gearPromotedArtifacts,
        skippedCount: skipped.length,
        skipped: skipped.slice(0, 40),
      }).slice(0, 4_000),
    },
  });

  return {
    evidenceApproved,
    recommendationsApproved,
    recommendationsPublished,
    gearPromotedWeapons,
    gearPromotedArtifacts,
    skipped,
  };
}

async function listPendingVisualRecommendationBatch(limit: number) {
  const rows = await prisma.characterBuildRecommendation.findMany({
    where: {
      origin: "single_video",
      status: { in: ["pending_review", "approved"] },
      contributions: { some: {} },
    },
    orderBy: { updatedAt: "desc" },
    take: limit,
    select: {
      id: true,
      status: true,
      contributions: { select: { evidenceId: true } },
    },
  });
  const evidenceIds = [
    ...new Set(
      rows.flatMap((row) =>
        row.contributions.map((c) => c.evidenceId).filter(Boolean),
      ),
    ),
  ] as string[];
  return { rows, evidenceIds, recommendationIds: rows.map((row) => row.id) };
}

/**
 * Batch-approve (採用) evidence + recommendations without publishing.
 * Also adopts orphan validated evidences that are still pending_review.
 */
export async function approvePendingVisualRecommendations(input: {
  limit?: number;
} = {}): Promise<VisualAutoPublishResult & { scanned: number }> {
  const limit = Math.min(Math.max(input.limit ?? 20, 1), 50);
  const { evidenceIds, recommendationIds, rows } =
    await listPendingVisualRecommendationBatch(limit);

  const orphanEvidences = await prisma.guideVisualEvidence.findMany({
    where: {
      validationStatus: "validated",
      approvalStatus: "pending_review",
      ...(evidenceIds.length > 0 ? { id: { notIn: evidenceIds } } : {}),
    },
    orderBy: { updatedAt: "desc" },
    take: limit,
    select: { id: true },
  });
  const allEvidenceIds = [
    ...new Set([...evidenceIds, ...orphanEvidences.map((e) => e.id)]),
  ];

  const pendingRecommendationIds = rows
    .filter((row) => row.status === "pending_review")
    .map((row) => row.id);

  const result = await autoPublishVisualRecommendations({
    evidenceIds: allEvidenceIds,
    recommendationIds: pendingRecommendationIds,
    publish: false,
  });
  return {
    ...result,
    scanned: Math.max(rows.length, orphanEvidences.length),
  };
}

/**
 * Batch-publish existing visual-origin recommendations that are not yet published.
 */
export async function publishPendingVisualRecommendations(input: {
  limit?: number;
} = {}): Promise<VisualAutoPublishResult & { scanned: number }> {
  const limit = Math.min(Math.max(input.limit ?? 20, 1), 50);
  const { evidenceIds, recommendationIds, rows } =
    await listPendingVisualRecommendationBatch(limit);
  const result = await autoPublishVisualRecommendations({
    evidenceIds,
    recommendationIds,
    publish: true,
  });
  return { ...result, scanned: rows.length };
}

/**
 * Re-promote gear mentions on already approved/published visual recommendations
 * and republish when possible.
 */
export async function repromoteVisualGearMentions(input: {
  limit?: number;
} = {}): Promise<
  VisualAutoPublishResult & {
    scanned: number;
    republished: number;
  }
> {
  const limit = Math.min(Math.max(input.limit ?? 20, 1), 50);
  const gate = await evaluateVisualAutoPublishGate();
  if (!gate.allowed) {
    return {
      evidenceApproved: 0,
      recommendationsApproved: 0,
      recommendationsPublished: 0,
      gearPromotedWeapons: 0,
      gearPromotedArtifacts: 0,
      skipped: [],
      scanned: 0,
      republished: 0,
    };
  }

  const rows = await prisma.characterBuildRecommendation.findMany({
    where: {
      origin: "single_video",
      status: { in: ["approved", "published"] },
      contributions: { some: {} },
    },
    orderBy: { updatedAt: "desc" },
    take: limit,
    select: { id: true, status: true, updatedAt: true },
  });

  let gearPromotedWeapons = 0;
  let gearPromotedArtifacts = 0;
  let recommendationsApproved = 0;
  let recommendationsPublished = 0;
  let republished = 0;
  const skipped: Array<{ recommendationId: string; reason: string }> = [];

  for (const row of rows) {
    try {
      const promotion = await applyGearPromotionToRecommendation(row.id);
      if (promotion) {
        gearPromotedWeapons += promotion.promotedWeapons;
        gearPromotedArtifacts += promotion.promotedArtifacts;
      }

      const latest = await prisma.characterBuildRecommendation.findUnique({
        where: { id: row.id },
        select: { id: true, status: true, updatedAt: true },
      });
      if (!latest) {
        skipped.push({ recommendationId: row.id, reason: "recommendationNotFound" });
        continue;
      }

      if (latest.status === "approved") {
        recommendationsApproved += 1;
        await setRecommendationStatus({
          recommendationId: latest.id,
          status: "published",
          expectedUpdatedAt: latest.updatedAt.toISOString(),
        });
        recommendationsPublished += 1;
        republished += 1;
        continue;
      }

      if (latest.status === "published") {
        recommendationsApproved += 1;
        recommendationsPublished += 1;
        // Re-publish to refresh public snapshot with promoted gear.
        await setRecommendationStatus({
          recommendationId: latest.id,
          status: "published",
          expectedUpdatedAt: latest.updatedAt.toISOString(),
        });
        republished += 1;
      }
    } catch (error) {
      skipped.push({ recommendationId: row.id, reason: safeReason(error) });
    }
  }

  await prisma.guideAdminAuditLog.create({
    data: {
      actor: "system",
      action: "visual_gear_repromote",
      status: "ok",
      detail: JSON.stringify({
        scanned: rows.length,
        republished,
        gearPromotedWeapons,
        gearPromotedArtifacts,
        skippedCount: skipped.length,
        skipped: skipped.slice(0, 40),
      }).slice(0, 4_000),
    },
  });

  return {
    evidenceApproved: 0,
    recommendationsApproved,
    recommendationsPublished,
    gearPromotedWeapons,
    gearPromotedArtifacts,
    skipped,
    scanned: rows.length,
    republished,
  };
}
