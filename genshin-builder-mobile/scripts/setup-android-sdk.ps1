# Android SDK セットアップ（Flutter 実機ビルド用）
# Android Studio インストール済みでも cmdline-tools が無い場合に実行する。
# 管理者権限不要。初回は数 GB ダウンロードがあります。

$ErrorActionPreference = "Stop"

$SdkRoot = Join-Path $env:LOCALAPPDATA "Android\sdk"
$JbrHome = "C:\Program Files\Android\Android Studio\jbr"
if (Test-Path $JbrHome) {
  $env:JAVA_HOME = $JbrHome
  $env:PATH = "$JbrHome\bin;$env:PATH"
  Write-Host "Using JAVA_HOME: $JbrHome"
} else {
  Write-Warning "Android Studio JBR not found. Install Android Studio or set JAVA_HOME to JDK 17+."
}
$CmdlineZip = Join-Path $env:TEMP "commandlinetools-win.zip"
$CmdlineUrl =
  "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"

Write-Host "SDK root: $SdkRoot"
New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null

$sdkmanager = Join-Path $SdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmanager)) {
  Write-Host "Downloading Android command-line tools..."
  Invoke-WebRequest -Uri $CmdlineUrl -OutFile $CmdlineZip
  $extractDir = Join-Path $env:TEMP "android-cmdline-tools"
  if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
  Expand-Archive -Path $CmdlineZip -DestinationPath $extractDir -Force
  $dest = Join-Path $SdkRoot "cmdline-tools\latest"
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Move-Item (Join-Path $extractDir "cmdline-tools") $dest
  Remove-Item $CmdlineZip -Force -ErrorAction SilentlyContinue
  Write-Host "cmdline-tools installed."
}

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:PATH = "$SdkRoot\platform-tools;$SdkRoot\cmdline-tools\latest\bin;$env:PATH"

Write-Host "Installing SDK packages (platform-tools, android-36, build-tools)..."
$packages = @(
  "platform-tools",
  "platforms;android-36",
  "build-tools;36.0.0",
  "cmdline-tools;latest"
)
& $sdkmanager @packages

Write-Host "Accepting SDK licenses..."
1..20 | ForEach-Object { "y" } | & $sdkmanager --licenses

# ユーザー環境変数（永続化）
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $SdkRoot, "User")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $SdkRoot, "User")
if (Test-Path $JbrHome) {
  [Environment]::SetEnvironmentVariable("JAVA_HOME", $JbrHome, "User")
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathAdds = @(
  "$SdkRoot\platform-tools",
  "$SdkRoot\cmdline-tools\latest\bin"
)
foreach ($p in $pathAdds) {
  if ($userPath -notlike "*$p*") {
    $userPath = if ($userPath) { "$userPath;$p" } else { $p }
  }
}
[Environment]::SetEnvironmentVariable("Path", $userPath, "User")

Write-Host ""
Write-Host "Done. Restart the terminal and run:"
Write-Host "  flutter doctor"
Write-Host "  flutter devices"
