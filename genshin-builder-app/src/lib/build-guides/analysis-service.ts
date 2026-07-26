import "server-only";

import { DeepSeekError, DeepSeekJsonClient } from "@/lib/ai/deepseek-json-client";
import { buildGuideCacheKey } from "./cache-key";
import { loadCharacterHints, resolveCharacterCandidates } from "./character-match";
import { deepSeekGuideSettings } from "./deepseek-guide-settings";
import {
  EvidenceValidationError,
  toValidatedPublishablePayload,
  validateEvidenceAgainstTranscript,
} from "./evidence-validator";
import { GUIDE_SYSTEM_PROMPT, buildGuideUserPayload } from "./prompts";
import { aiGuideExtractionSchema, type AiGuideExtraction } from "./schemas";
import {
  createPendingRecommendationFromPayload,
  getCachedGuideResult,
  saveGuideAnalysisArtifacts,
  upsertAnalysisJob,
} from "./store";
import {
  chunkTranscript,
  hashTranscript,
  normalizeTranscript,
  TranscriptError,
  type TranscriptFormat,
} from "./transcript";
import {
  GUIDE_CHARACTER_DATA_VERSION,
  GUIDE_PROMPT_VERSION,
  GUIDE_SCHEMA_VERSION,
} from "./versions";

export class GuideAnalysisError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "GuideAnalysisError";
  }
}

function mergeExtractions(parts: AiGuideExtraction[]): AiGuideExtraction {
  if (parts.length === 0) {
    return aiGuideExtractionSchema.parse({});
  }
  const first = parts[0]!;
  const targets = [...first.targets];
  const mainStats = [...first.mainStats];
  const priority = [...first.substatPriority];
  const unresolved = new Set(first.unresolvedEntities);
  const caveats = new Set(first.caveats);
  let characterId = first.characterId;
  let characterNameHint = first.characterNameHint;
  let confidenceSum = first.overallConfidence;
  const context = { ...first.context };

  for (const part of parts.slice(1)) {
    if (!characterId && part.characterId) characterId = part.characterId;
    if (!characterNameHint && part.characterNameHint) {
      characterNameHint = part.characterNameHint;
    }
    for (const key of ["role", "teamArchetype", "weaponPreference", "notes"] as const) {
      if (!context[key] && part.context[key]) context[key] = part.context[key];
    }
    for (const target of part.targets) {
      if (!targets.some((t) => t.stat === target.stat && t.recommended === target.recommended)) {
        targets.push(target);
      }
    }
    for (const slot of part.mainStats) {
      if (!mainStats.some((m) => m.slot === slot.slot)) mainStats.push(slot);
    }
    for (const stat of part.substatPriority) {
      if (!priority.includes(stat)) priority.push(stat);
    }
    for (const item of part.unresolvedEntities) unresolved.add(item);
    for (const item of part.caveats) caveats.add(item);
    confidenceSum += part.overallConfidence;
  }

  return aiGuideExtractionSchema.parse({
    characterId,
    characterNameHint,
    unresolvedEntities: [...unresolved].slice(0, 20),
    context,
    mainStats: mainStats.slice(0, 6),
    substatPriority: priority.slice(0, 10),
    targets: targets.slice(0, 20),
    overallConfidence: confidenceSum / parts.length,
    caveats: [...caveats].slice(0, 10),
  });
}

export async function analyzeVideoTranscript(input: {
  videoId: string;
  title: string;
  description: string;
  transcriptRaw: string;
  format?: TranscriptFormat;
  force?: boolean;
  client?: DeepSeekJsonClient;
}): Promise<{
  jobId: string;
  cacheKey: string;
  recommendationId?: string;
  characterId?: string;
  status: string;
}> {
  let transcript;
  try {
    transcript = normalizeTranscript(input.transcriptRaw, { format: input.format });
  } catch (error) {
    if (error instanceof TranscriptError) throw new GuideAnalysisError(error.code);
    throw error;
  }

  const transcriptHash = hashTranscript(transcript.normalizedText);
  const settings = deepSeekGuideSettings();
  const cacheKey = buildGuideCacheKey({
    videoId: input.videoId,
    transcriptHash,
    characterDataVersion: GUIDE_CHARACTER_DATA_VERSION,
    promptVersion: GUIDE_PROMPT_VERSION,
    schemaVersion: GUIDE_SCHEMA_VERSION,
    modelIdentifier: settings.model,
  });

  if (!input.force) {
    const cached = await getCachedGuideResult(cacheKey);
    if (cached) {
      return {
        jobId: cached.jobId,
        cacheKey,
        recommendationId: cached.recommendationId,
        characterId: cached.characterId,
        status: cached.status,
      };
    }
  }

  const job = await upsertAnalysisJob({
    videoId: input.videoId,
    transcriptHash,
    inputFormat: transcript.format,
    status: "running",
    modelIdentifier: settings.model,
    promptVersion: GUIDE_PROMPT_VERSION,
    schemaVersion: GUIDE_SCHEMA_VERSION,
    characterDataVersion: GUIDE_CHARACTER_DATA_VERSION,
    segmentCount: transcript.segments.length,
    charCount: transcript.charCount,
  });

  const hints = await loadCharacterHints();
  const { matchedIds } = resolveCharacterCandidates(
    input.title,
    input.description,
    hints,
  );
  const allowedCharacterIds =
    matchedIds.length > 0 ? matchedIds : hints.slice(0, 80).map((h) => h.id);
  const characterHints = hints.filter((h) => allowedCharacterIds.includes(h.id));

  const chunks = chunkTranscript(transcript);
  const client = input.client ?? new DeepSeekJsonClient();
  const extractions: AiGuideExtraction[] = [];
  let attempts = 0;
  const usageAcc: Record<string, number> = {};

  try {
    for (const chunk of chunks) {
      const completion = await client.completeJson({
        settings: {
          apiKey: settings.apiKey,
          model: settings.model,
          timeoutMs: settings.timeoutMs,
          maxAttempts: settings.maxAttempts,
          maxTokens: 4096,
          userAgent: "genshin-builder/1.0 (build-guide-analysis)",
        },
        systemPrompt: GUIDE_SYSTEM_PROMPT,
        userContent: buildGuideUserPayload({
          videoId: input.videoId,
          title: input.title,
          description: input.description,
          allowedCharacterIds,
          characterHints,
          chunkIndex: chunk.chunkIndex,
          chunkCount: chunks.length,
          chunkText: chunk.text,
          segments: chunk.segments,
        }),
      });
      attempts += completion.attempts;
      for (const [key, value] of Object.entries(completion.usage)) {
        usageAcc[key] = (usageAcc[key] ?? 0) + value;
      }
      let decoded: unknown;
      try {
        decoded = JSON.parse(completion.content) as unknown;
      } catch {
        throw new GuideAnalysisError("invalidJson");
      }
      const parsed = aiGuideExtractionSchema.parse(decoded);
      extractions.push(parsed);
    }

    const merged = mergeExtractions(extractions);
    validateEvidenceAgainstTranscript(merged, transcript);

    let characterId = merged.characterId;
    if (characterId && !allowedCharacterIds.includes(characterId)) {
      merged.unresolvedEntities = [
        ...new Set([...(merged.unresolvedEntities ?? []), characterId]),
      ];
      characterId = undefined;
    }
    if (!characterId && matchedIds.length === 1) {
      characterId = matchedIds[0];
    }
    if (!characterId) {
      throw new GuideAnalysisError("characterUnresolved");
    }

    const validated = toValidatedPublishablePayload(merged, characterId);
    const saved = await saveGuideAnalysisArtifacts({
      jobId: job.id,
      cacheKey,
      videoId: input.videoId,
      transcriptHash,
      characterId,
      modelIdentifier: settings.model,
      promptVersion: GUIDE_PROMPT_VERSION,
      schemaVersion: GUIDE_SCHEMA_VERSION,
      characterDataVersion: GUIDE_CHARACTER_DATA_VERSION,
      rawAiOutput: JSON.stringify(merged),
      validated,
      usagePayload: JSON.stringify(usageAcc),
      attempts,
    });

    const recommendationId = await createPendingRecommendationFromPayload({
      characterId,
      videoId: input.videoId,
      payload: validated,
      origin: "single_video",
    });

    return {
      jobId: job.id,
      cacheKey,
      recommendationId,
      characterId,
      status: saved.status,
    };
  } catch (error) {
    const code =
      error instanceof GuideAnalysisError ||
      error instanceof EvidenceValidationError ||
      error instanceof DeepSeekError ||
      (error instanceof Error && /^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(error.message))
        ? error instanceof Error
          ? error.message
          : "analysisFailed"
        : "analysisFailed";
    await upsertAnalysisJob({
      videoId: input.videoId,
      transcriptHash,
      inputFormat: transcript.format,
      status: "failed",
      modelIdentifier: settings.model,
      promptVersion: GUIDE_PROMPT_VERSION,
      schemaVersion: GUIDE_SCHEMA_VERSION,
      characterDataVersion: GUIDE_CHARACTER_DATA_VERSION,
      segmentCount: transcript.segments.length,
      charCount: transcript.charCount,
      errorCode: code,
      attempts,
      usagePayload: JSON.stringify(usageAcc),
      jobId: job.id,
    });
    throw new GuideAnalysisError(code);
  }
}
