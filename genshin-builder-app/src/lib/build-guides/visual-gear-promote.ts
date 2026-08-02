/**
 * Auto-promote OCR gear mentions into publishable structured fields.
 * Used only when BUILD_GUIDE_VISUAL_AUTO_PUBLISH is enabled.
 */

export type GearMentionWeapon = {
  exactVisibleText?: string | null;
  normalizedWeaponId?: string | null;
  weaponId?: string | null;
  displayName?: string | null;
  videoId?: string | null;
  confidence?: number | null;
};

export type GearMentionArtifact = {
  exactVisibleText?: string | null;
  normalizedArtifactSetId?: string | null;
  setId?: string | null;
  displayName?: string | null;
  videoId?: string | null;
  confidence?: number | null;
  /** Optional DeepSeek/admin suggestion: 2 or 4 only. */
  suggestedPieces?: number | null;
};

export type MasterNameEntry = Readonly<{ id: string; name: string }>;

export type GearPromotionResult = Readonly<{
  structured: Record<string, unknown>;
  promotedWeapons: number;
  promotedArtifacts: number;
  deferredWeapons: number;
  deferredArtifacts: number;
}>;

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function normName(value: string | null | undefined): string {
  return (value ?? "").trim().normalize("NFC");
}

function resolveWeapon(
  mention: GearMentionWeapon,
  weaponsById: ReadonlyMap<string, MasterNameEntry>,
  weaponsByName: ReadonlyMap<string, MasterNameEntry>,
): MasterNameEntry | null {
  const idCandidates = [
    mention.normalizedWeaponId,
    mention.weaponId,
  ].filter((v): v is string => typeof v === "string" && v.trim().length > 0);
  for (const id of idCandidates) {
    const hit = weaponsById.get(id.trim());
    if (hit) return hit;
  }
  const nameCandidates = [
    mention.exactVisibleText,
    mention.displayName,
  ].filter((v): v is string => typeof v === "string" && v.trim().length > 0);
  for (const name of nameCandidates) {
    const hit = weaponsByName.get(normName(name));
    if (hit) return hit;
  }
  return null;
}

function resolveArtifactSet(
  mention: GearMentionArtifact,
  setsById: ReadonlyMap<string, MasterNameEntry>,
  setsByName: ReadonlyMap<string, MasterNameEntry>,
): MasterNameEntry | null {
  const idCandidates = [
    mention.normalizedArtifactSetId,
    mention.setId,
  ].filter((v): v is string => typeof v === "string" && v.trim().length > 0);
  for (const id of idCandidates) {
    const hit = setsById.get(id.trim());
    if (hit) return hit;
  }
  const nameCandidates = [
    mention.exactVisibleText,
    mention.displayName,
  ].filter((v): v is string => typeof v === "string" && v.trim().length > 0);
  for (const name of nameCandidates) {
    const hit = setsByName.get(normName(name));
    if (hit) return hit;
  }
  return null;
}

function collectWeaponMentions(
  structured: Record<string, unknown>,
  evidenceWeapons: readonly GearMentionWeapon[],
): GearMentionWeapon[] {
  const pending = asRecord(structured.pendingMentions);
  const fromPending = asArray(pending.weapons).map((item) => {
    const map = asRecord(item);
    return {
      exactVisibleText:
        typeof map.displayName === "string"
          ? map.displayName
          : typeof map.exactVisibleText === "string"
            ? map.exactVisibleText
            : null,
      weaponId: typeof map.weaponId === "string" ? map.weaponId : null,
      normalizedWeaponId:
        typeof map.normalizedWeaponId === "string"
          ? map.normalizedWeaponId
          : null,
      displayName: typeof map.displayName === "string" ? map.displayName : null,
      videoId: typeof map.videoId === "string" ? map.videoId : null,
      confidence: typeof map.confidence === "number" ? map.confidence : null,
    } satisfies GearMentionWeapon;
  });
  return [...evidenceWeapons, ...fromPending];
}

function collectArtifactMentions(
  structured: Record<string, unknown>,
  evidenceArtifacts: readonly GearMentionArtifact[],
): GearMentionArtifact[] {
  const pending = asRecord(structured.pendingMentions);
  const fromPending = asArray(pending.artifactSets).map((item) => {
    const map = asRecord(item);
    return {
      exactVisibleText:
        typeof map.displayName === "string"
          ? map.displayName
          : typeof map.exactVisibleText === "string"
            ? map.exactVisibleText
            : null,
      setId: typeof map.setId === "string" ? map.setId : null,
      normalizedArtifactSetId:
        typeof map.normalizedArtifactSetId === "string"
          ? map.normalizedArtifactSetId
          : null,
      displayName: typeof map.displayName === "string" ? map.displayName : null,
      videoId: typeof map.videoId === "string" ? map.videoId : null,
      confidence: typeof map.confidence === "number" ? map.confidence : null,
    } satisfies GearMentionArtifact;
  });
  return [...evidenceArtifacts, ...fromPending];
}

/**
 * Promote ID/name-resolved gear mentions into structured publishable fields.
 * Clears pendingMentions so auto-publish is not blocked by unresolved leftovers.
 */
export function promoteResolvedGearMentionsForAutoPublish(input: {
  structured: Record<string, unknown>;
  evidenceWeapons?: readonly GearMentionWeapon[];
  evidenceArtifacts?: readonly GearMentionArtifact[];
  weaponsById: ReadonlyMap<string, MasterNameEntry>;
  weaponsByName: ReadonlyMap<string, MasterNameEntry>;
  setsById: ReadonlyMap<string, MasterNameEntry>;
  setsByName: ReadonlyMap<string, MasterNameEntry>;
}): GearPromotionResult {
  const structured = { ...input.structured };
  const weaponMentions = collectWeaponMentions(
    structured,
    input.evidenceWeapons ?? [],
  );
  const artifactMentions = collectArtifactMentions(
    structured,
    input.evidenceArtifacts ?? [],
  );

  const existingWeapons = asArray(structured.weapons).map((item) =>
    asRecord(item),
  );
  const seenWeaponIds = new Set(
    existingWeapons
      .map((w) => (typeof w.weaponId === "string" ? w.weaponId : null))
      .filter((id): id is string => Boolean(id)),
  );

  const promotedWeaponRows: Record<string, unknown>[] = [...existingWeapons];
  let deferredWeapons = 0;
  for (const mention of weaponMentions) {
    const resolved = resolveWeapon(
      mention,
      input.weaponsById,
      input.weaponsByName,
    );
    if (!resolved) {
      deferredWeapons += 1;
      continue;
    }
    if (seenWeaponIds.has(resolved.id)) continue;
    seenWeaponIds.add(resolved.id);
    const citationId =
      typeof mention.videoId === "string" && mention.videoId.trim()
        ? `source-${mention.videoId.trim()}`
        : null;
    promotedWeaponRows.push({
      weaponId: resolved.id,
      displayName: resolved.name,
      rank: promotedWeaponRows.length + 1,
      recommendationLevel: null,
      reason: "",
      conditions: [],
      role: null,
      citationId,
      dataOrigin: "structured",
      adminConfirmed: true,
    });
  }

  // Re-rank after merge.
  const weapons = promotedWeaponRows.slice(0, 12).map((row, index) => ({
    ...row,
    rank: index + 1,
  }));
  const promotedWeapons = Math.max(
    0,
    weapons.length - existingWeapons.length,
  );

  const resolvedSets: Array<{
    entry: MasterNameEntry;
    videoId: string | null;
    pieces: 2 | 4;
  }> = [];
  const seenSetIds = new Set<string>();
  let deferredArtifacts = 0;
  for (const mention of artifactMentions) {
    const resolved = resolveArtifactSet(
      mention,
      input.setsById,
      input.setsByName,
    );
    if (!resolved) {
      deferredArtifacts += 1;
      continue;
    }
    if (seenSetIds.has(resolved.id)) continue;
    seenSetIds.add(resolved.id);
    const suggested =
      mention.suggestedPieces === 2 || mention.suggestedPieces === 4
        ? mention.suggestedPieces
        : 4;
    resolvedSets.push({
      entry: resolved,
      videoId:
        typeof mention.videoId === "string" && mention.videoId.trim()
          ? mention.videoId.trim()
          : null,
      pieces: suggested,
    });
  }

  const existingArtifacts = asArray(structured.artifactRecommendations).map(
    (item) => asRecord(item),
  );
  let artifactRecommendations = existingArtifacts;
  let promotedArtifacts = 0;
  // Only auto-promote a single resolved set (no 4+2 guessing).
  if (resolvedSets.length === 1 && existingArtifacts.length === 0) {
    const only = resolvedSets[0]!;
    artifactRecommendations = [
      {
        sets: [{ setId: only.entry.id, pieces: only.pieces }],
        rank: 1,
        recommendationLevel: null,
        reason: "",
        conditions: [],
        role: null,
        isAlternative: false,
        citationId: only.videoId ? `source-${only.videoId}` : null,
        dataOrigin: "structured",
        adminConfirmed: true,
      },
    ];
    promotedArtifacts = 1;
  } else if (resolvedSets.length > 1) {
    deferredArtifacts += resolvedSets.length;
  }

  structured.weapons = weapons;
  structured.artifactRecommendations = artifactRecommendations;
  structured.pendingMentions = { weapons: [], artifactSets: [] };
  if (deferredWeapons > 0 || deferredArtifacts > 0) {
    structured.deferredMentions = {
      weapons: deferredWeapons,
      artifactSets: deferredArtifacts,
    };
  } else {
    delete structured.deferredMentions;
  }

  return {
    structured,
    promotedWeapons,
    promotedArtifacts,
    deferredWeapons,
    deferredArtifacts,
  };
}

export function buildMasterNameMaps(
  entries: readonly MasterNameEntry[],
): {
  byId: Map<string, MasterNameEntry>;
  byName: Map<string, MasterNameEntry>;
} {
  const byId = new Map<string, MasterNameEntry>();
  const byName = new Map<string, MasterNameEntry>();
  for (const entry of entries) {
    byId.set(entry.id, entry);
    const key = normName(entry.name);
    if (key && !byName.has(key)) {
      byName.set(key, entry);
    }
  }
  return { byId, byName };
}
