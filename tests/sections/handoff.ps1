# tests/sections/handoff.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

Section 'watcher handoff'
$Wh = New-ChatqWatchState
$Wh.blocked['claude'] = [pscustomobject]@{ Until = (Get-Date).AddHours(2); Type = 'five_hour'; Source = 'probe' }
$Wh.outage['codex'] = @{ Since = (Get-Date).AddMinutes(-30); Attempts = 2; Status = $null; Alerted = $true; Reminded = $false; LastProbe = (Get-Date).AddMinutes(-5); NextCheck = (Get-Date).AddMinutes(1) }
$Wh.authAlerted['claude|x'] = $true
$Wh.handoff = $true
Save-ChatqWatchState $Wh
$Wg = New-ChatqWatchState
Check 'a successor carries on from the watcher before it' ((Restore-ChatqWatchState $Wg) -and $Wg.blocked['claude'].Type -eq 'five_hour' -and $Wg.outage['codex'].Alerted -and $Wg.authAlerted['claude|x'])
$Wh.handoff = $false
Save-ChatqWatchState $Wh
Check 'a cold start asks again instead' (-not (Restore-ChatqWatchState (New-ChatqWatchState)))
$script:Spawned = 0
$script:ChatqSpawn = { $script:Spawned++; $true }
Lock-Queue { chatq 'Deadline notes' -Prompt 'keep the loop busy' *> $null }
Save-ChatqText $script:ChatqRestartPath 'restart'
Invoke-ChatqWatchLoop *> $null
$sh = Get-ChatqState
Check 'a restart request hands over: lock let go, successor started, state kept' ($script:Spawned -eq 1 -and -not (Test-ChatqWatcherAlive) -and $sh.handoff -and -not (Test-Path -LiteralPath $script:ChatqRestartPath)) "spawned $($script:Spawned) handoff $($sh.handoff)"
Save-ChatqText $script:ChatqRestartPath 'restart'
$env:FAKE_RECORD = $rec
# -Now, or the loop waits out the sandbox's own two-hour limit record
Send-ChatqWake 'now'
Invoke-ChatqWatchLoop -Foreground *> $null
Remove-Item env:FAKE_RECORD
Check 'never in a console someone is watching' ($script:Spawned -eq 1 -and (Test-Path -LiteralPath $script:ChatqRestartPath))
Remove-Item -LiteralPath $script:ChatqRestartPath -Force
$script:ChatqSpawn = { $true }
