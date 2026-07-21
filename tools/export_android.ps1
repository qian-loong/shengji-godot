<#
.SYNOPSIS
    Export Godot project to Android APK

.DESCRIPTION
    Exports the Godot project to Android with configurable renderer options.

.PARAMETER Renderer
    Renderer mode: 'mobile' (Vulkan, default) or 'compat' (OpenGL ES 3 for emulators)

.PARAMETER GodotExecutable
    Path to Godot executable (defaults to $env:GODOT_EXE)

.PARAMETER ProjectPath
    Path to Godot project directory (defaults to relative path: tools/../src/godot)

.PARAMETER OutputPath
    Output APK path (defaults to builds/android/shengji-debug-<renderer>.apk)

.EXAMPLE
    .\tools\export_android.ps1
    Export with Vulkan renderer (mobile mode)

.EXAMPLE
    .\tools\export_android.ps1 -Renderer compat
    Export with OpenGL ES 3 renderer (emulator mode)

.EXAMPLE
    .\tools\export_android.ps1 -GodotExecutable "C:\Godot\Godot.exe"
    Override Godot executable path

.NOTES
    Environment Variables:
    - GODOT_EXE: Path to Godot executable (required if not passed as parameter)

    Output Locations:
    - Mobile (Vulkan): builds/android/shengji-debug-mobile.apk
    - Compat (OpenGL): builds/android/shengji-debug-compat.apk
#>

param(
    [ValidateSet('mobile', 'compat')]
    [string]$Renderer = 'mobile',

    [string]$GodotExecutable = $env:GODOT_EXE,

    [string]$ProjectPath = (Join-Path $PSScriptRoot "..\src\godot"),

    [string]$OutputPath = ""
)

# Banner
$rendererName = if ($Renderer -eq 'mobile') { 'Mobile (Vulkan)' } else { 'Compatibility (OpenGL ES 3)' }
Write-Host "=== Godot Android Export: $rendererName ===" -ForegroundColor Cyan
Write-Host ""

# Validate Godot executable
if (-not $GodotExecutable) {
    Write-Host "ERROR: GODOT_EXE environment variable is not set." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set the GODOT_EXE environment variable to your Godot executable path:" -ForegroundColor Yellow
    Write-Host "  Example: `$env:GODOT_EXE = 'C:\Path\To\Godot_v4.6.2-stable_win64_console.exe'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Or pass it as a parameter:" -ForegroundColor Yellow
    Write-Host "  .\tools\export_android.ps1 -GodotExecutable 'C:\Path\To\Godot.exe'" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

if (-not (Test-Path $GodotExecutable)) {
    Write-Host "ERROR: Godot executable not found at: $GodotExecutable" -ForegroundColor Red
    exit 1
}

# Resolve paths
$ProjectPath = Resolve-Path $ProjectPath
$projectFile = Join-Path $ProjectPath "project.godot"

if (-not (Test-Path $projectFile)) {
    Write-Host "ERROR: project.godot not found at: $ProjectPath" -ForegroundColor Red
    exit 1
}

# Set default output path if not specified
if (-not $OutputPath) {
    $buildsDir = Join-Path $PSScriptRoot "..\builds\android"
    New-Item -ItemType Directory -Force -Path $buildsDir | Out-Null
    $OutputPath = Join-Path $buildsDir "shengji-debug-$Renderer.apk"
    $OutputPath = Resolve-Path $buildsDir | Join-Path -ChildPath "shengji-debug-$Renderer.apk"
}

Write-Host "Godot:   $GodotExecutable" -ForegroundColor Gray
Write-Host "Project: $ProjectPath" -ForegroundColor Gray
Write-Host "Output:  $OutputPath" -ForegroundColor Gray
Write-Host "Renderer: $rendererName" -ForegroundColor Gray
Write-Host ""

# Handle compatibility mode (temporarily switch renderer)
$needsRestore = $false
$backupPath = ""

if ($Renderer -eq 'compat') {
    Write-Host "Switching to gl_compatibility renderer..." -ForegroundColor Yellow

    $backupPath = Join-Path $ProjectPath "project.godot.bak"
    Copy-Item $projectFile $backupPath -Force

    $content = Get-Content $projectFile -Raw
    $content = $content -replace 'rendering/renderer/rendering_method="mobile"', 'rendering/renderer/rendering_method="gl_compatibility"'
    Set-Content $projectFile $content -NoNewline

    $needsRestore = $true
    Write-Host "Renderer switched (backup saved)" -ForegroundColor Green
    Write-Host ""
}

# Export
Write-Host "Exporting Android APK..." -ForegroundColor Cyan

try {
    & $GodotExecutable `
        --headless `
        --path $ProjectPath `
        --export-debug "Android" `
        $OutputPath

    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "SUCCESS: APK exported to $OutputPath" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "ERROR: Export failed with code $exitCode" -ForegroundColor Red
        Write-Host "Check Godot editor for configuration issues (Project -> Export -> Android)" -ForegroundColor Yellow
    }
} finally {
    # Restore original renderer if needed
    if ($needsRestore -and (Test-Path $backupPath)) {
        Write-Host ""
        Write-Host "Restoring original renderer configuration..." -ForegroundColor Yellow
        Move-Item $backupPath $projectFile -Force
        Write-Host "Configuration restored" -ForegroundColor Green
    }
}

exit $exitCode
