# Domain Golden（Web ↔ Mobile パリティ）

Web（TypeScript）と Mobile（Dart）が **同一の計算結果** を返すことを保証するための golden テストです。

## ファイル

| パス | 役割 |
|------|------|
| `cases.json` | 入力と期待値（両側のテストが読む） |

## 実行

```bash
# Web
cd genshin-builder-app
npm test -- src/lib/__tests__/domain-golden.test.ts

# Mobile
cd genshin-builder-mobile
flutter test test/domain/domain_golden_test.dart
```

## ケース追加手順

1. `cases.json` に `input` / `expected` を追加する
2. Web・Mobile の両方でテストを実行し、どちらも緑になることを確認する
3. 片側だけ失敗する場合は、その側のドメイン実装のズレを修正する（golden を安易に合わせない）

## ルール

- 期待値は **両実装が一致した確定値** のみ入れる
- 並び順に依存しない比較（`linesByMaterialId` など）を優先する
- 外部 API / DB に依存するケースは入れない（純関数のみ）

## Mobile CI Parity gate

`genshin-mobile-ci.yml` は全件 `flutter test` の前に、次を **名前付き必須実行**する（破壊検知ゲート。計算仕様そのものは変えない）:

1. `test/domain/domain_golden_test.dart`
2. `test/domain/artifact_completion_test.dart`
3. `test/domain/artifact_score_test.dart`

- `cases.json` / 上記テストの期待値変更、および domain 計算の仕様変更は「仕様変更」扱いとする
- 変更する場合は **理由・影響範囲・テスト変更内容** を提示し、片側だけ合わせて緑にしない
- Web↔Mobile 共有計算の CI は従来どおり `.github/workflows/genshin-domain-golden.yml` も参照
