<#
.SYNOPSIS
Exports a local Bobux build into a fresh artifact directory without publishing it.
.EXAMPLE
./tools/build_local.ps1 -Preset Android -DryRun
.EXAMPLE
./tools/build_local.ps1 -Project Launcher -ArtifactRoot D:\Bobux_Artifacts\local
#>
[CmdletBinding()]
param(
    [ValidateSet('Game', 'Launcher')]
    [string]$Project = 'Game',

    [ValidateSet('Windows Desktop', 'Android', 'Linux')]
    [string]$Preset = 'Windows Desktop',

    [string]$ArtifactRoot = '',
    [string]$GodotBin = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = if ($Project -eq 'Launcher') { Join-Path $repoRoot 'launcher' } else { $repoRoot }
if ($Project -eq 'Launcher' -and $Preset -ne 'Windows Desktop') {
    throw 'The launcher currently has only the Windows Desktop export preset.'
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project not found: $projectRoot"
}

function Get-AbsolutePath([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Value))
}

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $prefix = $Parent.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $Child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path must stay inside its selected root: $Child"
    }
}

function Assert-NoReparsePoint([string]$Path) {
    # Do not follow a junction/symlink into a different output tree.
    $current = $Path
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Artifact paths may not pass through a reparse point: $current"
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}

if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = $env:BOBUX_ARTIFACT_ROOT }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $ArtifactRoot = if (Test-Path -LiteralPath 'D:\' -PathType Container) {
        'D:\Bobux_Artifacts\local'
    } else { Join-Path $repoRoot '.dist/local' }
}
$artifactPath = Get-AbsolutePath $ArtifactRoot
if (Test-Path -LiteralPath $artifactPath -PathType Leaf) { throw "Artifact root is a file: $artifactPath" }
Assert-NoReparsePoint $artifactPath

if ([string]::IsNullOrWhiteSpace($GodotBin)) { $GodotBin = $env:GODOT_BIN }
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = Join-Path $repoRoot '.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
}
$godotPath = Get-AbsolutePath $GodotBin
$godotExists = Test-Path -LiteralPath $godotPath -PathType Leaf
if (-not $DryRun -and -not $godotExists) {
    throw "Godot executable not found. Supply -GodotBin or GODOT_BIN: $godotPath"
}

$platform = switch ($Preset) { 'Windows Desktop' { 'windows' } 'Android' { 'android' } 'Linux' { 'linux' } }
$filename = if ($Project -eq 'Launcher') { 'BobuxLauncher.exe' } else {
    switch ($Preset) { 'Windows Desktop' { 'Bobux.exe' } 'Android' { 'Bobux.apk' } 'Linux' { 'Bobux.x86_64' } }
}
$runName = '{0}-{1}-{2}-{3}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Project.ToLowerInvariant(), $platform, [Guid]::NewGuid().ToString('N')
$runDir = Get-AbsolutePath (Join-Path $artifactPath $runName)
$outputPath = Get-AbsolutePath (Join-Path $runDir $filename)
$logPath = Get-AbsolutePath (Join-Path $runDir 'export.log')
Assert-ChildPath $artifactPath $runDir
Assert-ChildPath $runDir $outputPath
Assert-ChildPath $runDir $logPath
if (Test-Path -LiteralPath $runDir) { throw "Refusing to reuse an existing export directory: $runDir" }
$godotArguments = @('--headless', '--path', $projectRoot, '--export-release', $Preset, $outputPath)
$plan = [ordered]@{
    dry_run = [bool]$DryRun
    project = $Project
    preset = $Preset
    godot = $godotPath
    godot_exists = [bool]$godotExists
    arguments = $godotArguments
    artifact_root = $artifactPath
    run_directory = $runDir
    output = $outputPath
    log = $logPath
}
if ($DryRun) {
    # Review only: do not create directories, alter presets or invoke Godot.
    [pscustomobject]$plan
    return
}

New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null
Assert-NoReparsePoint $artifactPath
New-Item -ItemType Directory -Path $runDir | Out-Null
Assert-NoReparsePoint $runDir
if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $logPath)) {
    throw "Refusing to overwrite an export or log in $runDir"
}
$stream = [IO.File]::Open($logPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
$runtimeError = $false
try {
    $writer.WriteLine(($plan | ConvertTo-Json -Depth 4))
    & $godotPath @godotArguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $writer.WriteLine($line)
        Write-Host $line
        if ($line -match '^(SCRIPT ERROR:|ERROR:|CrashHandler:)') { $runtimeError = $true }
    }
    $exportExit = $LASTEXITCODE
    $writer.WriteLine("Godot exit code: $exportExit")
    if ($exportExit -ne 0 -or $runtimeError) { throw "Godot export failed; see $logPath" }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or (Get-Item -LiteralPath $outputPath).Length -eq 0) {
        throw "Godot returned without a non-empty export: $outputPath"
    }
} catch {
    $writer.WriteLine("Export failed: $($_.Exception.Message)")
    throw
} finally {
    $writer.Dispose()
}
Write-Host "Local build: $outputPath"
Write-Host "Export log: $logPath"
