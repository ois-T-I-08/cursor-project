# Agent Memory Log

> セッションごとの**決定事項・未完了タスク**を記録する。会話全文ではなく、次の Agent が作業を再開できる要点のみ書く。
>
> **運用:** タスク完了時に最新エントリを先頭（`##` 見出し）に追記。古いエントリは削除しない。

## 2026-08-02 — 「今日やること」DeepSeek優先タスク提案

- **目的:** 既存のFlutter「今日やること」画面・モデル・完了キーと、共通`DeepSeekJsonClient`を再利用し、候補外を生成しない今日の優先タスク提案を追加。
- **決定事項:** Flutterの通常コードが曜日素材、週ボス、`UpgradeOption`、目標、樹脂見積、ブックマークから安定ID付き候補を上限20件で生成する。Next.jsはstrict Zod → DeepSeek JSON → allowlist/重複/当日可否/樹脂/時間/表示文字列の決定論的最終検証を行い、全失敗時は通常ルールへ戻す。AIは`DEEPSEEK_ENABLED`と`DEEPSEEK_DAILY_PLAN_ENABLED`の両方がtrueの場合だけ共通キー・モデル・timeout・retryで呼ぶ。
- **プライバシー/永続化:** Cookie、UID、未加工HoYoLABレスポンス、AI原文を送信・保存しない。匿名化スコープと構造化済み最小DTOだけをHTTPS（ローカル開発先を除く）へ送る。process-local 15分キャッシュと端末`app_settings`には最終検証済み提案と安全なメタデータだけを保存し、採用前は進捗・目標・完了状態を変更しない。DB migrationなし。
- **UI:** 既存画面内に出典、上位1〜5件、短い根拠、警告、再生成、採用、閉じるを追加。明示採用後だけ既存ID/完了キーを維持して並び・理由へ反映し、候補・進捗・樹脂・日付・rules版変更時はfingerprint不一致で無効化。
- **検証:** Web typecheck成功、lintはerror 0（既存/対象外warning 2）、Vitest 398成功・DB専用46 skip、Next production build成功。Flutter analyze 0件、全776テスト成功。`git diff --check`成功。セキュリティ自己監査はBLOCKER/HIGH/MEDIUMなし。
- **未完了 / 次回:** 本番環境の`DEEPSEEK_DAILY_PLAN_ENABLED`は既定false。実DeepSeek疎通、staging/実機UI確認、段階的flag有効化はデプロイ運用時に実施。

## 2026-08-01 — YouTube feature を main 取り込み・merge-ready へ

- **目的:** PR #25（Draft）を main と整合させ、GHA checkout 欠落を直し、ローカル検証まで完走する。本番/フラグ ON はしない。
- **決定事項:** `origin/main`（abyss ingest #35/#37）を feature へ merge。`abyss-aza-ingest-staging.yml` は main の hardened 版を採用。`youtube-guide-automation.yml` に `actions/checkout@v4` を追加（job summary 用スクリプト必須）。
- **PR 状態:** #34 は feature へ **MERGED 済み**。#25 は **OPEN/Draft のまま**（Ready/merge しない）。
- **未完了 / 次回（オーナー）:** staging Neon へ automation migrate（`20260731120000` 以降）適用承認、provider secrets、kill switch 段階 ON、GHA vars、#25 Ready。

## 2026-07-31 — YouTube自動化PR #34 最終安全監査修正

- **目的:** 最終監査で残ったHIGH 1件（half-open probe固着）とsafety-related MEDIUM 2件（公開済み字幕差分、要約保持期限E2E）をfail-closedで解消。
- **決定事項:** provider circuit probeをowner/token/acquired/expires/stateVersion付きの期限付きpermitへ変更し、取得・期限切れ再取得・結果反映をCASでフェンスする。`PUBLISHED` / `REVIEW_REQUIRED`も現在字幕を必ず再取得し、metadata/transcript/analyzer/prompt/schema/policyの完全キー一致時だけAIを省略する。run/API/Job Summaryはstrict allowlistのみ。
- **Migration:** `20260731180000_fence_provider_circuit_probe`をforward-onlyで追加。旧half-open行は即時再取得可能なopenへ戻す。旧`20260731120000_add_youtube_automation_pipeline`は変更せずSHA-256 `7928117E523BD141317073E1C31B34785AB7873988A079DC5FA2BFDEAA8E47AD`を維持。
- **検証:** Prisma generate/validate、typecheck、lint、Vitest 374成功・DB専用46 skip、Next production build、production dependency audit 0、Flutter analyze 0件・764テスト成功。CI disposable PostgreSQLでmigration upgrade/中断rollback/clean retry、migrate deploy/status、DB全テスト、build、auditがpush/PRとも成功。MobileとWeb/Mobile Golden parityもpush/PRで成功。修正後再監査はBLOCKER 0 / HIGH 0 / safety-related MEDIUM 0、review thread 0件。Flutter契約変更なし。
- **未完了 / 次回（更新）:** PR #34 は feature へ MERGED 済み。staging/production migration、実provider、cron/dispatch、flag有効化は未実施。PR #25 は Draft 維持。

## 2026-07-30 — gcsim 完全廃止（おすすめ編成は維持）

- **決定:** gcsim シミュレーション層を削除。AZA.GG / 共起 / ルールベースのおすすめ編成と Job API は維持。
- **削除:** runner / Config 生成 / IDマップ / rotation / `GCSIM_*` / `TeamSimulationCache` / `docs/GCSIM_INTEGRATION.md` / vendor 想定パス。
- **環境変数:** `TEAM_RECOMMENDATION_MAX_*` / `TEAM_RECOMMENDATION_JOB_TTL_SECONDS` / `TEAM_RECOMMENDATION_SCORE_*`（旧 `GCSIM_*` は互換読取しない）。
- **Migration:** `20260730120000_drop_team_simulation_cache`（staging/production への apply は別 ops）。
- **未完了:** staging での migrate deploy、Vercel 環境からの旧 `GCSIM_*` 削除確認。

## 2026-07-28 — 全体品質仕上げとBuild Guide公開安全性

- **目的:** 既存機能・ドメイン計算を維持し、公開中の編集、楽観ロック、公開前検証、管理UI、外部URL、開発手順をリリース前品質へ揃える。
- **決定事項:** 公開中の保存・承認・revision復元は旧公開スナップショットを直接上書きせず`adminWorkingDraft`を使う。公開・公開取り消し・overrideは`id + updatedAt`完全一致の条件付き更新とrevision/auditを同一transactionで行う。公開時は採用/部分採用した根拠だけを使い、チャンネル許可、public動画、evidence=`approved`、管理レビュー、Amberマスター、pieces、citationをサーバーで再検証する。
- **安全性/UI:** 公開出典URLをHTTPS YouTube/youtu.beへ限定。管理画面は未保存の選択移動を確認し、409後も入力を保持、未保存・未承認時のdisabled理由を表示。マスター一覧の取得はレコード選択時の1回と明示再試行に限定。
- **最終レビュー:** 管理変異の`expectedUpdatedAt`を必須化し、全更新を`id + updatedAt`条件へ統一。作業下書き承認で公開`lastVerifiedAt`を動かさず、`adminConfirmed: true`と`structuredReviewStatus: admin_confirmed`を公開必須にした。ETagは公開DTO全体を指紋化し、weak/list形式の`If-None-Match`にも対応。Web/FlutterのYouTube URLは`youtube.com`、`www.youtube.com`、`m.youtube.com`、`youtu.be`だけを許可する。
- **変更ファイル（主要）:** `src/lib/build-guides/{store,structured-admin,public-recommendation-normalize}.ts`、管理route/editor、回帰テスト、README/開発資料/Build Guide運用資料。
- **検証:** Prisma 6.19.3 generate/validate成功、local SQLite 11 migrationsでstatus/deployともpendingなし、typecheck/lint成功、Vitest 334成功・環境依存DB integration 1 skip、Flutter analyze 0件・756テスト成功・debug APK成功、Next.js 16.2.12 production build成功、production dependency audit 0。
- **未完了 / 次回:** 本番migration・デプロイは未実施。signed release、staging疎通、実機migration/UI確認、CIは運用者ゲート。dev-only ESLint依存にhigh advisory 9件が残るため、互換修正版待ち（`audit fix --force`禁止）。

## 2026-07-26 — 承認済み編成テンプレートと事前生成入れ替え候補

- `team-recommendations/replacements/`へTeamSource、ローカルJSON、正規化、Prisma永続化、10〜20件の一次絞り込み、DeepSeek JSON評価、Zod＋決定論的最終検証、版付きキャッシュを追加。GenshinBuilds接続は公開API許可待ちで意図的に未実装。
- 管理APIはBearer認証・fail closed・10回/分制限。DeepSeekは管理者の事前生成だけで呼び、Flutter公開GETは検証済みキャッシュだけを返す。
- Flutterは既存おすすめ編成に承認テンプレートを統合し、編成適性／端末計算の育成準備度／重み付き総合点、フィルター、確認後の編成反映を追加。
- Next.jsは既知アドバイザリ対応で16.2.12へ更新。npm auditはNext内包postcss/sharpのhigh 3件が残り、非破壊修正版待ち（`--force`はNext 9.3.3へdowngradeするため禁止）。
- DBモデルは現行Prismaへ追加済み。mainはSQLiteで、Neon/PostgreSQL基盤のPR #16はDraft・競合中・本番未適用のため、この機能のproduction Neon migrationは同PR統合後に再生成・staging検証が必要。
- 詳細と運用手順は`docs/TEAM_TEMPLATE_REPLACEMENTS.md`。

## 2026-07-20 — おすすめ編成: リクエスト正規化 + gcsim IDマップ拡充

- Flutterは旅人複合ID等を除外し、APIの`^\d{5,12}$`/元素/レアリティ制約に合うスナップショットだけ送る。attackerが落ちた場合は`attackerUnavailable`。
- gcsim IDマップは`v2.43.4`の`data_gen.textproto`/`config.yml`から生成（キャラ106・武器228・聖遺物52）。再生成は`node scripts/generate-gcsim-id-maps.mjs`。
- 公式最新releaseも`v2.43.4`のまま。サンドローネ等はupstream未実装のためシミュレーション不可（AZA/ルールへフォールバック）。
- ローカル有効化: `vendor/gcsim/v2.43.4/`へ公式バイナリ配置（SHA-256検証）+ `GCSIM_ENABLED=true`。バイナリは`.gitignore`。
- 未完了: 旅人複合ID→gcsimキー変換、gcsim新version取り込み（upstream release待ち）、production有効化前のdurable queue再評価。

## 2026-07-20 — gcsimおすすめ編成バックエンド

- gcsimは`v2.43.4` / commit `24042de8ba3243693e97cd7efe22292762b08331` / 公式release SHA-256へ固定。macOS 2 assetを含めGitHub release digestと再照合済み。既定`GCSIM_ENABLED=false`。
- APIは正規化済み戦闘DTOだけを受け、未知キーを拒否する。Cookie、UID、HoYoLAB本文、任意Config/command/pathは受けない。
- `team-recommendations/`を候補生成、ID mapper、Config、rotation、Runner、parser、score、store/serviceへ分割。Runnerはshellなし・固定path/checksum・temp cleanup・timeout/output/concurrency制限・環境変数除去。
- Prisma migration `20260720120000_add_team_simulation_jobs`は`TeamSimulationJob`と`TeamSimulationCache`の追加のみ。本番未適用。
- gcsim未対応/失敗時もAZA.GG・ルール候補を返す。成功値だけcache更新し、失敗時はstale最終成功値を使う。
- process-localバックグラウンド実行は初期実装。同一request enqueueのsingle-flight、既定8 active Job上限、期限切れcache purgeを適用し、複数instance/production有効化前にdurable queue/workerを再評価する。

---

## 2026-07-19 — Android release backend URL gate

- **目的:** 署名Release AABへFlutter用Next.js backend originを安全に必須注入する
- **決定事項:** `GENSHIN_BUILDER_API_BASE_URL`は単一のGitHub Secretから取得する。値をログへ出さず、空値、空白、不正URL、非HTTPS、userinfo、path/query/fragment、localhost、loopback、`10.0.2.2`をbuild前に拒否する。末尾の`/`は許容する
- **変更ファイル（主要）:** mobile release／CI workflow、Flutter backend URL・workflow契約テスト、`.env.example`、Android release運用資料
- **検証:** Web 155件、Flutter 588件、analyze 0 issue、lint、typecheck、Prisma validate/generate、Next.js production build、YAML構文、URL検証10ケースが成功
- **未完了 / 次回:** GitHub Secret登録、branch protection、production migration、staging 4経路、release workflow、署名AAB実機確認、AZA.GG利用許可証跡は外部環境作業として未実施

## 2026-07-19 — AZA.GG 深境螺旋統計バックエンド

- **目的:** Flutter に AZA.GG の深境螺旋キャラクター／編成統計を安全に提供する
- **決定事項:** Flutter は AZA を直接呼ばず `GET /api/abyss/statistics` のみ利用。`AbyssStatisticsProvider` を交換境界とし、AZA 公開 KV API を実レスポンスの確認済みフィールドだけで正規化。API キーは現在不要のため未確認ヘッダーを送らない
- **可用性:** Prisma `ExternalApiCache` に最終成功値を保存。6時間 TTL、同一 Node.js プロセス内だけの single-flight、最大1回再試行、期限切れ時の stale fallback、`AZA_ABYSS_ENABLED` kill switch。staging は Vercel→AZA が 403 のため `AZA_LIVE_FETCH_ENABLED=false` とし、GHA が `POST /api/abyss/statistics/ingest` でキャッシュ更新。現時点では AZA 経路に分散ロックを追加しない
- **契約監視:** 既知 `meta.api_ver` は `5.6`。未知版は現行スキーマ適合なら warning で継続、不適合なら `invalidResponse`。2026-07-19 の120キャラは全件 `phase` キーが `"1"` のみで、明示的な `"2"` がない場合だけ補数を使用
- **安全性:** HTTPS upstream、10秒 timeout、2MiB、配列／ID／比率／日時検証、安全なエラー code と許可フィールド限定ログ。ゲームバージョンと編成使用回数は upstream にないため生成しない
- **変更ファイル（主要）:** `src/lib/api/abyss/*`, `src/lib/abyss/*`, `src/app/api/abyss/statistics/route.ts`, `src/app/api/abyss/statistics/ingest/route.ts`, Prisma schema/migration, `.env.example`, `.github/workflows/abyss-aza-ingest-staging.yml`, 関連テスト・資料
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
