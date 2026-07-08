import {
  EXCLUDE_PATTERNS,
  PATH_HINTS,
  PROJECT_MARKERS,
  VALID_TYPES,
} from "./config.mjs";
import { getNumStat, looksSecret } from "./git.mjs";

/**
 * @param {string} path
 * @returns {string}
 */
function normalizePath(path) {
  return path.replace(/\\/g, "/").toLowerCase();
}

/**
 * @param {string} path
 * @returns {boolean}
 */
export function shouldExclude(path) {
  const normalized = normalizePath(path);
  if (looksSecret(path)) return true;
  return EXCLUDE_PATTERNS.some((p) => normalized.includes(p.toLowerCase()));
}

/**
 * @typedef {{ path: string, status: string, isNew: boolean, isDeleted: boolean, isDoc: boolean, isTest: boolean, isCode: boolean }} FileMeta
 */

/**
 * @param {{ path: string, status: string }} file
 * @returns {FileMeta}
 */
function classifyFile(file) {
  const normalized = normalizePath(file.path);
  const ext = normalized.split(".").pop() ?? "";
  const isDoc = [".md", ".mdc", ".txt"].some((e) => normalized.endsWith(e));
  const isTest =
    normalized.includes("/test/") ||
    normalized.includes("/tests/") ||
    normalized.endsWith("_test.dart") ||
    normalized.endsWith(".test.ts") ||
    normalized.endsWith(".test.tsx") ||
    normalized.endsWith(".spec.ts");
  const isCode =
    !isDoc &&
    [
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
      "sh",
    ].includes(ext);

  const status = file.status.trim();
  const isNew = status === "??" || status.includes("A");
  const isDeleted = status.includes("D");

  return {
    path: file.path,
    status,
    isNew,
    isDeleted,
    isDoc,
    isTest,
    isCode,
  };
}

/**
 * @param {FileMeta[]} files
 * @returns {{ scopes: Set<string>, labels: Set<string> }}
 */
function collectHints(files) {
  const scopes = new Set();
  const labels = new Set();

  for (const file of files) {
    const normalized = normalizePath(file.path);

    for (const [marker, scope] of Object.entries(PROJECT_MARKERS)) {
      if (normalized.startsWith(marker)) {
        scopes.add(scope);
      }
    }

    for (const hint of PATH_HINTS) {
      if (normalized.startsWith(hint.prefix.toLowerCase())) {
        if (hint.scope) scopes.add(hint.scope);
        for (const label of hint.labels) labels.add(label);
      }
    }
  }

  return { scopes, labels };
}

/**
 * @param {FileMeta[]} files
 * @param {{ added: number, deleted: number }} stats
 * @returns {import('./config.mjs').CommitType}
 */
function inferType(files, stats) {
  const codeFiles = files.filter((f) => f.isCode);
  const docOnly = files.length > 0 && files.every((f) => f.isDoc);
  const testOnly = files.length > 0 && files.every((f) => f.isTest);
  const newCodeCount = codeFiles.filter((f) => f.isNew).length;
  const gitignoreOnly =
    files.length > 0 &&
    files.every((f) => normalizePath(f.path).endsWith(".gitignore"));

  if (testOnly) return "test";
  if (docOnly) return "docs";
  if (gitignoreOnly) return "chore";

  const hasFixCue = files.some((f) => {
    const p = normalizePath(f.path);
    return (
      p.includes("fix") ||
      p.includes("bug") ||
      p.includes("error") ||
      p.includes("exception")
    );
  });
  if (hasFixCue) return "fix";

  if (newCodeCount >= Math.max(2, Math.ceil(codeFiles.length * 0.4))) {
    return "feat";
  }

  if (stats.deleted > stats.added * 0.25 && stats.added + stats.deleted > 40) {
    return "refactor";
  }

  if (codeFiles.some((f) => f.isNew)) return "feat";
  return "refactor";
}

/**
 * @param {Set<string>} scopes
 * @returns {string | null}
 */
function pickScope(scopes) {
  if (scopes.size === 1) {
    const [only] = scopes;
    if (only === "web") return null;
    return only;
  }
  return null;
}

/**
 * @param {Set<string>} labels
 * @param {Set<string>} scopes
 * @param {import('./config.mjs').CommitType} type
 * @returns {string}
 */
function buildSubject(labels, scopes, type) {
  const labelList = [...labels];

  if (scopes.has("mobile") && scopes.has("web")) {
    if (type === "docs") return "モバイル/Web のドキュメントを更新";
    if (type === "refactor") return "モバイル/Web の構成整理とデータ永続化の改善";
    return "モバイル/Web の機能を更新";
  }

  if (scopes.has("mobile") && labelList.length > 0) {
    const main = labelList.slice(0, 2).join("・");
    if (type === "feat") return `${main}を追加`;
    if (type === "fix") return `${main}の不具合を修正`;
    if (type === "refactor") return `${main}を整理`;
    if (type === "docs") return `${main}のドキュメントを更新`;
    if (type === "test") return `${main}のテストを追加`;
    return `${main}を更新`;
  }

  if (scopes.has("web")) {
    if (labelList.includes("ブックマーク")) {
      if (type === "feat") return "素材ブックマーク機能とホーム合算表示を追加";
      return "ブックマーク処理を整理";
    }
    if (labelList.includes("UI")) return "キャラ詳細UIを更新";
    if (type === "docs") return "Web ドキュメントを更新";
    return "Web 版の機能を更新";
  }

  if (scopes.has("hooks") && scopes.has("tools")) {
    return "自動コミットツールと Cursor フックを追加";
  }

  if (scopes.has("hooks")) {
    return type === "feat"
      ? "Cursor フック自動化を追加"
      : "Cursor フックを更新";
  }

  if (scopes.has("tools")) {
    return "自動コミットツールを追加";
  }

  if (type === "docs") return "ドキュメントを更新";
  if (type === "test") return "テストを追加";
  if (type === "chore") return "ビルド・設定ファイルを更新";
  if (type === "feat") return "機能を追加";
  if (type === "fix") return "不具合を修正";
  return "コードを整理";
}

/**
 * @param {FileMeta[]} files
 * @param {Set<string>} labels
 * @returns {string[]}
 */
function buildBody(files, labels) {
  const lines = [];
  const byProject = new Map();

  for (const file of files) {
    const normalized = normalizePath(file.path);
    let project = "other";
    for (const marker of Object.keys(PROJECT_MARKERS)) {
      if (normalized.startsWith(marker)) {
        project = marker.replace(/\/$/, "");
        break;
      }
    }
    const list = byProject.get(project) ?? [];
    list.push(file.path);
    byProject.set(project, list);
  }

  for (const [project, paths] of byProject) {
    if (paths.length <= 3) {
      lines.push(`${project}: ${paths.join(", ")}`);
    } else {
      lines.push(`${project}: ${paths.length} ファイル`);
    }
  }

  if (labels.size > 0) {
    lines.push(`領域: ${[...labels].join("、")}`);
  }

  return lines.slice(0, 6);
}

/**
 * @param {string} repoRoot
 * @param {{ path: string, status: string }[]} changedFiles
 * @returns {{ message: string, files: FileMeta[], type: import('./config.mjs').CommitType } | null}
 */
export function generateCommitMessage(repoRoot, changedFiles) {
  const eligible = changedFiles.filter((f) => !shouldExclude(f.path));
  if (eligible.length === 0) return null;

  const files = eligible.map(classifyFile);
  const paths = files.map((f) => f.path);
  const stats = getNumStat(repoRoot, paths);
  const { scopes, labels } = collectHints(files);
  const type = inferType(files, stats);
  const scope = pickScope(scopes);
  const subject = buildSubject(labels, scopes, type);

  const header = scope
    ? `${type}(${scope}): ${subject}`
    : `${type}: ${subject}`;

  if (!VALID_TYPES.includes(type)) {
    return null;
  }

  const body = buildBody(files, labels);
  const message = body.length > 0 ? `${header}\n\n${body.join("\n")}` : header;

  return { message, files, type };
}
