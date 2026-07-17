param(
    [string]$AndroidSdkPath = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$JavaSdkPath = "C:\Program Files\Android\Android Studio\jbr"
)

$failed = $false

function Test-RequiredPath {
    param(
        [string]$Label,
        [string]$Path
    )
    if (Test-Path -LiteralPath $Path) {
        Write-Host "[OK] $Label -> $Path" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $Label -> $Path" -ForegroundColor Red
        $script:failed = $true
    }
}

Write-Host "Checking Bobux Android export toolchain..."
Write-Host "Android SDK: $AndroidSdkPath"
Write-Host "Java SDK:    $JavaSdkPath"
Write-Host ""

Test-RequiredPath "Android SDK root" $AndroidSdkPath
Test-RequiredPath "platform-tools" (Join-Path $AndroidSdkPath "platform-tools")
Test-RequiredPath "adb" (Join-Path $AndroidSdkPath "platform-tools\adb.exe")
Test-RequiredPath "build-tools" (Join-Path $AndroidSdkPath "build-tools")
Test-RequiredPath "cmdline-tools" (Join-Path $AndroidSdkPath "cmdline-tools")
Test-RequiredPath "Java SDK" $JavaSdkPath
Test-RequiredPath "java" (Join-Path $JavaSdkPath "bin\java.exe")

$apksigner = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkPath "build-tools") -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($apksigner) {
    Write-Host "[OK] apksigner -> $($apksigner.FullName)" -ForegroundColor Green
} else {
    Write-Host "[MISSING] apksigner.bat under Android SDK build-tools" -ForegroundColor Red
    $failed = $true
}

if ($failed) {
    Write-Host ""
    Write-Host "Toolchain is not ready yet. Install Android Studio + SDK Platform Tools + Build Tools, then run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Android export toolchain looks ready." -ForegroundColor Green
