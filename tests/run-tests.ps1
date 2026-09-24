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
# Copilot's store too: an index sync without -Provider would otherwise read
# this machine's real Copilot chats into the sandbox
$codeUser = Join-Path $sb 'code-user'
$env:CHAT_CODE_USER = $codeUser
$env:CHATQ_CLAUDE = Join-Path $here 'fake-claude.cmd'
$env:CHATQ_CODEX = Join-Path $here 'fake-claude.cmd'
$env:CHATQ_WATCHER = '1'      # no auto-start from the load below
# gh's login is this machine's, whatever the sandbox: no run - child
# processes included - ever reaches it
$env:CHATQ_GH = Join-Path $here 'no-such-gh.exe'
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
# a second thread, named in Hangul: the index is BOM-less UTF-8, which 5.1
# reads in the ANSI code page unless told otherwise
$cx2Id = '01900000-0000-7000-8000-000000000002'
$tHan = -join [char[]](0xD55C, 0xAE00, 0x20, 0xC2A4, 0xB808, 0xB4DC)   # "Hangul thread"
$cx2Lines = @(
    ([ordered]@{ timestamp = $now.AddHours(-2).ToString('o'); type = 'session_meta'; payload = [ordered]@{ session_id = $cx2Id; id = $cx2Id; cwd = $projA; originator = 'codex_vscode' } } | ConvertTo-Json -Compress -Depth 6)
    ([ordered]@{ timestamp = $now.AddHours(-2).ToString('o'); type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = 'name me' }) } } | ConvertTo-Json -Compress -Depth 6)
)
[System.IO.File]::WriteAllText((Join-Path $cxDir "rollout-2026-09-20T09-00-00-$cx2Id.jsonl"), ($cx2Lines -join "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $codexHome 'session_index.jsonl'),
    ((([ordered]@{ id = $cxId; thread_name = 'Codex gitignore thread'; updated_at = $now.ToString('o') } | ConvertTo-Json -Compress),
            ([ordered]@{ id = $cx2Id; thread_name = $tHan; updated_at = $now.ToString('o') } | ConvertTo-Json -Compress)) -join "`n") + "`n", $utf8)

# Copilot: one chat in this project's folder, so a title can name it
$wsDir = Join-Path (Join-Path $codeUser 'workspaceStorage') 'ws1'
$null = New-Item -ItemType Directory -Path (Join-Path $wsDir 'chatSessions') -Force
[System.IO.File]::WriteAllText((Join-Path $wsDir 'workspace.json'), (@{ folder = ([Uri]$projA).AbsoluteUri } | ConvertTo-Json -Compress), $utf8)
$cpId = '15151515-1515-4151-8151-151515151515'
$cpJson = [ordered]@{ version = 3; requests = @([ordered]@{ message = [ordered]@{ text = 'explain the copilot tests' } })
    customTitle = 'Copilot chat about tests'; lastMessageDate = $now.AddHours(-1).ToUnixTimeMilliseconds() } | ConvertTo-Json -Compress -Depth 6
[System.IO.File]::WriteAllText((Join-Path (Join-Path $wsDir 'chatSessions') "$cpId.json"), $cpJson, $utf8)

# find-and-delete: chats that get deleted, one with every leftover a Claude
# chat keeps beside its transcript
$idDoom1 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
$idDoom2 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
$pDoom1 = New-FakeChat $projA $idDoom1 'Doomed chat one' 2 @('delete me later', 'unique prompt phrase zebra')
$pDoom2 = New-FakeChat $projA $idDoom2 'Doomed chat two' 2 @('delete me too')
$side = Join-Path (Split-Path $pDoom1 -Parent) $idDoom1
$null = New-Item -ItemType Directory -Path (Join-Path $side 'subagents') -Force
[System.IO.File]::WriteAllText((Join-Path $side 'subagents\agent-1.jsonl'), '{}', $utf8)
foreach ($d in 'file-history', 'session-env') {
    $dd = Join-Path (Join-Path $claudeHome $d) $idDoom1
    $null = New-Item -ItemType Directory -Path $dd -Force
    [System.IO.File]::WriteAllText((Join-Path $dd 'x'), 'x', $utf8)
}
# the rest of claude-chats-delete's inventory, each named or found by the id
$left = @{
    Debug = Join-Path $claudeHome "debug\$idDoom1.txt"
    Tasks = Join-Path $claudeHome "tasks\$idDoom1\t.json"
    Sec = Join-Path $claudeHome "security\security_warnings_state_$idDoom1.json"
    SecLock = Join-Path $claudeHome "security\security_warnings_state_$idDoom1.lock"
    Tele = Join-Path $claudeHome "telemetry\evt-$idDoom1-1.json"
    Todo = Join-Path $claudeHome "todos\$idDoom1-agent-1.json"
    Job = Join-Path $claudeHome 'jobs\cccccccc\state.json'
    Plan = Join-Path $claudeHome 'plans\doom-slug.md'
    PlanAgent = Join-Path $claudeHome 'plans\doom-slug-agent-a1.md'
    Shared = Join-Path $claudeHome 'plans\shared-slug.md'
}
foreach ($p in $left.Values) {
    $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
    [System.IO.File]::WriteAllText($p, 'x', $utf8)
}
[System.IO.File]::WriteAllText($left.Job, ('{"sessionId":"' + $idDoom1 + '"}'), $utf8)
function Add-Slug([string]$Path, [string]$Slug) {
    [System.IO.File]::AppendAllText($Path, ('{"type":"system","subtype":"x","slug":"' + $Slug + '","sessionId":"s"}' + "`n"), $utf8)
}
Add-Slug $pDoom1 'doom-slug'
Add-Slug $pDoom2 'shared-slug'
# more prompts than the index previews, one of them only -Deep can see - and
# it shares doomed chat two's plan slug, so that plan must stay
$idDeep = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
$pDeep = New-FakeChat $projA $idDeep 'Many prompts chat' 3 @('p1', 'p2', 'p3', 'p4', 'needle-deep-xyz', 'p6', 'p7', 'p8')
Add-Slug $pDeep 'shared-slug'
# one to hold open while deleting, one to archive and bring back
$idLock = '16161616-1616-4161-8161-161616161616'
$pLock = New-FakeChat $projA $idLock 'Locked open chat' 8 @('hold me')
$lockHist = Join-Path $claudeHome "file-history\$idLock"
$null = New-Item -ItemType Directory -Path $lockHist -Force
[System.IO.File]::WriteAllText((Join-Path $lockHist 'x'), 'x', $utf8)
$idArch = '17171717-1717-4171-8171-171717171717'
$pArch = New-FakeChat $projA $idArch 'Archive me please' 9 @('archive this one')
$archHist = Join-Path $claudeHome "file-history\$idArch"
$null = New-Item -ItemType Directory -Path $archHist -Force
[System.IO.File]::WriteAllText((Join-Path $archHist 'x'), 'x', $utf8)
$idQuote = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
$null = New-FakeChat $projA $idQuote 'Say "hi" to it' 4 @('greet')
$idDead = '12121212-1212-4121-8121-121212121212'
$null = New-FakeChat $projA $idDead 'Deadline notes' 5 @('dates')
$idSmart = '13131313-1313-4131-8131-131313131313'
$tSmart = "Don$([char]0x2019)t break it"
$null = New-FakeChat $projA $idSmart $tSmart 6 @('careful')
# a subagent transcript: flagged on its first line, hidden from search and Tab
$idHid = '14141414-1414-4141-8141-141414141414'
$hidLines = @(
    ([ordered]@{ type = 'user'; isSidechain = $true; message = [ordered]@{ role = 'user'; content = 'sub task' }; uuid = [guid]::NewGuid().ToString()
            timestamp = $now.AddHours(-1).ToString('o'); cwd = $projA; sessionId = $idHid } | ConvertTo-Json -Compress -Depth 5)
    ([ordered]@{ type = 'ai-title'; aiTitle = 'Hidden subagent work'; sessionId = $idHid } | ConvertTo-Json -Compress)
)
[System.IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $claudeHome 'projects') (Get-Slug $projA)) "$idHid.jsonl"), ($hidLines -join "`n") + "`n", $utf8)

# --- load --------------------------------------------------------------------
. (Join-Path $sb 'tool\VS-code-chat-manager.ps1')
Set-Location -LiteralPath $projA
# nothing real leaves the sandbox: no desktop toast, no idle clock (as if
# nobody were at the PC), no push service, no ghost-watch events
$script:Toasts = [System.Collections.Generic.List[string]]::new()
$script:ChatqToastSeam = { param($t, $x) $script:Toasts.Add("$t|$x") }
$script:ChatqIdleSeam = 99999
$script:Ntfys = [System.Collections.Generic.List[object]]::new()
$script:ChatqNtfySeam = { param($server, $body, $headers) $script:Ntfys.Add([pscustomobject]@{ Server = $server; Body = $body; Headers = $headers }) }
$script:ChatNoGhostWatch = $true
# and no real background watcher: one would outlive the sandbox it runs in
$script:ChatqSpawn = { $true }

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
Check 'no match: a guess from this project only' ($r.Tier -eq 'nomatch' -and (Test-ChatInProject $r.Row (Get-ChatProjectScope $projA))) "$($r.Rule) $($r.Row.Group)"
Check 'no match never reaches the nested sibling slug' ($r.Row.Id -ne $idMob)
# a prompt typed after the title joins the title, and only ever guesses a chat
$said = (Write-ChatqPromptHint 'zzqx nothing like it read the notes at C:\tmp\p.txt and improve' $r 6>&1 | Out-String)
Check 'a sentence typed as a title points at -Prompt' ($said -match "-Prompt '<the rest>'") $said
$said = (Write-ChatqPromptHint 'zzqx nothing like it and a few more words' $r -HasPrompt 6>&1 | Out-String)
Check 'no hint when the prompt was given' (-not $said.Trim()) $said
$said = (Write-ChatqPromptHint 'zzqx nothing' $r 6>&1 | Out-String)
Check 'no hint for a short target' (-not $said.Trim()) $said
$r2 = Resolve-ChatqTarget 'card redesign'
$said = (Write-ChatqPromptHint 'card redesign and a few more words here' $r2 6>&1 | Out-String)
Check 'no hint when a title really matched' (-not $said.Trim()) $said
# and through chatq itself, the way it was typed - -WhatIf queues nothing
$said = (chatq zzqx nothing like it read the notes at C:\tmp\p.txt and improve -WhatIf 6>&1 | Out-String)
Check 'chatq itself says it for a prompt typed where the title goes' ($said -like "*-Prompt '<the rest>'*") $said
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
# the chat the limit just stopped is the one most likely to be missing from the
# index, and a uuid is not what "chatq '<title>' -Continue" below asks for
Remove-ChatIndexRow $pFw
$row = @(Get-ChatqCutOffChats @() | Where-Object { $_.Id -eq $idFw })[0]
Check 'one missing from the index still shows its title' ($row -and $row.Title -eq 'Parser rewrite and plugin unification') "$($row.Title)"
$null = Sync-ChatIndex

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
$probe = "Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; try { . '$(Join-Path $sb 'tool\VS-code-chat-manager.ps1')'; Set-Location -LiteralPath '$projA'; chatq plugin -WhatIf *> `$null; chatqlist *> `$null; chatqlog 1 *> `$null; `$r = & `$script:ChatTitleCompleter 'chatq' 'Target' 'Pars' `$null @{}; 'ok' } catch { 'threw: ' + `$_.Exception.Message }"
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
$echoSrc = @'
public static class EchoArgs {
    public static void Main(string[] a) {
        foreach (var s in a) System.Console.WriteLine(System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(s)));
    }
}
'@
$built = $false
try { Add-Type -OutputAssembly $echo -OutputType ConsoleApplication -TypeDefinition $echoSrc; $built = $true } catch {}
if (-not $built) {
    # pwsh 7's Add-Type builds libraries only. .NET Framework's own compiler,
    # which every Windows carries, still builds the exe.
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if ($env:WINDIR -and (Test-Path -LiteralPath $csc)) {
        $cs = Join-Path $sb 'echoargs.cs'
        [System.IO.File]::WriteAllText($cs, $echoSrc, $utf8)
        & $csc /nologo "/out:$echo" $cs | Out-Null
        $built = $LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $echo)
    }
}
if ($built) {
    $argsIn = @('plain', '', 'with space', 'quote"inside', 'trail\', 'C:\path with\', 'a\\"b', '--tools', '', $titleCard)
    $out = [System.Collections.Generic.List[string]]::new()
    $null = Invoke-ChatqProcess -Exe $echo -ArgList $argsIn -StdIn '' -OnLine { param($l) $out.Add($utf8.GetString([Convert]::FromBase64String($l))) } -TimeoutSec 30
    Check 'argument quoting round-trips' (($out -join '|') -eq ($argsIn -join '|')) ($out -join '|')
}
else {
    # said, never counted as a pass
    Write-Host '  skip  argument quoting round-trips - nothing here can build the echo exe' -ForegroundColor Yellow
}
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
# as a real run leaves it: the chat's transcript written this minute
(Get-Item -LiteralPath $j.path).LastWriteTime = Get-Date
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'an idle live chat runs, with a reload warning' ($j.state -eq 'done' -and $j.result.stale) "$($j.state) stale=$($j.result.stale)"
$rq = [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json
Check 'and a reload offer for the window that holds it' ($rq.kind -eq 'ran' -and $rq.cwd -eq $projA) "$($rq.kind) $($rq.cwd)"
# projA has chats left mid-turn by the tests above, so busy is only checked
# for being judged here; 'reload while a chat works' checks its value
Check 'saying nobody is at the PC, and whether the folder was busy' ($rq.away -eq $true -and $null -ne $rq.busy) "away=$($rq.away) busy=$($rq.busy)"
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

Section 'the job core'
# what chatq writes is what it always wrote, plus sendNow at the end
$jc = New-TestJob 'card redesign' 'field order'
$fields = ($jc.PSObject.Properties | ForEach-Object Name) -join ','
$want = 'v,id,seq,provider,sessionId,title,group,path,cwd,home,chatWhen,typed,rule,score,runnerUp,kind,promptFile,mode,modeAtQueue,model,runModel,first,sandbox,network,notBefore,state,attempts,retryAs,autoContinue,deferUntil,deferredSince,busyAlerted,createdAt,startedAt,endedAt,runnerPid,result,history,sendNow'
Check 'a job made by chatq has the fields it always had, in order, and sendNow' ($fields -eq $want -and $jc.sendNow -eq $false) $fields
$null = Remove-ChatqJob $jc 'test'
$rowCard = Get-ChatqRowById $idCard
$rowUpper = Get-ChatqRowById $idCard.ToUpperInvariant()
Check 'a row by its id - exact, any case, nothing fuzzy' ($rowCard.Id -eq $idCard -and $rowUpper.Id -eq $idCard -and -not (Get-ChatqRowById 'facade') -and -not (Get-ChatqRowById $idCard.Substring(0, 8))) "$($rowCard.Title)"
$before = @(Get-ChildItem -LiteralPath $script:ChatqQueueDir).Count
$nEmpty = New-ChatqJob -Row $rowCard -Prompt '   '
$nCopilot = New-ChatqJob -Row ([pscustomobject]@{ Provider = 'copilot'; Id = 'x'; Title = 'c' }) -Prompt 'hi'
$nKind = New-ChatqJob -Row $rowCard -Kind continue -Sources @{ Files = @($pFw) }
$nInfo = New-ChatqJob -Row ([pscustomobject]@{ Provider = 'claude'; Id = 'deadbeef-0000'; Title = 'gone'; Path = (Join-Path $sb 'no-such.jsonl'); Group = 'x' }) -Prompt 'hi'
$nCopy = New-ChatqJob -Row $rowCard -Prompt 'with a file' -Sources @{ Files = @($pFw, (Join-Path $sb 'no-such-file.png')) }
$after = @(Get-ChildItem -LiteralPath $script:ChatqQueueDir).Count
Check 'New-ChatqJob says why and leaves nothing: empty, Copilot, continue with files, a chat gone, a file gone' (
    $nEmpty.Code -eq 'empty' -and $nEmpty.Error -eq 'empty prompt - nothing queued' -and $nCopilot.Code -eq 'provider' -and $nKind.Code -eq 'kind' -and
    $nInfo.Code -eq 'info' -and $nCopy.Code -eq 'copy' -and $nCopy.Error -like 'a file could not be copied - nothing queued*' -and $after -eq $before -and -not $nCopy.Job) "$($nEmpty.Code) $($nCopilot.Code) $($nKind.Code) $($nInfo.Code) $($nCopy.Code) $before/$after"
# the console's own staged copy moves in; two jobs in one second get two ids
$stage = Join-Path $sb 'stage'
$null = New-Item -ItemType Directory -Path $stage -Force
$staged = Join-Path $stage 'shot 1.png'
[System.IO.File]::WriteAllBytes($staged, [byte[]](1, 2, 3))
$at = (Get-Date).AddHours(3)
$n1 = New-ChatqJob -Row $rowCard -Prompt 'first of two' -First -SendNow -Model 'sonnet' -NotBefore $at -Sources @{ Files = @($staged); Images = @(@{ Name = 'clip.png'; Bytes = [byte[]](9, 9) }) } -MoveSources -Rule 'picked'
$n2 = New-ChatqJob -Row $rowCard -Prompt 'second of two' -Rule 'picked'
$f1 = @($n1.Files | ForEach-Object Name | Sort-Object) -join ','
Check 'New-ChatqJob: first, send now, a model, not before, a staged file moved in and a pasted image' (
    $n1.Job -and $n1.Job.first -and $n1.Job.sendNow -and $n1.Job.runModel -eq 'sonnet' -and $n1.Job.rule -eq 'picked' -and
    [math]::Abs(((ConvertTo-ChatqDate $n1.Job.notBefore) - $at).TotalSeconds) -lt 2 -and $f1 -eq 'clip.png,shot-1.png' -and -not (Test-Path -LiteralPath $staged) -and
    (Read-ChatqPrompt $n1.Job) -eq 'first of two') "$f1 $($n1.Job.notBefore)"
Check 'two jobs for one chat inside a second get ids of their own' ($n2.Job -and $n2.Job.id -ne $n1.Job.id -and (Get-ChatqAttachDir $n2.Job) -ne (Get-ChatqAttachDir $n1.Job)) "$($n1.Job.id) $($n2.Job.id)"
Check 'and the first one sorts ahead of the queue' ((@(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })[0]).id -eq $n1.Job.id)
# an id and the same id with -2 after it: the whole id finds the first, not
# nothing - the watcher looks each job up by id before it runs it
$twins = @([pscustomobject]@{ id = '20260924-101010-abcd'; seq = 1 }, [pscustomobject]@{ id = '20260924-101010-abcd-2'; seq = 2 })
Check 'a job is found by its whole id even when another id starts with it' (
    (Find-ChatqJob '20260924-101010-abcd' $twins).seq -eq 1 -and (Find-ChatqJob '20260924-101010-abcd-2' $twins).seq -eq 2 -and
    -not (Find-ChatqJob '20260924-101010' $twins))
$noAdd = Add-ChatqJobFiles ([pscustomobject]@{ seq = 9; state = 'done'; kind = 'prompt' }) @{ Files = @($pFw) }
Check 'files go only to a job still waiting' ($noAdd.Error -eq '#9 is done - files added now would go nowhere')
$null = Remove-ChatqJob $n1.Job 'test'
$null = Remove-ChatqJob $n2.Job 'test'
Check 'Remove-ChatqJob takes its prompt and files too' (-not (Test-Path -LiteralPath (Get-ChatqAttachDir $n1.Job)) -and -not (Test-Path -LiteralPath (Get-ChatqPromptPath $n1.Job)))
# what a run did, from its log - the plain run above
$ran = @(Get-ChatqJobs | Where-Object { $_.state -eq 'done' -and (Test-Path -LiteralPath (Join-Path $script:ChatqLogDir "$($_.id).jsonl")) })[0]
$ents = @(Get-ChatqLogEntries $ran)
$tail = @(Get-ChatqLogEntries $ran -MaxBytes 200)
Check 'a run''s log read as entries: its start, the reply, how it ended; a tail read reads less' (
    @($ents | Where-Object Type -eq 'init').Count -and @($ents | Where-Object Type -eq 'result').Count -and $tail.Count -lt $ents.Count) "$(($ents | ForEach-Object Type) -join ',') / $($tail.Count)"
# a running job's log is held open for writing by its run
$held = [System.IO.File]::Open((Join-Path $script:ChatqLogDir "$($ran.id).jsonl"), 'Open', 'ReadWrite', 'ReadWrite')
try { $entsHeld = @(Get-ChatqLogEntries $ran) } finally { $held.Dispose() }
Check 'and read while a run still holds it open to write' ($entsHeld.Count -eq $ents.Count) "$($entsHeld.Count) of $($ents.Count)"
Check 'Stop-ChatqJobRun leaves a job that already ended as it ended' ((Stop-ChatqJobRun $ran) -eq 'not running' -and (Find-ChatqJob $ran.id).state -eq 'done')
# the watcher asked for without a wait: the wake goes, a process only when none runs
$spawnWas = $script:ChatqSpawn
$script:ChatqSpawns = 0
$script:ChatqSpawn = { $script:ChatqSpawns++; $true }
$lk = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rq1 = Request-ChatqWatcher -Wake now
$ms1 = $sw.ElapsedMilliseconds
$sp1 = $rq1.Spawned
$st1 = Test-ChatqWatcherRequest $rq1 $true
$lk.Dispose()
$rq2 = Request-ChatqWatcher
$st2 = Test-ChatqWatcherRequest $rq2 $true
$rq2.At = (Get-Date).AddSeconds(-11)
$st3 = Test-ChatqWatcherRequest $rq2 $true
# one running when poked that has gone since, with jobs waiting: started again, once
$st4 = Test-ChatqWatcherRequest $rq1 $true
$st5 = Test-ChatqWatcherRequest $rq1 $false
$script:ChatqSpawn = $spawnWas
Check 'Request-ChatqWatcher never waits: a running watcher gets the wake, none gets a start' (
    $rq1.Alive -and -not $sp1 -and $ms1 -lt 500 -and $st1 -eq 'up' -and (Get-Content -LiteralPath $script:ChatqWakePath -Raw).Trim() -eq 'poke' -and
    $rq2.Spawned -and $st2 -eq 'waiting' -and $st3 -eq 'failed' -and $st4 -eq 'waiting' -and $rq1.Respawned -and $st5 -eq 'up' -and $script:ChatqSpawns -eq 2) "$ms1 ms $st1 $st2 $st3 $st4 $st5 spawns=$($script:ChatqSpawns)"

Section 'new chats'
$newDir = Join-Path $sb 'work\fresh project'
$null = New-Item -ItemType Directory -Path $newDir -Force
$nn = New-ChatqJob -Kind new -Cwd $newDir -Prompt "set up the build`nwith tests"
$nj = $nn.Job
$slugNew = ($newDir -replace '[^A-Za-z0-9]', '-')
Check 'a new chat''s job: its session id chosen now, its transcript''s path known, named by the first line' (
    $nj.kind -eq 'new' -and $nj.sessionId -match '^[0-9a-f-]{36}$' -and $nj.title -eq 'set up the build' -and $nj.rule -eq 'new' -and
    $nj.path -eq (Join-Path (Join-Path (Join-Path $claudeHome 'projects') $slugNew) "$($nj.sessionId).jsonl") -and $nj.cwd -eq $newDir -and -not (Test-Path -LiteralPath $nj.path)) "$($nj.title) $($nj.path)"
$env:FAKE_RECORD = $rec
$env:FAKE_NEW_CHAT = '1'
Remove-Item -LiteralPath $script:ChatReloadPath -Force -EA SilentlyContinue
Invoke-ChatqJob $W (Find-ChatqJob $nj.id)
$nj = Find-ChatqJob $nj.id
$argvNew = @([System.IO.File]::ReadAllLines((Join-Path $rec 'argv.txt')))
$si = [Array]::IndexOf($argvNew, '--session-id')
$ni = [Array]::IndexOf($argvNew, '--name')
$rqNew = if (Test-Path -LiteralPath $script:ChatReloadPath) { [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json } else { $null }
Check 'its first run starts the chat with that id and name - no --resume - and it lands where said' (
    $nj.state -eq 'done' -and $si -ge 0 -and $argvNew[$si + 1] -eq $nj.sessionId -and $ni -ge 0 -and $argvNew[$ni + 1] -eq 'set up the build' -and
    $argvNew -notcontains '--resume' -and (Test-Path -LiteralPath $nj.path)) "$($nj.state) $($argvNew -join ' ')"
Check 'and a window on that folder is offered a reload to pick it up' ($rqNew -and $rqNew.kind -eq 'new' -and $rqNew.cwd -eq $newDir -and $rqNew.title -eq 'set up the build') "$($rqNew.kind) $($rqNew.cwd)"
$newRow = Get-ChatqRowById $nj.sessionId -Path $nj.path
$follow = (New-ChatqJob -Row $newRow -Prompt 'now the tests' -Rule 'picked').Job
Invoke-ChatqJob $W (Find-ChatqJob $follow.id)
$argvF = @([System.IO.File]::ReadAllLines((Join-Path $rec 'argv.txt')))
$ri = [Array]::IndexOf($argvF, '--resume')
Check 'the chat it made is a chat like any other: found by id, named, and the next prompt resumes it' (
    $newRow.Title -eq 'set up the build' -and $ri -ge 0 -and $argvF[$ri + 1] -eq $nj.sessionId -and $argvF -notcontains '--session-id' -and
    (Find-ChatqJob $follow.id).state -eq 'done') "$($newRow.Title) $($argvF -join ' ')"
# a limit after the prompt reached the new chat: back as a continue into it,
# never a second new chat
$nl = (New-ChatqJob -Kind new -Cwd $newDir -Prompt 'a second new one' -Title 'limited start').Job
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\rejected.jsonl'
Remove-Item -LiteralPath $script:ChatReloadPath -Force -EA SilentlyContinue
Invoke-ChatqJob $W (Find-ChatqJob $nl.id)
$nl = Find-ChatqJob $nl.id
$rqLimited = Test-Path -LiteralPath $script:ChatReloadPath
Remove-Item env:FAKE_SCENARIO
$W.blocked = @{}
# Claude Code writes the limit into the chat as it stops; the continue goes
# only while that is still the chat's last word
$limRec = [ordered]@{ type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = (Get-Date).ToUniversalTime().ToString('o'); sessionId = $nl.sessionId
    message = [ordered]@{ model = '<synthetic>'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = "You've hit your session limit" }) }
    quotaLimits = [ordered]@{ status = 'rejected'; resetsAt = [DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds(); rateLimitType = 'five_hour' }
    error = 'rate_limit'; isApiErrorMessage = $true } | ConvertTo-Json -Compress -Depth 6
[System.IO.File]::AppendAllText($nl.path, $limRec + "`n", $utf8)
Invoke-ChatqJob $W (Find-ChatqJob $nl.id)
$argvL = @([System.IO.File]::ReadAllLines((Join-Path $rec 'argv.txt')))
$stdinL = [System.IO.File]::ReadAllText((Join-Path $rec 'stdin.bin'), $utf8)
$ri = [Array]::IndexOf($argvL, '--resume')
Check 'a new chat limited after its prompt landed goes on as "continue" in that same chat' (
    $nl.retryAs -eq 'continue' -and $ri -ge 0 -and $argvL[$ri + 1] -eq $nl.sessionId -and $stdinL -eq $script:ChatqContinueText -and (Find-ChatqJob $nl.id).state -eq 'done') "$($nl.retryAs) $($argvL -join ' ')"
$rqL = if (Test-Path -LiteralPath $script:ChatReloadPath) { [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json } else { $null }
Check 'its reload is offered when it finishes, not lost with the run the limit cut' (-not $rqLimited -and $rqL.kind -eq 'new' -and $rqL.title -eq 'limited start') "$rqLimited $($rqL.kind) $($rqL.title)"
# Claude filed it under a folder name that is not the slug - a path over 200
# characters, or CLAUDE_CODE_PROJECT_DIR_NAME: found by its id and kept, and
# never started twice with --session-id, which Claude refuses. Its title goes
# through claude.cmd - cmd.exe - with nothing cmd would take as its own.
$env:CLAUDE_CODE_PROJECT_DIR_NAME = 'named-elsewhere'
$nr = (New-ChatqJob -Kind new -Cwd $newDir -Prompt 'filed elsewhere' -Title 'Use "quotes" & more').Job
Remove-Item -LiteralPath $script:ChatReloadPath -Force -EA SilentlyContinue
Invoke-ChatqJob $W (Find-ChatqJob $nr.id)
$nr = Find-ChatqJob $nr.id
$argvR = @([System.IO.File]::ReadAllLines((Join-Path $rec 'argv.txt')))
$ni = [Array]::IndexOf($argvR, '--name')
$wantR = Join-Path (Join-Path (Join-Path $claudeHome 'projects') 'named-elsewhere') "$($nr.sessionId).jsonl"
$rqR = if (Test-Path -LiteralPath $script:ChatReloadPath) { [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json } else { $null }
Check 'a title through claude.cmd keeps its words and loses what cmd.exe would run' ($ni -ge 0 -and $argvR[$ni + 1] -eq 'Use quotes more' -and $argvR -contains 'stream-json') ($argvR -join ' ')
Check 'a new chat filed under another folder name is found by its id, and kept' (
    $nr.state -eq 'done' -and $nr.path -eq $wantR -and $nr.group -eq 'named-elsewhere' -and $rqR.kind -eq 'new') "$($nr.state) $($nr.path) $($rqR.kind)"
$null = Reset-ChatqJob $nr
Invoke-ChatqJob $W (Find-ChatqJob $nr.id)
$argvR2 = @([System.IO.File]::ReadAllLines((Join-Path $rec 'argv.txt')))
Check 'and a requeue resumes it' ((Find-ChatqJob $nr.id).state -eq 'done' -and $argvR2 -contains '--resume' -and $argvR2 -notcontains '--session-id') ($argvR2 -join ' ')
Remove-Item env:CLAUDE_CODE_PROJECT_DIR_NAME
# its transcript deleted since: the continue fails as a chat gone - never a
# fresh chat whose only prompt is "continue"
Remove-Item -LiteralPath $nr.path -Force
$null = Reset-ChatqJob (Find-ChatqJob $nr.id)
Remove-Item -LiteralPath (Join-Path $rec 'argv.txt') -Force
Invoke-ChatqJob $W (Find-ChatqJob $nr.id)
$gone = Find-ChatqJob $nr.id
Check 'a new chat deleted since is gone: no second start' ($gone.state -eq 'failed' -and $gone.result.reason -like '*chat is gone*' -and -not (Test-Path -LiteralPath (Join-Path $rec 'argv.txt'))) "$($gone.state) $($gone.result.reason)"
Remove-Item env:FAKE_NEW_CHAT, env:FAKE_RECORD
$noDir = New-ChatqJob -Kind new -Cwd (Join-Path $sb 'no such folder') -Prompt 'x'
$noText = New-ChatqJob -Kind new -Cwd $newDir -Prompt ' '
$cutOk = try { $null = Get-ChatqCutOffChats (@(Get-ChatqJobs) + @([pscustomobject]@{ state = 'queued'; sessionId = $null })); $true } catch { $false }
Check 'a folder that is not there, or no prompt, makes no job; a job with no session never breaks the cut-off list' (
    $noDir.Code -eq 'info' -and $noText.Code -eq 'empty' -and $cutOk) "$($noDir.Error) / $($noText.Code) / $cutOk"
# a drive's root: C:\, not C: - which as a working folder means wherever
# that drive last was - and Claude's slug for it, C--
$driveRoot = [System.IO.Path]::GetPathRoot($sb)
$nroot = (New-ChatqJob -Kind new -Cwd $driveRoot -Prompt 'at the root').Job
$rootSlug = ($driveRoot -replace '[^A-Za-z0-9]', '-')
Check 'a new chat at a drive''s root keeps the root, and the slug Claude gives it' (
    $nroot.cwd -eq $driveRoot -and $nroot.group -eq $rootSlug -and (Get-ChatSlug 'D:\a\b\') -eq 'D--a-b' -and (Get-ChatSlug 'C:\') -eq 'C--') "$($nroot.cwd) $($nroot.group)"
foreach ($x in $nj, $follow, $nl, $nr, $nroot) { $null = Remove-ChatqJob (Find-ChatqJob $x.id) 'test' }

Section 'find and delete'
$rows = @(Sync-ChatIndex)
$provs = (@($rows | ForEach-Object Provider | Sort-Object -Unique)) -join ','
Check 'the index holds all three providers' ($provs -eq 'claude,codex,copilot') $provs
$hr = @($rows | Where-Object { $_.Id -eq $cx2Id })
Check 'a Hangul Codex thread name is read as UTF-8' ($hr.Count -eq 1 -and $hr[0].Title -eq $tHan) "$($hr.Title)"
$qr = @($rows | Where-Object { $_.Id -eq $idQuote })
Check 'an escaped Claude title comes back unescaped' ($qr.Count -eq 1 -and $qr[0].Title -eq 'Say "hi" to it') "$($qr.Title)"
$f = @(chatfind 'Doomed chat one')
Check 'chatfind by title' ($f.Count -eq 1 -and $f[0].Id -eq $idDoom1) $f.Count
$f = @(chatfind 'unique prompt phrase zebra')
Check 'chatfind by prompt text' ($f.Count -eq 1 -and $f[0].Id -eq $idDoom1) $f.Count
Check 'text past the previews is left to -Deep' (@(chatfind 'needle-deep-xyz').Count -eq 0 -and @(chatfind 'needle-deep-xyz' -Deep).Count -eq 1)

chatrm 'Doomed chat one' -Force *> $null
Check 'chatrm -Force removes the transcript and its leftovers' (-not (Test-Path -LiteralPath $pDoom1) -and -not (Test-Path -LiteralPath $side) -and
    -not (Test-Path -LiteralPath (Join-Path $claudeHome "file-history\$idDoom1")) -and -not (Test-Path -LiteralPath (Join-Path $claudeHome "session-env\$idDoom1")))
$tomb = if (Test-Path -LiteralPath $script:ChatTombPath) { [System.IO.File]::ReadAllText($script:ChatTombPath, $utf8) } else { '' }
Check 'a tombstone is written and the row leaves the index' ($tomb -like "*$idDoom1*" -and -not @(Get-ChatIndex | Where-Object { $_.Id -eq $idDoom1 }))
$gone = @('Debug', 'Tasks', 'Sec', 'SecLock', 'Tele', 'Todo', 'Plan', 'PlanAgent' | Where-Object { Test-Path -LiteralPath $left[$_] })
Check 'and every other leftover: debug, tasks, security, telemetry, todos, plans' (-not $gone) ($gone -join ',')
Check 'a background job folder goes by the id inside it' (-not (Test-Path -LiteralPath (Split-Path $left.Job -Parent)))

$j = New-TestJob 'Doomed chat two' 'keep me'
chatrm 'Doomed chat two' -Force *> $null
Check 'a chat with a prompt queued for it is kept' ((Test-Path -LiteralPath $pDoom2) -and (Find-ChatqJob $j.id))
chatrm 'Doomed chat two' -Force -DropJobs *> $null
Check '-DropJobs drops the prompt, then deletes' (-not (Test-Path -LiteralPath $pDoom2) -and -not (Find-ChatqJob $j.id))
Check 'a plan file another chat in the project shares is kept' (Test-Path -LiteralPath $left.Shared)

# held open without delete sharing, as a live window holds it: nothing goes
$fh = [System.IO.File]::Open($pLock, 'Open', 'Read', 'Read')
try { chatrm 'Locked open chat' -Force *> $null } finally { $fh.Dispose() }
Check 'a locked transcript keeps its leftovers' ((Test-Path -LiteralPath $pLock) -and (Test-Path -LiteralPath $lockHist))

$r = Resolve-ChatqTarget 'Copilot chat about tests'
Check 'a Copilot chat is named, then refused' ($r.Error -like '*Copilot*') $r.Error
$r = Resolve-ChatqTarget 'zzqx nothing like it'
Check 'a guess is never a Copilot chat' ($r.Row -and $r.Row.Provider -ne 'copilot') "$($r.Row.Provider)"

function Complete([string]$Cmd, [string]$Param, [string]$Word, [hashtable]$Bound = @{}) {
    @(& $script:ChatTitleCompleter $Cmd $Param $Word $null $Bound)
}
Check 'chatq <digits> completes nothing' ((Complete 'chatq' 'Target' '3').Count -eq 0)
Check 'chatq never offers a Copilot chat' (-not @(Complete 'chatq' 'Target' 'Copilot' | Where-Object { $_.CompletionText -like '*Copilot*' }))
Check 'chatrm does' (@(Complete 'chatrm' 'Target' 'Copilot' | Where-Object { $_.CompletionText -like '*Copilot chat*' }).Count -eq 1)
Check 'a subagent chat is not offered' ((Complete 'chatrm' 'Target' 'Hidden sub').Count -eq 0)
Check '... unless -All is given' ((Complete 'chatfind' 'Text' 'Hidden sub' @{ All = $true }).Count -eq 1)
Check 'hex completes an id' (@(Complete 'chatrm' 'Target' '2222')[0].CompletionText -eq $idCard)
Check 'a title that looks like hex still completes' (@(Complete 'chatrm' 'Target' 'dead')[0].CompletionText -eq "'Deadline notes'")
$sq = @(Complete 'chatq' 'Target' 'Don')[0].CompletionText
$sqOk = try { (& ([scriptblock]::Create($sq))) -eq $tSmart } catch { $false }
Check 'a typographic apostrophe is quoted so it survives' $sqOk $sq
$byId = $false
Check 'Tab cycling skips a subagent chat' (@(Get-ChatCycleRows 'Hidden sub' ([ref]$byId)).Count -eq 0)
Check 'chatq cycling skips Copilot, chatrm cycling does not' (@(Get-ChatCycleRows 'Copilot' ([ref]$byId) -Queue).Count -eq 0 -and @(Get-ChatCycleRows 'Copilot' ([ref]$byId)).Count -eq 1)
Check 'a tail left mid-line comes off a chatq line' (("chatq 'Parser rewrite' (1h) #1/2 -Prompt 'x'" -replace $script:ChatMidTailPattern, '') -eq "chatq 'Parser rewrite' -Prompt 'x'")
Check 'a zero-width cell is empty, not an error' ((Format-ChatCell 'abc' 0) -eq '' -and (Format-ChatCell 'abcdef' 2) -eq '..')
Start-ChatGhostWatch
Check 'no ghost watch inside the background watcher' (-not (Test-ChatGhostWatch))

# one profile line for both halves, and uninstall takes only that
$PROFILE = Join-Path $sb 'profile.ps1'
[System.IO.File]::WriteAllLines($PROFILE, [string[]]@('. "C:\x\chatrm\chatrm.ps1"', 'Set-Alias foo bar', '. "C:\x\chatq\chatq.ps1"'))
chatinstall *> $null
$pl = @(Get-Content -LiteralPath $PROFILE)
$me = Join-Path $sb 'tool\VS-code-chat-manager.ps1'
Check 'one install line replaces chatrm''s and chatq''s' (@($pl | Where-Object { $_ -match $script:ChatProfilePattern }).Count -eq 1 -and
    ($pl -join "`n").Contains($me) -and $pl -contains 'Set-Alias foo bar') ($pl -join ' | ')
chatuninstall *> $null
$pl = @(Get-Content -LiteralPath $PROFILE)
Check 'uninstall leaves the rest of the profile alone' ($pl.Count -eq 1 -and $pl[0] -eq 'Set-Alias foo bar') ($pl -join ' | ')

# StrictMode again, the way a real shell loads it: not as the watcher, with no
# queue at all yet, and a stop on the first error
$sb2 = Join-Path $sb 'strict2'
$null = New-Item -ItemType Directory -Path $sb2 -Force
Copy-Item -LiteralPath (Join-Path $root 'VS-code-chat-manager.ps1') -Destination $sb2
$probe2 = "Remove-Item env:CHATQ_WATCHER -EA SilentlyContinue; Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; try { . '$(Join-Path $sb2 'VS-code-chat-manager.ps1')'; Set-Location -LiteralPath '$projA'; chatfind Doomed *> `$null; chatindex *> `$null; `$r = & `$script:ChatTitleCompleter 'chatrm' 'Target' 'Pars' `$null @{}; chatqlist *> `$null; chat *> `$null; chatoverlay -Print *> `$null; 'ok' } catch { 'threw: ' + `$_.Exception.Message + ' ' + `$_.InvocationInfo.PositionMessage }"
$strict2 = (& $exe -NoProfile -NonInteractive -Command $probe2 | Select-Object -Last 1)
Check 'loads and runs under StrictMode as a normal shell does' ($strict2 -eq 'ok') $strict2

function Get-AlertCount([string]$Like) {
    $f = Join-Path $script:ChatqLogDir 'alerts.log'
    if (-not (Test-Path -LiteralPath $f)) { return 0 }
    @([System.IO.File]::ReadAllLines($f, $utf8) | Where-Object { $_ -like $Like }).Count
}
function Lock-Queue([scriptblock]$Do) {
    # a held lock is what a running watcher looks like: chatq queues, starts none
    New-ChatqDir $script:ChatqData
    $lk = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    try { & $Do } finally { $lk.Dispose() }
}

Section 'retries and failures'
$o = Invoke-Scenario 'network'
Check 'a dropped connection -> network, not failed' ($o.kind -eq 'network') "$($o.kind) $($o.reason)"
$o = Invoke-Scenario 'auth'
Check 'an expired login -> auth, in the API''s own words' ($o.kind -eq 'auth' -and $o.reason -ceq 'login refused: OAuth token has expired. (401)') "$($o.kind) $($o.reason)"
# a subscription that ran out: a 403, not a login gone, and the words say so
$o = Invoke-Scenario 'auth-403'
$planWords = "This account$([char]0x2019)s plan does not include Claude Code. (403)"
Check 'a 403 -> auth, its message kept, not "logged out"' ($o.kind -eq 'auth' -and $o.reason -ceq "login refused: $planWords") "$($o.kind) $($o.reason)"
$w = Get-ChatqAuthWords 'API Error: 403 {"error":{"message":"Plan \"Max\" ended \u2014 renew"}}'
Check 'the message read out of the JSON, escapes and all, the code from the text' ($w -ceq "Plan `"Max`" ended $([char]0x2014) renew (403)") $w
$w = Get-ChatqAuthWords "Invalid API key`n  Please run /login" 401
Check 'no JSON: the text itself, one line' ($w -ceq 'Invalid API key Please run /login') $w
$w = Get-ChatqAuthWords ('x' * 400)
Check 'and cut short' ($w.Length -eq 160 -and $w.EndsWith($script:ChatqEllipsis)) $w.Length
Check 'nothing said at all still says something' ((Get-ChatqAuthWords '' 403) -ceq 'API Error 403' -and (Get-ChatqAuthWords '') -ceq 'no reason given')
$w = Get-ChatqAuthWords (('[warn] retrying ' * 20) + 'OAuth token has expired. Please run /login')
Check 'log noise ahead of the refusal does not crowd it out' ($w -ceq "$($script:ChatqEllipsis)OAuth token has expired. Please run /login") $w
# no result line: $text is the last reply, and a reply is never the refusal
$st = New-ChatqRunState
$st.LastText = 'Here is the payload: {"message":"hello"}'
$o = Get-ChatqClaudeOutcome $st ([pscustomobject]@{ ExitCode = 1; StdErr = 'OAuth token has expired. Please run /login'; Stopped = $null }) 'auto'
Check 'the words come from the error, never from the chat''s reply' ($o.kind -eq 'auth' -and $o.reason -ceq 'login refused: OAuth token has expired. Please run /login') "$($o.kind) $($o.reason)"
$st = New-ChatqRunState
foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $here 'fixtures\stream\codex-auth.jsonl'), $utf8)) { if ($l.Trim()) { Update-ChatqCodexState $st $l } }
$o = Get-ChatqCodexOutcome $st ([pscustomobject]@{ ExitCode = 1; StdErr = ''; Stopped = $null })
Check 'codex refused -> auth, its message and "unexpected status" code kept' ($o.kind -eq 'auth' -and $o.reason -ceq 'login refused: Your refresh token has expired. Please sign in again. (401)') "$($o.kind) $($o.reason)"
Check 'and the error text whole beside it' ($o.detail -like 'unexpected status 401 Unauthorized: {"error":{"message":"Your refresh token*"code":"refresh_token_expired"}}') $o.detail
$st = New-ChatqRunState
foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $here 'fixtures\stream\codex-network.jsonl'), $utf8)) { if ($l.Trim()) { Update-ChatqCodexState $st $l } }
$o = Get-ChatqCodexOutcome $st ([pscustomobject]@{ ExitCode = 1; StdErr = ''; Stopped = $null })
Check 'codex "stream disconnected" -> network' ($o.kind -eq 'network') "$($o.kind) $($o.reason)"
$o = Get-ChatqClaudeOutcome (New-ChatqRunState) ([pscustomobject]@{ ExitCode = 1; StdErr = 'ECONNRESET'; Stopped = 'timeout' }) 'auto'
Check 'chatq''s own time limit is never taken for a network drop' ($o.kind -eq 'failed' -and $o.reason -eq 'timeout') "$($o.kind) $($o.reason)"

$pDead = Join-Path (Join-Path (Join-Path $claudeHome 'projects') (Get-Slug $projA)) "$idDead.jsonl"
$env:FAKE_RECORD = $rec
$j = New-TestJob 'Deadline notes' 'survive the drop'
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\network.jsonl'
$env:FAKE_LAND = $pDead
$Wn = New-ChatqWatchState
Invoke-ChatqJob $Wn (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
$ra = ConvertTo-ChatqDate $j.retryAt
$inS = if ($ra) { ($ra - (Get-Date)).TotalSeconds } else { -1 }
Check 'network drop -> queued again, a minute out' ($j.state -eq 'queued' -and $inS -gt 30 -and $inS -lt 90) "$($j.state) in $inS s"
Check 'the landed prompt comes back as a continue that is always sent' ($j.retryAs -eq 'continue' -and -not $j.autoContinue -and [int]$j.netRetries -eq 1) "$($j.retryAs) $($j.autoContinue) $($j.netRetries)"
Check 'the watcher will not pick it before then' ($null -ne (Get-ChatqDueTime $Wn $j (Get-Date)))
foreach ($k in 2, 3, 4) { Invoke-ChatqJob $Wn (Find-ChatqJob $j.id) }
$j = Find-ChatqJob $j.id
Check 'three retries, then it fails' ($j.state -eq 'failed' -and $j.result.reason -like '*gave up after 3*') "$($j.state) $($j.result.reason)"
Remove-Item env:FAKE_SCENARIO, env:FAKE_LAND

$cfg0 = Get-ChatqConfig
Set-ChatqProp $cfg0 'maxRetries' 2
Save-ChatqJson $script:ChatqConfigPath $cfg0
$j = New-TestJob 'Many prompts chat' 'try twice'
$Wc = New-ChatqWatchState
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\rejected.jsonl'
Invoke-ChatqJob $Wc (Find-ChatqJob $j.id)
$j1 = Find-ChatqJob $j.id
Check 'a run cut off before any reply counts toward the cap' ($j1.state -eq 'queued' -and [int]$j1.noProgress -eq 1) "$($j1.state) $($j1.noProgress)"
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\weekly-synthetic.jsonl'
Invoke-ChatqJob $Wc (Find-ChatqJob $j.id)
$j1 = Find-ChatqJob $j.id
Check 'one that got a reply first starts the count over' ($j1.state -eq 'queued' -and [int]$j1.noProgress -eq 0) "$($j1.state) $($j1.noProgress)"
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\rejected.jsonl'
Invoke-ChatqJob $Wc (Find-ChatqJob $j.id)
Invoke-ChatqJob $Wc (Find-ChatqJob $j.id)
$j1 = Find-ChatqJob $j.id
Check 'maxRetries in a row with no reply -> gave up' ($j1.state -eq 'failed' -and $j1.result.reason -like 'gave up*') "$($j1.state) $($j1.result.reason)"
$cfg0.PSObject.Properties.Remove('maxRetries')
Save-ChatqJson $script:ChatqConfigPath $cfg0

$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\auth.jsonl'
$Wa = New-ChatqWatchState
$ja = [pscustomobject]@{ id = 'auth-x'; provider = 'claude'; home = $null; model = 'claude-opus-5'; runModel = $null; cwd = $projA; title = 'x'; seq = 99 }
$a0 = Get-AlertCount '*login refused*'
$ok = Confirm-ChatqAllowed $Wa $ja
Check 'a login gone: the lane waits and its jobs stay queued' (-not $ok -and $Wa.blocked[(Get-ChatqLane $ja)].Type -eq 'login needed') "$ok $($Wa.blocked['claude'].Type)"
$null = Confirm-ChatqAllowed $Wa $ja
Check 'with one alert, not one per probe' ((Get-AlertCount '*login refused*') -eq $a0 + 1)
Check 'which quotes the API and names both ways out' ((Get-AlertCount '*login refused: OAuth token has expired. (401)*/login, or check the subscription*') -eq 1)
$wlog = [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'watcher.log'), $utf8)
Check 'the watcher log keeps the same words' ($wlog -like '*claude login refused: OAuth token has expired. (401)*')
Check 'and the error text whole, type and all' ($wlog -like '*claude error text: Failed to authenticate. API Error: 401 {"type":"error","error":{"type":"authentication_error",*')
Check 'and so does the status line' ((Get-ChatqStatusLine @() $Wa.blocked) -like '*Claude login refused: OAuth token has expired. (401) - log in or check the subscription*') (Get-ChatqStatusLine @() $Wa.blocked)
$old = @{ claude = [pscustomobject]@{ Until = (Get-Date).AddMinutes(9); Type = 'login needed'; Source = 'probe' } }
Check 'a watcher from before the words were kept still reads right' ((Get-ChatqStatusLine @() $old) -like '*Claude login refused - log in*') (Get-ChatqStatusLine @() $old)

# the same refusal met by a run rather than the probe
$j = New-TestJob 'Deadline notes' 'after the plan ran out'
$env:FAKE_SCENARIO = Join-Path $here 'fixtures\stream\auth-403.jsonl'
$Wp = New-ChatqWatchState
Invoke-ChatqJob $Wp (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
$bp = $Wp.blocked[(Get-ChatqLane $j)]
Check 'a 403 mid-run: the job waits, the lane holds what the API said' ($j.state -eq 'queued' -and $bp.Type -eq 'login needed' -and $bp.Source -ceq "login refused: $planWords") "$($j.state) $($bp.Type) $($bp.Source)"
Check 'and the job''s result says it too' ($j.result.kind -eq 'auth' -and $j.result.reason -ceq "login refused: $planWords") "$($j.result.reason)"
Check 'the alert quotes it on this path too' ((Get-AlertCount "*login refused: $planWords*check the subscription*") -eq 1)
$wlog = [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'watcher.log'), $utf8)
Check 'and so does the watcher log, error type and all' ($wlog -like "*login refused: $planWords*" -and $wlog -like '*error text: API Error: 403 {"type":"error","error":{"type":"permission_error",*')
Check 'and the status line' ((Get-ChatqStatusLine @() $Wp.blocked) -like "*login refused: $planWords - log in*") (Get-ChatqStatusLine @() $Wp.blocked)
chatqrm $j.seq -Force *> $null
Remove-Item env:FAKE_SCENARIO

Set-FakeStatus 'major_outage'
$Wr = New-ChatqWatchState
$Wr.outage['claude'] = @{ Since = (Get-Date).AddHours(-7); Attempts = 3; Status = 'major_outage'; Alerted = $true; LastProbe = (Get-Date).AddMinutes(-2); NextCheck = (Get-Date).AddSeconds(-1) }
$r0 = Get-AlertCount '*still overloaded after 6 h*'
$null = Test-ChatqOutageOver $Wr $ja
$Wr.outage['claude'].NextCheck = (Get-Date).AddSeconds(-1)
$null = Test-ChatqOutageOver $Wr $ja
Check 'an outage past 6 h sends one reminder' ((Get-AlertCount '*still overloaded after 6 h*') -eq $r0 + 1)
Set-FakeStatus 'operational'

Section 'per-job model and order'
Lock-Queue { chatq 'Deadline notes' -Prompt 'on another model' -Model 'claude-sonnet-9' *> $null }
$jm = @(Get-ChatqJobs | Where-Object { $_.runModel -eq 'claude-sonnet-9' })[0]
Check '-Model is kept apart from the chat''s own model' ($jm -and $jm.model -eq 'claude-opus-5') "$($jm.runModel) $($jm.model)"
$null = Invoke-ChatqProbe 'claude' $jm
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
Check 'the probe asks with it' ($argv -match '--no-session-persistence' -and $argv -match '--model\s+claude-sonnet-9') ($argv -replace "`n", ' ')
Invoke-ChatqJob (New-ChatqWatchState) (Find-ChatqJob $jm.id)
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
Check 'and the run uses it' ($argv -match '--resume' -and $argv -match '--model\s+claude-sonnet-9') ($argv -replace "`n", ' ')
Lock-Queue { chatq 'Codex gitignore thread' -Prompt 'on gpt-9' -Model 'gpt-9' *> $null }
$jx = @(Get-ChatqJobs | Where-Object { $_.runModel -eq 'gpt-9' })[0]
$null = Invoke-ChatqRun $jx 'x' $null $null
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
Check 'a Codex run gets -m before the thread id' ($argv -match "-m\s+gpt-9\s+$cxId") ($argv -replace "`n", ' ')
chatqrm $jx.seq -Force *> $null

Lock-Queue {
    chatq 'Old chat about gitignore rules' -Prompt 'back of the line' *> $null
    chatq 'Old chat about gitignore rules' -Prompt 'front of the line' -First *> $null
}
$q = @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })
Check '-First puts a job ahead of older ones' ((Read-ChatqPrompt $q[0]) -eq 'front of the line') (Read-ChatqPrompt $q[0])
$eta = Get-ChatqEta $q @{}
Check 'and the "sends" column agrees' ($eta[$q[0].id] -eq 'next') $eta[$q[0].id]
$back = @($q | Where-Object { (Read-ChatqPrompt $_) -eq 'back of the line' })[0]
chatqrun $back.seq -First *> $null
$q = @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })
Check 'chatqrun <n> -First moves a queued job up' ($q[0].id -eq $back.id) (Read-ChatqPrompt $q[0])
foreach ($x in @($q | Where-Object { (Read-ChatqPrompt $_) -like '*of the line' })) { chatqrm $x.seq -Force *> $null }
# a job's own history goes with its file, so the diary is the only account left
# of one that was removed rather than run
$diary = [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'jobs.log'), $utf8)
Check 'every job event is logged, removals included' ($diary -match "#$($back.seq) queued \(prompt\)" -and $diary -match "#$($back.seq) removed by chatqrm \(was queued\)") (@($diary -split "`n" | Where-Object { $_ -match "#$($back.seq) " }) -join ' / ')
Remove-Item env:FAKE_RECORD

Section 'attachments'
$env:FAKE_RECORD = $rec
$af = Join-Path $sb 'attach-src'
$null = New-Item -ItemType Directory -Path $af -Force
$png = Join-Path $af 'mock up.png'          # the space comes out of the copy's name
[System.IO.File]::WriteAllBytes($png, [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3))
$txt = Join-Path $af 'notes.txt'
[System.IO.File]::WriteAllText($txt, 'the notes', $utf8)
$n0 = @(Get-ChatqJobs).Count
$d0 = @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Directory -EA SilentlyContinue).Count
Lock-Queue { chatq 'Deadline notes' -Prompt 'look' -Attach (Join-Path $af 'nope.png') *> $null }
Check 'a missing file queues nothing' (@(Get-ChatqJobs).Count -eq $n0)
Lock-Queue { chatq 'Deadline notes' -Continue -Attach $txt *> $null }
Check '-Continue with files is refused - it sends "continue" alone' (@(Get-ChatqJobs).Count -eq $n0)
$said = Lock-Queue { chatq 'Deadline notes' -Prompt 'look' -Attach $png, $txt -WhatIf 6>&1 | Out-String }
Check '-WhatIf names the files and copies none' ($said -like '*2 files*' -and @(Get-ChatqJobs).Count -eq $n0 -and
    @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Directory -EA SilentlyContinue).Count -eq $d0) $said

Lock-Queue { chatq 'Deadline notes' -Prompt 'compare these' -Attach $png, $txt *> $null }
$ja = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'compare these' })[0]
$fa = @(Get-ChatqAttachments $ja)
Check 'the files are copied into the job, in order, the space out of the name' ($fa.Count -eq 2 -and $fa[0].Name -eq 'mock-up.png' -and $fa[1].Name -eq 'notes.txt' -and (Test-Path -LiteralPath $png)) (($fa | ForEach-Object Name) -join ',')
[System.IO.File]::WriteAllText($txt, 'changed later', $utf8)
Check 'a copy, not a link: the original changing later changes nothing' ([System.IO.File]::ReadAllText($fa[1].FullName, $utf8) -eq 'the notes')
$shown = (Write-ChatqList 6>&1 | Out-String)
Check 'chatqlist counts a job''s files' ($shown -like '*+2 files*') ''
Invoke-ChatqJob (New-ChatqWatchState) (Find-ChatqJob $ja.id)
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
$stdin = [System.IO.File]::ReadAllText((Join-Path $rec 'stdin.bin'), $utf8)
Check 'Claude gets every file named under the prompt' ($stdin.StartsWith('compare these') -and
    $stdin -like "*Attached files - read each one:*- $($fa[0].FullName)*- $($fa[1].FullName)*") $stdin
Check 'and the job''s folder allowed with --add-dir' ($argv -like "*--add-dir`n$(Get-ChatqAttachDir $ja)*") ($argv -replace "`n", ' ')

Lock-Queue { chatq 'Codex gitignore thread' -Prompt 'look at this' -Attach $png, $txt *> $null }
$jc = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'look at this' })[0]
$fc = @(Get-ChatqAttachments $jc)
$null = Invoke-ChatqRun $jc 'look at this' $null $null -Files $fc
$argv = [System.IO.File]::ReadAllText((Join-Path $rec 'argv.txt'))
$stdin = [System.IO.File]::ReadAllText((Join-Path $rec 'stdin.bin'), $utf8)
Check 'Codex gets the image with -i, and -- before the thread id' ($argv -like "*-i`n$($fc[0].FullName)`n--`n$cxId`n-*") ($argv -replace "`n", ' ')
Check 'and the rest only named in the prompt, the image only said to be there' ($argv -notlike "*$($fc[1].FullName)*" -and $stdin -like "*- $($fc[1].FullName)*" -and
    $stdin -notlike "*$($fc[0].FullName)*" -and $stdin -like '*(1 image is attached to this message.)*') $stdin

# the same file twice is one copy; a wildcard is expanded; a file locked since
# it was checked stops the job instead of going without
$png2 = Join-Path $af 'second.png'
[System.IO.File]::WriteAllBytes($png2, [byte[]](0x89, 0x50, 0x4E, 0x47, 5))
Lock-Queue { chatq 'Deadline notes' -Prompt 'one file given two times' -Attach $png, $png *> $null }
$jd = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'one file given two times' })[0]
Check 'the same file given twice goes once' (@(Get-ChatqAttachments $jd).Count -eq 1)
Lock-Queue { chatq 'Deadline notes' -Prompt 'all the shots' -Attach (Join-Path $af '*.png') *> $null }
$jw = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'all the shots' })[0]
Check 'a wildcard brings every match' ((@(Get-ChatqAttachments $jw) | ForEach-Object Name) -join ',' -eq 'mock-up.png,second.png') ((@(Get-ChatqAttachments $jw) | ForEach-Object Name) -join ',')
$n2 = @(Get-ChatqJobs).Count
$d2 = @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Directory -EA SilentlyContinue).Count
$held = [System.IO.File]::Open($png2, 'Open', 'ReadWrite', 'None')
try { $said = Lock-Queue { chatq 'Deadline notes' -Prompt 'locked' -Attach $png, $png2 6>&1 | Out-String } } finally { $held.Dispose() }
Check 'a file that cannot be copied queues nothing, and leaves no folder' (@(Get-ChatqJobs).Count -eq $n2 -and
    @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Directory -EA SilentlyContinue).Count -eq $d2 -and $said -like '*could not be copied*') $said

# chatq <n> -Attach adds to a job still waiting, and only to one
$said = (chatq $jd.seq -Attach $txt 6>&1 | Out-String)
Check 'chatq <n> -Attach adds a file to a queued job' (@(Get-ChatqAttachments $jd).Count -eq 2 -and $said -like '*now has 2 files*') $said
$script:ChatqClipboardSeam = { [pscustomobject]@{ Image = $null; Files = @(); Text = 'words' } }
$said = (chatq $jd.seq -Paste 6>&1 | Out-String)
Check 'chatq <n> -Paste with only text says where text goes, and adds nothing' (@(Get-ChatqAttachments $jd).Count -eq 2 -and $said -like '*opens the prompt*') $said
$script:ChatqClipboardSeam = $null
$said = (chatq $ja.seq -Attach $txt 6>&1 | Out-String)
Check 'and nothing is added to one already sent' ($said -like '*would go nowhere*' -and @(Get-ChatqAttachments $ja).Count -eq 2) $said

# the clipboard, through a seam - never this machine's own. Closures: a seam
# runs inside chatq, whose own variables would shadow the test's.
$script:ChatqClipboardSeam = { [pscustomobject]@{ Image = [byte[]](0x89, 0x50, 0x4E, 0x47, 9, 9); Files = @(); Text = 'a caption that came along' } }
Lock-Queue { chatq 'Deadline notes' -Prompt 'what is wrong here' -Paste *> $null }
$jp = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'what is wrong here' })[0]
$fp = @(Get-ChatqAttachments $jp)
Check '-Paste: a screenshot becomes clip.png, the caption with it left out' ($fp.Count -eq 1 -and $fp[0].Name -eq 'clip.png' -and $fp[0].Length -eq 6) (($fp | ForEach-Object Name) -join ',')
$script:ChatqClipboardSeam = { [pscustomobject]@{ Image = $null; Files = @($txt, $af); Text = $null } }.GetNewClosure()
Lock-Queue { chatq 'Deadline notes' -Prompt 'files from explorer' -Paste *> $null }
$jf = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq 'files from explorer' })[0]
Check '-Paste: files copied in Explorer come in, a folder does not' (@(Get-ChatqAttachments $jf).Count -eq 1 -and @(Get-ChatqAttachments $jf)[0].Name -eq 'notes.txt')
$cbText = "a prompt with 'quotes', `"more`" and `$vars"
$script:ChatqClipboardSeam = { [pscustomobject]@{ Image = $null; Files = @(); Text = $cbText } }.GetNewClosure()
Lock-Queue { chatq 'Deadline notes' -Paste *> $null }
$jt = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -eq $cbText })[0]
Check '-Paste: text alone is the prompt, quotes and all' ($jt -and -not @(Get-ChatqAttachments $jt).Count)
Lock-Queue { chatq 'Deadline notes' -Prompt 'fix this:' -Paste *> $null }
$jt2 = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -like 'fix this:*' })[0]
Check '-Paste: text goes under a prompt given with it' ($jt2 -and (Read-ChatqPrompt $jt2) -eq "fix this:`n`n$cbText") (Read-ChatqPrompt $jt2)
$script:ChatqClipboardSeam = { [pscustomobject]@{ Image = $null; Files = @(); Text = '' } }
$n1 = @(Get-ChatqJobs).Count
Lock-Queue { chatq 'Deadline notes' -Prompt 'x' -Paste *> $null }
Check '-Paste with nothing on the clipboard queues nothing' (@(Get-ChatqJobs).Count -eq $n1)
$script:ChatqClipboardSeam = $null

# what VS Code writes when an image is pasted into the prompt tab: the file
# beside the prompt, in data/queue/, and a link to it
$pasted = Join-Path $script:ChatqQueueDir 'image.png'
[System.IO.File]::WriteAllBytes($pasted, [byte[]](0x89, 0x50, 0x4E, 0x47, 7))
Lock-Queue { chatq 'Deadline notes' -Prompt "see ![image](image.png), [the notes](<$txt>) and [a site](https://example.com)" *> $null }
$jl = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -like 'see !*' })[0]
$fl = @(Get-ChatqAttachments $jl)
$pt = Read-ChatqPrompt $jl
Check 'a pasted image moves into the job, and its link follows it' (-not (Test-Path -LiteralPath $pasted) -and ($fl.Name -contains 'image.png') -and $pt -like "*($($jl.id)/image.png)*") $pt
Check 'a link to a file anywhere else is left as it is - the chat opens that one' ($fl.Count -eq 1 -and $pt.Contains("[the notes](<$txt>)") -and $pt.Contains('(https://example.com)')) (($fl | ForEach-Object Name) -join ',')
# nothing outside data/queue is even looked at: chatq's own data, a share
$secret = Join-Path $script:ChatqData 'secret.txt'
[System.IO.File]::WriteAllText($secret, 'private', $utf8)
$p4 = Join-Path $script:ChatqQueueDir 'shot(1).png'
[System.IO.File]::WriteAllBytes($p4, [byte[]](0x89, 0x50, 0x4E, 0x47, 4))
$vs = Join-Path $script:ChatqQueueDir '#99 Some title'
$null = New-Item -ItemType Directory -Path $vs -Force
[System.IO.File]::WriteAllBytes((Join-Path $vs 'image.png'), [byte[]](0x89, 0x50, 0x4E, 0x47, 6))
Lock-Queue { chatq 'Deadline notes' -Prompt 'mix [a](../secret.txt) [b](\\chatq-no-such-host\s\x.png) ![c](shot(1).png) ![d](<#99 Some title/image.png>) [e](#top)' *> $null }
$jm2 = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -like 'mix *' })[0]
$fm = @(Get-ChatqAttachments $jm2)
$pm = Read-ChatqPrompt $jm2
Check 'a ../ link to chatq''s own data and a \\share link are not taken' ((Test-Path -LiteralPath $secret) -and $fm.Name -notcontains 'secret.txt' -and $pm -like '*(../secret.txt)*' -and $pm -like '*(\\chatq-no-such-host\s\x.png)*') $pm
Check 'a name with parentheses, and a folder VS Code named after the prompt, are' (($fm.Name -contains 'shot-1-.png') -and ($fm.Name -contains 'image.png') -and -not (Test-Path -LiteralPath $vs) -and $pm -like '*(#top)*') (($fm | ForEach-Object Name) -join ',')
chatqrm $jm2.seq *> $null
Remove-Item -LiteralPath $secret -Force
# the same file linked twice is one copy; a name another one starts with is
# its own file, and each link is rewritten where it stands
$p2 = Join-Path $script:ChatqQueueDir 'shot.png'
$p3 = Join-Path $script:ChatqQueueDir 'shot.png.bak'
[System.IO.File]::WriteAllBytes($p2, [byte[]](0x89, 0x50, 0x4E, 0x47, 2))
[System.IO.File]::WriteAllBytes($p3, [byte[]](0x89, 0x50, 0x4E, 0x47, 3, 3))
Lock-Queue { chatq 'Deadline notes' -Prompt 'twice ![a](shot.png) and ![b](shot.png), then [c](shot.png.bak)' *> $null }
$j2 = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt $_) -like 'twice*' })[0]
$f2 = @(Get-ChatqAttachments $j2)
Check 'a file linked twice is one copy, and a look-alike name keeps its own link' ($f2.Count -eq 2 -and
    (Read-ChatqPrompt $j2) -eq "twice ![a]($($j2.id)/shot.png) and ![b]($($j2.id)/shot.png), then [c]($($j2.id)/shot.png.bak)") (Read-ChatqPrompt $j2)
chatqrm $j2.seq *> $null
$dl = Get-ChatqAttachDir $jl
chatqrm $jl.seq *> $null
Check 'chatqrm takes the job''s files with it' (-not (Test-Path -LiteralPath $dl))
foreach ($x in @(Get-ChatqJobs | Where-Object { $_.id -in @($ja.id, $jc.id, $jp.id, $jf.id, $jt.id, $jt2.id, $jd.id, $jw.id) })) { chatqrm $x.seq -Force *> $null }
Remove-Item env:FAKE_RECORD

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

Section 'alert channels'
$topic = 'chatq-test-topic-7f3a'
$said = (chatqnotify -Ntfy $topic 6>&1 | Out-String)
Check 'ntfy is saved, and the topic is never printed whole' ((Get-ChatqConfig).ntfy.topic -and $said -notlike "*$topic*" -and $said -like '*cha...*') $said
$script:ChatqIdleSeam = 30
$n0 = $script:Ntfys.Count; $t0 = $script:Toasts.Count
$sent = Send-ChatqAlert 'done' 'at the desk' 1
Check 'at the PC: the toast shows, the phone stays quiet' ($script:Toasts.Count -eq $t0 + 1 -and $script:Ntfys.Count -eq $n0 -and -not $sent)
chatqnotify -Test *> $null
Check 'chatqnotify -Test reaches the phone anyway' ($script:Ntfys.Count -eq $n0 + 1)
$script:ChatqIdleSeam = 99999
$txt = "done $([char]0xC644)$([char]0xB8CC) a & b %PATH%"
$sent = Send-ChatqAlert 'done' $txt 2
$nb = $script:Ntfys[$script:Ntfys.Count - 1].Body | ConvertFrom-Json
Check 'away: ntfy gets JSON - the title, Hangul intact, priority 5' ($sent -and $nb.topic -eq $topic -and $nb.title -eq "chatq $([char]0xB7) done" -and $nb.message -eq $txt -and $nb.priority -eq 5) ($script:Ntfys[$script:Ntfys.Count - 1].Body)
$hookOut = Join-Path $sb 'hook.txt'
chatqnotify -Command ("Set-Content -LiteralPath '$hookOut' -Encoding UTF8 -Value (`$env:CHATQ_EVENT + '|' + `$env:CHATQ_TEXT + '|' + `$env:CHATQ_PRESENT)") *> $null
$null = Send-ChatqAlert 'needs input' $txt 2
$hk = if (Test-Path -LiteralPath $hookOut) { [System.IO.File]::ReadAllText($hookOut, $utf8).Trim() } else { '' }
Check 'the command gets the alert in its environment, & and %PATH% as they are' ($hk -eq "needs input|$txt|0") $hk
$script:ChatqHookTimeoutSec = 2
chatqnotify -Command 'Start-Sleep -Seconds 30' *> $null
$t1 = Get-Date
$null = Send-ChatqAlert 'test' 'slow hook' 0
Check 'a command that hangs is stopped' ((@($script:ChatqAlertReport) -join ' ') -like '*stopped after 2 s*' -and ((Get-Date) - $t1).TotalSeconds -lt 15) (@($script:ChatqAlertReport) -join ' ')
$script:ChatqHookTimeoutSec = $null
# the Join page shows a whole push URL, and pasting it is the obvious move
chatqnotify -ApiKey 'https://joinjoaomgcd.appspot.com/_ah/api/messaging/v1/sendPush?apikey=deadbeefcafe1234&deviceId=abc123' *> $null
$jn = (Get-ChatqConfig).join
Check 'a pasted Join URL gives up its key and device' ((Unprotect-ChatqSecret $jn.apiKey) -eq 'deadbeefcafe1234' -and $jn.device -eq 'abc123') "$($jn.device)"
chatqnotify -Off *> $null
Check 'chatqnotify -Off clears the phone and the command' (-not (Get-ChatqConfig).PSObject.Properties['ntfy'] -and -not (Get-ChatqConfig).PSObject.Properties['command'])
$script:ChatqIdleSeam = $null
$idle = try { Get-ChatqIdleSeconds } catch { 'threw' }
$script:ChatqIdleSeam = 99999
Check 'the idle clock reads without an error' ($null -eq $idle -or ($idle -is [double] -and $idle -ge 0)) "$idle"
# away is what lets a window reload by itself, so it is known, never assumed
$script:ChatqIdleSeam = 30
$awayAt = Test-ChatqUserAway $null
$script:ChatqIdleSeam = 99999
$awayGone = Test-ChatqUserAway $null
$awayZero = Test-ChatqUserAway ([pscustomobject]@{ quietMinutes = 0 })
$origIdle = ${function:Get-ChatqIdleSeconds}
${function:Get-ChatqIdleSeconds} = { $null }
$awayBlind = Test-ChatqUserAway $null
${function:Get-ChatqIdleSeconds} = $origIdle
Check 'away only when known: not at the PC, not with quietMinutes 0, not on a clock that cannot be read' (-not $awayAt -and -not $awayZero -and $awayGone -and -not $awayBlind) "$awayAt $awayZero $awayGone $awayBlind"

Section 'usage'
$fetched = [DateTimeOffset]::Now.AddMinutes(-20).ToUnixTimeMilliseconds()
$cj = '{"numStartups":3,"cachedUsageUtilization":{"fetchedAtMs":' + $fetched + ',"utilization":{"limits":[' +
'{"kind":"session","percent":83,"resets_at":"' + $now.AddHours(2).ToString('o') + '","scope":null},' +
'{"kind":"weekly_all","percent":41,"resets_at":"' + $now.AddDays(3).ToString('o') + '","scope":null},' +
'{"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}]}},"other":1}'
[System.IO.File]::WriteAllText((Join-Path $claudeHome '.claude.json'), $cj, $utf8)
$u = @(Get-ChatqUsage)
$ucl = @($u | Where-Object { $_.Provider -eq 'Claude' })[0]
$ucx = @($u | Where-Object { $_.Provider -eq 'Codex' })[0]
Check 'Claude''s usage from its own cache, with how old it is' ($ucl -and ($ucl.Parts -join ',') -eq '5h 83%,week 41%' -and $ucl.AsOf) "$($ucl.Parts -join ',') $($ucl.AsOf)"
Check 'Codex''s from the newest rollout that has any' ($ucx -and $ucx.Parts[0] -like '5h 100%, resets *' -and $ucx.Parts[1] -eq 'week 12%') "$($ucx.Parts -join ',')"
$shown = (Write-ChatqList 6>&1 | Out-String)
Check 'chatqlist shows it' ($shown -like '*usage  Claude 5h 83%*') ''
# Both caches refresh only when their own tool runs, so the numbers can be
# older than what the status line above them says - and a lane limited right
# now cannot be at 83% of a window it has spent.
$was = Get-ChatqState
Save-ChatqJson $script:ChatqStatePath ([ordered]@{
        pid = $PID; blocked = @{ claude = @{ until = (Get-Date).AddHours(1).ToUniversalTime().ToString('o'); type = 'five_hour'; source = 'transcript' } }; outage = @{}
    })
$shown = Lock-Queue { Write-ChatqList 6>&1 | Out-String }
Check 'a limited account reads 5h limited, never a percent from before it' ($shown -like '*Claude 5h limited*' -and $shown -notlike '*5h 83%*') (@($shown -split "`n" | Where-Object { $_ -like '*usage*' }) -join '')
# and only the window that is blocked: a week gone says nothing about the 5 h
Save-ChatqJson $script:ChatqStatePath ([ordered]@{
        pid = $PID; blocked = @{ claude = @{ until = (Get-Date).AddDays(2).ToUniversalTime().ToString('o'); type = 'weekly_all'; source = 'transcript' } }; outage = @{}
    })
$shown = Lock-Queue { Write-ChatqList 6>&1 | Out-String }
Check 'a weekly limit leaves the 5 h figure alone' ($shown -like '*Claude 5h 83%*' -and $shown -like '*week limited*') (@($shown -split "`n" | Where-Object { $_ -like '*usage*' }) -join '')
Save-ChatqJson $script:ChatqStatePath $was
[System.IO.File]::WriteAllText((Join-Path $claudeHome '.claude.json'),
    $cj.Replace("$fetched", [string]([DateTimeOffset]::Now.AddHours(-3).ToUnixTimeMilliseconds())), $utf8)
$shown = (Write-ChatqList 6>&1 | Out-String)
Check 'a reading hours old is marked stale' ($shown -match 'as of [^)]+ - stale') (@($shown -split "`n" | Where-Object { $_ -like '*usage*' }) -join '')

Section 'archive and restore'
chatrm 'Archive me please' -Archive -Force *> $null
$man = Join-Path $script:ChatArchiveDir "claude\$idArch\manifest.json"
Check 'chatrm -Archive moves the chat and its leftovers into data/archive' (-not (Test-Path -LiteralPath $pArch) -and -not (Test-Path -LiteralPath $archHist) -and (Test-Path -LiteralPath $man))
$tomb = if (Test-Path -LiteralPath $script:ChatTombPath) { [System.IO.File]::ReadAllText($script:ChatTombPath, $utf8) } else { '' }
Check 'the old path is tombstoned and leaves the index' ($tomb -like "*$idArch*" -and -not @(Get-ChatIndex | Where-Object { $_.Id -eq $idArch }))
Check 'chatrestore lists it' (@(Get-ChatArchive | Where-Object { $_.Id -eq $idArch }).Count -eq 1)
# what the window writes back on its next reload: a stub, no messages
[System.IO.File]::WriteAllText($pArch, ('{"type":"ai-title","aiTitle":"Archive me please","sessionId":"' + $idArch + '"}' + "`n"), $utf8)
chatrestore 'Archive me please' *> $null
$backText = if (Test-Path -LiteralPath $pArch) { [System.IO.File]::ReadAllText($pArch, $utf8) } else { '' }
Check 'restore replaces the stub with the chat, leftovers and all' ($backText -like '*archive this one*' -and (Test-Path -LiteralPath (Join-Path $archHist 'x')) -and -not (Test-Path -LiteralPath (Split-Path $man -Parent)))
$tomb = if (Test-Path -LiteralPath $script:ChatTombPath) { [System.IO.File]::ReadAllText($script:ChatTombPath, $utf8) } else { '' }
Check 'its tombstone is cleared and it is back in the index' ($tomb -notlike "*$idArch*" -and @(Get-ChatIndex | Where-Object { $_.Id -eq $idArch }).Count -eq 1)
chatrm 'Archive me please' -Archive -Force *> $null
[System.IO.File]::WriteAllText($pArch, ('{"type":"user","message":{"role":"user","content":"written since"},"sessionId":"x"}' + "`n"), $utf8)
chatrestore 'Archive me please' *> $null
Check 'restore never moves over a chat with messages in it' ((Test-Path -LiteralPath $man) -and ([System.IO.File]::ReadAllText($pArch, $utf8) -like '*written since*'))
Remove-Item -LiteralPath $pArch -Force
chatrestore 'Archive me please' *> $null
$env:FAKE_AGENTS = '[{"pid":1,"sessionId":"' + $idArch + '","kind":"interactive","status":"idle"}]'
chatrm 'Archive me please' -Archive -Force *> $null
Remove-Item env:FAKE_AGENTS
Check 'a chat still open in a window is not archived' ((Test-Path -LiteralPath $pArch) -and -not (Test-Path -LiteralPath $man))
chatrm 'Codex gitignore thread' -Archive -Force *> $null
$cxArch = @(Get-ChildItem -LiteralPath (Join-Path $codexHome 'archived_sessions') -Filter "*$cxId*" -Recurse -File -EA SilentlyContinue)
Check 'a Codex thread goes through codex archive' ($cxArch.Count -eq 1 -and -not (Test-Path -LiteralPath $cxPath))
Check 'and chatrestore lists it too' (@(Get-ChatArchive | Where-Object { $_.Id -eq $cxId -and $_.Provider -eq 'codex' }).Count -eq 1)
chatrestore 'Codex gitignore thread' *> $null
Check 'codex unarchive brings it back' ((Test-Path -LiteralPath $cxPath) -and -not (Test-Path -LiteralPath (Join-Path $script:ChatArchiveDir "codex\$cxId")))
chatrm 'Archive me please' -Archive -Force *> $null
chatuninstall -All *> $null
Check 'chatuninstall -All will not take the only copy of an archived chat' ((Test-Path -LiteralPath $man) -and (Test-Path -LiteralPath (Join-Path $sb 'tool\VS-code-chat-manager.ps1')))
chatrestore 'Archive me please' *> $null

Section 'reload while a chat works'
# A project of its own: every chat in projA was written to just now by the
# sections above, which is "active" on its own.
$projW = Join-Path $work 'projW'
$null = New-Item -ItemType Directory -Path $projW -Force
$idW1 = 'abababab-abab-4bab-8bab-abababababab'
$idW2 = 'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd'
$pW1 = New-FakeChat $projW $idW1 'Workflow host chat' 2 @('run the review workflow')
$null = New-FakeChat $projW $idW2 'Quiet neighbour chat' 3 @('nothing much')
$null = @(Sync-ChatIndex)
function Add-ChatRecord([string]$Path, $Record, [double]$MinutesAgo) {
    # one transcript record as Claude Code writes it: Node's JSON.stringify
    # leaves < > & ' alone, where 5.1's ConvertTo-Json escapes them
    $Record['timestamp'] = (Get-Date).ToUniversalTime().AddMinutes(-$MinutesAgo).ToString('o')
    $Record['sessionId'] = $idW1
    $u = [string][char]92 + 'u00'
    $j = ($Record | ConvertTo-Json -Compress -Depth 8).Replace("${u}3c", '<').Replace("${u}3e", '>').Replace("${u}26", '&').Replace("${u}27", "'")
    [System.IO.File]::AppendAllText($Path, $j + "`n", $utf8)
}
function Add-ChatLaunch([string]$Tool, $Result, [double]$MinutesAgo) {
    # the call, its result, and the turn ending straight after - the shape of
    # a turn that sends work to the background
    $use = 'toolu_' + [guid]::NewGuid().ToString('N')
    Add-ChatRecord $pW1 ([ordered]@{ type = 'assistant'; message = [ordered]@{ role = 'assistant'; stop_reason = 'tool_use'
                content = @([ordered]@{ type = 'tool_use'; id = $use; name = $Tool; input = @{} }) } }) $MinutesAgo
    Add-ChatRecord $pW1 ([ordered]@{ type = 'user'; message = [ordered]@{ role = 'user'
                content = @([ordered]@{ tool_use_id = $use; type = 'tool_result'; content = "$Tool launched in background" }) }
            toolUseResult = $Result }) $MinutesAgo
    Add-ChatRecord $pW1 ([ordered]@{ type = 'assistant'; message = [ordered]@{ role = 'assistant'; stop_reason = 'end_turn'
                content = @([ordered]@{ type = 'text'; text = 'Running in the background.' }) } }) $MinutesAgo
}
function Add-ChatNotification([string]$TaskId, [double]$MinutesAgo) {
    Add-ChatRecord $pW1 ([ordered]@{ type = 'user'; origin = @{ kind = 'task-notification' }
            message = [ordered]@{ role = 'user'; content = "<task-notification>`n<task-id>$TaskId</task-id>`n<status>completed</status>`n<summary>finished</summary>`n</task-notification>" } }) $MinutesAgo
    Add-ChatRecord $pW1 ([ordered]@{ type = 'assistant'; message = [ordered]@{ role = 'assistant'; stop_reason = 'end_turn'
                content = @([ordered]@{ type = 'text'; text = 'Done.' }) } }) $MinutesAgo
}
function Set-Quiet { (Get-Item -LiteralPath $pW1).LastWriteTime = (Get-Date).AddMinutes(-2) }   # past the 60 s layer
function Set-Live([string]$Status = 'idle', [double]$StartedMinutesAgo = 60) {
    $at = [DateTimeOffset]::UtcNow.AddMinutes(-$StartedMinutesAgo).ToUnixTimeMilliseconds()
    $env:FAKE_AGENTS = '[{"pid":1,"sessionId":"' + $idW1 + '","kind":"interactive","status":"' + $Status + '","startedAt":' + $at + '}]'
}

Remove-Item env:FAKE_AGENTS -EA SilentlyContinue
Check 'a project whose chats have all finished is idle' ((Test-ChatIdle -Cwd $projW) -eq $true)
Set-Live 'busy'
Check 'a chat Claude calls busy is active, though its transcript reads finished' ((Test-ChatIdle -Cwd $projW) -eq $false)
Set-Live 'waiting'
Check 'and so is one waiting on a permission prompt' ((Test-ChatIdle -Cwd $projW) -eq $false)

Add-ChatLaunch 'Workflow' ([ordered]@{ status = 'async_launched'; taskId = 'wtask0001'; taskType = 'local_workflow'; workflowName = 'review'; runId = 'wf_test-0001' }) 30
Set-Quiet
Set-Live 'idle'
Check 'a workflow still running after its turn ended keeps the chat active' ((Test-ChatIdle -Cwd $projW) -eq $false -and (Test-ChatTranscriptBusy $pW1) -ne $true)
Remove-Item env:FAKE_AGENTS
Check 'with the chat''s process gone, its workflow is gone too' ((Test-ChatIdle -Cwd $projW) -eq $true)
Set-Live 'idle' 10
Check 'one started before the chat was last opened died with the old process' ((Test-ChatIdle -Cwd $projW) -eq $true)
Add-ChatNotification 'wtask0001' 20
Set-Quiet
Set-Live 'idle'
Check 'its task-notification ends it' ((Test-ChatIdle -Cwd $projW) -eq $true)

Add-ChatLaunch 'Agent' ([ordered]@{ isAsync = $true; status = 'async_launched'; agentId = 'aagent0001'; description = 'map it' }) 15
Set-Quiet
Check 'a background agent keeps it active' ((Test-ChatIdle -Cwd $projW) -eq $false)
Add-ChatNotification 'aagent0001' 12
Set-Quiet
$quiet = (Test-ChatIdle -Cwd $projW) -eq $true
Add-ChatLaunch 'SendMessage' ([ordered]@{ success = $true; message = 'Resuming agent aagent0'; resumedAgentId = 'aagent0001' }) 10
Set-Quiet
Check 'until it reports; SendMessage waking it makes it active again' ($quiet -and (Test-ChatIdle -Cwd $projW) -eq $false)
Add-ChatNotification 'aagent0001' 8
Add-ChatLaunch 'Bash' ([ordered]@{ stdout = ''; stderr = ''; interrupted = $false; backgroundTaskId = 'bshell0001' }) 5
Set-Quiet
Check 'a background shell does not count - it may be a server that never ends' ((Test-ChatIdle -Cwd $projW) -eq $true)
# the chat a queued run just wrote reads live for a minute; that alone must
# not stop its window reloading by itself
(Get-Item -LiteralPath $pW1).LastWriteTime = Get-Date
Check 'a chat written this minute is live - unless it is the one the run wrote' ((Test-ChatIdle -Cwd $projW) -eq $false -and (Test-ChatIdle -Cwd $projW -Except $pW1) -eq $true)
# but what Claude says of that chat's own open process still counts: after
# the run it can only be a window's, and that may be mid-answer
Set-Live 'busy'
Check 'the run''s own chat busy in a window still counts' ((Test-ChatIdle -Cwd $projW -Except $pW1) -eq $false)
Remove-Item env:FAKE_AGENTS
# a chat written minutes ago is someone's, at the PC or from the phone
$pW2 = Join-Path (Join-Path (Join-Path $claudeHome 'projects') (Get-Slug $projW)) "$idW2.jsonl"
$w2Was = (Get-Item -LiteralPath $pW2).LastWriteTime
(Get-Item -LiteralPath $pW2).LastWriteTime = (Get-Date).AddMinutes(-3)
Check 'a neighbour written 3 min ago is live over quietMinutes, not over one minute' ((Test-ChatIdle -Cwd $projW -Except $pW1 -Seconds 300) -eq $false -and (Test-ChatIdle -Cwd $projW -Except $pW1) -eq $true)
(Get-Item -LiteralPath $pW2).LastWriteTime = $w2Was
# the common case: a folder with one chat, the one the run wrote
$projOne = Join-Path $work 'projOne'
$null = New-Item -ItemType Directory -Path $projOne -Force
$pOne = New-FakeChat $projOne 'cdcdcdcd-cdcd-4cdc-8cdc-cdcdcdcdcdcd' 'The only chat here' 1 @('hello')
$null = @(Sync-ChatIndex)
(Get-Item -LiteralPath $pOne).LastWriteTime = Get-Date
Check 'a folder whose only chat is the one the run wrote is idle, not unjudged' ((Test-ChatIdle -Cwd $projOne -Except $pOne) -eq $true)
Set-Quiet
# and end to end: a queued run into that chat, open and idle in a window,
# with nobody at the PC - the one case the window reloads by itself
$jw = New-TestJob 'Workflow host chat' 'one more pass'
Set-Live 'idle'
(Get-Item -LiteralPath $pW1).LastWriteTime = Get-Date
Invoke-ChatqJob (New-ChatqWatchState) (Find-ChatqJob $jw.id)
$rqW = [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json
Check 'a run into a quiet folder asks for the reload it may take by itself' ($rqW.kind -eq 'ran' -and $rqW.away -eq $true -and $rqW.busy -eq $false) "$($rqW.kind) away=$($rqW.away) busy=$($rqW.busy)"
Set-Quiet

# the request the window reads carries the verdict. Write-ChatGhostAdvice
# speaks only while a VS Code window is up, so one is made to look up.
function Get-Process {
    [CmdletBinding()] param([string[]]$Name, [int[]]$Id)
    if ($Name) { return [pscustomobject]@{ Name = 'Code' } }
    Microsoft.PowerShell.Management\Get-Process @PSBoundParameters
}
Push-Location -LiteralPath $projW
Set-Live 'busy'
Write-ChatGhostAdvice -Title 'Gone chat' *> $null
$rqBusy = [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json
Set-Live 'idle'
Write-ChatGhostAdvice -Title 'Gone chat' *> $null
$rqIdle = [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json
Pop-Location
Remove-Item function:Get-Process
Remove-Item env:FAKE_AGENTS
Check 'the reload request says whether a chat was working' ($rqBusy.busy -eq $true -and $rqIdle.busy -eq $false -and $rqBusy.kind -eq 'deleted') "$($rqBusy.busy) $($rqIdle.busy)"

Section 'status and alerts'
Write-ChatqBoard
$board = [System.IO.File]::ReadAllText($script:ChatqBoardPath, $utf8)
Check 'board folds each prompt away' ($board -match '<details><summary>' -and $board -match 'second half please')
Check 'Hangul counts two cells' ((Get-ChatCells $tSel) -eq 4)
Check 'cells clip on a wide character' ((Get-ChatCells (Format-ChatCell "$tSel$tSel$tSel" 5)) -eq 5)
$url = Get-ChatqJoinUrl 'k' 'group.phone' 'chatq x' ($tSel * 400) 1
Check 'Join URL fits and targets the group' ($url.Length -le 1900 -and $url -match 'deviceId=group\.phone') $url.Length
$url = Get-ChatqJoinUrl 'k' 'Pixel 8' 't' 'hi' 0
Check 'a device name goes as deviceNames' ($url -match 'deviceNames=Pixel%208')
$e = Get-ChatqExcerpt ("a`n`n" + ('word ' * 200)) 300
Check 'excerpt stays within 300' ($e.Length -le 300) $e.Length

Section 'overlay'
# Nothing reaches the network or the real process list: a stand-in for the
# usage endpoint, and one for "is that process still the session".
$script:OvFetches = 0
$liveJson = '{"five_hour":{"utilization":42.0,"resets_at":"' + $now.AddMinutes(90).ToString('o') + '"},"limits":[' +
'{"kind":"session","group":"session","percent":42,"severity":"normal","resets_at":"' + $now.AddMinutes(90).ToString('o') + '","scope":null},' +
'{"kind":"weekly_all","group":"weekly","percent":77,"severity":"warning","resets_at":"' + $now.AddDays(3).ToString('o') + '","scope":null},' +
'{"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Opus"}}},' +
'{"kind":"weekly_scoped","group":"weekly","percent":5,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Fable"}}}]}'
$script:ChatOverlayUsageSeam = { $script:OvFetches++; @{ Ok = $true; Status = 200; Windows = @(ConvertFrom-ChatqUtilization ($liveJson | ConvertFrom-Json)) } }
$script:ChatqAliveSeam = { param($e) $e.Pid -ne 444 }

# transcripts written the way Claude Code writes them: a last-prompt and an
# ai-title record every turn, then a few more records after them
$projO = Join-Path $work 'projO'
$null = New-Item -ItemType Directory -Path $projO -Force
function New-OverlayChat([string]$Id, [string[]]$Lines, [string]$Proj = $projO) {
    $dir = Join-Path (Join-Path $claudeHome 'projects') (Get-Slug $Proj)
    $null = New-Item -ItemType Directory -Path $dir -Force
    $path = Join-Path $dir "$Id.jsonl"
    [System.IO.File]::WriteAllText($path, ($Lines -join "`n") + "`n", $utf8)
    return $path
}
function OvUser([string]$Text) { [ordered]@{ type = 'user'; message = [ordered]@{ role = 'user'; content = $Text }; uuid = [guid]::NewGuid().ToString() } | ConvertTo-Json -Compress -Depth 5 }
function OvReply { '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}' }
function OvLast([string]$Text) { [ordered]@{ type = 'last-prompt'; lastPrompt = $Text; sessionId = 'x' } | ConvertTo-Json -Compress }
function OvTitle([string]$Text) { [ordered]@{ type = 'ai-title'; aiTitle = $Text; sessionId = 'x' } | ConvertTo-Json -Compress }
function OvTail { '{"type":"system","subtype":"turn_duration","durationMs":1234}' }
function OvPad([int]$Bytes) { '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"' + ('y' * $Bytes) + '"}]}}' }
$idO1 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a01'
$idO2 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a02'
$idO3 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a03'
$idO4 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a04'
$idO5 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a05'
$idO6 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a06'
$idO7 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a07'
$idO8 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a08'
$pO1 = New-OverlayChat $idO1 @((OvUser 'the very first ask'), (OvReply), (OvPad 3000000), (OvUser 'fix the loader'), (OvReply), (OvLast 'fix the loader'), (OvTitle 'Loader fixes'), (OvTail), (OvTail), (OvTail))
$pO2 = New-OverlayChat $idO2 @((OvUser 'a prompt from before the pad'), (OvReply), (OvPad 3000000), (OvTitle 'Deep chat'), (OvTail))
$pO3 = New-OverlayChat $idO3 @((OvUser 'the real ask'), (OvReply), (OvLast '<command-name>/compact</command-name>'), (OvTitle 'Noisy chat'), (OvTail))
$tCustom = "$tSel custom name"
$pO4 = New-OverlayChat $idO4 @((OvUser 'rename me'), (OvReply), (OvLast 'rename me'), (OvTitle 'Auto title'),
    ([ordered]@{ type = 'custom-title'; customTitle = $tCustom; sessionId = $idO4 } | ConvertTo-Json -Compress), (OvTail))

$script:ChatOverlayBytesRead = 0
$r = Find-ChatTailRecords $pO1
Check 'the newest prompt and title come from the last 256 KB of a 3 MB chat' ($r.Prompt -eq 'fix the loader' -and $r.PromptKind -eq 'last' -and $r.AiTitle -eq 'Loader fixes' -and $script:ChatOverlayBytesRead -le 262144) "$($r.Prompt) / $($r.AiTitle) / $($script:ChatOverlayBytesRead) bytes"
$r = Find-ChatTailRecords $pO2
Check 'with no record after a 3 MB line, it reads back past it' ($r.Prompt -eq 'a prompt from before the pad' -and $r.PromptKind -eq 'user' -and $r.AiTitle -eq 'Deep chat') "$($r.Prompt) / $($r.AiTitle)"
$r = Find-ChatTailRecords $pO2 -Budget 1MB
Check 'a budget stops it, keeping the title it found' (-not $r.Prompt -and $r.AiTitle -eq 'Deep chat' -and $r.Scanned -le 1MB + 262144) "$($r.Prompt) / $($r.Scanned)"
$r = Find-ChatTailRecords $pO3
Check 'a last-prompt that is machinery falls back to the real prompt' ($r.Prompt -eq 'the real ask') $r.Prompt
# a Hangul prompt cut by the first block's edge one byte into a character
$hg = (U '\uD55C\uAE00') * 300
$lead = '{"type":"last-prompt","lastPrompt":"'
$lpLine = $lead + $hg + '","sessionId":"x"}'
$ttLine = OvTitle 'Boundary'
$fill = 262144 - ($utf8.GetByteCount($lpLine) + 1 - ($utf8.GetByteCount($lead) + 1)) - ($utf8.GetByteCount($ttLine) + 1)
$padLine = '{"type":"system","pad":"' + ('z' * ($fill - 27)) + '"}'
$pO5 = New-OverlayChat $idO5 @((OvUser 'earlier'), (OvReply), $lpLine, $ttLine, $padLine)
$r = Find-ChatTailRecords $pO5
Check 'a UTF-8 character cut by a block edge is put back together' ($r.Prompt -eq $hg -and $r.AiTitle -eq 'Boundary' -and $r.Scanned -gt 262144) "$($r.Prompt.Length) chars, $($r.Scanned) bytes"

# a slash command, the way /compact goes: taken off the queue with no record
# while it runs, then written after the fact - and the last-prompt records
# after it go on naming the prompt before. Written by hand: 5.1's
# ConvertTo-Json would escape the angle brackets Claude Code writes as is.
function OvQueue([string]$Op, [datetime]$At) { '{"type":"queue-operation","operation":"' + $Op + '","timestamp":"' + $At.ToUniversalTime().ToString('o') + '","sessionId":"x"}' }
function OvStamp($At) { if ($At) { ',"timestamp":"' + ([datetime]$At).ToUniversalTime().ToString('o') + '"' } else { '' } }
function OvCommand([string]$Name, [string]$Rest = '', $At = $null) { '{"type":"user","message":{"role":"user","content":"<command-name>/' + $Name + '</command-name>\n            <command-message>' + $Name + '</command-message>\n            <command-args>' + $Rest + '</command-args>"},"uuid":"' + [guid]::NewGuid() + '"' + (OvStamp $At) + '}' }
function OvUserAt([string]$Text, $At) { '{"type":"user","message":{"role":"user","content":"' + $Text + '"},"uuid":"' + [guid]::NewGuid() + '"' + (OvStamp $At) + '}' }
$idO9 = '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a09'
$tq = (Get-Date).AddSeconds(-40)
$pO9 = New-OverlayChat $idO9 @((OvUser 'continue'), (OvReply), (OvLast 'continue'), (OvTitle 'Compacting chat'), (OvTail), (OvQueue 'enqueue' $tq), (OvQueue 'dequeue' $tq))
$r = Find-ChatTailRecords $pO9
Check 'while a command runs, what it took off the queue is marked pending' ($r.Prompt -eq 'continue' -and $r.Pending -and [Math]::Abs($r.Pending - [DateTimeOffset]::new($tq).ToUnixTimeMilliseconds()) -lt 1000) "$($r.Prompt) / $($r.Pending)"
$cx9 = New-ChatOverlayContext
$s9 = [pscustomobject]@{ SessionId = $idO9; Cwd = $projO }
Update-ChatOverlayText $cx9 $s9
$after = @((OvLast 'continue'), (OvTitle 'Compacting chat'), '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}',
    '{"type":"user","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"This session is being continued from a previous conversation."}}',
    '{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>Caveat: the messages below were generated by the user</local-command-caveat>"}}',
    (OvCommand 'compact' '' $tq), '{"type":"user","message":{"role":"user","content":"<local-command-stdout>Compacted </local-command-stdout>"}}',
    (OvLast 'continue'), (OvTitle 'Compacting chat'), (OvTail), ('{"type":"system","pad":"' + ('z' * 100000) + '"}'))
[System.IO.File]::AppendAllText($pO9, (($after -join "`n") + "`n"), $utf8)
$r = Find-ChatTailRecords $pO9
Check 'once it ends, the command is the newest thing sent - not the summary, not the prompt before' ($r.Prompt -eq '/compact' -and $r.PromptKind -eq 'command' -and -not $r.Pending) "$($r.Prompt) / $($r.PromptKind) / $($r.Pending)"
Update-ChatOverlayText $cx9 $s9
# 100 KB on, the command is outside what the next read overlaps
[System.IO.File]::AppendAllText($pO9, (((OvLast 'continue'), (OvTail)) -join "`n") + "`n", $utf8)
$script:ChatOverlayBytesRead = 0
Update-ChatOverlayText $cx9 $s9
Check 'and stays so while only the old last-prompt is written again' ($cx9.Text[$idO9].Prompt -eq '/compact' -and -not $cx9.Text[$idO9].Pending -and $script:ChatOverlayBytesRead -lt 70000) "$($cx9.Text[$idO9].Prompt) / $($script:ChatOverlayBytesRead)"
# the same words as the prompt before, typed again: newer by its timestamp
[System.IO.File]::AppendAllText($pO9, (((OvUserAt 'continue' (Get-Date)), (OvReply), (OvLast 'continue'), (OvTail)) -join "`n") + "`n", $utf8)
Update-ChatOverlayText $cx9 $s9
Check 'the prompt before, typed again, takes the command''s place' ($cx9.Text[$idO9].Prompt -eq 'continue' -and $cx9.Text[$idO9].PromptKind -ne 'command') "$($cx9.Text[$idO9].Prompt) / $($cx9.Text[$idO9].PromptKind)"
[System.IO.File]::AppendAllText($pO9, (((OvUser 'next ask'), (OvReply), (OvLast 'next ask'), (OvTail)) -join "`n") + "`n", $utf8)
Update-ChatOverlayText $cx9 $s9
Check 'until a prompt is typed after it' ($cx9.Text[$idO9].Prompt -eq 'next ask') $cx9.Text[$idO9].Prompt
$pO10 = New-OverlayChat '0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a10' @((OvUser 'first'), (OvCommand 'model' 'opus[1m]'), (OvUser 'after the switch'), (OvReply), (OvLast 'after the switch'), (OvTitle 'Switched'), (OvTail))
$r = Find-ChatTailRecords $pO10
Check 'a prompt after a command wins, arguments read with the command' ($r.Prompt -eq 'after the switch' -and $r.After -and (Read-ClaudeSlashCommand (OvCommand 'model' 'opus[1m]')) -eq '/model opus[1m]') "$($r.Prompt) / $($r.After)"
Check 'a skill the model loads is no command typed' ($null -eq (Read-ClaudeSlashCommand '{"type":"user","message":{"role":"user","content":"<command-message>workflow-authoring</command-message>\n<command-name>workflow-authoring</command-name>"}}'))
$pend = @{ Path = 'x'; AiTitle = 't'; Prompt = 'continue'; PromptKind = 'last'; Pending = [DateTimeOffset]::new((Get-Date).AddSeconds(-30)).ToUnixTimeMilliseconds() }
$mkS = { param($st) [pscustomobject]@{ SessionId = 'p1'; Pid = 1; Status = $st; Cwd = 'C:\p\one'; StatusUpdatedAt = 1 } }
$rb = @(Get-ChatOverlayRows -Sessions @(& $mkS 'busy') -Texts @{ p1 = $pend })[0]
$ri = @(Get-ChatOverlayRows -Sessions @(& $mkS 'idle') -Texts @{ p1 = $pend })[0]
Check 'a chat working on a command not yet written says so, not the prompt before' ($rb.prompt -eq $script:ChatOverlayPendingText -and $rb.promptKind -eq 'pending' -and $ri.prompt -eq 'continue') "$($rb.prompt) / $($ri.prompt)"

# the registry: four sessions and a dead one, and a .key locked the way a
# live session holds it - reading it would throw
$sessDir = Join-Path $claudeHome 'sessions'
$null = New-Item -ItemType Directory -Path $sessDir -Force
$nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function Set-OvSession([int]$ProcId, [string]$Sid, [string]$Status, [double]$MinutesAgo, $WaitingFor = $null, [string]$Name = 'derived-name', [string]$Kind = 'interactive') {
    $o = [ordered]@{ pid = $ProcId; sessionId = $Sid; cwd = $projO; startedAt = $nowMs - 3600000; procStart = '134346197461820071'; kind = $Kind
        entrypoint = 'claude-vscode'; pidDomain = "win32:$([Environment]::MachineName)"; name = $Name; status = $Status
        updatedAt = $nowMs - [int64]($MinutesAgo * 60000); statusUpdatedAt = $nowMs - [int64]($MinutesAgo * 60000) }
    if ($WaitingFor) { $o.waitingFor = $WaitingFor }
    [System.IO.File]::WriteAllText((Join-Path $sessDir "$ProcId.json"), ($o | ConvertTo-Json -Compress), $utf8)
}
Set-OvSession 111 $idO1 'waiting' 5 'permission'
Set-OvSession 112 $idO1 'idle' 40
Set-OvSession 222 $idO4 'busy' 1
Set-OvSession 333 $idO3 'idle' 30
Set-OvSession 444 $idO2 'busy' 2
Set-OvSession 555 $idO6 'busy' 2 $null 'fresh-chat-1a'
Set-OvSession 666 $idO7 'idle' 3
Set-OvSession 777 $idO8 'busy' 1 $null 'x' 'print'
$keyFile = Join-Path $sessDir '111.0fb15029164cbeb453ceb405db09b1caeff7424a77491bfef6e933a8e0cc3172.key'
[System.IO.File]::WriteAllText($keyFile, 'secret', $utf8)
$keyLock = [System.IO.File]::Open($keyFile, 'Open', 'ReadWrite', 'None')
try {
    $reg = @(Read-ChatqSessionRegistry $sessDir @{})
    $ctx = New-ChatOverlayContext
    $snap = Invoke-ChatOverlayCycle $ctx -Peek
}
finally { $keyLock.Dispose() }
Check 'the registry reads <pid>.json only, never the .key' ($reg.Count -eq 8 -and -not $snap.header.error) "$($reg.Count) $($snap.header.error)"
$row = { param($id) @($snap.rows | Where-Object { $_.sessionId -eq $id -and $_.kind -eq 'session' })[0] }
$r1 = & $row $idO1
Check 'a chat open in two windows is one row, at its more urgent state' ($r1 -and $r1.status -eq 'waiting' -and @($r1.pids).Count -eq 2 -and $r1.rank -eq 0) "$($r1.status) $(@($r1.pids) -join ',')"
Check 'its row: project, title, newest prompt, what it waits on' ($r1.project -eq 'projO' -and $r1.title -eq 'Loader fixes' -and $r1.prompt -eq 'fix the loader' -and $r1.stateText -like 'permission *') "$($r1.project) | $($r1.title) | $($r1.prompt) | $($r1.stateText)"
Check 'a rename wins over the generated title' ((& $row $idO4).title -eq $tCustom) (& $row $idO4).title
Check 'a registry entry whose process is gone has no row' (-not (& $row $idO2))
Check 'a working chat with no transcript yet shows the registry name' ((& $row $idO6).title -eq 'fresh-chat-1a')
Check 'an idle one with none - a new chat tab - has no row' (-not (& $row $idO7))
Check 'chatq''s own claude -p runs are not chats' (-not (& $row $idO8))
$ranks = @($snap.rows | ForEach-Object { [int]$_.rank })
Check 'rows run most urgent first' ((($ranks | Sort-Object) -join ',') -eq ($ranks -join ',')) ($ranks -join ',')
Check 'the snapshot counts what the rows show' ($snap.counts.waiting -eq 1 -and $snap.counts.busy -eq 2 -and $snap.counts.idle -eq 1) ($snap.counts | ConvertTo-Json -Compress)
$u = @($snap.header.usage | Where-Object { $_.provider -eq 'Claude' })[0]
Check 'usage live at the top: 5h, week, and one model''s week once used' ($u.source -eq 'live' -and (@($u.windows | ForEach-Object { "$($_.label) $($_.percent)" }) -join ',') -eq '5h 42,week 77,Fable week 5') (@($u.windows | ForEach-Object { "$($_.label) $($_.percent)" }) -join ',')
Check 'with the server''s own colour for each window' (@($u.windows)[1].severity -eq 'warning' -and @($u.windows)[0].resetsAt -gt $nowMs)
Check 'config in the snapshot is the overlay''s alone' ((@($snap.config.PSObject.Properties.Name) -notcontains 'join') -and (@($snap.config.PSObject.Properties.Name) -contains 'hotkey'))
$fetched = $script:OvFetches
$null = Invoke-ChatOverlayCycle $ctx -Peek
Check 'the endpoint is not asked again on the next pass' ($script:OvFetches -eq $fetched) "$fetched -> $($script:OvFetches)"
$ctx.Live.Windows[0].ResetsAt = (Get-Date).AddSeconds(-10)
$ctx.Live.At = (Get-Date).AddMinutes(-2)
$gone = ConvertTo-ChatOverlayUsage 'Claude' 'live' $ctx.Live (Get-Date) $null @{}
$null = Invoke-ChatOverlayCycle $ctx -Peek
Check 'a window whose reset passed reads empty, and is asked about at once' (@($gone.windows)[0].percent -eq 0 -and $null -eq @($gone.windows)[0].resetsAt -and $script:OvFetches -eq $fetched + 1) "$fetched -> $($script:OvFetches)"
# two traps of the same kind: an if that yields an empty array assigns $null
$cq = New-ChatOverlayContext
$null = Invoke-ChatOverlayCycle $cq
$sq1 = Invoke-ChatOverlayCycle $cq
Check 'passes with no command in them queue no command' ($cq.Commands.Count -eq 0 -and @($sq1.commands).Count -eq 0) "$($cq.Commands.Count)"
$cxWas = $script:ChatCodexHome
$script:ChatCodexHome = Join-Path $sb 'no-codex-here'
$un = try { @(Update-ChatOverlayUsage (New-ChatOverlayContext) $true) } catch { "threw: $($_.Exception.Message)" }
$script:ChatCodexHome = $cxWas
Check 'a machine with no Codex at all still gets Claude''s usage' (@($un | Where-Object { $_.provider -eq 'Claude' }).Count -eq 1 -and -not @($un | Where-Object { $_.provider -eq 'Codex' }).Count) "$un"

# the transcript grew: only the new part is read
[System.IO.File]::AppendAllText($pO1, ((@((OvUser 'now the tests'), (OvReply), (OvLast 'now the tests'), (OvTitle 'Loader fixes and tests'), (OvTail)) -join "`n") + "`n"), $utf8)
$script:ChatOverlayBytesRead = 0
$snap = Invoke-ChatOverlayCycle $ctx -Peek
$r1 = & $row $idO1
Check 'a transcript that grew is read from where it was, no further' ($r1.prompt -eq 'now the tests' -and $r1.title -eq 'Loader fixes and tests' -and $script:ChatOverlayBytesRead -lt 70000) "$($r1.prompt) | $($r1.title) | $($script:ChatOverlayBytesRead)"
Remove-Item -LiteralPath (Join-Path $sessDir '112.json')
$ctx.AliveAt = [datetime]::MinValue
$snap = Invoke-ChatOverlayCycle $ctx -Peek
Check 'a window closing leaves the chat''s other one' (@((& $row $idO1).pids).Count -eq 1)

# the watcher's own reader of the registry, when claude agents cannot run
$was = $env:CHATQ_CLAUDE
$env:CHATQ_CLAUDE = Join-Path $sb 'no-such-claude.exe'
$liveS = @(Get-ChatqLiveSessions $claudeHome)
$env:CHATQ_CLAUDE = $was
$w1 = @($liveS | Where-Object { $_.SessionId -eq $idO1 })[0]
Check 'the watcher''s fallback reads the same registry, waitingFor and all' ($w1 -and $w1.WaitingFor -eq 'permission' -and -not @($liveS | Where-Object { $_.SessionId -eq $idO2 })) "$(@($liveS).Count) $($w1.WaitingFor)"

# the same session test, against a real process
$node = Get-Command node -CommandType Application -EA SilentlyContinue | Select-Object -First 1
if ($node) {
    $script:ChatqAliveSeam = $null
    $np = Start-Process -FilePath $node.Source -ArgumentList '-e', '"setTimeout(function () {}, 60000)"' -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 800
    $np.Refresh()
    $ft = $np.StartTime.ToFileTimeUtc()
    $sa = [DateTimeOffset]::new($np.StartTime).ToUnixTimeMilliseconds()
    $mk = { param($ps, $at, $dom = "win32:$([Environment]::MachineName)") [pscustomobject]@{ Pid = $np.Id; ProcStart = $ps; StartedAt = $at; PidDomain = $dom } }
    Check 'a process that started when its entry says is that session' (Test-ChatqSessionAlive (& $mk "$ft" $sa))
    Check 'procStart an hour off is some other process' (-not (Test-ChatqSessionAlive (& $mk "$($ft - 36000000000)" $sa)))
    Check 'so is one started long after the session did - a reused pid' (-not (Test-ChatqSessionAlive (& $mk $null ($sa - 3600000))))
    Check 'a macOS-style date procStart is not held against it' (Test-ChatqSessionAlive (& $mk 'Tue Sep 23 10:00:00 2026' $sa))
    Check 'nor is another machine''s entry this one' (-not (Test-ChatqSessionAlive (& $mk "$ft" $sa 'win32:some-other-host')))
    Stop-Process -Id $np.Id -Force -EA SilentlyContinue
    $script:ChatqAliveSeam = { param($e) $e.Pid -ne 444 }
}
else { Write-Host '  skip  real-process session checks - no node here' -ForegroundColor Yellow }

# merging and order, on the pure function
$tnow = Get-Date
$ago = { param($m) [DateTimeOffset]::new($tnow.AddMinutes(-$m)).ToUnixTimeMilliseconds() }
$S = @(
    [pscustomobject]@{ SessionId = 'w-old'; Pid = 1; Status = 'waiting'; Cwd = 'C:\p\one'; StatusUpdatedAt = (& $ago 30) }
    [pscustomobject]@{ SessionId = 'w-new'; Pid = 2; Status = 'waiting'; Cwd = 'C:\p\two'; StatusUpdatedAt = (& $ago 5) }
    [pscustomobject]@{ SessionId = 'b-old'; Pid = 3; Status = 'busy'; Cwd = 'C:\p\three'; StatusUpdatedAt = (& $ago 20) }
    [pscustomobject]@{ SessionId = 'b-new'; Pid = 4; Status = 'busy'; Cwd = 'C:\p\four'; StatusUpdatedAt = (& $ago 2) }
    [pscustomobject]@{ SessionId = 'i-1'; Pid = 5; Status = 'idle'; Cwd = 'C:\p\five'; StatusUpdatedAt = (& $ago 60) }
    [pscustomobject]@{ SessionId = 'i-2'; Pid = 6; Status = 'idle'; Cwd = 'C:\p\six'; StatusUpdatedAt = (& $ago 10) }
    [pscustomobject]@{ SessionId = 'i-2'; Pid = 7; Status = 'busy'; Cwd = 'C:\p\six'; StatusUpdatedAt = (& $ago 1) }
)
$T = @{}
foreach ($k in 'w-old', 'w-new', 'b-old', 'b-new', 'i-1', 'i-2') { $T[$k] = @{ Path = 'x'; AiTitle = "title $k"; Prompt = "prompt $k" } }
$stamp = { param($m) $tnow.AddMinutes(-$m).ToUniversalTime().ToString('o') }
$J = @(
    [pscustomobject]@{ First = 'for an open chat'; Job = [pscustomobject]@{ id = 'j1'; seq = 1; state = 'queued'; provider = 'claude'; sessionId = 'i-1'; title = 'title i-1'; cwd = 'C:\p\five'; createdAt = (& $stamp 50) } }
    [pscustomobject]@{ First = 'for a closed one'; Job = [pscustomobject]@{ id = 'j2'; seq = 2; state = 'queued'; provider = 'claude'; sessionId = 'closed-1'; title = 'Closed chat'; cwd = 'C:\p\seven'; createdAt = (& $stamp 40) } }
    [pscustomobject]@{ First = 'for codex'; Job = [pscustomobject]@{ id = 'j3'; seq = 3; state = 'queued'; provider = 'codex'; sessionId = 'cx'; title = 'Codex chat'; cwd = 'C:\p\eight'; createdAt = (& $stamp 30) } }
    [pscustomobject]@{ First = 'parked'; Job = [pscustomobject]@{ id = 'j4'; seq = 4; state = 'needs-input'; provider = 'claude'; sessionId = 'closed-2'; title = 'Parked'; cwd = 'C:\p\nine'; endedAt = (& $stamp 15); result = [pscustomobject]@{ reason = 'asked to edit' } } }
    [pscustomobject]@{ First = 'running'; Job = [pscustomobject]@{ id = 'j5'; seq = 5; state = 'running'; provider = 'claude'; sessionId = 'closed-3'; title = 'Running one'; cwd = 'C:\p\ten'; startedAt = (& $stamp 3) } }
)
$R = @(Get-ChatOverlayRows -Sessions $S -Texts $T -Jobs $J -Eta @{ j1 = '17:10'; j2 = 'after #1'; j3 = 'next' } -Now $tnow)
$want = 's:w-old,j:j4,s:w-new,s:i-2,s:b-new,s:b-old,j:j5,s:i-1,j:j2,j:j3'
Check 'waiting oldest first, then working, running, idle newest first, queued in order' (($R.key -join ',') -eq $want) ($R.key -join ',')
$ri1 = @($R | Where-Object { $_.key -eq 's:i-1' })[0]
Check 'a prompt queued for an open chat rides on its row' ($ri1.job.seq -eq 1 -and $ri1.stateText -like '#1 sends 17:10*idle*' -and -not @($R | Where-Object { $_.key -eq 'j:j1' })) $ri1.stateText
$ri2 = @($R | Where-Object { $_.key -eq 's:i-2' })[0]
Check 'the second window''s state wins when it is the more urgent' ($ri2.status -eq 'busy' -and (@($ri2.pids) -join ',') -eq '6,7') "$($ri2.status) $(@($ri2.pids) -join ',')"
Check 'a job row says what it is and carries its first line' ((@($R | Where-Object { $_.key -eq 'j:j2' })[0].stateText -eq '#2 after #1') -and (@($R | Where-Object { $_.key -eq 'j:j2' })[0].prompt -eq 'for a closed one'))
# cut off by the limit or a 529: an open idle chat takes the state, one not
# open gets a row, one a job is queued for leaves it to the job
$resetAt = $tnow.AddMinutes(90)
$C = @(
    [pscustomobject]@{ Id = 'i-1'; Title = 'title i-1'; Why = 'limit'; ResetsAt = $resetAt; At = $tnow.AddMinutes(-60); Cwd = 'C:\p\five' }
    [pscustomobject]@{ Id = 'b-new'; Title = 'title b-new'; Why = 'limit'; ResetsAt = $resetAt; At = $tnow.AddMinutes(-2); Cwd = 'C:\p\four' }
    [pscustomobject]@{ Id = 'gone-1'; Title = 'Stopped at the limit'; Why = 'limit'; ResetsAt = $resetAt; At = $tnow.AddMinutes(-30); Cwd = 'C:\p\eleven'; Path = 'C:\x.jsonl' }
    [pscustomobject]@{ Id = 'gone-2'; Title = 'Stopped by a 529'; Why = 'overloaded'; ResetsAt = $null; At = $tnow.AddMinutes(-20); Cwd = 'C:\p\twelve' }
    [pscustomobject]@{ Id = 'closed-1'; Title = 'Closed chat'; Why = 'limit'; ResetsAt = $resetAt; At = $tnow.AddMinutes(-45); Cwd = 'C:\p\seven' }
)
$S2 = @($S | Where-Object { $_.SessionId -ne 'i-1' }) + @([pscustomobject]@{ SessionId = 'i-3'; Pid = 8; Status = 'idle'; Cwd = 'C:\p\five'; StatusUpdatedAt = (& $ago 60) })
$C[0].Id = 'i-3'
$T['i-3'] = @{ Path = 'x'; AiTitle = 'title i-3'; Prompt = 'prompt i-3' }
$RC = @(Get-ChatOverlayRows -Sessions $S2 -Texts $T -Jobs $J -Eta @{ j1 = '17:10'; j2 = 'after #1'; j3 = 'next' } -Now $tnow -CutOff $C)
$r3 = @($RC | Where-Object { $_.key -eq 's:i-3' })[0]
$rg1 = @($RC | Where-Object { $_.key -eq 'c:gone-1' })[0]
$rg2 = @($RC | Where-Object { $_.key -eq 'c:gone-2' })[0]
$rbn = @($RC | Where-Object { $_.key -eq 's:b-new' })[0]
$firstCut = [array]::IndexOf(@($RC.key), 'c:gone-2')
Check 'cut off: an open idle chat says when the limit resets; a working one has moved on' (
    $r3.status -eq 'cutoff' -and $r3.rank -eq 0.5 -and $r3.stateText -eq "cut off - resets $($resetAt.ToString('HH:mm'))" -and $rbn.status -eq 'busy') "$($r3.status) $($r3.stateText) / $($rbn.status)"
Check 'one not open gets a row of its own - a 529 says what it waits on - and a queued continue replaces it' (
    $rg1.kind -eq 'cutoff' -and $rg1.project -eq 'eleven' -and $rg2.stateText -eq '529 - waits for Claude' -and -not @($RC | Where-Object { $_.key -eq 'c:closed-1' }) -and
    $firstCut -gt [array]::IndexOf(@($RC.key), 's:w-new') -and $firstCut -lt [array]::IndexOf(@($RC.key), 's:b-new')) ($RC.key -join ',')
Check 'and when the limit is over it says so' ((Format-ChatOverlayCutOff ([pscustomobject]@{ Why = 'limit'; ResetsAt = $tnow.AddMinutes(-5) }) $tnow) -eq 'cut off - limit over')
# the scan the overlay runs every minute reads a transcript again only once it moved
$cutCache = @{}
$script:ChatqCutOffReads = 0
$cut1 = @(Get-ChatqCutOffChats @() -Cache $cutCache)
$reads1 = $script:ChatqCutOffReads
$cut2 = @(Get-ChatqCutOffChats @() -Cache $cutCache)
$reads2 = $script:ChatqCutOffReads - $reads1
# the new chat the limit cut above: its limit record has no cwd of its own
$cutNl = @($cut1 | Where-Object { $_.Id -eq $nl.sessionId })[0]
Check 'the cut-off scan reads what moved and nothing else, and says where each chat ran' (
    $cut1.Count -ge 1 -and $cut2.Count -eq $cut1.Count -and $reads1 -ge 1 -and $reads2 -eq 0 -and $cutNl.Path -eq $nl.path -and $cutNl.Cwd -eq $newDir) "$($cut1.Count) chats, $reads1 then $reads2 reads, $($cutNl.Cwd)"
# one working now is neither read nor listed - and, forgotten by the cache,
# is read on the next pass that does not skip it
$r0 = $script:ChatqCutOffReads
$cutSkip = @(Get-ChatqCutOffChats @() -Cache $cutCache -Skip @($nl.sessionId))
$readsSkip = $script:ChatqCutOffReads - $r0
$null = @(Get-ChatqCutOffChats @() -Cache $cutCache)
# it moved on: read again, only it, and off the list
$okRec = [ordered]@{ type = 'assistant'; uuid = [guid]::NewGuid().ToString(); timestamp = (Get-Date).ToUniversalTime().ToString('o'); sessionId = $nl.sessionId
    message = [ordered]@{ model = 'claude-fake-1'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = 'carried on' }) } } | ConvertTo-Json -Compress -Depth 6
[System.IO.File]::AppendAllText($nl.path, $okRec + "`n", $utf8)
$r0 = $script:ChatqCutOffReads
$cutMoved = @(Get-ChatqCutOffChats @() -Cache $cutCache)
$readsMoved = $script:ChatqCutOffReads - $r0
Check 'one working is neither read nor listed; one that moved on is read once more, and leaves' (
    $readsSkip -eq 0 -and $cutSkip.Count -eq $cut1.Count - 1 -and -not @($cutSkip | Where-Object { $_.Id -eq $nl.sessionId }) -and
    $readsMoved -eq 1 -and $cutMoved.Count -eq $cut1.Count - 1 -and -not @($cutMoved | Where-Object { $_.Id -eq $nl.sessionId })) "skip: $readsSkip reads, $($cutSkip.Count); moved: $readsMoved reads, $($cutMoved.Count) of $($cut1.Count)"

# commands, the lock, and the handoffs
$script:ChatOverlayStopWaitMs = 400
$script:OvSpawned = 0
$script:ChatOverlaySpawn = { $script:OvSpawned++; $true }
Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
$ovLock = [System.IO.File]::Open($script:ChatOverlayLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    chatoverlay *> $null
    $cmds = [System.IO.File]::ReadAllText($script:ChatOverlayCmdPath)
    Check 'a running overlay is shown, never started twice' ($script:OvSpawned -eq 0 -and $cmds -match ' show\n') $cmds
    chatoverlay -Stop *> $null
    chatinstall *> $null
    chatuninstall *> $null
    $cmds = [System.IO.File]::ReadAllText($script:ChatOverlayCmdPath)
    Check '-Stop, chatinstall and chatuninstall each tell it' ($cmds -match ' stop\n' -and $cmds -match ' restart\n' -and ([regex]::Matches($cmds, ' stop\n')).Count -eq 2) ($cmds -replace "`n", ' | ')
}
finally { $ovLock.Dispose() }
[System.IO.File]::AppendAllText($script:ChatOverlayCmdPath, "$((Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')) hide`n", $utf8)
$verbs = @(Receive-ChatOverlayCommands)
Check 'commands are taken once, and a stale one is dropped' (($verbs -join ',') -eq 'show,stop,restart,stop' -and -not (Test-Path -LiteralPath $script:ChatOverlayCmdPath)) ($verbs -join ',')
Send-ChatOverlayCommand 'restart'
$why = Invoke-ChatOverlayCollectLoop (New-ChatOverlayContext) -IntervalMs 10 -MaxCycles 3
$why2 = Invoke-ChatOverlayCollectLoop (New-ChatOverlayContext) -IntervalMs 10 -MaxCycles 2
Check 'the collector loop ends on a restart, or after its passes' ($why -eq 'restart' -and $why2 -eq 'max') "$why $why2"
# chatconsole: a running overlay is told; else one starts with the console
# open - a command left for it would be swept away as it takes its lock
Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
$ovLock = [System.IO.File]::Open($script:ChatOverlayLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try { chatconsole *> $null; $cmdsC = [System.IO.File]::ReadAllText($script:ChatOverlayCmdPath) } finally { $ovLock.Dispose() }
Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
$script:OvSpawned = 0
chatconsole *> $null
$launchC = Get-ChatOverlayLaunch -Open console
Check 'chatconsole: a running overlay is told to open it; otherwise one starts with it open' (
    $cmdsC -match ' console\n' -and $script:OvSpawned -eq 1 -and $launchC.Command -like "*Start-ChatOverlayHost -Open 'console'*") "$cmdsC / $($script:OvSpawned)"
Check 'and the snapshot it saves has no BOM and keeps Hangul' ((Test-Path -LiteralPath $script:ChatOverlayPath) -and
    ([System.IO.File]::ReadAllBytes($script:ChatOverlayPath)[0] -eq [byte][char]'{') -and
    ([System.IO.File]::ReadAllText($script:ChatOverlayPath, $utf8).Contains($tCustom)))
$saved = [System.IO.File]::ReadAllText($script:ChatOverlayPath, $utf8) | ConvertFrom-Json
Check 'schema 1, times as epoch milliseconds' ($saved.schema -eq 1 -and [double]$saved.at -gt 1.7e12 -and @($saved.rows | Where-Object { $_.since -and [double]$_.since -gt 1.7e12 }).Count)
chatoverlay -Unlock *> $null
chatoverlay -Reset *> $null
chatoverlay -Collapse *> $null
$ost = Read-ChatOverlayState
chatoverlay -Expand *> $null
Check 'not running: -Unlock, -Reset and -Collapse wait in overlay-state.json' ((-not $ost.locked) -and $null -eq $ost.x -and $ost.collapsed -and -not (Read-ChatOverlayState).collapsed)
chatoverlay -Lock *> $null
chatoverlay -AutoStart on *> $null
Check '-AutoStart on is kept in config.json, and read at shell start' ((Get-ChatqConfig).overlay.autoStart -eq $true -and (Test-ChatOverlayAutoStart))
chatoverlay -AutoStart off *> $null
chatoverlay -Hotkey 'Ctrl+Hyper+Q' *> $null
Check 'a hotkey it cannot read is refused, not saved' ((Get-ChatOverlayConfig).hotkey -eq 'Ctrl+Alt+Shift+O')
$chkDefault = (Get-ChatOverlayConfig).consoleHotkey
chatoverlay -ConsoleHotkey none *> $null
$chkNone = (Get-ChatOverlayConfig).consoleHotkey
chatoverlay -ConsoleHotkey 'Ctrl+Hyper+Q' *> $null
Check 'the console''s hotkey: Ctrl+Alt+Shift+Q unless set, none for no key, nonsense refused' (
    $chkDefault -eq 'Ctrl+Alt+Shift+Q' -and $chkNone -eq 'none' -and (Get-ChatOverlayConfig).consoleHotkey -eq 'none') "$chkDefault $chkNone"
Set-ChatOverlayConfig @{ consoleHotkey = 'Ctrl+Alt+Shift+Q' }
chatoverlay -Theme light -Opacity 85 *> $null
$oc = Get-ChatOverlayConfig
chatoverlay -Opacity 5 *> $null
Check '-Theme and -Opacity are kept, a percent read as one, nonsense refused' ($oc.theme -eq 'light' -and $oc.opacity -eq 0.85 -and (Get-ChatOverlayConfig).opacity -eq 0.85) "$($oc.theme) $($oc.opacity)"
Set-ChatOverlayConfig @{ theme = 'purple' }
Check 'a theme it does not know draws dark' ((Get-ChatOverlayConfig).theme -eq 'dark')
Set-ChatOverlayConfig @{ theme = 'dark'; opacity = 0.94 }
$uvDefault = (Get-ChatOverlayConfig).usageView
chatoverlay -UsageView bars -CopilotUsage off *> $null
$uvSet = Get-ChatOverlayConfig
Set-ChatOverlayConfig @{ usageView = 'sideways' }
Check 'usage as lines unless -UsageView bars; -CopilotUsage off kept; a view it does not know draws lines' (
    $uvDefault -eq 'lines' -and $uvSet.usageView -eq 'bars' -and -not $uvSet.copilotUsage -and (Get-ChatOverlayConfig).usageView -eq 'lines') "$uvDefault $($uvSet.usageView) $($uvSet.copilotUsage)"
Set-ChatOverlayConfig @{ usageView = 'lines'; copilotUsage = $true }
$script:ChatOverlaySpawn = { $true }

# the pure parts
$hk = ConvertFrom-ChatOverlayHotkey 'Ctrl+Alt+Shift+O'
$hk2 = ConvertFrom-ChatOverlayHotkey 'ctrl+win+F9'
$bad = @('O', 'Ctrl+Alt', 'Ctrl+Hyper+O') | Where-Object { try { $null = ConvertFrom-ChatOverlayHotkey $_; $true } catch { $false } }
Check 'hotkeys: modifiers and key read, none is none, nonsense refused' ($hk.Mods -eq 7 -and $hk.Vk -eq 0x4F -and $hk2.Mods -eq 10 -and $hk2.Vk -eq 0x78 -and
    $null -eq (ConvertFrom-ChatOverlayHotkey 'none') -and -not $bad) "$($hk.Mods)/$($hk.Vk) $($hk2.Mods)/$($hk2.Vk) $bad"
$scr = @([pscustomobject]@{ X = 0; Y = 0; Width = 1920; Height = 1040; Primary = $true }, [pscustomobject]@{ X = 1920; Y = 0; Width = 1920; Height = 1040; Primary = $false })
$pl1 = Get-ChatOverlayPlacement 3000 100 380 260 $scr
$pl2 = Get-ChatOverlayPlacement 5000 100 380 260 $scr
$pl3 = Get-ChatOverlayPlacement $null $null 380 260 $scr
Check 'placement: kept on a screen that has it, else the main one''s top right' ((-not $pl1.Moved) -and $pl1.X -eq 3000 -and $pl2.Moved -and $pl2.X -eq 1524 -and $pl2.Y -eq 56 -and $pl3.X -eq 1524) "$($pl2.X),$($pl2.Y)"
$launch = Get-ChatOverlayLaunch
$decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($launch.Args[-1]))
Check 'launched as powershell.exe -STA, marked as the overlay' ($launch.Exe -like '*WindowsPowerShell*powershell.exe' -and $launch.Args -contains '-STA' -and
    $decoded -eq $launch.Command -and $decoded -like "*CHATQ_OVERLAY='1'*" -and $decoded -like '*Start-ChatOverlayHost*' -and $decoded -like "*$sb*") $decoded
$script:ChatOverlaySystemDarkSeam = { $true }
$tDark = Resolve-ChatOverlayTheme 'system'
$script:ChatOverlaySystemDarkSeam = { $false }
$tLight = Resolve-ChatOverlayTheme 'system'
$script:ChatOverlaySystemDarkSeam = $null
Check 'theme: system follows Windows'' own setting' ($tDark -eq 'dark' -and $tLight -eq 'light' -and (Resolve-ChatOverlayTheme 'light') -eq 'light' -and (Resolve-ChatOverlayTheme '') -eq 'dark')
Check 'both looks name every colour' (@($script:ChatOverlayPalettes.dark.Keys | Where-Object { -not $script:ChatOverlayPalettes.light.ContainsKey($_) }).Count -eq 0)
# the buttons' window on the panel's top edge: panel and size in screen pixels
$work = [pscustomobject]@{ X = 0; Y = 0; Width = 1920; Height = 1040 }
$cp1 = Get-ChatOverlayControlsPlacement @(1524, 200, 380, 400) @(136, 24) $work 4
$cp2 = Get-ChatOverlayControlsPlacement @(1524, 10, 380, 400) @(136, 24) $work 4
Check 'the buttons sit on the panel''s top edge, flush with its right, or under it with no room above' (
    $cp1.Side -eq 'above' -and $cp1.X -eq 1768 -and $cp1.Y -eq 172 -and $cp2.Side -eq 'below' -and $cp2.X -eq 1768 -and $cp2.Y -eq 414) "$($cp1.Side) $($cp1.X),$($cp1.Y) / $($cp2.Side) $($cp2.X),$($cp2.Y)"
$cp3 = Get-ChatOverlayControlsPlacement @(1700, 200, 380, 400) @(136, 24) $work 4
$cp4 = Get-ChatOverlayControlsPlacement @(-300, 200, 380, 400) @(136, 24) $work 4
$cp5 = Get-ChatOverlayControlsPlacement @(2400, 200, 380, 400) @(136, 24) ([pscustomobject]@{ X = 1920; Y = 0; Width = 1920; Height = 1040 }) 4
Check 'kept on the screen side to side, on a second screen too' ($cp3.X -eq 1784 -and $cp4.X -eq 0 -and $cp5.X -eq 2644 -and $cp5.Y -eq 172) "$($cp3.X) / $($cp4.X) / $($cp5.X),$($cp5.Y)"
# room above for the 30-pixel row of buttons, not for the 115-pixel box
$cp6 = Get-ChatOverlayControlsPlacement @(1524, 60, 380, 400) @(250, 115) $work 4 'above' 30
$cp7 = Get-ChatOverlayControlsPlacement @(1524, 10, 380, 400) @(250, 115) $work 4 'below' 30
Check 'the box opening keeps the buttons on their side, on the screen' ($cp6.Side -eq 'above' -and $cp6.Y -eq 0 -and $cp6.X -eq 1654 -and $cp7.Side -eq 'below' -and $cp7.Y -eq 414) "$($cp6.Side) $($cp6.X),$($cp6.Y) / $($cp7.Side) $($cp7.Y)"
# shown, on panel, on buttons, dragging, button held, ms resting on the panel, ms since over either
$sh = { param($s, $p, $c, $d, $dn, $r, $o) [bool](Get-ChatOverlayControlsShown $s $p $c $d $dn $r $o) }
Check 'the buttons come after the pointer rests on the panel, and stay while it is on either or a button is held' (
    -not (& $sh $false $true $false $false $false 120 0) -and (& $sh $false $true $false $false $false 360 0) -and
    (& $sh $true $false $true $false $false 0 0) -and (& $sh $true $false $false $false $true 0 5000) -and
    (& $sh $true $false $false $false $false 0 500) -and -not (& $sh $true $false $false $false $false 0 800) -and
    (& $sh $false $false $false $true $false 0 99999))
$bigSnap = [pscustomobject]@{ counts = [pscustomobject]@{ waiting = 12; needsInput = 3; busy = 40; running = 1; idle = 88; queued = 9 }; header = [pscustomobject]@{ usage = @() } }
Check 'the tray tooltip never reaches the 64 characters that throw' ((Format-ChatOverlayTooltip $bigSnap).Length -le 63) (Format-ChatOverlayTooltip $bigSnap)

# the console's pure parts
$wNow = ConvertFrom-ChatConsoleWhen 'now' ''
$wTurn = ConvertFrom-ChatConsoleWhen 'turn' ''
$wIn = ConvertFrom-ChatConsoleWhen 'in' '2h'
$wAtBad = ConvertFrom-ChatConsoleWhen 'at' 'soonish'
$wInNone = ConvertFrom-ChatConsoleWhen 'in' ' '
Check 'console When: now is first and looked at every 30 s, in turn is neither, at/in a time - or why not' (
    $wNow.First -and $wNow.SendNow -and -not $wNow.NotBefore -and -not $wTurn.First -and -not $wTurn.SendNow -and
    [Math]::Abs(($wIn.NotBefore - (Get-Date).AddHours(2)).TotalMinutes) -lt 1 -and $wAtBad.Error -like "'soonish' is not a time*" -and $wInNone.Error -like 'give a time*') "$($wAtBad.Error) / $($wInNone.Error)"
$chatsC = @(
    [pscustomobject]@{ Title = 'Card layout redesign'; Project = 'parser' }
    [pscustomobject]@{ Title = 'Rate limiter'; Project = 'api' }
    [pscustomobject]@{ Title = 'Release notes'; Project = 'parser' }
)
Check 'console search: every word, in the title or the project, any case; a cap' (
    @(Select-ChatConsoleChats $chatsC 'PARSER card').Count -eq 1 -and @(Select-ChatConsoleChats $chatsC 'parser').Count -eq 2 -and
    @(Select-ChatConsoleChats $chatsC '').Count -eq 3 -and @(Select-ChatConsoleChats $chatsC '' 2).Count -eq 2 -and -not @(Select-ChatConsoleChats $chatsC 'nothing').Count)
$pNow = [pscustomobject]@{ Error = $null; NotBefore = $null; First = $true; SendNow = $true }
$pTurn = [pscustomobject]@{ Error = $null; NotBefore = $null; First = $false; SendNow = $false }
$tn = Get-Date '2026-09-24T12:00:00'
$pv1 = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = $null } $pNow $null 3 $true $tn
$pv2 = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = 'busy' } $pNow ([pscustomobject]@{ Until = $tn.AddMinutes(59); Type = 'five_hour' }) 0 $false $tn
$pv3 = Get-ChatConsoleSendPreview @{ Kind = 'new'; Live = $null } $pTurn $null 2 $true $tn
$pv4 = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = 'idle' } $pNow ([pscustomobject]@{ Until = $tn; Type = 'overloaded' }) 0 $true $tn
$pv5 = Get-ChatConsoleSendPreview $null $pNow $null 0 $true $tn
Check 'console preview: what Send will do - soon, a limit, a busy chat, behind others, a new chat, a 529, the watcher' (
    $pv1 -eq 'sends within a few seconds' -and $pv2 -eq 'limited until 12:59 - sends 13:00 - that chat is working in VS Code - it goes once the chat is idle, looked at every 30 s - the watcher starts for it' -and
    $pv3 -like 'after the 2 queued ahead of it - a new chat*' -and $pv4 -like 'Claude is overloaded*open in VS Code*' -and $pv5 -like 'pick a chat*') "$pv1 | $pv2 | $pv3 | $pv4"
# a refused login is no limit: it says what the CLI said, not "limited until"
$pvL = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = $null } $pNow ([pscustomobject]@{ Until = $tn.AddMinutes(15); Type = 'login needed'; Why = 'login refused: OAuth token has expired. (401)' }) 0 $true $tn
$pvL2 = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = $null } $pNow ([pscustomobject]@{ Until = $tn.AddMinutes(15); Type = 'login needed'; Why = 'probe' }) 0 $true $tn
$pvP = Get-ChatConsoleSendPreview @{ Kind = 'chat'; Live = $null } $pNow ([pscustomobject]@{ Until = $tn.AddMinutes(10); Type = 'probe failed'; Why = 'no claude CLI found' }) 0 $true $tn
Check 'console preview: a refused login says what the CLI said, an older block says login refused, a failed probe when it looks again - never "limited until"' (
    $pvL -like 'login refused: OAuth token has expired. (401) - log in or check the subscription*' -and $pvL2 -like 'login refused - log in*' -and
    $pvP -eq 'the limit could not be checked - looked at again 12:10' -and "$pvL $pvL2 $pvP" -notmatch 'limited until') "$pvL | $pvL2 | $pvP"
# the limit the preview names, from what the collector holds - nothing read
$soon = (Get-Date).AddMinutes(40)
$later = (Get-Date).AddMinutes(95)
$bUsage = Get-ChatConsoleBlock @{ Ctx = @{ Blocks = @{}; CutOff = @() }; Snap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @(
                [pscustomobject]@{ provider = 'Claude'; windows = @([pscustomobject]@{ label = '5h'; limited = $true; resetsAt = ([DateTimeOffset]$soon).ToUnixTimeMilliseconds() }) }) } } } 'claude'
$bCut = Get-ChatConsoleBlock @{ Ctx = @{ Blocks = $null; CutOff = @(
            [pscustomobject]@{ Why = 'limit'; ResetsAt = $soon }, [pscustomobject]@{ Why = 'limit'; ResetsAt = $later }, [pscustomobject]@{ Why = 'overloaded'; ResetsAt = $null }) }
    Snap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @() } } } 'claude'
$bNone = Get-ChatConsoleBlock @{ Ctx = @{ Blocks = @{}; CutOff = @([pscustomobject]@{ Why = 'limit'; ResetsAt = $later }) }; Snap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @() } } } 'codex'
$bLogin = Get-ChatConsoleBlock @{ Ctx = @{ Blocks = @{ claude = [pscustomobject]@{ Until = $soon; Type = 'login needed'; Source = 'login refused: OAuth token has expired. (401)' } }; CutOff = @() }
    Snap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @() } } } 'claude'
Check 'console: the limit ahead from a usage window marked limited, else the latest reset of the chats it cut off; Codex not from Claude''s; the watcher''s block with its words' (
    [Math]::Abs(($bUsage.Until - $soon).TotalSeconds) -lt 1 -and $bUsage.Type -eq '5h' -and [Math]::Abs(($bCut.Until - $later).TotalSeconds) -lt 1 -and -not $bNone -and
    $bLogin.Type -eq 'login needed' -and $bLogin.Why -eq 'login refused: OAuth token has expired. (401)') "$($bUsage.Until) $($bCut.Until) $bNone $($bLogin.Why)"
$js1 = Get-ChatConsoleJobStatus ([pscustomobject]@{ state = 'queued' }) '13:01'
$js2 = Get-ChatConsoleJobStatus ([pscustomobject]@{ state = 'needs-input'; result = [pscustomobject]@{ reason = 'Edit denied' } }) $null
$js3 = Get-ChatConsoleJobStatus ([pscustomobject]@{ state = 'failed'; result = [pscustomobject]@{ reason = 'chat gone' } }) $null
Check 'console queue: each job says where it stands, in its colour' ($js1.Text -eq 'sends 13:01' -and $js1.Tone -eq 'queued' -and $js2.Text -eq 'needs you - Edit denied' -and $js2.Tone -eq 'waiting' -and $js3.Text -eq 'failed - chat gone' -and $js3.Tone -eq 'error') "$($js1.Text) | $($js2.Text) | $($js3.Text)"
$scrC = @([pscustomobject]@{ X = 0; Y = 0; Width = 1536; Height = 816; Primary = $true })
$plKeep = Get-ChatConsolePlacement ([pscustomobject]@{ x = 100; y = 80; w = 900; h = 600 }) $scrC
$plGone = Get-ChatConsolePlacement ([pscustomobject]@{ x = 4000; y = 80; w = 900; h = 600 }) $scrC
$plNew = Get-ChatConsolePlacement $null $scrC
Check 'console placement: where it was left while it shows, else the main screen''s middle' (
    $plKeep.X -eq 100 -and $plKeep.W -eq 900 -and $plGone.X -eq 278 -and $plGone.Y -eq 68 -and $plNew.W -eq 980 -and $plNew.H -eq 680) "$($plGone.X),$($plGone.Y) $($plNew.W)x$($plNew.H)"
$in90 = [DateTimeOffset]::Now.AddMinutes(90.5).ToUnixTimeMilliseconds()
Check 'reset countdowns' ((Format-ChatOverlayReset $in90) -eq '1h 30m' -and (Format-ChatOverlayReset ($nowMs - 1000)) -eq 'reset' -and
    (Format-ChatOverlayReset ([DateTimeOffset]::Now.AddDays(3).ToUnixTimeMilliseconds())) -match '^[A-Z][a-z]{2} \d\d:\d\d$') (Format-ChatOverlayReset $in90)

# the endpoint refusing: Claude Code's own cached figure, marked, and a wait
$cu = New-ChatOverlayContext
$script:ChatOverlayUsageSeam = { $script:OvFetches++; @{ Ok = $false; Status = 401; Why = 'the usage endpoint answered 401'; Auth = $true } }
$uu = @(Update-ChatOverlayUsage $cu $true)
$uc = @($uu | Where-Object { $_.provider -eq 'Claude' })[0]
Check 'refused for the login: the cached figure, and no asking for 10 minutes' ($uc.source -eq 'cache' -and $uc.why -like '*401*' -and $cu.HoldUntil -gt (Get-Date).AddMinutes(9)) "$($uc.source) $($uc.why) $($cu.HoldUntil)"
$cu = New-ChatOverlayContext
$script:ChatOverlayUsageSeam = { @{ Ok = $false; Status = 429; Why = 'the usage endpoint answered 429' } }
$null = Update-ChatOverlayUsage $cu $true
Check 'a 429 with no Retry-After backs off 5 minutes' ($cu.HoldUntil -gt (Get-Date).AddMinutes(4.5) -and $cu.HoldUntil -lt (Get-Date).AddMinutes(5.5) -and $cu.LiveWhy -like 'rate-limited - asking again at *') "$($cu.HoldUntil) $($cu.LiveWhy)"
Request-ChatOverlayUsageRefresh $cu
$tooSoon = $cu.HoldUntil -gt (Get-Date)
$cu.LiveTriedAt = (Get-Date).AddSeconds(-30)
Request-ChatOverlayUsageRefresh $cu
Check 'the refresh button asks at once after a guessed wait, but not twice in 20 s' ($tooSoon -and $cu.HoldUntil -le (Get-Date) -and $null -eq $cu.LiveTriedAt)
# what a click did, said on the panel - an answer that moves no figure
# otherwise looks like a click that did nothing
$script:ChatOverlayUsageSeam = { @{ Ok = $true; Status = 200; Windows = @([pscustomobject]@{ Label = '5h'; Percent = 39; ResetsAt = $null; Severity = 'normal' }) } }
$cq = New-ChatOverlayContext
$cq.LiveTriedAt = (Get-Date).AddMinutes(-1)
$cq.HoldUntil = Get-Date
Request-ChatOverlayUsageRefresh $cq
$asking = Get-ChatOverlayRefreshNote $cq.Refresh $cq.Live (Get-Date)
$null = Update-ChatOverlayUsage $cq $false
$checked = Get-ChatOverlayRefreshNote $cq.Refresh $cq.Live (Get-Date)
$gone = Get-ChatOverlayRefreshNote $cq.Refresh $cq.Live (Get-Date).AddSeconds(11)
Request-ChatOverlayUsageRefresh $cq
$again = Get-ChatOverlayRefreshNote $cq.Refresh $cq.Live (Get-Date)
Check 'a refresh says it is asking, then when Claude answered, then goes; a second click says why it waits' (
    $asking -eq 'asking...' -and $checked -match '^checked \d\d:\d\d:\d\d$' -and $null -eq $gone -and $again -eq 'just asked') "$asking | $checked | $gone | $again"
$held = Get-ChatOverlayRefreshNote @{ Kind = 'held'; At = (Get-Date); Done = $null; Ok = $false } $null (Get-Date)
$null = Invoke-ChatOverlayCycle $cq
$cq.Refresh = @{ Kind = 'held'; At = (Get-Date); Done = $null; Ok = $false }
$snapR = Invoke-ChatOverlayCycle $cq -Peek
# the pass after a -Peek one saves what the -Peek one saw first
$null = Invoke-ChatOverlayCycle $cq
$savedR = Read-ChatqJson $script:ChatOverlayPath
$clOf = { param($s) @($s.header.usage | Where-Object { $_.provider -eq 'Claude' })[0].status }
Check 'inside a named wait it says it did not ask - at the end of Claude''s line, and in overlay.json on the next pass' (
    $held -like '*not asked*' -and (& $clOf $snapR) -eq 'not asked - wait' -and (& $clOf $savedR) -eq 'not asked - wait') "$held | $(& $clOf $snapR) | $(& $clOf $savedR)"
$cq.Config.usageView = 'bars'
$snapB = Invoke-ChatOverlayCycle $cq -Peek
$cq.Config.usageView = 'lines'
Check 'as bars too: the same few words by the name, and no row of their own' ((& $clOf $snapB) -eq 'not asked - wait' -and -not @($snapB.header.notes).Count) "$(& $clOf $snapB) | $(@($snapB.header.notes).Count)"
# each usage line's end, and when a time needs its date
$nowS = Get-Date '2026-09-23T22:30:00'
$msOf = { param($d) [DateTimeOffset]::new($d).ToUnixTimeMilliseconds() }
$march = Get-Date '2026-03-13T16:38:00'
$stLive = [pscustomobject]@{ provider = 'Claude'; source = 'live'; at = (& $msOf $nowS.AddMinutes(-3)); why = $null }
$stCache = [pscustomobject]@{ provider = 'Claude'; source = 'cache'; at = (& $msOf $march); why = $null }
$stCodex = [pscustomobject]@{ provider = 'Codex'; source = 'rollout'; at = (& $msOf $march); why = $null }
$stHeld = [pscustomobject]@{ provider = 'Claude'; source = 'live'; at = (& $msOf $nowS.AddMinutes(-20)); why = 'rate-limited until 22:40' }
Check 'a usage line ends in when its figure is from, or what is happening to it' (
    (Get-ChatOverlayUsageStatus $stLive $false $null $null $nowS) -eq '22:27' -and
    (Get-ChatOverlayUsageStatus $stLive $true $null $null $nowS) -eq 'asking...' -and
    (Get-ChatOverlayUsageStatus $stLive $false 'checked 22:29:59' $null $nowS) -eq 'checked 22:29:59' -and
    (Get-ChatOverlayUsageStatus $stCache $false $null $null $nowS) -eq 'cached Mar 13' -and
    (Get-ChatOverlayUsageStatus $stCodex $false $null $null $nowS) -eq 'last run Mar 13' -and
    (Get-ChatOverlayUsageStatus $stHeld $false $null $nowS.AddMinutes(10) $nowS) -eq '22:10, retry 22:40') (Get-ChatOverlayUsageStatus $stHeld $false $null $nowS.AddMinutes(10) $nowS)
Check 'a time six months back shows its date, not a weekday that reads as last week' (
    (Format-ChatOverlayWhen $march $nowS) -eq 'Mar 13' -and (Format-ChatOverlayWhen $nowS.AddDays(-3) $nowS) -eq 'Sun 22:30' -and (Format-ChatOverlayWhen $nowS.AddHours(-1) $nowS) -eq '21:30')
$codexOld = ConvertTo-ChatOverlayUsage 'Codex' 'rollout' ([pscustomobject]@{ Windows = @([pscustomobject]@{ Label = 'week'; Percent = 5; ResetsAt = $null; Severity = $null }); At = (Get-Date).AddDays(-2) }) (Get-Date) $null @{}
$codexSt = Get-ChatOverlayUsageStatus $codexOld $false $null $null (Get-Date)
Check 'Codex''s old figure says it is from Codex''s last run, not when anything refreshed' ($codexSt -like 'last run *') "$codexSt"
$inlN = @(Get-ChatOverlayNotes ([pscustomobject]@{ usage = @($codexOld); watcher = 'none'; next = '17:10'; error = $null }))
Check 'no usage figure takes a row of its own under the usage; the next queued prompt still does' ($inlN.Count -eq 1 -and $inlN[0].text -like 'next queued prompt*') (($inlN | ForEach-Object { $_.text }) -join ' | ')
# Copilot through gh: GitHub's answer on Copilot Free (ids left out), and on a paid plan
$freeJson = '{"copilot_plan":"individual","access_type_sku":"free_limited_copilot","quota_reset_date":"2026-10-01","quota_snapshots":{"chat":{"entitlement":200,"percent_remaining":100,"remaining":200,"unlimited":false,"has_quota":true},"completions":{"entitlement":2000,"percent_remaining":99.9,"remaining":1999,"unlimited":false,"has_quota":true},"premium_interactions":{"entitlement":0,"percent_remaining":0,"remaining":0,"unlimited":false,"has_quota":false}}}'
$proJson = '{"quota_reset_date":"2026-10-01","quota_snapshots":{"chat":{"entitlement":0,"percent_remaining":100,"unlimited":true},"completions":{"entitlement":0,"percent_remaining":100,"unlimited":true},"premium_interactions":{"entitlement":300,"percent_remaining":25,"unlimited":false}}}'
$cpFree = @(ConvertFrom-ChatqCopilotQuota ($freeJson | ConvertFrom-Json))
$cpPro = @(ConvertFrom-ChatqCopilotQuota ($proJson | ConvertFrom-Json))
Check 'Copilot: chat and code on the free plan, premium alone on a paid one, and the month''s reset' (
    ($cpFree.Label -join ',') -eq 'chat,code' -and $cpFree[0].Percent -eq 0 -and [Math]::Abs($cpFree[1].Percent - 0.1) -lt 0.01 -and
    ($cpPro.Label -join ',') -eq 'premium' -and $cpPro[0].Percent -eq 75 -and $cpFree[0].ResetsAt.ToUniversalTime().Date -eq [datetime]'2026-10-01') "$($cpFree.Label -join ',') / $($cpPro.Label -join ',') $($cpPro[0].Percent)"
$script:ChatOverlayCopilotSeam = { @{ Ok = $true; Windows = @(ConvertFrom-ChatqCopilotQuota ($freeJson | ConvertFrom-Json)) } }
$cc = New-ChatOverlayContext
$cc.Config.liveUsage = $false
$ccCop = @(@(Update-ChatOverlayUsage $cc $false) | Where-Object { $_.provider -eq 'Copilot' })[0]
$script:ChatOverlayCopilotSeam = { @{ Ok = $false; Status = 4; Why = 'gh: To get started with GitHub CLI, please run:  gh auth login'; Quiet = $true } }
$cc.CopilotTriedAt = $null
$ccOut = @(@(Update-ChatOverlayUsage $cc $false) | Where-Object { $_.provider -eq 'Copilot' })
$script:ChatOverlayCopilotSeam = $null
# CHATQ_GH points at nothing: the real path, with no gh to run
$cc2 = New-ChatOverlayContext
$cc2.Config.liveUsage = $false
$ccNone = @(@(Update-ChatOverlayUsage $cc2 $false) | Where-Object { $_.provider -eq 'Copilot' })
$olPath = Join-Path $script:ChatqLogDir 'overlay.log'
$quietLog = -not (Test-Path -LiteralPath $olPath) -or -not (Select-String -LiteralPath $olPath -SimpleMatch 'copilot usage' -Quiet)
Check 'a Copilot line from gh''s answer; none when gh is not logged in or not there - and nothing logged' (
    $ccCop -and ($ccCop.windows.label -join ',') -eq 'chat,code' -and -not $ccOut.Count -and -not $ccNone.Count -and $cc2.CopilotWhy -eq 'no GitHub CLI' -and $quietLog) "$($ccCop.windows.label -join ',') $($ccOut.Count) $($ccNone.Count) $($cc2.CopilotWhy)"
# the real answer carried Retry-After: 2867, read as $null through .Delta.Value
Add-Type -AssemblyName System.Net.Http
# 429 has no name in .NET Framework's HttpStatusCode, and PowerShell will not cast to it
$s429 = [Enum]::ToObject([System.Net.HttpStatusCode], 429)
$resp = [System.Net.Http.HttpResponseMessage]::new($s429)
$resp.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([TimeSpan]::FromSeconds(2867))
$resp2 = [System.Net.Http.HttpResponseMessage]::new($s429)
$resp2.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([DateTimeOffset]::UtcNow.AddSeconds(600))
$raD = Get-ChatqRetryAfter $resp
$raT = Get-ChatqRetryAfter $resp2
Check 'Retry-After read, as seconds or as a date' ($raD -eq 2867 -and $raT -gt 590 -and $raT -le 600 -and $null -eq (Get-ChatqRetryAfter ([System.Net.Http.HttpResponseMessage]::new($s429)))) "$raD $raT"
$cu = New-ChatOverlayContext
$script:ChatOverlayUsageSeam = { @{ Ok = $false; Status = 429; Why = 'the usage endpoint answered 429'; RetryAfter = 2867 } }
$null = Update-ChatOverlayUsage $cu $true
$heldTo = $cu.HoldUntil
Request-ChatOverlayUsageRefresh $cu
Check 'a named wait is kept, refresh button or not, and shown with its end' ($heldTo -gt (Get-Date).AddMinutes(47) -and $cu.HoldUntil -eq $heldTo -and $cu.HoldKind -eq 'server' -and $cu.LiveWhy -like 'rate-limited until *') "$heldTo $($cu.LiveWhy)"
# shown on the panel with the last live figure up, not only over the cached one
$liveU = ConvertTo-ChatOverlayUsage 'Claude' 'live' ([pscustomobject]@{ Windows = @([pscustomobject]@{ Label = '5h'; Percent = 60; ResetsAt = $null; Severity = 'normal' }); At = (Get-Date).AddMinutes(-2) }) (Get-Date) $cu.LiveWhy @{}
$liveSt = Get-ChatOverlayUsageStatus $liveU $false $null $cu.HoldUntil (Get-Date)
Check 'the panel says so over the last live figure too: its time, and when it asks again' ($liveSt -match '^\d\d:\d\d, retry \d\d:\d\d$') "$liveSt"
$liveOld = [pscustomobject]@{ Windows = @([pscustomobject]@{ Label = '5h'; Percent = 60; ResetsAt = $null; Severity = 'normal' }); At = (Get-Date).AddMinutes(-16) }
Check 'a live figure 16 minutes old is not stale while idle asks are 15 apart' (-not (ConvertTo-ChatOverlayUsage 'Claude' 'live' $liveOld (Get-Date) $null @{} 20).stale -and (ConvertTo-ChatOverlayUsage 'Claude' 'cache' $liveOld (Get-Date) $null @{}).stale)
$cOff = New-ChatOverlayContext
$cOff.Config.liveUsage = $false
$cOff.Live = [pscustomobject]@{ Windows = @([pscustomobject]@{ Label = '5h'; Percent = 99; ResetsAt = $null; Severity = 'normal' }); At = (Get-Date) }
$offU = @(@(Update-ChatOverlayUsage $cOff $true) | Where-Object { $_.provider -eq 'Claude' })[0]
Check 'live usage off: the cache only, never a live figure from before' (-not $offU -or $offU.source -eq 'cache') "$($offU.source)"
# a restart keeps the last live figure and the named wait
$cu.Live = [pscustomobject]@{ Windows = @([pscustomobject]@{ Label = '5h'; Percent = 81; ResetsAt = (Get-Date).AddMinutes(70); Severity = 'warning' }); At = (Get-Date).AddMinutes(-3) }
$cu.Cache = $null
$script:ChatOverlayUsageSeam = $null
$cuSnap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @(Update-ChatOverlayUsage $cu $true); usageWhy = $cu.LiveWhy; liveHold = (ConvertTo-ChatOverlayMs $cu.HoldUntil) } }
[System.IO.File]::WriteAllText($script:ChatOverlayPath, ($cuSnap | ConvertTo-Json -Depth 6 -Compress), $utf8)
$cr = New-ChatOverlayContext
Restore-ChatOverlayUsage $cr
$crU = @(@(Update-ChatOverlayUsage $cr $true) | Where-Object { $_.provider -eq 'Claude' })[0]
Check 'a restart keeps the last live figure and the wait the endpoint named' ($crU.source -eq 'live' -and @($crU.windows)[0].percent -eq 81 -and $cr.HoldKind -eq 'server' -and
    [Math]::Abs(($cr.HoldUntil - $heldTo).TotalSeconds) -lt 2 -and -not $cr.Fetch) "$($crU.source) $(@($crU.windows)[0].percent) $($cr.HoldUntil)"
Remove-Item -LiteralPath $script:ChatOverlayPath -Force -EA SilentlyContinue
# the token: read, never written anywhere - not even into the log of a failure
$cred = Join-Path $claudeHome '.credentials.json'
$tokSecret = 'sk-ant-oat01-must-never-be-logged'
[System.IO.File]::WriteAllText($cred, ('{"claudeAiOauth":{"accessToken":"' + $tokSecret + '","expiresAt":' + $nowMs + '}}'), $utf8)
$tk = Get-ChatqClaudeToken $claudeHome
Check 'an expired login is not used' (-not $tk.Token -and $tk.Auth)
[System.IO.File]::WriteAllText($cred, ('{"claudeAiOauth":{"accessToken":"' + $tokSecret + '","expiresAt":' + ($nowMs + 3600000) + '}}'), $utf8)
$script:ChatOverlayUsageSeam = $null
$urlWas = $script:ChatOverlayUsageUrl
$script:ChatOverlayUsageUrl = 'http://127.0.0.1:9/api/oauth/usage'
$cu = New-ChatOverlayContext
$null = Update-ChatOverlayUsage $cu $true -WaitMs 15000
$script:ChatOverlayUsageUrl = $urlWas
$olog = [System.IO.File]::ReadAllText((Join-Path $script:ChatqLogDir 'overlay.log'), $utf8)
Check 'a failed ask is logged, the token never' ($cu.LiveWhy -and $olog -like '*usage:*' -and $olog -notlike "*$tokSecret*" -and -not (Select-String -LiteralPath (Get-ChildItem -LiteralPath $script:ChatqData -Recurse -File).FullName -SimpleMatch $tokSecret -List)) $cu.LiveWhy
Remove-Item -LiteralPath $cred -Force

# the Windows panel itself, built but never shown, in the STA process WPF needs
$wpf = @"
`$env:CHATQ_OVERLAY = '1'
. '$(Join-Path $sb 'tool\VS-code-chat-manager.ps1')'
Set-StrictMode -Off
Initialize-ChatOverlayNative
`$H = New-ChatOverlayHostState
`$script:ChatOverlayHost = `$H
`$H.Ctx = New-ChatOverlayContext
`$H.State = [pscustomobject]@{ x = `$null; y = `$null; locked = `$true; hidden = `$false }
New-ChatOverlayWindow `$H
`$use = @([pscustomobject]@{ provider = 'Claude'; source = 'live'; stale = `$false; status = '22:22'; windows = @([pscustomobject]@{ label = '5h'; percent = 42; resetsAt = `$null; severity = 'normal'; limited = `$false }) })
`$rows = @(1..10 | ForEach-Object { [pscustomobject]@{ key = "s:`$_"; kind = 'session'; status = 'idle'; rank = 3; project = 'p'; title = "chat `$_"; prompt = 'x'; stateText = 'idle 1m'; job = `$null } })
`$H.Ctx.ViewSig = 'a'
Update-ChatOverlayView `$H ([pscustomobject]@{ header = [pscustomobject]@{ usage = `$use; notes = @() }; rows = `$rows })
`$t = @(`$H.Stack.Children | Where-Object { `$_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { `$_.Text })
`$n10 = `$H.Stack.Children.Count
`$more = `$t -contains '+2 more ' + [char]0x00B7 + ' 2 idle'
# usage as a line - name, end, then the windows between - and as bars once
# the settings box says so
`$u0 = `$H.Stack.Children[0]
# a TextBlock built of runs has an empty .Text: the runs' own text
`$lineOk = `$u0 -is [System.Windows.Controls.DockPanel] -and (@(`$u0.Children | ForEach-Object { (@(`$_.Inlines) | ForEach-Object { `$_.Text }) -join '' }) -join '|') -eq 'Claude|22:22|5h 42%'
Set-ChatOverlayUsageView `$H 'bars'
`$H.ViewKey = `$null
Update-ChatOverlayView `$H ([pscustomobject]@{ header = [pscustomobject]@{ usage = `$use; notes = @() }; rows = `$rows })
# the bars with the name and, under it, when the figure is from
`$b0 = `$H.Stack.Children[0]
`$barsOk = (Get-ChatOverlayConfig).usageView -eq 'bars' -and `$b0 -is [System.Windows.Controls.Grid] -and (@(`$b0.Children[0].Children | ForEach-Object { `$_.Text }) -join '|') -eq 'Claude|22:22'
Set-ChatOverlayUsageView `$H 'lines'
`$H.Ctx.ViewSig = 'b'
Update-ChatOverlayView `$H ([pscustomobject]@{ header = [pscustomobject]@{ usage = `$use; notes = @() }; rows = @() })
`$t = @(`$H.Stack.Children | Where-Object { `$_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { `$_.Text })
`$n0 = `$H.Stack.Children.Count
`$nb = @(`$H.Controls.Child.Children).Count
`$hid = `$H.CtlWin.IsVisible
# shown the way the host shows them - WPF sets WS_EX_APPWINDOW again as a
# window shows - both still off every screen: the panel was never placed
# (marked placed, so un-hiding leaves it there), the buttons on its top edge
`$H.Placed = `$true
Set-ChatOverlayHidden `$H `$true
Set-ChatOverlayHidden `$H `$false
# a screen of the test's own, off every real one, with room above the
# panel: the buttons go there, placed by the code the pointer check runs
`$script:ChatOverlayWorkAreaSeam = { param(`$r) [pscustomobject]@{ X = -4000; Y = 0; Width = 1920; Height = 1020 } }
[ChatOverlayNative]::MoveTo(`$H.Hwnd, -2594, 197)
Set-ChatOverlayControlsPlacement `$H
`$pre = [ChatOverlayNative]::GetRect(`$H.CtlHwnd)
Show-ChatOverlayControls `$H `$true
`$ex = [ChatOverlayNative]::GetExStyle(`$H.Hwnd)
`$cex = [ChatOverlayNative]::GetExStyle(`$H.CtlHwnd)
`$pr = [ChatOverlayNative]::GetRect(`$H.Hwnd)
`$cr = [ChatOverlayNative]::GetRect(`$H.CtlHwnd)
`$gap = [int][Math]::Round(4 * `$pr[2] / `$H.Win.ActualWidth)
# pass after pass, as the pointer check places them every 120 ms
Set-ChatOverlayControlsPlacement `$H
Set-ChatOverlayControlsPlacement `$H
`$cr2 = [ChatOverlayNative]::GetRect(`$H.CtlHwnd)
`$beside = `$H.CtlSide -eq 'above' -and (`$cr[0] + `$cr[2]) -eq (`$pr[0] + `$pr[2]) -and (`$cr[1] + `$cr[3] + `$gap) -eq `$pr[1] -and
    `$cr2[0] -eq `$cr[0] -and `$cr2[1] -eq `$cr[1] -and [Math]::Abs(`$pre[0] - `$cr[0]) -le 1 -and [Math]::Abs(`$pre[1] - `$cr[1]) -le 1
`$kids = @(`$H.CtlLine.Children)
`$first = `$kids[0].ToolTip
`$far = `$kids[-1].ToolTip
Set-ChatOverlaySettingsOpen `$H `$true
`$H.CtlWin.UpdateLayout()
`$cw = [ChatOverlayNative]::GetRect(`$H.CtlHwnd)
`$grew = `$cw[3] -gt `$cr[3] -and (`$cw[1] + `$cw[3] + `$gap) -eq `$pr[1] -and (`$cw[0] + `$cw[2]) -eq (`$pr[0] + `$pr[2]) -and `$H.CtlStack.Children[1] -eq `$H.Controls
# the refresh icon turns while an ask is out, and stops when none is
`$H.Ctx.Fetch = @{ Task = [System.Threading.Tasks.TaskCompletionSource[int]]::new().Task }
Update-ChatOverlaySpin `$H
`$turning = `$H.Spinning
`$H.Ctx.Fetch = `$null
Update-ChatOverlaySpin `$H
`$spun = `$turning -and -not `$H.Spinning
`$H.Ctx.Config.theme = 'light'
Update-ChatOverlayTheme `$H
`$still = (`$H.Settings.Visibility -eq 'Visible') -and (`$H.CtlStack.Children.Count -eq 2)
# the slider itself, then the pass that saves what it rested on
`$slider = @(`$H.Settings.Child.Children | Where-Object { `$_ -is [System.Windows.Controls.Slider] })[0]
`$slider.Value = 0.5
`$moved = `$H.Win.Opacity -eq 0.5 -and `$H.PendingOpacity -eq 0.5
`$H.PendingAt = (Get-Date).AddSeconds(-2)
Update-ChatOverlayHover
`$kept = `$moved -and `$null -eq `$H.PendingOpacity -and (Get-ChatOverlayConfig).opacity -eq 0.5
Set-ChatOverlayCollapsed `$H `$true
`$one = @(`$H.Stack.Children[0].Children | Where-Object { `$_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { `$_.Text }) -join '/'
'{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}|{20}|{21}' -f `$n10, `$more, `$n0, (`$t -contains 'no chats open'), `$ex,
    `$nb, `$hid, `$H.Frame.Background.Color, `$still, `$kept,
    `$cex, `$H.Stack.Children.Count, `$one, `$H.CtlButtons[1].ToolTip, `$first,
    `$beside, `$grew, `$far, `$spun, `$lineOk, `$barsOk, "pre `$(`$pre -join ',') panel `$(`$pr -join ',') ctl `$(`$cr -join ',') then `$(`$cr2 -join ',') box `$(`$cw -join ',')"
"@
$wpfOut = @(& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -STA -EncodedCommand ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wpf))) 2>&1) | Select-Object -Last 1
$wp = "$wpfOut" -split '\|'
$ex = if ($wp.Count -ge 5) { [int64]$wp[4] } else { 0 }
Check 'the panel: 8 rows and "+2 more", or one line when nothing is open' ($wp[0] -eq '11' -and $wp[1] -eq 'True' -and $wp[2] -eq '3' -and $wp[3] -eq 'True') "$wpfOut"
Check 'shown, a tool window that never activates and lets clicks through, and no taskbar button' ((($ex -band 0x80800A0) -eq 0x80800A0) -and -not ($ex -band 0x40000)) ('0x{0:X}' -f $ex)
$cex = if ($wp.Count -ge 11) { [int64]$wp[10] } else { 0 }
Check 'seven buttons in a window of their own - the console''s among them - out of sight until the pointer comes' ($wp[5] -eq '7' -and $wp[6] -eq 'False') "$wpfOut"
Check 'that window, shown, takes clicks but never focus, and has no taskbar button' ((($cex -band 0x8080080) -eq 0x8080080) -and -not ($cex -band 0x20) -and -not ($cex -band 0x40000)) ('0x{0:X}' -f $cex)
Check 'the grip at the left end, close at the corner' ($wp[14] -eq 'Drag to move' -and $wp[17] -like 'Close*') "$wpfOut"
Check 'the buttons sit on the panel''s top edge, flush right, and stay put pass after pass - placed by their size, not where they are' ($wp[15] -eq 'True') "$wpfOut"
Check 'the settings box opens above the buttons, never over the panel' ($wp[16] -eq 'True') "$wpfOut"
Check 'the refresh icon turns while Claude is being asked' ($wp[18] -eq 'True') "$wpfOut"
Check 'usage drawn as a line - name, the windows, when it is from - and as bars, with the time under the name, once the settings box says so' ($wp[19] -eq 'True' -and $wp[20] -eq 'True') "$wpfOut"
Check 'the light theme redraws the frame and keeps the settings box open' ($wp[7] -eq '#F2FAFAFB' -and $wp[8] -eq 'True') "$wpfOut"
Check 'the opacity slider sets the panel''s, and config.json gets it once it rests' ($wp[9] -eq 'True') "$wpfOut"
Check 'collapsed: one line of counts and usage, and the chevron offers to expand' ($wp[11] -eq '1' -and $wp[12] -eq ('5h 42%/no chats open') -and $wp[13] -eq 'Expand') "$wpfOut"

# the console, built and shown off every screen, never activated, and driven
# the way a user would: its lists, a search, a chat picked, a file dropped, a
# screenshot pasted, Send, a theme switch, closing it
$con = @"
`$env:CHATQ_OVERLAY = '1'
. '$(Join-Path $sb 'tool\VS-code-chat-manager.ps1')'
Set-StrictMode -Off
`$script:ChatqSpawn = { `$true }
`$script:ChatConsoleNoSync = `$true
`$script:ChatConsoleClipboardSeam = { [pscustomobject]@{ Files = @(); Image = [byte[]](137, 80, 78, 71, 13, 10) } }
Initialize-ChatOverlayNative
`$H = New-ChatOverlayHostState
`$script:ChatOverlayHost = `$H
`$H.Ctx = New-ChatOverlayContext
`$H.State = [pscustomobject]@{ x = `$null; y = `$null; locked = `$true; hidden = `$false }
New-ChatOverlayWindow `$H
`$H.Snap = [pscustomobject]@{ header = [pscustomobject]@{ usage = @(); notes = @() }; counts = [pscustomobject]@{ queued = 0; running = 0; cutOff = 1 }; rows = @(
    [pscustomobject]@{ key = 's:$idCard'; kind = 'session'; status = 'idle'; chat = 'idle'; rank = 3; project = 'A'; title = 'Card'; stateText = 'idle 1m'; sessionId = '$idCard'; cwd = '$projA'; job = `$null; prompt = `$null }
    [pscustomobject]@{ key = 'c:c1'; kind = 'cutoff'; status = 'cutoff'; chat = 'cutoff'; rank = 0.5; project = 'api'; title = 'Rate limiter'; stateText = 'cut off - resets 13:00'; sessionId = 'c1'; cwd = 'C:\p'; path = 'C:\p\x.jsonl'; job = `$null; prompt = `$null }) }
New-ChatConsoleWindow `$H
`$C = `$H.Con
`$C.Win.ShowActivated = `$false
`$C.Win.Show()
`$C.Win.Left = -32000
`$C.Win.Top = -32000
`$ex = [ChatOverlayNative]::GetExStyle(`$C.Hwnd)
`$C.IndexParsed = `$true
`$C.Index = @(Get-ChatIndex)
Update-ChatConsole `$H
# the index read in a runspace of its own, its rows taken when ready - the
# timer that would take them needs a message loop this test does not run
`$idxStarted = [bool]`$C.IndexRead
for (`$i = 0; `$i -lt 200 -and `$C.IndexRead -and -not `$C.IndexRead.Async.IsCompleted; `$i++) { Start-Sleep -Milliseconds 50 }
Complete-ChatConsoleIndexRead `$H
`$idxRead = `$idxStarted -and -not `$C.IndexRead -and @(`$C.Index).Count -gt 0 -and @(`$C.Index).Count -eq @(Get-ChatIndex).Count -and `$C.IndexStamp -eq (Get-ChatIndexStamp)
`$idxSay = "`$idxStarted `$(@(`$C.Index).Count) `$(`$C.IndexStamp)"
`$kinds = (@(`$C.ChatItems | ForEach-Object Kind | Sort-Object -Unique) -join ',')
`$C.SearchBox.Text = 'limiter'
`$searched = @(`$C.ChatItems).Count
`$C.SearchBox.Text = ''
Select-ChatConsoleTarget `$H @(`$C.ChatItems | Where-Object { `$_.Id -eq '$idCard' })[0]
`$to = (@(`$C.To.Children[0].Inlines) | ForEach-Object { `$_.Text }) -join ''
`$f = Join-Path '$sb' 'console-drop.txt'
[IO.File]::WriteAllText(`$f, 'x')
Add-ChatConsoleDrop `$H @(`$f, '$sb')
for (`$i = 0; `$i -lt 60 -and @(`$C.Staged | Where-Object { `$_.Task -and -not `$_.Task.IsCompleted }).Count; `$i++) { Start-Sleep -Milliseconds 50 }
Update-ChatConsoleStaging `$H
`$folderSaid = `$C.Status.Text -like '*is a folder*'
Invoke-ChatConsolePaste `$H (Get-ChatConsoleClipboard)
`$staged = (@(`$C.Staged | ForEach-Object Name | Sort-Object) -join ',')
`$C.Prompt.Text = 'from the console'
Invoke-ChatConsoleSend `$H
`$j = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt `$_) -eq 'from the console' })[0]
`$files = (@(Get-ChatqAttachments `$j | ForEach-Object Name | Sort-Object) -join ',')
`$sent = [bool](`$j -and `$j.sendNow -and `$j.first -and `$j.sessionId -eq '$idCard' -and `$files -eq 'clip.png,console-drop.txt' -and `$C.Prompt.Text -eq '' -and -not `$C.Staged.Count -and
    -not @(Get-ChildItem -LiteralPath `$script:ChatConsoleDraftDir -EA SilentlyContinue).Count -and `$C.Status.Text -like 'queued #*')
# an edit to the queued prompt outlives a redraw of the queue
`$C.Sel = `$j.id
`$C.Sigs.Queue = `$null
Update-ChatConsoleQueue `$H
if (`$C.EditBox) { `$C.EditBox.Text = 'edited in place' }
`$C.Sigs.Queue = `$null
Update-ChatConsoleQueue `$H
`$editKept = [bool](`$C.EditBox -and `$C.EditBox.Text -eq 'edited in place')
# Remove asks first, and the second half of a double-click is no answer
Invoke-ChatConsoleJobAction `$H `$j.id 'remove'
Invoke-ChatConsoleJobAction `$H `$j.id 'remove'
`$askHeld = [bool](Find-ChatqJob `$j.id) -and [bool]`$C.Confirm[`$j.id]
`$C.Confirm[`$j.id] = (Get-Date).AddSeconds(-1)
Invoke-ChatConsoleJobAction `$H `$j.id 'remove'
`$removed = -not (Find-ChatqJob `$j.id)
# Continue twice before the list redraws: one job
`$ci = [pscustomobject]@{ Id = '$idCard'; Title = 'Card'; Path = `$null; Cwd = '$projA' }
Invoke-ChatConsoleContinue `$H @(`$ci)
Invoke-ChatConsoleContinue `$H @(`$ci)
`$conts = @(Get-ChatqJobs | Where-Object { `$_.kind -eq 'continue' -and `$_.sessionId -eq '$idCard' -and `$_.state -eq 'queued' })
`$contOnce = `$conts.Count -eq 1 -and `$C.Status.Text -like '*1 had one already*'
`$contSay = "`$(`$conts.Count) - `$(`$C.Status.Text)" -replace '\|', '/'
foreach (`$x in `$conts) { `$null = Remove-ChatqJob `$x 'test' }
# a Codex chat: no mode or model offered, and none sent even if picked before
`$cxItem = @(`$C.ChatItems | Where-Object { `$_.Provider -eq 'codex' })[0]
`$codexOpts = `$false
`$codexSent = `$false
if (`$cxItem) {
    `$C.Mode = 'plan'
    `$C.Model = 'opus'
    Select-ChatConsoleTarget `$H `$cxItem
    `$codexOpts = `$C.Opts.Children.Count -eq 2
    `$C.Prompt.Text = 'to codex'
    Invoke-ChatConsoleSend `$H
    `$cj = @(Get-ChatqJobs | Where-Object { (Read-ChatqPrompt `$_) -eq 'to codex' })[0]
    `$codexSent = [bool](`$cj -and `$cj.provider -eq 'codex' -and -not `$cj.mode -and -not `$cj.runModel)
    if (`$cj) { `$null = Remove-ChatqJob `$cj 'test' }
    `$C.Mode = ''
    `$C.Model = ''
    Select-ChatConsoleTarget `$H @(`$C.ChatItems | Where-Object { `$_.Id -eq '$idCard' })[0]
}
`$C.Prompt.Text = 'kept across a theme'
`$H.Ctx.Config.theme = 'light'
Update-ChatOverlayTheme `$H
`$kept = `$C.Prompt.Text -eq 'kept across a theme' -and `$C.Win.Background.Color.ToString() -eq '#FFF6F8FA'
Hide-ChatConsole `$H
`$st = Read-ChatConsoleState
`$saved = `$st.draft.text -eq 'kept across a theme' -and `$st.draft.target.Id -eq '$idCard' -and -not `$C.Win.IsVisible
if (`$j -and (Find-ChatqJob `$j.id)) { `$null = Remove-ChatqJob `$j 'test' }
'{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}' -f `$ex, `$kinds, `$searched, `$to, `$staged, `$sent, `$kept, `$saved, `$folderSaid, `$files, `$editKept, `$askHeld, `$removed, `$contOnce, `$codexOpts, `$codexSent, `$contSay, `$idxRead, `$idxSay
"@
$conOut = @(& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -STA -EncodedCommand ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($con))) 2>&1) | Select-Object -Last 1
$cp = "$conOut" -split '\|'
$cex = if ($cp.Count -ge 1 -and $cp[0] -match '^\d+$') { [int64]$cp[0] } else { -1 }
Check 'the console is a window of its own kind: it can take focus, and is no tool window, nor always on top' ($cex -ge 0 -and -not ($cex -band 0x80) -and -not ($cex -band 0x08000000) -and -not ($cex -band 0x8)) "$conOut"
Check 'it lists the chats the limit cut off and those open in VS Code; the search narrows them' ($cp[1] -like '*cutoff*' -and $cp[1] -like '*open*' -and $cp[2] -eq '1') "$conOut"
Check 'a chat picked is the one written to; a file dropped and a screenshot pasted go with it, a folder does not' ($cp[3] -like 'To*Card*' -and $cp[4] -eq 'clip.png,console-drop.txt' -and $cp[8] -eq 'True') "$conOut"
Check 'Send makes the job chatq would - first, sent now, files moved in - and clears the box for the next' ($cp[5] -eq 'True') "$conOut"
Check 'a theme switch keeps what is typed; closing it hides it and keeps the draft for next time' ($cp[6] -eq 'True' -and $cp[7] -eq 'True') "$conOut"
Check 'a queued prompt being edited outlives a redraw of the queue' ($cp[10] -eq 'True') "$conOut"
Check 'Remove asks, a double-click does not answer, a second click does' ($cp[11] -eq 'True' -and $cp[12] -eq 'True') "$conOut"
Check 'Continue clicked twice queues one continue' ($cp[13] -eq 'True') "$($cp[16])"
Check 'the index is read in a runspace of its own, never on the window''s thread, and its rows taken when ready' ($cp[17] -eq 'True') "$($cp[18])"
Check 'a Codex chat is offered no mode or model, and is sent none' ($cp[14] -eq 'True' -and $cp[15] -eq 'True') "$conOut"
$script:ChatOverlayUsageSeam = $null
$script:ChatqAliveSeam = $null
Remove-Item -LiteralPath $sessDir -Recurse -Force -EA SilentlyContinue

Set-Location -LiteralPath $here
Write-Host ''
$color = if ($script:Fail) { 'Red' } else { 'Green' }
Write-Host "  $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $color
if (-not $Keep) { Remove-Item -LiteralPath (Join-Path $here '.sandbox') -Recurse -Force -EA SilentlyContinue }
exit $script:Fail
