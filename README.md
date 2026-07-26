# cursor-project (Genshin Builder)

原神の育成・編成・素材計画を支援するモバイルアプリ（Flutter）と、同期・統計 API 用の Next.js バックエンドで構成されるモノレポです。

## License

運営者が独自に作成したソースコードおよび文書は [MIT License](LICENSE) です。

```text
Copyright (c) 2026 ois-T-I-08
```

### ライセンス対象外（第三者・ゲーム権利）

次のものは MIT License の対象外です。権利は各権利者に帰属します。本リポジトリのコードがそれらを参照・表示する場合でも、再配布許諾を意味しません。

- 原神および HoYoverse に帰属する名称、キャラクター名、武器名、画像、アイコン、商標、ロゴ
- ゲーム内数値・ゲームデータ
- Project Amber が提供するデータ
- AZA.GG が提供するデータ
- HoYoLAB / HoYoverse が提供するデータ
- YShelper が提供するデータ
- その他第三者が提供するコード・データ・素材

第三者サービスの扱い・確認状況は [`genshin-builder-app/THIRD_PARTY_NOTICES.md`](genshin-builder-app/THIRD_PARTY_NOTICES.md) を参照してください。

## Packages

| ディレクトリ | 内容 |
|--------------|------|
| [`genshin-builder-mobile`](genshin-builder-mobile/) | Flutter クライアント |
| [`genshin-builder-app`](genshin-builder-app/) | Next.js API / Web |
| [`docs`](docs/) | 横断ドキュメント（LICENSE 記録、Play Data Safety、GitHub 整理など） |

## Privacy and terms

- Privacy Policy / Terms of Use: アプリ設定画面から公式サイトの文書へリンクします
- HoYoLAB 連携は任意です。連携前に説明画面での明示確認が必要です
- 詳細な Google Play Data Safety 申告案: [`docs/PLAY_DATA_SAFETY.md`](docs/PLAY_DATA_SAFETY.md)
