import "server-only";

import { DeepSeekError } from "@/lib/ai/deepseek-json-client";
import {
  configuredDailyPlanModel,
  isDeepSeekDailyPlanEnabled,
} from "./deepseek-daily-plan-settings";
import { DeepSeekDailyPlanClient } from "./deepseek-client";
import {
  dailyPlanCacheIdentity,
  dailyPlanCacheKey,
  dailyPlanInputHash,
} from "./daily-plan-cache-key";
import {
  buildDeterministicDailyPlanProposal,
  validateAndFinalizeDailyPlan,
} from "./final-validator";
import type {
  DailyPlanEnrichRequest,
  DailyPlanGenerationMetadata,
  DailyPlanProposal,
} from "./types";

const CACHE_TTL_MS = 15 * 60 * 1000;
const MAX_CACHE_ENTRIES = 100;

interface CachedProposal {
  proposal: DailyPlanProposal;
  metadata: DailyPlanGenerationMetadata;
  expiresAt: number;
}

const cache = new Map<string, CachedProposal>();
const inFlight = new Map<string, Promise<DailyPlanProposal>>();

export async function enrichDailyPlan(
  request: DailyPlanEnrichRequest,
  options: {
    client?: DeepSeekDailyPlanClient;
    env?: Readonly<Record<string, string | undefined>>;
    now?: Date;
  } = {},
): Promise<DailyPlanProposal> {
  const env = options.env ?? process.env;
  const now = options.now ?? new Date();
  const modelIdentifier = configuredDailyPlanModel(env);
  const identity = dailyPlanCacheIdentity(request, modelIdentifier);
  const cacheKey = dailyPlanCacheKey(identity);
  const inputHash = dailyPlanInputHash(identity);
  const enabled = isDeepSeekDailyPlanEnabled(env);

  if (enabled && !request.force) {
    const cached = readCache(cacheKey, now.getTime());
    if (cached) return cached.proposal;
    const pending = inFlight.get(cacheKey);
    if (pending) return pending;
  }

  if (!enabled) {
    return buildDeterministicDailyPlanProposal(
      request,
      inputHash,
      now,
      "dailyPlanDisabled",
    );
  }

  const generate = generateProposal({
    request,
    inputHash,
    modelIdentifier,
    client: options.client ?? new DeepSeekDailyPlanClient(),
    env,
    now,
    cacheKey,
  });

  if (!request.force) inFlight.set(cacheKey, generate);
  try {
    return await generate;
  } finally {
    if (inFlight.get(cacheKey) === generate) inFlight.delete(cacheKey);
  }
}

async function generateProposal(input: {
  request: DailyPlanEnrichRequest;
  inputHash: string;
  modelIdentifier: string;
  client: DeepSeekDailyPlanClient;
  env: Readonly<Record<string, string | undefined>>;
  now: Date;
  cacheKey: string;
}): Promise<DailyPlanProposal> {
  let metadata: DailyPlanGenerationMetadata;
  try {
    const evaluation = await input.client.evaluate(input.request, input.env);
    const proposal = validateAndFinalizeDailyPlan(
      evaluation.result,
      input.request,
      input.inputHash,
      evaluation.modelIdentifier,
      input.now,
    );
    metadata = {
      inputHash: input.inputHash,
      candidateCount: input.request.candidates.length,
      modelIdentifier: evaluation.modelIdentifier,
      attempts: evaluation.attempts,
      usage: evaluation.usage,
      generatedAt: proposal.generatedAt,
      source: proposal.source,
    };
    writeCache(input.cacheKey, proposal, metadata, input.now.getTime());
    return proposal;
  } catch (error) {
    const safeErrorCode =
      error instanceof DeepSeekError ? error.code : "dailyPlanGenerationFailed";
    return buildDeterministicDailyPlanProposal(
      input.request,
      input.inputHash,
      input.now,
      safeErrorCode,
    );
  }
}

function readCache(cacheKey: string, nowMs: number): CachedProposal | null {
  const cached = cache.get(cacheKey);
  if (!cached) return null;
  if (cached.expiresAt <= nowMs) {
    cache.delete(cacheKey);
    return null;
  }
  return cached;
}

function writeCache(
  cacheKey: string,
  proposal: DailyPlanProposal,
  metadata: DailyPlanGenerationMetadata,
  nowMs: number,
): void {
  if (cache.size >= MAX_CACHE_ENTRIES && !cache.has(cacheKey)) {
    const oldest = cache.keys().next().value as string | undefined;
    if (oldest) cache.delete(oldest);
  }
  cache.set(cacheKey, {
    proposal,
    metadata,
    expiresAt: nowMs + CACHE_TTL_MS,
  });
}

export function resetDailyPlanCacheForTest(): void {
  cache.clear();
  inFlight.clear();
}

export function getDailyPlanCacheMetadataForTest(
  cacheKey: string,
): DailyPlanGenerationMetadata | null {
  return cache.get(cacheKey)?.metadata ?? null;
}
