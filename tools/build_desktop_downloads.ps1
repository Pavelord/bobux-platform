[CmdletBinding()]
param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][int]$Build)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godot = Join-Path $root '.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
$stage = Join-Path $root "dist/linux-$Build"
if (Test-Path -LiteralPath $stage) { throw "Linux stage already exists: $stage" }
New-Item -ItemType Directory -Path $stage | Out-Null
& $godot --headless --path $root --export-release Linux (Join-Path $stage 'Bobux.x86_64') *> (Join-Path $root 'dist/release/linux-export.log')
if ($LASTEXITCODE -ne 0) { throw 'Linux export failed; see linux-export.log' }
$compilerCandidates = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe")
$iscc = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 compiler is required to build the Windows installer.' }
& $iscc "/DMyAppVersion=$Version" "/DLauncherBuildDir=$root\launcher_export\windows" "/O$root\dist\release" "$root\tools\installer\bobux_launcher.iss"
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed' }
python -X utf8 "$root/tools/package_linux.py" --stage $stage --version $Version --build $Build
if ($LASTEXITCODE -ne 0) { throw 'Desktop packaging failed' }
