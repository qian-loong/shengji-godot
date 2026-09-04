# Export Android debug APK for emulator UI testing.
#
# Uses the dedicated "Android-Emulator" export preset, which carries the custom
# feature tag `emulator`. project.godot maps that tag to the GL renderer:
#
#     renderer/rendering_method="mobile"                  # device build: Vulkan Mobile
#     renderer/rendering_method.emulator="gl_compatibility"
#
# The preset also enables the x86_64 ABI, which the device preset omits — most
# PC emulator images are x86_64.
#
# This script no longer rewrites project.godot. The previous version patched the
# renderer setting in place and restored it afterwards; once gl_compatibility
# became the committed value that patch became a no-op and the script aborted on
# its own "patch did not change anything" guard, taking verify_ui_emulator.ps1
# down with it.
#
# Requires: $env:GODOT_EXE pointing to the Godot console binary.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$godotProject = Join-Path $repoRoot "src\godot"
$outDir = Join-Path $repoRoot "builds\android"
$outApk = Join-Path $outDir "shengji-debug-emulator.apk"
$presetName = "Android-Emulator"

if (-not $env:GODOT_EXE) {
    Write-Error "GODOT_EXE is not set. Example: `$env:GODOT_EXE='E:\DevTools\Godot\Godot_v4.6.2-stable_win64_console.exe'"
}
if (-not (Test-Path $env:GODOT_EXE)) {
    Write-Error "GODOT_EXE not found: $env:GODOT_EXE"
}

# Fail loudly if the preset is missing rather than silently exporting the device
# build under the emulator filename.
$presetFile = Join-Path $godotProject "export_presets.cfg"
if (-not (Select-String -Path $presetFile -SimpleMatch "name=`"$presetName`"" -Quiet)) {
    throw "Export preset '$presetName' not found in $presetFile"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Godot writes "ObjectDB leaked" to stderr on success; avoid PowerShell NativeCommandError.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $env:GODOT_EXE `
        --headless `
        --path $godotProject `
        --export-debug $presetName `
        $outApk 2>&1 | Out-Null
} finally {
    $ErrorActionPreference = $prevEap
}

if ($LASTEXITCODE -ne 0 -and -not (Test-Path $outApk)) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

$f = Get-Item $outApk
Write-Host ""
Write-Host "Emulator debug APK exported (preset: $presetName, renderer: gl_compatibility):"
Write-Host "  $($f.FullName)"
Write-Host ("  {0:N2} MB" -f ($f.Length / 1MB))
