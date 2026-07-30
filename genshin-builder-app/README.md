# Genshin Builder Web / API

Next.js 16（App Router）、TypeScript、Prisma で構成する Genshin Builder の Web・API・管理サービスです。

## 主な責務

- Project Amber のゲームマスター同期と Prisma への保存
- 匿名ユーザーの育成状況、編成、素材計画
- AZA.GG の深境螺旋統計を安全な内部 DTO へ正規化・キャッシュ
- AZA.GG / ルールベースの編成推薦
- 承認済み YouTube 映像証拠から作る育成おすすめ
- `/admin/guides` の構造化編集、検証、承認、公開、revision 復元
- Flutter 向け公開 API

モノレポ全体のセットアップ、Flutter、検証、トラブルシューティングは [ルート README](../README.md) を先に参照してください。

## ローカル起動

必要環境は Node.js 24 と npm、および **PostgreSQL** です（SQLite は開発対象外）。

```powershell
Copy-Item .env.example .env
# DATABASE_URL / DIRECT_URL をローカル Postgres に合わせて編集
npm ci
npx prisma generate
npx prisma migrate deploy
npm run dev
```

PostgreSQL 運用の詳細は [docs/POSTGRES_MIGRATION.md](../docs/POSTGRES_MIGRATION.md)、staging は [docs/STAGING_SETUP.md](../docs/STAGING_SETUP.md) を参照してください。

`http://localhost:3000` を開きます。初回のゲームマスター同期は「設定」画面または認証済み `POST /api/sync` から実行します。

PostgreSQL への接続確認と migration 適用:

```powershell
npx prisma validate
npx prisma migrate status
npx prisma migrate deploy
```

`migrate dev` はローカルで新しい migration を作る場合だけ使います。本番 DB の migration や公開は、このリポジトリの通常検証では実行しません。

## 環境変数

正本は [`.env.example`](.env.example) です。

- `DATABASE_URL` — Prisma 接続先（PostgreSQL）
- `DIRECT_URL` — Migrate 用 direct 接続（ローカルでは `DATABASE_URL` と同じで可）
- `SYNC_API_SECRET` — `/api/sync` の Bearer secret
- `BUILD_GUIDE_ADMIN_SECRET` — Build Guide 管理 API。未設定は 503
- `TEAM_TEMPLATE_ADMIN_SECRET` — 編成テンプレート管理 API
- `AZA_*` — 統計 upstream、TTL、kill switch
- `TEAM_RECOMMENDATION_*` — 編成推薦（候補数・Job TTL・スコア重み）
- `YOUTUBE_*` / `GEMINI_*` / `DEEPSEEK_GUIDE_*` — 動画メタデータ・映像解析・証拠統合。既定無効

secret はクライアント bundle、公開 API、ログ、URL、ドキュメントへ含めないでください。

## 管理画面と公開 API

- 管理画面: `http://localhost:3000/admin/guides`
- 管理 API: `/api/admin/build-guides`（Bearer 認証、サイズ上限、レート制限、fail-closed）
- 公開おすすめ: `GET /api/build-recommendations/{characterId}`
- 出典: `GET /api/build-recommendations/{characterId}/sources`
- 深境螺旋統計: `GET /api/abyss/statistics`

公開おすすめは内容指紋ベースの ETag と 304 に対応します。`adminWorkingDraft`、管理者メモ、revision、pending mention、内部レビュー状態は公開 DTO に含めません。詳細は [`docs/BUILD_GUIDE_RECOMMENDATIONS.md`](docs/BUILD_GUIDE_RECOMMENDATIONS.md) を参照してください。

## 検証

```powershell
npm run typecheck
npm run lint
npm test
npm run build
```

Vitest は正規化、同期、認証、公開情報漏えい、ETag、楽観ロック、Build Guide、編成推薦、ドメイン計算を含みます。DB integration test は明示的なテスト用 DB 設定がある場合だけ実行されます。

## データフロー

```text
外部 API
  -> src/lib/api（取得・タイムアウト・検証・正規化）
  -> src/lib/sync / service（整合性とキャッシュ）
  -> Prisma（PostgreSQL）
  -> App Router / 公開 API
  -> Flutter
```

Build Guide は次の境界を追加します。

```text
許可済み YouTube metadata
  -> Gemini による映像証拠候補
  -> 通常コードによる ID・時刻・数値検証
  -> 管理者の採用・構造化・承認
  -> 公開時のサーバー再検証
  -> 公開 DTO
```

映像内の mention は `pendingMentions` に留め、管理者が確認するまで正式なおすすめへ昇格しません。公開中の編集は `adminWorkingDraft` に分離し、承認・公開に失敗しても旧公開スナップショットを維持します。

## 開発資料

| ファイル | 内容 |
|---|---|
| [`AGENTS.md`](AGENTS.md) | 作業開始時の必須ルール |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Web の境界とデータフロー |
| [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) | 実装規約と検証 |
| [`AI_AGENT_RULES.md`](AI_AGENT_RULES.md) | 変更時の安全ルール |
| [`docs/BUILD_GUIDE_RECOMMENDATIONS.md`](docs/BUILD_GUIDE_RECOMMENDATIONS.md) | 構造化攻略情報の公開フロー |
| [`docs/AZA_ABYSS_OPERATIONS.md`](docs/AZA_ABYSS_OPERATIONS.md) | AZA.GG の運用・障害対応 |

## Windows で Prisma がロックされる場合

`npm ci` や `prisma generate` が `EPERM`、`query_engine-windows.dll.node`、`lightningcss` などのロックで失敗した場合は、このプロジェクトの `next dev` / Node プロセスだけを終了して再実行します。実行中プロセスのコマンドラインと作業ディレクトリを確認し、無関係な Node プロセスを一括終了しないでください。
