# YouTube 育成ガイド自動化

## 安全境界

自動化は fail-closed です。`YOUTUBE_GUIDE_ENABLED`、
`YOUTUBE_AUTOMATION_ENABLED`、対象ステージのフラグがすべて明示的に
`true` の場合だけ実行します。初期値、CI、staging template はすべて
`false` です。Cookie、非公式 scraping、動画ファイルのダウンロードは
実装していません。

runner は全候補を検証して `READY_TO_PUBLISH` にする Pass 1 と、character
単位で公開可否を決める Pass 2 に分かれます。初期の自動公開対象は、
許可済みチャンネルの単一動画から得たデータだけです。
字幕、厳格 JSON Schema、既知 ID、引用、タイムスタンプ、証拠一致、
confidence、競合なしの全条件を満たさなければ公開しません。source 数は
caller の値を使わず、character publication lease の内側で候補 item と
既存 published contribution の distinct videoId を transaction 内で
再計算します。2 source 以上は `REVIEW_REQUIRED` /
`MULTI_SOURCE_REVIEW_REQUIRED` となり、既存 snapshot と ETag は維持します。

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
複数 source -> REVIEW_REQUIRED
緊急停止 -> STOPPED
```

`GuidePipelineRun.pipelineRunId`、discovery key、transcript identity/hash、
analysis key、`publicationKey`、revision/audit action key は PostgreSQL の
UNIQUE 制約でも重複を防ぎます。worker は DB lease の
`leaseOwner`、`leaseAcquiredAt`、`leaseExpiresAt`、`leaseVersion` を
compare-and-set し、期限切れ lease だけを再取得します。各 item は
`pipeline-item:<itemId>` を `<pipelineRunId>:<workerId>` で claim し、
状態更新は active run、owner、leaseVersion、stateVersion の一致を必須に
します。origin run は保持し、別 run の resume は active/last run だけを
原子的に更新します。stale worker と lease 取得の敗者は status を変更できません。

retry は指数 backoff、上限回数、`nextRetryAt`、`resumeStatus` を持ちます。
provider circuit は `closed` / `open` / `half_open` を DB に保存し、
cooldown 後の probe を一 worker だけへ許可します。probe は
`probeOwner`、単調増加する `probeToken`、`probeAcquiredAt`、
`probeExpiresAt`、`stateVersion` を持ち、取得と期限切れ再取得は DB の
compare-and-set です。成功／失敗の反映にも同じ permit と有効期限を必須とし、
期限切れまたは旧 owner の結果は破棄します。worker が probe 中に停止しても
期限後に一 worker だけが再取得できます。half-open 中の circuit 対象外エラーは
失敗回数へ加算せず closed に戻します。

## 字幕

字幕経路は公式 YouTube Data API captions の OAuth アダプターだけです。
投稿者字幕を自動字幕より優先し、指定言語順と track ID で決定論的に選びます。
資格情報または track がなければ `BLOCKED_TRANSCRIPT_UNAVAILABLE` となり、
別経路へ fallback しません。実行主体が字幕へアクセスできる OAuth 権限を
持つ場合だけ取得できます。

`PUBLISHED` / `REVIEW_REQUIRED` の item も再実行時に現在の字幕を取得し、
正規化した transcript hash、metadata hash、analyzer / prompt / schema /
policy version から完全な analysis key を再計算します。全入力が一致する場合
だけ解析 provider を省略します。字幕または解析入力が変わった場合だけ再解析し、
現在字幕を確認できない場合は item を `BLOCKED` / `RETRYABLE_ERROR` にして、
既存の公開 snapshot、ETag、`publishedAt` は更新しません。

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
検証後の永続 payload は `evidenceText` を除去した canonical 型です。
segment ID、evidence hash、timestamp、transcript hash だけを保存し、
provider response や verbatim 抜粋は analysis、draft、revision、audit、
event に残しません。`deleteExpiredTranscripts` は期限切れに加え、関連 item
が terminal、retry 予定なし、active item lease なしであることを同じ
transaction 内で row lock 後に再確認します。segment は cascade delete
します。検証済み公開 snapshot、revision、本文を含まない citation
timestamp/hash は残ります。削除は
`YOUTUBE_GUIDE_MAINTENANCE_ENABLED=true` の保守 run からのみ呼び出し、
実行件数だけを監査します。

## 解析と公開

解析 provider は schema-constrained JSON を要求し、その後にローカルでも
strict Zod schema と意味検証を行います。自由文 provider response は
`rawAiOutput` へ保存しません。各 claim は既存マスター ID、存在する segment、
証拠文字列一致、confidence を検証し、timestamp は検証済み segment から
計算します。

自動公開 transaction は次を一括処理します。

1. control singleton row lock と emergency stop 再確認
2. item lease/fence、active run、input hash、policy/schema の再確認
3. candidate/contribution source cohort のDB再計算
4. canonical validation hash の再検証と validated result 作成
5. working draft と published snapshot 作成
6. contribution 作成（字幕本文はコピーしない）
7. revision / ETag / validation metadata 作成
8. audit、recommendation/item status、pipeline event 更新

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
404 の旧 server だけで v1 へ fallback します。401/403/500、timeout、
malformed payload、未対応 schemaVersion では fallback しません。
source unavailable は source と evidence timestamp の両リンクを無効にし、
semantic label で利用不能を通知します。公開済み snapshot の内容は引き続き
閲覧できます。

## 管理と緊急停止

`/admin/guides` の「自動化監視」は flags、緊急停止、run、item、retry、
circuit、active lease、安全な failure code を表示します。字幕本文と
provider response は返しません。管理 API は既存の Bearer 認証、サイズ制限、
rate limit を共有し、secret 未設定 503、認証なし 401、不正 Bearer 403 です。
pipeline run POST は `application/json` または
`application/json; charset=utf-8` だけを受け付け、それ以外は 415 です。

緊急停止は `GuideAutomationControl` に version 付きで保存します。runner
入口と各外部 stage/maintenance の直前に fail-closed で確認し、publish と
stop 更新は同じ singleton row を `FOR UPDATE` します。row missing/読取失敗も
停止です。解除しても環境フラグが自動で有効になることはありません。

## GitHub Actions と段階導入

`youtube-guide-automation.yml` は staging environment 専用です。schedule と
workflow_dispatch を定義しますが、Repository Variable
`YOUTUBE_AUTOMATION_ENABLED` が `true` でなければ job は skip されます。
schedule 制御に secret は使いません。認証には staging 専用 secret を使い、
production secret は参照しません。concurrency は 1、timeout は 10 分です。
job summary は件数と `pipelineRunId` だけで、字幕や provider response を
含みません。runner の戻り値、`GuidePipelineRun.summaryPayload`、管理 API
成功レスポンスは同じ strict allowlist schema を通過した
`pipelineRunId`、実行状態の boolean、状態別件数だけです。workflow は
`format-youtube-guide-job-summary.mjs` を実際の API レスポンスへ適用し、
未知フィールド、本文、provider raw response、自由形式 error message を
含むレスポンスを fail-closed で拒否します。

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

### Staging 進捗（PR #25 / tip `fc7b762` 時点）

| Tier | 内容 | 状態 |
|------|------|------|
| A（gate-only） | 全 flags `false` のまま `dryRun:true`。provider 前に `skipped=true`。DB 件数増なし | **PASS**（`2026-08-01` 前後。再検証は下の smoke） |
| B（provider dry-run） | guide+automation+discovery(+gemini) を ON、auto-publish/maintenance は OFF。OAuth/API 実呼び出し。内部 pipeline row は増えうる。公開しない | **未実施**（owner 承認 + `YOUTUBE_OAUTH_ACCESS_TOKEN` 等） |

実施済み（secrets / 値は記録しない）:

- Vercel `ois/staging` に feature tip を redeploy（admin / v2 routes が実 API）
- Neon staging に automation migrations（`20260731120000` 以降）適用済み
- 公開 API は published guide なしで JSON `notFound`（500 ではない）
- Gate-only smoke: `genshin-builder-app/scripts/gate-only-smoke.mjs`

```powershell
# PowerShell（秘密はチャットに貼らない。Clipboard なら Trim）
$env:BUILD_GUIDE_ADMIN_SECRET = (Get-Clipboard).Trim()
node genshin-builder-app/scripts/gate-only-smoke.mjs
Remove-Item Env:BUILD_GUIDE_ADMIN_SECRET
```

期待: `GATE_SMOKE=PASS`、全 flag `false`、`skipped=true`、`*_delta=0`。
Admin GET の flags / control / runs は **`automation` 配下**（UI と同じ）。

まだ触らない（要承認）: いずれかの kill switch を `true`、OAuth token 追加、
GHA `environment: staging` / repo var 解錠、auto-publish、PR Ready / merge、production。

### merge-ready 後の staging 段階導入チェックリスト

コードが default branch に入ったあとも、フラグはすべて `false` のまま開始する。

1. Neon staging に automation migrations（`20260731120000` 以降）を `migrate deploy` — **staging は適用済み**
2. GitHub `environment: staging` に `STAGING_API_BASE_URL` / `STAGING_BUILD_GUIDE_ADMIN_SECRET`、repo var `YOUTUBE_AUTOMATION_ENABLED`（job 解錠用）を用意。schedule はまだ実質 OFF（アプリ flags false）
3. Vercel staging に staging 専用 provider secrets を登録（チャット・git に書かない）。字幕経路には `YOUTUBE_OAUTH_ACCESS_TOKEN` が必要
4. Tier A smoke 再確認 → Tier B（provider dry-run）→ discovery → transcript/analysis → 単一 source auto-publish → maintenance → schedule の順で一段ずつ有効化
5. 各段で `/admin/guides` の自動化監視と公開 API を確認。問題時は緊急停止 + 全 flags `false`

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
