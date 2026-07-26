import { describe, expect, it } from "vitest";
import {
  snippetExistsInTranscript,
  toValidatedPublishablePayload,
  validateEvidenceAgainstTranscript,
  EvidenceValidationError,
} from "../build-guides/evidence-validator";
import { mergeGuidePayloads } from "../build-guides/merge-service";
import { normalizeTranscript } from "../build-guides/transcript/normalize";
import type { ValidatedGuidePayload } from "../build-guides/schemas";

describe("evidence and merge", () => {
  it("accepts verbatim snippets and rejects mismatches", () => {
    const transcript = normalizeTranscript("会心率は70パーセントを目指します");
    expect(snippetExistsInTranscript("会心率は70", transcript)).toBe(true);
    expect(() =>
      validateEvidenceAgainstTranscript(
        {
          unresolvedEntities: [],
          context: {},
          mainStats: [],
          substatPriority: [],
          targets: [
            {
              stat: "critRate",
              recommended: 70,
              inferred: false,
              evidence: { snippet: "存在しない文言" },
            },
          ],
          overallConfidence: 0.5,
          caveats: [],
        },
        transcript,
      ),
    ).toThrowError(EvidenceValidationError);
  });

  it("requires evidence for numeric non-inferred targets", () => {
    const transcript = normalizeTranscript("会心率は70パーセントを目指します");
    expect(() =>
      validateEvidenceAgainstTranscript(
        {
          unresolvedEntities: [],
          context: {},
          mainStats: [],
          substatPriority: [],
          targets: [{ stat: "critRate", recommended: 70, inferred: false }],
          overallConfidence: 0.5,
          caveats: [],
        },
        transcript,
      ),
    ).toThrowError(/evidenceRequiredForNumericTarget/);
  });

  it("rejects timestamp that does not match the segment", () => {
    const transcript = normalizeTranscript(`WEBVTT

00:00:01.000 --> 00:00:03.000
会心率は70パーセント
`);
    expect(() =>
      validateEvidenceAgainstTranscript(
        {
          unresolvedEntities: [],
          context: {},
          mainStats: [],
          substatPriority: [],
          targets: [
            {
              stat: "critRate",
              recommended: 70,
              inferred: false,
              evidence: {
                snippet: "会心率は70",
                segmentIndex: 0,
                startMs: 9999,
                endMs: 3000,
              },
            },
          ],
          overallConfidence: 0.5,
          caveats: [],
        },
        transcript,
      ),
    ).toThrowError(EvidenceValidationError);
  });

  it("strips inferred targets from publishable payload", () => {
    const payload = toValidatedPublishablePayload(
      {
        characterId: "hu-tao",
        unresolvedEntities: [],
        context: {},
        mainStats: [],
        substatPriority: ["critRate"],
        targets: [
          {
            stat: "critRate",
            recommended: 70,
            inferred: false,
            evidence: { snippet: "会心率は70" },
          },
          { stat: "er", recommended: 120, inferred: true },
        ],
        overallConfidence: 0.8,
        caveats: [],
      },
      "hu-tao",
    );
    expect(payload.targets).toHaveLength(1);
    expect(payload.targets[0]?.stat).toBe("critRate");
  });

  it("detects blocking conflicts across videos", () => {
    const base: ValidatedGuidePayload = {
      characterId: "hu-tao",
      context: { role: "dps" },
      mainStats: [],
      substatPriority: ["critRate"],
      targets: [
        {
          stat: "critRate",
          recommended: 70,
          inferred: false,
          evidence: { snippet: "70" },
        },
      ],
      overallConfidence: 0.7,
      caveats: [],
      unresolvedEntities: [],
    };
    const merged = mergeGuidePayloads("hu-tao", [
      { videoId: "abcdefghijk", payload: base },
      {
        videoId: "lmnopqrstuv",
        payload: {
          ...base,
          targets: [
            {
              stat: "critRate",
              recommended: 90,
              inferred: false,
              evidence: { snippet: "90" },
            },
          ],
        },
      },
    ]);
    expect(merged.conflicts.some((c) => c.severity === "blocking")).toBe(true);
  });
});
