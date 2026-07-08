# Android 実機テスト手順

## 現在の環境状態（セットアップ済み）

| 項目 | 状態 |
|------|------|
| Android Studio | `C:\Program Files\Android\Android Studio` |
| Android SDK | `%LOCALAPPDATA%\Android\sdk` |
| Flutter JDK | Android Studio JBR（`flutter config --jdk-dir` 設定済み） |
| `flutter doctor` | Android toolchain ✓ |
| デバッグ APK | `build\app\outputs\flutter-apk\app-debug.apk` |

SDK が不足していた場合は以下で再インストール:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-android-sdk.ps1
```

---

## 1. スマホ側の準備

1. **設定** → **端末情報** → **ビルド番号** を 7 回タップ → 開発者向けオプションを有効化
2. **設定** → **開発者向けオプション**
   - **USB デバッグ** を ON
   - （あれば）**USB デバッグ（セキュリティ設定）** も ON
3. USB ケーブルで PC に接続（データ転送モード / ファイル転送）
4. スマホに「USB デバッグを許可しますか？」→ **許可**（「常に許可」推奨）

---

## 2. 接続確認

**新しい PowerShell** を開いて（環境変数反映のため）:

```powershell
cd "c:\cursor project\genshin-builder-mobile"
flutter devices
adb devices
```

実機が表示されれば OK（例: `SM G991B • android-arm64`）。

`adb devices` が `unauthorized` のとき → スマホでデバッグ許可ダイアログを承認。

---

## 3. 実機にインストールして起動

### 方法 A: Flutter で直接実行（開発向け・ホットリロード可）

```powershell
cd "c:\cursor project\genshin-builder-mobile"
flutter run
```

複数デバイスがある場合:

```powershell
flutter run -d <device-id>
```

### 方法 B: ビルド済み APK をインストール

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### ヘルパースクリプト

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-android-device.ps1
```

---

## 4. 実機で確認する項目

| 画面 | 確認内容 |
|------|----------|
| ホーム | ブックマーク一覧、同期状態 |
| 設定 | マスタ同期（進捗バー）、HoYoLAB 連携入口 |
| キャラ一覧 | Project Amber 同期後のキャラ表示 |
| キャラ詳細 | レベル・天賦・**武器突破素材** |
| HoYoLAB | WebView ログイン → 樹脂・デイリー表示 |

初回は **設定 → 今すぐ同期** を実行（武器突破は数分かかる場合あり）。

---

## 5. Android Studio から実行（任意）

1. Android Studio を起動
2. **Open** → `genshin-builder-mobile` フォルダ
3. 上部デバイス選択で実機を選ぶ
4. **Run**（緑の三角）または **Flutter** プラグイン経由で実行

Flutter / Dart プラグインが未導入なら:
**Settings** → **Plugins** → `Flutter` をインストール（Dart も自動）

---

## 6. トラブルシュート

| 症状 | 対処 |
|------|------|
| `flutter devices` に Android が出ない | USB ケーブル変更、ドライバ再インストール、[Google USB Driver](https://developer.android.com/studio/run/win-usb) |
| `cmdline-tools` エラー | `scripts\setup-android-sdk.ps1` を再実行 |
| Java バージョンエラー | `flutter config --jdk-dir="C:\Program Files\Android\Android Studio\jbr"` |
| Gradle ビルド失敗 | `flutter clean` → `flutter pub get` → 再ビルド |
| HoYoLAB Cookie 取得失敗 | 実機 WebView でログイン後「連携を完了」、Chrome カスタムタブではなくアプリ内 WebView を使用 |

---

## 環境変数（永続化済み）

- `ANDROID_HOME` = `%LOCALAPPDATA%\Android\sdk`
- `ANDROID_SDK_ROOT` = 同上
- `Path` に `platform-tools` と `cmdline-tools\latest\bin` を追加

ターミナルを開き直してから `flutter doctor` で確認してください。
