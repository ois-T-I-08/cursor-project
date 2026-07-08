#!/usr/bin/env node
/**
 * 変更ファイルを解析し、Conventional Commits 形式の日本語メッセージで自動コミットする。
 *
 * Usage:
 *   node scripts/auto-commit/index.mjs              # 1回実行
 *   node scripts/auto-commit/index.mjs --dry-run    # メッセージのみ表示
 *   node scripts/auto-commit/index.mjs --watch 30   # 30秒間隔で監視（デバウンス 8秒）
 *   node scripts/auto-commit/index.mjs --hook         # Cursor stop フック用
 */
import { existsSync, unlinkSync, writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import {
  generateCommitMessage,
  shouldExclude,
} from "./message.mjs";
import {
  isGitRepo,
  listChangedFiles,
  recentCommitSubjects,
  runGit,
  stageAndCommit,
} from "./git.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..", "..");
const FLAG_PATH = join(REPO_ROOT, ".cursor", ".commit-pending");
const DEBOUNCE_MS = 8000;

/**
 * @param {string[]} argv
 */
function parseArgs(argv) {
  const opts = {
    dryRun: false,
    watchIntervalSec: 0,
    hookMode: false,
    verbose: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") opts.dryRun = true;
    else if (arg === "--hook") opts.hookMode = true;
    else if (arg === "--verbose" || arg === "-v") opts.verbose = true;
    else if (arg === "--watch") {
      const next = Number(argv[i + 1]);
      opts.watchIntervalSec = Number.isFinite(next) && next > 0 ? next : 30;
      i += 1;
    }
  }

  return opts;
}

/**
 * @param {string} msg
 */
function log(msg) {
  process.stderr.write(`${msg}\n`);
}

function clearFlag() {
  if (existsSync(FLAG_PATH)) {
    try {
      unlinkSync(FLAG_PATH);
    } catch {
      /* ignore */
    }
  }
}

function setFlag(reason) {
  mkdirSync(dirname(FLAG_PATH), { recursive: true });
  writeFileSync(
    FLAG_PATH,
    JSON.stringify({ at: new Date().toISOString(), reason }, null, 2),
  );
}

/**
 * @param {{ dryRun?: boolean, verbose?: boolean, requireFlag?: boolean }} opts
 * @returns {Promise<{ committed: boolean, message?: string, reason?: string }>}
 */
async function runOnce(opts = {}) {
  const { dryRun = false, verbose = false, requireFlag = false } = opts;

  if (!isGitRepo(REPO_ROOT)) {
    return { committed: false, reason: "not a git repository" };
  }

  if (requireFlag && !existsSync(FLAG_PATH)) {
    return { committed: false, reason: "no pending changes flag" };
  }

  const changed = listChangedFiles(REPO_ROOT);
  const committable = changed.filter((f) => !shouldExclude(f.path));

  if (committable.length === 0) {
    clearFlag();
    return { committed: false, reason: "no committable changes" };
  }

  const generated = generateCommitMessage(REPO_ROOT, committable);
  if (!generated) {
    clearFlag();
    return { committed: false, reason: "could not generate message" };
  }

  const { message, files } = generated;
  const paths = files.map((f) => f.path);

  const recent = recentCommitSubjects(REPO_ROOT, 3);
  const subject = message.split("\n")[0];
  if (recent.includes(subject)) {
    clearFlag();
    return {
      committed: false,
      reason: "duplicate subject (already committed recently)",
      message,
    };
  }

  if (verbose || dryRun) {
    log("--- auto-commit preview ---");
    log(`files: ${paths.length}`);
    for (const p of paths) log(`  ${p}`);
    log(`message:\n${message}`);
    log("-------------------------");
  }

  if (dryRun) {
    return { committed: false, message, reason: "dry-run" };
  }

  const result = stageAndCommit(REPO_ROOT, paths, message);
  if (!result.ok) {
    return {
      committed: false,
      reason: result.stderr ?? "commit failed",
      message,
    };
  }

  clearFlag();
  return { committed: true, message };
}

/**
 * @param {number} intervalSec
 */
async function watchLoop(intervalSec) {
  let lastSnapshot = "";
  let debounceTimer = null;

  log(`[auto-commit] watching every ${intervalSec}s (debounce ${DEBOUNCE_MS}ms)`);

  const tick = async () => {
    const changed = listChangedFiles(REPO_ROOT);
    const committable = changed.filter((f) => !shouldExclude(f.path));
    const snapshot = committable
      .map((f) => `${f.status}:${f.path}`)
      .sort()
      .join("|");

    if (snapshot === "" || snapshot === lastSnapshot) {
      return;
    }

    if (debounceTimer) clearTimeout(debounceTimer);

    debounceTimer = setTimeout(async () => {
      const current = listChangedFiles(REPO_ROOT)
        .filter((f) => !shouldExclude(f.path))
        .map((f) => `${f.status}:${f.path}`)
        .sort()
        .join("|");

      if (current !== snapshot) return;

      lastSnapshot = snapshot;
      const result = await runOnce({ verbose: true });
      if (result.committed) {
        log(`[auto-commit] committed: ${result.message?.split("\n")[0]}`);
        lastSnapshot = "";
      } else if (result.reason && result.reason !== "no committable changes") {
        log(`[auto-commit] skipped: ${result.reason}`);
      }
    }, DEBOUNCE_MS);
  };

  await tick();
  setInterval(tick, intervalSec * 1000);
}

/**
 * Cursor stop フックから呼ばれる
 */
async function runHookMode() {
  const raw = await readStdin();
  let input = {};
  try {
    input = raw ? JSON.parse(raw) : {};
  } catch {
    process.stdout.write("{}\n");
    process.exit(0);
  }

  if (input.status !== "completed") {
    process.stdout.write("{}\n");
    process.exit(0);
  }

  const result = await runOnce({ requireFlag: true, verbose: false });

  if (result.committed) {
    const subject = result.message?.split("\n")[0] ?? "commit";
    process.stdout.write(
      JSON.stringify({
        followup_message: `[自動コミット] ${subject} — 続きの作業があれば進めてください。`,
      }) + "\n",
    );
    process.exit(0);
  }

  process.stdout.write("{}\n");
  process.exit(0);
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.hookMode) {
    await runHookMode();
    return;
  }

  if (opts.watchIntervalSec > 0) {
    await watchLoop(opts.watchIntervalSec);
    return;
  }

  const result = await runOnce({
    dryRun: opts.dryRun,
    verbose: opts.verbose,
  });

  if (result.committed) {
    log(`Committed: ${result.message?.split("\n")[0]}`);
    process.exit(0);
  }

  if (opts.dryRun && result.message) {
    process.exit(0);
  }

  if (result.reason) {
    log(result.reason);
  }
  process.exit(result.reason === "no committable changes" ? 0 : 1);
}

export { runOnce, setFlag, REPO_ROOT, FLAG_PATH };

main().catch((err) => {
  log(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
