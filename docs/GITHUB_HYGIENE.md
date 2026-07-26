# GitHub PR / Issue 整理（判断記録）

調査日: 2026-07-26（所有者確定判断反映）。  
Close / Merge は所有者が実行する（本ファイルは判断結果のみ）。

## 所有者確定判断（要約）

| 項目 | 決定 |
|------|------|
| LICENSE | MIT / `Copyright (c) 2026 ois-T-I-08`。第三者データは対象外 |
| SQLCipher | v1.0 は Option 1（平文 Drift + Secure Storage）。ADR Accepted |
| Play Data Safety | 収集あり（任意 User IDs）。広告・解析 SDK なし。詳細は `PLAY_DATA_SAFETY.md` |
| 同意 | 初回起動の全面同意はしない。HoYoLAB 連携直前に明示説明 |
| PR #16 | 機能凍結。本番 YShelper 収集は許可文書化まで無効 |

## Draft / Open PR

| PR | 判定 | メモ |
|----|------|------|
| **#16** | **継続・機能凍結** | Neon + YShelper 基盤。外部許可まで merge / 本番収集しない |
| **#17** | **Merged** | team-rec / 日本語 UI。完了 |
| **#1** | **Closed (Obsolete)** | 初期静的 Web 向け。既に Close 済み |
| **#4** | **salvage 後 Close** | 代替: [#20](https://github.com/ois-T-I-08/cursor-project/pull/20) lease / [#22](https://github.com/ois-T-I-08/cursor-project/pull/22) daily plan |
| **#5** | **salvage 後 Close** | 代替: [#23](https://github.com/ois-T-I-08/cursor-project/pull/23) domain。UI/calendar は別途 |
| **#6** | **salvage 後 Close** | 代替: [#21](https://github.com/ois-T-I-08/cursor-project/pull/21) remote JSON URL hardening |
| **#19** | **継続** | 所有者確定判断（LICENSE / SQLCipher / consent / Data Safety） |
| #13–#15 | **main 統合済み** | 参照のみ |

推奨順: #17 → #16（Draft 維持・外部ゲート）→ #4〜#6 salvage 新 PR → 旧 PR Close。

## Issues

| Issue | 状態 |
|-------|------|
| **#7 LICENSE** | ルート `LICENSE` 作成済み。Close は所有者確認後に可 |
| **#8 Privacy/Terms** | 文書草案 + HoYoLAB 開示実装。Play Console 入力は所有者作業 |
| **#11 SQLCipher** | ADR Accepted / Option 1。Close 可能と報告 |
| **#9 / #10 / #12** | 実装・方針ドキュメントあり。個別 Close は検証後 |
