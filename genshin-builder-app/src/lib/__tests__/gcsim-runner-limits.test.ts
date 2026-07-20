import { describe, expect, it } from "vitest";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  runBoundedProcess,
  safeRemoveTempDirectory,
  verifyFileChecksum,
} from "@/lib/team-recommendations/gcsim-runner";
import type { TeamRecommendationSettings } from "@/lib/team-recommendations/settings";

describe("bounded gcsim process adapter", () => {
  it("terminates a timed-out process", async () => {
    await expect(runBoundedProcess(process.execPath, ["-e", "setTimeout(() => {}, 10000)"], process.cwd(), settings({ timeoutMs: 50 }))).rejects.toThrow("gcsimTimeout");
  });
  it("enforces stdout limit", async () => {
    await expect(runBoundedProcess(process.execPath, ["-e", "process.stdout.write('x'.repeat(4096))"], process.cwd(), settings({ maxOutputBytes: 64 }))).rejects.toThrow("stdoutTooLarge");
  });
  it("enforces stderr limit", async () => {
    await expect(runBoundedProcess(process.execPath, ["-e", "process.stderr.write('x'.repeat(4096))"], process.cwd(), settings({ maxOutputBytes: 64 }))).rejects.toThrow("stderrTooLarge");
  });
  it("rejects a checksum mismatch before a binary can be trusted", async () => {
    const directory = await mkdtemp(join(tmpdir(), "genshin-builder-gcsim-"));
    try {
      const binary = join(directory, "gcsim-test");
      await writeFile(binary, "tampered", { flag: "wx" });
      await expect(verifyFileChecksum(binary, "0".repeat(64))).rejects.toThrow("binaryChecksumMismatch");
    } finally {
      await safeRemoveTempDirectory(directory);
    }
  });
  it("refuses to delete a directory outside the trusted temp root", async () => {
    await expect(safeRemoveTempDirectory(process.cwd())).rejects.toThrow("unsafeTempDirectory");
  });
});

function settings(overrides: Partial<TeamRecommendationSettings>): TeamRecommendationSettings {
  return { enabled: true, maxCandidates: 20, maxConcurrency: 2, maxActiveJobs: 8, timeoutMs: 1000, iterations: 1000, cacheTtlSeconds: 86400, jobTtlSeconds: 86400, maxConfigBytes: 65536, maxOutputBytes: 2097152, durationSeconds: 90, ...overrides };
}
