import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { spawn } from "node:child_process";
import type { GcsimRunResult } from "./types";
import { GCSIM_BINARY_SHA256, GCSIM_VERSION, type TeamRecommendationSettings } from "./settings";
import { GcsimOutputParser } from "./output-parser";

export interface GcsimRunner {
  run(config: string): Promise<GcsimRunResult>;
}

export class SecureGcsimRunner implements GcsimRunner {
  private readonly semaphore: Semaphore;
  private checksumPromise?: Promise<void>;

  constructor(
    private readonly settings: TeamRecommendationSettings,
    private readonly parser = new GcsimOutputParser(),
  ) {
    this.semaphore = new Semaphore(settings.maxConcurrency);
  }

  async run(config: string): Promise<GcsimRunResult> {
    if (Buffer.byteLength(config, "utf8") > this.settings.maxConfigBytes) throw new Error("configTooLarge");
    const release = await this.semaphore.acquire();
    const directory = await mkdtemp(join(tmpdir(), "genshin-builder-gcsim-"));
    try {
      const binary = trustedBinaryPath();
      const expectedChecksum = GCSIM_BINARY_SHA256[`${process.platform}-${process.arch}`];
      if (!expectedChecksum) throw new Error("unsupportedPlatform");
      this.checksumPromise ??= verifyFileChecksum(binary, expectedChecksum);
      await this.checksumPromise;
      const configPath = resolve(directory, "config.txt");
      const outputPath = resolve(directory, "result.json");
      await writeFile(configPath, config, { encoding: "utf8", flag: "wx", mode: 0o600 });
      await runBoundedProcess(binary, ["-c", configPath, "-out", outputPath], directory, this.settings);
      const outputStat = await stat(outputPath);
      if (outputStat.size > this.settings.maxOutputBytes) throw new Error("outputTooLarge");
      return this.parser.parse(await readFile(outputPath, "utf8"));
    } finally {
      try {
        await safeRemoveTempDirectory(directory);
      } finally {
        release();
      }
    }
  }
}

function trustedBinaryPath(): string {
  const key = `${process.platform}-${process.arch}`;
  const fileName = process.platform === "win32" ? "gcsim_windows_amd64.exe"
    : process.platform === "darwin" ? (process.arch === "arm64" ? "gcsim_darwin_arm64" : "gcsim_darwin_amd64")
    : "gcsim_linux_amd64";
  if (!GCSIM_BINARY_SHA256[key]) throw new Error("unsupportedPlatform");
  return resolve(process.cwd(), "vendor", "gcsim", GCSIM_VERSION, fileName);
}

export async function verifyFileChecksum(binary: string, expected: string): Promise<void> {
  const digest = await new Promise<string>((resolveDigest, reject) => {
    const hash = createHash("sha256");
    const stream = createReadStream(binary);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolveDigest(hash.digest("hex")));
  });
  if (digest !== expected) throw new Error("binaryChecksumMismatch");
}

export async function safeRemoveTempDirectory(directory: string): Promise<void> {
  const resolved = resolve(directory);
  if (dirname(resolved) !== resolve(tmpdir()) || !basename(resolved).startsWith("genshin-builder-gcsim-")) {
    throw new Error("unsafeTempDirectory");
  }
  await rm(resolved, { recursive: true, force: true });
}

export async function runBoundedProcess(
  binary: string,
  args: string[],
  cwd: string,
  settings: TeamRecommendationSettings,
): Promise<void> {
  await new Promise<void>((resolvePromise, reject) => {
    const child = spawn(binary, args, {
      cwd,
      shell: false,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
      env: { NODE_ENV: process.env.NODE_ENV ?? "production", LANG: "C", LC_ALL: "C" },
    });
    child.stdin.end();
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    let terminalError: Error | undefined;
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error); else resolvePromise();
    };
    const limit = (kind: "stdout" | "stderr", chunk: Buffer) => {
      if (kind === "stdout") stdoutBytes += chunk.length; else stderrBytes += chunk.length;
      if (stdoutBytes > settings.maxOutputBytes || stderrBytes > settings.maxOutputBytes) {
        terminalError ??= new Error(`${kind}TooLarge`);
        child.kill("SIGKILL");
      }
    };
    child.stdout.on("data", (chunk: Buffer) => limit("stdout", chunk));
    child.stderr.on("data", (chunk: Buffer) => limit("stderr", chunk));
    child.on("error", (error) => finish(error));
    child.on("close", (code) => finish(terminalError ?? (code === 0 ? undefined : new Error("gcsimFailed"))));
    const timer = setTimeout(() => {
      terminalError ??= new Error("gcsimTimeout");
      child.kill("SIGKILL");
    }, settings.timeoutMs);
    timer.unref();
  });
}

class Semaphore {
  private active = 0;
  private readonly waiting: Array<() => void> = [];
  constructor(private readonly limit: number) {}
  async acquire(): Promise<() => void> {
    if (this.active >= this.limit) await new Promise<void>((resolveWait) => this.waiting.push(resolveWait));
    this.active += 1;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.active -= 1;
      this.waiting.shift()?.();
    };
  }
}
