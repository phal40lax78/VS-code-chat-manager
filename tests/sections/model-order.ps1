# tests/sections/model-order.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

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
