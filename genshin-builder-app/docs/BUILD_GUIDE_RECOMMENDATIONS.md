# Build Guide Recommendations（YouTube 映像OCR）

管理者が許可した YouTube チャンネルの動画メタデータを取得し、**公開 YouTube URL を Gemini で映像解析**して画面内の文字・表・ステータスを抽出します。通常コードで検証したあと、DeepSeek V4 Pro で整理し、管理者承認後に Flutter へ「動画内推奨目安」として公開します。

## 役割分担

| 層 | 役割 |
|----|------|
| YouTube Data API | チャンネル/動画メタデータ同期のみ |
| Gemini Video Understanding | 公開 YouTube URL を直接解析し画面内情報を抽出 |
| 通常コード | ID・時刻・数値・用途・マスター整合の検証 |
| DeepSeek V4 Pro | 検証済み映像証拠の統合・矛盾整理（動画本体は見ない） |
| 管理者 | 該当時刻確認・採用/却下・公開 |

## データフロー

1. `/admin/guides` でチャンネル登録（`permissionStatus=approved_for_processing`）
2. YouTube Data API で動画一覧同期
  - チャンネルの投稿一覧（uploads）、または **特定プレイリスト URL/ID**
  - プレイリスト同期は、承認済みチャンネルに属する動画のみ取り込み（未登録チャンネルはスキップ）
  - タイトルに `【原神】` を含む動画のみ取り込み・管理画面の動画一覧に表示
3. `analyzeVideoVisuals` / **`analyzePendingGenshinVideos`** で Gemini に公開 URL を渡し一次探索（既定 1 FPS）
   - 管理画面「最新の未解析を N 件解析」はタイトルに `【原神】` を含む未解析動画を公開日新しい順に処理
   - **「全キャラ解析（未カバー優先）」**は育成ガイド寄りの動画から、まだ推奨のないキャラを1人1本ずつ連続解析（日次上限を最大300まで自動引き上げ）
   - 成功時は映像証拠（pending_review）とキャラ別推奨ドラフトまで作成（自動公開はしない）
4. 候補時刻周辺を `analyzeSelectedRanges` / `reanalyzeVideoVisuals(ranges)` でクリップ再解析（既定 3 FPS、`video_metadata`）
5. Zod + 決定論的検証（用途分類、timestamp、数値、マスター ID）
6. DeepSeek で候補構造化 → `pending_review`
7. 管理者が映像証拠を確認し承認・公開
8. Flutter は公開 API のみ参照（Gemini/DeepSeek 非呼び出し）

## 構造化スキーマ

`CharacterBuildRecommendation` は既存の列との互換性を維持しながら、`structuredPayload` に `schemaVersion: 1` の構造化情報を保存します。

| フィールド | 意味 |
|---|---|
| `weapons` | 管理者確認済みの武器候補。`weaponId`、順位、推奨度、理由、条件、`citationId` |
| `artifactRecommendations` | 4セットまたは2+2。`sets[].setId` と `pieces` を明示し、推測で補完しない |
| `mainStats` | 時計・杯・冠の第一候補、代替、条件 |
| `recommendedStats` | 数値目標。`flat` / `percent` を表示し、未知の ratio はモバイル未表示 |
| `investmentPriority` | 明示された育成優先度。confidence から推測しない |
| `sources` | 公開 DTO のトップレベル出典。各候補は `citationId` で参照 |
| `pendingMentions` | 映像抽出した未確認候補。公開対象ではない |
| `structuredReviewStatus` | `review_required` / `admin_confirmed`。公開 DTO では除去 |
| `adminWorkingDraft` | 公開中の次版。公開 DTO では必ず除去 |

構造化武器が無い古いデータだけは `context.weaponPreference` を `legacy_preference` として読み替えます。この fallback は新しい正式データを上書きしません。

## 管理画面の状態遷移

| 操作 | 永続化と公開への影響 |
|---|---|
| 保存 | 非公開行を更新。公開中は `keepPublished` により `adminWorkingDraft` だけを更新し、旧公開スナップショットと ETag を維持 |
| 検証 / APIプレビュー | DB を変更せず、現在のフォームまたは working draft を公開正規化して問題箇所を返す |
| 承認 | `structuredReviewStatus=admin_confirmed`。公開中の working draft を承認しても行の `published` 状態と旧公開内容を維持 |
| 公開 | working draft を公開列へ昇格し、`publishedContentUpdatedAt` を更新。公開前検証とDB更新・revision・auditを1 transactionで実行 |
| 公開取り消し | `approved` へ戻し `publishedAt` と公開使用フラグを解除。構造化内容とrevisionは保持 |
| revision復元 | 非公開なら編集内容へ復元。公開中なら公開版を直接上書きせず working draft へ復元 |

保存・承認・公開・公開取り消し・revision復元は、画面が取得した `expectedUpdatedAt` を送ります。サーバーは日時をミリ秒単位で完全一致させ、transaction 内でも `id + updatedAt` の条件付き更新を行います。競合は 409 とし、管理画面は入力を消さず最新状態の確認を促します。

公開中の編集で `row.updatedAt` が動いても、公開 API の `updatedAt` / ETag は `publishedContentUpdatedAt` を基準にするため変化しません。

## 公開時の fail-closed 条件

`setRecommendationStatus(..., published)` は UI の検証結果を信頼せず、サーバーで再検証します。

- 現在の状態が `approved` または `published`
- 採用・部分採用した contribution のチャンネルが処理許可済み
- 動画が public
- 対応する映像証拠が `approved`（`pending_review` も拒否）
- `structuredReviewStatus=admin_confirmed`
- `pendingMentions` が空
- `evidence_mention` / `adminConfirmed: false` が正式候補にない
- 武器 ID がローカルマスターに存在
- 聖遺物候補がある場合、Amber マスターを取得でき、setId が存在
- 4セットまたは2+2の pieces 合計が4。未確定 pieces は拒否
- 武器・聖遺物・推奨値・メインステータスの `citationId` が、採用した出典で解決可能

どれかが失敗した場合は更新前に拒否し、旧公開データを維持します。Amber 障害時も、聖遺物候補を含む新しい公開は安全側に停止します。

## 禁止事項

* 動画ダウンロード / フレーム・音声の長期保存
* 概要欄を推奨根拠として AI に渡す / 採用する
* 字幕 TXT/VTT/SRT の手動入力・解析
* 投稿者本人の現在ビルド / ダメージ検証 / 比較画面を自動推奨化
* API キーを Flutter に含める
* 提供終了モデル（例: `gemini-2.0-flash`）の利用

## 環境変数

| 変数 | 説明 |
|------|------|
| `BUILD_GUIDE_ADMIN_SECRET` | 管理 API Bearer。未設定は 503 |
| `YOUTUBE_GUIDE_ENABLED` | 既定 `false` |
| `YOUTUBE_API_KEY` | YouTube Data API（サーバのみ） |
| `GEMINI_VIDEO_ANALYSIS_ENABLED` | 既定 `false` |
| `GEMINI_API_KEY` | Gemini API キー |
| `GEMINI_VIDEO_ANALYSIS_MODEL` | 主モデルは `gemini-3.6-flash`（許可外は fail-closed） |
| `GEMINI_VIDEO_ANALYSIS_TIMEOUT_MS` | 既定 180000 |
| `GEMINI_VIDEO_ANALYSIS_MAX_ATTEMPTS` | 既定 2 |
| `GEMINI_VIDEO_MAX_DURATION_SECONDS` | 動画時間上限 |
| `GEMINI_VIDEO_DISCOVERY_FPS` | 一次探索 FPS（既定 1） |
| `GEMINI_VIDEO_DETAIL_FPS` | 詳細クリップ解析 FPS（既定 3） |
| `GEMINI_VIDEO_MAX_DETAIL_FPS` | FPS 上限 clamp（既定 5） |
| `GEMINI_VIDEO_MAX_RANGE_SECONDS` | 1 範囲の最大秒数（既定 180） |
| `DEEPSEEK_GUIDE_ANALYSIS_*` | 検証済み証拠の統合用（動画解析ではない） |

## 採用 Gemini モデル

* **主モデル / 既定**: `gemini-3.6-flash`（公式 Video understanding の YouTube URL 例）
* **一時フォールバック（既定にしない）**: `gemini-2.5-flash` / `gemini-2.5-pro`  
  → Google の提供終了予定: **2026-10-16**
* **削除済み**: `gemini-2.0-flash`（**2026-06-01** 提供終了）

モデル未設定・許可外は解析不可です。

Gemini 3.6 Flash リクエストでは非推奨 sampling パラメータ（`temperature` / `top_p` / `top_k` / `candidate_count` / `thinking_budget`）を送信しません。`generationConfig` は `responseMimeType: application/json` のみです。

## 指定時間帯クリップ

`analyzeSelectedRanges` および `reanalyzeVideoVisuals`（ranges 指定時）は、プロンプトに時刻を書くだけでなく Gemini `video_metadata` で実際にクリップします。

* `start_offset` / `end_offset`（例: `120s`）と `fps`
* 範囲ごとにリクエストし結果を統合
* 範囲外タイムスタンプは検証で拒否
* requestHash に `analysisMode` / `fps` / 実際の範囲を含め、全動画解析とキャッシュ分離

## コスト対策

* 既定 OFF（kill switch）
* 一次探索 1 FPS、詳細のみ 3 FPS（管理画面にコスト倍率を表示）
* requestHash キャッシュ（force のみ再解析）
* チャンネル日次解析上限
* 同時実行は videoId 単位で排他
* 範囲長上限・範囲数上限
* 失敗時の無限再試行禁止

## 障害時

`GEMINI_VIDEO_ANALYSIS_ENABLED=false` または `YOUTUBE_GUIDE_ENABLED=false` にすると新規解析を停止できます。公開済みデータは公開 API から引き続き取得できます。

## 技術的負債

* 現行実装は `generateContent` + `file_data.file_uri`（YouTube URL）を使用している。Gemini 公式ドキュメントでは Interactions API 側の記載が進んでおり、将来は Interactions API への移行を検討する（本機能の全面移行は未着手）。
* Gemini YouTube URL 入力は公式ドキュメント上 Preview。料金・レート制限の変更に追従すること。
* `gemini-2.5-*` フォールバックは 2026-10-16 終了予定のため、期限前に許可リストから外す。

## Neon / PostgreSQL

現行は SQLite。Neon 移行時は provider 変更後に migration を再生成してください。

## 公開 API（Flutter）

`GET /api/build-recommendations/[characterId]`

* `schemaVersion: 1`
* 正式フィールド: `weapons` / `artifactRecommendations` / `mainStats` / `recommendedStats` / `investmentPriority` / `sources` / `updatedAt`
* 出典はトップレベル `sources[].id` へ正規化し、候補は `citationId` で参照
* `investmentPriority` は明示登録時のみ（`overallConfidence` から推定しない）
* 構造化 `weapons` が無い場合のみ `context.weaponPreference` を legacy 候補へ変換（`dataOrigin: legacy_preference`）
* 映像証拠の `weaponMentions` / `artifactSetMentions` は `structuredPayload.pendingMentions` のみへ格納（正式 `weapons` / `artifactRecommendations` には自動昇格しない。pieces・推奨順位は捏造しない）
* `dataOrigin: evidence_mention` および `adminConfirmed: false` は公開正規化で除外
* 管理画面「構造化編集」で確認・編集・承認・公開（聖遺物は Amber `/reliquary` マスター検索、目標ステは専用フォーム。JSON 手編集は読み取り専用）
* 公開中の編集は `structuredPayload.adminWorkingDraft` に分離（`keepPublished`）。公開 API は下書きを返さない
* 公開前は `validateStructuredForPublish`（pendingMentions・未確定 pieces・未知 setId・解決不能 citation・レビュー未完了で拒否）
* 2+2 構成は管理 override の `structuredPayload` で配列として登録可能
* HTTP: 内容指紋ベースの `ETag` + `Cache-Control: max-age=60, stale-while-revalidate=300`
* 公開内容の時刻は `structuredPayload.publishedContentUpdatedAt`（working draft 保存では変更しない）
* `sources[].sourceUrl` は HTTPS の `youtube.com` / `www.youtube.com` / `m.youtube.com` / `youtu.be` のみ。サーバー正規化と Flutter 起動前の両方で検証
* ratio は公開 JSON に含められるがモバイル表示は未対応（管理画面で警告、公開はブロックしない）

正規化実装: `src/lib/build-guides/public-recommendation-normalize.ts`  
管理バリデーション: `src/lib/build-guides/structured-admin.ts`

## 配布・復旧チェック

本番反映前:

1. DB と環境変数をバックアップし、secret を成果物へ含めていないことを確認
2. `npm ci`
3. `npx prisma generate`
4. `npx prisma validate`
5. 対象 DB を明示して `npx prisma migrate status`
6. 承認された migration だけを `npx prisma migrate deploy`
7. `npm run typecheck && npm run lint && npm test && npm run build`
8. staging で管理 API の 401 / 403 / 503、保存、検証、承認、公開、公開取り消し、409 を確認
9. 公開 API の 200 / ETag / 304と、管理情報が含まれないことを確認
10. Flutter で Akasha / YouTube の分離、出典、空・エラー・再試行を確認

障害時は新規解析の kill switch を OFF にし、公開データを維持したまま原因を切り分けます。誤公開は「公開取り消し」で `approved` に戻し、必要なら revision を working draft へ復元して再検証します。migration の巻き戻しは SQL を即興で実行せず、バックアップ復元またはレビュー済みの forward fix を使います。

### トラブルシューティング

- **409 conflict**: 別の更新が先に保存済み。画面の入力は保持される。最新データと差分を確認して再実行する
- **ETag が更新されない**: working draft の保存だけなら仕様どおり。実際の「公開」後に `publishedContentUpdatedAt` が更新される
- **working draft が見えない**: 公開 API には出ない。Bearer 認証済みの `/admin/guides` で対象行を選択する
- **Amber 取得失敗 / 不明 setId**: 聖遺物を含む公開は停止。IDを推測せず、マスター復旧後に検索ピッカーで置換する
- **401 / 403 / 503**: Bearer 不足 / 不一致 / `BUILD_GUIDE_ADMIN_SECRET` 未設定。レスポンスやログへ secret を出さない
- **Flutter パースエラー**: 公開 API の `schemaVersion` と DTO を確認。未知フィールドは無視し、必須フィールド破損はセクションエラーとして再試行可能にする
