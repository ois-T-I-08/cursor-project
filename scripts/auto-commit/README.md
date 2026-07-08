# auto-commit

変更ファイルを解析し、リポジトリの既存スタイルに合わせた Conventional Commits 形式（日本語）のメッセージで自動コミットするツールです。

## 使い方

```bash
# プレビュー（コミットしない）
node scripts/auto-commit/index.mjs --dry-run

# 1 回だけ実行
node scripts/auto-commit/index.mjs

# バックグラウンド監視（30 秒間隔・8 秒デバウンス）
node scripts/auto-commit/index.mjs --watch 30
```

## Cursor 連携

`.cursor/hooks.json` で以下が有効です。

| フック | 動作 |
|--------|------|
| `afterFileEdit` / `postToolUse` | `Write` / `StrReplace` 編集時に `.cursor/.commit-pending` フラグを立てる |
| `stop` | Agent ターン完了時にフラグがあれば自動コミット |

Agent セッション終了ごとに、まとめて 1 コミットされます（編集のたびに即コミットはしません）。

## メッセージ生成

- 変更パスから `mobile` / `web` / `hooks` スコープを推定
- 新規ファイル比率・差分量から `feat` / `refactor` / `docs` 等を判定
- 直近 3 コミットと同一 subject の場合はスキップ（重複防止）

## 除外

以下は自動コミット対象外です。

- `.next/`, `build/`, `.dart_tool/`, `node_modules/`
- `.env`, 鍵ファイル, `credentials.json`
- `scripts/auto-commit/` の編集は Cursor フックではフラグ対象外（CLI からはコミット可）

## 注意

- `--no-verify` は使用しません
- 秘密情報を含むパスはブロックします
- 大きな変更は `--dry-run` でメッセージを確認してから実行してください
