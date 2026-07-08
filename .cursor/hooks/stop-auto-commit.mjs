#!/usr/bin/env node
/**
 * Agent ターン終了時: コード変更フラグがあれば自動コミットを実行する。
 */
import { spawnSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const AUTO_COMMIT = join(REPO_ROOT, "scripts", "auto-commit", "index.mjs");

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function noop() {
  process.stdout.write("{}\n");
  process.exit(0);
}

async function main() {
  const raw = await readStdin();
  let input = {};
  try {
    input = raw ? JSON.parse(raw) : {};
  } catch {
    noop();
  }

  if (input.status !== "completed") {
    noop();
  }

  const result = spawnSync(process.execPath, [AUTO_COMMIT, "--hook"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    input: raw,
    maxBuffer: 10 * 1024 * 1024,
  });

  const stdout = (result.stdout ?? "").trim();
  if (stdout) {
    process.stdout.write(stdout.endsWith("\n") ? stdout : `${stdout}\n`);
  } else {
    noop();
  }

  process.exit(result.status ?? 0);
}

main().catch(() => noop());
