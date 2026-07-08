#!/usr/bin/env node
/**
 * Agent が genshin-builder-app 内のファイルを編集したら、
 * Memory 自動追記のフラグを立てる。
 */
import { mkdirSync, writeFileSync } from "fs";
import { dirname, join } from "path";

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

function extractFilePath(input) {
  if (input.file_path) return String(input.file_path);
  const toolInput = input.tool_input ?? input.arguments ?? input.input ?? {};
  if (typeof toolInput === "string") {
    try {
      const parsed = JSON.parse(toolInput);
      return parsed.path ?? parsed.file_path ?? parsed.target_notebook ?? "";
    } catch {
      return "";
    }
  }
  return (
    toolInput.path ??
    toolInput.file_path ??
    toolInput.target_notebook ??
    ""
  );
}

async function main() {
  const raw = await readStdin();
  let input = {};
  try {
    input = raw ? JSON.parse(raw) : {};
  } catch {
    noop();
  }

  const filePath = String(extractFilePath(input))
    .replace(/\\/g, "/")
    .toLowerCase();

  if (!filePath.includes("genshin-builder-app/")) {
    noop();
  }

  const skipPatterns = [
    "docs/agent_memory.md",
    ".cursor/hooks/",
    ".cursor/.memory-pending",
    "/.next/",
    "prisma/dev.db",
  ];

  if (skipPatterns.some((p) => filePath.includes(p))) {
    noop();
  }

  const flagPath = join(
    process.cwd(),
    "genshin-builder-app",
    ".cursor",
    ".memory-pending",
  );

  mkdirSync(dirname(flagPath), { recursive: true });
  writeFileSync(
    flagPath,
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
