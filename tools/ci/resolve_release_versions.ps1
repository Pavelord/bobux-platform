[CmdletBinding()]
param(
	[string]$Version = "auto",
	[string]$Build = "auto",
	[string]$MobileVersion = "auto",
	[string]$MobileBuild = "auto",
	[string]$LauncherVersion = "current",
	[string]$LauncherBuild = "current",
	[switch]$Production,
	[switch]$AllowRedeploy,
	[string]$ServerIp = "109.71.245.162"
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

function Read-JsonFile([string]$Path) {
	return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-RemoteJson([string]$Url, $Fallback) {
	try {
		return Invoke-RestMethod -Uri $Url -TimeoutSec 20
	} catch {
		Write-Warning "Could not read $Url; using repository metadata."
		return $Fallback
	}
}

function Bump-Patch([string]$Value, [string]$Suffix = "") {
	$base = $Value
	if ($Suffix -ne "" -and $base.EndsWith($Suffix, [StringComparison]::OrdinalIgnoreCase)) {
		$base = $base.Substring(0, $base.Length - $Suffix.Length)
	}
	if ($base -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
		throw "Cannot automatically increment semantic version: $Value"
	}
	return "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)$Suffix"
}

function Resolve-Build([string]$Requested, [int]$Current, [string]$Name) {
	if ($Requested.Equals("auto", [StringComparison]::OrdinalIgnoreCase)) {
		return $Current + 1
	}
	$parsed = 0
	if (-not [int]::TryParse($Requested, [ref]$parsed) -or $parsed -lt 1) {
		throw "$Name must be 'auto' or a positive integer."
	}
	return $parsed
}

$localWindows = Read-JsonFile (Join-Path $projectRoot "game\launcher\latest.json")
$localMobile = Read-JsonFile (Join-Path $projectRoot "mobile\latest.json")
$remoteWindows = Get-RemoteJson "http://$ServerIp/launcher/latest.json" $localWindows
$remoteMobile = Get-RemoteJson "http://$ServerIp/mobile/latest.json" $localMobile

$resolvedVersion = if ($Version.Equals("auto", [StringComparison]::OrdinalIgnoreCase)) {
	Bump-Patch ([string]$remoteWindows.version)
} else {
	$Version
}
$resolvedBuild = Resolve-Build $Build ([int]$remoteWindows.build) "Build"
$resolvedMobileVersion = if ($MobileVersion.Equals("auto", [StringComparison]::OrdinalIgnoreCase)) {
	Bump-Patch ([string]$remoteMobile.version) "-mobile"
} else {
	$MobileVersion
}
$resolvedMobileBuild = Resolve-Build $MobileBuild ([int]$remoteMobile.build) "MobileBuild"
$resolvedLauncherVersion = if ($LauncherVersion.Equals("current", [StringComparison]::OrdinalIgnoreCase)) {
	[string]$localWindows.launcher.version
} else {
	$LauncherVersion
}
$resolvedLauncherBuild = if ($LauncherBuild.Equals("current", [StringComparison]::OrdinalIgnoreCase)) {
	[int]$localWindows.launcher.build
} else {
	Resolve-Build $LauncherBuild 0 "LauncherBuild"
}

if ($resolvedVersion -notmatch '^\d+\.\d+\.\d+$') {
	throw "Version must match MAJOR.MINOR.PATCH."
}
if ($resolvedMobileVersion -notmatch '^\d+\.\d+\.\d+-mobile$') {
	throw "MobileVersion must match MAJOR.MINOR.PATCH-mobile."
}
if ($resolvedLauncherVersion -notmatch '^\d+\.\d+\.\d+$') {
	throw "LauncherVersion must match MAJOR.MINOR.PATCH."
}
if ($Production -and -not $AllowRedeploy) {
	if ($resolvedBuild -le [int]$remoteWindows.build) {
		throw "Production build $resolvedBuild must be newer than deployed build $($remoteWindows.build)."
	}
	if ($resolvedMobileBuild -le [int]$remoteMobile.build) {
		throw "Production mobile build $resolvedMobileBuild must be newer than deployed build $($remoteMobile.build)."
	}
}

$resolved = [ordered]@{
	RELEASE_VERSION = $resolvedVersion
	RELEASE_BUILD = $resolvedBuild
	MOBILE_VERSION = $resolvedMobileVersion
	MOBILE_BUILD = $resolvedMobileBuild
	LAUNCHER_VERSION = $resolvedLauncherVersion
	LAUNCHER_BUILD = $resolvedLauncherBuild
}
foreach ($entry in $resolved.GetEnumerator()) {
	Write-Host "$($entry.Key)=$($entry.Value)"
	if ($env:GITHUB_ENV) {
		Add-Content -LiteralPath $env:GITHUB_ENV -Value "$($entry.Key)=$($entry.Value)" -Encoding utf8
	}
	if ($env:GITHUB_OUTPUT) {
		Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$($entry.Key.ToLowerInvariant())=$($entry.Value)" -Encoding utf8
	}
}
