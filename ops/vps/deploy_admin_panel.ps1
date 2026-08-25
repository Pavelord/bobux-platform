param(
	[string]$Server = "root@109.71.245.162",
	[string]$ProjectRoot = "C:\robloxclone",
	[string]$AdminEmail = "admin@bobux.local",
	[string]$AdminPassword = $env:POCKETBASE_SUPERUSER_PASSWORD
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
	throw "Provide -AdminPassword or set POCKETBASE_SUPERUSER_PASSWORD."
}

function ConvertTo-BashLiteral {
	param([Parameter(Mandatory = $true)][string]$Value)
	return "'" + ($Value -replace "'", "'\''") + "'"
}

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$localArchive = Join-Path $env:TEMP "bobux-admin-panel-$stamp.tar.gz"
$localRemoteScript = Join-Path $env:TEMP "bobux-admin-panel-apply-$stamp.sh"
$remoteArchive = "/tmp/bobux-admin-panel-$stamp.tar.gz"
$remoteScript = "/tmp/bobux-admin-panel-apply-$stamp.sh"

Write-Host "=== Packing Bobux admin panel ==="
tar -czf $localArchive -C $ProjectRoot `
	ops/vps/admin.html `
	ops/vps/index.html `
	ops/vps/bobux_nginx.conf `
	ops/vps/bootstrap_pocketbase_admin.sh `
	ops/vps/ADMIN_SETUP.md

Write-Host "=== Uploading to $Server ==="
scp $localArchive "$Server`:$remoteArchive"

$adminEmailLiteral = ConvertTo-BashLiteral $AdminEmail
$adminPasswordLiteral = ConvertTo-BashLiteral $AdminPassword

$remoteCommand = @"
set -euo pipefail
mkdir -p /opt/bobux-server/ops/vps /var/www/bobux
tar -xzf "$remoteArchive" -C /opt/bobux-server
cp /opt/bobux-server/ops/vps/index.html /var/www/bobux/index.html
cp /opt/bobux-server/ops/vps/admin.html /var/www/bobux/admin.html
cp /opt/bobux-server/ops/vps/bobux_nginx.conf /etc/nginx/sites-available/bobux
ln -sf /etc/nginx/sites-available/bobux /etc/nginx/sites-enabled/bobux
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
export POCKETBASE_SUPERUSER_EMAIL=$adminEmailLiteral
export POCKETBASE_SUPERUSER_PASSWORD=$adminPasswordLiteral
export PRINT_POCKETBASE_PASSWORD=1
bash /opt/bobux-server/ops/vps/bootstrap_pocketbase_admin.sh
"@

[System.IO.File]::WriteAllText($localRemoteScript, $remoteCommand, [System.Text.UTF8Encoding]::new($false))
scp $localRemoteScript "$Server`:$remoteScript"

Write-Host "=== Applying on VPS ==="
ssh $Server "bash $remoteScript"

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Bobux admin dashboard: http://109.71.245.162/admin.html"
Write-Host "PocketBase admin console: http://admin.109.71.245.162.nip.io/_/"
Write-Host "PocketBase admin login: $AdminEmail"
Write-Host "PocketBase admin password was supplied securely and is not printed."
