# Development Guide — Genshin Builder

開発者・AI エージェント向けの実装ガイドです。  
**変更前に `AI_AGENT_RULES.md` と `ARCHITECTURE.md` を必ず読んでください。**

---

## 1. 開発環境セットアップ

```bash
cd genshin-builder-app
npm install
cp .env.example .env          # Neon development branchのpooled/direct URLを設定
npx prisma migrate deploy
npx prisma generate
npm run dev                     # http://localhost:3000
```

### よくある問題

| 症状 | 対処 |
|------|------|
| `EPERM` on `prisma generate` | dev サーバーを止めてから再実行 |
| 同期 500 / 即失敗 | migrate + generate + dev 再起動 |
| `npm` が見つからない | Node.js PATH を確認。Cursor 統合ターミナルを使う |

### 初回データ投入

1. http://localhost:3000/settings を開く
2. **ゲームデータを同期**（初回は数分）
3. 突破データが揃えば緑バナー表示

---

## 2. フォルダ構成ルール

```
src/
├── app/              # ルート・ページ・Route Handlers のみ。ビジネスロジックを書かない
├── components/       # React UI。ドメインロジックは lib/ へ
│   ├── layout/
│   ├── character/
│   ├── settings/
│   └── ui/           # ドメイン非依存の汎用部品
├── lib/
│   ├── api/          # 外部 API（fetch のみ）
│   ├── repository/   # DB 読み取り
│   ├── actions/      # Server Actions（ユーザー書き込み）
│   ├── sync*.ts      # マスタ同期
│   └── *.ts          # 純関数ドメインロジック
└── types/            # アプリ全体の型（Prisma モデル型は @prisma/client）
```

### 新規ファイルの置き場

| 追加するもの | 置き場 |
|-------------|--------|
| 新ページ | `src/app/{route}/page.tsx` |
| API Route | `src/app/api/{name}/route.ts` |
| キャラ UI | `src/components/character/` |
| DB 読み取り | `src/lib/repository/{domain}.ts` |
| 外部 API | `src/lib/api/` |
| 計算ロジック | `src/lib/{name}.ts`（既存ファイルに追加優先） |

---

## 3. 命名規則

### ファイル

| 種類 | 規則 | 例 |
|------|------|-----|
| React コンポーネント | PascalCase.tsx | `DetailEditor.tsx` |
| lib モジュール | kebab-case.ts | `sync-upgrade.ts` |
| 型定義 | kebab-case.ts or types/ | `character.ts` |
| Route Handler | route.ts（固定） | `api/sync/route.ts` |

### コード

| 種類 | 規則 | 例 |
|------|------|-----|
| コンポーネント | PascalCase | `CharacterCard` |
| 関数 | camelCase | `getCharacterUpgrade` |
| 定数 | UPPER_SNAKE | `LEVEL_MARKS` |
| 型・Interface | PascalCase | `SyncStatus` |
| DB フィールド | camelCase（Prisma） | `weaponType` |
| 元素・武器種（内部） | 英小文字 | `pyro`, `sword` |

### ID

- キャラ・武器・素材 ID は **Project Amber の数値文字列**（例 `"10000046"`）
- slug 名（`hu-tao`）は使わない

---

## 4. コンポーネント設計方針

### Server Component（デフォルト）

- ページ (`page.tsx`)、layout、表示専用カード
- `async` で repository / api を await
- props は Client に渡せる JSON のみ

### Client Component（`"use client"`）

次のいずれかがある場合のみ:

- `useState` / `useEffect` / イベントハンドラ
- ブラウザ API
- デバウンス autosave
- フィルター・スライダー・アコーディオン

### 推奨パターン

```tsx
// page.tsx (Server)
export default async function Page() {
  const data = await getSomething();
  return <Editor initial={data} />;
}

// Editor.tsx (Client)
"use client";
export default function Editor({ initial }: { initial: Data }) {
  const [state, setState] = useState(initial);
  // ...
}
```

### 詳細エディタの分割

- `DetailEditor` — 状態の単一ソース + autosave
- `*Section` — アコーディオン単位（Weapon, Artifact, Talent...）
- `*Panel` — 素材表示など表示専用
- `ui/*Slider` — 汎用スライダー

**新セクション追加:** `DetailEditor` に props を1本追加し、既存セクションと同じ Accordion パターンに従う。

---

## 5. API 利用ルール（実装者向け）

### マスタデータを UI に載せる場合

1. **一覧・コスト・突破** → 同期 + DB + repository（優先）
2. **説明文・動的ステ** → `amber-details.ts`（表示時）

### 同期を変更する場合

- 通常同期: `fullUpgrade: false` — 未登録分のみ API
- 完全同期: `fullUpgrade: true` — 全件再取得
- `sync-utils.ts` の `idsForNotIn()` を必ず使用
- concurrency / delay は `sync-upgrade.ts` 定数のみ変更

### 新 Route Handler

```typescript
// src/app/api/example/route.ts
import { NextResponse } from "next/server";

export async function GET() {
  // サーバー側のみ。Prisma / lib/api OK
  return NextResponse.json({ ok: true });
}
```

Client からは `fetch("/api/...")` のみ。外部 URL を Client から直接叩かない。

---

## 6. データベース

### マイグレーション

```bash
# 空のNeon development branchへ適用
npx prisma migrate deploy
npx prisma migrate status
npx prisma generate
```

- 既存JSON文字列フィールドは互換性のため`String`を維持する
- 新規YShelperメタデータは`Json`を使用し、検索項目は正規化テーブルへ分ける
- `prisma/migrations-sqlite-archive`は履歴専用。PostgreSQLへ適用しない
- `migrate reset`、既存Migrationの再作成、運用DBの初期化は禁止

### 書き込み経路（厳守）

| データ | 書き込み |
|--------|----------|
| Character/Weapon/Material/Upgrade | `syncMasterData` のみ |
| UserProgress | `saveProgress` / `deleteProgress` のみ |

---

## 7. エラー処理

```typescript
// API 層 — null で返す
export async function fetchX(): Promise<X | null> {
  try { /* ... */ } catch (e) {
    console.error("...", e);
    return null;
  }
}

// Repository — 空で返す
export async function getX(): Promise<X[]> {
  try { /* prisma */ } catch {
    return [];
  }
}

// Server Action — 結果オブジェクト
return { ok: false }; // UI が status 表示
```

UI では「データがありません」+ **設定への Link**（`LevelMaterialsPanel` 参照）。

---

## 8. セキュリティ

- `.env` / `dev.db` を commit しない
- Server Action で入力 clamp（`saveProgress` を参考）
- `dangerouslySetInnerHTML` 禁止
- API 説明文は `stripMarkup()` 済みテキストのみ表示
- 本番: sync エンドポイント保護、cookie `secure: true`

---

## 9. スタイリング

- Tailwind CSS v4（`globals.css` でテーマ）
- ダーク基調: `#1e2a3a`, `#151d2a`, accent `#d4a853`
- 既存コンポーネントの class パターンに合わせる
- ライトモードは将来対応（`globals.css` コメント）

---

## 10. テスト方針

### 現状

- 自動テストなし
- `npm run build` + `npm run lint` が最低ライン

### 手動テストチェックリスト

- [ ] ホーム / キャラ一覧表示
- [ ] 設定 → 通常同期成功
- [ ] キャラ詳細 → レベル変更 → 素材表示
- [ ] 武器変更 → 性能・突破素材
- [ ] 天賦スライダー → 素材
- [ ] 育成保存 → リロード後も保持
- [ ] API 不通時も一覧表示（DB データ）

### 将来のテスト優先度

1. `level-progression.ts` — 素材計算
2. `artifact-score.ts` — スコア
3. `sync-utils.ts` — idsForNotIn
4. E2E — 同期 → 詳細保存

---

## 11. 変更時の確認事項（チェックリスト）

非 trivial な PR / 変更では以下を説明に含める:

1. **Why** — なぜこの変更が必要か
2. **Scope** — 変更ファイルと行数の目安
3. **Layers** — どのレイヤーを触ったか
4. **Migration** — yes/no
5. **API impact** — 同期・表示の呼び出し回数
6. **Breaking** — 既存ユーザーへの影響
7. **Verify** — build + 手動確認手順

---

## 12. やってはいけない実装例

| NG | OK |
|----|-----|
| ページ内に fetch URL 直書き | `lib/api/` 経由 |
| Client で Prisma | Server Action |
| 同期なしで全 detail 取得 | 差分同期 |
| 巨大な God Component | Section 分割 |
| 依頼外の eslint-disable | 根本原因を直す |
| 無断 commit | ユーザー指示時のみ |

---

## 13. Git / コミット

- **コミットはユーザー明示時のみ**
- `prisma/dev.db`, `.env`, `.next/` は含めない
- メッセージ例: `feat:`, `fix:`, `refactor:` + 日本語で why

---

## 14. 関連ドキュメント

| ファイル | 用途 |
|----------|------|
| `docs/AGENT_MEMORY.md` | セッションごとの決定事項・未完了（**最新エントリを先に読む**） |
| `.cursor/rules/agent-memory.mdc` | Memory ログの読み書きルール（常時適用） |
| `../.cursor/hooks.json` | Memory 自動追記 Hook（コード変更検知 → stop でトリガー） |
| `AI_AGENT_RULES.md` | AI 向け禁止事項・必須手順 |
| `ARCHITECTURE.md` | システム構成・データフロー |
| `README.md` | ユーザー向け概要 |
| `AGENTS.md` | Next.js 16 固有ルール |

---

## 15. AI エージェント向け再掲

> **コード変更前に必ず既存設計を確認し、影響範囲を説明してから最小差分で実装すること。**  
> 大規模リファクタ・無関係ファイルの変更・同期ロジックの暗黙変更は禁止。

Cursor 利用時は `.cursor/rules` や `AGENTS.md` から本ガイドへリンクされている想定です。
