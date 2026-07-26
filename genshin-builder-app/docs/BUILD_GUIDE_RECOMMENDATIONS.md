# Build Guide Recommendations（YouTube 攻略動画推奨ステータス）

管理者が許可した YouTube チャンネルの動画メタデータを取得し、**手動貼り付けの字幕**を DeepSeek V4 Pro で抽出・検証したうえで、承認後に Flutter へ「動画内推奨目安」として公開する機能です。

## データフロー

1. `/admin/guides` でチャンネル登録（`permissionStatus` を設定）
2. YouTube Data API（`youtube.googleapis.com` 固定）で動画一覧を同期
3. 管理者が動画を選び、TXT / VTT / SRT 字幕を貼り付けて解析
4. DeepSeek（`deepseek-v4-pro` 既定、`thinking: disabled`）がチャンク抽出 → 統合
5. 決定論的検証（キャラ ID・evidence snippet・min≤rec≤max・inferred 除外）
6. `pending_review` → 承認 → 公開（`approved_for_processing` 以外は公開不可）
7. Flutter は `GET /api/build-recommendations/:characterId` のみ参照（DeepSeek 非呼び出し）

```text
Admin UI → /api/admin/build-guides → YouTube / transcript / DeepSeek → SQLite
Flutter  → /api/build-recommendations/[characterId] → 公開済みのみ
```

## 字幕を自動取得しない理由

- 非公式キャプションスクレイピング・音声認識・OCR は本機能の範囲外
- 著作・利用許諾・利用規約リスクを管理者が制御できるようにする
- 字幕全文は **DB に保存しない**（実行中メモリのみ）。保存するのは `transcriptHash`・形式・件数・短い evidence（≤200 文字）

再解析時は管理者が字幕を再貼り付けするか、hash 不一致で新規 Job になります。

## 環境変数

| 変数 | 説明 |
|------|------|
| `BUILD_GUIDE_ADMIN_SECRET` | 管理 API Bearer。未設定は 503 fail-closed |
| `YOUTUBE_GUIDE_ENABLED` | 既定 `false`。`true` のときのみ YouTube 呼び出し |
| `YOUTUBE_API_KEY` | YouTube Data API キー（サーバのみ） |
| `YOUTUBE_TIMEOUT_MS` | タイムアウト |
| `DEEPSEEK_GUIDE_ANALYSIS_ENABLED` | 既定は有効化しない。`true` で解析可 |
| `DEEPSEEK_GUIDE_ANALYSIS_API_KEY` | 未設定時は `DEEPSEEK_API_KEY` にフォールバック |
| `DEEPSEEK_GUIDE_ANALYSIS_MODEL` | 既定 `deepseek-v4-pro` |
| `GUIDE_TRANSCRIPT_MAX_BYTES` | 字幕入力上限（既定 500000） |

編成テンプレート用の `DEEPSEEK_*` / `TEAM_TEMPLATE_ADMIN_SECRET` は変更しません。

## 公開表現

- UI ラベルは「動画内推奨目安」
- 公式 / 理想 / 最適の断定禁止
- 条件付き効果・編成バフ非含有の注意を維持

## 削除・クリア

- 管理 action `deleteTranscriptData`: `rawAiOutput` を空にし Job を `transcript_cleared` に更新
- 公開取り下げ: `unpublishRecommendation`（status を `approved` に戻し `publishedAt` を null）

## 将来境界（未実装）

- 字幕公式 API からの自動取得
- 音声認識 / OCR
- ダメージ計算や最適ビルド生成

## Neon / PostgreSQL への移行メモ

現行 datasource は **SQLite**（`provider = "sqlite"`）です。将来 Neon 等へ移す場合:

1. `prisma/schema.prisma` の `datasource db.provider` を `"postgresql"` に変更
2. `DATABASE_URL` を Postgres 接続文字列へ
3. **既存 SQLite 用 migration を流用せず**、`prisma migrate diff` 等で Postgres 向け migration を再生成する
4. JSON は当面 `String` カラムのままでも可。必要なら段階的に `Json` 型へ

Draft PR #16（Neon）の内容はこの機能ブランチでは取り込みません。

## 管理 UI

- URL: `/admin/guides`
- モジュール: チャンネル / 動画 / 解析実行 / 推奨詳細 / 動画比較・矛盾
