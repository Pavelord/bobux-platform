<#
.SYNOPSIS
  Full Bobux release pipeline: export from Godot -> build archives -> update manifests -> upload -> deploy.
  Run this ONE script and everything happens automatically.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\robloxclone\tools\deploy_bobux_release.ps1
  powershell -ExecutionPolicy Bypass -File C:\robloxclone\tools\deploy_bobux_release.ps1 -SkipExport
  powershell -ExecutionPolicy Bypass -File C:\robloxclone\tools\deploy_bobux_release.ps1 -SkipMobile
#>
[CmdletBinding()]
param(
	[string]$Server         = "root@109.71.245.162",
	[string]$ServerIp       = "109.71.245.162",
	[string]$RemoteRoot     = "/opt/bobux-server",
	[string]$WebRoot        = "/var/www/bobux",

	# ---- Versions ----
	[string]$Version        = "0.1.34",
	[int]$Build             = 39,
	[string]$MobileVersion  = "0.1.26-mobile",
	[int]$MobileBuild       = 27,
	[string]$LauncherVersion = "0.1.11",
	[int]$LauncherBuild     = 13,
	[string]$WindowsArchitecture = "x86_32",
	[string]$ReleaseNotes = "Bobux release $Version build $Build.",
	[string]$MobileReleaseNotes = "",

	# ---- Flags ----
	[switch]$SkipExport,
	[switch]$SkipMobile,
	[Alias("LocalOnly")]
	[switch]$SkipUpload,

	# ---- Server env ----
	[string]$BobuxApiUrl    = "http://127.0.0.1:3000/api",
	[string]$BobuxServiceKey = "bobux-server-compat",
	[string]$HeartbeatToken = $env:BOBUX_SERVER_HEARTBEAT_TOKEN,

	# ---- Reproducible build inputs ----
	[string]$GodotExecutable = $env:GODOT_BIN,
	[string]$AndroidKeystorePath = $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
	[string]$AndroidKeystoreUser = $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER,
	[string]$AndroidKeystorePassword = $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---- Godot binary ----
# Prefer the console binary so export failures are visible and reflected in LASTEXITCODE.
$godotBin = $GodotExecutable
if ([string]::IsNullOrWhiteSpace($godotBin)) {
	$godotBin = Join-Path $projectRoot ".codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
}
if (-not (Test-Path $godotBin)) {
	$godotBin = Join-Path $projectRoot ".codex-tools\godot-4.7\Godot_v4.7-stable_win64.exe"
}
if (-not (Test-Path $godotBin)) {
	$godotBin = "C:\Users\Pavel\Desktop\Godot_v4.7-stable_win64_console.exe"
}
if (-not (Test-Path $godotBin)) {
	$godotBin = "C:\Users\Pavel\Desktop\Godot_v4.7-stable_win64.exe"
}
if (-not (Test-Path $godotBin)) {
	$godotBin = "C:\Program Files\Godot\Godot_v4.7-stable_win64_console.exe"
}
if (-not (Test-Path $godotBin)) {
	$godotBin = "C:\Program Files\Godot\Godot_v4.7-stable_win64.exe"
}

# ---- Derived paths ----
$distDir            = Join-Path $projectRoot "dist"
$distGame           = Join-Path $distDir "game"
$distRelease        = Join-Path $distDir "release"
$gameExe            = Join-Path $distGame "Bobux.exe"
$gamePck            = Join-Path $distGame "Bobux.pck"
$gameApk            = Join-Path $distGame "bobuxbeta.apk"
$hotfix             = Join-Path $distDir "bobux-hotfix-build$Build.tar.gz"
$windowsStageDir    = Join-Path $distRelease "Bobux-Windows-$Version-build$Build-stage"
$windowsVersionedZip = Join-Path $distRelease "Bobux-Windows-$Version-build$Build.zip"
$windowsZip         = Join-Path $distRelease "Bobux-Windows.zip"
$mobileApkVersioned = Join-Path $distRelease "Bobux-Android-$MobileVersion-build$MobileBuild.apk"
$mobileApkLatest    = Join-Path $distRelease "Bobux-Android.apk"
$launcherManifest   = Join-Path $projectRoot "game\launcher\latest.json"
$mobileManifest     = Join-Path $projectRoot "mobile\latest.json"
$launcherZip        = Join-Path $distDir "BobuxLauncher-Windows.zip"
$launcherRoot       = Join-Path $projectRoot "launcher"
$launcherProjectGodot = Join-Path $launcherRoot "project.godot"
$launcherExportPresets = Join-Path $launcherRoot "export_presets.cfg"
$launcherExportDir  = Join-Path $projectRoot "launcher_export\windows"
$launcherExe        = Join-Path $launcherExportDir "BobuxLauncher.exe"
$launcherPck        = Join-Path $launcherExportDir "BobuxLauncher.pck"
$gameLuaExtensionDll = Join-Path $projectRoot "addons\luaAPI\bin\libluaapi.windows.template_release.$WindowsArchitecture.dll"
$rbxlConverterSource = Join-Path $projectRoot "addons\rbxl_importer\rbxl_converter.py"

if ([string]::IsNullOrWhiteSpace($MobileReleaseNotes)) {
	$MobileReleaseNotes = $ReleaseNotes
}

# Keep signing credentials out of export_presets.cfg. Godot officially supports
# these environment variables and they work both locally and in GitHub Actions.
if (-not $SkipMobile) {
	if ([string]::IsNullOrWhiteSpace($AndroidKeystorePath)) {
		$AndroidKeystorePath = Join-Path $projectRoot "tools\mobile\bobux_debug.keystore"
	}
	if ([string]::IsNullOrWhiteSpace($AndroidKeystoreUser)) {
		$AndroidKeystoreUser = "bobuxdebug"
	}
	if ([string]::IsNullOrWhiteSpace($AndroidKeystorePassword)) {
		$AndroidKeystorePassword = "android"
	}
	if (-not (Test-Path -LiteralPath $AndroidKeystorePath -PathType Leaf)) {
		throw "Android release keystore is missing: $AndroidKeystorePath"
	}
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = [System.IO.Path]::GetFullPath($AndroidKeystorePath)
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $AndroidKeystoreUser
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $AndroidKeystorePassword
}

function Get-SizeMB([string]$Path) {
	if (Test-Path $Path) {
		return [math]::Round((Get-Item $Path).Length / 1MB, 1)
	}
	return 0
}

function Get-WindowsFileVersion([string]$SemanticVersion) {
	$numeric = ($SemanticVersion -replace '[^0-9.]', '').Trim('.')
	$parts = @($numeric.Split('.') | Where-Object { $_ -ne "" })
	while ($parts.Count -lt 4) {
		$parts += "0"
	}
	if ($parts.Count -gt 4) {
		$parts = $parts[0..3]
	}
	return ($parts -join ".")
}

function Assert-HealthyFile([string]$Path, [long]$MinimumBytes, [string]$Label) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "$Label is missing: $Path"
	}
	$length = (Get-Item -LiteralPath $Path).Length
	if ($length -lt $MinimumBytes) {
		throw "$Label is too small ($length bytes, expected at least $MinimumBytes): $Path"
	}
}

function Assert-ZipEntries([string]$Path, [hashtable]$RequiredEntries, [string]$Label) {
	Assert-HealthyFile $Path 1024 $Label
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($Path))
	try {
		foreach ($entryName in $RequiredEntries.Keys) {
			$entry = $archive.Entries |
				Where-Object { $_.FullName.Replace('\', '/') -eq $entryName } |
				Select-Object -First 1
			if ($null -eq $entry) {
				throw "$Label is missing required entry '$entryName'."
			}
			$minimumBytes = [long]$RequiredEntries[$entryName]
			if ($entry.Length -lt $minimumBytes) {
				throw "$Label entry '$entryName' is too small ($($entry.Length) bytes, expected at least $minimumBytes)."
			}
		}
	} finally {
		$archive.Dispose()
	}
}

function Invoke-GameSmokeTest([string]$ExecutablePath, [string]$LogDirectory) {
	Assert-HealthyFile $ExecutablePath (10MB) "Windows game executable"
	if (-not (Test-Path -LiteralPath $LogDirectory)) {
		New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
	}
	$stdoutPath = Join-Path $LogDirectory "game-smoke.stdout.log"
	$stderrPath = Join-Path $LogDirectory "game-smoke.stderr.log"
	Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
	$startInfo = New-Object System.Diagnostics.ProcessStartInfo
	$startInfo.FileName = $ExecutablePath
	$startInfo.Arguments = "--headless --audio-driver Dummy --quit-after 3"
	$startInfo.WorkingDirectory = Split-Path -Parent $ExecutablePath
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $startInfo
	$started = $false
	try {
		$started = $process.Start()
		if (-not $started) {
			throw "Windows game smoke test could not start the executable."
		}
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		if (-not $process.WaitForExit(90000)) {
			$process.Kill()
			$process.WaitForExit()
			throw "Windows game smoke test timed out after 90 seconds."
		}
		$process.WaitForExit()
		$stdoutText = $stdoutTask.Result
		$stderrText = $stderrTask.Result
		$exitCode = $process.ExitCode
		[System.IO.File]::WriteAllText($stdoutPath, $stdoutText, (New-Object System.Text.UTF8Encoding($false)))
		[System.IO.File]::WriteAllText($stderrPath, $stderrText, (New-Object System.Text.UTF8Encoding($false)))
		if ($exitCode -ne 0) {
			throw "Windows game smoke test failed with exit code $exitCode. $stderrText"
		}
		$combinedLog = $stdoutText + "`n" + $stderrText
		if ($combinedLog -match 'Couldn''t load project data|PCK file is missing|Parse Error|Compile Error|Failed to load script') {
			throw "Windows game smoke test found a fatal project/PCK error. See $stdoutPath and $stderrPath"
		}
	} finally {
		if ($started -and -not $process.HasExited) {
			$process.Kill()
			$process.WaitForExit()
		}
		$process.Dispose()
	}
	Start-Sleep -Milliseconds 300
}

# Ensure directories exist
foreach ($d in @($distDir, $distGame, $distRelease)) {
	if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  BOBUX FULL RELEASE PIPELINE"                        -ForegroundColor Cyan
Write-Host "  PC:      $Version  build $Build"                    -ForegroundColor Cyan
Write-Host "  Android: $MobileVersion  build $MobileBuild"        -ForegroundColor Cyan
Write-Host "  Server:  $Server"                                   -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# ================================================================
#  STEP 1: Bump versions in project.godot and export_presets.cfg
# ================================================================
Write-Host "--- Step 1/7: Bumping version ---" -ForegroundColor Yellow
$projectGodot = Join-Path $projectRoot "project.godot"
if (Test-Path $projectGodot) {
	$content = Get-Content $projectGodot -Raw
	$content = $content -replace 'config/version="[^"]*"', "config/version=`"$Version`""
	$content = $content -replace 'mobile/build=\d+', "mobile/build=$MobileBuild"
	[System.IO.File]::WriteAllText($projectGodot, $content, $utf8NoBom)
	Write-Host "  OK: project.godot -> $Version, mobile build $MobileBuild" -ForegroundColor Green
}
$exportPresets = Join-Path $projectRoot "export_presets.cfg"
if (Test-Path $exportPresets) {
	$windowsFileVersion = Get-WindowsFileVersion $Version
	$exportContent = Get-Content $exportPresets -Raw
	$exportContent = $exportContent -replace 'application/file_version="[^"]*"', "application/file_version=`"$windowsFileVersion`""
	$exportContent = $exportContent -replace 'application/product_version="[^"]*"', "application/product_version=`"$windowsFileVersion`""
	$exportContent = $exportContent -replace 'binary_format/architecture="[^"]*"', "binary_format/architecture=`"$WindowsArchitecture`""
	$exportContent = [regex]::Replace($exportContent, '(?s)(name="Windows Desktop".*?binary_format/embed_pck=)false', '${1}true', 1)
	$exportContent = $exportContent -replace 'version/code=\d+', "version/code=$MobileBuild"
	$exportContent = $exportContent -replace 'version/name="[^"]*"', "version/name=`"$MobileVersion`""
	[System.IO.File]::WriteAllText($exportPresets, $exportContent, $utf8NoBom)
	Write-Host "  OK: export_presets.cfg -> Windows $windowsFileVersion ($WindowsArchitecture), Android $MobileVersion build $MobileBuild" -ForegroundColor Green
}
if (Test-Path $launcherProjectGodot) {
	$launcherContent = Get-Content $launcherProjectGodot -Raw
	$launcherContent = $launcherContent -replace 'version="[^"]*"', "version=`"$LauncherVersion`""
	$launcherContent = $launcherContent -replace 'build=\d+', "build=$LauncherBuild"
	[System.IO.File]::WriteAllText($launcherProjectGodot, $launcherContent, $utf8NoBom)
	Write-Host "  OK: launcher/project.godot -> $LauncherVersion build $LauncherBuild" -ForegroundColor Green
}
$launcherScript = Join-Path $launcherRoot "scripts\launcher.gd"
if (Test-Path $launcherScript) {
	$launcherScriptContent = Get-Content $launcherScript -Raw
	$launcherScriptContent = $launcherScriptContent -replace 'const LAUNCHER_VERSION: String = "[^"]*"', "const LAUNCHER_VERSION: String = `"$LauncherVersion`""
	$launcherScriptContent = $launcherScriptContent -replace 'const LAUNCHER_BUILD: int = \d+', "const LAUNCHER_BUILD: int = $LauncherBuild"
	[System.IO.File]::WriteAllText($launcherScript, $launcherScriptContent, $utf8NoBom)
	Write-Host "  OK: launcher script constants -> $LauncherVersion build $LauncherBuild" -ForegroundColor Green
}
if (Test-Path $launcherExportPresets) {
	$launcherFileVersion = Get-WindowsFileVersion $LauncherVersion
	$launcherExportContent = Get-Content $launcherExportPresets -Raw
	$launcherExportContent = $launcherExportContent -replace 'application/file_version="[^"]*"', "application/file_version=`"$launcherFileVersion`""
	$launcherExportContent = $launcherExportContent -replace 'application/product_version="[^"]*"', "application/product_version=`"$launcherFileVersion`""
	$launcherExportContent = $launcherExportContent -replace 'binary_format/architecture="[^"]*"', "binary_format/architecture=`"$WindowsArchitecture`""
	$launcherExportContent = [regex]::Replace($launcherExportContent, '(?s)(name="Windows Desktop".*?binary_format/embed_pck=)false', '${1}true', 1)
	[System.IO.File]::WriteAllText($launcherExportPresets, $launcherExportContent, $utf8NoBom)
	Write-Host "  OK: launcher/export_presets.cfg -> $launcherFileVersion ($WindowsArchitecture)" -ForegroundColor Green
}

# Compile the exact source state that is about to be exported.
Write-Host ""
Write-Host "--- Step 1b/7: Validating Godot projects ---" -ForegroundColor Yellow
if (-not (Test-Path $godotBin)) {
	throw "Godot executable was not found: $godotBin"
}
$ErrorActionPreference = 'Continue'
$projectValidationOutput = & $godotBin --headless --editor --quit --path $projectRoot 2>&1
$projectValidationExit = $LASTEXITCODE
$launcherValidationOutput = & $godotBin --headless --editor --quit --path $launcherRoot 2>&1
$launcherValidationExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$fatalValidationPattern = 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script'
if ($projectValidationExit -ne 0 -or (($projectValidationOutput -join "`n") -match $fatalValidationPattern)) {
	$projectValidationOutput | ForEach-Object { Write-Host "    $($_.ToString())" }
	throw "Main Godot project validation failed."
}
if ($launcherValidationExit -ne 0 -or (($launcherValidationOutput -join "`n") -match $fatalValidationPattern)) {
	$launcherValidationOutput | ForEach-Object { Write-Host "    $($_.ToString())" }
	throw "Launcher Godot project validation failed."
}
Write-Host "  OK: main project and launcher compile cleanly" -ForegroundColor Green

# ================================================================
#  STEP 2: Export from Godot (builds exe/pck/apk)
# ================================================================
if (-not $SkipExport) {
	Write-Host ""
	Write-Host "--- Step 2/7: Exporting from Godot ---" -ForegroundColor Yellow

	if (-not (Test-Path $godotBin)) {
		Write-Host "  ERROR: Godot not found: $godotBin" -ForegroundColor Red
		Write-Host "  Pass -SkipExport to use existing builds in dist\game\." -ForegroundColor Red
		exit 1
	}

	# Windows export
	Write-Host "  Exporting Windows Desktop -> $gameExe"
	foreach ($oldArtifact in @($gameExe, $gamePck)) {
		if (Test-Path $oldArtifact) { Remove-Item $oldArtifact -Force }
	}
	$ErrorActionPreference = 'Continue'
	& $godotBin --headless --path $projectRoot --export-release "Windows Desktop" $gameExe 2>&1 | ForEach-Object { Write-Host "    $($_.ToString())" }
	$windowsExportExit = $LASTEXITCODE
	$ErrorActionPreference = 'Stop'
	if ($windowsExportExit -eq 0 -and (Test-Path $gameExe)) {
		Assert-HealthyFile $gameExe (10MB) "Windows game executable"
		$sz = Get-SizeMB $gameExe
		Write-Host "  OK: Bobux.exe ($sz MB)" -ForegroundColor Green
	} else {
		Write-Host "  FAIL: Windows export failed or Bobux.exe was not created!" -ForegroundColor Red
		exit 1
	}

	# Android export
	if (-not $SkipMobile) {
		Write-Host "  Exporting Android -> $gameApk"
		foreach ($oldArtifact in @($gameApk, "$gameApk.idsig")) {
			if (Test-Path $oldArtifact) { Remove-Item $oldArtifact -Force }
		}
		$ErrorActionPreference = 'Continue'
		& $godotBin --headless --path $projectRoot --export-release "Android" $gameApk 2>&1 | ForEach-Object { Write-Host "    $($_.ToString())" }
		$androidExportExit = $LASTEXITCODE
		$ErrorActionPreference = 'Stop'
		if ($androidExportExit -eq 0 -and (Test-Path $gameApk)) {
			Assert-HealthyFile $gameApk (10MB) "Android APK"
			$sz = Get-SizeMB $gameApk
			Write-Host "  OK: bobuxbeta.apk ($sz MB)" -ForegroundColor Green
		} else {
			Write-Host "  FAIL: Android export failed or bobuxbeta.apk was not created!" -ForegroundColor Red
			exit 1
		}
	}

	# Launcher export
	Write-Host "  Exporting Windows Launcher -> $launcherExe"
	if (Test-Path $launcherExportDir) {
		Remove-Item $launcherExportDir -Recurse -Force
	}
	New-Item -ItemType Directory -Path $launcherExportDir -Force | Out-Null
	$ErrorActionPreference = 'Continue'
	& $godotBin --headless --path $launcherRoot --export-release "Windows Desktop" $launcherExe 2>&1 | ForEach-Object { Write-Host "    $($_.ToString())" }
	$launcherExportExit = $LASTEXITCODE
	$ErrorActionPreference = 'Stop'
	if ($launcherExportExit -eq 0 -and (Test-Path $launcherExe)) {
		Assert-HealthyFile $launcherExe (10MB) "Windows launcher executable"
		$sz = Get-SizeMB $launcherExe
		Write-Host "  OK: BobuxLauncher.exe ($sz MB)" -ForegroundColor Green
	} else {
		Write-Host "  FAIL: Launcher export failed or BobuxLauncher.exe was not created!" -ForegroundColor Red
		exit 1
	}
} else {
	Write-Host ""
	Write-Host "--- Step 2/7: Skipping Godot export (using existing builds) ---" -ForegroundColor DarkGray
	if (-not (Test-Path $gameExe)) {
		Write-Host "  ERROR: No Bobux.exe found at $gameExe" -ForegroundColor Red
		Write-Host "  Run without -SkipExport to build it, or export manually from Godot." -ForegroundColor Red
		exit 1
	}
	if (-not (Test-Path $launcherZip) -and -not (Test-Path $launcherExe)) {
		Write-Host "  ERROR: No launcher build found at $launcherExe or $launcherZip" -ForegroundColor Red
		Write-Host "  Run without -SkipExport to build the launcher." -ForegroundColor Red
		exit 1
	}
}

# ================================================================
#  STEP 3: Build hotfix tarball (server code)
# ================================================================
Write-Host ""
Write-Host "--- Step 3/7: Building server hotfix tarball ---" -ForegroundColor Yellow

if (Test-Path $hotfix) { Remove-Item $hotfix -Force }

Push-Location $projectRoot
tar -czf $hotfix `
	--exclude="./.git" `
	--exclude="./*/.git" `
	--exclude="./*/.git/*" `
	--exclude="./game" `
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

$sz = Get-SizeMB $hotfix
Assert-HealthyFile $hotfix 1024 "Server hotfix archive"
Write-Host "  OK: $hotfix ($sz MB)" -ForegroundColor Green

# ================================================================
#  STEP 4: Build Windows ZIP
# ================================================================
Write-Host ""
Write-Host "--- Step 4/7: Building Windows ZIP ---" -ForegroundColor Yellow

if (Test-Path $windowsStageDir) { Remove-Item $windowsStageDir -Recurse -Force }
New-Item -ItemType Directory -Path $windowsStageDir -Force | Out-Null

Copy-Item $gameExe (Join-Path $windowsStageDir "Bobux.exe") -Force
if (Test-Path $gamePck) {
	Copy-Item $gamePck (Join-Path $windowsStageDir "Bobux.pck") -Force
}
$stageRbxlImporterDir = Join-Path $windowsStageDir "addons\rbxl_importer"
New-Item -ItemType Directory -Path $stageRbxlImporterDir -Force | Out-Null
Assert-HealthyFile $rbxlConverterSource (32KB) "RBXL converter"
Copy-Item $rbxlConverterSource (Join-Path $stageRbxlImporterDir "rbxl_converter.py") -Force
$stageLuaExtensionDir = Join-Path $windowsStageDir "addons\luaAPI\bin"
New-Item -ItemType Directory -Path $stageLuaExtensionDir -Force | Out-Null
Assert-HealthyFile $gameLuaExtensionDll (256KB) "LuaAPI Windows extension"
Copy-Item $gameLuaExtensionDll (Join-Path $stageLuaExtensionDir (Split-Path -Leaf $gameLuaExtensionDll)) -Force
$gameVersionMarker = @{
	version    = $Version
	build      = $Build
	arch       = $WindowsArchitecture
	updated_at = (Get-Date).ToUniversalTime().ToString("s") + "Z"
}
[System.IO.File]::WriteAllText((Join-Path $windowsStageDir "version.json"), ($gameVersionMarker | ConvertTo-Json -Depth 3), $utf8NoBom)

Invoke-GameSmokeTest (Join-Path $windowsStageDir "Bobux.exe") $distRelease

if (Test-Path $windowsVersionedZip) { Remove-Item $windowsVersionedZip -Force }
Compress-Archive -Path "$windowsStageDir\*" -DestinationPath $windowsVersionedZip -CompressionLevel Optimal
Copy-Item $windowsVersionedZip $windowsZip -Force
Assert-ZipEntries $windowsVersionedZip @{
	"Bobux.exe" = 10MB
	"addons/rbxl_importer/rbxl_converter.py" = 32KB
	"addons/luaAPI/bin/$(Split-Path -Leaf $gameLuaExtensionDll)" = 256KB
	"version.json" = 20
} "Windows release ZIP"
$windowsRoundTripDir = Join-Path $distRelease "Bobux-Windows-$Version-build$Build-verify"
if (Test-Path $windowsRoundTripDir) {
	Remove-Item $windowsRoundTripDir -Recurse -Force
}
Expand-Archive -LiteralPath $windowsVersionedZip -DestinationPath $windowsRoundTripDir -Force
Assert-HealthyFile (Join-Path $windowsRoundTripDir "Bobux.exe") (10MB) "Extracted Windows game executable"
Assert-HealthyFile (Join-Path $windowsRoundTripDir "addons\rbxl_importer\rbxl_converter.py") (32KB) "Extracted RBXL converter"
Assert-HealthyFile (Join-Path $windowsRoundTripDir "addons\luaAPI\bin\$(Split-Path -Leaf $gameLuaExtensionDll)") (256KB) "Extracted LuaAPI Windows extension"
Invoke-GameSmokeTest (Join-Path $windowsRoundTripDir "Bobux.exe") (Join-Path $distRelease "roundtrip-smoke")
Remove-Item $windowsRoundTripDir -Recurse -Force

$sz = Get-SizeMB $windowsVersionedZip
Write-Host "  OK: $windowsVersionedZip ($sz MB)" -ForegroundColor Green

# ================================================================
#  STEP 5: Prepare mobile APK
# ================================================================
if (-not $SkipMobile) {
	Write-Host ""
	Write-Host "--- Step 5/7: Preparing mobile APK ---" -ForegroundColor Yellow

	$versionedGameApk = Join-Path $distGame "Bobux-Android-$MobileVersion-build$MobileBuild.apk"
	$sourceApk = $gameApk
	if ($SkipExport -and (Test-Path $versionedGameApk)) {
		$sourceApk = $versionedGameApk
	} elseif (-not (Test-Path $sourceApk) -and (Test-Path $versionedGameApk)) {
		$sourceApk = $versionedGameApk
	}

	if (Test-Path $sourceApk) {
		Copy-Item $sourceApk $mobileApkVersioned -Force
		Copy-Item $sourceApk $mobileApkLatest -Force
		if (-not (Test-Path $versionedGameApk)) {
			Copy-Item $sourceApk $versionedGameApk -Force
		}
		Assert-ZipEntries $mobileApkVersioned @{
			"AndroidManifest.xml" = 1024
			"classes.dex" = 1024
			"lib/arm64-v8a/libgodot_android.so" = 1MB
			"lib/armeabi-v7a/libgodot_android.so" = 1MB
		} "Android APK"
		$sz = Get-SizeMB $mobileApkVersioned
		Write-Host "  OK: $mobileApkVersioned ($sz MB)" -ForegroundColor Green
	} else {
	Write-Host "  WARN: No APK found - skipping mobile" -ForegroundColor Red
	$SkipMobile = $true
	}
} else {
	Write-Host ""
	Write-Host "--- Step 5/7: Skipping mobile ---" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "--- Step 5b/7: Building Launcher ZIP ---" -ForegroundColor Yellow
if (Test-Path $launcherExe) {
	if (Test-Path $launcherZip) { Remove-Item $launcherZip -Force }
	Compress-Archive -Path "$launcherExportDir\*" -DestinationPath $launcherZip -CompressionLevel Optimal
	Assert-ZipEntries $launcherZip @{
		"BobuxLauncher.exe" = 10MB
	} "Windows launcher ZIP"
	$sz = Get-SizeMB $launcherZip
	Write-Host "  OK: $launcherZip ($sz MB)" -ForegroundColor Green
} elseif (Test-Path $launcherZip) {
	$sz = Get-SizeMB $launcherZip
	Write-Host "  OK: existing $launcherZip ($sz MB)" -ForegroundColor Green
} else {
	Write-Host "  FAIL: Launcher ZIP cannot be built because $launcherExe is missing." -ForegroundColor Red
	exit 1
}

# ================================================================
#  STEP 6: Update manifests (latest.json)
# ================================================================
Write-Host ""
Write-Host "--- Step 6/7: Updating manifests ---" -ForegroundColor Yellow

$winSha256 = (Get-FileHash $windowsVersionedZip -Algorithm SHA256).Hash

$launcherSha256 = ""
if (Test-Path $launcherZip) {
	$launcherSha256 = (Get-FileHash $launcherZip -Algorithm SHA256).Hash
}

$manifestObj = @{
	version    = $Version
	build      = $Build
	zip_url    = "http://$ServerIp/downloads/Bobux-Windows-$Version-build$Build.zip"
	sha256     = $winSha256
	executable = "Bobux.exe"
	embedded_pck = $true
	compat_executables = @()
	mirrors    = @(
		"http://$ServerIp/downloads/Bobux-Windows-$Version-build$Build.zip"
		"http://$ServerIp/downloads/Bobux-Windows.zip"
	)
	launcher   = @{
		version = $LauncherVersion
		build   = $LauncherBuild
		zip_url = "http://$ServerIp/downloads/BobuxLauncher-Windows.zip"
		sha256  = $launcherSha256
		mirrors = @(
			"http://$ServerIp/downloads/BobuxLauncher-Windows.zip"
		)
	}
	notes      = $ReleaseNotes
}
[System.IO.File]::WriteAllText($launcherManifest, ($manifestObj | ConvertTo-Json -Depth 4), $utf8NoBom)
Write-Host "  OK: $launcherManifest" -ForegroundColor Green

if (-not $SkipMobile) {
	$mobileSha256 = (Get-FileHash $mobileApkVersioned -Algorithm SHA256).Hash
	$mobileManifestObj = @{
		version = $MobileVersion
		build   = $MobileBuild
		android = @{
			version           = $MobileVersion
			build             = $MobileBuild
			apk_url           = "http://$ServerIp/mobile/Bobux-Android.apk"
			versioned_apk_url = "http://$ServerIp/mobile/Bobux-Android-$MobileVersion-build$MobileBuild.apk"
			sha256            = $mobileSha256
			required          = $true
			notes             = $MobileReleaseNotes
		}
	}
	[System.IO.File]::WriteAllText($mobileManifest, ($mobileManifestObj | ConvertTo-Json -Depth 4), $utf8NoBom)
	Write-Host "  OK: $mobileManifest" -ForegroundColor Green
}

# ================================================================
#  STEP 7: Upload and deploy to VPS
# ================================================================
if ($SkipUpload) {
	Write-Host ""
	Write-Host "--- Step 7/7: Skipping upload (-SkipUpload) ---" -ForegroundColor DarkGray
	Write-Host ""
	Write-Host "Build artifacts are ready in:" -ForegroundColor Green
	Write-Host "  $windowsVersionedZip"
	Write-Host "  $hotfix"
	if (-not $SkipMobile) { Write-Host "  $mobileApkVersioned" }
	Write-Host ""
	exit 0
}

Write-Host ""
Write-Host "--- Step 7/7: Uploading and deploying to $Server ---" -ForegroundColor Yellow

$hotfixSha256 = (Get-FileHash $hotfix -Algorithm SHA256).Hash

Write-Host "  Uploading hotfix tarball..."
scp $hotfix "${Server}:/tmp/bobux-hotfix.tar.gz"

Write-Host "  Uploading launcher manifest..."
scp $launcherManifest "${Server}:/tmp/latest.json"

Write-Host "  Uploading Windows ZIP..."
scp $windowsZip "${Server}:/tmp/Bobux-Windows.zip"
scp $windowsVersionedZip "${Server}:/tmp/Bobux-Windows-$Version-build$Build.zip"

if (Test-Path $launcherZip) {
	Write-Host "  Uploading Launcher ZIP..."
	scp $launcherZip "${Server}:/tmp/BobuxLauncher-Windows.zip"
}

if (-not $SkipMobile) {
	Write-Host "  Uploading mobile manifest..."
	scp $mobileManifest "${Server}:/tmp/mobile-latest.json"
	Write-Host "  Uploading mobile APK..."
	scp $mobileApkLatest "${Server}:/tmp/Bobux-Android.apk"
	scp $mobileApkVersioned "${Server}:/tmp/Bobux-Android-$MobileVersion-build$MobileBuild.apk"
}

Write-Host "  Uploading deploy_remote.sh..."
scp (Join-Path $projectRoot "ops\vps\deploy_remote.sh") "${Server}:/tmp/deploy_remote.sh"

Write-Host "  OK: All files uploaded" -ForegroundColor Green

# ---- Remote install ----
Write-Host ""
Write-Host "  Running remote install..." -ForegroundColor Yellow

$mobileRemoteBlock = ""
if (-not $SkipMobile) {
	$mobileRemoteBlock = "mkdir -p $WebRoot/mobile && cp /tmp/mobile-latest.json $WebRoot/mobile/latest.json && cp /tmp/Bobux-Android.apk $WebRoot/mobile/Bobux-Android.apk && cp /tmp/Bobux-Android-$MobileVersion-build$MobileBuild.apk $WebRoot/mobile/Bobux-Android-$MobileVersion-build$MobileBuild.apk && chmod 644 $WebRoot/mobile/* && echo 'OK: Mobile deployed'"
}

$remoteCommands = @(
	"set -e"
	"echo '=== Bobux Remote Deploy v$Version build $Build ==='"
	"echo '$hotfixSha256  /tmp/bobux-hotfix.tar.gz' | sha256sum -c -"
	"echo '$winSha256  /tmp/Bobux-Windows.zip' | sha256sum -c -"
	"echo '$winSha256  /tmp/Bobux-Windows-$Version-build$Build.zip' | sha256sum -c -"
	"echo '$launcherSha256  /tmp/BobuxLauncher-Windows.zip' | sha256sum -c -"
	"mkdir -p $RemoteRoot $WebRoot/launcher $WebRoot/downloads /var/log/bobux"
	"tar -xzf /tmp/bobux-hotfix.tar.gz -C $RemoteRoot"
	"echo 'OK: Server code extracted'"
	"test -f $RemoteRoot/ops/vps/index.html && cp $RemoteRoot/ops/vps/index.html $WebRoot/index.html"
	"test -f $RemoteRoot/ops/vps/admin.html && cp $RemoteRoot/ops/vps/admin.html $WebRoot/admin.html"
	"cp /tmp/latest.json $WebRoot/launcher/latest.json"
	"cp /tmp/latest.json $WebRoot/downloads/latest.json"
	"cp /tmp/Bobux-Windows.zip $WebRoot/downloads/Bobux-Windows.zip"
	"test -f /tmp/Bobux-Windows-$Version-build$Build.zip && cp /tmp/Bobux-Windows-$Version-build$Build.zip $WebRoot/downloads/Bobux-Windows-$Version-build$Build.zip || true"
	"test -f /tmp/BobuxLauncher-Windows.zip && cp /tmp/BobuxLauncher-Windows.zip $WebRoot/downloads/BobuxLauncher-Windows.zip || true"
	"chmod 644 $WebRoot/index.html $WebRoot/admin.html $WebRoot/launcher/* $WebRoot/downloads/* 2>/dev/null || true"
	"echo 'OK: Windows builds deployed'"
)
if ($mobileRemoteBlock -ne "") {
	$remoteCommands += "echo '$mobileSha256  /tmp/Bobux-Android.apk' | sha256sum -c -"
	$remoteCommands += "echo '$mobileSha256  /tmp/Bobux-Android-$MobileVersion-build$MobileBuild.apk' | sha256sum -c -"
	$remoteCommands += $mobileRemoteBlock
}
$remoteCommands += @(
	"test -f $RemoteRoot/ops/vps/bobux_nginx.conf || { echo 'FAIL: Missing $RemoteRoot/ops/vps/bobux_nginx.conf'; exit 1; }"
	"cp $RemoteRoot/ops/vps/bobux_nginx.conf /etc/nginx/sites-available/bobux && ln -sf /etc/nginx/sites-available/bobux /etc/nginx/sites-enabled/bobux && rm -f /etc/nginx/sites-enabled/default && nginx -t && systemctl reload nginx && echo 'OK: Nginx reloaded'"
	"test -d $RemoteRoot/services/bobux_api || { echo 'FAIL: Missing Bobux API source in $RemoteRoot/services/bobux_api'; exit 1; }"
	"mkdir -p /opt/bobux-api; rsync -a --delete --exclude='.env' --exclude='node_modules' $RemoteRoot/services/bobux_api/ /opt/bobux-api/; test ! -f /opt/bobux-api/.env && test -f /opt/bobux-api/.env.example && cp /opt/bobux-api/.env.example /opt/bobux-api/.env; cd /opt/bobux-api; npm install --omit=dev 2>/dev/null || true; pm2 delete bobux-api 2>/dev/null || true; test -f /opt/bobux-api/.env && { set -a; . /opt/bobux-api/.env; set +a; }; pm2 start /opt/bobux-api/server.js --name bobux-api --update-env; echo 'OK: API restarted'"
	"GODOT_BIN=/usr/local/bin/godot; if [ -x `$GODOT_BIN ]; then cd $RemoteRoot; `$GODOT_BIN --headless --import --path $RemoteRoot || true; pm2 delete bobux 2>/dev/null || true; PUBLIC_SERVER_WS_URL='ws://$ServerIp/ws' GODOT_SERVER_PORT='9000' GODOT_SERVER_MAP='classic' BOBUX_API_URL='$BobuxApiUrl' BOBUX_SERVICE_KEY='$BobuxServiceKey' BOBUX_SERVER_HEARTBEAT_TOKEN='$HeartbeatToken' pm2 start `$GODOT_BIN --name bobux -- --headless --path $RemoteRoot --script res://server/server_main.gd; echo 'OK: Game server restarted'; else echo 'WARN: Godot not found - run deploy_remote.sh for full install'; fi"
	"sleep 2"
	"curl -fsS http://127.0.0.1:3000/api/health | grep -q '""ok"":true' || { echo 'FAIL: Bobux API is not healthy on 127.0.0.1:3000'; exit 1; }"
	"curl -fsS http://127.0.0.1/launcher/latest.json >/dev/null || { echo 'FAIL: nginx is not serving /launcher/latest.json'; exit 1; }"
	"curl -fsS http://127.0.0.1/api/health | grep -q '""ok"":true' || { echo 'FAIL: public /api is not routed to Bobux API'; exit 1; }"
	"echo '$winSha256  $WebRoot/downloads/Bobux-Windows-$Version-build$Build.zip' | sha256sum -c -"
	"echo '$launcherSha256  $WebRoot/downloads/BobuxLauncher-Windows.zip' | sha256sum -c -"
	"AUTH_CODE=`$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{""email"":""bobux-healthcheck@example.invalid"",""password"":""bad-password""}' 'http://127.0.0.1/api/auth/v1/token?grant_type=password' || echo 000); case `$AUTH_CODE in 200|400|401|422|429) echo ""OK: Auth route reachable (`$AUTH_CODE)"" ;; *) echo ""FAIL: auth endpoint returned `$AUTH_CODE""; exit 1 ;; esac"
	"pm2 save"
	"echo ''"
	"echo '=== DEPLOY COMPLETE ==='"
)

$remoteScript = $remoteCommands -join "; "
ssh $Server "bash -c '$($remoteScript -replace "'","'\''")'"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "  DEPLOY COMPLETE!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Verify:" -ForegroundColor Cyan
Write-Host "    http://$ServerIp/launcher/latest.json"
Write-Host "    http://$ServerIp/downloads/Bobux-Windows.zip"
Write-Host "    http://$ServerIp/downloads/Bobux-Windows-$Version-build$Build.zip"
if (-not $SkipMobile) {
	Write-Host "    http://$ServerIp/mobile/latest.json"
Write-Host "    http://$ServerIp/mobile/Bobux-Android.apk"
}
Write-Host "    http://$ServerIp/health"
Write-Host "    http://$ServerIp/api/health"
Write-Host ""
