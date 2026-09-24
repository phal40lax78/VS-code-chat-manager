# tests/sections/metadata.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

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
