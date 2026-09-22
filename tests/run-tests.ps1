<#
VS-code-chat-manager self-test. No Pester, no network, no model: every claude/codex call goes
to tests/fake-agent.ps1. The exit code is the number of failed checks.

    powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
    pwsh       -NoProfile -File tests/run-tests.ps1

It builds a sandbox in tests/.sandbox - fake Claude and Codex homes whose chats
are generated here with timestamps relative to now, so no fixture ever goes
stale - copies the script into it (its data/ follows the script, so the sandbox
gets its own), and dot-sources that copy. -Keep leaves the sandbox behind.

This file is ASCII: Hangul is written as \uXXXX and decoded by U, because
Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
#>
param([switch]$Keep)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$sb = Join-Path (Join-Path $here '.sandbox') 'run'
if (Test-Path -LiteralPath $sb) { Remove-Item -LiteralPath $sb -Recurse -Force }
$null = New-Item -ItemType Directory -Path $sb -Force
$utf8 = New-Object System.Text.UTF8Encoding $false

function U([string]$s) { [regex]::Unescape($s) }

$script:Pass = 0
$script:Fail = 0
function Check([string]$Name, [bool]$Ok, $Detail) {
    if ($Ok) { $script:Pass++; Write-Host "  ok    $Name" -ForegroundColor Green }
    else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Section([string]$Name) { Write-Host ''; Write-Host "  $Name" -ForegroundColor Cyan }

# --- sandbox -----------------------------------------------------------------
$claudeHome = Join-Path $sb 'claude'
$codexHome = Join-Path $sb 'codex'
$work = Join-Path $sb 'work'
$projA = Join-Path $work 'projA'
$projM = Join-Path $work 'projA-Mobile'
foreach ($d in $claudeHome, $codexHome, $projA, $projM, (Join-Path $sb 'tool')) { $null = New-Item -ItemType Directory -Path $d -Force }
Copy-Item -LiteralPath (Join-Path $root 'VS-code-chat-manager.ps1') -Destination (Join-Path $sb 'tool\VS-code-chat-manager.ps1')

$env:CLAUDE_CONFIG_DIR = $claudeHome
$env:CODEX_HOME = $codexHome
$env:CHATQ_CLAUDE = Join-Path $here 'fake-claude.cmd'
$env:CHATQ_CODEX = Join-Path $here 'fake-claude.cmd'
$env:CHATQ_WATCHER = '1'      # no auto-start from the load below
foreach ($n in 'FAKE_RECORD', 'FAKE_SCENARIO', 'FAKE_LAND', 'FAKE_STDERR', 'FAKE_SLEEP', 'FAKE_AGENTS') { Remove-Item "env:$n" -EA SilentlyContinue }

function Get-Slug([string]$Path) { $Path.TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-' }

function New-FakeChat {
    # one Claude transcript: a prompt and a reply per entry in $Prompts, the
    # title record, and optionally the synthetic limit record at the end
    param([string]$Proj, [string]$Id, [string]$Title, [double]$HoursAgo, [string[]]$Prompts,
        [string]$Mode = 'auto', [switch]$CutOff, [int64]$ResetsAt, [int]$PadBytes = 0, [switch]$ModeFarBack,
        [switch]$Overloaded, [string]$LimitType = 'five_hour', [string]$HomeDir = $claudeHome)
    $dir = Join-Path (Join-Path $HomeDir 'projects') (Get-Slug $Proj)
    $null = New-Item -ItemType Directory -Path $dir -Force
    $path = Join-Path $dir "$Id.jsonl"
    $t = (Get-Date).ToUniversalTime().AddHours(-$HoursAgo)
    $sbuf = [System.Text.StringBuilder]::new()
    $k = 0
    foreach ($p in $Prompts) {
        $k++
        $ts = $t.AddMinutes(-10 + $k).ToString('o')
        $u = [ordered]@{ parentUuid = $null; isSidechain = $false; type = 'user'; message = [ordered]@{ role = 'user'; content = $p }
            uuid = [guid]::NewGuid().ToString(); timestamp = $ts; permissionMode = $Mode; cwd = $Proj; sessionId = $Id }
        [void]$sbuf.AppendLine(($u | ConvertTo-Json -Compress -Depth 6))
        $a = [ordered]@{ parentUuid = $null; isSidechain = $false; message = [ordered]@{ model = 'claude-opus-5'; id = 'msg_1'; type = 'message'; role = 'assistant'
                content = @([ordered]@{ type = 'text'; text = "reply $k" }); stop_reason = 'end_turn' }
            type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = $ts; cwd = $Proj; sessionId = $Id }
        [void]$sbuf.AppendLine(($a | ConvertTo-Json -Compress -Depth 8))
    }
    if ($PadBytes) {
        # a long tool result after the last mode record: pushes it far back
        $pad = [ordered]@{ type = 'user'; message = [ordered]@{ role = 'user'; content = @([ordered]@{ type = 'tool_result'; content = ('y' * $PadBytes) }) }
            uuid = [guid]::NewGuid().ToString(); timestamp = $t.ToString('o'); sessionId = $Id }
        [void]$sbuf.AppendLine(($pad | ConvertTo-Json -Compress -Depth 8))
    }
    [void]$sbuf.AppendLine(([ordered]@{ type = 'ai-title'; aiTitle = $Title; sessionId = $Id } | ConvertTo-Json -Compress))
    if ($CutOff) {
        $s = [ordered]@{ parentUuid = $null; isSidechain = $false; type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = $t.ToString('o')
            message = [ordered]@{ model = '<synthetic>'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = "You've hit your session limit" }) }
            quotaLimits = [ordered]@{ status = 'rejected'; resetsAt = $ResetsAt; rateLimitType = $LimitType }
            error = 'rate_limit'; isApiErrorMessage = $true; cwd = $Proj; sessionId = $Id }
        [void]$sbuf.AppendLine(($s | ConvertTo-Json -Compress -Depth 8))
    }
    if ($Overloaded) {
        # the 529 turn exactly as Claude Code writes it
        $s = [ordered]@{ parentUuid = $null; isSidechain = $false; type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = $t.ToString('o')
            message = [ordered]@{ model = '<synthetic>'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = 'API Error: 529 Overloaded. This is a server-side issue, usually temporary - try again in a moment. If it persists, check https://status.claude.com.' }) }
            error = 'server_error'; isApiErrorMessage = $true; apiErrorStatus = 529; cwd = $Proj; sessionId = $Id }
        [void]$sbuf.AppendLine(($s | ConvertTo-Json -Compress -Depth 8))
    }
    [System.IO.File]::WriteAllText($path, $sbuf.ToString(), $utf8)
    (Get-Item -LiteralPath $path).LastWriteTime = $t.ToLocalTime()
    return $path
}

$now = [DateTimeOffset]::UtcNow
$future = $now.AddHours(2).ToUnixTimeSeconds()
$past = $now.AddHours(-3).ToUnixTimeSeconds()
$idFw = '11111111-1111-4111-8111-111111111111'
$idCard = '22222222-2222-4222-8222-222222222222'
$idTong = '33333333-3333-4333-8333-333333333333'
$idOld = '44444444-4444-4444-8444-444444444444'
$idMob = '55555555-5555-4555-8555-555555555555'
$idA = '66666666-6666-4666-8666-666666666666'
$idB = '77777777-7777-4777-8777-777777777777'
$idLong = '88888888-8888-4888-8888-888888888888'
$idFar = '99999999-9999-4999-8999-999999999999'
$tSel = U '\uC120\uD0DD'                 # "selection"
$tTong = U '\uD1B5\uD569'                # "integration"
$titleCard = "$tSel card UI redesign"
$titleTong = "card UI $tTong"
$longTitle = 'Investigate why the log viewer drops lines when the input pipe is saturated by a chatty build'

$pFw = New-FakeChat $projA $idFw 'Parser rewrite and plugin unification' 1 @('unify the parser entry points', 'now the plugins') -CutOff -ResetsAt $future
$pCard = New-FakeChat $projA $idCard $titleCard 2 @('redesign the selection card layout', 'level the card heights') -Mode 'acceptEdits'
$null = New-FakeChat $projA $idTong $titleTong 3 @("$tTong $tTong card merge", "$tTong UI merge the two cards") -CutOff -ResetsAt $past
$null = New-FakeChat $projA $idOld 'Old chat about gitignore rules' 72 @('write gitignore rules')
$null = New-FakeChat $projM $idMob 'Mobile only chat' 1.5 @('mobile layout')
$null = New-FakeChat $projA $idLong $longTitle 30 @('lines drop')
$pFar = New-FakeChat $projA $idFar 'Mode far back' 40 @('long one') -Mode 'plan' -PadBytes 1300000
$idOver = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
$pOver = New-FakeChat $projA $idOver 'Overloaded mid task' 0.5 @('refactor the parser') -Overloaded

# a second account whose only limit is one model's weekly one
$claude2 = Join-Path $sb 'claude2'
$null = New-FakeChat $projA 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' 'Opus only' 1 @('x') -CutOff -ResetsAt $now.AddDays(4).ToUnixTimeSeconds() -LimitType 'seven_day_opus' -HomeDir $claude2
$statusFile = Join-Path $sb 'status.json'
function Set-FakeStatus([string]$State) {
    $j = @{ components = @(@{ name = 'claude.ai'; status = 'operational' }, @{ name = 'Claude Code'; status = $State }) } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($statusFile, $j, $utf8)
}

# two chats for the 5 h edge, in a folder of their own
$projE = Join-Path $work 'projE'
$null = New-Item -ItemType Directory -Path $projE -Force
$null = New-FakeChat $projE $idA 'Edge alpha tool' 1 @('alpha')
$null = New-FakeChat $projE $idB 'Edge beta tool' (1 + 4.98) @('beta')

# codex: one rollout with its thread name, sandbox and a full rate window
$cxId = '01900000-0000-7000-8000-000000000001'
$cxDir = Join-Path $codexHome 'sessions\2026\09\20'
$null = New-Item -ItemType Directory -Path $cxDir -Force
$cxPath = Join-Path $cxDir "rollout-2026-09-20T10-00-00-$cxId.jsonl"
$cxLines = @(
    ([ordered]@{ timestamp = $now.AddHours(-1).ToString('o'); type = 'session_meta'; payload = [ordered]@{ session_id = $cxId; id = $cxId; cwd = $projA; originator = 'codex_vscode' } } | ConvertTo-Json -Compress -Depth 6)
    ([ordered]@{ timestamp = $now.AddHours(-1).ToString('o'); type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = 'add the codex gitignore' }) } } | ConvertTo-Json -Compress -Depth 6)
    ([ordered]@{ timestamp = $now.AddHours(-1).ToString('o'); type = 'turn_context'; payload = [ordered]@{ cwd = $projA; approval_policy = 'on-request'; sandbox_policy = [ordered]@{ type = 'workspace-write'; network_access = $true }; model = 'gpt-5.6' } } | ConvertTo-Json -Compress -Depth 6)
    ([ordered]@{ timestamp = $now.AddHours(-1).ToString('o'); type = 'event_msg'; payload = [ordered]@{ type = 'token_count'; rate_limits = [ordered]@{ limit_id = 'codex'; primary = [ordered]@{ used_percent = 100.0; window_minutes = 300; resets_at = $future }; secondary = [ordered]@{ used_percent = 12.0; window_minutes = 10080; resets_at = $now.AddDays(3).ToUnixTimeSeconds() } } } } | ConvertTo-Json -Compress -Depth 6)
)
[System.IO.File]::WriteAllText($cxPath, ($cxLines -join "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $codexHome 'session_index.jsonl'),
    (([ordered]@{ id = $cxId; thread_name = 'Codex gitignore thread'; updated_at = $now.ToString('o') } | ConvertTo-Json -Compress) + "`n"), $utf8)

# --- load --------------------------------------------------------------------
. (Join-Path $sb 'tool\VS-code-chat-manager.ps1')
Set-Location -LiteralPath $projA

Section 'bigrams and cosine'
$a = Get-ChatqBigrams 'card UI redesign'
Check 'identical text scores 1' ([Math]::Abs((Get-ChatqCosine $a (Get-ChatqBigrams 'card UI redesign')) - 1) -lt 1e-9)
Check 'disjoint text scores 0' ((Get-ChatqCosine $a (Get-ChatqBigrams 'zzz qqq')) -eq 0)
$h = Get-ChatqCosine (Get-ChatqBigrams "$tSel $tTong") (Get-ChatqBigrams "$tTong card")
Check 'shared Hangul word scores above 0' ($h -gt 0) $h
Check 'Hangul syllables count as letters' ((Get-ChatqBigrams $tSel).Count -eq 3) (Get-ChatqBigrams $tSel).Count
Check 'empty input scores 0, no throw' ((Get-ChatqCosine (Get-ChatqBigrams '') $a) -eq 0)

Section 'resolver'
$r = Resolve-ChatqTarget 'Parser rewrite and plugin unification'
Check 'exact title' ($r.Row.Id -eq $idFw -and $r.Rule -eq 'exact') "$($r.Rule) $($r.Row.Id)"
$r = Resolve-ChatqTarget 'plugin'
Check 'contains' ($r.Row.Id -eq $idFw -and $r.Tier -eq 'contains') "$($r.Rule)"
$r = Resolve-ChatqTarget 'card redesign'
Check 'every word, any order' ($r.Row.Id -eq $idCard -and $r.Tier -eq 'words') "$($r.Rule) $($r.Row.Title)"
$r = Resolve-ChatqTarget $titleCard
Check 'exact Hangul title' ($r.Row.Id -eq $idCard -and $r.Rule -eq 'exact') "$($r.Rule)"
$r = Resolve-ChatqTarget ($titleCard.Normalize([System.Text.NormalizationForm]::FormD))
Check 'NFD-typed Hangul still exact' ($r.Row.Id -eq $idCard -and $r.Rule -eq 'exact') "$($r.Rule)"
$r = Resolve-ChatqTarget 'card UI'
Check 'two within 5h -> relevance' ($r.Rule -eq 'contains/relevance' -and $r.Cluster -eq 2) "$($r.Rule) cluster=$($r.Cluster)"
$r = Resolve-ChatqTarget 'card UI' "$tTong $tTong UI merge"
Check 'the prompt decides between look-alikes' ($r.Row.Id -eq $idTong) "$($r.Row.Title) $($r.Score) vs $($r.RunnerUpScore)"
Check 'runner-up is reported' ($null -ne $r.RunnerUp -and $r.RunnerUp.Id -eq $idCard) "$($r.RunnerUp.Title)"
$r = Resolve-ChatqTarget 'zzqx nothing like it'
Check 'no match: a guess from this project only' ($r.Tier -eq 'nomatch' -and (Test-ChatqInProject $r.Row (Get-ChatqProjectScope $projA))) "$($r.Rule) $($r.Row.Group)"
Check 'no match never reaches the nested sibling slug' ($r.Row.Id -ne $idMob)
$r = Resolve-ChatqTarget 'Mobile only chat'
Check 'a title only in another project is found there' ($r.Row.Id -eq $idMob -and $r.Wide) "$($r.Rule) wide=$($r.Wide)"
$r = Resolve-ChatqTarget '2222222'
Check 'hex prefix is an id' ($r.Row.Id -eq $idCard -and $r.Rule -eq 'id') "$($r.Rule)"
$r = Resolve-ChatqTarget $longTitle
Check 'a title past the 60-char clip still exact' ($r.Row.Id -eq $idLong -and $r.Rule -eq 'exact') "$($r.Rule)"
Set-Location -LiteralPath $projE
$r = Resolve-ChatqTarget 'tool'
Check '4h59 apart: relevance decides' ($r.Rule -eq 'contains/relevance') "$($r.Rule)"
$null = New-FakeChat $projE $idB 'Edge beta tool' (1 + 5.05) @('beta')
$r = Resolve-ChatqTarget 'tool'
Check '5h03 apart: newest wins' ($r.Rule -eq 'contains/newest' -and $r.Row.Id -eq $idA) "$($r.Rule)"
Set-Location -LiteralPath $projA
$r = Resolve-ChatqTarget 'Codex gitignore thread'
Check 'codex thread name resolves' ($r.Row.Provider -eq 'codex' -and $r.Row.Id -eq $cxId) "$($r.Row.Provider) $($r.Row.Id)"

Section 'metadata'
$m = Get-ChatqClaudeMeta $pCard (Get-Slug $projA)
Check 'cwd is the project folder' ($m.Cwd -eq $projA) $m.Cwd
Check 'last permission mode' ($m.Mode -eq 'acceptEdits') $m.Mode
Check 'last real model' ($m.Model -eq 'claude-opus-5') $m.Model
$m = Get-ChatqClaudeMeta $pFar (Get-Slug $projA)
Check 'mode 1.3 MB from the end is still found' ($m.Mode -eq 'plan') $m.Mode
$m = Get-ChatqClaudeMeta $pFw (Get-Slug $projA)
Check 'cut off by the limit' ($m.LastTurn.Limit) $m.LastTurn
Check 'reset time read from the record' ($m.LastTurn.ResetsAt -and [Math]::Abs(($m.LastTurn.ResetsAt - [DateTimeOffset]::FromUnixTimeSeconds($future).LocalDateTime).TotalSeconds) -lt 2)
Check 'a finished chat is not cut off' (-not (Get-ChatqClaudeMeta $pCard (Get-Slug $projA)).LastTurn.Limit)
$c = Get-ChatqCodexMeta $cxPath
Check 'codex cwd and sandbox' ($c.Cwd -eq $projA -and $c.Sandbox -eq 'workspace-write' -and $c.Network) "$($c.Cwd) $($c.Sandbox) $($c.Network)"

Section 'limits'
$b = Get-ChatqClaudeBlock $claudeHome
Check 'future reset found, past one ignored' ($b -and [Math]::Abs(($b.Until - [DateTimeOffset]::FromUnixTimeSeconds($future).LocalDateTime).TotalSeconds) -lt 2) $b
Check 'the record''s own time comes with it' ($b -and $b.At -and $b.At -lt (Get-Date)) $b.At
$x = Get-ChatqCodexBlock $codexHome
Check 'codex full window found' ($x -and $x.Type -eq 'five_hour') $x
$d = ConvertFrom-ChatqLimitText 'try again at Sep 21st, 2026 8:37 AM.'
Check 'codex prose reset time parsed' ($d -eq [datetime]'2026-09-21 08:37') $d
$cut = @(Get-ChatqCutOffChats @())
Check 'cut-off chats listed' (@($cut | Where-Object { $_.Id -eq $idFw }).Count -eq 1) ($cut | ForEach-Object Title)

Section 'classifier'
function Invoke-Scenario([string]$Name, [string]$Mode = 'auto') {
    $st = New-ChatqRunState
    $file = Join-Path $here "fixtures\stream\$Name.jsonl"
    foreach ($l in [System.IO.File]::ReadAllLines($file, $utf8)) {
        if ($l.Trim()) { Update-ChatqClaudeState $st ($l.Replace('{{RESETS}}', "$future").Replace('{{SESSION}}', $idCard)) }
    }
    Get-ChatqClaudeOutcome $st ([pscustomobject]@{ ExitCode = 0; StdErr = ''; Stopped = $null }) $Mode
}
$o = Invoke-Scenario 'denied'
Check 'denial -> needs-input' ($o.kind -eq 'needs-input' -and $o.reason -like '*Write(note.txt)*') "$($o.kind) $($o.reason)"
$o = Invoke-Scenario 'rejected'
Check 'rejected event -> limited, reset time kept' ($o.kind -eq 'limited' -and $o.resetsAt) "$($o.kind) $($o.resetsAt)"
$o = Invoke-Scenario 'legacy'
Check 'legacy "|epoch" -> limited with time' ($o.kind -eq 'limited' -and $o.resetsAt) "$($o.kind) $($o.resetsAt)"
$o = Invoke-Scenario 'weekly-synthetic'
Check 'weekly limit text -> limited' ($o.kind -eq 'limited') "$($o.kind)"
$o = Invoke-Scenario 'plan' 'plan'
Check 'plan mode -> needs-input' ($o.kind -eq 'needs-input') "$($o.kind)"
$o = Invoke-Scenario 'maxturns'
Check 'turn limit -> needs-input' ($o.kind -eq 'needs-input') "$($o.kind)"
$o = Invoke-Scenario 'error'
Check 'error subtype -> failed' ($o.kind -eq 'failed') "$($o.kind)"
$o = Invoke-Scenario 'noresult'
Check 'no result line -> failed' ($o.kind -eq 'failed' -and $o.reason -like 'no result*') "$($o.kind) $($o.reason)"
$o = Invoke-Scenario 'asks'
Check 'ends on a question -> done, asks' ($o.kind -eq 'done' -and $o.asks) "$($o.kind) $($o.asks)"
Check 'excerpt drops code fences' ($o.excerpt -notlike '*some code*' -and $o.excerpt -like '*update the tests?*') $o.excerpt
$st = New-ChatqRunState
foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $here 'fixtures\stream\codex-limit.jsonl'), $utf8)) { if ($l.Trim()) { Update-ChatqCodexState $st $l } }
$o = Get-ChatqCodexOutcome $st ([pscustomobject]@{ ExitCode = 1; StdErr = ''; Stopped = $null })
Check 'codex usage limit -> limited with time' ($o.kind -eq 'limited' -and $o.resetsAt) "$($o.kind) $($o.resetsAt)"
$st = New-ChatqRunState
foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $here 'fixtures\stream\codex-done.jsonl'), $utf8)) { if ($l.Trim()) { Update-ChatqCodexState $st $l } }
$o = Get-ChatqCodexOutcome $st ([pscustomobject]@{ ExitCode = 0; StdErr = ''; Stopped = $null })
Check 'codex turn.completed -> done' ($o.kind -eq 'done' -and $o.excerpt -like '*build passes*') "$($o.kind) $($o.excerpt)"
$st = New-ChatqRunState
foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $here 'fixtures\stream\codex-retry-done.jsonl'), $utf8)) { if ($l.Trim()) { Update-ChatqCodexState $st $l } }
$o = Get-ChatqCodexOutcome $st ([pscustomobject]@{ ExitCode = 0; StdErr = ''; Stopped = $null })
Check 'codex reconnect notice then turn.completed -> done' ($o.kind -eq 'done') "$($o.kind) $($o.reason)"
$o = Invoke-Scenario 'overloaded'
Check '529 Overloaded -> overloaded, not failed' ($o.kind -eq 'overloaded' -and $o.reason -like 'API Error: 529*') "$($o.kind) $($o.reason)"
$o = Invoke-Scenario 'overage-success'
Check 'a rejected event before a successful turn -> done' ($o.kind -eq 'done') "$($o.kind)"

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

Section 'review regressions'
Check 'pwsh-7-style [datetime] input is not shifted' ((ConvertTo-ChatqDate ([datetime]::SpecifyKind([datetime]'2026-09-22 03:00', 'Utc'))) -eq ([datetime]::SpecifyKind([datetime]'2026-09-22 03:00', 'Utc')).ToLocalTime())
Check 'one model''s weekly limit blocks nothing' ($null -eq (Get-ChatqClaudeBlock $claude2))
$Wb = New-ChatqWatchState
$jb = [pscustomobject]@{ provider = 'claude'; home = $claudeHome; model = $null }
$Wb.lastAllowed[(Get-ChatqLane $jb)] = Get-Date
Update-ChatqBlock $Wb $jb -Force
Check 'a limit record older than an allowed probe is ignored' ($null -eq $Wb.blocked[(Get-ChatqLane $jb)])
$e1 = [pscustomobject]@{ id = 'a'; seq = 1; state = 'queued'; provider = 'claude'; home = $null; notBefore = (Get-Date).AddHours(3).ToUniversalTime().ToString('o'); deferUntil = $null }
$e2 = [pscustomobject]@{ id = 'b'; seq = 2; state = 'queued'; provider = 'claude'; home = $null; notBefore = $null; deferUntil = $null }
$eta = Get-ChatqEta @($e1, $e2) @{}
Check 'a free job is not shown "after" a waiting one' ($eta['b'] -eq 'next' -and $eta['a'] -notlike 'after*') "a=$($eta['a']) b=$($eta['b'])"
Set-Location -LiteralPath $sb
$r = Resolve-ChatqTarget 'zzqx nothing like it'
Check 'no project here and no match: refuse to guess' ($r.Error -like '*not a project*') $r.Error
Set-Location -LiteralPath $projA
$hdr = "<!-- chatq: prompt for '$('A ---> B' -replace '-{2,}', '-')' (claude). tail -->`n`nreal prompt"
Check 'a title full of dashes cannot close the header early' ((Remove-ChatqPromptHeader $hdr) -eq 'real prompt') (Remove-ChatqPromptHeader $hdr)
$smart = "Don$([char]0x2019)t break"
$esc = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($smart)
Check 'completion quotes a typographic apostrophe' ($null -ne [scriptblock]::Create("'$esc'"))
# a profile with StrictMode on: dot-source there, then only what a user types
$exe = (Get-Process -Id $PID).Path
$probe = "Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; try { . '$(Join-Path $sb 'tool\VS-code-chat-manager.ps1')'; Set-Location -LiteralPath '$projA'; chatq plugin -WhatIf *> `$null; chatqlist *> `$null; chatqlog 1 *> `$null; `$r = & `$script:ChatqTitleCompleter 'chatq' 'Target' 'Pars'; 'ok' } catch { 'threw: ' + `$_.Exception.Message }"
$strict = (& $exe -NoProfile -NonInteractive -Command $probe | Select-Object -Last 1)
Check 'works from a StrictMode Latest session' ($strict -eq 'ok') $strict

Section 'process runner'
$rec = Join-Path $sb 'rec'
$env:FAKE_RECORD = $rec
$env:ANTHROPIC_API_KEY = 'sk-must-not-leak'
$env:CLAUDECODE = '1'
$prompt = (U '\uC900\uBE44 \uC644\uB8CC') + " `"quoted`" back\slash %PATH% tab`t end`nsecond line"
$lines = [System.Collections.Generic.List[string]]::new()
$p = Invoke-ChatqProcess -Exe $env:CHATQ_CLAUDE -ArgList @('-p', '--resume', $idCard) -StdIn $prompt -OnLine { param($l) $lines.Add($l) } -TimeoutSec 60
$got = [System.IO.File]::ReadAllBytes((Join-Path $rec 'stdin.bin'))
$want = $utf8.GetBytes($prompt)
Check 'stdin arrives byte-exact (Hangul, quotes, %, newlines)' ([Convert]::ToBase64String($got) -eq [Convert]::ToBase64String($want)) "$($got.Length) vs $($want.Length) bytes"
Check 'no BOM on stdin' (-not ($got.Length -ge 3 -and $got[0] -eq 0xEF -and $got[1] -eq 0xBB))
$envSeen = [System.IO.File]::ReadAllText((Join-Path $rec 'env.txt'), $utf8)
Check 'ANTHROPIC_API_KEY kept out of the child' ($envSeen -match '(?m)^ANTHROPIC_API_KEY=$') $envSeen
Check 'CLAUDECODE kept out of the child' ($envSeen -match '(?m)^CLAUDECODE=$')
Check 'stdout read line by line' ($lines.Count -eq 3 -and $p.ExitCode -eq 0) "$($lines.Count) lines exit $($p.ExitCode)"
Remove-Item env:ANTHROPIC_API_KEY, env:CLAUDECODE

$env:FAKE_STDERR = '400000'
$p = Invoke-ChatqProcess -Exe $env:CHATQ_CLAUDE -ArgList @('-p') -StdIn 'x' -TimeoutSec 60
Check '400 KB of stderr does not deadlock' ($p.ExitCode -eq 0 -and $p.StdErr.Length -ge 390000) "exit $($p.ExitCode) err $($p.StdErr.Length)"
Remove-Item env:FAKE_STDERR

$env:FAKE_SLEEP = '30'
$t0 = Get-Date
$p = Invoke-ChatqProcess -Exe $env:CHATQ_CLAUDE -ArgList @('-p') -StdIn 'x' -TimeoutSec 2
$fakePid = [int]([System.IO.File]::ReadAllText((Join-Path $rec 'pid.txt')))
Start-Sleep -Milliseconds 500
Check 'timeout stops the run' ($p.Stopped -eq 'timeout' -and ((Get-Date) - $t0).TotalSeconds -lt 20) "$($p.Stopped)"
Check 'and takes the whole process tree with it' (-not (Get-Process -Id $fakePid -EA SilentlyContinue)) $fakePid
Remove-Item env:FAKE_SLEEP

# the quoting rules, checked against what the CLR itself hands Main()
$echo = Join-Path $sb 'echoargs.exe'
Add-Type -OutputAssembly $echo -OutputType ConsoleApplication -TypeDefinition @'
public static class EchoArgs {
    public static void Main(string[] a) {
        foreach (var s in a) System.Console.WriteLine(System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(s)));
    }
}
'@
$argsIn = @('plain', '', 'with space', 'quote"inside', 'trail\', 'C:\path with\', 'a\\"b', '--tools', '', $titleCard)
$out = [System.Collections.Generic.List[string]]::new()
$null = Invoke-ChatqProcess -Exe $echo -ArgList $argsIn -StdIn '' -OnLine { param($l) $out.Add($utf8.GetString([Convert]::FromBase64String($l))) } -TimeoutSec 30
Check 'argument quoting round-trips' (($out -join '|') -eq ($argsIn -join '|')) ($out -join '|')
Remove-Item env:FAKE_RECORD

Section 'jobs and the watcher'
function New-TestJob([string]$Target, [string]$PromptText, [switch]$Continue) {
    # the real chatq command, with the watcher kept from starting: holding the
    # lock is exactly what a running watcher looks like
    New-ChatqDir $script:ChatqData
    $lk = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        if ($Continue) { chatq $Target -Continue *> $null } else { chatq $Target -Prompt $PromptText *> $null }
    }
    finally { $lk.Dispose() }
    return @(Get-ChatqJobs | Sort-Object { [int]$_.seq })[-1]
}
$j = New-TestJob 'card redesign' (U 'level the heights \uC120\uD0DD')
Check 'chatq queues with the chat''s cwd and mode' ($j.sessionId -eq $idCard -and $j.cwd -eq $projA -and $j.modeAtQueue -eq 'acceptEdits') "$($j.sessionId) $($j.cwd) $($j.modeAtQueue)"
Check 'prompt kept in its own .md' ((Read-ChatqPrompt $j) -eq (U 'level the heights \uC120\uD0DD')) (Read-ChatqPrompt $j)
Check 'the prompt file is named after the chat' ($j.promptFile -like "#$($j.seq) $tSel card UI redesign.md") $j.promptFile

$W = New-ChatqWatchState
$env:FAKE_RECORD = $rec
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'a plain run ends done' ($j.state -eq 'done') "$($j.state) $($j.result.reason)"
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
Check 'resumed with the chat''s own mode, prompts denied' ($argv -match '--resume\s+' + $idCard -and $argv -match 'acceptEdits' -and $argv -match 'none') ($argv -replace "`n", ' ')
$alerts = [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'alerts.log'), $utf8)
Check 'started and done alerts logged' ($alerts -match "`tstarted`t" -and $alerts -match "`tdone`t")

# a limit mid-run, after the prompt reached the chat: back in the queue, as a
# "continue", and the provider blocked until the reset the run reported
$j = New-TestJob 'Parser rewrite and plugin unification' 'second half please'
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\rejected.jsonl'
$env:FAKE_LAND = $pFw
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'limited mid-run -> queued again' ($j.state -eq 'queued') $j.state
Check 'landed prompt retries as continue' ($j.retryAs -eq 'continue') $j.retryAs
$laneA = Get-ChatqLane $j
Check 'provider blocked until the reset' ($W.blocked[$laneA] -and $W.blocked[$laneA].Until -gt (Get-Date).AddMinutes(90)) $W.blocked[$laneA]
Remove-Item env:FAKE_SCENARIO, env:FAKE_LAND

# denied -> needs-input, parked
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\denied.jsonl'
$j = New-TestJob 'Old chat about gitignore rules' 'write them'
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'denied -> needs-input' ($j.state -eq 'needs-input') "$($j.state) $($j.result.reason)"
Remove-Item env:FAKE_SCENARIO

# -Continue on a chat that has moved on is dropped, not sent
$j = New-TestJob $titleCard -Continue
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check '-Continue on a chat already continued -> skipped' ($j.state -eq 'skipped') "$($j.state)"

# busy in a live window -> deferred, not run
$env:FAKE_AGENTS = '[{"pid":1,"sessionId":"' + $idOld + '","kind":"interactive","status":"busy"}]'
$j = New-TestJob 'Old chat about gitignore rules' 'again'
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'a busy chat is deferred' ($j.state -eq 'queued' -and $j.deferUntil) "$($j.state) $($j.deferUntil)"
$env:FAKE_AGENTS = '[{"pid":1,"sessionId":"' + $idOld + '","kind":"interactive","status":"idle"}]'
Set-ChatqProp $j 'deferUntil' $null; Save-ChatqJob $j
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'an idle live chat runs, with a reload warning' ($j.state -eq 'done' -and $j.result.stale) "$($j.state) stale=$($j.result.stale)"
Remove-Item env:FAKE_AGENTS

# a 529 mid-run, after the prompt reached the chat: queued again as an
# automatic "continue", its lane waiting on status.claude.com
$j = New-TestJob 'Overloaded mid task' 'finish the parser refactor'
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\overloaded.jsonl'
$env:FAKE_LAND = $pOver
Set-FakeStatus 'major_outage'
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check '529 mid-run -> queued again, not failed' ($j.state -eq 'queued') "$($j.state) $($j.result.reason)"
Check 'landed prompt retries as an automatic continue' ($j.retryAs -eq 'continue' -and $j.autoContinue) "$($j.retryAs) $($j.autoContinue)"
Check 'its lane waits on the status page' ($null -ne $W.outage[(Get-ChatqLane $j)])
Check 'the watcher will not pick it before the next check' ($null -ne (Get-ChatqDueTime $W $j (Get-Date)))
Remove-Item env:FAKE_SCENARIO, env:FAKE_LAND
# Claude writes the 529 turn into the chat as well. While it is the chat's
# last word the continue goes out; once the chat has moved on it is dropped.
$rec529 = [ordered]@{ type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = (Get-Date).ToUniversalTime().ToString('o')
    message = [ordered]@{ model = '<synthetic>'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = 'API Error: 529 Overloaded.' }) }
    error = 'server_error'; isApiErrorMessage = $true; apiErrorStatus = 529; sessionId = $idOver } | ConvertTo-Json -Compress -Depth 6
[System.IO.File]::AppendAllText($pOver, $rec529 + "`n", $utf8)
Set-FakeStatus 'operational'
$W.outage = @{}
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'chat still stopped by the 529 -> the continue is sent' ($j.state -eq 'done') "$($j.state) $($j.result.reason)"
$moved = [ordered]@{ type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = (Get-Date).ToUniversalTime().ToString('o')
    message = [ordered]@{ model = 'claude-opus-5'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = 'all done' }); stop_reason = 'end_turn' }
    sessionId = $idOver } | ConvertTo-Json -Compress -Depth 6
[System.IO.File]::AppendAllText($pOver, $moved + "`n", $utf8)
Set-ChatqProp $j 'retryAs' 'continue'; Set-ChatqProp $j 'autoContinue' $true; Set-ChatqJobState $j 'queued' 'test'
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'an automatic continue into a chat that moved on is dropped' ($j.state -eq 'skipped') "$($j.state)"

# a job left running by a dead watcher - even when its old pid is alive
# again as some other process
$j = New-TestJob 'Mode far back' 'x'
$other = (Get-Process | Where-Object { $_.Id -ne $PID -and $_.Id -gt 4 } | Select-Object -First 1).Id
Set-ChatqProp $j 'runnerPid' $other; Set-ChatqProp $j 'startedAt' (Get-ChatqStamp); Set-ChatqJobState $j 'running' 'test'
Repair-ChatqInterrupted
$j = Find-ChatqJob $j.id
Check 'interrupted run -> failed, never resent on its own' ($j.state -eq 'failed' -and $j.result.reason -like 'interrupted*') "$($j.state)"
Set-ChatqJobState $j 'running' 'test'
chatqrm $j.seq -Force *> $null
$j = Find-ChatqJob $j.id
Check 'chatqrm -Force with no watcher fails it at once, leaves no cancel file' ($j.state -eq 'failed' -and -not (Test-Path -LiteralPath (Join-Path $script:ChatqQueueDir "$($j.id).cancel"))) $j.state
$lk = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$null = Start-ChatqWatcher -Wake 'now'
$lk.Dispose()
Check '-Now reaches a running watcher intact' ((Get-Content -LiteralPath $script:ChatqWakePath -Raw).Trim() -eq 'now')

# the whole loop, once. The sandbox holds a chat cut off with a reset two
# hours out, so a plain start would wait for it - chatqrun -Now is the way
# past, and after it the watcher runs the queue (the limited job above too)
# and exits
$j = New-TestJob 'plugin' 'loop test'
Send-ChatqWake 'now'
Invoke-ChatqWatchLoop -Foreground *> $null
$j = Find-ChatqJob $j.id
Check 'watcher loop runs the queue and exits' ($j.state -eq 'done' -and -not (Test-ChatqWatcherAlive)) "$($j.state)"
$lk = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$t0 = Get-Date
Invoke-ChatqWatchLoop -Foreground *> $null
Check 'a second watcher will not start' (((Get-Date) - $t0).TotalSeconds -lt 5)
$lk.Dispose()
Remove-Item env:FAKE_RECORD

Section 'status and alerts'
Write-ChatqBoard
$board = [System.IO.File]::ReadAllText($script:ChatqBoardPath, $utf8)
Check 'board folds each prompt away' ($board -match '<details><summary>' -and $board -match 'second half please')
Check 'Hangul counts two cells' ((Get-ChatqCells $tSel) -eq 4)
Check 'cells clip on a wide character' ((Get-ChatqCells (Format-ChatqCell "$tSel$tSel$tSel" 5)) -eq 5)
$url = Get-ChatqJoinUrl 'k' 'group.phone' 'chatq x' ($tSel * 400) 1
Check 'Join URL fits and targets the group' ($url.Length -le 1900 -and $url -match 'deviceId=group\.phone') $url.Length
$url = Get-ChatqJoinUrl 'k' 'Pixel 8' 't' 'hi' 0
Check 'a device name goes as deviceNames' ($url -match 'deviceNames=Pixel%208')
$e = Get-ChatqExcerpt ("a`n`n" + ('word ' * 200)) 300
Check 'excerpt stays within 300' ($e.Length -le 300) $e.Length

Set-Location -LiteralPath $here
Write-Host ''
$color = if ($script:Fail) { 'Red' } else { 'Green' }
Write-Host "  $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $color
if (-not $Keep) { Remove-Item -LiteralPath (Join-Path $here '.sandbox') -Recurse -Force -EA SilentlyContinue }
exit $script:Fail
