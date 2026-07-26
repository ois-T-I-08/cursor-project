# GitHub PR / Issue 整理（判断記録）

**この文書は判断結果のみ。Close / Merge は所有者が実行する。**  
調査日: 2026-07-26。ブランチ作業は `feature/neon-yshelper-battle-statistics`（PR #16）上。

## Draft / Open PR

| PR | 判定 | メモ |
|----|------|------|
| **#16** | **継続・機能凍結** | Neon + YShelper + Actions CLI 収集。Draft のまま。外部許可まで merge しない。**新規機能追加は禁止**（バグ修正・検証・ドキュメントのみ可）。規模: ~134 files / ~11k additions |
| **#17** | **継続** | team-rec / JP UI。#16 と独立。先に review しやすい。追加機能は #16 ではなくこちらまたは新規 PR へ |
| **#1** | **close可能** | 108 behind。実質 root `AGENTS.md` のみ。mobile に既存 AGENTS |
| **#4** | **rebaseが必要** | CONFLICTING。daily completion 等が main 未着 |
| **#5** | **rebase / 分割が必要** | #4 スタック。#14 と一部重複の可能性 |
| **#6** | **rebase 後 close可能** | hardening を main 向け新 PR へ抽出推奨 |
| #13–#15 | **mainへ統合済み** | 参照のみ |

推奨マージ順: #17（任意）→ #16（外部ゲートクリア後）→ Issue トラック（Node / HoYoLAB / LICENSE / ADR / format）。

## PR #16 機能凍結（2026-07-26）

レビュー不能を避けるため、PR #16 への**新規機能追加は停止**する。

| 許可 | 禁止 |
|------|------|
| バグ修正 | 新機能・新画面・新 API |
| 検証（テスト補強含む） | スコープ拡大のリファクタ |
| ドキュメント更新 | #16 への無関係な作業の混入 |

追加機能は PR #17 または新規 PR で扱う。

## Issues

| Issue | 状態 | 完了条件の更新案 |
|-------|------|------------------|
| **#7 LICENSE** | not started → **草案あり** | [`docs/LICENSE_DRAFT.md`](LICENSE_DRAFT.md)。著作権者名は所有者確定待ち。ルート `LICENSE` 未作成 |
| **#8 Privacy/Terms** | **partial** | サイト・設定リンク済。残り: 初回同意/改定、Play Data Safety、運営者情報 |
| **#9 HoYoLAB streaming** | **implemented on #16 branch** | `HoyolabHttpGuard.readBoundedResponse` + API `send` 経路。CI 緑確認後 Issue を更新可 |
| **#10 Node pin** | **partial on #16 branch** | ルート `.nvmrc` / `.node-version` = 20、`package.json#engines`。README 追随は任意 |
| **#11 SQLCipher** | **ADR proposed** | [`genshin-builder-mobile/docs/adr/0001-sqlcipher-strategy.md`](../genshin-builder-mobile/docs/adr/0001-sqlcipher-strategy.md)。破壊的移行なし |
| **#12 Dart format** | **方針ドキュメント** | [`docs/DART_FORMAT_BASELINE.md`](DART_FORMAT_BASELINE.md)。format-only PR は未実施 |

## 外部ゲート（YShelper 本番有効化）

- 利用許可（書面）
- 保存・加工・再配布可否
- 正式レート制限 / 推奨間隔
- API 変更通知
- SLA（または保証なしの明示）

Kill switch と schedule は無効のまま。
