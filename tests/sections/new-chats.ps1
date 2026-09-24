# tests/sections/new-chats.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

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
