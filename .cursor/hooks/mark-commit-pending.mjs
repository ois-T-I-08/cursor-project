#!/usr/bin/env node
/**
 * Agent がコードファイルを編集したら自動コミット用フラグを立てる。
 */
import { mkdirSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const FLAG_PATH = join(REPO_ROOT, ".cursor", ".commit-pending");

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

const SKIP_PATTERNS = [
  "docs/agent_memory.md",
  ".cursor/hooks/",
  ".cursor/.memory-pending",
  ".cursor/.commit-pending",
  "/.next/",
  "/node_modules/",
  "/.dart_tool/",
  "/build/",
  "prisma/dev.db",
  "scripts/auto-commit/",
];

const CODE_EXTENSIONS = new Set([
  "dart",
  "ts",
  "tsx",
  "js",
  "mjs",
  "json",
  "sql",
  "prisma",
  "yaml",
  "yml",
  "md",
  "mdc",
]);

async function main() {
  const raw = await readStdin();
  let input = {};
  try {
    input = raw ? JSON.parse(raw) : {};
  } catch {
    noop();
  }

  const filePath = String(input.file_path ?? "")
    .replace(/\\/g, "/")
    .toLowerCase();

  if (!filePath) noop();

  if (SKIP_PATTERNS.some((p) => filePath.includes(p))) {
    noop();
  }

  const ext = filePath.split(".").pop() ?? "";
  if (!CODE_EXTENSIONS.has(ext)) {
    noop();
  }

  mkdirSync(dirname(FLAG_PATH), { recursive: true });
  writeFileSync(
    FLAG_PATH,
    JSON.stringify(
      {
        at: new Date().toISOString(),
        file: input.file_path,
      },
      null,
      2,
    ),
  );

  noop();
}

main().catch(() => noop());
