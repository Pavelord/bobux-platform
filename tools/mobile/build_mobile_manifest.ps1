param(
    [Parameter(Mandatory=$true)]
    [string]$ApkPath,

    [string]$Version = "0.1.0-mobile",
    [int]$Build = 1,
    [string]$BaseUrl = "http://109.71.245.162/mobile",
    [string]$OutputPath = "mobile/latest.json"
)

$resolvedApk = Resolve-Path -LiteralPath $ApkPath
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedApk).Hash
$apkName = Split-Path -Leaf $resolvedApk
$manifest = [ordered]@{
    version = $Version
    build = $Build
    android = [ordered]@{
        version = $Version
        build = $Build
        apk_url = "$BaseUrl/Bobux-Android.apk"
        versioned_apk_url = "$BaseUrl/$apkName"
        sha256 = $hash
        required = $true
        notes = "A new Bobux mobile beta is available. Download it to keep playing with PC friends."
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$json = $manifest | ConvertTo-Json -Depth 8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath (Split-Path -Parent $OutputPath)).Path + "\" + (Split-Path -Leaf $OutputPath), $json, $utf8NoBom)
Write-Host "Manifest written to $OutputPath"
Write-Host "SHA256: $hash"
