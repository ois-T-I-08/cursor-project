/** @typedef {'feat' | 'fix' | 'refactor' | 'docs' | 'test' | 'chore'} CommitType */

/**
 * コミット対象外パス（部分一致・小文字比較）
 * @type {string[]}
 */
export const EXCLUDE_PATTERNS = [
  "/.next/",
  "/node_modules/",
  "/.dart_tool/",
  "/build/",
  "/coverage/",
  "/.cursor/.memory-pending",
  "/.cursor/.commit-pending",
  "prisma/dev.db",
  "/.env",
  ".keystore",
  "credentials.json",
  "id_rsa",
  ".pem",
];

/**
 * 秘密情報とみなすファイル名パターン
 * @type {RegExp[]}
 */
export const SECRET_PATTERNS = [
  /^\.env(\.|$)/i,
  /credentials/i,
  /\.pem$/i,
  /\.key$/i,
  /id_rsa/i,
  /\.keystore$/i,
];

/** パスプレフィックスから領域ヒントを得る */
export const PATH_HINTS = [
  {
    prefix: "genshin-builder-mobile/lib/data/hoyolab/",
    scope: "mobile",
    labels: ["HoYoLAB"],
  },
  {
    prefix: "genshin-builder-mobile/lib/data/db/",
    scope: "mobile",
    labels: ["DB", "永続化"],
  },
  {
    prefix: "genshin-builder-mobile/lib/data/sync/",
    scope: "mobile",
    labels: ["マスタ同期"],
  },
  {
    prefix: "genshin-builder-mobile/lib/data/repositories/",
    scope: "mobile",
    labels: ["Repository"],
  },
  {
    prefix: "genshin-builder-mobile/lib/features/",
    scope: "mobile",
    labels: ["画面"],
  },
  {
    prefix: "genshin-builder-mobile/lib/providers/",
    scope: "mobile",
    labels: ["Provider"],
  },
  {
    prefix: "genshin-builder-mobile/lib/domain/",
    scope: "mobile",
    labels: ["ドメイン"],
  },
  {
    prefix: "genshin-builder-mobile/test/",
    scope: "mobile",
    labels: ["テスト"],
  },
  {
    prefix: "genshin-builder-app/src/components/",
    scope: null,
    labels: ["UI"],
  },
  {
    prefix: "genshin-builder-app/src/contexts/",
    scope: null,
    labels: ["ブックマーク"],
  },
  {
    prefix: "genshin-builder-app/src/lib/",
    scope: null,
    labels: ["ロジック"],
  },
  {
    prefix: "genshin-builder-app/prisma/",
    scope: null,
    labels: ["DBスキーマ"],
  },
  {
    prefix: ".cursor/hooks/",
    scope: "hooks",
    labels: ["Cursorフック"],
  },
  {
    prefix: "scripts/auto-commit/",
    scope: "tools",
    labels: ["自動コミット"],
  },
];

/**
 * プロジェクトルート直下のマーカー
 * @type {Record<string, string>}
 */
export const PROJECT_MARKERS = {
  "genshin-builder-mobile/": "mobile",
  "genshin-builder-app/": "web",
  ".cursor/": "hooks",
  "scripts/": "tools",
};

/** @type {CommitType[]} */
export const VALID_TYPES = [
  "feat",
  "fix",
  "refactor",
  "docs",
  "test",
  "chore",
];
