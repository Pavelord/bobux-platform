param(
    [string]$InputDir = (Join-Path $env:USERPROFILE 'Downloads'),
    [string]$OutputDir = '',
    [string]$MapsFile = (Join-Path $PSScriptRoot 'attached_maps_2026-10-03.txt'),
    [switch]$ReuseOracle
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$oracleProject = Join-Path $PSScriptRoot 'rbxdom_oracle'
$oracleExe = Join-Path $oracleProject 'target\release\rbxdom_place_oracle.exe'
$runner = Join-Path $PSScriptRoot 'run_suite.py'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot '.codex-tmp\rbxdom_diff_20261003'
}

$cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if ($cargoCommand) {
	$cargoExe = $cargoCommand.Source
} else {
	# Rustup installs Cargo here; the current process PATH can predate its install.
	$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
	if (-not (Test-Path -LiteralPath $cargoExe -PathType Leaf)) {
		throw 'Rust Cargo is required. Install the stable Rust toolchain from https://rust-lang.org/tools/install/ and rerun this script.'
	}
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'Python is required but was not found on PATH.'
}

Push-Location $oracleProject
try {
    & $cargoExe build --locked --release
    if ($LASTEXITCODE -ne 0) {
        throw "rbx-dom oracle build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$arguments = @(
    $runner,
    '--input-dir', (Resolve-Path -LiteralPath $InputDir).Path,
    '--oracle-exe', $oracleExe,
    '--output-dir', $OutputDir,
    '--maps-file', (Resolve-Path -LiteralPath $MapsFile).Path
)
if ($ReuseOracle) {
    $arguments += '--reuse-oracle'
}

python @arguments
exit $LASTEXITCODE
