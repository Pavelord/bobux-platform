param(
	[string]$GodotExe = "C:\Users\Pavel\Desktop\Godot_v4.6.1-stable_win64_console.exe",
	[string]$ProjectPath = "C:\robloxclone",
	[int]$QuitAfterFrames = 900,
	[int]$LobbyLoops = 3,
	[int]$ScenarioTimeoutSec = 120,
	[switch]$VerboseLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
	throw "Godot executable not found: $GodotExe"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportRoot = Join-Path $ProjectPath "stress_reports\$timestamp"
$logsDir = Join-Path $reportRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

function Get-RegexCount {
	param(
		[string]$Text,
		[string]$Pattern
	)
	if ([string]::IsNullOrEmpty($Text)) {
		return 0
	}
	return [regex]::Matches($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::Multiline).Count
}

function Analyze-Log {
	param([string]$LogText)

	$errors = Get-RegexCount -Text $LogText -Pattern '^(ERROR:|SCRIPT ERROR:|E\s+\d)'
	$warnings = Get-RegexCount -Text $LogText -Pattern '^(WARNING:|SCRIPT WARNING:|W\s+\d)'
	$parseErrors = Get-RegexCount -Text $LogText -Pattern '(Parse Error|Failed to load script|Unexpected "`")'
	$hostTimeouts = Get-RegexCount -Text $LogText -Pattern '(Connection timed out before the room host responded|Host migration timed out|No replacement host was found)'
	$nullPeerAccess = Get-RegexCount -Text $LogText -Pattern '(multiplayer instance isn.t currently active|No multiplayer peer is assigned)'
	$peerPollSpam = Get-RegexCount -Text $LogText -Pattern '!connected_peers\.has\(sender\)'

	return [ordered]@{
		errors = $errors
		warnings = $warnings
		parse_errors = $parseErrors
		host_timeouts = $hostTimeouts
		null_peer_access = $nullPeerAccess
		peer_poll_spam = $peerPollSpam
	}
}

function Run-GodotScenario {
	param(
		[string]$Name,
		[string[]]$Arguments,
		[string]$OutputPrefix,
		[int]$TimeoutSec
	)

	$stdoutPath = Join-Path $logsDir "$OutputPrefix.stdout.log"
	$stderrPath = Join-Path $logsDir "$OutputPrefix.stderr.log"
	$mergedPath = Join-Path $logsDir "$OutputPrefix.log"

	$sw = [Diagnostics.Stopwatch]::StartNew()
	$proc = Start-Process -FilePath $GodotExe -ArgumentList $Arguments -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
	$cores = [Math]::Max(1, [Environment]::ProcessorCount)
	$peakCpu = 0.0
	$peakRamMb = 0.0
	$timedOut = $false

	$lastCpu = 0.0
	try {
		$lastCpu = [double]$proc.CPU
	} catch {
		$lastCpu = 0.0
	}
	$lastSample = Get-Date

	while (-not $proc.HasExited) {
		Start-Sleep -Milliseconds 250
		$proc.Refresh()
		$now = Get-Date
		$elapsed = ($now - $lastSample).TotalSeconds
		if ($elapsed -le 0) {
			$elapsed = 0.25
		}

		$cpuNow = $lastCpu
		try {
			$cpuNow = [double]$proc.CPU
		} catch {
			$cpuNow = $lastCpu
		}
		$deltaCpu = [Math]::Max(0.0, $cpuNow - $lastCpu)
		$cpuPct = ($deltaCpu / $elapsed) * (100.0 / $cores)
		if ($cpuPct -gt $peakCpu) {
			$peakCpu = $cpuPct
		}

		$ramMb = 0.0
		try {
			$ramMb = [double]$proc.WorkingSet64 / 1MB
		} catch {
			$ramMb = 0.0
		}
		if ($ramMb -gt $peakRamMb) {
			$peakRamMb = $ramMb
		}

		$lastCpu = $cpuNow
		$lastSample = $now

		if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
			try {
				$proc.Kill()
			} catch {
			}
			$timedOut = $true
			break
		}
	}
	$sw.Stop()

	$stdoutText = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
	$stderrText = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
	$logText = "$stdoutText`r`n$stderrText"
	Set-Content -Path $mergedPath -Value $logText -Encoding UTF8

	$analysis = Analyze-Log -LogText $logText
	$status = "PASS"
	if ($timedOut -or [int]$analysis.parse_errors -gt 0 -or [int]$analysis.errors -gt 0) {
		$status = "FAIL"
	} elseif ([int]$analysis.host_timeouts -gt 0 -or [int]$analysis.null_peer_access -gt 0) {
		$status = "WARN"
	}

	return [PSCustomObject]@{
		scenario = $Name
		status = $status
		duration_s = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
		peak_cpu_pct = [Math]::Round($peakCpu, 2)
		peak_ram_mb = [Math]::Round($peakRamMb, 2)
		errors = [int]$analysis.errors
		warnings = [int]$analysis.warnings
		parse_errors = [int]$analysis.parse_errors
		host_timeouts = [int]$analysis.host_timeouts
		null_peer_access = [int]$analysis.null_peer_access
		peer_poll_spam = [int]$analysis.peer_poll_spam
		timed_out = $timedOut
		log = $mergedPath
	}
}

function Run-ConcurrentGodotScenario {
	param(
		[string]$Name,
		[string[]]$Arguments,
		[string]$OutputPrefix,
		[int]$TimeoutSec
	)

	$userDataA = Join-Path $reportRoot "userdata_a"
	$userDataB = Join-Path $reportRoot "userdata_b"
	New-Item -ItemType Directory -Force -Path $userDataA, $userDataB | Out-Null

	$stdoutA = Join-Path $logsDir "$OutputPrefix.a.stdout.log"
	$stderrA = Join-Path $logsDir "$OutputPrefix.a.stderr.log"
	$stdoutB = Join-Path $logsDir "$OutputPrefix.b.stdout.log"
	$stderrB = Join-Path $logsDir "$OutputPrefix.b.stderr.log"
	$mergedPath = Join-Path $logsDir "$OutputPrefix.log"

	$argsA = @($Arguments + @("--user-data-dir", $userDataA))
	$argsB = @($Arguments + @("--user-data-dir", $userDataB))

	$procA = Start-Process -FilePath $GodotExe -ArgumentList $argsA -PassThru -RedirectStandardOutput $stdoutA -RedirectStandardError $stderrA
	$procB = Start-Process -FilePath $GodotExe -ArgumentList $argsB -PassThru -RedirectStandardOutput $stdoutB -RedirectStandardError $stderrB

	$sw = [Diagnostics.Stopwatch]::StartNew()
	$cores = [Math]::Max(1, [Environment]::ProcessorCount)
	$peakCpu = 0.0
	$peakRamMb = 0.0
	$timedOut = $false

	$lastCpuA = 0.0
	$lastCpuB = 0.0
	try { $lastCpuA = [double]$procA.CPU } catch { $lastCpuA = 0.0 }
	try { $lastCpuB = [double]$procB.CPU } catch { $lastCpuB = 0.0 }
	$lastSample = Get-Date

	while ((-not $procA.HasExited) -or (-not $procB.HasExited)) {
		Start-Sleep -Milliseconds 250
		$procA.Refresh()
		$procB.Refresh()
		$now = Get-Date
		$elapsed = ($now - $lastSample).TotalSeconds
		if ($elapsed -le 0) {
			$elapsed = 0.25
		}

		$cpuNowA = $lastCpuA
		$cpuNowB = $lastCpuB
		try { $cpuNowA = [double]$procA.CPU } catch { $cpuNowA = $lastCpuA }
		try { $cpuNowB = [double]$procB.CPU } catch { $cpuNowB = $lastCpuB }

		$deltaCpu = [Math]::Max(0.0, $cpuNowA - $lastCpuA) + [Math]::Max(0.0, $cpuNowB - $lastCpuB)
		$cpuPct = ($deltaCpu / $elapsed) * (100.0 / $cores)
		if ($cpuPct -gt $peakCpu) {
			$peakCpu = $cpuPct
		}

		$ramA = 0.0
		$ramB = 0.0
		try { $ramA = [double]$procA.WorkingSet64 / 1MB } catch { $ramA = 0.0 }
		try { $ramB = [double]$procB.WorkingSet64 / 1MB } catch { $ramB = 0.0 }
		$ramSum = $ramA + $ramB
		if ($ramSum -gt $peakRamMb) {
			$peakRamMb = $ramSum
		}

		$lastCpuA = $cpuNowA
		$lastCpuB = $cpuNowB
		$lastSample = $now

		if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
			foreach ($p in @($procA, $procB)) {
				if (-not $p.HasExited) {
					try { $p.Kill() } catch {}
				}
			}
			$timedOut = $true
			break
		}
	}
	$sw.Stop()

	$textA = ""
	$textB = ""
	if (Test-Path $stdoutA) { $textA += (Get-Content $stdoutA -Raw) + "`r`n" }
	if (Test-Path $stderrA) { $textA += (Get-Content $stderrA -Raw) + "`r`n" }
	if (Test-Path $stdoutB) { $textB += (Get-Content $stdoutB -Raw) + "`r`n" }
	if (Test-Path $stderrB) { $textB += (Get-Content $stderrB -Raw) + "`r`n" }
	$logText = "[Instance A]`r`n$textA`r`n[Instance B]`r`n$textB"
	Set-Content -Path $mergedPath -Value $logText -Encoding UTF8

	$analysis = Analyze-Log -LogText $logText
	$status = "PASS"
	if ($timedOut -or [int]$analysis.parse_errors -gt 0 -or [int]$analysis.errors -gt 0) {
		$status = "FAIL"
	} elseif ([int]$analysis.host_timeouts -gt 0 -or [int]$analysis.null_peer_access -gt 0) {
		$status = "WARN"
	}

	return [PSCustomObject]@{
		scenario = $Name
		status = $status
		duration_s = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
		peak_cpu_pct = [Math]::Round($peakCpu, 2)
		peak_ram_mb = [Math]::Round($peakRamMb, 2)
		errors = [int]$analysis.errors
		warnings = [int]$analysis.warnings
		parse_errors = [int]$analysis.parse_errors
		host_timeouts = [int]$analysis.host_timeouts
		null_peer_access = [int]$analysis.null_peer_access
		peer_poll_spam = [int]$analysis.peer_poll_spam
		timed_out = $timedOut
		log = $mergedPath
	}
}

function Run-StaticChecks {
	$gdFiles = Get-ChildItem (Join-Path $ProjectPath "autoload"), (Join-Path $ProjectPath "scripts") -Recurse -Filter *.gd
	$nonAsciiHits = 0
	$whileTrueHits = 0
	$instantiateInFrameHits = 0

	foreach ($file in $gdFiles) {
		$text = [IO.File]::ReadAllText($file.FullName)
		$nonAsciiHits += [regex]::Matches($text, '[^\u0000-\u007F]').Count
		$whileTrueHits += [regex]::Matches($text, '\bwhile\s+true\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count

		$lines = Get-Content $file.FullName
		$inFrameFunc = $false
		foreach ($line in $lines) {
			if ($line -match '^\s*func\s+(_process|_physics_process)\b') {
				$inFrameFunc = $true
				continue
			}
			if ($line -match '^\s*func\s+') {
				$inFrameFunc = $false
			}
			if ($inFrameFunc -and $line -match '\.instantiate\s*\(') {
				$instantiateInFrameHits += 1
			}
		}
	}

	$status = "PASS"
	if ($nonAsciiHits -gt 0 -or $whileTrueHits -gt 0 -or $instantiateInFrameHits -gt 0) {
		$status = "WARN"
	}

	return [PSCustomObject]@{
		scenario = "Static checks"
		status = $status
		duration_s = 0.0
		peak_cpu_pct = 0.0
		peak_ram_mb = 0.0
		errors = 0
		warnings = 0
		parse_errors = 0
		host_timeouts = 0
		null_peer_access = 0
		peer_poll_spam = 0
		timed_out = $false
		log = "non_ascii=$nonAsciiHits; while_true=$whileTrueHits; instantiate_in_frame=$instantiateInFrameHits"
	}
}

function Write-Report {
	param(
		[array]$Rows,
		[string]$Path
	)

	$md = New-Object System.Collections.Generic.List[string]
	$md.Add("# Stress Harness Report")
	$md.Add("")
	$md.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
	$md.Add("")
	$md.Add("| Scenario | Status | Duration(s) | Peak CPU(%) | Peak RAM(MB) | Errors | Warnings | Parse | HostTimeout | NullPeer | PollSpam | Timeout | Log |")
	$md.Add("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")

	foreach ($row in $Rows) {
		$md.Add("| $($row.scenario) | $($row.status) | $($row.duration_s) | $($row.peak_cpu_pct) | $($row.peak_ram_mb) | $($row.errors) | $($row.warnings) | $($row.parse_errors) | $($row.host_timeouts) | $($row.null_peer_access) | $($row.peer_poll_spam) | $($row.timed_out) | $($row.log) |")
	}

	$failCount = @($Rows | Where-Object { $_.status -eq "FAIL" }).Count
	$warnCount = @($Rows | Where-Object { $_.status -eq "WARN" }).Count
	$md.Add("")
	$md.Add("Summary: fail=$failCount warn=$warnCount total=$($Rows.Count)")
	$md.Add("")
	$md.Add("Notes:")
	$md.Add("- Headless quit-after runs may report ObjectDB leaks because the engine is forced to exit while async requests are still in flight.")
	$md.Add("- FAIL is only used for parse/runtime hard errors, explicit timeouts, or non-zero ERROR signatures.")

	Set-Content -Path $Path -Value $md -Encoding UTF8
}

$scenarioRows = New-Object System.Collections.Generic.List[object]
$commonArgs = @("--headless", "--path", $ProjectPath)
if ($VerboseLogs) {
	$commonArgs = @("--verbose", "--headless", "--path", $ProjectPath)
}

$scenarioRows.Add((Run-StaticChecks))
$scenarioRows.Add((Run-GodotScenario -Name "Boot Login" -Arguments ($commonArgs + @("res://scenes/login/login.tscn", "--quit-after", "$QuitAfterFrames")) -OutputPrefix "boot_login" -TimeoutSec $ScenarioTimeoutSec))
$scenarioRows.Add((Run-GodotScenario -Name "Boot Lobby" -Arguments ($commonArgs + @("res://scenes/lobby/lobby.tscn", "--quit-after", "$QuitAfterFrames")) -OutputPrefix "boot_lobby" -TimeoutSec $ScenarioTimeoutSec))
$scenarioRows.Add((Run-GodotScenario -Name "Boot Main" -Arguments ($commonArgs + @("res://scenes/main/main.tscn", "--quit-after", "$QuitAfterFrames")) -OutputPrefix "boot_main" -TimeoutSec $ScenarioTimeoutSec))

for ($i = 1; $i -le $LobbyLoops; $i++) {
	$scenarioRows.Add((Run-GodotScenario -Name ("Lobby Loop #{0}" -f $i) -Arguments ($commonArgs + @("res://scenes/lobby/lobby.tscn", "--quit-after", "$QuitAfterFrames")) -OutputPrefix ("lobby_loop_{0}" -f $i) -TimeoutSec $ScenarioTimeoutSec))
}

$scenarioRows.Add((Run-ConcurrentGodotScenario -Name "Parallel Lobby x2" -Arguments ($commonArgs + @("res://scenes/lobby/lobby.tscn", "--quit-after", "$QuitAfterFrames")) -OutputPrefix "parallel_lobby_2x" -TimeoutSec $ScenarioTimeoutSec))

$reportPath = Join-Path $reportRoot "stress_table.md"
Write-Report -Rows $scenarioRows -Path $reportPath

$latestReportPath = Join-Path $ProjectPath "docs\stress_table_latest.md"
Set-Content -Path $latestReportPath -Value (Get-Content $reportPath -Raw) -Encoding UTF8

Write-Output "Stress harness complete."
Write-Output "Report: $reportPath"
Write-Output "Latest: $latestReportPath"
