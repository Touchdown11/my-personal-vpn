# ==============================================================================
# VeloVPN Personal Edition — One-Click Windows Local Builder (PowerShell)
# Run inside PowerShell on your Windows PC:
#   powershell -ExecutionPolicy Bypass -File .\build-on-windows.ps1
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Host "⚡ Checking for Flutter SDK on your Windows PC..." -ForegroundColor Cyan
if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Flutter is not installed yet!" -ForegroundColor Red
    Write-Host "Install Flutter free in Windows PowerShell using:" -ForegroundColor Yellow
    Write-Host "   winget install -e --id Google.Flutter" -ForegroundColor Green
    Write-Host "Then close & reopen PowerShell and run this script again."
    exit 1
}

Write-Host "🛠️ Preparing Android & Windows native folders..." -ForegroundColor Cyan
if (-not (Test-Path ".\windows") -or -not (Test-Path ".\android")) {
    Copy-Item ".\pubspec.yaml" "$env:TEMP\velo_pubspec.bak" -Force
    Copy-Item ".\lib" "$env:TEMP\velo_lib.bak" -Recurse -Force

    flutter create . --platforms=android,windows --org com.personal.velovpn --project-name velo_personal_vpn

    Copy-Item "$env:TEMP\velo_pubspec.bak" ".\pubspec.yaml" -Force
    Remove-Item ".\lib" -Recurse -Force
    Copy-Item "$env:TEMP\velo_lib.bak" ".\lib" -Recurse -Force
}

Write-Host "🤖 Preparing Android scaffolding for the vendored WireGuard plugin..." -ForegroundColor Cyan
dart tool/prepare_android.dart
if ($LASTEXITCODE -ne 0) { throw "Android preparation failed." }

Write-Host "📦 Downloading Flutter packages..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

Write-Host "🔎 Analyzing Dart code..." -ForegroundColor Cyan
flutter analyze
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }

Write-Host "🧪 Running regression tests..." -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }

Write-Host "🖥️ Building Windows Desktop App (.exe)..." -ForegroundColor Cyan
flutter config --enable-windows-desktop
flutter build windows --release --no-tree-shake-icons

Write-Host ""
Write-Host "✅ Windows EXE built successfully!" -ForegroundColor Green
Write-Host "   Location: .\build\windows\x64\runner\Release\velo_personal_vpn.exe" -ForegroundColor Yellow
Write-Host "   (Right-click velo_personal_vpn.exe -> Run as administrator to connect VPN!)"

Write-Host ""
Write-Host "📱 Checking if Android SDK is installed for local APK build..." -ForegroundColor Cyan
try {
    flutter build apk --release --no-tree-shake-icons
    Write-Host "✅ Android APK built successfully!" -ForegroundColor Green
    Write-Host "   Location: .\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Yellow
} catch {
    Write-Host "ℹ️ Android Studio/SDK not installed locally — use the included GitHub Cloud Builder (.github/workflows/build-personal-vpn.yml) to compile your Android APK for free with 0 GB download!" -ForegroundColor Cyan
}
