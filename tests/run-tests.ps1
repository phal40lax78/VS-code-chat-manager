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
Invoke-ChatqJob $W (Find-ChatqJob $j.id)
$j = Find-ChatqJob $j.id
Check 'an idle live chat runs, with a reload warning' ($j.state -eq 'done' -and $j.result.stale) "$($j.state) stale=$($j.result.stale)"
$rq = [System.IO.File]::ReadAllText($script:ChatReloadPath, $utf8) | ConvertFrom-Json
Check 'and a reload offer for the window that holds it' ($rq.kind -eq 'ran' -and $rq.cwd -eq $projA) "$($rq.kind) $($rq.cwd)"
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
$probe2 = "Remove-Item env:CHATQ_WATCHER -EA SilentlyContinue; Set-StrictMode -Version Latest; `$ErrorActionPreference = 'Stop'; try { . '$(Join-Path $sb2 'VS-code-chat-manager.ps1')'; Set-Location -LiteralPath '$projA'; chatfind Doomed *> `$null; chatindex *> `$null; `$r = & `$script:ChatTitleCompleter 'chatrm' 'Target' 'Pars' `$null @{}; chatqlist *> `$null; chat *> `$null; 'ok' } catch { 'threw: ' + `$_.Exception.Message + ' ' + `$_.InvocationInfo.PositionMessage }"
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
Check 'an expired login -> auth' ($o.kind -eq 'auth') "$($o.kind) $($o.reason)"
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
$a0 = Get-AlertCount '*logged out*'
$ok = Confirm-ChatqAllowed $Wa $ja
Check 'a login gone: the lane waits and its jobs stay queued' (-not $ok -and $Wa.blocked[(Get-ChatqLane $ja)].Type -eq 'login needed') "$ok $($Wa.blocked['claude'].Type)"
$null = Confirm-ChatqAllowed $Wa $ja
Check 'with one alert, not one per probe' ((Get-AlertCount '*logged out*') -eq $a0 + 1)
Check 'and the status line says logged out' ((Get-ChatqStatusLine @() $Wa.blocked) -like '*logged out*')
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

Set-Location -LiteralPath $here
Write-Host ''
$color = if ($script:Fail) { 'Red' } else { 'Green' }
Write-Host "  $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $color
if (-not $Keep) { Remove-Item -LiteralPath (Join-Path $here '.sandbox') -Recurse -Force -EA SilentlyContinue }
exit $script:Fail
