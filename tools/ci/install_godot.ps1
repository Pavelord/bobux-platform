[CmdletBinding()]
param(
	[string]$Version = "4.7",
	[string]$Status = "stable",
	[string]$InstallRoot = "",
	[switch]$SkipTemplates
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
	$InstallRoot = Join-Path $projectRoot ".codex-tools\godot-$Version"
}
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

$releaseName = "$Version-$Status"
if ($releaseName -ne "4.7-stable") {
	throw "Verified checksums are currently pinned only for Godot 4.7-stable."
}
$editorArchiveName = "Godot_v$releaseName" + "_win64.exe.zip"
$templatesArchiveName = "Godot_v$releaseName" + "_export_templates.tpz"
$releaseBase = "https://github.com/godotengine/godot-builds/releases/download/$releaseName"
$editorSha512 = "41645a908eb3181d6f2d1201ed7b6d6f095f6a23aaed8903d5d255277cc8d142814f3e6817f865b3cac142c39b8aff99280091d3bbdaa301517730b3ba0522b9"
$templatesSha512 = "1035dfde4edcc2472bb0c0b9610ce3ee9302642c2b9957e9066372f9f6bb759ab250c8887551a66f0bc5f51bbd9a58bb45e33a0f29844e97615a9b1138c1120e"

function Get-VerifiedDownload(
	[string]$Url,
	[string]$Destination,
	[string]$ExpectedSha512
) {
	if (Test-Path -LiteralPath $Destination -PathType Leaf) {
		$existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash
		if ($existingHash.Equals($ExpectedSha512, [StringComparison]::OrdinalIgnoreCase)) {
			return
		}
		Remove-Item -LiteralPath $Destination -Force
	}

	Write-Host "Downloading $Url"
	& curl.exe --fail --location --retry 5 --retry-delay 3 --output $Destination $Url
	if ($LASTEXITCODE -ne 0) {
		throw "Download failed with exit code $LASTEXITCODE`: $Url"
	}
	$actualHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash
	if (-not $actualHash.Equals($ExpectedSha512, [StringComparison]::OrdinalIgnoreCase)) {
		Remove-Item -LiteralPath $Destination -Force
		throw "SHA512 mismatch for $Destination"
	}
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
$cacheRoot = if ($env:RUNNER_TEMP) {
	Join-Path $env:RUNNER_TEMP "bobux-godot-downloads"
} else {
	Join-Path $env:TEMP "bobux-godot-downloads"
}
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

$consoleName = "Godot_v$releaseName" + "_win64_console.exe"
$editorName = "Godot_v$releaseName" + "_win64.exe"
$consolePath = Join-Path $InstallRoot $consoleName
$editorPath = Join-Path $InstallRoot $editorName
if (
	-not (Test-Path -LiteralPath $consolePath -PathType Leaf) -or
	-not (Test-Path -LiteralPath $editorPath -PathType Leaf)
) {
	$editorArchive = Join-Path $cacheRoot $editorArchiveName
	Get-VerifiedDownload "$releaseBase/$editorArchiveName" $editorArchive $editorSha512
	Expand-Archive -LiteralPath $editorArchive -DestinationPath $InstallRoot -Force
}
if (-not (Test-Path -LiteralPath $consolePath -PathType Leaf) -or
	-not (Test-Path -LiteralPath $editorPath -PathType Leaf)) {
	throw "Godot editor extraction is incomplete in $InstallRoot"
}

# Self-contained mode keeps the runner's export templates inside the cacheable
# installation directory instead of depending on a machine-specific profile.
$selfContainedMarker = Join-Path $InstallRoot "_sc_"
if (-not (Test-Path -LiteralPath $selfContainedMarker)) {
	New-Item -ItemType File -Path $selfContainedMarker -Force | Out-Null
}

if (-not $SkipTemplates) {
	$templateRoot = Join-Path $InstallRoot "editor_data\export_templates\$Version.$Status"
	$requiredTemplates = @(
		"windows_release_x86_32.exe",
		"windows_release_x86_32_console.exe",
		"android_release.apk",
		"android_debug.apk",
		"icudt_godot.dat",
		"version.txt"
	)
	$templatesReady = $true
	foreach ($name in $requiredTemplates) {
		if (-not (Test-Path -LiteralPath (Join-Path $templateRoot $name) -PathType Leaf)) {
			$templatesReady = $false
			break
		}
	}

	if (-not $templatesReady) {
		$templatesArchive = Join-Path $cacheRoot $templatesArchiveName
		Get-VerifiedDownload "$releaseBase/$templatesArchiveName" $templatesArchive $templatesSha512
		$extractRoot = Join-Path $cacheRoot "templates-$releaseName"
		if (Test-Path -LiteralPath $extractRoot) {
			Remove-Item -LiteralPath $extractRoot -Recurse -Force
		}
		New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
		& tar.exe -xf $templatesArchive -C $extractRoot
		if ($LASTEXITCODE -ne 0) {
			throw "Could not extract Godot export templates."
		}
		$sourceRoot = Join-Path $extractRoot "templates"
		New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null
		foreach ($name in $requiredTemplates) {
			$source = Join-Path $sourceRoot $name
			if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
				throw "Required export template is missing from TPZ: $name"
			}
			Copy-Item -LiteralPath $source -Destination (Join-Path $templateRoot $name) -Force
		}
	}
}

$versionOutput = & $consolePath --version
if ($LASTEXITCODE -ne 0 -or (($versionOutput -join "`n") -notmatch [regex]::Escape($Version))) {
	throw "Installed Godot failed its version check."
}

$env:GODOT_BIN = $consolePath
if ($env:GITHUB_ENV) {
	Add-Content -LiteralPath $env:GITHUB_ENV -Value "GODOT_BIN=$consolePath" -Encoding utf8
}
if ($env:GITHUB_OUTPUT) {
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "godot_bin=$consolePath" -Encoding utf8
}
Write-Host "Godot ready: $consolePath"
