# Genshin Builder

原神の育成・編成・素材計画を支援する非公式ファンツールです。Next.js の Web/API・管理画面と、Flutter のモバイルクライアントを同じリポジトリで管理しています。

> 本プロジェクトは miHoYo / HoYoverse と関係ありません。外部データの正確性・継続提供は保証されません。

## 構成

| ディレクトリ | 内容 |
|---|---|
| [`genshin-builder-app`](genshin-builder-app/) | Next.js 16 / TypeScript / Prisma。公開 API、同期、統計、管理画面 |
| [`genshin-builder-mobile`](genshin-builder-mobile/) | Flutter / Riverpod / Drift。育成管理、素材計算、攻略情報表示 |
| [`docs`](docs/) | リリース検証、プライバシー、ストア申告などの横断文書 |

攻略情報は Akasha の利用統計と、管理者が確認した YouTube 由来のおすすめを別の情報源として表示します。動画から抽出した言及は、そのままおすすめや公開データへ昇格しません。

## 必要環境

- Node.js 24（Web CI と同じメジャー）
- npm（`package-lock.json` を使用）
- Flutter 3.44.5（モバイル CI と同じ版。対応 Dart SDK を同梱）
- Android の実機・release build を行う場合は Android SDK / Java / 署名鍵

## Web のセットアップ

```powershell
Set-Location genshin-builder-app
Copy-Item .env.example .env
npm ci
npx prisma generate
npx prisma migrate deploy
npm run dev
```

開発 URL は `http://localhost:3000` です。DB は既定で `genshin-builder-app/prisma/dev.db` の SQLite を使います。開発専用の新規 migration を作る場合だけ `npx prisma migrate dev` を使い、既存 migration の適用確認には `migrate status` / `migrate deploy` を使ってください。

主な環境変数は次のとおりです。全項目と安全な既定値は [`genshin-builder-app/.env.example`](genshin-builder-app/.env.example) を参照してください。

| 変数 | 用途 |
|---|---|
| `DATABASE_URL` | Prisma 接続先。ローカル既定は `file:./dev.db` |
| `SYNC_API_SECRET` | マスターデータ同期 API の Bearer secret。本番では必須 |
| `BUILD_GUIDE_ADMIN_SECRET` | `/api/admin/build-guides` 専用 Bearer secret。未設定時は 503 |
| `TEAM_TEMPLATE_ADMIN_SECRET` | 編成テンプレート管理 API 専用 Bearer secret |
| `AZA_*` | 深境螺旋統計の upstream、TTL、kill switch |
| `YOUTUBE_*` / `GEMINI_*` / `DEEPSEEK_GUIDE_*` | 攻略動画処理。既定は無効、キーはサーバーだけに置く |

管理画面は `http://localhost:3000/admin/guides` です。画面の表示自体に秘密情報は含まず、読み書き API は `BUILD_GUIDE_ADMIN_SECRET` が未設定なら fail-closed、未認証・不一致なら 401/403 になります。

主な公開 API:

- `GET /api/build-recommendations/{characterId}` — 確認・公開済みの育成おすすめ。ETag / 304 対応
- `GET /api/build-recommendations/{characterId}/sources` — 出典と映像証拠
- `GET /api/abyss/statistics` — AZA.GG を正規化・キャッシュした深境螺旋統計
- `GET /api/team-recommendations` — 編成候補

## Flutter のセットアップ

```powershell
Set-Location genshin-builder-mobile
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run
```

Web API の origin はビルド時に指定します。本番値は HTTPS にしてください。

```powershell
flutter run --dart-define=GENSHIN_BUILDER_API_BASE_URL=https://builder.example.com
```

Android エミュレーターからローカル Web へ接続する場合は、通常 `http://10.0.2.2:3000` を使います。

## 検証とビルド

Web:

```powershell
Set-Location genshin-builder-app
npm ci
npx prisma generate
npx prisma validate
npx prisma migrate status
npx prisma migrate deploy
npm run typecheck
npm run lint
npm test
npm run build
```

Flutter:

```powershell
Set-Location genshin-builder-mobile
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build appbundle --release --dart-define=GENSHIN_BUILDER_API_BASE_URL=https://builder.example.com
```

署名済み Android 成果物、本番 migration、本番公開は、権限・鍵・バックアップを確認した運用者だけが実行します。現在の手動ゲートは [`docs/pre-release-validation.md`](docs/pre-release-validation.md) を参照してください。

## よくある問題

- `npm ci` / `prisma generate` が Windows の `EPERM` や DLL ロックで失敗する
  対象ディレクトリで動いている `next dev` / Node プロセスを終了してから再実行します。別プロジェクトの Node プロセスは終了しないでください。
- Turbopack が別の lockfile を workspace root と誤認する
  [`genshin-builder-app/next.config.ts`](genshin-builder-app/next.config.ts) の `turbopack.root` と、実行ディレクトリを確認します。
- Prisma migration が不一致
  先に DB をバックアップし、`npx prisma migrate status` で状態を確認します。既存 migration の編集や、本番での `migrate dev` は行いません。
- 管理 API が 401 / 403 / 503
  401 は Bearer 不足、403 は不一致、503 はサーバー側 secret 未設定です。secret をログや URL に記録しないでください。
- 保存時に 409
  別の更新が先に保存されています。入力は保持されるため、最新状態を確認してから再保存します。
- Amber 取得失敗 / 不明 `setId`
  既存公開版は維持されます。聖遺物候補を含む新規公開は、マスターを取得できるまで fail-closed です。
- Flutter の API パースエラー
  Web の公開 API、`schemaVersion`、`GENSHIN_BUILDER_API_BASE_URL` を確認します。セクション単位の取得失敗は再試行できます。

攻略情報の状態遷移・公開安全策は [`genshin-builder-app/docs/BUILD_GUIDE_RECOMMENDATIONS.md`](genshin-builder-app/docs/BUILD_GUIDE_RECOMMENDATIONS.md)、各層の詳細は [`genshin-builder-app/ARCHITECTURE.md`](genshin-builder-app/ARCHITECTURE.md) と [`genshin-builder-mobile/ARCHITECTURE.md`](genshin-builder-mobile/ARCHITECTURE.md) を参照してください。

## License

運営者が独自に作成したソースコードおよび文書は [MIT License](LICENSE) です。

```text
Copyright (c) 2026 ois-T-I-08
```

原神 / HoYoverse の名称・画像・ゲームデータ、Project Amber / AZA.GG / HoYoLAB / YShelper などの第三者データ・素材は MIT License の対象外です。詳細は [`genshin-builder-app/THIRD_PARTY_NOTICES.md`](genshin-builder-app/THIRD_PARTY_NOTICES.md) と [`docs/PLAY_DATA_SAFETY.md`](docs/PLAY_DATA_SAFETY.md) を参照してください。
