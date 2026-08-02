import "server-only";

import {
  applyEntityMatchesToWeaponMentions,
  resolveEntitiesWithDeepSeek,
} from "@/lib/build-guides/deepseek-entity-resolve";
import { isDeepSeekGuideAnalysisEnabled } from "@/lib/build-guides/deepseek-guide-settings";
import type { MasterNameEntry } from "@/lib/build-guides/visual-gear-promote";
import type { TranscriptAnalysis, TranscriptClaim } from "./analysis-schema";

function norm(value: string): string {
  return value.trim().normalize("NFC");
}

/**
 * Soft-resolve transcript claim entityIds against an allowlist.
 * 1) Exact name match (deterministic)
 * 2) DeepSeek allowlist match when guide analysis is enabled
 * Unknown IDs that cannot be resolved are cleared to null (caller may still block).
 */
export async function softResolveTranscriptAnalysis(input: {
  analysis: TranscriptAnalysis;
  entities: readonly MasterNameEntry[];
}): Promise<TranscriptAnalysis> {
  const byId = new Map(input.entities.map((e) => [e.id, e]));
  const byName = new Map<string, MasterNameEntry>();
  for (const entry of input.entities) {
    const key = norm(entry.name);
    if (key && !byName.has(key)) byName.set(key, entry);
  }

  let claims: TranscriptClaim[] = input.analysis.claims.map((claim) => {
    if (claim.entityId && byId.has(claim.entityId)) return claim;
    const byValue = byName.get(norm(claim.value));
    if (byValue) {
      return { ...claim, entityId: byValue.id };
    }
    if (claim.entityId && !byId.has(claim.entityId)) {
      return { ...claim, entityId: null };
    }
    return claim;
  });

  if (!isDeepSeekGuideAnalysisEnabled()) {
    return { ...input.analysis, claims };
  }

  const unresolved = claims.filter(
    (c) =>
      !c.entityId &&
      (c.kind === "weapon" || c.kind === "artifact_set") &&
      c.value.trim(),
  );
  if (unresolved.length === 0) {
    return { ...input.analysis, claims };
  }

  // Resolve weapons and artifact sets separately.
  // Master rows are untyped here; pass full allowlist and rely on DeepSeek + post filter.
  const weaponQueries = unresolved
    .filter((c) => c.kind === "weapon")
    .map((c) => ({ query: c.value, contextTexts: [c.evidenceText] }));
  const artifactQueries = unresolved
    .filter((c) => c.kind === "artifact_set")
    .map((c) => ({ query: c.value, contextTexts: [c.evidenceText] }));

  if (weaponQueries.length > 0) {
    const matches = await resolveEntitiesWithDeepSeek({
      kind: "weapon",
      queries: weaponQueries,
      allowedEntities: input.entities,
    });
    const applied = applyEntityMatchesToWeaponMentions({
      mentions: weaponQueries.map((q) => ({ exactVisibleText: q.query })),
      matches,
    });
    const byQuery = new Map(
      applied
        .filter((m) => m.normalizedWeaponId)
        .map((m) => [norm(String(m.exactVisibleText)), m.normalizedWeaponId!] as const),
    );
    claims = claims.map((claim) => {
      if (claim.kind !== "weapon" || claim.entityId) return claim;
      const id = byQuery.get(norm(claim.value));
      return id ? { ...claim, entityId: id } : claim;
    });
  }

  if (artifactQueries.length > 0) {
    const matches = await resolveEntitiesWithDeepSeek({
      kind: "artifact_set",
      queries: artifactQueries,
      allowedEntities: input.entities,
    });
    const byQuery = new Map(
      matches
        .filter((m) => m.entityId)
        .map((m) => [norm(m.query), m.entityId!] as const),
    );
    claims = claims.map((claim) => {
      if (claim.kind !== "artifact_set" || claim.entityId) return claim;
      const id = byQuery.get(norm(claim.value));
      return id ? { ...claim, entityId: id } : claim;
    });
  }

  return { ...input.analysis, claims };
}
