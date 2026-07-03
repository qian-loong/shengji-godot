# Export gl_compatibility emulator APK, install, and launch for UI verification.
# Run after any GUI/layout change under src/godot (required workflow — see CLAUDE.md).
#
# Usage:
#   .\tools\verify_ui_emulator.ps1
#   .\tools\verify_ui_emulator.ps1 -Screenshot

param(
    [switch]$Screenshot
)

$ErrorActionPreference = "Stop"

function Find-AdbPath {
    if ($env:ADB_EXE -and (Test-Path $env:ADB_EXE)) {
        return $env:ADB_EXE
    }
    foreach ($candidate in @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "E:\DevTools\AndroidSdk\platform-tools\adb.exe"
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    throw "adb not found. Set `$env:ADB_EXE or install Android platform-tools."
}

function Wait-EmulatorDevice {
    param([string]$Adb)
    for ($i = 1; $i -le 90; $i++) {
        $devices = & $Adb devices 2>$null
        if ($devices -match "emulator-\d+\s+device") {
            $boot = (& $Adb shell getprop sys.boot_completed 2>$null)
            if ($boot -match "1") {
                return (($devices | Select-String "emulator-\d+\s+device").ToString().Split()[0])
            }
        }
        Start-Sleep -Seconds 2
    }
    return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $repoRoot "builds\android\shengji-debug-emulator.apk"
$qaDir = Join-Path $repoRoot "builds\android\qa"

& (Join-Path $PSScriptRoot "export_android_emulator.ps1")

if (-not (Test-Path $apk)) {
    throw "Export did not produce: $apk"
}

$adb = Find-AdbPath

# adb often prints "* daemon not running; starting now" to stderr on first use,
# which PowerShell would otherwise turn into a NativeCommandError under
# $ErrorActionPreference = 'Stop'. Warm the server up in a tolerant scope.
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $adb start-server 2>&1 | Out-Null
$ErrorActionPreference = $prevPref

$serial = Wait-EmulatorDevice $adb
if (-not $serial) {
    throw "No running emulator. Start AVD (e.g. Pixel_6_API_36) and retry."
}

Write-Host "Installing to $serial ..."
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) {
    throw "adb install failed with exit code $LASTEXITCODE"
}

& $adb -s $serial shell am force-stop com.gamestudios.shengji
& $adb -s $serial shell am start -n com.gamestudios.shengji/com.godot.game.GodotAppLauncher
Write-Host "App launched on emulator."

Start-Sleep -Seconds 8
# Dismiss Android immersive fullscreen hint if shown (landscape 2400x1080).
& $adb -s $serial shell input tap 1702 499 2>$null
Start-Sleep -Seconds 1

if ($Screenshot) {
    New-Item -ItemType Directory -Force -Path $qaDir | Out-Null
    Start-Sleep -Seconds 3
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $png = Join-Path $qaDir "ui-$stamp.png"
    & $adb -s $serial shell screencap -p /sdcard/qa-ui.png
    & $adb -s $serial pull /sdcard/qa-ui.png $png
    Write-Host "Screenshot: $png"
}
