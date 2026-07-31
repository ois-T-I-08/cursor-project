# YouTube 育成ガイド自動化

## 安全境界

自動化は fail-closed です。`YOUTUBE_GUIDE_ENABLED`、
`YOUTUBE_AUTOMATION_ENABLED`、対象ステージのフラグがすべて明示的に
`true` の場合だけ実行します。初期値、CI、staging template はすべて
`false` です。Cookie、非公式 scraping、動画ファイルのダウンロードは
実装していません。

初期の自動公開対象は、許可済みチャンネルの単一動画から得たデータだけです。
字幕、厳格 JSON Schema、既知 ID、引用、タイムスタンプ、証拠一致、
confidence、競合なしの全条件を満たさなければ公開しません。複数動画の
決定論的統合は競合検出まで行いますが、常に
`READY_TO_PUBLISH` / review-only です。

## 状態と再開

```text
DISCOVERED
  -> METADATA_FETCHED
  -> TRANSCRIPT_FETCHED
  -> ANALYZING
  -> VALIDATING
  -> READY_TO_PUBLISH
  -> PUBLISHED

任意の処理中状態 -> RETRYABLE_ERROR -> METADATA_FETCHED（有限回の再開）
任意の未公開状態 -> BLOCKED
```

`GuidePipelineRun.pipelineRunId`、discovery key、transcript identity/hash、
analysis key、`publicationKey`、revision/audit action key は PostgreSQL の
UNIQUE 制約でも重複を防ぎます。worker は DB lease の
`leaseOwner`、`leaseAcquiredAt`、`leaseExpiresAt`、`leaseVersion` を
compare-and-set し、期限切れ lease だけを再取得します。

retry は指数 backoff、上限回数、`nextRetryAt`、`resumeStatus` を持ちます。
provider circuit は `closed` / `open` / `half_open` を DB に保存し、
cooldown 後の probe を一 worker だけへ許可します。

## 字幕

字幕経路は公式 YouTube Data API captions の OAuth アダプターだけです。
投稿者字幕を自動字幕より優先し、指定言語順と track ID で決定論的に選びます。
資格情報または track がなければ `BLOCKED_TRANSCRIPT_UNAVAILABLE` となり、
別経路へ fallback しません。実行主体が字幕へアクセスできる OAuth 権限を
持つ場合だけ取得できます。

字幕本文と segment 本文は `GuideTranscript` /
`GuideTranscriptSegment` に保存する内部データです。アクセス経路は
server-only の Prisma store と解析 runner に限定します。公開 API、
job summary、通常ログ、provider error、audit detail には本文を入れません。
通常の運用情報は次だけです。

- videoId
- language
- segment count
- transcript hash
- provider ID
- safe error code

保持期間は quality policy の `transcriptRetentionDays`（現在 30 日）です。
`deleteExpiredTranscripts` は期限切れ transcript を最大 1,000 件ずつ削除し、
segment は cascade delete します。検証済み公開 snapshot、revision、
本文を含まない citation timestamp は残ります。削除は maintenance flag を
有効化した保守 run からのみ呼び出し、実行件数だけを監査します。

## 解析と公開

解析 provider は schema-constrained JSON を要求し、その後にローカルでも
strict Zod schema と意味検証を行います。自由文 provider response は
`rawAiOutput` へ保存しません。各 claim は既存マスター ID、存在する segment、
証拠文字列一致、confidence を検証し、timestamp は検証済み segment から
計算します。

自動公開 transaction は次を一括処理します。

1. 完成した公開 DTO の事前 schema 検証
2. item、channel permission、source availability、evidence の再確認
3. published snapshot 作成
4. item-level contribution 作成（字幕本文はコピーしない）
5. revision / ETag / validation metadata 作成
6. item を `PUBLISHED` へ compare-and-set
7. pipeline event / audit 作成

途中失敗は全て rollback します。外部 provider 失敗、source unavailable、
低品質な再解析は、既存の公開済み snapshot を削除・非公開化しません。
maintenance は source の availability と `unavailableSince` だけを更新します。

## API 互換方式

方式 B（versioned endpoint）を採用しました。既存クライアントを壊さず、
字幕本文を返さない新契約を明確に分離できるためです。

- v1: `GET /api/build-recommendations/{characterId}`（変更なし）
- v2: `GET /api/v2/build-recommendations/{characterId}`

v2 は `verificationMode`、source の `availability` /
`unavailableSince`、evidence の `timestampStart` / `timestampEnd` を返し、
`exactVisibleText` を返しません。Flutter は v2 を先に取得し、v2 endpoint が
404 の旧 server では v1 へ fallback します。source unavailable は表示し、
公開済み snapshot の内容は引き続き閲覧できます。

## 管理と緊急停止

`/admin/guides` の「自動化監視」は flags、緊急停止、run、item、retry、
circuit、active lease、安全な failure code を表示します。字幕本文と
provider response は返しません。管理 API は既存の Bearer 認証、サイズ制限、
rate limit を共有し、secret 未設定 503、認証なし 401、不正 Bearer 403 です。

緊急停止は `GuideAutomationControl` に version 付きで保存します。解除しても
環境フラグが自動で有効になることはありません。

## GitHub Actions と段階導入

`youtube-guide-automation.yml` は staging environment 専用です。schedule と
workflow_dispatch を定義しますが、Repository Variable
`YOUTUBE_AUTOMATION_ENABLED` が `true` でなければ job は skip されます。
schedule 制御に secret は使いません。認証には staging 専用 secret を使い、
production secret は参照しません。concurrency は 1、timeout は 10 分です。
job summary は件数と `pipelineRunId` だけで、字幕や provider response を
含みません。

段階導入順:

1. 全フラグ false（初期状態）
2. dry-run
3. discovery
4. transcript / analysis / validation
5. 単一 source auto publish
6. maintenance
7. schedule

default branch へ入る前は workflow_dispatch、cron、実 staging provider、
auto publish を実行済みとは扱いません。

## 障害時の手順

1. 管理画面で緊急停止を ON にする。
2. provider circuit、safe error code、retry 予定を確認する。
3. 外部障害中は既存 snapshot を維持し、source を削除しない。
4. 必要なら revision restore または既存の unpublish 操作を管理者判断で行う。
5. 原因解消後、フラグを一段ずつ戻し dry-run から再開する。

DB migration の rollback は schema を逆変更せず、アプリ flags を false に
して旧コードへ戻すのが第一手段です。forward migration は disposable
PostgreSQL で `migrate deploy` / `migrate status` を検証し、production または
staging DB にはこの作業から適用しません。
