import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  buildPipelineRunSuccessResponse,
  buildPipelineRunSummary,
  parsePipelineRunSummary,
  serializePipelineRunSummary,
} from "@/lib/build-guides/automation/pipeline-summary";

const rawMarker = "RAW_SUMMARY_MARKER_MUST_NOT_LEAK";
const safeSummary = {
  pipelineRunId: "summary-test-run",
  skipped: false,
  dryRun: true,
  discovered: 2,
  published: 1,
  ready: 0,
  reviewRequired: 1,
  blocked: 0,
  stopped: 0,
  retryable: 0,
};

describe("YouTube automation safe summaries", () => {
  it("round-trips only the strict summary allowlist", () => {
    const summary = buildPipelineRunSummary(safeSummary);
    expect(parsePipelineRunSummary(serializePipelineRunSummary(summary))).toEqual(
      safeSummary,
    );
    expect(
      parsePipelineRunSummary(
        JSON.stringify({ ...safeSummary, rawTranscript: rawMarker }),
      ),
    ).toBeNull();
    expect(() =>
      buildPipelineRunSummary({
        ...safeSummary,
        errorMessage: rawMarker,
      }),
    ).toThrow();
  });

  it("uses the workflow formatter for the strict API success response", () => {
    const temp = mkdtempSync(join(tmpdir(), "youtube-job-summary-"));
    const responsePath = join(temp, "response.json");
    const outputPath = join(temp, "job-summary.md");
    const script = resolve(
      process.cwd(),
      "scripts",
      "format-youtube-guide-job-summary.mjs",
    );
    writeFileSync(
      responsePath,
      JSON.stringify(
        buildPipelineRunSuccessResponse(
          buildPipelineRunSummary(safeSummary),
        ),
      ),
      "utf8",
    );
    writeFileSync(outputPath, "", "utf8");
    execFileSync(process.execPath, [script, responsePath, outputPath]);
    const output = readFileSync(outputPath, "utf8");
    expect(output).toContain("## YouTube guide pipeline");
    expect(output).toContain('"reviewRequired": 1');
    expect(output).not.toContain(rawMarker);

    writeFileSync(
      responsePath,
      JSON.stringify({
        ok: true,
        summary: { ...safeSummary, rawProviderResponse: rawMarker },
      }),
      "utf8",
    );
    expect(() =>
      execFileSync(process.execPath, [script, responsePath, outputPath], {
        stdio: "pipe",
      }),
    ).toThrow();
    expect(readFileSync(outputPath, "utf8")).toBe(output);
  });
});
