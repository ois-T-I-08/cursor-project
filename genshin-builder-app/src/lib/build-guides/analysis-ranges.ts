export type AnalysisRange = {
  startSeconds: number;
  endSeconds: number;
  reason: string;
};

export class AnalysisRangeError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "AnalysisRangeError";
  }
}

export function normalizeAnalysisRanges(input: {
  ranges: AnalysisRange[];
  durationSeconds: number | null;
  maxRangeSeconds: number;
  maxRanges: number;
}): AnalysisRange[] {
  if (input.ranges.length === 0) {
    throw new AnalysisRangeError("rangesRequired");
  }
  if (input.ranges.length > input.maxRanges) {
    throw new AnalysisRangeError("tooManyRanges");
  }

  const normalized: AnalysisRange[] = [];
  for (const range of input.ranges) {
    if (
      !Number.isFinite(range.startSeconds) ||
      !Number.isFinite(range.endSeconds)
    ) {
      throw new AnalysisRangeError("rangeNotFinite");
    }
    if (range.startSeconds < 0 || range.endSeconds < 0) {
      throw new AnalysisRangeError("rangeNegative");
    }
    if (!(range.startSeconds < range.endSeconds)) {
      throw new AnalysisRangeError("rangeOrderInvalid");
    }
    const length = range.endSeconds - range.startSeconds;
    if (length > input.maxRangeSeconds) {
      throw new AnalysisRangeError("rangeTooLong");
    }
    if (
      input.durationSeconds != null &&
      (range.endSeconds > input.durationSeconds + 1 ||
        range.startSeconds > input.durationSeconds + 1)
    ) {
      throw new AnalysisRangeError("rangeBeyondDuration");
    }
    normalized.push({
      startSeconds: Math.floor(range.startSeconds),
      endSeconds: Math.ceil(range.endSeconds),
      reason: range.reason.slice(0, 200),
    });
  }
  return normalized.sort((a, b) => a.startSeconds - b.startSeconds);
}

export function timestampWithinRanges(
  startSeconds: number,
  endSeconds: number,
  ranges: AnalysisRange[],
  slackSeconds = 1,
): boolean {
  return ranges.some(
    (range) =>
      startSeconds >= range.startSeconds - slackSeconds &&
      endSeconds <= range.endSeconds + slackSeconds,
  );
}
