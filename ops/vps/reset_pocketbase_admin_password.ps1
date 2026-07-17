param(
	[string]$Server = "root@109.71.245.162",
	[string]$AdminEmail = "admin@bobux.local",
	[string]$AdminPassword = "kaknazlo35"
)

$ErrorActionPreference = "Stop"

function ConvertTo-BashLiteral {
	param([Parameter(Mandatory = $true)][string]$Value)
	return "'" + ($Value -replace "'", "'\''") + "'"
}

$adminEmailLiteral = ConvertTo-BashLiteral $AdminEmail
$adminPasswordLiteral = ConvertTo-BashLiteral $AdminPassword
$remoteScript = @"
set -euo pipefail
export POCKETBASE_SUPERUSER_EMAIL=$adminEmailLiteral
export POCKETBASE_SUPERUSER_PASSWORD=$adminPasswordLiteral
export PRINT_POCKETBASE_PASSWORD=1
bash /opt/bobux-server/ops/vps/bootstrap_pocketbase_admin.sh
"@

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$localScript = Join-Path $env:TEMP "bobux-reset-pb-admin-$stamp.sh"
$remotePath = "/tmp/bobux-reset-pb-admin-$stamp.sh"
[System.IO.File]::WriteAllText($localScript, $remoteScript, [System.Text.UTF8Encoding]::new($false))

scp $localScript "$Server`:$remotePath"
ssh $Server "bash $remotePath"

Write-Host ""
Write-Host "PocketBase admin is reset."
Write-Host "URL: http://admin.109.71.245.162.nip.io/_/"
Write-Host "Login: $AdminEmail"
Write-Host "Password: $AdminPassword"
