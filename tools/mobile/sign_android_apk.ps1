param(
    [Parameter(Mandatory=$true)]
    [string]$InputApk,

    [string]$OutputApk = "",
    [string]$AndroidSdkPath = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$JavaSdkPath = "C:\Program Files\Android\Android Studio\jbr",
    [string]$KeystorePath = "C:\robloxclone\tools\mobile\bobux_debug.keystore",
    [string]$Alias = "bobuxdebug",
    [string]$Password = "android"
)

$resolvedInput = Resolve-Path -LiteralPath $InputApk
if ($OutputApk.Trim().Length -eq 0) {
    $directory = Split-Path -Parent $resolvedInput
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInput)
    $OutputApk = Join-Path $directory "$baseName-signed.apk"
}

$env:JAVA_HOME = $JavaSdkPath
$env:PATH = "$JavaSdkPath\bin;$env:PATH"

$apksigner = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkPath "build-tools") -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if (-not $apksigner) {
    throw "apksigner.bat was not found under $AndroidSdkPath\build-tools"
}

if (-not (Test-Path -LiteralPath $KeystorePath)) {
    $keytool = Join-Path $JavaSdkPath "bin\keytool.exe"
    if (-not (Test-Path -LiteralPath $keytool)) {
        throw "keytool.exe was not found under $JavaSdkPath\bin"
    }
    & $keytool -genkeypair -v -keystore $KeystorePath -storepass $Password -keypass $Password -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Bobux Debug,O=Bobux,C=RU"
}

if (Test-Path -LiteralPath $OutputApk) {
    Remove-Item -LiteralPath $OutputApk -Force
}

& $apksigner.FullName sign --ks $KeystorePath --ks-key-alias $Alias --ks-pass "pass:$Password" --key-pass "pass:$Password" --out $OutputApk $resolvedInput
if ($LASTEXITCODE -ne 0) {
    throw "APK signing failed."
}

& $apksigner.FullName verify --verbose $OutputApk
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed."
}

Write-Host "Signed APK: $OutputApk"
