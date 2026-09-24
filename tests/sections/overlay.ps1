# tests/sections/overlay.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

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
function Set-OvSession([int]$ProcId, [string]$Sid, [string]$Status, [double]$MinutesAgo, $WaitingFor = $null, [string]$Name = 'derived-name', [string]$Kind = 'interactive',
    [string]$Entrypoint = 'claude-vscode') {
    $o = [ordered]@{ pid = $ProcId; sessionId = $Sid; cwd = $projO; startedAt = $nowMs - 3600000; procStart = '134346197461820071'; kind = $Kind
        entrypoint = $Entrypoint; pidDomain = "win32:$([Environment]::MachineName)"; name = $Name; status = $Status
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
# run after 22:30, the reset falls on tomorrow, and says its day
$resetSays = if ($resetAt.Date -eq $tnow.Date) { $resetAt.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } else { $resetAt.ToString('ddd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) }
Check 'cut off: an open idle chat says when the limit resets; a working one has moved on' (
    $r3.status -eq 'cutoff' -and $r3.rank -eq 0.5 -and $r3.stateText -eq "cut off - resets $resetSays" -and $rbn.status -eq 'busy') "$($r3.status) $($r3.stateText) / $($rbn.status)"
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
# their zone takes in the gap to the panel, on whichever side they sit - and
# resting on it brings them, hidden, straight from above the panel
$z1 = Get-ChatOverlayControlsZone @(1768, 172, 136, 24) 'above' 4
$z2 = Get-ChatOverlayControlsZone @(1768, 414, 136, 24) 'below' 4
Check 'the buttons'' zone runs from them to the panel''s edge, above it or below' (($z1 -join ',') -eq '1768,172,136,28' -and ($z2 -join ',') -eq '1768,410,136,28') "$($z1 -join ',') / $($z2 -join ',')"
Check 'resting on the buttons'' spot brings them, straight from above, after the same 350 ms' (
    (& $sh $false $false $true $false $false 360 0) -and -not (& $sh $false $false $true $false $false 120 0))
Check 'never with a mouse button held - a drag in the app below would drop onto them' (
    -not (& $sh $false $false $true $false $true 360 0) -and -not (& $sh $false $true $false $false $true 360 0))
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
# the spot the pointer check counts while they are hidden
`$zh = Get-ChatOverlayControlsHoverZone `$H
Show-ChatOverlayControls `$H `$true
`$ex = [ChatOverlayNative]::GetExStyle(`$H.Hwnd)
`$cex = [ChatOverlayNative]::GetExStyle(`$H.CtlHwnd)
`$pr = [ChatOverlayNative]::GetRect(`$H.Hwnd)
`$cr = [ChatOverlayNative]::GetRect(`$H.CtlHwnd)
`$gap = [int][Math]::Round(4 * `$pr[2] / `$H.Win.ActualWidth)
`$zoneOk = `$zh -and [Math]::Abs(`$zh[0] - `$cr[0]) -le 1 -and [Math]::Abs(`$zh[1] - `$cr[1]) -le 1 -and
    [Math]::Abs(`$zh[2] - `$cr[2]) -le 1 -and [Math]::Abs(`$zh[3] - (`$cr[3] + `$gap)) -le 1
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
'{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}|{20}|{21}|{22}' -f `$n10, `$more, `$n0, (`$t -contains 'no chats open'), `$ex,
    `$nb, `$hid, `$H.Frame.Background.Color, `$still, `$kept,
    `$cex, `$H.Stack.Children.Count, `$one, `$H.CtlButtons[1].ToolTip, `$first,
    `$beside, `$grew, `$far, `$spun, `$lineOk, `$barsOk, [bool]`$zoneOk, "pre `$(`$pre -join ',') zone `$(`$zh -join ',') panel `$(`$pr -join ',') ctl `$(`$cr -join ',') then `$(`$cr2 -join ',') box `$(`$cw -join ',')"
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
Check 'while hidden, the pointer check counts the very spot the buttons then show on, and the gap to the panel' ($wp[21] -eq 'True') "$wpfOut"
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
