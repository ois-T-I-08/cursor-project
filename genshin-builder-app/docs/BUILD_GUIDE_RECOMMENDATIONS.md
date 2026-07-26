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
2. YouTube Data API で動画一覧同期（タイトル・公開日・時間・privacy 等）
3. `analyzeVideoVisuals` で Gemini に公開 URL を渡し一次探索（既定 1 FPS）
4. 候補時刻周辺を `analyzeSelectedRanges` / `reanalyzeVideoVisuals(ranges)` でクリップ再解析（既定 3 FPS、`video_metadata`）
5. Zod + 決定論的検証（用途分類、timestamp、数値、マスター ID）
6. DeepSeek で候補構造化 → `pending_review`
7. 管理者が映像証拠を確認し承認・公開
8. Flutter は公開 API のみ参照（Gemini/DeepSeek 非呼び出し）

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
