import { spawnSync } from "child_process";
import { SECRET_PATTERNS } from "./config.mjs";

/**
 * @param {string} repoRoot
 * @param {string[]} args
 * @returns {{ ok: boolean, stdout: string, stderr: string }}
 */
export function runGit(repoRoot, args) {
  const result = spawnSync("git", args, {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });

  return {
    ok: result.status === 0,
    stdout: (result.stdout ?? "").trim(),
    stderr: (result.stderr ?? "").trim(),
  };
}

/**
 * @param {string} repoRoot
 * @returns {boolean}
 */
export function isGitRepo(repoRoot) {
  const { ok, stdout } = runGit(repoRoot, ["rev-parse", "--is-inside-work-tree"]);
  return ok && stdout === "true";
}

/**
 * @typedef {{ status: string, path: string, origPath?: string }} ChangedFile
 */

/**
 * @param {string} repoRoot
 * @returns {ChangedFile[]}
 */
export function listChangedFiles(repoRoot) {
  const { ok, stdout } = runGit(repoRoot, ["status", "--porcelain", "-uall"]);
  if (!ok || !stdout) return [];

  /** @type {ChangedFile[]} */
  const files = [];

  for (const line of stdout.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const status = line.slice(0, 2);
    let rest = line.slice(2);
    if (rest.startsWith(" ")) rest = rest.slice(1);
    rest = rest.trim();

    if (rest.includes(" -> ")) {
      const [orig, next] = rest.split(" -> ");
      files.push({ status, path: next, origPath: orig });
    } else {
      files.push({ status, path: rest });
    }
  }

  return files;
}

/**
 * @param {string} repoRoot
 * @param {string[]} paths
 * @returns {string}
 */
export function getDiffStat(repoRoot, paths) {
  if (paths.length === 0) return "";
  const { stdout } = runGit(repoRoot, ["diff", "--stat", "HEAD", "--", ...paths]);
  return stdout;
}

/**
 * @param {string} repoRoot
 * @param {string[]} paths
 * @returns {{ added: number, deleted: number }}
 */
export function getNumStat(repoRoot, paths) {
  if (paths.length === 0) return { added: 0, deleted: 0 };

  const { stdout } = runGit(repoRoot, ["diff", "--numstat", "HEAD", "--", ...paths]);
  let added = 0;
  let deleted = 0;

  for (const line of stdout.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const [a, d] = line.split("\t");
    if (a === "-") continue;
    added += Number(a) || 0;
    deleted += Number(d) || 0;
  }

  return { added, deleted };
}

/**
 * @param {string} path
 * @returns {boolean}
 */
export function looksSecret(path) {
  const base = path.split(/[/\\]/).pop() ?? path;
  return SECRET_PATTERNS.some((re) => re.test(base) || re.test(path));
}

/**
 * @param {string} repoRoot
 * @param {string[]} paths
 * @returns {{ ok: boolean, stderr?: string }}
 */
export function stageAndCommit(repoRoot, paths, message) {
  const add = runGit(repoRoot, ["add", "--", ...paths]);
  if (!add.ok) {
    return { ok: false, stderr: add.stderr || "git add failed" };
  }

  const commit = runGit(repoRoot, ["commit", "-m", message]);
  if (!commit.ok) {
    return { ok: false, stderr: commit.stderr || "git commit failed" };
  }

  return { ok: true };
}

/**
 * @param {string} repoRoot
 * @returns {string[]}
 */
export function recentCommitSubjects(repoRoot, count = 5) {
  const { stdout } = runGit(repoRoot, [
    "log",
    `-${count}`,
    "--format=%s",
  ]);
  return stdout ? stdout.split(/\r?\n/).filter(Boolean) : [];
}
