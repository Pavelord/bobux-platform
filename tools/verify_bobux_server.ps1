<#
.SYNOPSIS
  Checks that the public Bobux VPS routes point to the Bobux web/API stack.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\robloxclone\tools\verify_bobux_server.ps1
#>
[CmdletBinding()]
param(
	[string]$ServerIp = "109.71.245.162"
)

$ErrorActionPreference = "Stop"

function Invoke-BobuxRequest {
	param(
		[string]$Url,
		[string]$Method = "GET",
		[object]$Body = $null,
		[hashtable]$Headers = @{}
	)

	try {
		$params = @{
			Uri             = $Url
			Method          = $Method
			TimeoutSec      = 20
			UseBasicParsing = $true
			Headers         = $Headers
		}
		if ($null -ne $Body) {
			$params.Body = ($Body | ConvertTo-Json -Compress -Depth 8)
			$params.ContentType = "application/json"
		}
		$response = Invoke-WebRequest @params
		return @{
			ok      = $true
			status  = [int]$response.StatusCode
			content = [string]$response.Content
			headers = $response.Headers
		}
	} catch {
		$status = 0
		$content = ""
		$headers = @{}
		if ($_.Exception.Response) {
			$status = [int]$_.Exception.Response.StatusCode
			$headers = $_.Exception.Response.Headers
			try {
				$reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
				$content = $reader.ReadToEnd()
			} catch {
				$content = ""
			}
		}
		return @{
			ok      = $false
			status  = $status
			content = $content
			headers = $headers
			error   = $_.Exception.Message
		}
	}
}

function Assert-Status {
	param(
		[string]$Name,
		[string]$Url,
		[int[]]$AllowedStatuses
	)
	$result = Invoke-BobuxRequest -Url $Url
	if ($AllowedStatuses -notcontains [int]$result.status) {
		throw "$Name failed: HTTP $($result.status) at $Url"
	}
	Write-Host "[OK] $Name -> HTTP $($result.status)" -ForegroundColor Green
	return $result
}

Write-Host "Checking Bobux VPS at $ServerIp..." -ForegroundColor Cyan

Assert-Status "Landing page" "http://$ServerIp/" @(200) | Out-Null
$manifest = Assert-Status "Launcher manifest" "http://$ServerIp/launcher/latest.json" @(200)
Assert-Status "Downloads manifest mirror" "http://$ServerIp/downloads/latest.json" @(200) | Out-Null
$mobileManifest = Assert-Status "Mobile manifest" "http://$ServerIp/mobile/latest.json" @(200)
$mobileCacheControl = [string]$mobileManifest.headers['Cache-Control']
if ($mobileCacheControl -notmatch '(?i)no-store') {
	throw "Mobile manifest is cacheable ($mobileCacheControl); clients may keep seeing an old build number."
}
$mobileJson = $mobileManifest.content | ConvertFrom-Json
if (-not $mobileJson.android.build -or -not $mobileJson.android.versioned_apk_url) {
	throw "Mobile manifest is missing the Android build or versioned APK URL."
}
$mobileApk = Invoke-BobuxRequest -Url ([string]$mobileJson.android.versioned_apk_url) -Method "HEAD"
if ([int]$mobileApk.status -ne 200) {
	throw "Versioned Android APK failed: HTTP $($mobileApk.status) at $($mobileJson.android.versioned_apk_url)"
}
$mobileApkLengthHeader = @($mobileApk.headers['Content-Length'])
$mobileApkSize = [long]$mobileApkLengthHeader[0]
if ($mobileApkSize -lt 10MB) {
	throw "Versioned Android APK is undersized ($mobileApkSize bytes)."
}
$stableApkUrl = [string]$mobileJson.android.apk_url
if ([string]::IsNullOrWhiteSpace($stableApkUrl)) {
	throw "Mobile manifest is missing the stable Android APK URL."
}
$stableApk = Invoke-BobuxRequest -Url $stableApkUrl -Method "HEAD"
if ([int]$stableApk.status -ne 200) {
	throw "Stable Android APK failed: HTTP $($stableApk.status) at $stableApkUrl"
}
$stableApkLengthHeader = @($stableApk.headers['Content-Length'])
$stableApkSize = [long]$stableApkLengthHeader[0]
if ($stableApkSize -ne $mobileApkSize) {
	throw "Stable APK size ($stableApkSize bytes) does not match the versioned build ($mobileApkSize bytes)."
}
Write-Host "[OK] Android build $($mobileJson.android.build): $mobileApkSize bytes, manifests are no-store" -ForegroundColor Green

$manifestJson = $manifest.content | ConvertFrom-Json
if (-not $manifestJson.version -or -not $manifestJson.zip_url) {
	throw "Launcher manifest is missing version or zip_url."
}
Write-Host "[OK] Manifest version $($manifestJson.version) build $($manifestJson.build)" -ForegroundColor Green

$health = Assert-Status "Bobux API health" "http://$ServerIp/api/health" @(200)
$healthJson = $health.content | ConvertFrom-Json
if ($true -ne $healthJson.ok) {
	throw "Public /api/health is not Bobux API. Response was: $($health.content)"
}
Write-Host "[OK] /api is routed to Bobux API" -ForegroundColor Green

$auth = Invoke-BobuxRequest `
	-Url "http://$ServerIp/api/auth/v1/token?grant_type=password" `
	-Method "POST" `
	-Headers @{ Accept = "application/json" } `
	-Body @{ email = "bobux-healthcheck@example.invalid"; password = "bad-password" }

if (@(200, 400, 401, 422, 429) -notcontains [int]$auth.status) {
	throw "Auth route is not reachable through Bobux API. HTTP $($auth.status)"
}
Write-Host "[OK] Auth route reachable -> HTTP $($auth.status)" -ForegroundColor Green

Write-Host "Bobux VPS routing looks good." -ForegroundColor Green

$desktop = (Assert-Status "Desktop downloads" "http://$ServerIp/downloads/desktop-latest.json" @(200)).content | ConvertFrom-Json
foreach ($platform in @('windows', 'linux')) {
    $artifact = $desktop.platforms.$platform
    if (-not $artifact.url -or $artifact.size -lt 1MB) { throw "Invalid $platform download manifest" }
    $head = Invoke-WebRequest -UseBasicParsing -Method Head -Uri "http://$ServerIp$($artifact.url)" -TimeoutSec 20
    $contentLength = @($head.Headers['Content-Length'])[0]
    if ([long]$contentLength -ne [long]$artifact.size) { throw "$platform download size mismatch" }
    Write-Host "[OK] $platform download: $($artifact.url)"
}
if ($desktop.platforms.linux.url -notlike '*.AppImage') { throw 'Linux AppImage not published' }
if ($desktop.platforms.windows.url -notlike '*Setup.exe') { throw 'Windows Setup not published' }
