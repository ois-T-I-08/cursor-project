# Android release signing

本番識別子:

- `applicationId` / `namespace`: `io.github.oisti08.genshinbuilder`
- 現在の`versionName`: `0.1.0`
- 現在の`versionCode`: `1`

`versionName`／`versionCode`は`pubspec.yaml`の`version: 0.1.0+1`からFlutter buildへ渡される。公開ごとに両方を確認し、`versionCode`を既公開版より大きくする。

## ローカル

1. アップロード用 keystore（`.jks`）を用意する  
2. `android/key.properties.example` を `android/key.properties` にコピーして記入（**コミット禁止**）  
3. Debug 開発: `flutter run` / `flutter build apk --debug`（keystore 不要）  
4. Release: `flutter build appbundle --release`  
   - `key.properties` または keystore が無い／空欄だと **GradleException で失敗**（debug 署名フォールバックなし）

## CI

- Workflow: `.github/workflows/genshin-mobile-release-example.yml`（`workflow_dispatch` のみ）  
- Backend URL Secret: `GENSHIN_BUILDER_API_BASE_URL`
- Signing Secrets: `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_STORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`
- 通常の `genshin-mobile-ci` や `pull_request` では署名 Secrets を使わない  
- 一時ファイルは `if: always()` で削除

`GENSHIN_BUILDER_API_BASE_URL` はFlutterからNext.js backendへ接続する公開originであり、AZA.GGのURLではない。ReleaseではHTTPSのoriginだけを許可し、空値、空白、userinfo、path/query/fragment、localhost、loopback、`10.0.2.2`をbuild開始前に拒否する。末尾の`/`は許容する。値はログへ表示しない。

ローカル開発では`http://localhost`、`http://127.0.0.1`、Android emulator用の`http://10.0.2.2`を`--dart-define`へ指定できるが、Release Secretには使用しない。

## Release workflow実行前チェック

- [ ] `GENSHIN_BUILDER_API_BASE_URL`をGitHub Secretへ登録し、承認済みのHTTPS backend originであることを値を表示せず確認する
- [ ] 4つのSigning Secretsが登録済みであることを確認する
- [ ] `pubspec.yaml`のversionName／versionCodeを公開対象版へ更新し、現在値を記録する
- [ ] 本番DBのバックアップと復旧手段を確認する
- [ ] 必要なPrisma migrationがすべて適用済みであることを確認する
- [ ] stagingで初回取得、fresh cache、stale fallback、kill switchの4経路が成功していることを確認する
- [ ] Flutter画面にAZA.GGクレジット、更新日時、サンプル数、stale状態が表示されることを確認する
- [ ] AZA.GG利用条件と商用・広告利用可否の確認記録を保管する
- [ ] `20260720120000_add_team_simulation_jobs` / PostgreSQL baseline と `20260730120000_drop_team_simulation_cache` が staging へ適用済みであることを確認する
- [ ] AZA/ルール推薦が表示されること（gcsim は廃止済み）を staging で確認する
- [ ] HoYoLAB Cookie/UIDが推薦API request、DB、サーバーログへ存在しないことを確認する
- [ ] workflow生成AABの署名、applicationId、versionName／versionCodeを確認する
- [ ] 署名AABを実機へinstallし、起動、backend接続、主要画面を確認する

## AAB 確認

```bash
# 署名（AAB は jarsigner）
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab

# applicationId は bundletool または Android Studio APK Analyzer
```

APK を別途作った場合のみ `apksigner verify` を使用してよい。

## Branch protectionの推奨required checks

GitHubの`Settings` → `Branches`またはRulesetsで`main`を対象に、次の既存job名をrequired status checksへ設定する。

- `analyze-and-test` — Genshin Mobile CI。analyze、保護対象テスト、全Flutterテスト、secret guardを含む
- `test` — 手動Flutter Tests
- `web-golden` — Domain Golden ParityのWeb job
- `mobile-golden` — Domain Golden ParityのMobile job
- `lint-and-build` — Genshin Web CI。Prisma generate／validate、lint、typecheck、全Webテスト、Next.js buildを含む

`Lint`、`Typecheck`、`Validate Prisma schema`、`Build`は現在`lint-and-build`内のstepであり、個別checkではない。個別にrequiredへ設定せず、job全体の`lint-and-build`をrequiredにする。path filterで必須jobが生成されないPRをブロックしないよう、Ruleset適用前に対象pathとrequired workflowの運用を確認する。

## P1-2 公開前保留事項

実装は完了。正規 keystore / 実機 / GitHub Secrets が揃ってから実施する。

- [ ] 正規アップロード用 keystore を作成・バックアップする
- [ ] `android/key.properties` をローカルで設定する
- [ ] 署名付き AAB を生成する
- [ ] jarsigner で AAB 署名を確認する
- [ ] applicationId を確認する（`io.github.oisti08.genshinbuilder`）
- [ ] 実機で起動と HoYoLAB MethodChannel を確認する
- [ ] GitHub Secrets を設定して release workflow を確認する
- [ ] Play Console 登録前に applicationId を最終確認する
