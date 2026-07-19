# Architecture — Genshin Builder

## プロジェクト概要

**Genshin Builder** は原神のキャラクター育成状況（レベル・武器・聖遺物・天賦・凸）を管理する Web アプリです。

- **Ver.1:** ログインなし。ブラウザ cookie の匿名 ID で育成データを紐づけ
- **マスタデータ:** 外部 API から同期し DB に永続化（オフライン耐性）
- **表示用リッチデータ:** スキル説明・ステータス計算等は表示時に API 取得（キャッシュ付き）

---

## 技術スタック

| 層 | 技術 |
|----|------|
| Framework | Next.js 16.2（App Router, Turbopack） |
| UI | React 19, Tailwind CSS v4 |
| Language | TypeScript 5（strict） |
| ORM | Prisma 6 |
| DB（開発） | SQLite（`prisma/dev.db`） |
| DB（本番予定） | PostgreSQL |
| 外部 API | Project Amber — `https://gi.yatta.moe`、AZA.GG（深境螺旋統計） |
| デプロイ（予定） | Vercel |

---

## システム構成図

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                               │
│  Client Components: DetailEditor, CharacterList, SyncButton  │
└───────────────────────────┬─────────────────────────────────┘
                            │ Server Actions / fetch / RSC props
┌───────────────────────────▼─────────────────────────────────┐
│                   Next.js Server                               │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ app/pages   │  │ api/routes   │  │ lib/actions         │ │
│  │ (RSC)       │  │ sync, weapons│  │ progress (write)    │ │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬──────────┘ │
│         │                 │                      │            │
│  ┌──────▼─────────────────▼──────────────────────▼──────────┐ │
│  │ lib/repository (read)    lib/sync* (master write)        │ │
│  └──────┬───────────────────────────────┬───────────────────┘ │
│         │                               │                     │
│  ┌──────▼──────┐                 ┌──────▼──────┐              │
│  │ Prisma/SQLite│                 │ lib/api     │              │
│  │ Master+User  │                 │ fetch+norm  │              │
│  └──────────────┘                 └──────┬──────┘              │
└──────────────────────────────────────────┼──────────────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │ Project Amber API       │
                              │ gi.yatta.moe            │
                              └─────────────────────────┘
```

---

## レイヤー責務

### `src/app/` — ルーティング・ページ

- **Server Component がデフォルト。** データ取得はここで完結させ、Client に props 渡し
- `dynamic = "force-dynamic"` は同期直後の件数反映等、必要なページのみ

### `src/components/` — UI

| ディレクトリ | 責務 |
|-------------|------|
| `layout/` | Header（Client）, Footer（Server） |
| `character/` | 一覧・カード・詳細エディタ |
| `character/detail/` | 育成入力 UI（Client 中心） |
| `settings/` | 同期 UI・案内 |
| `bookmark/` | 素材ブックマーク UI（個別・範囲・サイドバー） |
| `home/` | ホーム（ブックマーク合算表示） |
| `providers/` | `BookmarkProvider`（Context ラッパー） |
| `ui/` | 汎用 UI（Slider, Accordion） |

### `src/contexts/` — クライアント状態

| ファイル | 責務 |
|----------|------|
| `MaterialBookmarkContext.tsx` | ブックマークの localStorage 永続化・合算 |

### `src/lib/` — ブックマーク・素材計算（追加）

| ファイル | 内容 |
|----------|------|
| `bookmark-storage.ts` | localStorage CRUD・materialId 合算 |
| `bookmark-utils.ts` | sourceKey 生成・エントリ構築・`formatMora` |
| `material-requirements.ts` | 範囲合算・次段階素材（`RequirementLine`） |

**永続化の分離**: 育成進捗は cookie 匿名 ID → Prisma `UserProgress`。ブックマークは **localStorage**（`gb_material_bookmarks`）でブラウザ単位に保持。

### `src/lib/api/` — 外部 API 層

| ファイル | 責務 |
|----------|------|
| `index.ts` | 使用中プロバイダーの export |
| `types.ts` | `GameDataProvider` インターフェース |
| `project-amber.ts` | リスト取得（キャラ・武器・素材） |
| `amber-details.ts` | 表示用 detail（スキル・凸・武器性能・聖遺物セット） |
| `amber-upgrade.ts` | 同期用 detail（突破・天賦・EXP 素材） |
| `merge-promotes.ts` | DB 突破 + API addProps のマージ |
| `genshin-jmp-blue.ts` | レガシー（未使用） |
| `abyss/provider.ts` | `AbyssStatisticsProvider` 交換契約 |
| `abyss/aza-provider.ts` | AZA.GG 公開 KV API の HTTPS 取得、上限・timeout・再試行・エラー分類 |
| `abyss/normalize-aza.ts` | AZA 固有 JSON の検証と内部 DTO への正規化 |

**Prisma 禁止。UI から直接 import しない（pages/actions/sync 経由）。**

### `src/lib/repository/` — DB 読み取り

- UI・Server Component 向けのクエリ
- DB 空時は `dummy-data.ts` にフォールバック（キャラのみ）
- **書き込み禁止**

### `src/lib/sync.ts` + `sync-upgrade.ts` — マスタ書き込み

- `syncMasterData()`: リスト upsert + 差分/完全突破同期
- `syncUpgradeData()`: 突破・天賦・EXP 表・経験値素材
- 結果を `SyncLog` に記録

### `src/lib/actions/` — ユーザー書き込み

- `saveProgress` / `deleteProgress`（Server Actions）
- 入力 sanitize・cookie 発行・`revalidatePath`

### `src/lib/` ドメインロジック（純関数）

| ファイル | 内容 |
|----------|------|
| `level-progression.ts` | レベル目盛り・突破・必要素材計算 |
| `talent-progression.ts` | 天賦レベル素材 |
| `weapon-exp.ts` | 武器 EXP・魔鉱（フォールバック定数） |
| `artifact-score.ts` | 聖遺物スコア |
| `stats.ts` | ステータス計算 |
| `level-config.ts` | 目盛り・定数（将来 DB 化の境界） |
| `material-requirements.ts` | 範囲・次段階の素材合算 |
| `bookmark-storage.ts` | ブックマーク localStorage |
| `bookmark-utils.ts` | sourceKey / エントリ生成 |

---

## データモデル（Prisma）

### マスタ（同期で更新）

| Model | 内容 |
|-------|------|
| `Character` | 基本情報（元素・武器種・レアリティ・アイコン） |
| `Weapon` | 武器基本情報 |
| `Material` | 素材（`expValue`/`expTarget` は EXP 素材のみ） |
| `CharacterUpgrade` | 突破 JSON + 天賦強化 JSON |
| `WeaponUpgrade` | 突破 JSON + 魔鉱 ID リスト |
| `LevelExpSegment` | 目盛り間 EXP（API 未提供のため同期時に定数投入） |

### ユーザー

| Model | 内容 |
|-------|------|
| `UserProgress` | 匿名 userId × characterId で一意。artifacts は JSON 文字列 |

### 運用

| Model | 内容 |
|-------|------|
| `SyncLog` | 同期結果 JSON |
| `ExternalApiCache` | 外部統計の最終成功スナップショット、取得時刻、失効時刻、版、サンプル数 |

---

## データフロー

### 1. マスタ同期

```
[設定] SyncButton
  → POST /api/sync { fullUpgrade: boolean }
  → syncMasterData()
      → project-amber: 3 list API
      → prisma upsert Character/Weapon/Material
      → syncUpgradeData()
          → 差分: 未登録の CharacterUpgrade/WeaponUpgrade のみ detail API
          → 完全: 全件 detail API（数百回）
  → SyncLog
```

**API 呼び出し目安**

| モード | 回数 |
|--------|------|
| 通常同期（2回目以降・データ揃い） | 約 3 回 |
| 通常同期（初回・不足あり） | 3 + 不足分 |
| 完全同期 | 3 + 全キャラ + 全武器 + α |

### 2. キャラ詳細表示

```
GET /characters/[id] (RSC)
  → repository: character, progress, weapons, materials, upgrade-data
  → amber-details: avatarDetail（スキル・凸・stats）, artifactSets
  → fetchWeaponDetail + mergePromotes（装備武器あり）
  → DetailEditor (Client) props
```

**突破・天賦の必要素材:** DB の `CharacterUpgrade`（同期済み）  
**スキル説明文・ステータス:** 表示時 API（24h キャッシュ）

### 3. 育成保存

```
DetailEditor state change
  → debounce 800ms
  → saveProgress (Server Action)
  → prisma UserProgress upsert
  → revalidatePath
```

### 4. 武器切り替え（Client）

```
DetailEditor → fetch /api/weapons/[id]
  → fetchWeaponDetail + getWeaponUpgrade (DB promotes 優先)
  → WeaponSection 更新
```

### 5. 深境螺旋統計（Flutter 向け）

```
Flutter → GET /api/abyss/statistics
  → AbyssStatisticsService
      → fresh ExternalApiCache があれば即返却
      → miss / expired は AzaAbyssStatisticsProvider（同一プロセス内は single-flight）
          → GET https://c1-api.aza.gg/kv/read?key_id=genshin_abyss_statistics
          → normalizeAzaAbyssStatistics（型・範囲・配列上限を検証）
          → 成功時だけ ExternalApiCache を更新
      → upstream 失敗か kill switch 時は最終成功値を stale として返却
```

責務境界:

- `AbyssStatisticsProvider` は AZA 固有の取得・正規化を担当し、別提供元へ交換できる
- `AbyssStatisticsService` は TTL、process-local single-flight、stale fallback、kill switch、構造化ログを担当する。Promise の共有範囲は同一 Node.js プロセスだけで、複数インスタンス間の排他は行わない
- Route Handler は安全なエラー code と内部 DTO だけを Flutter へ返し、upstream 本文・URL・内部例外を露出しない
- API の `meta.api_ver` は **AZA API 仕様版** として保持する。既知版は `5.6`。未知版でも現行スキーマに適合すれば warning を記録して継続し、不適合なら `invalidResponse` とする。ゲームバージョンや upstream にない編成使用回数は補完しない

---

## API 利用マップ

| エンドポイント | 用途 | キャッシュ |
|----------------|------|------------|
| `/api/v2/jp/avatar` | キャラ一覧 | 1h |
| `/api/v2/jp/weapon` | 武器一覧 | 1h |
| `/api/v2/jp/material` | 素材一覧 | 1h |
| `/api/v2/jp/avatar/{id}` | 詳細・同期 | 24h |
| `/api/v2/jp/weapon/{id}` | 詳細・同期 | 24h |
| `/api/v2/jp/material/{id}` | EXP 素材 | 24h |
| `/api/v2/static/avatarCurve` | ステ計算 | 24h + React cache |
| `/api/v2/static/weaponCurve` | 武器ステ | 24h + React cache |
| `/api/v2/jp/reliquary` | 聖遺物セット | 24h + React cache |
| `GET /api/abyss/statistics` | Flutter 向け深境螺旋統計 DTO | DB 6h TTL + stale fallback |

---

## Server / Client 境界

```
Server Component (page)
  ├─ データ fetch（repository + amber-details）
  └─ Client Component
       ├─ useState / useEffect
       ├─ Server Actions (saveProgress)
       └─ Route Handler fetch (/api/weapons/[id])
```

**ルール:** 状態・イベント・デバウンス = Client。DB・外部 API の初回取得 = Server。

---

## エラー処理方針

| 層 | 方針 |
|----|------|
| `lib/api/*` | try/catch → `null` or 空配列。console.error |
| `lib/api/abyss/*` | typed error code。本文・秘密・内部例外をログやレスポンスへ出さない |
| `repository/*` | try/catch → 空/ダミー。画面を落とさない |
| `sync*` | `Promise.allSettled` + errors 配列。部分成功を許容 |
| `actions/*` | `{ ok: boolean }` を返す |
| UI | null 時メッセージ + 設定への導線 |

---

## 今後追加予定（README / コードコメントより）

| 機能 | 備考 |
|------|------|
| 樹脂タイマー | 未実装 |
| 素材自動計算 | 部分実装（詳細画面の必要素材表示） |
| 曜日別素材表示 | 未実装 |
| 聖遺物管理強化 | 基本入力のみ |
| チーム編成 | 未実装 |
| ガチャ履歴 | 未実装 |
| デイリー・週ボス管理 | 未実装 |
| Enka.Network 連携 | 未実装 |
| PWA / 通知 | 未実装 |
| Google ログイン | `user.ts` / settings に言及 |
| 育成データ export/import | settings に placeholder |
| Lv.90–100 / 天賦 Lv.11–13 | UI 余白のみ。`level-config.ts` |
| Vercel Cron 自動同期 | `sync/route.ts` コメント |
| PostgreSQL 本番 DB | schema コメント |
| `/api/sync` 認証 | 本番必須 |

**新機能追加時:** 上記リストと競合しないか、どのレイヤーに置くかを ARCHITECTURE に沿って決める。

---

## 変更時の影響分析テンプレート

AI / 開発者は非 trivial な変更前に以下を記載すること。

1. **目的** — 何を達成するか
2. **触るレイヤー** — api / sync / repository / actions / UI
3. **DB** — マイグレーション要否
4. **API** — 新規呼び出し回数・同期への影響
5. **Server/Client** — 境界変更の有無
6. **後方互換** — 既存育成データ・同期データへの影響
7. **確認手順** — build / 同期 / 詳細画面

---

関連: `AI_AGENT_RULES.md`, `DEVELOPMENT_GUIDE.md`, `README.md`
