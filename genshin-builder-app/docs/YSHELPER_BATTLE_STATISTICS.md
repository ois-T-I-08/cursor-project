# Neon PostgreSQL / YShelper編成統計 運用手順

運用 Runbook（有効化前チェック・停止・map更新・障害調査）: [YSHELPER_OPERATIONS_RUNBOOK.md](./YSHELPER_OPERATIONS_RUNBOOK.md)
PR #16 外の将来項目: [YSHELPER_BACKLOG.md](./YSHELPER_BACKLOG.md)

## 現在確認できている境界

- Next.jsはPrisma 6.19.3、Neon PostgreSQLを使用する。
- `DATABASE_URL`はpooled connection、`DIRECT_URL`はdirect connection専用。
- FlutterはNext.jsの公開APIだけを呼び、NeonとYShelperへ直接接続しない。
- 技術的に確認済みのHTTPS endpoint / 生JSON構造は`native-v1` Adapterで`canonical-v1`へ変換する。
- kill switch（`YSHELPER_*_ENABLED`）と`YSHELPER_ADAPTER_MODE`が揃うまでCollectorは外部通信しない。既定は無効。

### 確認済みendpoint（技術仕様）

| contentType | path + fixed query |
|-------------|--------------------|
| `abyss` | `/ys/getAbyssRank.php?star=all&role=all&lang=en` |
| `stygian`（採用） | `/ys/getAbyssRank2.php?star=only_nandu6&role=all&lang=en` |

Base origin例: `https://api.yshelper.com`。全難易度版（`star=all`）は仕様確認用に残してよいが、本番設定例は難度6のみ。

`canonical-v1`はbridge / fixture用契約。`native-v1`が確認済み生レスポンス用Adapter。

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
- `YSHELPER_API_BASE_URL`: HTTPS origin（例 `https://api.yshelper.com`）
- `YSHELPER_ABYSS_ENDPOINT`: 確認済み相対path + 固定query
- `YSHELPER_STYGIAN_ENDPOINT`: 確認済み相対path + 固定query（難度6）
- `YSHELPER_ADAPTER_MODE`: 生JSONは`native-v1`、bridgeは`canonical-v1`。未設定は通信しない
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

## Native Adapter変換（要約）

- キャラクター: `usageRate = use / top_own`、`usageCount = use`、`ownershipRate = own_rate`、`usageAmongOwnersRate = use_rate`（入力はpercent、normalizeでratio）。
- 編成: side件数（`up`/`mid`/`down_use_num` → `upper`/`middle`/`lower`）を`top_own`で割る。side欠落時のみ`use / top_own`。side合計≠`use`はschema error。
- avatar → `ename` → Amber ID。`Ambor`→Amber。`Traveler`は未解決。1〜3人編成・未解決・重複キャラは除外。
- avatar URL・生本文・token・完全URLはDB/ログへ保存しない。

## 開発用Neonでの公開ID照合

- スクリプト: `npm run yshelper:dry-run:db`（`--require-db`）。DB書き込みは行わない。
- シェルに古い`DATABASE_URL=localhost`が残っていると`.env`のNeon URLが上書きされる。照合前に当該変数を外すか、`node --env-file=.env`をクリーンな環境で実行する。
- 2026-07-25時点のlive dry-run: 開発用Neon `Character` 122件に対し、abyss/stygian公開ID欠損0件（union欠損0）。kill switchはfalseのまま。
- `native-v1`はTraveler以外の未解決enameをfail-closedで拒否する（map更新漏れの黙殺防止）。
- upstream fetchは`redirect: "error"`（同一origin open redirect経由の境界迂回を防ぐ）。
- `--require-db`はlocalhost接続を拒否する。

## 有効化前に未確認のまま残す事項

1. 第三者アプリでの利用許可・規約。
2. 保存・加工・再配布可否。
3. 正式なレート制限。
4. API変更通知方法。
5. SLA。
6. token要否と正式な認証header（現状は公開JSONとして取得できるが保証ではない）。

kill switchを有効化するのは上記が揃ってから。

## Collector（GitHub Actions CLI）

収集は **GitHub Actions 上の Node CLI** が行う。Next.js のリクエスト処理中に YShelper へアクセスしない。

```text
YShelper
  → Actions: npm run yshelper:collect
  → validate / Prisma
  → Neon
  → Next.js 公開 API（読み取りのみ）
  → Flutter
```

- Workflow: `.github/workflows/yshelper-battle-statistics.yml`（`workflow_dispatch` のみ。schedule はコメントアウト）
- CLI: `npm run yshelper:collect`（[`scripts/yshelper-collect.mts`](../scripts/yshelper-collect.mts)）
- Kill switch がすべて false / 未設定なら Workflow は収集を skip して成功終了（既定安全）
- `POST /api/internal/yshelper/collect` は **410 Gone**（HTTP collect 廃止）
- 最終完全成功から14日未満なら`skipped / not_due`。process-local排他と DB `SyncLease` を併用
- abyss/stygian は個別に記録・検証し、valid な Snapshot だけ Manifest を更新する。片方の失敗で他方を壊さない

Actions secrets（例）: `YSHELPER_COLLECT_DATABASE_URL` / `YSHELPER_COLLECT_DIRECT_URL`、endpoint 系。Variables の kill switch は既定 false。secret・URL・本文をログへ出さない。

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

推奨（Flutter はこちらを使用）:

- `GET /api/v1/battle-statistics/manifest`: ETag、`If-None-Match`、304
- `GET /api/v1/battle-statistics/bundle?type=abyss&revision=...&page=...`: 500件単位
- `GET /api/v1/battle-statistics/teams`: cursor、limit最大100
- `GET /api/v1/battle-statistics/characters`: cursor、limit最大100

互換のため `/api/battle-statistics/*`（v1 なし）も同一実装を公開する。

Flutterは起動を待たせずManifestを確認する。同一ETagなら終了し、変更された種類だけ全ページを取得する。schema、hash、Character ID、重複を確認後、Drift transactionでManifestとデータを切り替える。失敗・offline・timeout時は旧revisionを維持する。閲覧UIは「編成使用率統計」（AZA「深境螺旋統計」とは別）。

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
