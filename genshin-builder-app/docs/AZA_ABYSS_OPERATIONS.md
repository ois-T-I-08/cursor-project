# AZA.GG 深境螺旋統計 運用手順

## 現在の契約

- Flutter は `GET /api/abyss/statistics` の内部 DTO だけを利用し、AZA.GG の JSON や API 固有フィールドへ依存しない。
- 既知の `meta.api_ver` は `5.6`。未知版は、現行スキーマに適合すれば warning を残して処理を続ける。スキーマ不適合は `invalidResponse` とし、最終正常キャッシュがあれば stale fallback する。
- キャッシュ TTL の既定値は 21,600 秒（6時間）。成功時だけ `ExternalApiCache` の固定キー `abyss-statistics:latest` を更新し、失敗レスポンスで最終成功値を上書きしない。
- upstream 取得は HTTPS、10秒 timeout、最大2MiB、最大1回の有限リトライで行う。
- **staging** では Vercel→AZA が HTTP 403 になるため、`AZA_LIVE_FETCH_ENABLED=false` とし、GitHub Actions が AZA を取得して `POST /api/abyss/statistics/ingest` でキャッシュを更新する（後述）。

## phase 正規化

- `phase["2"]` が存在し、有効な0〜1の数値なら明示値を下半比率として優先する。
- `phase["2"]` が存在しない場合だけ、有効な `phase["1"]` から `1 - phase["1"]` を計算し、浮動小数点誤差を0〜1へ clamp する。
- `phase`、`phase["1"]` が null／欠損なら、任意値として上半・下半比率を生成しない。
- 存在する値が数値以外または範囲外なら、推測せず `invalidResponse` とする。

2026-07-19 の公開 KV レスポンスを監査した時点では、120キャラクターすべての `phase` キーは `"1"` のみで、`"2"` は0件だった。一部の `phase["1"]` は null であり、null から補数を生成しない。この観測事実は将来のレスポンス契約を保証しないため、版とスキーマの監視を継続する。

## single-flight と分散ロック

現在の実装は `processLocalSingleFlight` である。`AbyssStatisticsService` の同じインスタンスが持つ Promise を共有するため、同一 Node.js プロセス内の同時更新だけをまとめる。複数プロセス／複数インスタンス間の排他は行わない。

現時点では、6時間 TTL、DB の最終成功キャッシュ、最大1回の有限リトライ、想定取得頻度を踏まえ、AZA 統計経路へ分散ロックを追加しない。ロック取得停止、timeout、lease 解放失敗という新しい障害経路を増やす方が現状ではリスクが高い。既存の `SyncLease` migration はマスタ同期向けであり、AZA 統計経路では使用しない。

次のいずれかが観測されたら再評価する。

- 水平スケール後に複数インスタンスから同時更新が継続的に発生する
- AZA.GG の rate limit、timeout、転送量が重複更新によって増加する
- キャッシュ更新競合により古い成功値での上書きが観測される
- インスタンス数またはアクセス数が現在の想定を大きく超える

将来候補は DB の期限付き lease と更新世代の比較、または単一の定期更新ジョブである。採用時は lease の期限切れ、所有者確認付き解放、障害時の stale fallback を先に設計し、無期限ロックを作らない。

## 安全なログ

構造化ログは `event` と、必要な場合だけ次を記録する。

- `sourceApiVersion`
- `scheduleId`
- `itemCount`
- `missingField`
- `invalidField`
- `durationMs`
- `cacheState`
- `fallbackUsed`

レスポンス本文、完全な URL、クエリ文字列、環境変数、Cookie、UID、秘密情報、内部例外、外部 API のレスポンス全文は記録しない。

## migration

2026-07-19 のローカル監査時点で未適用なのは次の2件。

- `20260715181000_add_sync_lease`
- `20260719000000_add_external_api_cache`

今回の変更では本番 DB へ適用しない。DB 初期化、migration の削除／再作成、既存データ削除も行わない。本番ではバックアップと変更時間帯を確認後、Web アプリと同じ revision で次を実行する。

```bash
npx prisma migrate status
npx prisma migrate deploy
npx prisma migrate status
```

適用前の `status` で対象と接続先を確認する。適用後は2件を含む全 migration が適用済みであることを確認する。`migrate dev`、`migrate reset`、DB ファイル削除は本番で使用しない。

`ExternalApiCache` は最終成功スナップショットを JSON 文字列で1行保持する。`source`、`version`、`sampleSize`、`fetchedAt`、`expiresAt` も保存し、履歴行は増やさない。

## staging の4経路確認

最初に `AZA_API_BASE_URL`、`DATABASE_URL`、`AZA_CACHE_TTL_SECONDS` を staging 用に設定し、migration 適用後に確認する。テストでも同じ契約を `abyss-statistics-staging-paths.test.ts` で固定している。

| 経路 | 操作 | 期待結果 |
|---|---|---|
| A: 初回取得 | 対象キーのキャッシュがない状態で1回 GET | HTTP 200、`isStale=false`、upstream 1回、DB 1回更新 |
| B: fresh hit | TTL 内に再度 GET | HTTP 200、`isStale=false`、upstream 0回、DB 更新なし、`fetchedAt` 不変 |
| C: stale fallback | TTL 失効後に staging の到達先を一時的に失敗させて GET | HTTP 200、`isStale=true`、upstream 1回、DB 更新なし、最終成功 `fetchedAt` 不変 |
| D: kill switch | `AZA_ABYSS_ENABLED=false` で GET | キャッシュありは HTTP 200 / stale、なしは安全な HTTP 503。upstream 0回、DB 更新なし |
| E: live fetch off | `AZA_LIVE_FETCH_ENABLED=false` で GET | キャッシュありは HTTP 200（期限切れなら stale）、なしは HTTP 503 `noData`。upstream 0回 |

確認後は staging の到達先と kill switch を元の承認済み値へ戻す。失敗レスポンスで `ExternalApiCache` の `payload`、`fetchedAt`、`expiresAt` が変わっていないことも確認する。

## staging: GHA ingest（推奨経路）

Vercel ランタイムから AZA への outbound が 403 になるため、staging では次の構成を使う。

1. Vercel staging env
   - `AZA_LIVE_FETCH_ENABLED=false`
   - `ABYSS_INGEST_SECRET`（十分な長さのランダム値。production と共有しない）
2. GitHub repository secrets（staging 専用）
   - `STAGING_ABYSS_INGEST_URL`（例: `https://staging-sable.vercel.app/api/abyss/statistics/ingest`）
   - `STAGING_ABYSS_INGEST_SECRET`（Vercel の `ABYSS_INGEST_SECRET` と同じ値）
3. Workflow: `.github/workflows/abyss-aza-ingest-staging.yml`
   - `schedule`（4時間ごと）と `workflow_dispatch`
   - AZA KV を取得 → Bearer 付きで ingest POST
   - **注意:** GitHub は default ブランチ上に workflow ファイルがあるときだけ `schedule` / `workflow_dispatch` が有効になる。feature マージ後、default へ載せるまで手動で同等の curl ingest を使う
4. 確認
   - Actions で1回 `workflow_dispatch`（default ブランチ上にある場合）または手動 curl ingest
   - `GET /api/abyss/statistics` が HTTP 200（キャッシュ配信）

2026-07-30 staging 確認: 手動 AZA fetch → ingest HTTP 200 → GET HTTP 200（`source=AZA.GG`, fresh）。`AZA_LIVE_FETCH_ENABLED=false` / `ABYSS_INGEST_SECRET` を Vercel staging に設定済み。GitHub secrets `STAGING_ABYSS_INGEST_*` 登録済み。

## 障害対応とロールバック

- AZA.GG 障害時は fresh cache を期限まで返し、期限切れ後の取得失敗では最終成功値を `isStale=true` で返す。キャッシュがなければ分類済みの安全なエラーを返す。
- 緊急停止は `AZA_ABYSS_ENABLED=false` を設定してアプリを再デプロイする。キャッシュがあれば stale 表示を継続し、upstream は呼ばない。
- 復旧時は `AZA_ABYSS_ENABLED` を削除するか `true` に戻し、staging の A〜D を再確認する。
- ロールバック時も `ExternalApiCache` を削除しない。最終成功値は障害時の継続表示に必要である。
- AZA.GG のレスポンス契約が変わった場合は、実レスポンスの安全なフィールド構造を確認し、provider／normalizer と契約テストを更新する。存在しない値を推測で生成しない。

公開前には AZA.GG の利用条件、クレジット表記、商用・広告利用可否を運用責任者が確認する。確認記録は URL と日時をテキストで残し、Discord のスクリーンショットや個人情報をリポジトリへ保存しない。
