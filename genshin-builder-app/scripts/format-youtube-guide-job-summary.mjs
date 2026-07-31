import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const summaryKeys = [
  "pipelineRunId",
  "skipped",
  "dryRun",
  "discovered",
  "published",
  "ready",
  "reviewRequired",
  "blocked",
  "stopped",
  "retryable",
];

export function parseYoutubeGuideSummary(value) {
  if (!isPlainObject(value)) throw new Error("invalidPipelineSummary");
  let candidate = value;
  if ("ok" in value || "summary" in value) {
    if (
      value.ok !== true ||
      !hasExactKeys(value, ["ok", "summary"]) ||
      !isPlainObject(value.summary)
    ) {
      throw new Error("invalidPipelineApiResponse");
    }
    candidate = value.summary;
  }
  if (!hasExactKeys(candidate, summaryKeys)) {
    throw new Error("invalidPipelineSummaryFields");
  }
  if (
    typeof candidate.pipelineRunId !== "string" ||
    candidate.pipelineRunId.length < 1 ||
    candidate.pipelineRunId.length > 128 ||
    typeof candidate.skipped !== "boolean" ||
    typeof candidate.dryRun !== "boolean"
  ) {
    throw new Error("invalidPipelineSummaryTypes");
  }
  for (const key of summaryKeys.slice(3)) {
    if (
      typeof candidate[key] !== "number" ||
      !Number.isSafeInteger(candidate[key]) ||
      candidate[key] < 0
    ) {
      throw new Error("invalidPipelineSummaryCounts");
    }
  }
  return Object.freeze(
    Object.fromEntries(summaryKeys.map((key) => [key, candidate[key]])),
  );
}

export function formatYoutubeGuideJobSummary(value) {
  const summary = parseYoutubeGuideSummary(value);
  return (
    "## YouTube guide pipeline\n\n```json\n" +
    JSON.stringify(summary, null, 2) +
    "\n```\n"
  );
}

function isPlainObject(value) {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasExactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return (
    actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index])
  );
}

if (
  process.argv[1] &&
  pathToFileURL(process.argv[1]).href === import.meta.url
) {
  const [, , responsePath, outputPath] = process.argv;
  if (!responsePath || !outputPath) {
    throw new Error("summaryFormatterPathsRequired");
  }
  const response = JSON.parse(readFileSync(responsePath, "utf8"));
  appendFileSync(outputPath, formatYoutubeGuideJobSummary(response), "utf8");
}
