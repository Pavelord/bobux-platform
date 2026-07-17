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
		}
	} catch {
		$status = 0
		$content = ""
		if ($_.Exception.Response) {
			$status = [int]$_.Exception.Response.StatusCode
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
