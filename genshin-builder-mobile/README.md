# Genshin Builder Mobile

原神のキャラクター育成（レベル・突破・天賦・武器）に必要な素材を計算・管理する **非公式** ファンツールです。

> **免責事項**: 本アプリは miHoYo / HoYoverse とは一切関係ありません。ゲームデータは [Project Amber (gi.yatta.moe)](https://gi.yatta.moe) 等の第三者ソースを参照しており、正確性・最新性は保証されません。

## 主な機能

- キャラクター一覧・詳細（Lv / 天賦 / 武器スライダー + 必要素材表示）
- 素材ブックマーク（ローカル DB、materialId 合算、キャラアイコン表示）
- ゲームマスターデータ同期（Project Amber → ローカル SQLite）
- HoYoLAB 連携（WebView ログイン・樹脂/デイリー/派遣表示・secure storage）
- 深境螺旋のキャラクター／編成統計（AZA.GG 提供データを Web バックエンド経由で表示）
- Akasha 利用率と、管理者確認済み YouTube おすすめの分離表示
- おすすめ武器・聖遺物（4セット / 2+2）・メインステータス・目標値・出典
- 育成ゴール、デイリープラン、通知、編成・育成進捗

## 関連プロジェクト

| プロジェクト | 説明 |
|-------------|------|
| `../genshin-builder-app/` | Web 版（Next.js）。計算ロジック・仕様の参照元 |
| [genshin_material](https://github.com/chika3742/genshin_material) | Flutter 参考実装（Drift / HoYoLAB WebView Cookie） |

## セットアップ

[Flutter SDK](https://docs.flutter.dev/get-started/install) をインストールし PATH に追加してください。CI と同じ Flutter 3.44.5 を推奨します。個人環境の絶対パスには依存しません。

```bash
cd genshin-builder-mobile

# 初回のみ: プラットフォームフォルダを生成（lib/ は既存のまま）
flutter create . --project-name genshin_builder_mobile

flutter pub get
dart run build_runner build   # Drift codegen
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run
```

深境螺旋統計を使う場合は、Web 版の公開 origin をビルド時に指定します。Flutter から AZA.GG へは直接接続しません。

```bash
flutter run --dart-define=GENSHIN_BUILDER_API_BASE_URL=https://builder.example.com
```

Android エミュレーターでローカル Web 版へ接続する場合は、必要に応じて `http://10.0.2.2:3000` を指定してください。本番は HTTPS を使用してください。

`flutter doctor` で Android / Visual Studio の警告が出る場合があります。解析・テストと、署名済み Android release build / 実機確認では必要な SDK が異なります。配布前は Android SDK、Java、署名鍵を用意し、ルートの `docs/pre-release-validation.md` に従って fresh install と migration を実機確認してください。

## Web API と安全な外部リンク

攻略情報は `GET /api/build-recommendations/{characterId}` から取得します。各セクションはローディング・空・エラーを独立して表示し、取得失敗時は再試行できます。

出典として起動できる URL は HTTPS の `youtube.com`、`www.youtube.com`、`m.youtube.com`、`youtu.be` だけです。パーサーと起動直前の両方で検証し、不正・未知の URL は表示データから除外します。

Akasha は利用統計、YouTube は攻略おすすめとして別ラベル・別リストで扱います。未知の武器 ID / 聖遺物 setId や未対応 ratio があっても画面全体をクラッシュさせず、既知のセクションを表示し続けます。

## 検証

```bash
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

ドメインゴールデン、聖遺物スコア・完成度、Drift migration は保護対象です。期待値の変更だけでテストを通さず、Web と Flutter の対応ロジックを同じ意味で更新してください。

## アーキテクチャ

`ARCHITECTURE.md` を参照。

## 開発ガイド

- `AGENTS.md` — AI エージェント向けルール
- `docs/PHASE1_IMPLEMENTATION.md` — 初期実装の履歴
- `docs/AGENT_MEMORY.md` — セッション決定ログ

## ライセンス

運営者の自作コード・文書はリポジトリルートの [MIT License](../LICENSE)（`Copyright (c) 2026 ois-T-I-08`）です。

原神 / HoYoverse の名称・画像・ゲームデータ、Project Amber / AZA.GG / HoYoLAB / YShelper 等の第三者データ・素材は MIT の対象外です。詳細は [THIRD_PARTY_NOTICES.md](../genshin-builder-app/THIRD_PARTY_NOTICES.md) およびルート [README.md](../README.md) を参照してください。
