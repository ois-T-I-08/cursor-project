# Agent Memory Log

> セッションごとの**決定事項・未完了タスク**を記録する。会話全文ではなく、次の Agent が作業を再開できる要点のみ書く。
>
> **運用:** タスク完了時に最新エントリを先頭（`##` 見出し）に追記。古いエントリは削除しない。

---

## 2026-07-19 — AZA.GG 深境螺旋統計バックエンド

- **目的:** Flutter に AZA.GG の深境螺旋キャラクター／編成統計を安全に提供する
- **決定事項:** Flutter は AZA を直接呼ばず `GET /api/abyss/statistics` のみ利用。`AbyssStatisticsProvider` を交換境界とし、AZA 公開 KV API を実レスポンスの確認済みフィールドだけで正規化。API キーは現在不要のため未確認ヘッダーを送らない
- **可用性:** Prisma `ExternalApiCache` に最終成功値を保存。6時間 TTL、同一 Node.js プロセス内だけの single-flight、最大1回再試行、期限切れ時の stale fallback、`AZA_ABYSS_ENABLED` kill switch。現時点では AZA 経路に分散ロックを追加しない
- **契約監視:** 既知 `meta.api_ver` は `5.6`。未知版は現行スキーマ適合なら warning で継続、不適合なら `invalidResponse`。2026-07-19 の120キャラは全件 `phase` キーが `"1"` のみで、明示的な `"2"` がない場合だけ補数を使用
- **安全性:** HTTPS upstream、10秒 timeout、2MiB、配列／ID／比率／日時検証、安全なエラー code と許可フィールド限定ログ。ゲームバージョンと編成使用回数は upstream にないため生成しない
- **変更ファイル（主要）:** `src/lib/api/abyss/*`, `src/lib/abyss/*`, `src/app/api/abyss/statistics/route.ts`, Prisma schema/migration, `.env.example`, 関連テスト・資料
- **検証:** Vitest 全155成功、lint 0、`npm run typecheck` 成功、Prisma validate/generate 成功、Next production build 成功
- **未完了 / 次回:** 本番 DB の未適用 migration 2件（`add_sync_lease`、`add_external_api_cache`）、AZA 利用規約／クレジット文言／商用・広告利用の運用確認、公開 API 変更監視

## エントリの書き方

```markdown
## YYYY-MM-DD — 短いタイトル

- **目的:**
- **決定事項:**
- **変更ファイル（主要）:**
- **未完了 / 次回:**
```

---

## 2026-07-10 — Domain Golden パリティ（Web ↔ Mobile）

- **目的:** TS/Dart 二重実装の計算ズレを同一 golden JSON で検出する
- **決定事項:**
  - 正本: `shared/domain-golden/cases.json`
  - Web: `src/lib/__tests__/domain-golden.test.ts`（Vitest）
  - Mobile: `test/domain/domain_golden_test.dart`（flutter test）
  - CI: `.github/workflows/genshin-domain-golden.yml`
  - 並び順非依存（`linesByMaterialId`）で比較
- **変更ファイル（主要）:**
  - `shared/domain-golden/*`
  - `genshin-builder-app/src/lib/__tests__/domain-golden.test.ts`
  - `genshin-builder-mobile/test/domain/domain_golden_test.dart`
  - `.github/workflows/genshin-domain-golden.yml`
- **未完了 / 次回:** ケース追加時は両側緑確認。片側失敗時は実装側を直す（golden を安易に合わせない）

---

## 2026-07-08 — Memory 自動保存 Hook

- **目的:** Agent ターン終了時に Memory 追記を手動依頼なしでトリガー
- **決定事項:**
  - `c:\cursor project\.cursor\hooks.json`（ワークスペースルート）
  - `afterFileEdit`（Write）→ `genshin-builder-app/.cursor/.memory-pending` フラグ
  - `stop`（completed, loop_count=0）→ `followup_message` で AGENT_MEMORY 追記を自動実行
  - loop_count≥1 でフラグ削除・ループ終了（`loop_limit: 2`）
  - Ask モードやコード変更なしの会話ではフラグが立たず、追記も走らない
- **変更ファイル（主要）:**
  - `.cursor/hooks.json`, `.cursor/hooks/*.mjs`
  - `genshin-builder-app/.gitignore`（`.memory-pending`）
- **未完了 / 次回:** Windows で Hook が動かない場合は Cursor 再起動 / Hooks 出力チャンネルで確認

---

## 2026-07-08 — Agent Memory システム導入

- **目的:** セッション間でコンテキストを引き継ぐため、要点ログと Cursor Rule を整備
- **決定事項:**
  - ログファイル: `docs/AGENT_MEMORY.md`（本ファイル）
  - 更新ルール: `.cursor/rules/agent-memory.mdc`（`alwaysApply: true`）
  - **自動追記:** ワークスペース `.cursor/hooks.json` の `stop` hook
    - コード編集時 `afterFileEdit` → `.cursor/.memory-pending` フラグ
    - Agent ターン終了時 → `docs/AGENT_MEMORY.md` 追記を自動トリガー
  - 作業開始時は本ファイル最新エントリ + `AI_AGENT_RULES.md` + `ARCHITECTURE.md` を読む
  - タスク完了時に Agent が本ファイルへ追記（ユーザーが「保存不要」と言った場合のみスキップ）
- **変更ファイル（主要）:**
  - `docs/AGENT_MEMORY.md`（新規）
  - `.cursor/rules/agent-memory.mdc`（新規）
  - `AI_AGENT_RULES.md`, `AGENTS.md`（参照追加）
- **未完了 / 次回:** 特になし

---

## 2026-07-08 — 育成素材ブックマーク + キャラアイコン表示

- **目的:** キャラ/武器/天賦の必要素材をブックマークし、ホームで合算管理
- **決定事項:**
  - 永続化: `localStorage` キー `gb_material_bookmarks`（DB ではなくクライアントのみ）
  - 状態: `MaterialBookmarkContext` + `BookmarkProvider`（`layout.tsx` でラップ）
  - 合算: `materialId` 単位（モラは `__mora__`）
  - ブックマーク元キャラ: `BookmarkCharacterSource` を各エントリに保存、ホームでアイコン表示
  - 旧ブックマーク（キャラ情報なし）は再登録までアイコン非表示
  - 範囲計算: `src/lib/material-requirements.ts`
- **変更ファイル（主要）:**
  - `src/types/bookmark.ts`, `src/lib/bookmark-*.ts`, `src/lib/material-requirements.ts`
  - `src/contexts/MaterialBookmarkContext.tsx`
  - `src/components/bookmark/*`, `src/components/home/HomeWithBookmarks.tsx`
  - `DetailEditor`, `WeaponSection`, `TalentSection`, 素材パネル, スライダー類
- **未完了 / 次回:** git commit 未実施（ユーザー依頼時のみ）

---

## 2026-07-07 頃 — DB 同期・突破天賦素材・差分同期

- **目的:** 突破/天賦/EXP データを API から DB 同期し、UI は repository 経由で参照
- **決定事項:**
  - スキーマ: `CharacterUpgrade`, `WeaponUpgrade`, `LevelExpSegment`, `Material.expValue/expTarget`
  - 同期: `sync-upgrade.ts` + `amber-upgrade.ts`、デフォルトは差分同期（`fullUpgrade: false`）
  - `sync-utils.ts` の `idsForNotIn()` で空 `notIn: []` Prisma エラーを回避
  - スキル説明等リッチデータは on-demand API（24h キャッシュ）
- **変更ファイル（主要）:**
  - `prisma/schema.prisma`, migrations
  - `src/lib/sync-upgrade.ts`, `src/lib/repository/upgrade-data.ts`
  - `SyncSection.tsx`, `SyncButton.tsx`
  - `AI_AGENT_RULES.md`, `ARCHITECTURE.md`, `DEVELOPMENT_GUIDE.md`
- **未完了 / 次回:** 本番 PostgreSQL 移行は未着手

---

## 2026-07-07 頃 — Next.js アプリ基盤

- **目的:** 静的 HTML から Next.js 16 + Prisma + Project Amber API 構成へ移行
- **決定事項:**
  - 外部 API: Project Amber (`https://gi.yatta.moe`)
  - ユーザー進捗: cookie `gb_user_id` + Server Actions (`saveProgress`)
  - レイヤー: `api → sync → Prisma → repository → pages → Client`
  - PowerShell では `&&` ではなく `;` を使用
- **未完了 / 次回:** Lv.90–100 / 天賦 Lv.11–13 は UI 余白のみ（未実装）
