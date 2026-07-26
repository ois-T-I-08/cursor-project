# Dart format baseline（Issue #12）

機能変更と混ぜない。順序:

1. Flutter / Dart SDK バージョンを CI・README・`pubspec` で固定する
2. 整形対象と除外を決める（下記）
3. **formatting-only** PR を単独で出す
4. 全テストを通す
5. CI に `dart format --output=none --set-exit-if-changed` を追加する

## 対象

- `genshin-builder-mobile/lib/**/*.dart`
- `genshin-builder-mobile/test/**/*.dart`
- `shared/domain-golden/**/*.dart`（存在する場合）

## 除外

- `**/*.g.dart`（Drift / freezed / json_serializable 等の generated）
- `**/*.freezed.dart`
- `**/generated/**`
- ベンダー・ツール生成キャッシュ

## 禁止

- 機能修正・リファクタと同一 PR で大量 format しない
- generated を手で format して差分を増やさない

この方針ドキュメント自体は Issue #12 の手順固定用。format 一括適用は別 PR。
