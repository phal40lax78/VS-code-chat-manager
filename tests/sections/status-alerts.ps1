# tests/sections/status-alerts.ps1: dot-sourced by tests/run-tests.ps1 in its turn,
# never on its own - it uses what the runner and the sections before it set.

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
