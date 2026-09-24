# tests/sections/overload.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

Section 'overload and status.claude.com'
$lt = Get-ChatqLastTurn $pOver
Check 'a chat stopped by a 529 is recognised' ($lt.Overloaded -and -not $lt.Limit) "over=$($lt.Overloaded) limit=$($lt.Limit)"
$cut = @(Get-ChatqCutOffChats @())
Check '529-stopped chat listed as cut off' (@($cut | Where-Object { $_.Id -eq $idOver -and $_.Why -eq 'overloaded' }).Count -eq 1)
$script:ChatqStatusUrl = $statusFile
Set-FakeStatus 'major_outage'
Check 'status page read' ((Get-ChatqClaudeStatus) -eq 'major_outage') (Get-ChatqClaudeStatus)
$Wo = New-ChatqWatchState
$fakeJob = [pscustomobject]@{ provider = 'claude'; home = $claudeHome; title = 'x'; model = $null; cwd = $projA }
Enter-ChatqOutage $Wo $fakeJob 'API Error: 529'
$lane = Get-ChatqLane $fakeJob
Check 'first retry waits a minute' ([Math]::Abs(($Wo.outage[$lane].NextCheck - (Get-Date).AddMinutes(1)).TotalSeconds) -lt 5)
$Wo.outage[$lane].NextCheck = (Get-Date).AddSeconds(-1)
Check 'outage page: no probe yet' (-not (Test-ChatqOutageOver $Wo $fakeJob))
Check 'then the page is polled every minute' ([Math]::Abs(($Wo.outage[$lane].NextCheck - (Get-Date).AddSeconds(60)).TotalSeconds) -lt 5)
Set-FakeStatus 'operational'
$Wo.outage[$lane].NextCheck = (Get-Date).AddSeconds(-1)
Check 'operational again: probe at once' (Test-ChatqOutageOver $Wo $fakeJob)
Set-FakeStatus 'partial_outage'
$Wo.outage[$lane].NextCheck = (Get-Date).AddSeconds(-1)
$Wo.outage[$lane].LastProbe = (Get-Date).AddMinutes(-16)
Check 'page lagging for 15 min: probe anyway' (Test-ChatqOutageOver $Wo $fakeJob)
Set-FakeStatus 'operational'
$Wo.outage[$lane].NextCheck = (Get-Date).AddSeconds(-1)
Check 'a good probe ends the outage' ((Confirm-ChatqAllowed $Wo $fakeJob) -and -not $Wo.outage[$lane])
$alerts0 = if (Test-Path -LiteralPath (Join-Path $script:ChatqLogDir 'alerts.log')) { [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'alerts.log'), $utf8) } else { '' }
Check 'one overloaded alert' (([regex]::Matches($alerts0, "`toverloaded`t")).Count -eq 1)
