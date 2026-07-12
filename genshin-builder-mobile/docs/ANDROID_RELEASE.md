# Android release signing

本番識別子:

- `applicationId` / `namespace`: `io.github.oisti08.genshinbuilder`

## ローカル

1. アップロード用 keystore（`.jks`）を用意する  
2. `android/key.properties.example` を `android/key.properties` にコピーして記入（**コミット禁止**）  
3. Debug 開発: `flutter run` / `flutter build apk --debug`（keystore 不要）  
4. Release: `flutter build appbundle --release`  
   - `key.properties` または keystore が無い／空欄だと **GradleException で失敗**（debug 署名フォールバックなし）

## CI

- Workflow: `.github/workflows/genshin-mobile-release-example.yml`（`workflow_dispatch` のみ）  
- Secrets: `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_STORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`  
- 通常の `genshin-mobile-ci` や `pull_request` では署名 Secrets を使わない  
- 一時ファイルは `if: always()` で削除

## AAB 確認

```bash
# 署名（AAB は jarsigner）
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab

# applicationId は bundletool または Android Studio APK Analyzer
```

APK を別途作った場合のみ `apksigner verify` を使用してよい。

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
