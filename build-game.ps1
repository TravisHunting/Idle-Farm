<#
.SYNOPSIS
Builds the Windows x64 release executable at build/IdleFarm.exe.
.EXAMPLE
.\build-game.ps1
.EXAMPLE
.\build-game.ps1 -GodotPath 'D:\Tools\Godot_v4.7.2-stable_win64_console.exe'
#>
[CmdletBinding()]
param(
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath. Pass -GodotPath with the path to your Godot console executable."
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$buildDirectory = Join-Path $PSScriptRoot 'build'
$outputPath = Join-Path $buildDirectory 'IdleFarm.exe'
New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

Write-Host 'Importing project resources...'
& $GodotPath --headless --path $PSScriptRoot --editor --import
if ($LASTEXITCODE -ne 0) {
    throw "Godot import failed with exit code $LASTEXITCODE."
}

Write-Host 'Exporting Windows release (requires matching Godot export templates)...'
& $GodotPath --headless --path $PSScriptRoot --export-release 'Windows Desktop' $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE. Install matching templates via Editor > Manage Export Templates."
}
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "Godot did not produce the executable: $outputPath"
}

Write-Host "Built: $outputPath"
