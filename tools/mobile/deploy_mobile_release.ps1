param(
    [Parameter(Mandatory=$true)]
    [string]$ApkPath,

    [string]$Version = "0.1.0-mobile",
    [int]$Build = 1,
    [string]$Server = "root@109.71.245.162",
    [string]$RemoteDir = "/var/www/bobux/mobile",
    [string]$BaseUrl = "http://109.71.245.162/mobile"
)

$resolvedApk = Resolve-Path -LiteralPath $ApkPath
$apkName = Split-Path -Leaf $resolvedApk
$manifestPath = "mobile/latest.json"

& "$PSScriptRoot\build_mobile_manifest.ps1" -ApkPath $resolvedApk -Version $Version -Build $Build -BaseUrl $BaseUrl -OutputPath $manifestPath
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Failed to build mobile manifest at $manifestPath."
}

ssh $Server "mkdir -p $RemoteDir"
scp $resolvedApk "${Server}:$RemoteDir/$apkName"
scp $manifestPath "${Server}:$RemoteDir/latest.json"
ssh $Server "cp $RemoteDir/$apkName $RemoteDir/Bobux-Android.apk && chmod 644 $RemoteDir/$apkName $RemoteDir/Bobux-Android.apk $RemoteDir/latest.json"

Write-Host "Uploaded mobile release:"
Write-Host "$BaseUrl/latest.json"
Write-Host "$BaseUrl/Bobux-Android.apk"
