# Neon PostgreSQL / YShelper編成統計 運用手順

## 現在確認できている境界

- Next.jsはPrisma 6.19.3、Neon PostgreSQLを使用する。
- `DATABASE_URL`はpooled connection、`DIRECT_URL`はdirect connection専用。
- FlutterはNext.jsの公開APIだけを呼び、NeonとYShelperへ直接接続しない。
- リポジトリ内にYShelperの正式なendpoint、利用条件、匿名化fixture、レスポンス型は存在しない。
- そのため実URLやフィールドを推測していない。`YSHELPER_ADAPTER_MODE`未設定時はCollectorが外部通信を開始しない。

`canonical-v1`は確認済みbridge responseを差し込むためのリポジトリ内契約であり、YShelperの生レスポンス仕様を表すものではない。

## Neonセットアップ

1. Neonで空のdevelopment branchとdatabaseを作る。
2. Next.js runtime用のpooled URLを`DATABASE_URL`へ登録する。
3. Migration用のdirect URLを`DIRECT_URL`へ登録する。
4. URLはNext.js/Vercel環境だけに保存し、`NEXT_PUBLIC_`を付けない。
5. 空のdevelopment branchで次を実行する。

```bash
cd genshin-builder-app
npx prisma validate
npx prisma migrate status
npx prisma migrate deploy
npx prisma generate
```

`prisma/migrations/20260724000000_postgresql_baseline`は空のPostgreSQL database向け初期Migrationである。`prisma/migrations-sqlite-archive`は履歴専用で、PostgreSQLへ適用しない。`migrate reset`、DB初期化、Migration再作成は行わない。

## 既存SQLiteデータ

`prisma/dev.db`は削除していない。2026-07-24の調査時点ではマスターデータに加えて匿名`UserProgress`が2件存在した。

- Character/Weapon/Material/UpgradeはNeon適用後に既存`POST /api/sync`で再生成できる。
- `UserProgress`はマスターデータではないため、必要なら所有者の明示判断後に別途export/importする。
- この変更は匿名育成データを自動送信・削除・移行しない。
- 本番SQLiteが別に存在する場合は、件数・保持要件・停止時間を確定してから専用移行を作る。

## 必要な環境変数

Next.js/Vercel:

- `DATABASE_URL`: Neon pooled connection
- `DIRECT_URL`: Neon direct connection
- `YSHELPER_API_BASE_URL`: 利用許可済みHTTPS origin
- `YSHELPER_ABYSS_ENDPOINT`: 確認済み相対path
- `YSHELPER_STYGIAN_ENDPOINT`: 確認済み相対path
- `YSHELPER_ADAPTER_MODE`: fixture一致確認後のみ`canonical-v1`
- `YSHELPER_API_TOKEN`: 必要な場合だけ。ログ・DB・Flutterへ出さない
- `YSHELPER_COLLECT_SECRET`: 内部Collector APIのBearer secret
- `YSHELPER_ABYSS_ENABLED` / `YSHELPER_STYGIAN_ENABLED`: 個別kill switch。明示的な`true`だけ有効
- `YSHELPER_SYNC_INTERVAL_DAYS`: 既定14
- `YSHELPER_REQUEST_TIMEOUT_MS`: 既定15000
- `YSHELPER_MAX_RESPONSE_BYTES`: 既定4194304

GitHub Actions Secrets:

- `GENSHIN_BUILDER_BACKEND_URL`: 末尾pathなしの公開HTTPS origin
- `YSHELPER_COLLECT_SECRET`: Next.jsと同一値

YShelper token、Neon URL、Collector secretをGitHub VariablesやFlutterの`dart-define`へ登録しない。

## 実レスポンスを有効化する前に必要な情報

1. YShelper側の利用許可、規約、レート制限、再配信可否。
2. abyss/stygianそれぞれの正式endpointとHTTP method。
3. token要否と正式な認証header。
4. 個人情報を除去した実レスポンスfixture。
5. season ID、更新日時、sample size、全編成、全キャラ使用率の正式フィールド。
6. usage rateがratioかpercentかの明示仕様。
7. side、stage、usage count、ownership rateが存在するか。
8. source schema/versionの変更通知方法。

fixtureが現在の`canonical-v1`と異なる場合は、生レスポンス専用adapterを追加してから有効化する。adapter testなしで`canonical-v1`へ合わせ込まない。

## Collector

`.github/workflows/yshelper-battle-statistics.yml`は`workflow_dispatch`でのみ内部APIを起動する。定期取得は正式仕様・匿名化fixture・Neon developmentでの検証が揃うまで有効化しない。

```text
POST /api/internal/yshelper/collect
Authorization: Bearer <YSHELPER_COLLECT_SECRET>
```

サーバーは最終完全成功から14日未満なら`skipped / not_due`を返し、外部APIを呼ばない。実行時はprocess-local排他とDB `SyncLease`を併用する。abyss/stygianは個別に記録・検証し、validなSnapshotだけ各Manifestを更新する。片方の失敗値で他方や最終成功値を上書きしない。

手動確認はActionsの`workflow_dispatch`を優先する。ローカルでcurlする場合もsecretをコマンド本文・ログ・スクリーンショットへ残さない。

## 検証と保持

- HTTP status、JSON Content-Type、timeout、最大bytes、UTF-8、JSON objectを境界で検証する。
- percent/ratioは`rateUnit`で明示変換し、値の大きさから推測しない。
- 編成は4人、重複キャラ不可。`teamKey=sort(ids).join(":")`。
- 同一編成順序違いは統合し、同一character scope重複は拒否する。
- 未知Characterは記録するが配信対象から除外し、割合が5%を超えればsuspicious。
- 空、50%超の件数急減、0.5超の既存使用率変化は公開しない。
- `source/contentType/seasonId/payloadHash`が同一ならSnapshotを重複作成しない。
- raw response、完全URL、query、token、Cookie、UIDは保存しない。

SnapshotとSyncRunは監査履歴として現時点では自動削除しない。保持期限を導入する場合は、公開Manifest参照中Snapshotと最終正常Snapshotを必ず除外する。

## 公開APIとFlutter同期

- `GET /api/battle-statistics/manifest`: ETag、`If-None-Match`、304
- `GET /api/battle-statistics/bundle?type=abyss&revision=...&page=...`: 500件単位
- `GET /api/battle-statistics/teams`: cursor、limit最大100、character/side/stage/filter
- `GET /api/battle-statistics/characters`: cursor、limit最大100

Flutterは起動を待たせずManifestを確認する。同一ETagなら終了し、変更された種類だけ全ページを取得する。schema、hash、Character ID、重複を確認後、Drift v9 transactionでManifestとデータを切り替える。失敗・offline・timeout時は旧revisionを維持する。

## production適用

1. YShelper利用許可と匿名化fixtureを確認する。
2. Neon development branchへ`migrate deploy`し、`migrate status`がcleanであることを確認する。
3. stagingへNext.jsをdeployし、`POST /api/sync`でマスタを再生成する。
4. adapterを無効のままManifest/認証/404/ページ上限を確認する。
5. stagingだけに確認済みYShelper設定を登録する。
6. 手動Collectorで`published / duplicate / not_due / upstream failure`を確認する。
7. Flutterで304、revision変更、hash不一致、offline、transaction rollbackを確認する。
8. production NeonへMigrationを明示作業で適用する。
9. production環境変数を登録し、最後に個別kill switchを有効化する。

このリポジトリ変更だけではNeon branch作成、Vercel環境変数、GitHub Secrets、本番Migration、deployを実行しない。

## rollback

1. `YSHELPER_ABYSS_ENABLED=false`と`YSHELPER_STYGIAN_ENABLED=false`で収集を停止する。
2. Actionsの手動Collectorを実行せず、必要ならCollector secretをローテーションする。
3. Next.jsを直前の正常versionへ戻す。
4. Manifestは最終正常Snapshotを指したまま維持し、Flutterは端末内キャッシュを使う。
5. PostgreSQL追加テーブルは即時DROPしない。アプリrollback中も履歴として保持する。
6. DBを戻す必要がある場合は別のレビュー済みforward migrationを作る。Migration fileの削除・履歴書換え・`migrate reset`はしない。
