# Artifact Score Weight Operations

聖遺物スコア重み（`artifact_score_weights`）の運用メモ。

新キャラのスコア基準（HP/攻撃など）の追加手順は [ARTIFACT_SCORE_CHARACTER_ONBOARDING.md](./ARTIFACT_SCORE_CHARACTER_ONBOARDING.md) を参照。

## 1. どんな時に remote を使うか

- 新キャラ実装直後に、アプリ更新なしで重みを反映したい
- 既存キャラの評価重みを短サイクルで調整したい
- 設定ミスを緊急修正したい
- 将来的に外部ビルドメタ（KQM/GO/Akasha 由来）を取り込んで運用したい

## 2. local だけで十分なケース

- キャラ追加・調整が低頻度
- オフライン優先で安定動作を最重視
- 配信サーバーや監視の運用コストを増やしたくない

## 3. 現在の実装方針

- デフォルトは local JSON (`assets/config/artifact_score_weights.json`)
- `ARTIFACT_SCORE_WEIGHTS_URL` が指定された場合のみ remote を有効化
- remote 失敗時は local/cache にフォールバックして継続
- マスタ同期後に新キャラを検知し、未登録なら重み再取得を試行

## 4. 有効化方法（remote）

```bash
flutter run --dart-define=ARTIFACT_SCORE_WEIGHTS_URL=https://your-domain/path/artifact_score_weights.json
```

未指定時は local のみ利用。

## 4.1 本番配信での必須事項（忘れ防止）

- remote で自動更新したい場合、**本番ビルド時に必ず**
  `ARTIFACT_SCORE_WEIGHTS_URL` を `--dart-define` で注入する
- 未指定で配信すると remote は無効になり、local のみ利用される
- その場合、新しい重み反映にはアプリ再リリースが必要になる

推奨チェック（リリース前）:

1. `ARTIFACT_SCORE_WEIGHTS_URL` が CI/CD の本番環境変数に設定済み
2. URL先 JSON が 200 応答かつ `profiles` を返す
3. 設定画面の `Score` version が期待どおり更新される

## 5. JSON の最低構成

```json
{
  "profiles": [
    {
      "characterId": "10000052",
      "name": "雷電将軍",
      "weights": {
        "critRate": 2,
        "critDamage": 1,
        "atkPercent": 0,
        "hpPercent": 0,
        "defPercent": 0,
        "elementalMastery": 0,
        "energyRecharge": 1
      }
    }
  ]
}
```

## 6. 追加・更新の実務フロー

1. `characterId` ごとに重みを追加/調整
2. JSON を配信（remote運用時）
3. 「今すぐ同期」または定期更新で反映確認
4. 設定画面の version 表示（Master/Score）で更新確認

## 7. 商用運用での推奨

- `Remote + Local fallback` の二段構成を維持
- 配信JSONにバージョン情報（`version`, `effectiveAt`）を将来追加
- 重要更新時は sync log 監視（missing character profile）を確認
- 将来的に署名検証を入れて改ざん耐性を上げる

## 8. CI/CD での注入例（GitHub Actions）

```yaml
env:
  ARTIFACT_SCORE_WEIGHTS_URL: ${{ secrets.ARTIFACT_SCORE_WEIGHTS_URL }}

# build command example
flutter build appbundle --release \
  --dart-define=ARTIFACT_SCORE_WEIGHTS_URL=${ARTIFACT_SCORE_WEIGHTS_URL}
```
