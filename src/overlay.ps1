# VS-code-chat-manager, src/overlay.ps1: dot-sourced by VS-code-chat-manager.ps1
# in its turn, never on its own - see the list there.

#region overlay: the command ---------------------------------------------------

function Test-ChatOverlayAlive {
    return (Test-ChatqLockHeld $script:ChatOverlayLockPath)
}

function Test-ChatOverlayAutoStart {
    # chatoverlay -AutoStart on, on a system with a panel to draw
    if (-not $script:ChatqIsWindows -and -not $script:ChatIsMac) { return $false }
    if (-not (Test-Path -LiteralPath $script:ChatqConfigPath)) { return $false }
    return [bool](Get-ChatOverlayConfig).autoStart
}

function ConvertFrom-ChatOverlayHotkey {
    <#
    'Ctrl+Alt+Shift+O' -> @{ Mods; Vk; Text } for RegisterHotKey, and 'none'
    -> $null. Throws on anything it cannot read, so a typo shows when it is
    set rather than when the overlay next starts.
    #>
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if (-not $t -or $t -eq 'none') { return $null }
    $mods = 0
    $vk = $null
    foreach ($p in @($t -split '\+' | ForEach-Object { $_.Trim() })) {
        if ($p -match '^(ctrl|control)$') { $mods = $mods -bor 2 }
        elseif ($p -eq 'alt') { $mods = $mods -bor 1 }
        elseif ($p -eq 'shift') { $mods = $mods -bor 4 }
        elseif ($p -match '^win(dows)?$') { $mods = $mods -bor 8 }
        elseif ($p -match '^f([1-9]|1[0-9]|2[0-4])$') { $vk = 0x6F + [int]$Matches[1] }
        elseif ($p -match '^[a-z]$') { $vk = [int][char]$p.ToUpperInvariant() }
        elseif ($p -match '^[0-9]$') { $vk = 0x30 + [int]$p }
        else { throw "cannot read '$p' in hotkey '$t' - use e.g. Ctrl+Alt+Shift+O, Ctrl+Win+F9 or none" }
    }
    if ($null -eq $vk) { throw "hotkey '$t' names no key - e.g. Ctrl+Alt+Shift+O" }
    if (-not $mods) { throw "hotkey '$t' needs Ctrl, Alt, Shift or Win with the key" }
    return @{ Mods = $mods; Vk = $vk; Text = $t }
}

function Get-ChatOverlayLaunch {
    <#
    How the overlay process is started: @{ Exe; Args; Command }. On Windows
    always Windows PowerShell with -STA, even from pwsh: WPF needs an STA
    thread, and every Windows has powershell.exe. The command carries the
    environment it needs, and a failure before the log function exists still
    reaches the log. -Open console: the console opens as it starts - a
    command left for it now would be swept away as it takes its lock.
    #>
    param([string]$Path = $script:ChatqScriptPath, [ValidateSet('', 'console')][string]$Open = '')
    $q = { param($s) "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$s) + "'" }
    $pre = '$env:CHATQ_OVERLAY=''1''; '
    foreach ($n in 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'CHATQ_CLAUDE', 'CHATQ_CODEX', 'CHATQ_GH') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $pre += "`$env:$n=$(& $q $v); " }
    }
    $entry = if ($script:ChatqIsWindows) { "Start-ChatOverlayHost$(if ($Open) { " -Open '$Open'" })" } else { 'Start-ChatOverlayMacHost' }
    $log = Join-Path $script:ChatqLogDir 'overlay.log'
    $cmd = $pre + "try { . $(& $q $Path); $entry } catch { try { [void][IO.Directory]::CreateDirectory($(& $q $script:ChatqLogDir)); " +
    "[IO.File]::AppendAllText($(& $q $log), (Get-Date).ToString('o') + '  overlay failed to start: ' + `$_.Exception.Message + [char]10) } catch {} }"
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    if ($script:ChatqIsWindows) {
        $root = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
        $exe = Join-Path $root 'System32\WindowsPowerShell\v1.0\powershell.exe'
        return [pscustomobject]@{ Exe = $exe; Args = @('-NoProfile', '-NonInteractive', '-STA', '-EncodedCommand', $enc); Command = $cmd }
    }
    return [pscustomobject]@{ Exe = (Get-Process -Id $PID).Path; Args = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc); Command = $cmd }
}

function Start-ChatOverlayProcess {
    # just the launch; chatoverlay decides whether one is needed
    param([string]$Open = '')
    if ($script:ChatOverlaySpawn) { return (& $script:ChatOverlaySpawn) }   # tests: no real process
    if (-not $script:ChatqIsWindows -and -not $script:ChatIsMac) { return $false }
    $path = $script:ChatqScriptPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        Write-Host '  cannot start the overlay: this shell does not know where VS-code-chat-manager.ps1 is' -ForegroundColor Yellow
        return $false
    }
    $l = Get-ChatOverlayLaunch $path -Open $Open
    try {
        if ($script:ChatqIsWindows) { Start-Process -FilePath $l.Exe -ArgumentList $l.Args -WindowStyle Hidden | Out-Null }
        else {
            New-ChatqDir $script:ChatqLogDir
            Start-Process -FilePath 'nohup' -ArgumentList (@($l.Exe) + $l.Args) `
                -RedirectStandardOutput (Join-Path $script:ChatqLogDir 'overlay.out') `
                -RedirectStandardError (Join-Path $script:ChatqLogDir 'overlay.err') | Out-Null
        }
    }
    catch {
        Write-Host "  cannot start the overlay: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Stop-ChatOverlay {
    # $true once it has let go of its lock
    if (-not (Test-ChatOverlayAlive)) { return $true }
    Send-ChatOverlayCommand 'stop'
    $until = (Get-Date).AddMilliseconds($script:ChatOverlayStopWaitMs)
    while ((Get-Date) -lt $until) {
        Start-Sleep -Milliseconds 200
        if (-not (Test-ChatOverlayAlive)) { return $true }
    }
    return $false
}

function chatoverlay {
    <#
    .SYNOPSIS
    A small always-on-top panel: usage live at the top, every open Claude chat and the queue beneath.
    .DESCRIPTION
    Each open chat is a row: project, title, its newest prompt, and whether it
    is working (green), waiting on you (amber, at the top), or idle (grey).
    Chats the limit cut off are orange, with when it resets. Queued prompts
    are rows too (purple), or ride on their chat's row when it is open. Usage sits at the top, a line for each of Claude, Codex and
    Copilot, each ending with when its figure is from - or as bars with a
    countdown to each reset. Claude's is asked live from its usage endpoint
    every five minutes while a chat works, every fifteen while all are idle,
    and on the refresh button; Copilot's through the GitHub CLI (gh) every
    fifteen; Codex's is what Codex wrote on its last run.

    Clicks go through it and it never takes focus. On Windows the pointer
    brings up a row of buttons over its top-right corner: a grip to drag it by, collapse to
    one line, refresh usage, the console (chatconsole), settings (opacity, theme,
    usage as lines or bars), hide to the tray -
    the tray dot shows it again - and close. The hotkey (Ctrl+Alt+Shift+O)
    or the tray menu unlocks the whole panel to drag; it locks again by
    itself two minutes after the pointer leaves. Windows and macOS
    (untested); elsewhere -Print shows the same in the console.
    .PARAMETER Stop
    Close it.
    .PARAMETER Unlock
    Take the mouse, to drag it somewhere else. -Lock lets clicks through again.
    .PARAMETER Reset
    Back to the main screen's top-right corner.
    .PARAMETER Collapse
    Down to one line: how many chats wait, work or idle, and usage. -Expand undoes it.
    .PARAMETER Refresh
    Ask Claude's usage endpoint now - unless it said to wait, which the panel shows.
    .PARAMETER Print
    One pass, drawn in this console.
    .PARAMETER AutoStart
    on: start it with every new shell, the way the watcher comes back after a reboot.
    .PARAMETER Hotkey
    The key that unlocks it or shows it: Ctrl+Alt+Shift+O by default, none for no key.
    .PARAMETER LiveUsage
    off: show only Claude Code's own cached usage figure, and never ask the endpoint.
    .PARAMETER Theme
    dark (the default), light, or system - following the OS's own light or dark setting.
    .PARAMETER Opacity
    How opaque the panel is, 0.3 to 1 - or as a percent, 30 to 100.
    .PARAMETER Console
    Open the console: pick a chat, write to it, drop files on it, send now or queue; the queue beside it. Starts the overlay if it is not running. Windows only.
    .PARAMETER ConsoleHotkey
    The key that opens the console: Ctrl+Alt+Shift+Q by default, none for no key.
    .PARAMETER UsageView
    lines (the default): usage as one line a provider. bars: a bar and a reset countdown per window.
    .PARAMETER CopilotUsage
    off: no Copilot line, and gh is never run for it.
    .EXAMPLE
    chatoverlay
    .EXAMPLE
    chatoverlay -AutoStart on
    .EXAMPLE
    chatoverlay -Theme system -Opacity 85
    #>
    [CmdletBinding()]
    param(
        [switch]$Stop, [switch]$Unlock, [switch]$Lock, [switch]$Reset, [switch]$Print,
        [switch]$Collapse, [switch]$Expand, [switch]$Refresh, [switch]$Console,
        [ValidateSet('on', 'off')][string]$AutoStart,
        [string]$Hotkey,
        [string]$ConsoleHotkey,
        [ValidateSet('on', 'off')][string]$LiveUsage,
        [ValidateSet('dark', 'light', 'system')][string]$Theme,
        [double]$Opacity,
        [ValidateSet('lines', 'bars')][string]$UsageView,
        [ValidateSet('on', 'off')][string]$CopilotUsage
    )
    Set-StrictMode -Off
    if ($Print) { Write-ChatOverlayPrint; return }
    $alive = Test-ChatOverlayAlive
    if ($Stop) {
        if (-not $alive) { Write-Host '  the overlay is not running' -ForegroundColor DarkGray; return }
        if (Stop-ChatOverlay) { Write-Host '  overlay closed' -ForegroundColor DarkGray }
        else { Write-Host '  asked the overlay to close - it has not yet; data/logs/overlay.log may say why' -ForegroundColor Yellow }
        return
    }
    $set = @{}
    if ($AutoStart) { $set.autoStart = ($AutoStart -eq 'on') }
    if ($LiveUsage) { $set.liveUsage = ($LiveUsage -eq 'on') }
    if ($Theme) { $set.theme = $Theme.ToLowerInvariant() }
    if ($UsageView) { $set.usageView = $UsageView.ToLowerInvariant() }
    if ($CopilotUsage) { $set.copilotUsage = ($CopilotUsage -eq 'on') }
    if ($PSBoundParameters.ContainsKey('Opacity')) {
        $o = if ($Opacity -gt 1) { $Opacity / 100 } else { $Opacity }
        if ($o -lt 0.3 -or $o -gt 1) { Write-Host '  -Opacity takes 0.3 to 1, or 30 to 100 as a percent' -ForegroundColor Yellow; return }
        $set.opacity = [Math]::Round($o, 2)
    }
    if ($PSBoundParameters.ContainsKey('Hotkey')) {
        try { $k = ConvertFrom-ChatOverlayHotkey $Hotkey }
        catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; return }
        $set.hotkey = if ($k) { $k.Text } else { 'none' }
    }
    if ($PSBoundParameters.ContainsKey('ConsoleHotkey')) {
        try { $k = ConvertFrom-ChatOverlayHotkey $ConsoleHotkey }
        catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; return }
        $set.consoleHotkey = if ($k) { $k.Text } else { 'none' }
    }
    if ($set.Count) {
        Set-ChatOverlayConfig $set
        if ($set.ContainsKey('autoStart')) { Write-Host "  start with every shell: $AutoStart" -ForegroundColor Green }
        if ($set.ContainsKey('liveUsage')) { Write-Host "  live usage: $LiveUsage" -ForegroundColor Green }
        if ($set.ContainsKey('hotkey')) { Write-Host "  hotkey: $($set.hotkey)" -ForegroundColor Green }
        if ($set.ContainsKey('consoleHotkey')) { Write-Host "  console hotkey: $($set.consoleHotkey)" -ForegroundColor Green }
        if ($set.ContainsKey('theme')) { Write-Host "  theme: $($set.theme)" -ForegroundColor Green }
        if ($set.ContainsKey('opacity')) { Write-Host "  opacity: $([int]($set.opacity * 100))%" -ForegroundColor Green }
        if ($set.ContainsKey('usageView')) { Write-Host "  usage as $($set.usageView)" -ForegroundColor Green }
        if ($set.ContainsKey('copilotUsage')) { Write-Host "  Copilot usage: $CopilotUsage$(if ($CopilotUsage -eq 'on') { ' - through the GitHub CLI, gh, when it is logged in' })" -ForegroundColor Green }
        if ($alive) { Send-ChatOverlayCommand 'reload' }
    }
    $verbs = @()
    if ($Unlock) { $verbs += 'unlock' }
    if ($Lock) { $verbs += 'lock' }
    if ($Reset) { $verbs += 'reset' }
    if ($Collapse) { $verbs += 'collapse' }
    if ($Expand) { $verbs += 'expand' }
    if ($verbs) {
        if ($alive) { foreach ($v in $verbs) { Send-ChatOverlayCommand $v } }
        else {
            # not running: left the way the next start will read it
            $st = Read-ChatOverlayState
            if ($Unlock) { $st.locked = $false }
            if ($Lock) { $st.locked = $true }
            if ($Reset) { $st.x = $null; $st.y = $null }
            if ($Collapse) { $st.collapsed = $true }
            if ($Expand) { $st.collapsed = $false }
            Save-ChatOverlayState $st
        }
        Write-Host "  $($verbs -join ', ')$(if (-not $alive) { ' - applies when it next starts' })" -ForegroundColor DarkGray
    }
    if ($Refresh) {
        # a wait the endpoint named: said here, not asked through
        $snapNow = Read-ChatqJson $script:ChatOverlayPath
        $held = if ($snapNow -and $snapNow.PSObject.Properties['header'] -and $snapNow.header.PSObject.Properties['liveHold'] -and $snapNow.header.liveHold) { [int64]$snapNow.header.liveHold } else { 0 }
        if ($held -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) {
            $until = [DateTimeOffset]::FromUnixTimeMilliseconds($held).LocalDateTime.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
            Write-Host "  Claude's usage endpoint asked to wait until $until - asking earlier only gets refused again" -ForegroundColor Yellow
        }
        elseif ($alive) { Send-ChatOverlayCommand 'refresh'; Write-Host "  asked Claude for usage now - it shows within a few seconds. Codex's moves only when Codex runs." -ForegroundColor DarkGray }
        else { Write-Host '  the overlay is not running - chatoverlay -Print asks once' -ForegroundColor DarkGray }
    }
    if ($Console) {
        if (-not $script:ChatqIsWindows) { Write-Host '  the console is Windows only for now - chatq, chatqlist and chatqrm do the same from a shell' -ForegroundColor Yellow; return }
        # Windows gives the focus to what the user started; a running overlay
        # only told to open it may just flash its taskbar button
        if ($alive) { Send-ChatOverlayCommand 'console'; Write-Host '  the console opens in the running overlay - its taskbar button, if it stays behind' -ForegroundColor DarkGray }
        elseif (Start-ChatOverlayProcess -Open 'console') { Write-Host '  starting the overlay with its console - a few seconds' -ForegroundColor DarkGray }
        return
    }
    if ($set.Count -or $verbs -or $Refresh) { return }

    if (-not $script:ChatqIsWindows -and -not $script:ChatIsMac) {
        Write-Host '  the panel is Windows and macOS only - chatoverlay -Print shows the same here' -ForegroundColor Yellow
        return
    }
    if ($alive) {
        Send-ChatOverlayCommand 'show'
        Write-Host '  the overlay is running - shown' -ForegroundColor DarkGray
    }
    else {
        # asked for by name: shown, even if it was hidden when it last closed
        $st = Read-ChatOverlayState
        if ($st.hidden) { $st.hidden = $false; Save-ChatOverlayState $st }
        if (-not (Start-ChatOverlayProcess)) { return }
        $up = $false
        for ($i = 0; $i -lt 40 -and -not $up; $i++) { Start-Sleep -Milliseconds 250; $up = Test-ChatOverlayAlive }
        if (-not $up) {
            Write-Host '  the overlay did not start - data/logs/overlay.log may say why' -ForegroundColor Yellow
            return
        }
        Write-Host '  overlay started - top right of the main screen' -ForegroundColor Green
        if ($script:ChatIsMac) { Write-Host '  macOS support is untested - TESTING.md lists what to check' -ForegroundColor DarkGray }
    }
    if ($script:ChatqIsWindows) { Write-Host '  clicks go through it - point at it for its buttons: move, collapse, refresh, console, settings, hide, close' -ForegroundColor DarkGray }
    else { Write-Host '  clicks go through it - the CQ menu bar item unlocks it to drag' -ForegroundColor DarkGray }
    Write-Host "  chatoverlay -Stop closes it $($script:ChatqDot) -AutoStart on brings it back with every shell" -ForegroundColor DarkGray
}

function chatconsole {
    <#
    .SYNOPSIS
    chatq in a window: pick a chat, write to it, drop files on it, send now or queue it.
    .DESCRIPTION
    The chats cut off by the limit (Continue, or Continue all), the ones open
    in VS Code, and the recent ones, with a search; + New chat starts one in
    a folder. Send now runs the prompt within seconds - once the chat is idle
    if it is working in VS Code - and In turn, At or In queue it. The queue
    sits below: each job's outcome and log, Try now, First, Remove, Cancel,
    Requeue. It is the overlay's window, so this starts the overlay if it is
    not running. Windows only. Ctrl+Alt+Shift+Q, the overlay's speech-bubble
    button and the tray menu open it too.
    #>
    Set-StrictMode -Off
    chatoverlay -Console
}

#endregion
