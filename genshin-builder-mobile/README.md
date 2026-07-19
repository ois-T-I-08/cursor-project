# Genshin Builder Mobile

原神のキャラクター育成（レベル・突破・天賦・武器）に必要な素材を計算・管理する **非公式** ファンツールです。

> **免責事項**: 本アプリは miHoYo / HoYoverse とは一切関係ありません。ゲームデータは [Project Amber (gi.yatta.moe)](https://gi.yatta.moe) 等の第三者ソースを参照しており、正確性・最新性は保証されません。

## 機能（Phase 1 MVP）

- キャラクター一覧・詳細（Lv / 天賦 / 武器スライダー + 必要素材表示）
- 素材ブックマーク（ローカル DB、materialId 合算、キャラアイコン表示）
- ゲームマスターデータ同期（Project Amber → ローカル SQLite）
- HoYoLAB 連携（WebView ログイン・樹脂/デイリー/派遣表示・secure storage）
- 深境螺旋のキャラクター／編成統計（AZA.GG 提供データを Web バックエンド経由で表示）

## 関連プロジェクト

| プロジェクト | 説明 |
|-------------|------|
| `../genshin-builder-app/` | Web 版（Next.js）。計算ロジック・仕様の参照元 |
| [genshin_material](https://github.com/chika3742/genshin_material) | Flutter 参考実装（Drift / HoYoLAB WebView Cookie） |

## セットアップ

[Flutter SDK](https://docs.flutter.dev/get-started/install) をインストールし PATH に追加してください。

**本環境の導入先**: `C:\src\flutter`（stable、`flutter\bin` をユーザー PATH に追加済み）

```bash
cd genshin-builder-mobile

# 初回のみ: プラットフォームフォルダを生成（lib/ は既存のまま）
flutter create . --project-name genshin_builder_mobile

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter analyze
flutter test
flutter run
```

深境螺旋統計を使う場合は、Web 版の公開 origin をビルド時に指定します。Flutter から AZA.GG へは直接接続しません。

```bash
flutter run --dart-define=GENSHIN_BUILDER_API_BASE_URL=https://builder.example.com
```

Android エミュレーターでローカル Web 版へ接続する場合は、必要に応じて `http://10.0.2.2:3000` を指定してください。本番は HTTPS を使用してください。

`flutter doctor` で Android / Visual Studio の警告が出る場合があります。テスト・codegen には Flutter + Chrome で十分です。実機ビルドには Android Studio または Visual Studio の C++ ワークロードが必要です。

## アーキテクチャ

`ARCHITECTURE.md` を参照。

## 開発ガイド

- `AGENTS.md` — AI エージェント向けルール
- `docs/PHASE1_IMPLEMENTATION.md` — Phase 1 ファイル一覧・優先順位
- `docs/AGENT_MEMORY.md` — セッション決定ログ

## ライセンス

MIT（ゲームアセット・データの権利は原権利者に帰属）
