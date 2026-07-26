import { describe, expect, it } from "vitest";
import { chunkTranscript } from "../build-guides/transcript/chunk";
import { hashTranscript } from "../build-guides/transcript/hash";
import {
  normalizeTranscript,
  TranscriptError,
} from "../build-guides/transcript/normalize";

describe("build-guide transcript", () => {
  it("parses txt / vtt / srt and hashes deterministically", () => {
    const txt = normalizeTranscript("会心率は70%\n元素チャージは180");
    expect(txt.format).toBe("txt");
    expect(txt.segments).toHaveLength(2);

    const vtt = normalizeTranscript(`WEBVTT

00:00:01.000 --> 00:00:03.000
会心率は70%

00:00:03.000 --> 00:00:05.000
元素チャージは180
`);
    expect(vtt.format).toBe("vtt");
    expect(vtt.segments[0]?.startMs).toBe(1000);

    const srt = normalizeTranscript(`1
00:00:01,000 --> 00:00:03,000
会心率は70%

2
00:00:03,000 --> 00:00:05,000
元素チャージは180
`);
    expect(srt.format).toBe("srt");
    expect(hashTranscript(txt.normalizedText)).toHaveLength(64);
    expect(hashTranscript(txt.normalizedText)).toBe(hashTranscript(txt.normalizedText));
  });

  it("chunks with overlap and rejects oversized input", () => {
    const long = Array.from({ length: 40 }, (_, i) => `line-${i}-${"x".repeat(200)}`).join(
      "\n",
    );
    const normalized = normalizeTranscript(long);
    const chunks = chunkTranscript(normalized, { maxChars: 800, overlapSegments: 2 });
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks[1]!.startSegmentIndex).toBeLessThan(chunks[0]!.endSegmentIndex);

    expect(() =>
      normalizeTranscript("a".repeat(10), { maxBytes: 5 }),
    ).toThrowError(TranscriptError);
  });
});
