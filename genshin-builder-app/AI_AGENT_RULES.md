# AI Agent Rules — Genshin Builder

> **AIエージェントはコード変更前に、必ず本ファイル・`ARCHITECTURE.md`・`DEVELOPMENT_GUIDE.md`・`docs/AGENT_MEMORY.md`（最新エントリ）を読むこと。**

本プロジェクトは Next.js 16 App Router + Prisma + 外部ゲームデータ API で構成される育成管理アプリです。
変更は「最小差分」「既存設計の尊重」「影響範囲の明示」を最優先してください。

---

## 1. 変更前の必須手順

コードを書く・直す・リファクタする前に、**必ず**以下を実行すること。

1. **関連ドキュメントを読む**
   - 本ファイル（`AI_AGENT_RULES.md`）
   - `docs/AGENT_MEMORY.md`（**最新エントリ** — セッション間の決定事項・未完了）
   - `ARCHITECTURE.md`（レイヤー・データフロー）
   - `DEVELOPMENT_GUIDE.md`（命名・実装規約）
   - `AGENTS.md`（Next.js 16 固有の注意。`node_modules/next/dist/docs/` も参照）
2. **既存実装を確認する**
   - 同種の機能が `src/lib/` または `src/components/` に既にないか検索する
   - 似た処理は**新規実装せず拡張**する
3. **影響範囲をユーザーに説明する**
   - 変更するファイル一覧
   - 触るレイヤー（api / sync / repository / actions / UI）
   - DB マイグレーションの要否
   - 外部 API 呼び出し回数への影響
4. **承認を得てから大きな変更に入る**
   - 3ファイル以上の横断変更
   - スキーマ変更
   - 同期ロジックの変更
   - 既存 UI の大幅な組み替え

---

## 2. 設計思想（変更してはいけない前提）

| 原則 | 内容 |
|------|------|
| **DB First for Master Data** | キャラ・武器・素材・突破コストは同期で DB に保存し、UI は repository 経由で読む |
| **On-demand for Display Rich Data** | スキル説明・凸・武器効説・聖遺物セットは表示時 API 取得（24h キャッシュ） |
| **Provider 分離** | 外部 API は `lib/api/` に閉じ込め、`GameDataProvider` 経由で差し替え可能にする |
| **Read/Write 分離** | 読み取り=`repository/`、マスタ書き込み=`sync*`、ユーザー書き込み=`actions/` |
| **Graceful Degradation** | API/DB 失敗時も画面が壊れない（null 許容・ダミーデータ・メッセージ表示） |
| **Minimal Diff** | 依頼範囲外のリファクタ・命名変更・フォーマット変更を混ぜない |

---

## 3. レイヤー別の禁止事項

### やってはいけない

| 禁止 | 理由 |
|------|------|
| Client Component から Prisma / 外部 API を直接呼ぶ | 秘密情報・キャッシュ・負荷制御が効かない |
| `lib/repository/` から外部 API を呼ぶ | 責務違反。repository は DB 読み取り専用 |
| `lib/api/` から Prisma を触る | 責務違反。api は正規化と fetch のみ |
| ページごとに Amber API を detail 全件取得 | API 負荷爆増。同期 or 差分同期を使う |
| 同期のたびに全キャラ detail を再取得 | `sync-upgrade.ts` の差分同期を壊さない |
| `deleteMany({ notIn: [] })` | Prisma が例外。`idsForNotIn()` を使う |
| `prisma/dev.db` を commit | ローカル DB・秘密ではないが環境依存 |
| `.env` を commit | 禁止 |
| ユーザー依頼なしの git commit / force push | ユーザー rule 参照 |
| 依頼なしの README / ドキュメント大量追加 | スコープ外 |
| Server Action なしで Client から DB 書き込み | 現行設計は Server Actions のみ |

### 慎重に（事前説明必須）

- Prisma スキーマ変更（マイグレーション必須）
- `POST /api/sync` の認証・レート制限変更
- `GameDataProvider` の差し替え
- 匿名 cookie 認証方式の変更
- 同期 concurrency / delay の変更

---

## 4. 外部 API 利用ルール

- **使用プロバイダー:** Project Amber（`https://gi.yatta.moe`）のみ。`lib/api/index.ts` で選択。
- **リスト取得:** 同期時のみ（`/api/v2/jp/avatar`, `weapon`, `material`）。revalidate 1h。
- **Detail 取得:** 同期（差分/完全）または表示用（`amber-details.ts`）。revalidate 24h。
- **新規 API 呼び出しを追加する場合:**
  1. `lib/api/` に集約
  2. キャッシュ方針（`next.revalidate` or React `cache()`）を決める
  3. 同期に載せるか、表示時のみかを ARCHITECTURE に沿って決める
  4. 呼び出し回数見積もりを PR/説明に書く

---

## 5. 変更時の確認チェックリスト

変更完了前に確認すること。

- [ ] `npm run build` が通る
- [ ] Prisma 変更時は `npx prisma migrate dev` + `npx prisma generate`（dev サーバー停止）
- [ ] Server/Client の境界が崩れていない（`"use client"` の範囲は最小）
- [ ] 新規 props は Server → Client でシリアライズ可能
- [ ] 同期 UI の文言と `SyncSection` / `SyncButton` の挙動が一致
- [ ] 突破データ不足時の案内（設定へのリンク）が維持されている
- [ ] 依頼外ファイルを変更していない
- [ ] commit していない（ユーザーが明示した場合のみ）

---

## 6. テスト方針（現状）

- **自動テスト:** Vitest（`src/lib/__tests__/`）。`npm test` で実行する。
- **必須の確認:**
  - `npm run lint`
  - `npm test`
  - `npm run build`
- **主要な手動確認:**
  - 設定 → 通常同期
  - キャラ詳細 → レベル/武器/天賦スライダー → 素材表示
  - 武器切り替え → `/api/weapons/[id]` 経由で性能表示
- **テスト追加時:** ビジネスロジック、同期の認証・排他・失敗復旧、公開 API の入力境界を優先する。

---

## 7. セキュリティ注意（エージェント向け）

- `POST /api/sync` は `SYNC_API_SECRET` の Bearer 認証必須。本番で未設定なら fail closed とする。
- 同期はレート制限と分散リースで多重実行を防ぐ。認証・排他を迂回する経路を追加しない。
- ユーザー識別は `gb_user_id` cookie（httpOnly）。他ユーザーデータへのアクセス経路を作らない。
- `saveProgress` の入力は clamp / 長さ制限済み。新フィールド追加時も同様に sanitize する。
- API 説明文は `stripMarkup()` 済み。HTML 生挿入しない。
- 本番では cookie の `secure: true` を維持し、エラー応答・ログへ Cookie、トークン、DB 接続情報を出さない。

---

## 8. ドキュメント更新ルール

以下を変更した場合、**該当ドキュメントも更新**すること。

| 変更内容 | 更新先 |
|----------|--------|
| レイヤー・データフロー | `ARCHITECTURE.md` |
| 命名・開発手順 | `DEVELOPMENT_GUIDE.md` |
| AI 向け禁止事項 | 本ファイル |
| ユーザー向けセットアップ | `README.md` |

---

## 9. やってはいけない実装例

```typescript
// ❌ Client から Prisma
"use client";
import { prisma } from "@/lib/db";
await prisma.character.findMany();

// ❌ 同期なしで毎ページ全キャラ detail API
for (const c of characters) {
  await fetch(`https://gi.yatta.moe/api/v2/jp/avatar/${c.id}`);
}

// ❌ 空配列 notIn
await prisma.weapon.deleteMany({
  where: { id: { notIn: [] } },
});

// ❌ 依頼外の大規模リネーム
// CharacterCard → CharCard など全体置換

// ❌ repository から fetch
export async function getCharacter(id: string) {
  const live = await fetch("https://gi.yatta.moe/...");
}
```

```typescript
// ✅ 正しいパターン
// 読み取り
const character = await getCharacter(id); // repository
const upgrade = await getCharacterUpgrade(id); // repository

// 書き込み（ユーザー）
await saveProgress(characterId, payload); // Server Action

// 書き込み（マスタ）
await syncMasterData({ fullUpgrade: false }); // sync

// 表示用 API（サーバーのみ）
const detail = await fetchAvatarDetail(id); // amber-details
```

---

## 10. 関連ファイル索引

| 用途 | ファイル |
|------|----------|
| プロバイダー選択 | `src/lib/api/index.ts` |
| マスタ同期 | `src/lib/sync.ts`, `src/lib/sync-upgrade.ts` |
| 突破データ読取 | `src/lib/repository/upgrade-data.ts` |
| 育成保存 | `src/lib/actions/progress.ts` |
| 匿名ユーザー | `src/lib/user.ts` |
| 同期 UI | `src/components/settings/SyncSection.tsx` |
| 詳細エディタ | `src/components/character/detail/DetailEditor.tsx` |
| 素材ブックマーク | `src/contexts/MaterialBookmarkContext.tsx`, `src/lib/bookmark-storage.ts` |
| Agent セッションログ | `docs/AGENT_MEMORY.md` |
| DB スキーマ | `prisma/schema.prisma` |

---

**Remember:** 既存設計を確認 → 影響範囲を説明 → 最小差分で実装。
