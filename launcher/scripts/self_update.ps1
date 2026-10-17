param(
    [Parameter(Mandatory=$true)][int]$OwnerPid,
    [Parameter(Mandatory=$true)][string]$SourceExe,
    [Parameter(Mandatory=$true)][string]$TargetExe,
    [Parameter(Mandatory=$true)][string]$StateRoot,
    [Parameter(Mandatory=$true)][string]$Nonce,
    [Parameter(Mandatory=$true)][string]$ExpectedHash,
    [Parameter(Mandatory=$true)][int]$ExpectedBuild,
    [int]$AckTimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($TargetExe)
$source = [IO.Path]::GetFullPath($SourceExe)
$state = [IO.Path]::GetFullPath($StateRoot)
if ($Nonce -notmatch '^[a-f0-9]{32}$') { exit 2 }
$ready = Join-Path $state ('_launcher_handoff_' + $Nonce + '.ready')
$ack = Join-Path $state ('_launcher_handoff_' + $Nonce + '.ack')
$status = Join-Path $state '_launcher_self_update_status.json'
$log = Join-Path $state 'launcher-update.log'
# These are exact, explicitly supplied executable paths, never directory moves.
$replacement = $target + '.bobux-update-new'
$backup = $target + '.bobux-update-backup'
$mutex = $null
$ownsMutex = $false
$child = $null
$installed = $false
$oldMoved = $false
$helperStartedTicks = ([Diagnostics.Process]::GetCurrentProcess()).StartTime.ToUniversalTime().Ticks.ToString()
function Write-Status([string]$phase, [string]$errorCode = '', [string]$exceptionType = '') {
    $value = @{phase=$phase; error_code=$errorCode; exception_type=$exceptionType; build=$ExpectedBuild; helper_pid=$PID; helper_started_ticks=$helperStartedTicks; owner_pid=$OwnerPid; nonce=$Nonce; time=[DateTime]::UtcNow.ToString('o')}
    $temporaryStatus = $status + '.tmp.' + $PID
    [IO.File]::WriteAllText($temporaryStatus, ($value | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    Retry-FileOperation {
        if ([IO.File]::Exists($status)) { [IO.File]::Replace($temporaryStatus, $status, [NullString]::Value) }
        else { [IO.File]::Move($temporaryStatus, $status) }
    }
    # A competing diagnostic reader/writer must never roll back a good update.
    try { [IO.File]::AppendAllText($log, ([DateTime]::UtcNow.ToString('o') + ' self_update ' + $phase + ' ' + $errorCode + ' ' + $exceptionType + "`r`n")) } catch {}
}
function Get-Sha256([string]$path) {
    # Get-FileHash is a module function and is absent in some clean/32-bit PS
    # installations. The framework stream also avoids reading the EXE into RAM.
    $stream = [IO.File]::OpenRead($path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Retry-FileOperation([scriptblock]$operation) {
    $last = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try { & $operation; return } catch { $last = $_; Start-Sleep -Milliseconds 250 }
    }
    throw $last
}
try {
    [IO.Directory]::CreateDirectory($state) | Out-Null
    if ($source -eq $target -or -not [IO.File]::Exists($source) -or -not [IO.File]::Exists($target)) { throw 'Executable path missing' }
    if ((Get-Sha256 $source) -ne $ExpectedHash.ToLowerInvariant()) { throw 'Source hash mismatch' }
    $sha = [Security.Cryptography.SHA256]::Create()
    $mutexKey = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($target.ToLowerInvariant())))).Replace('-', '')
    $sha.Dispose()
    $mutex = New-Object Threading.Mutex($false, ('Local\BobuxLauncherUpdate_' + $mutexKey))
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'Another self-update helper is active' }
    $owner = Get-Process -Id $OwnerPid -ErrorAction Stop
    Write-Status 'helper_ready'
    [IO.File]::WriteAllText($ready, $Nonce)
    if (-not $owner.WaitForExit(30000)) { throw 'Old launcher did not exit' }
    Write-Status 'applying'
    Retry-FileOperation { [IO.File]::Copy($source, $replacement, $true) }
    if ((Get-Sha256 $replacement) -ne $ExpectedHash.ToLowerInvariant()) { throw 'Replacement hash mismatch' }
    # Do not silently overwrite an un-restored backup from an interrupted update.
    if ([IO.File]::Exists($backup)) { Retry-FileOperation { [IO.File]::Delete($backup) } }
    Retry-FileOperation { [IO.File]::Move($target, $backup) }
    $oldMoved = $true
    Retry-FileOperation { [IO.File]::Move($replacement, $target) }
    $installed = $true
    Write-Status 'starting_visible_launcher'
    $child = Start-Process -FilePath $target -ArgumentList @('--', ('--launcher-handoff=' + $Nonce)) -WorkingDirectory ([IO.Path]::GetDirectoryName($target)) -WindowStyle Normal -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($AckTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ([IO.File]::Exists($ack)) {
            try {
                $reply = [IO.File]::ReadAllText($ack) | ConvertFrom-Json
                if ($reply.nonce -eq $Nonce -and $reply.pid -eq $child.Id -and $reply.build -ge $ExpectedBuild -and $reply.ready -eq $true) {
                    Write-Status 'complete'
                    # Cleanup failure must not undo an acknowledged, working launcher.
                    try { [IO.File]::Delete($backup); [IO.File]::Delete($ready); [IO.File]::Delete($ack) } catch {}
                    exit 0
                }
            } catch {}
        }
        $child.Refresh()
        if ($child.HasExited) { break }
        Start-Sleep -Milliseconds 150
    }
    throw 'New launcher did not acknowledge startup'
} catch {
    $code = if ($installed) { 'new_launcher_no_ack' } elseif ($oldMoved) { 'replacement_failed' } else { 'apply_failed' }
    $exceptionType = $_.Exception.GetType().FullName + ':' + $_.Exception.HResult
    try { Write-Status 'failed' $code $exceptionType } catch {}
    # Only the process started by this helper may be stopped during rollback.
    if ($null -ne $child) { try { $child.Refresh(); if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit(10000) | Out-Null } } catch {} }
    try {
        if ($oldMoved -and [IO.File]::Exists($backup)) {
            if ([IO.File]::Exists($target)) { Retry-FileOperation { [IO.File]::Delete($target) } }
            Retry-FileOperation { [IO.File]::Move($backup, $target) }
        }
        # If the owner is still alive it is showing the error itself.
        if (-not (Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $target -ArgumentList @('--', '--launcher-self-update-recovered') -WorkingDirectory ([IO.Path]::GetDirectoryName($target)) -WindowStyle Normal | Out-Null
        }
    } catch { try { Write-Status 'recovery_failed' 'restore_failed' } catch {} }
    exit 1
} finally {
    if ($ownsMutex -and $null -ne $mutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
