# Genshin Builder

原神のキャラクター育成状況を管理するWebアプリです。

## 技術スタック

- **Next.js**（App Router）
- **TypeScript**
- **Tailwind CSS**
- Neon PostgreSQL（Prisma、pooled/direct接続を分離）
- Vercelでデプロイ予定

## 開発の始め方

```bash
npm install
cp .env.example .env.local
npx prisma generate
npx prisma migrate deploy # 空のdevelopment branchへ初期Migrationを適用
npm run dev
```

### Windows PowerShell の場合

```powershell
npm install
Copy-Item .env.example .env.local
npx prisma generate
npx prisma migrate deploy
npm run dev
```

### 環境変数

| 変数 | 必須 | 説明 |
|------|------|------|
| `DATABASE_URL` | はい | Neon pooled connection。Next.jsの通常実行用 |
| `DIRECT_URL` | はい | Neon direct connection。Prisma Migration用 |
| `SYNC_API_SECRET` | 本番のみ | `/api/sync` と設定画面の手動同期で共用する認証トークン。手動同期時は画面へ同じ値を入力 |
| `AZA_API_BASE_URL` | 統計機能のみ | AZA.GG 公開 API の HTTPS origin。既定例は `https://c1-api.aza.gg` |
| `AZA_ABYSS_ENABLED` | いいえ | `false` で深境螺旋統計の upstream 更新を停止する kill switch（キャッシュがあれば stale で返却） |
| `AZA_CACHE_TTL_SECONDS` | いいえ | 統計の DB キャッシュ TTL。300〜86400 秒、既定 21600 秒（6時間） |
| `AZA_REQUEST_TIMEOUT_MS` | いいえ | AZA.GG へのタイムアウト。1000〜30000 ms、既定 10000 ms |
| `YSHELPER_COLLECT_SECRET` | Collectorのみ | 手動GitHub Actionsから内部Collector APIを呼ぶBearer secret |
| `YSHELPER_ADAPTER_MODE` | YShelper有効化時 | 実fixture確認後のみ`canonical-v1`。未設定時は外部通信しない |

`DATABASE_URL` が未設定の状態で起動すると、Prisma Client の初期化時にエラーが表示されます。

http://localhost:3000 を開き、「設定」→「ゲームデータを同期」でマスターデータを取り込んでください。

## 現在の実装状況

- [x] プロジェクト構成・共通レイアウト（ヘッダー・フッター）
- [x] ホーム画面（最近編集したキャラクター・お知らせエリア）
- [x] キャラクター一覧（名前検索・元素・武器種・レアリティフィルター）
- [x] API接続（Project Amber / gi.yatta.moe → サーバー側で取得・日本語名対応）
- [x] マスターデータのDB保存・同期（`POST /api/sync`・設定画面の同期ボタン）
- [x] 育成状況の保存機能（匿名ユーザーID発行・Server ActionでDB保存・自動保存）
- [x] キャラクター詳細画面（アコーディオン形式）
  - レベル・突破段階
  - 武器（性能・精錬ランクごとの武器効果表示）
  - 聖遺物（セット効果・メイン/サブステータス・スコア計算）
  - 命ノ星座（凸効果一覧・解放状態の強調表示）
  - スキル・天賦（説明文・固有天賦一覧）

## データ取得の流れ

```
外部API（Project Amber / gi.yatta.moe）
    ↓ lib/api（プロバイダー分離・正規化）
Next.js サーバー（POST /api/sync）
    ↓ lib/sync（必要な項目だけ upsert）
データベース（Prisma / Neon PostgreSQL）
    ↓ lib/repository（DB読み取り・空ならダミーへフォールバック）
ブラウザ（Server Componentで表示）
```

- APIが利用できなくてもDB内のデータでアプリは動作し続ける
- プロバイダー変更時は `lib/api/` の実装を差し替えるだけでよい
- 同期履歴は `SyncLog` テーブルに記録（将来のCron自動実行を想定）

### 深境螺旋統計

```
AZA.GG 公開 API
    ↓ src/lib/api/abyss（取得・検証・内部 DTO へ正規化）
AbyssStatisticsService（6時間 TTL・process-local single-flight・最大1回再試行）
    ↓ 成功時に ExternalApiCache へ最終成功スナップショットを保存
GET /api/abyss/statistics（Flutter 向け安全な同一-origin DTO）
```

- Flutter は AZA.GG を直接呼ばず、この Next.js API だけを呼び出す
- 期限切れ後の upstream 障害時は、最終成功キャッシュを `isStale: true` で返す
- 現在確認できる公開 KV API は API キー不要。未確認の認証ヘッダーは送信しない
- 原神ゲームバージョンや編成使用回数は upstream に存在しないため生成しない
- migration、kill switch、stale fallback、staging 確認手順は [`docs/AZA_ABYSS_OPERATIONS.md`](./docs/AZA_ABYSS_OPERATIONS.md) を参照

### YShelper編成統計

GitHub Actionsは手動実行時だけ認証済み内部APIを起動し、定期取得は無効です。サーバーが前回成功から14日以上かを判定し、期限前は外部APIを呼びません。検証済みSnapshotだけがManifestから公開され、Flutterはrevision/hashが変わった種類だけを同期します。

YShelperの実エンドポイントと生レスポンス仕様はリポジトリ内で未確認です。利用許可と匿名化fixtureを確認するまではadapterを有効にせず、URLやフィールドを推測しません。Neon、Migration、Secrets、障害時、rollbackの手順は [`docs/YSHELPER_BATTLE_STATISTICS.md`](./docs/YSHELPER_BATTLE_STATISTICS.md) を参照してください。

## ディレクトリ構成

```
prisma/                   # DBスキーマ・マイグレーション
src/
├── app/                  # App Router のページ
│   ├── layout.tsx        # 共通レイアウト
│   ├── page.tsx          # ホーム
│   ├── api/sync/         # マスターデータ同期API
│   ├── characters/       # キャラクター一覧・詳細
│   └── settings/         # 設定（同期ボタン）
├── components/
│   ├── layout/           # ヘッダー・フッター
│   ├── character/        # キャラ関連UI
│   └── settings/         # 設定画面UI
├── lib/
│   ├── api/              # 外部API取得層（プロバイダー分離）
│   ├── repository/       # DB読み取り層
│   ├── db.ts             # Prisma Client
│   └── sync.ts           # マスターデータ同期処理
└── types/                # 型定義
```

## 設計方針

- Server Component と Client Component を使い分け（フィルター操作など状態を持つ部分のみ Client）
- 外部APIのレスポンスはそのまま使わず、正規化してからDBへ保存
- マスターデータ（キャラ・武器・素材）とユーザーの育成状況は別テーブルで管理
- Ver.1はログインなし。初回アクセス時に匿名IDを発行してデータを紐づける（今後実装）

## AI / 開発者向けドキュメント

| ファイル | 内容 |
|----------|------|
| [`AI_AGENT_RULES.md`](./AI_AGENT_RULES.md) | AI エージェント向けルール・禁止事項 |
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | アーキテクチャ・データフロー |
| [`DEVELOPMENT_GUIDE.md`](./DEVELOPMENT_GUIDE.md) | 開発ガイド・命名規則 |
| [`docs/AZA_ABYSS_OPERATIONS.md`](./docs/AZA_ABYSS_OPERATIONS.md) | AZA.GG 深境螺旋統計の運用・障害対応 |
| [`docs/YSHELPER_BATTLE_STATISTICS.md`](./docs/YSHELPER_BATTLE_STATISTICS.md) | Neon・YShelper統計同期・公開APIの運用 |
| [`AGENTS.md`](./AGENTS.md) | エントリポイント（Next.js 16 注意含む） |

## 今後追加予定

樹脂タイマー / 素材自動計算 / 曜日別素材表示 / 聖遺物管理 / チーム編成 / ガチャ履歴 / デイリー・週ボス管理 / Enka.Network連携 / PWA対応 / 通知機能
