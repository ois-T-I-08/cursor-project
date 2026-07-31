export const PIPELINE_STATUSES = [
  "DISCOVERED",
  "METADATA_FETCHED",
  "TRANSCRIPT_FETCHED",
  "ANALYZING",
  "VALIDATING",
  "READY_TO_PUBLISH",
  "REVIEW_REQUIRED",
  "PUBLISHED",
  "RETRYABLE_ERROR",
  "STOPPED",
  "BLOCKED",
] as const;

export type PipelineStatus = (typeof PIPELINE_STATUSES)[number];

const NEXT: Readonly<Record<PipelineStatus, ReadonlySet<PipelineStatus>>> = {
  DISCOVERED: new Set([
    "METADATA_FETCHED",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  METADATA_FETCHED: new Set([
    "TRANSCRIPT_FETCHED",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  TRANSCRIPT_FETCHED: new Set([
    "ANALYZING",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  ANALYZING: new Set([
    "VALIDATING",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  VALIDATING: new Set([
    "READY_TO_PUBLISH",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  READY_TO_PUBLISH: new Set([
    "REVIEW_REQUIRED",
    "PUBLISHED",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  REVIEW_REQUIRED: new Set([
    "METADATA_FETCHED",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  PUBLISHED: new Set([
    "METADATA_FETCHED",
    "RETRYABLE_ERROR",
    "STOPPED",
    "BLOCKED",
  ]),
  RETRYABLE_ERROR: new Set([
    "METADATA_FETCHED",
    "TRANSCRIPT_FETCHED",
    "ANALYZING",
    "VALIDATING",
    "READY_TO_PUBLISH",
    "STOPPED",
    "BLOCKED",
  ]),
  STOPPED: new Set(["METADATA_FETCHED", "BLOCKED"]),
  BLOCKED: new Set(["METADATA_FETCHED", "STOPPED"]),
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
