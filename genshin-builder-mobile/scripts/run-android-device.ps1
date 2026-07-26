# 実機が接続されていれば flutter run を実行する
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $ProjectRoot

$SdkRoot = Join-Path $env:LOCALAPPDATA "Android\sdk"
$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:PATH = "$SdkRoot\platform-tools;$SdkRoot\emulator;$env:PATH"

$jbr = "C:\Program Files\Android\Android Studio\jbr"
if (Test-Path $jbr) {
  $env:JAVA_HOME = $jbr
}

Write-Host "Checking connected devices..."
adb devices -l
Write-Host ""

$devices = flutter devices --machine 2>$null | ConvertFrom-Json
$android = $devices | Where-Object { $_.targetPlatform -eq "android-arm" -or $_.targetPlatform -eq "android-arm64" -or $_.targetPlatform -eq "android-x64" }

if (-not $android) {
  Write-Host "Android 実機が見つかりません。" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "手順:"
  Write-Host "  1. スマホで USB デバッグを有効化"
  Write-Host "  2. USB で PC に接続し、デバッグ許可を承認"
  Write-Host "  3. flutter devices で表示を確認"
  Write-Host ""
  Write-Host "詳細: docs\ANDROID_DEVICE_TEST.md"
  exit 1
}

$deviceId = $android[0].id
Write-Host "Running on: $($android[0].name) ($deviceId)" -ForegroundColor Green

# Team recommendations / abyss APIs need the Next.js backend origin.
# Prefer env GENSHIN_BUILDER_API_BASE_URL; otherwise local Next via adb reverse.
$apiBase = $env:GENSHIN_BUILDER_API_BASE_URL
if ([string]::IsNullOrWhiteSpace($apiBase)) {
  $apiBase = "http://127.0.0.1:3000"
  Write-Host "GENSHIN_BUILDER_API_BASE_URL unset; using $apiBase (run adb reverse tcp:3000 tcp:3000)" -ForegroundColor Yellow
  adb -s $deviceId reverse tcp:3000 tcp:3000 | Out-Null
}

flutter run -d $deviceId --dart-define=GENSHIN_BUILDER_API_BASE_URL=$apiBase
