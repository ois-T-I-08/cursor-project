# 新キャラ追加時のスコア基準オンボーディング

聖遺物スコアの「取得基準」を新キャラ追加時に正しくする手順。

## ルール（1行）

> **Amber の `specialProp` を確認し、参照ステータスと一致しなければ `artifact_score_type_overrides.json` に1件追加してテストする。一致していれば追加不要。**

## 編集するファイル

| ファイル | 役割 |
|---------|------|
| `assets/config/artifact_score_type_overrides.json` | **名前マップ（ここだけ編集）** |
| `test/domain/artifact_score_test.dart` | 代表ケースのテスト追加 |
| `tool/lookup_character_score.dart` | 新キャラの `specialProp` 確認 |

重み係数を変えたい場合は別ファイル `artifact_score_weights.json`（通常は不要）。

## 手順

### 1. 新キャラの Amber データを確認

`tool/lookup_character_score.dart` の名前を書き換えて実行:

```bash
dart run tool/lookup_character_score.dart
```

確認項目:

- `name` … 表示名（JSON の `name` と一致させる）
- `characterId` … JSON の `characterId`
- `specialProp` … Amber API の突破/固有ステ
- `inferScoreType` … 自動推定結果

### 2. 名前マップ追加が必要か判定

**追加不要**（`inferScoreType` だけで正しい）:

| specialProp | 取得基準 |
|-------------|---------|
| `FIGHT_PROP_HP_PERCENT` | HP |
| `FIGHT_PROP_ATTACK_PERCENT` | 攻撃 |
| `FIGHT_PROP_DEFENSE_PERCENT` | 防御 |
| `FIGHT_PROP_ELEMENT_MASTERY` | 元素熟知 |
| `FIGHT_PROP_CHARGE_EFFICIENCY` | 元素チャージ |

**追加が必要**（コロンビーナ型）:

- `FIGHT_PROP_CRITICAL` / `FIGHT_PROP_CRITICAL_HURT`
- `FIGHT_PROP_*_ADD_HURT`（元素ダメージ）
- 上記以外で、スキル倍率の参照ステと `inferScoreType` 結果が食い違う場合

### 3. JSON に1件追加

`assets/config/artifact_score_type_overrides.json`:

```json
{
  "characterId": "10000125",
  "name": "コロンビーナ",
  "scoreType": "hp",
  "note": "specialProp=FIGHT_PROP_CRITICAL"
}
```

`scoreType` の値: `atk` / `hp` / `def` / `em` / `recharge`

`note` は任意（なぜ上書きしているかのメモ）。

### 4. テストを1件追加

```dart
expect(
  inferScoreType(
    'FIGHT_PROP_CRITICAL',
    'コロンビーナ',
    nameOverrides: const {'コロンビーナ': ArtifactScoreType.hp},
  ),
  ArtifactScoreType.hp,
);
```

### 6. マスタ同期 → 実機確認

設定画面からマスタ同期後、キャラ詳細の聖遺物で取得基準を確認。


## JSON 例

```json
{
  "overrides": [
    {
      "characterId": "10000125",
      "name": "コロンビーナ",
      "scoreType": "hp",
      "note": "specialProp=FIGHT_PROP_CRITICAL"
    }
  ]
}
```

## 関連ドキュメント

- 重み JSON / remote 運用: [ARTIFACT_SCORE_WEIGHT_OPERATIONS.md](./ARTIFACT_SCORE_WEIGHT_OPERATIONS.md)
