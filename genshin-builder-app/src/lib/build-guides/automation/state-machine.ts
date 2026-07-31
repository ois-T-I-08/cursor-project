export const PIPELINE_STATUSES = [
  "DISCOVERED",
  "METADATA_FETCHED",
  "TRANSCRIPT_FETCHED",
  "ANALYZING",
  "VALIDATING",
  "READY_TO_PUBLISH",
  "PUBLISHED",
  "RETRYABLE_ERROR",
  "BLOCKED",
] as const;

export type PipelineStatus = (typeof PIPELINE_STATUSES)[number];

const NEXT: Readonly<Record<PipelineStatus, ReadonlySet<PipelineStatus>>> = {
  DISCOVERED: new Set(["METADATA_FETCHED", "RETRYABLE_ERROR", "BLOCKED"]),
  METADATA_FETCHED: new Set(["TRANSCRIPT_FETCHED", "RETRYABLE_ERROR", "BLOCKED"]),
  TRANSCRIPT_FETCHED: new Set(["ANALYZING", "RETRYABLE_ERROR", "BLOCKED"]),
  ANALYZING: new Set(["VALIDATING", "RETRYABLE_ERROR", "BLOCKED"]),
  VALIDATING: new Set(["READY_TO_PUBLISH", "RETRYABLE_ERROR", "BLOCKED"]),
  READY_TO_PUBLISH: new Set(["PUBLISHED", "RETRYABLE_ERROR", "BLOCKED"]),
  PUBLISHED: new Set([]),
  RETRYABLE_ERROR: new Set([
    "METADATA_FETCHED",
    "TRANSCRIPT_FETCHED",
    "ANALYZING",
    "VALIDATING",
    "READY_TO_PUBLISH",
    "BLOCKED",
  ]),
  BLOCKED: new Set([]),
};

export class PipelineTransitionError extends Error {
  constructor(from: PipelineStatus, to: PipelineStatus) {
    super(`invalidPipelineTransition:${from}:${to}`);
    this.name = "PipelineTransitionError";
  }
}

export function assertPipelineTransition(
  from: PipelineStatus,
  to: PipelineStatus,
): void {
  if (!NEXT[from].has(to)) throw new PipelineTransitionError(from, to);
}

export function retryDelayMs(attempt: number, baseSeconds = 30): number {
  const normalized = Math.max(1, Math.min(10, Math.trunc(attempt)));
  return Math.min(3_600_000, baseSeconds * 1_000 * 2 ** (normalized - 1));
}

export function retryTarget(status: PipelineStatus): PipelineStatus | null {
  return status === "RETRYABLE_ERROR" ? null : status;
}
