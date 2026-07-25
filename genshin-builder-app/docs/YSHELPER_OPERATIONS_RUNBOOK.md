# YShelper 編成統計 運用 Runbook

関連: [YSHELPER_BATTLE_STATISTICS.md](./YSHELPER_BATTLE_STATISTICS.md)（技術境界・API・Migration）
将来機能候補: [YSHELPER_BACKLOG.md](./YSHELPER_BACKLOG.md)

この文書は**運用手順**のみを扱う。PR #16 時点では kill switch は既定 `false` のまま。外部利用条件が書面で確認されるまで、本番収集・cron・kill switch 有効化は行わない。

---

## 前提

| 項目 | 状態 / 方針 |
|------|-------------|
| 外部利用条件 | 書面確認が完了するまで有効化しない |
| kill switch | `YSHELPER_ABYSS_ENABLED` / `YSHELPER_STYGIAN_ENABLED` は明示 `true` のみ有効。既定・未設定は無効 |
| Adapter | 生JSONは `YSHELPER_ADAPTER_MODE=native-v1` |
| Stygian | 難度6のみ（`star=only_nandu6`）。全難易度は本PR範囲外 |
| 生レスポンス | ファイル・DB・コミットに保存しない |
| 秘密情報 | DB URL、token、Cookie、Authorization、完全URL、レスポンス本文をログ・Issue・PRに出さない |
| 環境区別 | **開発**（dry-run / Neon dev）→ **ステージング**（一度だけ有効化検証）→ **本番**（別作業・明示承認後） |

### 使用 endpoint（技術確認済み）

| contentType | path + fixed query |
|-------------|--------------------|
| `abyss` | `/ys/getAbyssRank.php?star=all&role=all&lang=en` |
| `stygian` | `/ys/getAbyssRank2.php?star=only_nandu6&role=all&lang=en` |

Base origin 例: `https://api.yshelper.com`（HTTPS 固定。redirect は拒否）。

---

## 有効化前チェック

すべて満たしてからステージング有効化を検討する。

1. PR #16（または後継）がレビュー・merge済み
2. 利用許可が書面で確認済み
3. 保存・加工・再配布の可否が確認済み
4. 正式レート制限・推奨取得間隔が確認済み
5. API変更通知手段と SLA（または「保証なし」の明示）が確認済み
6. 開発用 dry-run成功: `npm run yshelper:dry-run` / `npm run yshelper:dry-run:db`
7. Character ID 欠損 0（開発 Neon 照合）
8. Character map check 成功: `npm run yshelper:check-character-map`
9. `npm test` / `npm run typecheck` / `npm run lint` / `npm run build` 成功
10. kill switch が意図どおり（ステージング以外は `false` / 未設定）
11. endpoint・timeout（`YSHELPER_REQUEST_TIMEOUT_MS`）・max bytes（`YSHELPER_MAX_RESPONSE_BYTES`）が確認済み設定と一致
12. rollback 担当者と判断基準（下記）が合意済み

---

## ステージング有効化手順（手順のみ・ここでは実行しない）

本番ではなくステージングで、**1 content type ずつ**一度だけ有効化する想定。

### 変更してよい環境変数（ステージングのみ）

- `YSHELPER_API_BASE_URL`
- `YSHELPER_ABYSS_ENDPOINT` / `YSHELPER_STYGIAN_ENDPOINT`
- `YSHELPER_ADAPTER_MODE=native-v1`
- `YSHELPER_COLLECT_SECRET`（ステージング専用値）
- 必要なら `YSHELPER_API_TOKEN`（要否未確認。ログへ出さない）
- `YSHELPER_SYNC_INTERVAL_DAYS`（既定14）
- `YSHELPER_REQUEST_TIMEOUT_MS` / `YSHELPER_MAX_RESPONSE_BYTES`
- **片方だけ** `YSHELPER_ABYSS_ENABLED=true` または `YSHELPER_STYGIAN_ENABLED=true`

### 変更しない値

- 本番 Neon の URL / secret
- 本番 kill switch
- GitHub Actions cron（`workflow_dispatch` のみ維持）
- Flutter 公開契約
- Character map を「推測」で手編集しない（下記 map 更新手順）

### 手順

1. 上記チェックリスト完了を確認
2. abyss だけ `true` にし、stygian は `false` のまま
3. `POST /api/internal/yshelper/collect` を1回（Actions `workflow_dispatch` 推奨）。secret をログに残さない
4. Snapshot: validationState、recordCount、payloadHash、unresolved 関連 issue を確認（本文は見ない）
5. Manifest: contentType / revision / seasonId / payloadHash
6. 公開 API: manifest ETag、bundle、teams/characters。metadata・生データが無いこと
7. Flutter: 304 / revision 更新 / offline 維持
8. 同じ入力で再実行し `duplicate` / 不要な公開更新が無いこと
9. 問題なければ stygian だけ同様に有効化し、abyss を一旦 `false` に戻すか、両方 `true` にする方針を決めてから実行
10. 不審なら即時停止（次節）

---

## 停止・ロールバック

1. `YSHELPER_ABYSS_ENABLED=false` と `YSHELPER_STYGIAN_ENABLED=false`（または削除）
2. cron / scheduler を起動しない。`workflow_dispatch` も止める
3. 最後の正常 Manifest を維持する（無効な Snapshot を公開しない）
4. 必要なら Manifest の `publishedSnapshotId` を以前の正常 Snapshot へ戻す（DB 破壊 reset・Migration 巻き戻しはしない）
5. 秘密情報漏えいが疑われる場合のみ `YSHELPER_COLLECT_SECRET` / token をローテーション
6. upstream 停止時: kill switch を false のまま公開キャッシュを維持し、Issue で監視

禁止: `migrate reset`、本番 Migration の巻き戻し、PostgreSQL テーブルの即時 DROP、生レスポンスの保存。

---

## Character ID map 更新

英語名 → 公開 Character.id の静的 map。

```bash
cd genshin-builder-app
npm run yshelper:check-character-map   # 差分があれば非0。ファイルは書き換えない
npm run yshelper:generate-character-map # Amber EN から再生成（件数急減は失敗）
```

### 必須ルール

- Traveler は map しない（native adapter が fail-closed）
- `Ambor` は Amber と同じ ID を明示 alias
- 件数は最低 `CHARACTER_ID_MAP_MIN_COUNT`（80）。既存の 80% 未満へ減る更新は拒否
- map 更新後は必ず `npm run yshelper:dry-run:db` で開発 Neon の Character ID 照合（欠損0・書き込み0）
- 未知キャラクター: adapter が `$.result[0].unresolvedCharacter` で失敗。Collector の `errorCode` は `invalid_response:$.result[0].unresolvedCharacter`（ename 本文はログしない）

シェルに古い `DATABASE_URL=localhost` が残っていると Neon 照合が壊れる。照合前にクリアする。

---

## 障害調査（安全に確認できる項目）

| 確認してよい | 記録禁止 |
|--------------|----------|
| 最終成功日時、content type | 完全URL / query token |
| HTTP status 分類、timeout、size超過 | response body |
| parse / schema field（ポインタのみ） | DB URL / password |
| validation state、issue code | headers / cookies |
| snapshot / manifest hash、record count | Authorization |
| unresolved count（件数）、Prisma error code | 個人情報・UID |
| DB 接続成否（host kind 程度） | 生YShelper JSON |

---

## アラート候補（未実装でも監視設計として推奨）

- 連続失敗回数、最終成功時刻、24時間以上更新なし
- HTTP 429、timeout 増加、response size 増加
- invalid / suspicious、record count 急減、sampleSize 急減
- unknown character / ratio、Character ID 欠損
- seasonId 巻き戻り疑い

## インシデント分類

| 等級 | 例 | 初動 |
|------|----|------|
| P1 | 不正データ公開、秘密情報漏えい | 即 kill switch false、必要なら secret ローテーション |
| P2 | 全 content type 停止、公開データ消失 | 収集停止、最後の正常 Manifest 維持、原因切り分け |
| P3 | 片方の content type 更新停止 | 失敗側だけ無効化、他方は維持 |
| P4 | upstream schema 変化で fail-closed | 公開維持、map/adapter 調査（許可後） |

---

## 開発用検証コマンド（秘密を表示しない）

```powershell
cd genshin-builder-app
npm test
npm run typecheck
npm run lint
npm run build
npm run yshelper:check-character-map
# DATABASE_URL の localhost 残りに注意したうえで:
npm run yshelper:dry-run:db
```
