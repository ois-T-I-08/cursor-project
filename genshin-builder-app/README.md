# Genshin Builder

原神のキャラクター育成状況を管理するWebアプリです。

## 技術スタック

- **Next.js**（App Router）
- **TypeScript**
- **Tailwind CSS**
- PostgreSQL（予定 / 開発初期はSQLite）
- Vercelでデプロイ予定

## 開発の始め方

```bash
npm install
cp .env.example .env      # DATABASE_URL を設定（開発はSQLite）
npx prisma migrate dev    # DB作成・マイグレーション
npm run dev
```

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
データベース（Prisma / SQLite → 本番はPostgreSQL）
    ↓ lib/repository（DB読み取り・空ならダミーへフォールバック）
ブラウザ（Server Componentで表示）
```

- APIが利用できなくてもDB内のデータでアプリは動作し続ける
- プロバイダー変更時は `lib/api/` の実装を差し替えるだけでよい
- 同期履歴は `SyncLog` テーブルに記録（将来のCron自動実行を想定）

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

## 今後追加予定

樹脂タイマー / 素材自動計算 / 曜日別素材表示 / 聖遺物管理 / チーム編成 / ガチャ履歴 / デイリー・週ボス管理 / Enka.Network連携 / PWA対応 / 通知機能
