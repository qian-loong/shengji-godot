# Export Android debug APK with gl_compatibility renderer for emulator UI testing.
# Restores the original project.godot rendering settings after export.
# Requires: $env:GODOT_EXE pointing to Godot console binary.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$godotProject = Join-Path $repoRoot "src\godot"
$projectFile = Join-Path $godotProject "project.godot"
$outDir = Join-Path $repoRoot "builds\android"
$outApk = Join-Path $outDir "shengji-debug-emulator.apk"

if (-not $env:GODOT_EXE) {
    Write-Error "GODOT_EXE is not set. Example: `$env:GODOT_EXE='E:\DevTools\Godot\Godot_v4.6.2-stable_win64_console.exe'"
}
if (-not (Test-Path $env:GODOT_EXE)) {
    Write-Error "GODOT_EXE not found: $env:GODOT_EXE"
}

$original = Get-Content $projectFile -Raw
$backup = Join-Path $godotProject "project.godot.bak-emulator-export"
Set-Content -Path $backup -Value $original -NoNewline

function Restore-ProjectGodot {
    if (Test-Path $backup) {
        Set-Content -Path $projectFile -Value (Get-Content $backup -Raw) -NoNewline
        Remove-Item $backup -Force
    }
}

try {
    $patched = $original
    if ($patched -match 'renderer/rendering_method\.mobile=') {
        $patched = [regex]::Replace(
            $patched,
            'renderer/rendering_method\.mobile="[^"]*"',
            'renderer/rendering_method.mobile="gl_compatibility"'
        )
    } else {
        $insert = "renderer/rendering_method=`"mobile`"`r`nrenderer/rendering_method.mobile=`"gl_compatibility`""
        $patched = $patched.Replace(
            'renderer/rendering_method="mobile"',
            $insert
        )
    }

    if ($patched -eq $original) {
        throw "Failed to patch project.godot rendering settings."
    }

    Set-Content -Path $projectFile -Value $patched -NoNewline
    Write-Host "Patched project.godot -> renderer/rendering_method.mobile=gl_compatibility"

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # Godot writes "ObjectDB leaked" to stderr on success; avoid PowerShell NativeCommandError.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $env:GODOT_EXE `
            --headless `
            --path $godotProject `
            --export-debug "Android" `
            $outApk 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $prevEap
    }

    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $outApk)) {
        throw "Godot export failed with exit code $LASTEXITCODE"
    }

    $f = Get-Item $outApk
    Write-Host ""
    Write-Host "Emulator debug APK exported:"
    Write-Host "  $($f.FullName)"
    Write-Host ("  {0:N2} MB" -f ($f.Length / 1MB))
}
finally {
    Restore-ProjectGodot
    Write-Host "Restored project.godot (mobile/Vulkan unchanged for device builds)."
}
