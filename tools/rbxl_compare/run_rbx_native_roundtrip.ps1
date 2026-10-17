param(
	[string]$InputDir = (Join-Path $env:USERPROFILE 'Downloads'),
	[string]$MapsFile = (Join-Path $PSScriptRoot 'attached_maps_2026-10-03.txt'),
	[string]$NativeRoot = '',
	[string]$OutputFile = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$nativeCommit = 'cc50d54b1528ac7ffc470ce232a45295ca5972aa'

if ([string]::IsNullOrWhiteSpace($NativeRoot)) {
	$NativeRoot = Join-Path $repoRoot '.codex-tmp\external\rbx-native'
}
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
	$OutputFile = Join-Path $repoRoot '.codex-tmp\rbx_native_roundtrip_20261003\summary.json'
}

$cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if ($cargoCommand) {
	$cargoExe = $cargoCommand.Source
} else {
	$cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
	if (-not (Test-Path -LiteralPath $cargoExe -PathType Leaf)) {
		throw 'Rust Cargo is required. Install the stable Rust toolchain from https://rust-lang.org/tools/install/ and rerun this script.'
	}
}

if (-not (Test-Path -LiteralPath (Join-Path $NativeRoot 'Cargo.toml') -PathType Leaf)) {
	$nativeParent = Split-Path -Parent $NativeRoot
	New-Item -ItemType Directory -Path $nativeParent -Force | Out-Null
	& git clone --filter=blob:none --no-checkout --sparse https://github.com/chteau/rbx-native.git $NativeRoot
	if ($LASTEXITCODE -ne 0) {
		throw "Could not clone rbx-native (git exit code $LASTEXITCODE)."
	}
	& git -C $NativeRoot fetch --depth 1 origin $nativeCommit
	if ($LASTEXITCODE -ne 0) {
		throw "Could not fetch pinned rbx-native commit $nativeCommit."
	}
	& git -C $NativeRoot sparse-checkout set --no-cone Cargo.toml Cargo.lock 'crates/*/Cargo.toml' 'crates/*/src/**' 'assets/API-Dump.json' 'assets/reflection-defaults.json'
	if ($LASTEXITCODE -ne 0) {
		throw "Could not configure the rbx-native sparse checkout (git exit code $LASTEXITCODE)."
	}
	& git -C $NativeRoot checkout --detach $nativeCommit
	if ($LASTEXITCODE -ne 0) {
		throw "Could not check out pinned rbx-native commit $nativeCommit."
	}
}

function Invoke-RbxDumpRoundtrip([string]$Executable, [string]$MapPath, [string]$WorkDir, [string]$LogStem) {
	$stdoutPath = Join-Path $WorkDir ($LogStem + '.stdout.txt')
	$stderrPath = Join-Path $WorkDir ($LogStem + '.stderr.txt')
	$argumentList = @('--roundtrip', ('"{0}"' -f $MapPath))
	$process = Start-Process -FilePath $Executable -ArgumentList $argumentList -Wait -PassThru -NoNewWindow `
		-RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
	$outputParts = [System.Collections.Generic.List[string]]::new()
	if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
		$stdout = Get-Content -LiteralPath $stdoutPath -Raw
		if (-not [string]::IsNullOrWhiteSpace($stdout)) { $outputParts.Add($stdout.TrimEnd()) }
	}
	if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
		$stderr = Get-Content -LiteralPath $stderrPath -Raw
		if (-not [string]::IsNullOrWhiteSpace($stderr)) { $outputParts.Add($stderr.TrimEnd()) }
	}
	return [pscustomobject]@{
		exit_code = $process.ExitCode
		output = ($outputParts -join "`n")
	}
}

function Get-RoundtripFormatStatus([string]$Output, [string]$FormatName) {
	$label = if ($FormatName -eq 'binary') { 'binary round-trip (rbx_binary)' } else { 'xml round-trip (rbx_xml)' }
	if ($Output -match [regex]::Escape("${label}: OK")) { return 'ok' }
	if ($Output -match [regex]::Escape("${label}: FAIL")) { return 'failed' }
	return 'not_reported'
}

function Get-RoundtripFailureKind([string]$Output) {
	if ($Output -match 'x: NaN') { return 'nan_equality_false_positive' }
	if ($Output -match 'CanvasSize is missing a value') { return 'binary_writer_rejects_partial_class_property' }
	if ($Output -match 'property `LinkedSource` changed: expected Content\(None\), actual String\(""\)') { return 'content_none_vs_empty_string' }
	if ($Output -match 'no XML encoder for the `Unknown` property kind') { return 'unknown_variant_xml_writer_unsupported' }
	if ($Output -match 'expected Unknown \{ type_id:') { return 'unknown_variant_binary_roundtrip_loss' }
	if ($Output -match ': FAIL') { return 'other_roundtrip_failure' }
	return $null
}

$checkedOutCommit = (& git -C $NativeRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
	throw "Could not read the rbx-native checkout at $NativeRoot."
}
if ($checkedOutCommit -ne $nativeCommit) {
	throw "Expected rbx-native commit $nativeCommit but found $checkedOutCommit. Set NativeRoot to the matching checkout to keep the comparison reproducible."
}

if (-not (Test-Path -LiteralPath $MapsFile -PathType Leaf)) {
	throw "Map manifest not found: $MapsFile"
}
if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
	throw "Map input directory not found: $InputDir"
}

Push-Location $NativeRoot
try {
	& $cargoExe build --locked --release -p rbx_parser_cli --bin rbxdump
	if ($LASTEXITCODE -ne 0) {
		throw "rbx-native rbxdump build failed with exit code $LASTEXITCODE."
	}
}
finally {
	Pop-Location
}

$rbxdumpExe = Join-Path $NativeRoot 'target\release\rbxdump.exe'
if (-not (Test-Path -LiteralPath $rbxdumpExe -PathType Leaf)) {
	throw "Built rbxdump executable not found: $rbxdumpExe"
}

$mapNames = @(Get-Content -LiteralPath $MapsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
$results = [System.Collections.Generic.List[object]]::new()
$outputParent = Split-Path -Parent $OutputFile
$workDir = Join-Path $outputParent 'native_work'
$sanitizedDir = Join-Path $workDir 'sanitized_xml'
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
	throw 'Python is required for the shared, narrow legacy-XML oracle normalization.'
}
$pythonExe = $pythonCommand.Source
$sanitizerModuleDir = $PSScriptRoot
$sanitizeCode = "import json,sys; from pathlib import Path; sys.path.insert(0, r'$sanitizerModuleDir'); from xml_compat import sanitize_legacy_xml; print(json.dumps(sanitize_legacy_xml(Path(sys.argv[1]), Path(sys.argv[2]))))"
$xmlProbeCode = "import sys; from pathlib import Path; sys.path.insert(0, r'$sanitizerModuleDir'); from xml_compat import is_legacy_xml; print('true' if is_legacy_xml(Path(sys.argv[1])) else 'false')"
for ($index = 0; $index -lt $mapNames.Count; $index++) {
	$mapName = $mapNames[$index]
	$mapPath = Join-Path $InputDir $mapName
	if (-not (Test-Path -LiteralPath $mapPath -PathType Leaf)) {
		$results.Add([pscustomobject]@{
			file = $mapName
			status = 'missing_input'
			load_status = 'missing_input'
			exit_code = $null
			binary_roundtrip = 'not_run'
		xml_roundtrip = 'not_run'
			failure_kind = $null
			sha256 = $null
			output = ''
		})
		Write-Host ("[{0}/{1}] {2} -> missing_input" -f ($index + 1), $mapNames.Count, $mapName)
		continue
	}

	$sha256 = (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash.ToLowerInvariant()
	$original = Invoke-RbxDumpRoundtrip $rbxdumpExe $mapPath $workDir ("map_{0:D2}_original" -f ($index + 1))
	$exitCode = $original.exit_code
	$status = if ($exitCode -eq 0) { 'roundtrip_ok' } elseif ($exitCode -eq 2) { 'parse_error' } else { 'roundtrip_mismatch' }
	$sanitizedRetry = $null
	$isLegacyXml = $false
	if ($exitCode -eq 2) {
		$xmlProbeOutput = & $pythonExe -c $xmlProbeCode $mapPath
		if ($LASTEXITCODE -ne 0) {
			throw "Could not inspect input format for '$mapName'."
		}
		$isLegacyXml = ($xmlProbeOutput | Out-String).Trim() -eq 'true'
	}
	if ($exitCode -eq 2 -and $isLegacyXml) {
		$sanitizedPath = Join-Path $sanitizedDir ("{0:D2}_{1}" -f ($index + 1), [System.IO.Path]::GetFileName($mapPath))
		$sanitizerOutput = & $pythonExe -c $sanitizeCode $mapPath $sanitizedPath
		if ($LASTEXITCODE -ne 0) {
			throw "Legacy XML normalization failed for '$mapName' with exit code $LASTEXITCODE."
		}
		$sanitization = ($sanitizerOutput | Out-String | ConvertFrom-Json)
		$retry = Invoke-RbxDumpRoundtrip $rbxdumpExe $sanitizedPath $workDir ("map_{0:D2}_sanitized" -f ($index + 1))
		$retryStatus = if ($retry.exit_code -eq 0) { 'roundtrip_ok' } elseif ($retry.exit_code -eq 2) { 'parse_error' } else { 'roundtrip_mismatch' }
		$sanitizedRetry = [pscustomobject]@{
			status = $retryStatus
			exit_code = $retry.exit_code
			input = $sanitizedPath
			sanitization = $sanitization
			output = $retry.output
		}
		if ($retry.exit_code -eq 0) { $status = 'roundtrip_ok_sanitized' }
		elseif ($retry.exit_code -eq 1) { $status = 'roundtrip_mismatch_sanitized' }
		else { $status = 'parse_error_sanitized' }
	}
	$effectiveOutput = if ($sanitizedRetry) { $sanitizedRetry.output } else { $original.output }
	$loadStatus = if ($exitCode -ne 2) { 'loaded_original' } elseif ($sanitizedRetry -and $sanitizedRetry.exit_code -ne 2) { 'loaded_after_oracle_sanitization' } else { 'parse_failed' }
	$results.Add([pscustomobject]@{
		file = $mapName
		status = $status
		load_status = $loadStatus
		exit_code = $exitCode
		binary_roundtrip = Get-RoundtripFormatStatus $effectiveOutput 'binary'
		xml_roundtrip = Get-RoundtripFormatStatus $effectiveOutput 'xml'
		failure_kind = Get-RoundtripFailureKind $effectiveOutput
		sha256 = $sha256
		output = $original.output
		sanitized_retry = $sanitizedRetry
	})
	Write-Host ("[{0}/{1}] {2} -> {3}" -f ($index + 1), $mapNames.Count, $mapName, $status)
}

$okCount = @($results | Where-Object { $_.status -eq 'roundtrip_ok' -or $_.status -eq 'roundtrip_ok_sanitized' }).Count
$loadedOriginalCount = @($results | Where-Object { $_.load_status -eq 'loaded_original' }).Count
$loadedSanitizedCount = @($results | Where-Object { $_.load_status -eq 'loaded_after_oracle_sanitization' }).Count
$parseFailedCount = @($results | Where-Object { $_.load_status -eq 'parse_failed' }).Count
$report = [ordered]@{
	generated_utc = [DateTime]::UtcNow.ToString('o')
	project = 'chteau/rbx-native'
	commit = $checkedOutCommit
	cargo_version = (& $cargoExe --version | Out-String).Trim()
	input_directory = (Resolve-Path -LiteralPath $InputDir).Path
	manifest = (Resolve-Path -LiteralPath $MapsFile).Path
	map_count = $results.Count
	loaded_original = $loadedOriginalCount
	loaded_after_oracle_sanitization = $loadedSanitizedCount
	parse_failed = $parseFailedCount
	passed = $okCount
	failed = $results.Count - $okCount
	results = @($results)
}

New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
Write-Host ("rbx-native round-trip: {0}/{1} passed. Report: {2}" -f $okCount, $results.Count, $OutputFile)
if ($okCount -ne $results.Count) {
	exit 1
}
