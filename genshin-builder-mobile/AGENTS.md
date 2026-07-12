# AGENTS.md — Genshin Builder Mobile

## プロジェクト

- **種別**: Flutter モバイルアプリ（非公式ファンツール）
- **参照 Web**: `../genshin-builder-app/`（育成 UI・計算仕様の正）
- **参考**: [genshin_material](https://github.com/chika3742/genshin_material)（HoYoLAB / Drift — **概念参考のみ、コード転載禁止**）

## Phase

| Phase | 内容 |
|-------|------|
| **1** | キャラ詳細 + 素材計算 + ブックマーク + Amber 同期 + **Drift** |
| **2** | HoYoLAB（WebView + Cookie + secure storage + dailyNote） |
| **拡張** | UseCase / Repository Port / Team·Damage·Meta·Cloud 境界 |

詳細: `ARCHITECTURE.md`

## 作業ルール

1. **既存 Web を変更しない**
2. **domain/ は純 Dart** — Flutter / Drift / http に依存しない
3. **計算・ブックマーク sourceKey は Web と一致**
4. **パリティゲート（厳守）** — CI `Parity gate` が次を必須実行する。壊さないこと。仕様変更時は理由・影響・テスト変更を提示（期待値の安易な合わせ込み禁止）
   - `test/domain/domain_golden_test.dart`
   - `test/domain/artifact_completion_test.dart`
   - `test/domain/artifact_score_test.dart`
   - 詳細: `../shared/domain-golden/README.md` / `.github/workflows/genshin-mobile-ci.yml`
5. **genshin_material は参考のみ**
6. **Cookie は secure storage のみ**
7. **README 非公式免責を維持**
8. **層依存（厳守）**
   - `features` → `providers` / `domain` / `application`（状態型）のみ。**`data/` 直参照は原則禁止**（hoyolab 機能内の DTO・ログインは例外）
   - `providers` → `application` + `domain` + `data` 実装の配線
   - `application` → `domain` + Repository 契約。必要時のみ data DTO（HoYoLAB 反映など）
   - `data` → `domain` 実装
   - `domain` → 外部パッケージ依存なし（純 Dart）
9. **マスタ同期との連携（厳守）**
   - 新機能・新データ・新画面は既存 Sync（Amber → DB upsert → probe / 起動自動同期）から孤立させない
   - 外部ソースから自動取得・差分更新できる設計を優先。手動入力・ハードコード一覧を増やさない
   - 追加時チェック: 既存 Sync で足りるか → API/Provider → スキーマ → 正規化 → `MasterSyncService` 組み込み → upsert/重複防止
   - 目標: 原神アップデートの新キャラ・武器・聖遺物・素材を自動同期で取り込めること
   - Cursor ルール: `../.cursor/rules/genshin-master-sync-extensibility.mdc`
10. **セキュリティ自己監査**
   - リリース前・HoYoLAB/秘密情報変更時は Skill `genshin-security-checklist`（`.cursor/skills/genshin-security-checklist/`）を使う
   - **自動読込**: `.cursor/rules/genshin-security-checklist.mdc`（alwaysApply）。読む直前に「genshin-security-checklist を読みます」と宣言する
   - 外部 800+ 攻撃系スキルは取り込まない。防御チェックのみ

## ディレクトリ

```
lib/
  core/                 # errors 等
  domain/
    models/
    repositories/       # 抽象契約
    team/ damage/ meta/ account/  # 将来機能の境界モデル
  application/
    characters/         # UseCase + CharacterDetailState
    sync/               # CloudSyncPort ローカル実装
  data/
    repositories/       # Drift* 実装
    sources 相当: amber/ hoyolab/ akasha/ meta/ db/
  providers/
  features/
```

## コマンド

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```
