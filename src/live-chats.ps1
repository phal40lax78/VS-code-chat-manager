# VS-code-chat-manager, src/live-chats.ps1: dot-sourced by VS-code-chat-manager.ps1
# in its turn, never on its own - see the list there.

#region live chats ------------------------------------------------------------
# Each VS Code window keeps a claude process alive for every chat opened in it,
# not just the one on screen, and clicking a chat in the history list switches
# back to that live process rather than re-reading the transcript. A run
# delivered from outside lands in the transcript that process never re-reads.

function Get-ChatqLiveSessions {
    # claude agents --json lists them all, panel tabs included, with no TTY.
    # ~/.claude/sessions/<pid>.json is the registry behind it - the fallback.
    # -RegistryOnly goes straight to it: a click waiting on an answer should
    # not wait up to 30 s for a CLI to start.
    param([string]$ConfigDir, [switch]$RegistryOnly)
    $exe = if ($RegistryOnly) { $null } else { Find-ChatqExe claude }
    if ($exe) {
        $buf = [System.Collections.Generic.List[string]]::new()
        try {
            $null = Invoke-ChatqProcess -Exe $exe -ArgList @('agents', '--json') -StdIn '' -TimeoutSec 30 `
                -SetEnv @{ CLAUDE_CONFIG_DIR = $ConfigDir } -OnLine { param($l) $buf.Add($l) }
            $list = ($buf -join "`n") | ConvertFrom-Json
            if ($null -ne $list) {
                return @($list | ForEach-Object {
                        $ep = if ($_.PSObject.Properties['entrypoint']) { [string]$_.entrypoint } else { $null }
                        [pscustomobject]@{ SessionId = $_.sessionId; Pid = $_.pid; Status = $_.status; Kind = $_.kind; WaitingFor = $_.waitingFor; ProcStart = $null; StartedAt = $_.startedAt; Entrypoint = $ep }
                    })
            }
        }
        catch {}
    }
    # A registry file can outlive its process, and the pid be reused by
    # something else - only a claude that started when the file says counts.
    $dir = Join-Path (Get-ChatqHomeDir 'claude' $ConfigDir) 'sessions'
    return @(Read-ChatqSessionRegistry $dir | Where-Object { Test-ChatqSessionAlive $_ } | ForEach-Object {
            [pscustomobject]@{ SessionId = $_.SessionId; Pid = $_.Pid; Status = $_.Status; Kind = $_.Kind; WaitingFor = $_.WaitingFor; ProcStart = $_.ProcStart; StartedAt = $_.StartedAt; Entrypoint = $_.Entrypoint }
        })
}

function Read-ChatqSessionRegistry {
    <#
    Claude Code's own list of what runs: sessions/<pid>.json, one per process,
    rewritten as its status moves between idle, busy and waiting. Only
    <digits>.json is read. The <pid>.<hash>.key beside each one is that
    session's messaging secret, and is never opened - nor is the file's
    messagingSocketPath taken: only the fields below are.
    -Cache (a hashtable kept between calls) re-parses only a file whose length
    or write time moved, which is what lets the overlay list it every 2 s.
    #>
    param([string]$Dir, [hashtable]$Cache)
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return @() }
    $seen = @{}
    $out = foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter *.json -File -EA SilentlyContinue)) {
        if ($f.Name -notmatch '^\d+\.json$') { continue }
        $key = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        $seen[$f.FullName] = $true
        $hit = if ($Cache) { $Cache[$f.FullName] } else { $null }
        if ($hit -and $hit.Key -eq $key) { if ($hit.Entry) { $hit.Entry }; continue }
        # one try, no waiting: a file caught mid-write reads again next pass,
        # and until then the last good copy stands
        $o = try { [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $null }
        if (-not $o -or -not $o.pid) {
            if ($hit -and $hit.Entry) { $hit.Entry }
            continue
        }
        $p = { param($n) if ($o.PSObject.Properties[$n]) { $o.$n } else { $null } }
        $e = [pscustomobject]@{
            Pid = [int]$o.pid; SessionId = [string](& $p 'sessionId'); Cwd = [string](& $p 'cwd')
            Status = [string](& $p 'status'); WaitingFor = & $p 'waitingFor'; Name = [string](& $p 'name')
            Kind = [string](& $p 'kind'); ProcStart = & $p 'procStart'; StartedAt = & $p 'startedAt'
            UpdatedAt = & $p 'updatedAt'; StatusUpdatedAt = & $p 'statusUpdatedAt'; PidDomain = [string](& $p 'pidDomain')
            # claude-vscode for a VS Code panel's process, something else for a terminal's
            Entrypoint = [string](& $p 'entrypoint')
        }
        if ($Cache) { $Cache[$f.FullName] = @{ Key = $key; Entry = $e } }
        $e
    }
    if ($Cache) { foreach ($k in @($Cache.Keys)) { if (-not $seen[$k]) { $Cache.Remove($k) } } }
    return @($out)
}

function Test-ChatqSessionAlive {
    <#
    Is the process a registry entry names still that session? The file
    outlives a crash, and Windows hands a pid to something else within
    minutes. So: a claude or node process with that pid, on this machine,
    started when the entry says - to 3 s by procStart where that is a FILETIME,
    and never more than 10 s after startedAt, which is what catches a pid
    reused by a later process.
    -Procs is a pid-keyed snapshot, so a pass over many entries asks the OS once.
    #>
    param($Entry, [hashtable]$Procs)
    if ($script:ChatqAliveSeam) { return [bool](& $script:ChatqAliveSeam $Entry) }   # tests
    if (-not $Entry -or -not $Entry.Pid) { return $false }
    # "win32:<host>": a registry synced in from another machine names its own
    if ($Entry.PidDomain -match '^win32:(.+)$' -and $Matches[1] -ne [Environment]::MachineName) { return $false }
    $pr = if ($Procs) { $Procs[[int]$Entry.Pid] } else { Get-Process -Id $Entry.Pid -EA SilentlyContinue }
    if (-not (Test-ChatqClaudeProcess $pr $Entry.ProcStart)) { return $false }
    if ($Entry.StartedAt) {
        try {
            $began = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Entry.StartedAt).LocalDateTime
            if (($pr.StartTime - $began).TotalSeconds -gt 10) { return $false }
        }
        catch {}
    }
    return $true
}

function Resolve-ChatqLiveAction {
    <#
    run    nothing holds the chat - the next click on it loads the run from disk
    defer  busy or waiting: someone, or Claude's own auto-continue, is using it
    stop   idle: end that process first, so the next click has to re-load
    warn   idle: run anyway and say to reload the window before typing there
    The idle case is config liveIdle ('warn' until the panel is known to
    recover cleanly from 'stop'); this is the one place it is decided.
    #>
    param($Job, [object[]]$Live)
    if ($Job.provider -ne 'claude') { return @{ Action = 'run' } }
    $hit = @($Live | Where-Object { $_.SessionId -eq $Job.sessionId })
    if (-not $hit) { return @{ Action = 'run' } }
    if (@($hit | Where-Object { $_.Status -in 'busy', 'waiting' })) { return @{ Action = 'defer'; Live = $hit } }
    $cfg = Get-ChatqConfig
    $idle = if ($cfg.liveIdle -in 'stop', 'warn') { $cfg.liveIdle } else { 'warn' }
    return @{ Action = $idle; Live = $hit }
}

function Get-ChatField {
    # a property that may be missing, read without tripping StrictMode
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-ChatqEntryStart {
    # when a live entry's process started: what it says, else the process's own
    param($Entry)
    $at = Get-ChatField $Entry 'StartedAt'
    if ($at) { try { return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$at).LocalDateTime } catch {} }
    try { return (Get-Process -Id ([int](Get-ChatField $Entry 'Pid')) -EA Stop).StartTime } catch { return [datetime]::MinValue }
}

function Test-ChatVsCodeOwned {
    # Is this claude a VS Code window's? Its registry entry says claude-vscode,
    # and its parent is a Code.exe that started before it - the window's
    # extension host (S29). A terminal's claude, even in VS Code's own
    # terminal, has a shell for a parent. The parent is worth its lookup for
    # its pid too: that names the one window holding the chat (hostPids).
    # Pure, for the tests.
    param([string]$Entrypoint, [string]$ParentName, $ParentStart, $ChildStart)
    if ($Entrypoint -and $Entrypoint -ne 'claude-vscode') { return $false }
    if ($ParentName -notmatch '^Code( - Insiders)?$') { return $false }
    if ($ParentStart -and $ChildStart -and $ParentStart -gt $ChildStart) { return $false }  # parent pid reused
    return $true
}

function Get-ChatParentProcess {
    # The process a chat's claude runs under, @{ Pid; Name; StartTime } - or
    # $null when that cannot be told, and off Windows, where there is no CIM
    # to ask.
    param($Entry, $Process)
    if ($script:ChatParentSeam) { return (& $script:ChatParentSeam $Entry) }   # tests
    if (-not $script:ChatqIsWindows) { return $null }
    try {
        $id = if ($Process) { [int]$Process.Id } else { [int](Get-ChatField $Entry 'Pid') }
        $w = Get-CimInstance Win32_Process -Filter "ProcessId = $id" -EA Stop | Select-Object -First 1
        if (-not $w) { return $null }
        $pp = Get-Process -Id ([int]$w.ParentProcessId) -EA Stop
        $st = try { $pp.StartTime } catch { $null }
        return @{ Pid = [int]$pp.Id; Name = [string]$pp.ProcessName; StartTime = $st }
    }
    catch { return $null }
}

function Stop-ChatIdleProcess {
    <#
    The one place a chat's old process is ended, so the next look at the chat
    loads it from disk (spike S29). Only a VS Code window's process, and only
    one Claude calls idle with no workflow or background agent of its own in
    flight - its registry file read again just before it goes. A terminal's
    claude is never ended. OldProcess says what became of it:
      none   nothing holds the chat
      held   busy, waiting, or background work in flight - or a print-mode
             claude going into the chat right now: nothing ended
      other  a terminal's claude holds it: nothing ended, and the chat is not
             to be shown in VS Code as well - that would be a second writer
      live   -JudgeOnly: a window's idle process, left running
      ended  every window's process of it ended
      kept   one could not be checked or ended (no registry file for it, off
             Windows): left running
    HostPids: the Code.exe each window's process runs under, taken before
    anything is ended - which window holds the chat. With -JudgeOnly they are
    taken for a held chat too, and a terminal's claude says other even while
    it works.
    Background work is told apart by who started it, never by when: what a
    print-mode run started died with it, what the window's process started
    is its own (Get-ChatBackgroundTasks -SkipPrint).
    #>
    param([string]$SessionId, [string]$Transcript, [string]$ConfigDir, [object[]]$Live, [switch]$JudgeOnly)
    $res = [pscustomobject]@{ OldProcess = 'none'; Stopped = [int[]]@(); HostPids = [int[]]@(); Terminal = $false }
    if (-not $PSBoundParameters.ContainsKey('Live')) { $Live = @(Get-ChatqLiveSessions $ConfigDir) }
    # a print-mode claude writing into the chat now - someone's claude -p, or
    # a run not chatq's: a window shown the chat meanwhile would hold a copy
    # from part way through, and a second writer
    if (Test-ChatPrintLive $Live $SessionId) { $res.OldProcess = 'held'; return $res }
    # interactive only: an ended print-mode run of the same chat holds nothing
    $mine = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @($Live)) {
        if (-not $e -or [string](Get-ChatField $e 'SessionId') -ne $SessionId) { continue }
        $k = [string](Get-ChatField $e 'Kind')
        if ($k -and $k -ne 'interactive') { continue }
        $mine.Add($e)
    }
    if (-not $mine.Count) { return $res }
    $held = $false
    foreach ($e in $mine) {
        if ([string](Get-ChatField $e 'Status') -in 'busy', 'waiting') { $held = $true; break }
    }
    # idle, as Claude sees it - which a turn that sent work to the background
    # also is, while that work goes on. No print-mode run of it is alive (just
    # above), so what one started is dead and left out.
    if (-not $held -and $Transcript -and (Test-Path -LiteralPath $Transcript)) {
        $wrote = (Get-Item -LiteralPath $Transcript).LastWriteTime
        foreach ($e in $mine) {
            $since = Get-ChatqEntryStart $e
            if ($wrote -lt $since) { continue }
            if (@(Get-ChatBackgroundTasks $Transcript $since -SkipPrint).Count) { $held = $true; break }
        }
    }
    # Held, and about to be ended: said at once, whoever's it is - nothing is
    # ended either way. Only judging (the chip, a run with someone at the
    # PC), whose it is still matters: a terminal's claude mid-turn is other,
    # or a tab would open beside it as a second writer, and a window's is
    # named, so that window is the one brought forward.
    if ($held -and -not $JudgeOnly) { $res.OldProcess = 'held'; return $res }

    # whose each one is, parent first: a window's, or a terminal's
    $ours = [System.Collections.Generic.List[object]]::new()
    $hosts = [System.Collections.Generic.List[int]]::new()
    foreach ($e in $mine) {
        $pr = Get-Process -Id ([int](Get-ChatField $e 'Pid')) -EA SilentlyContinue
        if (-not $script:ChatParentSeam) {
            if (-not $pr) { continue }   # gone since the list was made
            if (-not $script:ChatqIsWindows) {
                # nothing to ask for its parent here: the registry's word
                # alone, and never ended (kept, below)
                $ep = [string](Get-ChatField $e 'Entrypoint')
                if ($ep -and $ep -ne 'claude-vscode') { $res.Terminal = $true } else { $ours.Add($e) }
                continue
            }
        }
        $par = Get-ChatParentProcess $e $pr
        $childStart = if ($pr) { try { $pr.StartTime } catch { $null } } else { $null }
        $owned = [bool]$par -and (Test-ChatVsCodeOwned ([string](Get-ChatField $e 'Entrypoint')) ([string](Get-ChatField $par 'Name')) (Get-ChatField $par 'StartTime') $childStart)
        if (-not $owned) { $res.Terminal = $true; continue }
        $ours.Add($e)
        $hp = [int](Get-ChatField $par 'Pid')
        if ($hp -and -not $hosts.Contains($hp)) { $hosts.Add($hp) }
    }
    $res.HostPids = [int[]]$hosts.ToArray()
    # a terminal holds it: any refresh in VS Code would start a second writer
    if ($res.Terminal) { $res.OldProcess = 'other'; return $res }
    if ($held) { $res.OldProcess = 'held'; return $res }
    if (-not $ours.Count) { return $res }
    if ($JudgeOnly) { $res.OldProcess = 'live'; return $res }

    # each one read again from its registry file, then ended at once: the gap
    # someone could start typing in is the time taskkill takes to start
    $dir = Join-Path (Get-ChatqHomeDir 'claude' $ConfigDir) 'sessions'
    $kept = $false
    $stopped = [System.Collections.Generic.List[int]]::new()
    $short = $SessionId.Substring(0, [Math]::Min(8, $SessionId.Length))
    foreach ($e in $ours) {
        $procId = [int](Get-ChatField $e 'Pid')
        $re = @(Read-ChatqSessionRegistry $dir | Where-Object { $_.Pid -eq $procId }) | Select-Object -First 1
        # no file to check it against: not ended on a guess
        if (-not $re) { $kept = $true; continue }
        # the pid is another chat's now: this one's process is gone
        if ($re.SessionId -and $re.SessionId -ne $SessionId) { continue }
        if ($re.Status -ne 'idle') { $res.OldProcess = 'held'; $res.Stopped = [int[]]$stopped.ToArray(); return $res }
        if ($script:ChatStopSeam) {
            # tests: ended, other (not verified - kept) or gone
            switch ([string](& $script:ChatStopSeam $re)) {
                'ended' { $stopped.Add($procId) }
                'other' { $kept = $true }
            }
            continue
        }
        $pr = Get-Process -Id $procId -EA SilentlyContinue
        if (-not $pr -or -not (Test-ChatqSessionAlive $re) -or -not (Test-ChatqClaudeProcess $pr $re.ProcStart)) { continue }
        if (-not $script:ChatqIsWindows) { $kept = $true; continue }
        Stop-ChatqTree $pr
        $stopped.Add($procId)
        Write-ChatqWatchLog "show: ended idle chat process $procId ($short)"
    }
    $res.Stopped = [int[]]$stopped.ToArray()
    $res.OldProcess = if ($kept) { 'kept' } elseif ($stopped.Count) { 'ended' } else { 'none' }
    return $res
}

function Find-ChatTranscriptPath {
    # a chat's transcript by its id: the index's folders for this project,
    # else wherever Claude Code put one the index has not seen yet
    param([string]$SessionId, [string]$Cwd, [string]$ConfigDir)
    $hit = @(Get-ChatProjectFiles -Cwd $Cwd | Where-Object { $_.Extension -eq '.jsonl' -and $_.BaseName -eq $SessionId }) | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return (Find-ChatOverlayTranscript (Get-ChatqHomeDir 'claude' $ConfigDir) $Cwd $SessionId)
}

function Show-ChatFresh {
    <#
    Show a chat up to date where it is open. One routine for all three ways
    in: a queued run into a chat a window still holds (-Via run), the
    overlay's open chip (-Via chip), and the extension's Show it button
    (-Via button). For a run and Show it, the chat's old idle process goes
    first (Stop-ChatIdleProcess), so the next look loads it from disk; then
    the window is told, and the extension in extension/ does the rest.
    After a run the process is ended only with nobody at the PC (-Away):
    someone there may be reading the chat, and what a side bar does when the
    chat on screen loses its process is unchecked (S30). Show it ends it.
    The chip ends nothing and judges no busy: it only asks the window to
    open the chat as a tab, or bring forward the tab already showing it.
    Ending the process under a tab that still showed the chat had the
    window resume it twice, and a second click then left both views with a
    process that exited with code 1. A terminal's chat is still turned away,
    and a queued run going into it still holds it.
    Returns @{ Outcome; ExitCode; Busy; OldProcess; HostPids; Stopped }; the
    chip's child exits with ExitCode, which picks the tray's words. An
    outcome that judged nothing (bad, missing) says kept: nothing was
    checked, which is as good as a process that could not be. Every call
    past the id and folder check leaves one line in watcher.log, so a click
    that went wrong can be traced afterwards.
    #>
    param([string]$SessionId, [string]$Cwd, [string]$Title, [string]$TitleB64, [string]$ConfigDir,
        [string]$Transcript, [ValidateSet('run', 'chip', 'button')][string]$Via = 'chip',
        [int]$Seconds = $script:ChatIdleSeconds, $Away = $null)
    $codes = @{ ok = 0; held = 10; running = 15; other = 20; 'not-raised' = 25; missing = 30; 'no-code' = 40; 'code-failed' = 41; bad = 50 }
    $logIt = $false
    $done = {
        param([string]$Outcome, $Busy = $null, $Judged = $null)
        $r = [pscustomobject]@{
            Outcome = $Outcome; ExitCode = [int]$codes[$Outcome]; Busy = $Busy
            OldProcess = $(if ($Judged) { [string]$Judged.OldProcess } else { 'kept' })
            HostPids = $(if ($Judged) { [int[]]@($Judged.HostPids | Where-Object { $_ }) } else { [int[]]@() })
            Stopped = $(if ($Judged) { [int[]]@($Judged.Stopped | Where-Object { $_ }) } else { [int[]]@() })
        }
        if ($logIt) {
            # ASCII only: the id is checked, and no title goes in
            $b = if ($null -eq $Busy) { 'unjudged' } elseif ($Busy) { 'true' } else { 'false' }
            $hp = if (@($r.HostPids).Count) { @($r.HostPids) -join ',' } else { 'none' }
            Write-ChatqWatchLog "show ($Via) $($SessionId.Substring(0, 8)): $($r.OldProcess), busy $b, hosts $hp -> $Outcome"
        }
        $r
    }
    # the title comes from the overlay as base64, so no chat's words are ever
    # parsed as code on the way
    if ($TitleB64) { try { $Title = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TitleB64)) } catch {} }
    if ($SessionId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' -or -not $Cwd -or
        -not (Test-Path -LiteralPath $Cwd -PathType Container)) { return (& $done 'bad') }
    $logIt = $true
    if (-not $Transcript) { $Transcript = Find-ChatTranscriptPath $SessionId $Cwd $ConfigDir }
    if (-not $Transcript -and $Via -ne 'run') { return (& $done 'missing') }
    $live = @(Get-ChatqLiveSessions $ConfigDir -RegistryOnly:($Via -eq 'button'))
    # A queued prompt going into it now - another after the one whose Show it
    # this is, say - or any print-mode claude: ending the window's process
    # and showing the chat would load it part way through, a second writer
    # beside the run, and cut off nothing less. Held, busy, and left alone;
    # the run's own request comes when it ends. After a run (-Via run) its
    # own process is gone and the next job has not started.
    if ($Via -ne 'run' -and (@(Get-ChatqJobs | Where-Object { $_.state -eq 'running' -and [string]$_.sessionId -eq $SessionId }).Count -or
            (Test-ChatPrintLive $live $SessionId))) {
        return (& $done 'running' $true ([pscustomobject]@{ OldProcess = 'held'; HostPids = @(); Stopped = @() }))
    }
    # the chip ends nothing: the window opens the chat as a tab, or brings
    # forward the one already showing it, on the process it has
    $judgeOnly = $Via -eq 'chip' -or ($Via -eq 'run' -and $Away -ne $true)
    $j = Stop-ChatIdleProcess -SessionId $SessionId -Transcript $Transcript -ConfigDir $ConfigDir -Live $live -JudgeOnly:$judgeOnly
    # busy: the chat itself held, or another in the folder working - which
    # Reload Webviews would cut off as surely as a window reload. Not judged
    # for the chip: opening a tab cuts nothing off.
    $busy = $true
    if ($Via -eq 'chip') { $busy = $null }
    elseif ($j.OldProcess -ne 'held') {
        $idle = Test-ChatIdle -Cwd $Cwd -Except $Transcript -Seconds $Seconds -ConfigDir $ConfigDir -Live $live
        $busy = if ($null -eq $idle) { $null } else { -not $idle }
    }
    $outcome = switch ($j.OldProcess) { 'held' { 'held' } 'other' { 'other' } default { 'ok' } }
    if ($Via -eq 'run') {
        Write-ChatReloadRequest -Title $Title -Cwd $Cwd -Kind 'ran' -Busy $busy -Away $Away -SessionId $SessionId `
            -ConfigHome $ConfigDir -OldProcess $j.OldProcess -HostPids $j.HostPids
    }
    elseif ($Via -eq 'chip' -and $j.OldProcess -ne 'other') {
        Write-ChatOpenRequest -SessionId $SessionId -Cwd $Cwd -Title $Title -ConfigHome $ConfigDir -Busy $busy `
            -OldProcess $j.OldProcess -HostPids $j.HostPids
        # A window holds it, but none is on exactly its folder - a multi-root
        # one, say: code -n <folder> would open a second window on it, so the
        # request alone goes. Which windows are exact is only guessed at from
        # their titles out here (S30).
        if (@($j.HostPids).Count -and -not (Test-ChatWindowExact $Cwd @(Get-ChatCodeWindowTitles) @(Get-ChatCodeProfileNames))) { $outcome = 'not-raised' }
        else {
            $c = Open-ChatCodeWindow $Cwd
            if (-not $c.Ok) { $outcome = [string]$c.Code }
        }
    }
    return (& $done $outcome $busy $j)
}

function ConvertTo-ChatFreshVerdict {
    # What the Show it button's child prints for the extension: one line of
    # ASCII JSON, read by its parseVerdict. Pure.
    param($Result)
    return ([ordered]@{
            busy       = $Result.Busy
            oldProcess = [string]$Result.OldProcess
            outcome    = [string]$Result.Outcome
            hostPids   = [int[]]@($Result.HostPids | Where-Object { $_ })
        } | ConvertTo-Json -Compress)
}

function Test-ChatWindowExact {
    <#
    Is a VS Code window open on exactly this folder? Told from the windows'
    titles, where VS Code's default puts the folder's name last before its
    own - or before the profile's name, when one other than Default is in
    use: ${activeEditorShort} - ${rootName} - ${profileName} - ${appName}.
    -Profiles are those names (Get-ChatCodeProfileNames), so only a real
    profile is stripped, never a folder that happens to follow another. A
    proxy all the same - a multi-root window shows its workspace's name
    there, and a window.title of one's own can hide it (S30). Pure, for the
    tests.
    #>
    param([string]$Cwd, [string[]]$Titles, [string[]]$Profiles = @())
    $leaf = Split-Path ([string]$Cwd).TrimEnd('\', '/') -Leaf
    if (-not $leaf) { return $false }
    foreach ($t in @($Titles)) {
        $s = (([string]$t) -replace '\s+-\s+Visual Studio Code( - Insiders)?(\s*\[[^\]]*\])?\s*$', '').Trim()
        $cut = @($s)
        foreach ($p in @($Profiles)) {
            if ($p -and $s.EndsWith(" - $p", [StringComparison]::OrdinalIgnoreCase)) { $cut += $s.Substring(0, $s.Length - $p.Length - 3) }
        }
        foreach ($c in $cut) {
            if ($c -eq $leaf -or $c.EndsWith(" - $leaf", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Get-ChatCodeProfileNames {
    # The names of VS Code's profiles, which its window titles carry after the
    # folder's (Test-ChatWindowExact). VS Code keeps them in its own
    # storage.json, userDataProfiles - read, nothing more; it is VS Code's
    # settings, not runtime data of ours. None when there are none.
    if ($script:ChatCodeProfilesSeam) { return @(& $script:ChatCodeProfilesSeam) }   # tests
    if (-not $env:APPDATA) { return @() }
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($app in 'Code', 'Code - Insiders') {
        $f = Join-Path $env:APPDATA "$app\User\globalStorage\storage.json"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $o = [System.IO.File]::ReadAllText($f) | ConvertFrom-Json
            if (-not $o.PSObject.Properties['userDataProfiles']) { continue }
            foreach ($p in @($o.userDataProfiles)) {
                $n = [string](Get-ChatField $p 'name')
                if ($n -and -not $names.Contains($n)) { $names.Add($n) }
            }
        }
        catch {}
    }
    return @($names)
}

# the titles of VS Code's windows, read and nothing else: nothing here moves,
# raises or activates a window
$script:ChatCodeWindowsCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ChatCodeWindows {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public static string[] Titles(int[] pids) {
        List<string> found = new List<string>();
        List<uint> want = new List<uint>();
        foreach (int p in pids) { want.Add((uint)p); }
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (want.Contains(pid) && IsWindowVisible(h)) {
                StringBuilder sb = new StringBuilder(512);
                if (GetWindowText(h, sb, 512) > 0) { found.Add(sb.ToString()); }
            }
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }
}
'@

function Get-ChatCodeWindowTitles {
    if ($script:ChatWindowTitlesSeam) { return @(& $script:ChatWindowTitlesSeam) }   # tests
    if (-not $script:ChatqIsWindows) { return @() }
    try {
        $ids = @(Get-Process -Name 'Code', 'Code - Insiders' -EA SilentlyContinue | ForEach-Object { [int]$_.Id })
        if (-not $ids) { return @() }
        if (-not ('ChatCodeWindows' -as [type])) { Add-Type -TypeDefinition $script:ChatCodeWindowsCode }
        return @([ChatCodeWindows]::Titles([int[]]$ids))
    }
    catch { return @() }
}

function Get-ChatRunningCodeExes {
    # the Code.exe files VS Code runs from right now, Insiders' too; Windows
    if ($script:ChatCodeExesSeam) { return @(& $script:ChatCodeExesSeam) }   # tests
    if (-not $script:ChatqIsWindows) { return @() }
    return @(Get-Process -Name 'Code', 'Code - Insiders' -EA SilentlyContinue |
        ForEach-Object { try { $_.Path } catch { $null } } | Where-Object { $_ } | Select-Object -Unique)
}

function Find-ChatCodeCommand {
    # CHATQ_CODE, else the code.cmd beside the Code.exe that is running - the
    # VS Code whose windows these are - else code on PATH (an Application,
    # never a function or alias), else where the user and system installers
    # put it. Running first: a machine can hold two installs, and PATH may
    # name the other. Here a system install left half-updated since February
    # came first on PATH, its code.cmd starting a Code.exe with no ICU data
    # beside it, which crashed every time (0x80000003) - while the per-user
    # install ran every window. Reading VS Code's install place is not
    # runtime data of ours.
    if ($env:CHATQ_CODE) { return $env:CHATQ_CODE }
    foreach ($exe in @(Get-ChatRunningCodeExes)) {
        foreach ($n in 'code.cmd', 'code-insiders.cmd') {
            $b = Join-Path (Join-Path (Split-Path $exe -Parent) 'bin') $n
            if (Test-Path -LiteralPath $b) { return $b }
        }
    }
    $c = Get-Command code -CommandType Application -EA SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in @(
            $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd' }),
            $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd' }))) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Get-ChatCodeEnvDrops {
    # What a child that starts code must not inherit. Run from inside a VS
    # Code terminal, or a Claude Code session's shell, VS Code's own VSCODE_*
    # and ELECTRON_* variables would reach the Code.exe that code.cmd starts
    # and speak for a process that is not its own. S29 blamed them for an
    # "Invalid file descriptor to ICU data" crash; that was a broken install
    # instead (Find-ChatCodeCommand), and it crashed with none of them.
    # code.cmd sets ELECTRON_RUN_AS_NODE again itself. Pure.
    param([string[]]$Names)
    return @($Names | Where-Object { $_ -match '^(VSCODE_|ELECTRON_)' })
}

function Get-ChatCodeLaunch {
    <#
    How to run code -n <folder>: @{ Exe; Arguments }, or $null when it cannot
    go on a command line safely. code.cmd runs through cmd.exe: inside its
    quotes & ^ and | are literal, and /v:off makes ! literal too, but % and "
    have no escape there at all, so a path holding either is refused. An .exe
    (CHATQ_CODE), or anything off Windows, is started directly. Pure.
    #>
    param([string]$Code, [string]$Folder, [bool]$Windows = $script:ChatqIsWindows)
    if (-not $Code -or -not $Folder) { return $null }
    if ($Code -match '\.exe$' -or -not $Windows) {
        return [pscustomobject]@{ Exe = $Code; Arguments = (ConvertTo-ChatqArgLine @('-n', $Folder)) }
    }
    if ("$Code$Folder" -match '[%"\r\n]') { return $null }
    # a trailing backslash would escape the quote after it, as Code.exe reads it
    if ($Folder.EndsWith('\')) { $Folder += '.' }
    $shell = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
    return [pscustomobject]@{ Exe = $shell; Arguments = '/d /s /v:off /c ""' + $Code + '" -n "' + $Folder + '""' }
}

function Open-ChatCodeWindow {
    <#
    code -n <folder>: VS Code brings forward the window that has that folder
    open, or opens a new one on it. -n keeps it from reusing an unrelated
    window when window.openFoldersInNewWindow is off; reusing one would close
    that window's folder. Nothing here moves the pointer, types, or calls a
    window API - VS Code raises its own window. The vscode:// link would do
    it without code on PATH, but asks first when opened from outside.
    Returns @{ Ok; Code (ok, no-code, code-failed); Why; Slow }.
    #>
    param([string]$Folder)
    if ($script:ChatCodeSeam) { return (& $script:ChatCodeSeam $Folder) }   # tests
    $fail = { param($c, $w) Write-ChatqWatchLog "open: $w"; [pscustomobject]@{ Ok = $false; Code = $c; Why = $w; Slow = $false } }
    $code = Find-ChatCodeCommand
    if (-not $code) { return (& $fail 'no-code' 'no code command - VS Code''s bin folder on PATH, or CHATQ_CODE, finds it') }
    $l = Get-ChatCodeLaunch $code $Folder
    if (-not $l) { return (& $fail 'code-failed' "cannot hand $Folder to $code") }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $l.Exe
        $psi.Arguments = $l.Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        foreach ($n in @(Get-ChatCodeEnvDrops @($psi.EnvironmentVariables.Keys))) { $psi.EnvironmentVariables.Remove($n) }
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(20000)) {
            Write-ChatqWatchLog 'open: code still running after 20 s - left to it'
            return [pscustomobject]@{ Ok = $true; Code = 'ok'; Why = $null; Slow = $true }
        }
        if ($p.ExitCode -ne 0) { return (& $fail 'code-failed' "code exited $($p.ExitCode) - $code") }
        return [pscustomobject]@{ Ok = $true; Code = 'ok'; Why = $null; Slow = $false }
    }
    catch { return (& $fail 'code-failed' "code: $($_.Exception.Message) - $code") }
}

#endregion
