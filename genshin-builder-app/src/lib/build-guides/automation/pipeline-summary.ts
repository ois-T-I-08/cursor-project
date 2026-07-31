import { z } from "zod";

const pipelineRunSummarySchema = z.strictObject({
  pipelineRunId: z.string().min(1).max(128),
  skipped: z.boolean(),
  dryRun: z.boolean(),
  discovered: z.number().int().nonnegative(),
  published: z.number().int().nonnegative(),
  ready: z.number().int().nonnegative(),
  reviewRequired: z.number().int().nonnegative(),
  blocked: z.number().int().nonnegative(),
  stopped: z.number().int().nonnegative(),
  retryable: z.number().int().nonnegative(),
});

export type PipelineRunSummary = Readonly<
  z.infer<typeof pipelineRunSummarySchema>
>;

export function buildPipelineRunSummary(input: unknown): PipelineRunSummary {
  return Object.freeze(pipelineRunSummarySchema.parse(input));
}

export function parsePipelineRunSummary(
  payload: string,
): PipelineRunSummary | null {
  try {
    const parsed = pipelineRunSummarySchema.safeParse(
      JSON.parse(payload) as unknown,
    );
    return parsed.success ? Object.freeze(parsed.data) : null;
  } catch {
    return null;
  }
}

export function serializePipelineRunSummary(
  summary: PipelineRunSummary,
): string {
  return JSON.stringify(buildPipelineRunSummary(summary));
}

export function buildPipelineRunSuccessResponse(summary: unknown): Readonly<{
  ok: true;
  summary: PipelineRunSummary;
}> {
  return Object.freeze({
    ok: true,
    summary: buildPipelineRunSummary(summary),
  });
}
