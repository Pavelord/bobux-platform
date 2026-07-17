<#
.SYNOPSIS
  Full Bobux deploy-to-VPS pipeline.
  Bumps version, builds hotfix + Windows ZIP, updates manifests,
  uploads everything via SCP, and restarts services remotely.

.EXAMPLE
  .\deploy_vps.ps1                           # defaults
  .\deploy_vps.ps1 -SkipBuild                # only re-upload existing artifacts
  .\deploy_vps.ps1 -Version "0.1.25" -Build 30  # override version
#>
[CmdletBinding()]
param(
    [string]$ServerIp          = "109.71.245.162",
    [string]$ServerUser        = "root",

    # ---- PC version ----
    [string]$Version           = "0.1.24",
    [int]   $Build             = 29,

    # ---- Mobile version ----
    [string]$MobileVersion     = "0.1.16-mobile",
    [int]   $MobileBuild       = 17,

    # ---- Launcher (unchanged unless you rebuild it) ----
    [string]$LauncherVersion   = "0.1.7",
    [int]   $LauncherBuild     = 9,

    # ---- Paths ----
    [string]$ProjectRoot       = "C:\robloxclone",

    # ---- Flags ----
    [switch]$SkipBuild,
    [switch]$SkipMobile,
    [switch]$SkipExport,

    # ---- Godot ----
    [string]$GodotBin          = "C:\robloxclone\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe",

    # ---- Server env ----
    [string]$BobuxApiUrl       = "http://127.0.0.1:3000/api",
    [string]$BobuxServiceKey   = "bobux-server-compat",
    [string]$HeartbeatToken    = $env:BOBUX_SERVER_HEARTBEAT_TOKEN
)

$ErrorActionPreference = "Stop"
$Server = "${ServerUser}@${ServerIp}"

# ---- Derived filenames ----
$hotfixTar       = Join-Path $ProjectRoot "dist\bobux-hotfix-build${Build}.tar.gz"
$windowsStageDir = Join-Path $ProjectRoot "dist\release\Bobux-Windows-${Version}-build${Build}-stage"
$windowsZip      = Join-Path $ProjectRoot "dist\release\Bobux-Windows-${Version}-build${Build}.zip"
$windowsLatest   = Join-Path $ProjectRoot "dist\release\Bobux-Windows.zip"
$launcherJson    = Join-Path $ProjectRoot "game\launcher\latest.json"
$mobileJson      = Join-Path $ProjectRoot "mobile\latest.json"
$mobileApk       = Join-Path $ProjectRoot "dist\release\Bobux-Android-${MobileVersion}-build${MobileBuild}.apk"
$mobileApkLatest = Join-Path $ProjectRoot "dist\release\Bobux-Android.apk"
$launcherZip     = Join-Path $ProjectRoot "dist\BobuxLauncher-Windows.zip"
$gameExe         = Join-Path $ProjectRoot "dist\game\Bobux.exe"
$gamePck         = Join-Path $ProjectRoot "dist\game\Bobux.pck"
$gameApk         = Join-Path $ProjectRoot "dist\game\bobuxbeta.apk"

# ============================================================
# 1. BUMP VERSION in project.godot
# ============================================================
Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " Bobux Deploy Pipeline"                               -ForegroundColor Cyan
Write-Host " PC:      $Version  build $Build"                     -ForegroundColor Cyan
Write-Host " Android: $MobileVersion  build $MobileBuild"         -ForegroundColor Cyan
Write-Host " Server:  $ServerIp"                                  -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

$projectGodot = Join-Path $ProjectRoot "project.godot"
if (Test-Path $projectGodot) {
    $content = Get-Content $projectGodot -Raw
    $content = $content -replace 'config/version="[^"]*"', "config/version=`"$Version`""
    Set-Content -Path $projectGodot -Value $content -NoNewline
    Write-Host "[OK] project.godot -> version $Version" -ForegroundColor Green
}

# ============================================================
# 1.5  EXPORT FROM GODOT (build exe/pck/apk)
# ============================================================
if (-not $SkipExport) {
    Write-Host ""
    Write-Host "--- Exporting from Godot ---" -ForegroundColor Yellow

    if (-not (Test-Path $GodotBin)) {
        Write-Host "[ERROR] Godot binary not found: $GodotBin" -ForegroundColor Red
        Write-Host "  Install Godot or pass -SkipExport to use existing builds." -ForegroundColor Red
        exit 1
    }

    # Ensure output directories exist
    $distGame = Join-Path $ProjectRoot "dist\game"
    if (-not (Test-Path $distGame)) { New-Item -ItemType Directory -Path $distGame -Force | Out-Null }

    # --- Windows export ---
    Write-Host "  Exporting Windows Desktop..."
    $winExportPath = Join-Path $distGame "Bobux.exe"
    & $GodotBin --headless --path $ProjectRoot --export-release "Windows Desktop" $winExportPath 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Windows export returned exit code $LASTEXITCODE" -ForegroundColor Red
    }
    if (Test-Path $winExportPath) {
        $exeSize = [math]::Round((Get-Item $winExportPath).Length / 1MB, 1)
        Write-Host "[OK] Exported: $winExportPath ($exeSize MB)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Windows export failed — no Bobux.exe produced" -ForegroundColor Red
        exit 1
    }

    # --- Android export ---
    if (-not $SkipMobile) {
        Write-Host "  Exporting Android..."
        $apkExportPath = Join-Path $distGame "bobuxbeta.apk"
        & $GodotBin --headless --path $ProjectRoot --export-release "Android" $apkExportPath 2>&1 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Android export returned exit code $LASTEXITCODE" -ForegroundColor Red
        }
        if (Test-Path $apkExportPath) {
            $apkSize = [math]::Round((Get-Item $apkExportPath).Length / 1MB, 1)
            Write-Host "[OK] Exported: $apkExportPath ($apkSize MB)" -ForegroundColor Green
            # Also copy to versioned name
            $versionedApkInGame = Join-Path $distGame "Bobux-Android-${MobileVersion}-build${MobileBuild}.apk"
            Copy-Item $apkExportPath $versionedApkInGame -Force
        } else {
            Write-Host "[WARN] Android export failed — no APK produced. Continuing without mobile." -ForegroundColor Red
            $SkipMobile = $true
        }
    }

    Write-Host ""
}

# ============================================================
# 2. BUILD HOTFIX TARBALL (server code + scripts only)
# ============================================================
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "--- Building hotfix tarball ---" -ForegroundColor Yellow

    if (Test-Path $hotfixTar) { Remove-Item $hotfixTar -Force }

    Push-Location $ProjectRoot
    tar -czf $hotfixTar `
        --exclude="./.git" `
        --exclude="./.godot" `
        --exclude="./exiting_game" `
        --exclude="./launcher_export" `
        --exclude="./dist" `
        --exclude="./mybuild" `
        --exclude="./tmp_*" `
        --exclude="./node_modules" `
        --exclude="./.env" `
        --exclude="./.venv" `
        --exclude="./.codex-tools" `
        .
    Pop-Location

    $hotfixSize = [math]::Round((Get-Item $hotfixTar).Length / 1MB, 1)
    Write-Host "[OK] Hotfix: $hotfixTar ($hotfixSize MB)" -ForegroundColor Green
}

# ============================================================
# 3. BUILD WINDOWS ZIP (Bobux.exe + Bobux.pck)
# ============================================================
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "--- Building Windows ZIP ---" -ForegroundColor Yellow

    # Create staging directory
    if (Test-Path $windowsStageDir) { Remove-Item $windowsStageDir -Recurse -Force }
    New-Item -ItemType Directory -Path $windowsStageDir -Force | Out-Null

    if (Test-Path $gameExe) {
        Copy-Item $gameExe (Join-Path $windowsStageDir "Bobux.exe")
    } else {
        Write-Host "[WARN] Bobux.exe not found at $gameExe — using last known build" -ForegroundColor Red
        # Try the latest release stage
        $lastStage = Get-ChildItem (Join-Path $ProjectRoot "dist\release") -Directory -Filter "Bobux-Windows-*-stage" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastStage) {
            Copy-Item (Join-Path $lastStage.FullName "Bobux.exe") (Join-Path $windowsStageDir "Bobux.exe")
        }
    }
    if (Test-Path $gamePck) {
        Copy-Item $gamePck (Join-Path $windowsStageDir "Bobux.pck")
    } else {
        $lastStage = Get-ChildItem (Join-Path $ProjectRoot "dist\release") -Directory -Filter "Bobux-Windows-*-stage" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastStage) {
            Copy-Item (Join-Path $lastStage.FullName "Bobux.pck") (Join-Path $windowsStageDir "Bobux.pck")
        }
    }

    # Create ZIP
    if (Test-Path $windowsZip) { Remove-Item $windowsZip -Force }
    Compress-Archive -Path "$windowsStageDir\*" -DestinationPath $windowsZip -CompressionLevel Optimal
    Copy-Item $windowsZip $windowsLatest -Force

    $zipSize = [math]::Round((Get-Item $windowsZip).Length / 1MB, 1)
    Write-Host "[OK] Windows ZIP: $windowsZip ($zipSize MB)" -ForegroundColor Green
}

# ============================================================
# 4. COPY MOBILE APK (if new build exists)
# ============================================================
if (-not $SkipMobile) {
    $sourceApk = Join-Path $ProjectRoot "dist\game\Bobux-Android-${MobileVersion}-build${MobileBuild}.apk"
    if (-not (Test-Path $sourceApk)) {
        # Fallback: latest bobuxbeta.apk
        if (Test-Path $gameApk) {
            $sourceApk = $gameApk
        }
    }
    if (Test-Path $sourceApk) {
        Copy-Item $sourceApk $mobileApk -Force
        Copy-Item $sourceApk $mobileApkLatest -Force
        Write-Host "[OK] Mobile APK: $mobileApk" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No mobile APK found for $MobileVersion build $MobileBuild" -ForegroundColor Red
        $SkipMobile = $true
    }
}

# ============================================================
# 5. UPDATE MANIFESTS
# ============================================================
Write-Host ""
Write-Host "--- Updating manifests ---" -ForegroundColor Yellow

# Windows ZIP SHA-256
$winSha256 = ""
if (Test-Path $windowsZip) {
    $winSha256 = (Get-FileHash $windowsZip -Algorithm SHA256).Hash
} elseif (Test-Path $windowsLatest) {
    $winSha256 = (Get-FileHash $windowsLatest -Algorithm SHA256).Hash
}

# Launcher SHA-256
$launcherSha256 = ""
if (Test-Path $launcherZip) {
    $launcherSha256 = (Get-FileHash $launcherZip -Algorithm SHA256).Hash
}

$launcherManifest = @{
    version    = $Version
    build      = $Build
    zip_url    = "http://${ServerIp}/downloads/Bobux-Windows-${Version}-build${Build}.zip"
    sha256     = $winSha256
    executable = "Bobux.exe"
    mirrors    = @(
        "http://${ServerIp}/downloads/Bobux-Windows-${Version}-build${Build}.zip"
        "http://${ServerIp}/downloads/Bobux-Windows.zip"
    )
    launcher   = @{
        version  = $LauncherVersion
        build    = $LauncherBuild
        zip_url  = "http://${ServerIp}/downloads/BobuxLauncher-${LauncherVersion}-build${LauncherBuild}.zip"
        sha256   = $launcherSha256
        mirrors  = @(
            "http://${ServerIp}/downloads/BobuxLauncher-${LauncherVersion}-build${LauncherBuild}.zip"
            "http://${ServerIp}/downloads/BobuxLauncher-Windows.zip"
        )
    }
    notes      = "Bobux ${Version}: PC build ${Build}, Android ${MobileVersion}. Studio 2.0, баг-фиксы аватаров и каталога."
}
$launcherManifest | ConvertTo-Json -Depth 4 | Set-Content -Path $launcherJson -Encoding UTF8
Write-Host "[OK] $launcherJson" -ForegroundColor Green

# Mobile manifest
if (-not $SkipMobile) {
    $mobileSha256 = ""
    if (Test-Path $mobileApk) {
        $mobileSha256 = (Get-FileHash $mobileApk -Algorithm SHA256).Hash
    }
    $mobileManifest = @{
        version  = $MobileVersion
        build    = $MobileBuild
        android  = @{
            version          = $MobileVersion
            build            = $MobileBuild
            apk_url          = "http://${ServerIp}/mobile/Bobux-Android.apk"
            versioned_apk_url = "http://${ServerIp}/mobile/Bobux-Android-${MobileVersion}-build${MobileBuild}.apk"
            sha256           = $mobileSha256
            required         = $true
            notes            = "Bobux mobile ${MobileVersion}: Studio 2.0, фиксы аватаров."
        }
    }
    $mobileManifest | ConvertTo-Json -Depth 4 | Set-Content -Path $mobileJson -Encoding UTF8
    Write-Host "[OK] $mobileJson" -ForegroundColor Green
}

# ============================================================
# 6. VERIFY REQUIRED FILES EXIST
# ============================================================
Write-Host ""
Write-Host "--- Verifying artifacts ---" -ForegroundColor Yellow

$requiredFiles = @(
    @{ Path = $hotfixTar;    Name = "Hotfix tar.gz" }
    @{ Path = $launcherJson; Name = "Launcher manifest" }
)
if (-not $SkipBuild) {
    $requiredFiles += @{ Path = $windowsZip;    Name = "Windows ZIP" }
    $requiredFiles += @{ Path = $windowsLatest; Name = "Windows ZIP (latest)" }
}
if (-not $SkipMobile) {
    $requiredFiles += @{ Path = $mobileApk;       Name = "Mobile APK (versioned)" }
    $requiredFiles += @{ Path = $mobileApkLatest;  Name = "Mobile APK (latest)" }
    $requiredFiles += @{ Path = $mobileJson;       Name = "Mobile manifest" }
}

$allOk = $true
foreach ($f in $requiredFiles) {
    if (Test-Path $f.Path) {
        $size = [math]::Round((Get-Item $f.Path).Length / 1MB, 1)
        Write-Host "  [OK] $($f.Name): $($f.Path) ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($f.Name): $($f.Path)" -ForegroundColor Red
        $allOk = $false
    }
}

if (-not $allOk) {
    Write-Host ""
    Write-Host "Some required files are missing! Fix them and re-run." -ForegroundColor Red
    exit 1
}

# ============================================================
# 7. UPLOAD TO VPS
# ============================================================
Write-Host ""
Write-Host "--- Uploading to ${ServerIp} ---" -ForegroundColor Yellow

# Hotfix (server code)
Write-Host "  Uploading hotfix tarball..."
scp $hotfixTar "${Server}:/tmp/bobux-hotfix.tar.gz"

# Launcher manifest
Write-Host "  Uploading launcher manifest..."
scp $launcherJson "${Server}:/tmp/latest.json"

# Windows ZIP
if (Test-Path $windowsLatest) {
    Write-Host "  Uploading Windows ZIP..."
    scp $windowsLatest "${Server}:/tmp/Bobux-Windows.zip"
    scp $windowsZip "${Server}:/tmp/Bobux-Windows-${Version}-build${Build}.zip"
}

# Launcher ZIP
if (Test-Path $launcherZip) {
    Write-Host "  Uploading Launcher ZIP..."
    scp $launcherZip "${Server}:/tmp/BobuxLauncher-Windows.zip"
}

# Mobile
if (-not $SkipMobile) {
    Write-Host "  Uploading mobile manifest..."
    scp $mobileJson "${Server}:/tmp/mobile-latest.json"
    Write-Host "  Uploading mobile APK..."
    scp $mobileApkLatest "${Server}:/tmp/Bobux-Android.apk"
    scp $mobileApk "${Server}:/tmp/Bobux-Android-${MobileVersion}-build${MobileBuild}.apk"
}

# Deploy remote script
Write-Host "  Uploading deploy_remote.sh..."
scp (Join-Path $ProjectRoot "ops\vps\deploy_remote.sh") "${Server}:/tmp/deploy_remote.sh"

Write-Host "[OK] All files uploaded." -ForegroundColor Green

# ============================================================
# 8. EXECUTE REMOTE DEPLOY
# ============================================================
Write-Host ""
Write-Host "--- Running remote deploy ---" -ForegroundColor Yellow

$mobileBlock = ""
if (-not $SkipMobile) {
    $mobileBlock = @"

mkdir -p /var/www/bobux/mobile
cp /tmp/mobile-latest.json /var/www/bobux/mobile/latest.json
cp /tmp/Bobux-Android.apk /var/www/bobux/mobile/Bobux-Android.apk
cp /tmp/Bobux-Android-${MobileVersion}-build${MobileBuild}.apk /var/www/bobux/mobile/Bobux-Android-${MobileVersion}-build${MobileBuild}.apk
chmod 644 /var/www/bobux/mobile/*
echo '[OK] Mobile APK deployed'
"@
}

$remoteScript = @"
set -e
echo '=== Bobux Remote Deploy ==='
echo 'Version: ${Version} build ${Build}'

# Extract server code
mkdir -p /opt/bobux-server /var/www/bobux/launcher /var/www/bobux/downloads /var/log/bobux
tar -xzf /tmp/bobux-hotfix.tar.gz -C /opt/bobux-server
echo '[OK] Server code updated'

# Copy launcher manifest and Windows builds
if [ -f /opt/bobux-server/ops/vps/index.html ]; then
    cp /opt/bobux-server/ops/vps/index.html /var/www/bobux/index.html
fi
if [ -f /opt/bobux-server/ops/vps/admin.html ]; then
    cp /opt/bobux-server/ops/vps/admin.html /var/www/bobux/admin.html
fi
cp /tmp/latest.json /var/www/bobux/launcher/latest.json
cp /tmp/latest.json /var/www/bobux/downloads/latest.json
cp /tmp/Bobux-Windows.zip /var/www/bobux/downloads/Bobux-Windows.zip
if [ -f /tmp/Bobux-Windows-${Version}-build${Build}.zip ]; then
    cp /tmp/Bobux-Windows-${Version}-build${Build}.zip /var/www/bobux/downloads/Bobux-Windows-${Version}-build${Build}.zip
fi
if [ -f /tmp/BobuxLauncher-Windows.zip ]; then
    cp /tmp/BobuxLauncher-Windows.zip /var/www/bobux/downloads/BobuxLauncher-Windows.zip
fi
chmod 644 /var/www/bobux/index.html /var/www/bobux/admin.html /var/www/bobux/downloads/* /var/www/bobux/launcher/* 2>/dev/null || true
echo '[OK] Windows builds deployed'
${mobileBlock}

# Update nginx config
if [ ! -f /opt/bobux-server/ops/vps/bobux_nginx.conf ]; then
    echo '[FAIL] Missing /opt/bobux-server/ops/vps/bobux_nginx.conf'
    exit 1
fi
cp /opt/bobux-server/ops/vps/bobux_nginx.conf /etc/nginx/sites-available/bobux
ln -sf /etc/nginx/sites-available/bobux /etc/nginx/sites-enabled/bobux
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
echo '[OK] Nginx updated'

# Update API service
if [ ! -d /opt/bobux-server/services/bobux_api ]; then
    echo '[FAIL] Missing Bobux API source in /opt/bobux-server/services/bobux_api'
    exit 1
fi
mkdir -p /opt/bobux-api
rsync -a --delete --exclude='.env' --exclude='node_modules' /opt/bobux-server/services/bobux_api/ /opt/bobux-api/
if [ ! -f /opt/bobux-api/.env ]; then
    [ -f /opt/bobux-api/.env.example ] && cp /opt/bobux-api/.env.example /opt/bobux-api/.env
fi
cd /opt/bobux-api
npm install --omit=dev 2>/dev/null || true
pm2 delete bobux-api 2>/dev/null || true
if [ -f /opt/bobux-api/.env ]; then
    set -a; . /opt/bobux-api/.env; set +a
fi
pm2 start /opt/bobux-api/server.js --name bobux-api --update-env
echo '[OK] API service restarted'

# Import Godot project & restart game server
GODOT_BIN=/usr/local/bin/godot
if [ -x "`$GODOT_BIN" ]; then
    cd /opt/bobux-server
    `$GODOT_BIN --headless --import --path /opt/bobux-server || true

    pm2 delete bobux 2>/dev/null || true
    PUBLIC_SERVER_WS_URL='ws://${ServerIp}/ws' \
    GODOT_SERVER_PORT='9000' \
    GODOT_SERVER_MAP='classic' \
    BOBUX_API_URL='${BobuxApiUrl}' \
    BOBUX_SERVICE_KEY='${BobuxServiceKey}' \
    BOBUX_SERVER_HEARTBEAT_TOKEN='${HeartbeatToken}' \
    pm2 start "`$GODOT_BIN" --name bobux -- \
        --headless --path /opt/bobux-server --script res://server/server_main.gd
    echo '[OK] Game server restarted'
else
    echo '[WARN] Godot binary not found - run deploy_remote.sh for full setup'
fi

sleep 2
curl -fsS http://127.0.0.1/launcher/latest.json >/dev/null
curl -fsS http://127.0.0.1:3000/api/health | grep -q '"ok":true'
curl -fsS http://127.0.0.1/api/health | grep -q '"ok":true'
AUTH_CODE="`$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{""email"":""bobux-healthcheck@example.invalid"",""password"":""bad-password""}' 'http://127.0.0.1/api/auth/v1/token?grant_type=password' || echo 000)"
case "`$AUTH_CODE" in
    200|400|401|422|429) echo "[OK] Auth route reachable (`$AUTH_CODE)" ;;
    *) echo "[FAIL] Auth route returned `$AUTH_CODE"; exit 1 ;;
esac

pm2 save
echo ''
echo '=== DEPLOY COMPLETE ==='
"@

ssh $Server "bash -c '$($remoteScript -replace "'","'\''")'"

# ============================================================
# 9. VERIFY
# ============================================================
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify these URLs:" -ForegroundColor Cyan
Write-Host "  http://${ServerIp}/launcher/latest.json"
Write-Host "  http://${ServerIp}/downloads/Bobux-Windows.zip"
Write-Host "  http://${ServerIp}/downloads/Bobux-Windows-${Version}-build${Build}.zip"
if (-not $SkipMobile) {
    Write-Host "  http://${ServerIp}/mobile/latest.json"
    Write-Host "  http://${ServerIp}/mobile/Bobux-Android.apk"
}
Write-Host "  http://${ServerIp}/health"
Write-Host "  http://${ServerIp}/api/health"
Write-Host ""
