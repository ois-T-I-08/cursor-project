# YShelper / battle statistics backlog（PR #16 外）

PR #16（Neon + YShelper `native-v1` 基盤）には**実装しない**将来項目。
外部利用条件が未確認の項目は blocked。

| ID | 題名 | Acceptance criteria（要約） | 状態 |
|----|------|------------------------------|------|
| B1 | Support partial Spiral Abyss teams | 1〜3人編成の公開契約・正規化・Flutter表示方針を定義し、4人のみ方針からの移行計画があること。PR #16 の除外ロジックを壊さないこと | open / not in #16 |
| B2 | Add Stygian difficulty selection | 難度6以外の取得・UI選択。endpoint・許可・Flutter契約を別途設計 | open / not in #16 |
| B3 | Automate character map update checks | CI または定期ジョブで `yshelper:check-character-map`。失敗時は収集を増やさない | open / not in #16 |
| B4 | Add YShelper collector observability | 連続失敗・429・record drop・unresolved 等の安全なメトリクス（本文・URLなし） | open / not in #16 |
| B5 | Enable staging collection after permission approval | Runbook のステージング手順を実行。kill switch をステージングのみ true。**利用許可・保存加工再配布・レート制限・通知・SLA が前提** | **blocked** on external permission |

参照: [YSHELPER_OPERATIONS_RUNBOOK.md](./YSHELPER_OPERATIONS_RUNBOOK.md)
