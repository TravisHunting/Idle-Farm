<#
.SYNOPSIS
Builds the Windows x64 release executable at build/IdleFarm.exe.
.DESCRIPTION
Runs with Windows PowerShell 5.1 or PowerShell 7 on any host with Godot and
the Windows export templates installed. Finds Godot via -GodotPath,
GODOT_PATH, or godot4/godot/Godot on PATH, in that order.
.EXAMPLE
.\build-game.ps1
.EXAMPLE
.\build-game.ps1 -GodotPath 'C:\Tools\Godot_console.exe'
#>
[CmdletBinding()]
param(
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = $env:GODOT_PATH
}

if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    if (Test-Path -LiteralPath $GodotPath -PathType Leaf) {
        $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    } else {
        $godotCommand = Get-Command -Name $GodotPath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $godotCommand) {
            throw "Godot executable not found: $GodotPath. Set -GodotPath or GODOT_PATH to a valid executable path or command name."
        }
        $GodotPath = $godotCommand.Source
    }
} else {
    foreach ($candidate in @('godot4', 'godot', 'Godot')) {
        $godotCommand = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($godotCommand) {
            $GodotPath = $godotCommand.Source
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($GodotPath)) {
        throw 'Godot was not found. Add Godot to PATH, set GODOT_PATH, or pass -GodotPath with its executable path.'
    }
}

$buildDirectory = Join-Path $PSScriptRoot 'build'
$outputPath = Join-Path $buildDirectory 'IdleFarm.exe'
New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

Write-Host "Using Godot: $GodotPath"
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
