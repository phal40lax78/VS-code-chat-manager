# VS-code-chat-manager, src/overlay-data.ps1: dot-sourced by VS-code-chat-manager.ps1
# in its turn, never on its own - see the list there.

#region overlay: configuration -------------------------------------------------
# chatoverlay: a small always-on-top panel with usage live at the top, then
# every open Claude chat - project, title, newest prompt, and whether it is
# working, waiting on you or idle - and the queue under them. A collector with
# no UI builds a snapshot, and a renderer draws it: WPF on Windows, a JXA
# panel on macOS. Nothing it does changes a chat, a job or the config; the
# only files it writes are its own, below.

$script:ChatOverlayPath = Join-Path $script:ChatqData 'overlay.json'
$script:ChatOverlayStatePath = Join-Path $script:ChatqData 'overlay-state.json'
$script:ChatOverlayLockPath = Join-Path $script:ChatqData 'overlay.lock'
$script:ChatOverlayPidPath = Join-Path $script:ChatqData 'overlay.pid'
$script:ChatOverlayCmdPath = Join-Path $script:ChatqData 'overlay-cmd'
$script:ChatOverlayMacJsPath = Join-Path $script:ChatqData 'overlay-mac.js'
# Claude's usage endpoint: what /usage and the panel's usage view ask
$script:ChatOverlayUsageUrl = 'https://api.anthropic.com/api/oauth/usage'
# how far back a first read of one transcript goes looking for its prompt
$script:ChatOverlayScanBudget = 16MB
# how long one pass may spend reading transcripts before it leaves the rest
# for the next: the Windows panel draws on the same thread
$script:ChatOverlaySliceMs = 250
$script:ChatOverlayStopWaitMs = 8000
# A row's prompt line while its chat runs a command not yet written down.
# Nothing on disk names it until it ends, so it is not guessed at.
$script:ChatOverlayPendingText = 'command running'
$script:ChatOverlayHost = $null
$script:ChatOverlayBrushes = @{}
$script:ChatOverlayLogSeen = @{}
# tests: bytes the transcript reader took, a stand-in launch, a stand-in
# usage endpoint
$script:ChatOverlayBytesRead = 0
$script:ChatOverlaySpawn = $null
$script:ChatOverlayUsageSeam = $null
# tests: a stand-in for gh's answer about Copilot
$script:ChatOverlayCopilotSeam = $null
# tests: stands in for Windows' own light or dark setting
$script:ChatOverlaySystemDarkSeam = $null
# tests: the screen under the panel, given its rect, so the buttons can be
# placed on a screen that is not there
$script:ChatOverlayWorkAreaSeam = $null

function Get-ChatOverlayConfig {
    # config.json -> overlay, with the defaults filled in and every number
    # held to a range the panel can draw. What the user chose lives here:
    # shell commands write it, and the panel's settings box its opacity and
    # theme. Where the panel sits is overlay-state.json.
    param($Cfg)
    if (-not $Cfg) { $Cfg = Get-ChatqConfig }
    $o = if ($Cfg.PSObject.Properties['overlay'] -and $Cfg.overlay) { $Cfg.overlay } else { [pscustomobject]@{} }
    $get = { param($n, $d) if ($o.PSObject.Properties[$n] -and $null -ne $o.$n) { $o.$n } else { $d } }
    $clamp = { param($v, $lo, $hi) [Math]::Max($lo, [Math]::Min($hi, $v)) }
    $theme = ([string](& $get 'theme' 'dark')).ToLowerInvariant()
    $view = ([string](& $get 'usageView' 'lines')).ToLowerInvariant()
    [pscustomobject]@{
        width        = [int](& $clamp ([int](& $get 'width' 380)) 260 800)
        maxRows      = [int](& $clamp ([int](& $get 'maxRows' 8)) 1 30)
        opacity      = [double](& $clamp ([double](& $get 'opacity' 0.94)) 0.3 1.0)
        # dark, light, or system - Windows' own app mode, or macOS's
        theme        = $(if ($theme -in 'dark', 'light', 'system') { $theme } else { 'dark' })
        prompts      = [bool](& $get 'prompts' $true)
        hotkey       = [string](& $get 'hotkey' 'Ctrl+Alt+Shift+O')
        # the one that opens the console
        consoleHotkey = [string](& $get 'consoleHotkey' 'Ctrl+Alt+Shift+Q')
        autoStart    = [bool](& $get 'autoStart' $false)
        # a Mac keeps the login in the keychain, whose first read by another
        # program puts up a password prompt - so there only when asked for
        liveUsage    = [bool](& $get 'liveUsage' (-not $script:ChatIsMac))
        usageSeconds = [int](& $clamp ([int](& $get 'usageSeconds' 300)) 60 3600)
        # usage as one line per provider, or the bars with reset countdowns
        usageView    = $(if ($view -in 'lines', 'bars') { $view } else { 'lines' })
        # Copilot's monthly quota through the GitHub CLI, where there is one
        copilotUsage = [bool](& $get 'copilotUsage' $true)
        # chats the limit or a 529 stopped, marked, and a row for one not open
        cutOff       = [bool](& $get 'cutOff' $true)
    }
}

function Set-ChatOverlayConfig {
    param([hashtable]$Values)
    $cfg = Get-ChatqConfig
    $o = if ($cfg.PSObject.Properties['overlay'] -and $cfg.overlay) { $cfg.overlay } else { [pscustomobject]@{} }
    foreach ($k in $Values.Keys) { Set-ChatqProp $o $k $Values[$k] }
    Set-ChatqProp $cfg 'overlay' $o
    Save-ChatqJson $script:ChatqConfigPath $cfg
    if (-not $script:ChatqIsWindows) { try { & chmod 600 $script:ChatqConfigPath } catch {} }
}

function Test-ChatOverlaySystemDark {
    # Windows' app mode: AppsUseLightTheme 0 is dark. Missing - before
    # Windows 10 1809, or off Windows - is light, the default then.
    if ($script:ChatOverlaySystemDarkSeam) { return [bool](& $script:ChatOverlaySystemDarkSeam) }
    try { return ([int](Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -EA Stop) -eq 0) }
    catch { return $false }
}

function Resolve-ChatOverlayTheme {
    # dark, light or system -> the one the panel draws in
    param([string]$Theme)
    if ($Theme -eq 'light') { return 'light' }
    if ($Theme -eq 'system') { if (Test-ChatOverlaySystemDark) { return 'dark' } else { return 'light' } }
    return 'dark'
}

function Read-ChatOverlayState {
    # where the panel sits and how it was left - written by the panel alone
    $s = Read-ChatqJson $script:ChatOverlayStatePath
    $p = { param($n, $d) if ($s -and $s.PSObject.Properties[$n] -and $null -ne $s.$n) { $s.$n } else { $d } }
    [pscustomobject]@{ x = & $p 'x' $null; y = & $p 'y' $null; locked = [bool](& $p 'locked' $true); hidden = [bool](& $p 'hidden' $false)
        collapsed = [bool](& $p 'collapsed' $false) }
}

function Save-ChatOverlayState {
    param($State)
    try { Save-ChatqJson $script:ChatOverlayStatePath $State } catch {}
}

function Write-ChatOverlayLog {
    # data/logs/overlay.log, rolled at 1 MB. The same line at most once in
    # 5 minutes: a pass runs every 2 s, and one lasting fault would otherwise
    # fill the file with itself.
    param([string]$Text)
    try {
        $last = $script:ChatOverlayLogSeen[$Text]
        if ($last -and ((Get-Date) - $last).TotalMinutes -lt 5) { return }
        $script:ChatOverlayLogSeen[$Text] = Get-Date
        New-ChatqDir $script:ChatqLogDir
        $p = Join-Path $script:ChatqLogDir 'overlay.log'
        if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).Length -gt 1MB) { Move-Item -LiteralPath $p -Destination "$p.1" -Force }
        [System.IO.File]::AppendAllText($p, "$((Get-Date).ToString('o'))  $Text`n", (New-Object System.Text.UTF8Encoding $false))
    }
    catch {}
}

function ConvertTo-ChatOverlayMs {
    # epoch milliseconds, which is what the snapshot carries for every time -
    # the one form both renderers read the same way
    param($When)
    if ($null -eq $When -or '' -eq $When) { return $null }
    if ($When -is [datetime]) { return [DateTimeOffset]::new($When).ToUnixTimeMilliseconds() }
    try { return [int64]$When } catch { return $null }
}

#endregion

#region overlay: usage ---------------------------------------------------------
# Usage for the top of the overlay. Claude's comes live from its usage
# endpoint: Claude Code caches the same answer in .claude.json, but only when
# something asks for /usage, and that copy was hours old while the account
# climbed from 55% to 79%. The cache stays the fallback, marked with its age.
# Codex's comes from its newest rollout, which it rewrites every turn.

function ConvertFrom-ChatqUtilization {
    <#
    One Claude account's usage windows, from what the usage endpoint answers -
    live, or as Claude Code cached it, which is the same shape. limits[] is
    the server's own list, with its own reading of each row (severity), so the
    colour is never guessed here; the older five_hour / seven_day fields stand
    in when it is absent.
    #>
    param($U)
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not $U) { return @() }
    if ($U.PSObject.Properties['limits'] -and $U.limits) {
        foreach ($l in @($U.limits)) {
            if (-not $l) { continue }
            $p = [double]$l.percent
            $scoped = $l.PSObject.Properties['scope'] -and $l.scope
            $label = switch ([string]$l.kind) {
                'session' { '5h' }
                'five_hour' { '5h' }
                { $_ -in 'weekly_all', 'seven_day', 'weekly' } { 'week' }
                default {
                    # one model's weekly window - worth a line only once used
                    if ($scoped -and $p -gt 0 -and $l.scope.model -and $l.scope.model.display_name) { "$($l.scope.model.display_name) week" }
                }
            }
            if (-not $label) { continue }
            $sev = if ($l.PSObject.Properties['severity']) { [string]$l.severity } else { '' }
            $out.Add([pscustomobject]@{ Label = [string]$label; Percent = $p; ResetsAt = (ConvertTo-ChatqDate $l.resets_at); Severity = $sev })
        }
        return $out.ToArray()
    }
    foreach ($w in @(@{ Name = 'five_hour'; Label = '5h' }, @{ Name = 'seven_day'; Label = 'week' })) {
        $v = if ($U.PSObject.Properties[$w.Name]) { $U.($w.Name) } else { $null }
        if (-not $v -or $null -eq $v.utilization) { continue }
        $out.Add([pscustomobject]@{ Label = $w.Label; Percent = [double]$v.utilization; ResetsAt = (ConvertTo-ChatqDate $v.resets_at); Severity = '' })
    }
    return $out.ToArray()
}

function ConvertFrom-ChatqCodexLimits {
    # Codex's rate_limits: used_percent, window_minutes and resets_at (epoch s)
    # per window. Which window is primary varies by plan, so its length is
    # what names it.
    param($R)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($w in @($R.primary, $R.secondary)) {
        if (-not $w -or $null -eq $w.used_percent) { continue }
        $m = [int]$w.window_minutes
        $label = if ($m -le 300) { '5h' } elseif ($m -le 10080) { 'week' } else { 'month' }
        $at = if ($w.resets_at) { [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$w.resets_at).LocalDateTime } else { $null }
        $out.Add([pscustomobject]@{ Label = $label; Percent = [double]$w.used_percent; ResetsAt = $at; Severity = '' })
    }
    return $out.ToArray()
}

function ConvertFrom-ChatqCopilotQuota {
    <#
    GitHub's answer for Copilot (copilot_internal/user, what VS Code's own
    Copilot status reads): quota_snapshots per kind, each with
    percent_remaining, and one quota_reset_date for the month. A kind that
    is unlimited, or not in the plan at all (entitlement 0 - premium on
    Copilot Free), is left out. Premium first: on a paid plan it is the only
    one that runs out.
    #>
    param($U)
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not $U -or -not $U.PSObject.Properties['quota_snapshots'] -or -not $U.quota_snapshots) { return $out.ToArray() }
    $reset = $null
    if ($U.PSObject.Properties['quota_reset_date'] -and $U.quota_reset_date) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact([string]$U.quota_reset_date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$d)) { $reset = $d.ToLocalTime() }
    }
    foreach ($k in @(@('premium_interactions', 'premium'), @('chat', 'chat'), @('completions', 'code'))) {
        $p = $U.quota_snapshots.PSObject.Properties[$k[0]]
        $s = if ($p) { $p.Value } else { $null }
        if (-not $s -or $s.unlimited -or -not [double]$s.entitlement -or $null -eq $s.percent_remaining) { continue }
        # 0.0, not 0: Max(0, 0.1) is the integer one, and 0.1 came back as 0
        $out.Add([pscustomobject]@{ Label = $k[1]; Percent = [Math]::Max(0.0, 100 - [double]$s.percent_remaining); ResetsAt = $reset; Severity = '' })
    }
    return $out.ToArray()
}

function Start-ChatqCopilotFetch {
    <#
    Ask GitHub for Copilot's quota through the GitHub CLI: gh api
    copilot_internal/user. gh keeps its own login and hands none of it over -
    this process never sees a token. Not waited on: the Windows panel draws
    on this thread. No gh (CHATQ_GH names another), or one not logged in,
    means no Copilot line.
    #>
    if ($script:ChatOverlayCopilotSeam) { return @{ Done = (& $script:ChatOverlayCopilotSeam) } }   # tests
    $gh = if ($env:CHATQ_GH) { $env:CHATQ_GH } else { Get-Command gh -CommandType Application -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty Source }
    if (-not $gh -or -not (Test-Path -LiteralPath $gh)) { return @{ Done = @{ Ok = $false; Status = 0; Why = 'no GitHub CLI'; Quiet = $true } } }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($gh, 'api copilot_internal/user')
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $p = [System.Diagnostics.Process]::Start($psi)
        return @{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync(); At = (Get-Date) }
    }
    catch { return @{ Done = @{ Ok = $false; Status = 0; Why = "gh: $($_.Exception.Message)" } } }
}

function Complete-ChatqCopilotFetch {
    # $null while gh is still at it; else @{ Ok; Windows | Why; Quiet }. -WaitMs
    # waits up to that long first. One stuck for 20 s is ended.
    param($Fetch, [int]$WaitMs = 0)
    if ($Fetch.Done) { return $Fetch.Done }
    $p = $Fetch.Proc
    if (-not $p.HasExited -and $WaitMs -gt 0) { [void]$p.WaitForExit($WaitMs) }
    if (-not $p.HasExited) {
        if (((Get-Date) - $Fetch.At).TotalSeconds -lt 20) { return $null }
        try { $p.Kill() } catch {}
        try { $p.Dispose() } catch {}
        return @{ Ok = $false; Status = 0; Why = 'gh gave no answer in 20 s' }
    }
    $res = $null
    try {
        [void]$p.WaitForExit()
        $text = [string]$Fetch.Out.Result
        $err = [string]$Fetch.Err.Result
        if ($p.ExitCode -ne 0) {
            # not logged in, or no Copilot on the account: no line, and no nagging
            $quiet = $err -match 'gh auth login|HTTP 404|HTTP 401'
            $why = (@($err -split "`n" | Where-Object { $_.Trim() }) | Select-Object -First 1)
            $res = @{ Ok = $false; Status = $p.ExitCode; Why = "gh: $why"; Quiet = $quiet }
        }
        else {
            $u = try { $text | ConvertFrom-Json } catch { $null }
            $w = @(ConvertFrom-ChatqCopilotQuota $u)
            $res = if ($w) { @{ Ok = $true; Windows = $w } } else { @{ Ok = $false; Status = 0; Why = 'no Copilot quota in the answer'; Quiet = $true } }
        }
    }
    catch { $res = @{ Ok = $false; Status = 0; Why = "gh: $($_.Exception.Message)" } }
    finally { try { $p.Dispose() } catch {} }
    return $res
}

function Get-ChatqClaudeJsonPath {
    # .claude.json sits beside the config dir by default (~/.claude.json) and
    # inside it when CLAUDE_CONFIG_DIR moves it
    param([string]$ClaudeHome = $script:ChatClaudeHome)
    if ($ClaudeHome -and $ClaudeHome.TrimEnd('\', '/') -ne (Join-Path $HOME '.claude')) { return (Join-Path $ClaudeHome '.claude.json') }
    return (Join-Path $HOME '.claude.json')
}

function Get-ChatqClaudeToken {
    <#
    The OAuth access token Claude Code saved when you logged in, read for one
    request and held nowhere else: never logged, never written, never handed
    to a child process. Never refreshed either - a refresh rotates the
    refresh token too, which would sign Claude Code itself out. An expired one
    means no live figure until Claude Code next runs and renews it; the cached
    figure shows meanwhile. Windows and Linux keep it in
    <config dir>/.credentials.json, macOS in the login keychain.
    #>
    param([string]$ClaudeHome = $script:ChatClaudeHome)
    $raw = $null
    $file = Join-Path $ClaudeHome '.credentials.json'
    if (Test-Path -LiteralPath $file) { $raw = try { [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) } catch { $null } }
    elseif ($script:ChatIsMac) { $raw = try { (& security find-generic-password -s 'Claude Code-credentials' -w 2>$null) -join "`n" } catch { $null } }
    if (-not $raw) { return @{ Token = $null; Why = 'no Claude login found' } }
    $o = try { $raw | ConvertFrom-Json } catch { $null }
    $c = if ($o -and $o.PSObject.Properties['claudeAiOauth']) { $o.claudeAiOauth } else { $null }
    if (-not $c -or -not $c.accessToken) { return @{ Token = $null; Why = 'no Claude login found' } }
    if ($c.PSObject.Properties['expiresAt'] -and $c.expiresAt -and
        [int64]$c.expiresAt -lt [DateTimeOffset]::UtcNow.AddSeconds(30).ToUnixTimeMilliseconds()) {
        return @{ Token = $null; Why = 'the login expired - Claude Code renews it when it next runs'; Auth = $true }
    }
    return @{ Token = [string]$c.accessToken; Why = $null }
}

function Get-ChatOverlayCredStamp {
    # when the saved login last changed: after a refusal, the next ask waits
    # for Claude Code to renew it rather than being refused again
    param([string]$ClaudeHome)
    $f = Join-Path $ClaudeHome '.credentials.json'
    try { if (Test-Path -LiteralPath $f) { return [System.IO.File]::GetLastWriteTimeUtc($f).Ticks } } catch {}
    return 0
}

function Start-ChatqUsageFetch {
    <#
    Ask Claude's usage endpoint without waiting for the answer: the Windows
    panel draws on the thread that asks, and a slow network must not freeze
    it. Complete-ChatqUsageFetch collects the answer on a later pass - or
    waits for it, for chatoverlay -Print.
    #>
    param([string]$ClaudeHome = $script:ChatClaudeHome)
    if ($script:ChatOverlayUsageSeam) { return @{ Done = (& $script:ChatOverlayUsageSeam) } }   # tests
    $tok = Get-ChatqClaudeToken $ClaudeHome
    if (-not $tok.Token) { return @{ Done = @{ Ok = $false; Status = 0; Why = $tok.Why; Auth = [bool]$tok.Auth } } }
    try {
        Add-Type -AssemblyName System.Net.Http -EA Stop
        Enable-ChatqTls12
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds(15)
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $script:ChatOverlayUsageUrl)
        [void]$req.Headers.TryAddWithoutValidation('Authorization', "Bearer $($tok.Token)")
        [void]$req.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20')
        [void]$req.Headers.TryAddWithoutValidation('User-Agent', "VS-code-chat-manager/$script:ChatVersion")
        return @{ Client = $client; Request = $req; Task = $client.SendAsync($req) }
    }
    catch { return @{ Done = @{ Ok = $false; Status = 0; Why = $_.Exception.Message } } }
}

function Get-ChatqRetryAfter {
    # Seconds a response's Retry-After asks for, or $null. Delta is a
    # Nullable[TimeSpan], which PowerShell hands over as the TimeSpan itself:
    # reading .Value off it gave $null, so every 429 was retried on a guess of
    # 5 to 20 minutes while the endpoint had asked for 48, and each early ask
    # was refused again. The header may be a date instead.
    param($Response)
    try {
        $h = $Response.Headers.RetryAfter
        if (-not $h) { return $null }
        if ($null -ne $h.Delta) { return [double]([TimeSpan]$h.Delta).TotalSeconds }
        if ($null -ne $h.Date) { return [double][Math]::Max(0, ([DateTimeOffset]$h.Date - [DateTimeOffset]::UtcNow).TotalSeconds) }
    }
    catch {}
    return $null
}

function Complete-ChatqUsageFetch {
    # $null while the answer is on its way; else @{ Ok; Status; Windows | Why;
    # RetryAfter; Auth }. -WaitMs waits up to that long for it first.
    param($Fetch, [int]$WaitMs = 0)
    if ($Fetch.Done) { return $Fetch.Done }
    $t = $Fetch.Task
    if (-not $t.IsCompleted -and $WaitMs -gt 0) { try { [void]$t.Wait($WaitMs) } catch {} }
    if (-not $t.IsCompleted) { return $null }
    $res = $null
    try {
        if ($t.IsFaulted -or $t.IsCanceled) {
            $why = if ($t.Exception) { $t.Exception.GetBaseException().Message } else { 'no answer in 15 s' }
            $res = @{ Ok = $false; Status = 0; Why = $why }
        }
        else {
            $r = $t.Result
            $code = [int]$r.StatusCode
            if ($code -eq 200) {
                $u = try { $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json } catch { $null }
                $w = @(ConvertFrom-ChatqUtilization $u)
                $res = if ($w) { @{ Ok = $true; Status = 200; Windows = $w } } else { @{ Ok = $false; Status = 200; Why = 'the usage answer held no windows' } }
            }
            else {
                $res = @{ Ok = $false; Status = $code; Why = "the usage endpoint answered $code"; RetryAfter = (Get-ChatqRetryAfter $r); Auth = ($code -in 401, 403) }
            }
            $r.Dispose()
        }
    }
    catch { $res = @{ Ok = $false; Status = 0; Why = $_.Exception.Message } }
    finally { try { $Fetch.Request.Dispose() } catch {}; try { $Fetch.Client.Dispose() } catch {} }
    return $res
}

function Read-ChatqClaudeUsageCache {
    # what Claude Code last cached of the usage endpoint's answer, and when.
    # Only that block of .claude.json is lifted out and parsed - the rest holds
    # the account and is none of this tool's business.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $t = try { Read-ChatAllText $Path } catch { return $null }
    $i = $t.IndexOf('"cachedUsageUtilization"', [StringComparison]::Ordinal)
    $j = if ($i -ge 0) { $t.IndexOf('{', $i) } else { -1 }
    $obj = if ($j -ge 0) { Read-ChatqJsonObjectAt $t $j } else { $null }
    $u = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
    if (-not $u -or -not $u.fetchedAtMs) { return $null }
    $w = @(ConvertFrom-ChatqUtilization $u.utilization)
    if (-not $w) { return $null }
    return [pscustomobject]@{ Windows = $w; At = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$u.fetchedAtMs).LocalDateTime }
}

function Read-ChatqCodexUsage {
    # the newest rate_limits snapshot among the rollouts Codex wrote to last -
    # which need not be in the newest one: a thread cut off before its first
    # reply has none
    param([object[]]$Files)
    foreach ($f in @($Files)) {
        if (-not $f) { continue }
        $t = Read-ChatqTail $f.FullName 262144
        $i = if ($t) { $t.LastIndexOf('"rate_limits":{', [StringComparison]::Ordinal) } else { -1 }
        $obj = if ($i -ge 0) { Read-ChatqJsonObjectAt $t ($i + 14) } else { $null }
        $r = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
        if (-not $r) { continue }
        $w = @(ConvertFrom-ChatqCodexLimits $r)
        if (-not $w) { continue }
        $at = Get-ChatqRecordTime $t $i
        return [pscustomobject]@{ Windows = $w; At = $(if ($at) { $at } else { $f.LastWriteTime }) }
    }
    return $null
}

function ConvertTo-ChatOverlayUsage {
    # one provider's usage as the snapshot carries it: epoch ms, whole
    # percents, the server's colour for a row or a local one where there is
    # none, and a window whose reset has passed read as empty until the next
    # answer says otherwise
    param([string]$Provider, [string]$Source, $Data, [datetime]$Now, [string]$Why, [hashtable]$Blocks, [double]$StaleMinutes = 15)
    $lane = $Provider.ToLowerInvariant()
    $kinds = @()
    if ($Blocks) {
        $kinds = @($Blocks.Keys | Where-Object { $_ -eq $lane -or $_ -like "$lane|*" } |
                Where-Object { $Blocks[$_].Until } | ForEach-Object { [string]$Blocks[$_].Type })
    }
    $ws = foreach ($w in @($Data.Windows)) {
        $p = [double]$w.Percent
        $reset = $w.ResetsAt
        if ($reset -and $reset -le $Now) { $p = 0; $reset = $null }
        $limited = $p -ge 100
        # a cached figure predates the limit the watcher is waiting out
        if ($Source -ne 'live') {
            if ($w.Label -eq '5h' -and @($kinds | Where-Object { $_ -in 'five_hour', 'session' }).Count) { $limited = $true }
            if ($w.Label -eq 'week' -and @($kinds | Where-Object { $_ -in 'seven_day', 'weekly', 'weekly_all' }).Count) { $limited = $true }
        }
        $sev = if ($limited) { 'critical' } elseif ($w.Severity) { [string]$w.Severity } elseif ($p -ge 90) { 'critical' } elseif ($p -ge 75) { 'warning' } else { 'normal' }
        [pscustomobject]@{ label = [string]$w.Label; percent = [int][Math]::Round($p); resetsAt = (ConvertTo-ChatOverlayMs $reset); severity = $sev; limited = [bool]$limited }
    }
    [pscustomobject]@{
        provider = $Provider; source = $Source; at = (ConvertTo-ChatOverlayMs $Data.At)
        stale = (($Now - $Data.At).TotalMinutes -ge $StaleMinutes); why = $(if ($Why) { $Why } else { $null }); windows = @($ws)
        # the end of its line in the panel, filled in by the pass
        status = $null
    }
}

function Update-ChatOverlayUsage {
    <#
    Keeps $Ctx's usage current and returns it for the snapshot. Claude is
    asked every usageSeconds (5 minutes) while a chat works, three times less
    often while every chat is idle - nothing moves the figure then - again
    the moment a window's reset passes, and on the refresh button. The
    endpoint is meant for a /usage opened now and then: asked once a minute
    it refused after about an hour, for 48 minutes. So a 429 waits as long as
    its Retry-After says, or backs off 5, 10, 20, then 30 minutes without
    one; a refusal for the login waits for Claude Code to renew it.
    #>
    param($Ctx, [bool]$Busy, [int]$WaitMs = 0, [hashtable]$Blocks)
    $now = Get-Date
    $cfg = $Ctx.Config
    if ($cfg.liveUsage) {
        if ($Ctx.AuthStamp -and (Get-ChatOverlayCredStamp $Ctx.ClaudeHome) -ne $Ctx.AuthStamp) {
            $Ctx.AuthStamp = $null
            $Ctx.HoldUntil = $now
        }
        if (-not $Ctx.Fetch -and $now -ge $Ctx.HoldUntil) {
            $every = if ($Busy) { $cfg.usageSeconds } else { 3 * $cfg.usageSeconds }
            $due = -not $Ctx.LiveTriedAt -or ($now - $Ctx.LiveTriedAt).TotalSeconds -ge $every
            if (-not $due -and $Ctx.Live) {
                foreach ($w in @($Ctx.Live.Windows)) {
                    if ($w.ResetsAt -and $w.ResetsAt -gt $Ctx.Live.At -and $w.ResetsAt.AddSeconds(5) -le $now) { $due = $true }
                }
            }
            if ($due) {
                $Ctx.LiveTriedAt = $now
                $Ctx.Fetch = Start-ChatqUsageFetch $Ctx.ClaudeHome
            }
        }
        if ($Ctx.Fetch) {
            $res = Complete-ChatqUsageFetch $Ctx.Fetch $WaitMs
            if ($res) {
                $Ctx.Fetch = $null
                if ($Ctx.Refresh -and $Ctx.Refresh.Kind -eq 'asked' -and -not $Ctx.Refresh.Done) { $Ctx.Refresh.Done = Get-Date; $Ctx.Refresh.Ok = [bool]$res.Ok }
                if ($res.Ok) {
                    $Ctx.Live = [pscustomobject]@{ Windows = @($res.Windows); At = (Get-Date) }
                    $Ctx.LiveWhy = $null
                    $Ctx.LiveFails = 0
                    $Ctx.HoldKind = $null
                }
                else {
                    $Ctx.LiveWhy = [string]$res.Why
                    $Ctx.LiveFails++
                    $wait = 120
                    $Ctx.HoldKind = 'backoff'
                    if ($res.Auth) { $Ctx.AuthStamp = Get-ChatOverlayCredStamp $Ctx.ClaudeHome; $wait = 600; $Ctx.HoldKind = 'auth' }
                    elseif ($res.Status -eq 429) {
                        if ($res.RetryAfter) { $wait = [Math]::Max(60, [double]$res.RetryAfter); $Ctx.HoldKind = 'server' }
                        else { $wait = [Math]::Min(1800, 300 * [Math]::Pow(2, [Math]::Min(3, $Ctx.LiveFails - 1))) }
                    }
                    $Ctx.HoldUntil = (Get-Date).AddSeconds($wait)
                    if ($res.Status -eq 429) {
                        $until = $Ctx.HoldUntil.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
                        $Ctx.LiveWhy = if ($Ctx.HoldKind -eq 'server') { "rate-limited until $until" } else { "rate-limited - asking again at $until" }
                    }
                    Write-ChatOverlayLog "usage: $($res.Why)$(if ($res.RetryAfter) { " - Retry-After $([int]$res.RetryAfter) s" })"
                }
            }
        }
    }
    # Claude Code's own copy: the fallback, read again only when the file moved
    if (($now - $Ctx.CacheAt).TotalSeconds -ge 30) {
        $Ctx.CacheAt = $now
        $p = Get-ChatqClaudeJsonPath $Ctx.ClaudeHome
        $stamp = try { if (Test-Path -LiteralPath $p) { $fi = [System.IO.FileInfo]::new($p); "$($fi.Length)|$($fi.LastWriteTimeUtc.Ticks)" } else { '' } } catch { '' }
        if ($stamp -ne $Ctx.CacheStamp) { $Ctx.CacheStamp = $stamp; $Ctx.Cache = Read-ChatqClaudeUsageCache $p }
    }
    # Codex: the rollouts listed every 5 minutes, the newest re-read as it grows
    if (($now - $Ctx.CodexListAt).TotalMinutes -ge 5) {
        $Ctx.CodexListAt = $now
        $root = Join-Path $script:ChatCodexHome 'sessions'
        # @() around the if, not inside it: an if whose branch yields an empty
        # array assigns $null, and then Codex-less machines fail right here
        $Ctx.CodexFiles = @(if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Filter *.jsonl -File -Recurse -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10
            })
        $Ctx.CodexStamp = $null
    }
    if ($Ctx.CodexFiles.Count -and ($now - $Ctx.CodexAt).TotalSeconds -ge 30) {
        $Ctx.CodexAt = $now
        $f = $Ctx.CodexFiles[0]
        $stamp = try { $f.Refresh(); "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)" } catch { '' }
        if ($stamp -ne $Ctx.CodexStamp) { $Ctx.CodexStamp = $stamp; $Ctx.Codex = Read-ChatqCodexUsage $Ctx.CodexFiles }
    }
    # Copilot: a monthly quota, so every 3 x usageSeconds (15 minutes) and on
    # the refresh button. gh not there or not logged in: no line, no fuss.
    if ($cfg.copilotUsage) {
        if (-not $Ctx.CopilotFetch -and (-not $Ctx.CopilotTriedAt -or ($now - $Ctx.CopilotTriedAt).TotalSeconds -ge 3 * $cfg.usageSeconds)) {
            $Ctx.CopilotTriedAt = $now
            $Ctx.CopilotFetch = Start-ChatqCopilotFetch
        }
        if ($Ctx.CopilotFetch) {
            $res = Complete-ChatqCopilotFetch $Ctx.CopilotFetch $WaitMs
            if ($res) {
                $Ctx.CopilotFetch = $null
                if ($res.Ok) { $Ctx.Copilot = [pscustomobject]@{ Windows = @($res.Windows); At = (Get-Date) }; $Ctx.CopilotWhy = $null }
                else {
                    $Ctx.CopilotWhy = [string]$res.Why
                    if ($res.Quiet) { $Ctx.Copilot = $null } else { Write-ChatOverlayLog "copilot usage: $($res.Why)" }
                }
            }
        }
    }
    $out = [System.Collections.Generic.List[object]]::new()
    $why = if ($cfg.liveUsage -and $Ctx.LiveWhy) { $Ctx.LiveWhy } else { $null }
    # the newer of the two readings wins - a /usage opened in a window can be
    # fresher than the last live answer. With live usage off, the cache alone:
    # a live figure from before would otherwise stay up, frozen.
    # A live figure goes stale only once an ask is overdue: idle, the next one
    # is 3 x usageSeconds away.
    $liveStale = [Math]::Max(15, 3 * $cfg.usageSeconds / 60 + 5)
    if ($cfg.liveUsage -and $Ctx.Live -and (-not $Ctx.Cache -or $Ctx.Live.At -ge $Ctx.Cache.At)) { $out.Add((ConvertTo-ChatOverlayUsage 'Claude' 'live' $Ctx.Live $now $why $Blocks $liveStale)) }
    elseif ($Ctx.Cache) { $out.Add((ConvertTo-ChatOverlayUsage 'Claude' 'cache' $Ctx.Cache $now $why $Blocks)) }
    if ($Ctx.Codex) { $out.Add((ConvertTo-ChatOverlayUsage 'Codex' 'rollout' $Ctx.Codex $now $null $Blocks)) }
    if ($cfg.copilotUsage -and $Ctx.Copilot) { $out.Add((ConvertTo-ChatOverlayUsage 'Copilot' 'live' $Ctx.Copilot $now $Ctx.CopilotWhy @{} $liveStale)) }
    return $out.ToArray()
}

function Request-ChatOverlayUsageRefresh {
    <#
    The refresh button, or chatoverlay -Refresh: ask the endpoint on this
    pass, and read Claude Code's and Codex's own copies again. Not inside a
    wait the endpoint itself named - asking early only earns another
    refusal - and not twice in 20 s. What came of it is kept in
    $Ctx.Refresh for the panel to say (Get-ChatOverlayRefreshNote): a click
    that changes no figure otherwise looks like one that did nothing.
    #>
    param($Ctx)
    $now = Get-Date
    $Ctx.CacheAt = [datetime]::MinValue
    $Ctx.CodexAt = [datetime]::MinValue
    $Ctx.CodexListAt = [datetime]::MinValue
    if (-not $Ctx.CopilotFetch -and -not ($Ctx.CopilotTriedAt -and ($now - $Ctx.CopilotTriedAt).TotalSeconds -lt 20)) { $Ctx.CopilotTriedAt = $null }
    $kind = if (-not $Ctx.Config.liveUsage) { 'off' }
    elseif ($Ctx.Fetch) { 'asked' }
    elseif ($Ctx.HoldKind -eq 'server' -and $now -lt $Ctx.HoldUntil) { 'held' }
    elseif ($Ctx.LiveTriedAt -and ($now - $Ctx.LiveTriedAt).TotalSeconds -lt 20) { 'recent' }
    else { 'ask' }
    $Ctx.Refresh = @{ Kind = $(if ($kind -eq 'ask') { 'asked' } else { $kind }); At = $now; Done = $null; Ok = $false }
    if ($kind -ne 'ask') { return }
    $Ctx.HoldUntil = $now
    $Ctx.LiveTriedAt = $null
    $Ctx.AuthStamp = $null
}

function Get-ChatOverlayRefreshNote {
    <#
    What the refresh button just did, in a few words for the end of Claude's
    usage line, for 10 s once there is an outcome: asking, when Claude
    answered, or why it was not asked. A click that moves no figure
    otherwise looks like one that did nothing. Pure, for the tests.
    #>
    param($Refresh, $Live, [datetime]$Now)
    if (-not $Refresh) { return $null }
    $end = if ($Refresh.Done) { $Refresh.Done } else { $Refresh.At }
    # an ask ends in 15 s at most, answered or not
    if ($Refresh.Kind -eq 'asked' -and -not $Refresh.Done) { if (($Now - $Refresh.At).TotalSeconds -lt 30) { return 'asking...' } else { return $null } }
    if (($Now - $end).TotalSeconds -ge 10) { return $null }
    switch ($Refresh.Kind) {
        # a refusal: the line says so itself (Get-ChatOverlayUsageStatus)
        'asked' { if ($Refresh.Ok -and $Live) { return "checked $($Live.At.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture))" } }
        'recent' { return 'just asked' }
        'held' { return 'not asked - wait' }
        'off' { return 'live usage off' }
    }
    return $null
}

function Format-ChatOverlayWhen {
    # a time for a line of the panel: 14:05 today, Fri 14:05 this week, and
    # the date past that - a weekday alone read six months old as last Friday
    param([datetime]$At, [datetime]$Now)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($At.Date -eq $Now.Date) { return $At.ToString('HH:mm', $inv) }
    if (($Now - $At).TotalDays -lt 6) { return $At.ToString('ddd HH:mm', $inv) }
    return $At.ToString('MMM d', $inv)
}

function Get-ChatOverlayUsageStatus {
    <#
    The few words at the end of a provider's usage line - what used to take
    a row of its own under the bars: when its figure is from, or what is
    happening to it. Asking; what the refresh button just did (-Refresh, the
    short note); a wait the endpoint named; Claude Code's cached copy; Codex's
    last run. Pure, for the tests.
    #>
    param($Usage, [bool]$Asking, [string]$Refresh, $HoldUntil, [datetime]$Now)
    if ($Asking) { return 'asking...' }
    if ($Refresh) { return $Refresh }
    $when = Format-ChatOverlayWhen ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Usage.at).LocalDateTime) $Now
    $base = switch ($Usage.source) { 'rollout' { "last run $when" } 'cache' { "cached $when" } default { $when } }
    if (-not $Usage.why) { return $base }
    if ($HoldUntil -and $HoldUntil -gt $Now) { return "$base, retry $($HoldUntil.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture))" }
    return "$base, ask failed"
}

function Restore-ChatOverlayUsage {
    # A restart - an update, chatinstall - would forget the last live figure
    # and any wait the endpoint named, and ask again at once: refused again
    # inside that wait, or the older cached figure shown until the next ask.
    # The last snapshot saved has both. The overlay's start and -Print only.
    param($Ctx)
    if (-not $Ctx.Config.liveUsage) { return }
    $s = Read-ChatqJson $script:ChatOverlayPath
    if (-not $s -or -not $s.PSObject.Properties['header'] -or -not $s.header) { return }
    $local = { param($ms) [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms).LocalDateTime }
    $u = @($s.header.usage | Where-Object { $_ -and $_.provider -eq 'Claude' -and $_.source -eq 'live' -and $_.at })[0]
    if ($u) {
        $ws = @($u.windows | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{ Label = [string]$_.label; Percent = [double]$_.percent; Severity = [string]$_.severity
                    ResetsAt = $(if ($_.resetsAt) { & $local $_.resetsAt } else { $null }) }
            })
        if ($ws) {
            $Ctx.Live = [pscustomobject]@{ Windows = $ws; At = (& $local $u.at) }
            $Ctx.LiveTriedAt = $Ctx.Live.At
        }
    }
    $hold = $s.header.PSObject.Properties['liveHold']
    if ($hold -and $hold.Value -and [int64]$hold.Value -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) {
        $Ctx.HoldUntil = & $local $hold.Value
        $Ctx.HoldKind = 'server'
        $Ctx.LiveWhy = [string]$s.header.usageWhy
    }
}

#endregion

#region overlay: collecting ----------------------------------------------------

function Find-ChatRecordBack {
    # The last line of $Text holding $Marker that $Take turns into a value,
    # walking back one match at a time, at most $Tries lines: @{ Value; At }.
    # Index lookups rather than a split - this runs over megabytes.
    param([string]$Text, [string]$Marker, [scriptblock]$Take, [int]$Tries = 8)
    $i = $Text.LastIndexOf($Marker, [StringComparison]::Ordinal)
    while ($i -ge 0 -and $Tries -gt 0) {
        $Tries--
        $s = $Text.LastIndexOf([char]10, $i) + 1
        $e = $Text.IndexOf([char]10, $i)
        if ($e -lt 0) { $e = $Text.Length }
        $v = & $Take ($Text.Substring($s, $e - $s))
        if ($v) { return @{ Value = $v; At = $s } }
        $i = if ($s -ge 2) { $Text.LastIndexOf($Marker, $s - 2, [StringComparison]::Ordinal) } else { -1 }
    }
    return $null
}

function Get-ChatLineStamp {
    # The "timestamp" of the transcript line starting at $At, as epoch ms. A
    # timestamp quoted inside a message is escaped, so only the record's own
    # matches.
    param([string]$Text, [int]$At)
    $e = $Text.IndexOf([char]10, $At)
    if ($e -lt 0) { $e = $Text.Length }
    $m = [regex]::Match($Text.Substring($At, $e - $At), '"timestamp":"([^"]+)"')
    if ($m.Success) { return ConvertTo-ChatOverlayMs (ConvertTo-ChatqDate $m.Groups[1].Value) }
    return $null
}

function Test-ChatPromptAfter {
    # whether a line after the one at $At in $Text is one $Take accepts
    param([string]$Text, [int]$At, [scriptblock]$Take)
    $i = $Text.IndexOf([char]10, $At)
    while ($i -ge 0) {
        $i = $Text.IndexOf('"type":"user"', $i, [StringComparison]::Ordinal)
        if ($i -lt 0) { return $false }
        $s = $Text.LastIndexOf([char]10, $i) + 1
        $e = $Text.IndexOf([char]10, $i)
        if ($e -lt 0) { $e = $Text.Length }
        if (& $Take ($Text.Substring($s, $e - $s))) { return $true }
        $i = $e
    }
    return $false
}

function Find-ChatTailRecords {
    <#
    The newest prompt and title in a Claude transcript, read backwards from
    the end: 256 KB, then 1 MB at a time, up to -Budget in all. Claude Code
    writes a last-prompt and an ai-title record every turn, a few dozen lines
    before the end rather than on the last line, so the first block nearly
    always holds both - even in a 20 MB chat. Lines are cut on the newline
    byte, so no UTF-8 character is split, and a line longer than 256 KB - tool
    output, never a record this wants - is skipped whole. -From stops it
    there: after a transcript grows, only the new part is read.
    Also: Last, the newest last-prompt record's text whatever won; After, a
    slash command was found and a prompt came after it; UserAt and
    CommandAt, when the newest typed prompt and slash command found were
    sent; Pending, when something was taken off the chat's queue that has
    left no record yet.
    #>
    param([string]$Path, [int64]$From = 0, [int64]$Budget = $script:ChatOverlayScanBudget)
    $out = [pscustomobject]@{ Prompt = $null; PromptKind = $null; Last = $null; After = $false; UserAt = $null; CommandAt = $null; Pending = $null
        AiTitle = $null; CustomTitle = $null; Length = 0; Scanned = 0 }
    try { $fs = Open-ChatRead $Path } catch { return $out }
    $lastPrompt = {
        param($l)
        $o = try { $l | ConvertFrom-Json } catch { $null }
        if ($o -and $o.PSObject.Properties['lastPrompt'] -and $o.lastPrompt) {
            $t = ([string]$o.lastPrompt).Trim()
            if ($t -and -not (Test-ChatNoise $t)) { $t -replace '\s+', ' ' }
        }
    }
    # the summary a compaction leaves is a user record too, and reads like one
    $userPrompt = { param($l) if ($l -notlike '*"isCompactSummary":true*') { Read-ClaudePrompt $l } }
    $slash = { param($l) Read-ClaudeSlashCommand $l }
    $newest = $true
    $field = {
        param($l, $n)
        $o = try { $l | ConvertFrom-Json } catch { $null }
        if ($o -and $o.PSObject.Properties[$n] -and $o.$n) { ([string]$o.$n -replace '\s+', ' ').Trim() }
    }
    try {
        $len = $fs.Length
        $out.Length = $len
        $pos = $len
        $carry = $null      # the start of the block after: the rest of the line this one ends in
        $skip = $false      # inside a line too long to keep
        $block = 262144
        $keep = 262144
        $utf8 = [System.Text.Encoding]::UTF8
        while ($pos -gt $From -and $out.Scanned -lt $Budget) {
            $n = [int][Math]::Min($block, $pos - $From)
            $pos -= $n
            $block = 1048576
            $buf = [byte[]]::new($n)
            [void]$fs.Seek($pos, [System.IO.SeekOrigin]::Begin)
            $got = 0
            while ($got -lt $n) { $r = $fs.Read($buf, $got, $n - $got); if ($r -le 0) { break }; $got += $r }
            $out.Scanned += $got
            $script:ChatOverlayBytesRead += $got
            $atStart = $pos -le $From
            $end = $n
            $tail = $carry
            if ($skip) {
                # this block ends inside the long line: drop that part
                $last = [Array]::LastIndexOf($buf, [byte]10)
                if ($last -lt 0) { continue }
                $end = $last + 1
                $tail = $null
                $skip = $false
            }
            $first = if ($atStart) { -1 } else { [Array]::IndexOf($buf, [byte]10, 0, $end) }
            $tailLen = if ($tail) { $tail.Length } else { 0 }
            if (-not $atStart -and $first -lt 0) {
                # the whole block is the middle of one line
                if ($end + $tailLen -gt $keep) { $skip = $true; $carry = $null; continue }
                $joined = [byte[]]::new($end + $tailLen)
                [Array]::Copy($buf, 0, $joined, 0, $end)
                if ($tailLen) { [Array]::Copy($tail, 0, $joined, $end, $tailLen) }
                $carry = $joined
                continue
            }
            $start = if ($atStart) { 0 } else { $first + 1 }
            if (-not $atStart) {
                if ($first -gt $keep) { $skip = $true; $carry = $null }
                else { $carry = [byte[]]::new($first); [Array]::Copy($buf, 0, $carry, 0, $first) }
            }
            $bytes = [byte[]]::new($end - $start + $tailLen)
            [Array]::Copy($buf, $start, $bytes, 0, $end - $start)
            if ($tailLen) { [Array]::Copy($tail, 0, $bytes, $end - $start, $tailLen) }
            $text = $utf8.GetString($bytes)
            if ($newest) {
                $newest = $false
                # Taken off the queue, and no user or assistant record since:
                # a slash command like /compact writes nothing until it ends.
                # A prompt's own record follows its dequeue within milliseconds.
                $dq = $text.LastIndexOf('"operation":"dequeue"', [StringComparison]::Ordinal)
                if ($dq -ge 0 -and $dq -gt $text.LastIndexOf('"type":"user"', [StringComparison]::Ordinal) -and
                    $dq -gt $text.LastIndexOf('"type":"assistant"', [StringComparison]::Ordinal)) {
                    $s = $text.LastIndexOf([char]10, $dq) + 1
                    $e = $text.IndexOf([char]10, $dq)
                    if ($e -lt 0) { $e = $text.Length }
                    if ($text.Substring($s, $e - $s) -match '"timestamp":"([^"]+)"') { $out.Pending = ConvertTo-ChatOverlayMs (ConvertTo-ChatqDate $Matches[1]) }
                }
            }
            if (-not $out.Prompt) {
                $lp = Find-ChatRecordBack $text '"type":"last-prompt"' $lastPrompt
                # further back than the others: a turn's tool results are user
                # records too, and there can be dozens after the prompt
                $up = Find-ChatRecordBack $text '"type":"user"' $userPrompt 64
                $cr = Find-ChatRecordBack $text '"content":"<command-name>/' $slash 4
                if ($lp) { $out.Last = $lp.Value }
                if ($up) { $out.UserAt = Get-ChatLineStamp $text $up.At }
                if ($cr) { $out.CommandAt = Get-ChatLineStamp $text $cr.At }
                # A slash command is no prompt to Claude Code: the last-prompt
                # records after it go on naming the prompt before. So it is the
                # newest thing sent until a prompt is typed after it. Otherwise
                # whichever is later in the file: a prompt still being answered
                # can be newer than the last last-prompt record.
                if ($cr -and -not (Test-ChatPromptAfter $text $cr.At $userPrompt)) { $out.Prompt = $cr.Value; $out.PromptKind = 'command' }
                elseif ($lp -and (-not $up -or $lp.At -ge $up.At)) { $out.Prompt = $lp.Value; $out.PromptKind = 'last' }
                elseif ($up) { $out.Prompt = $up.Value; $out.PromptKind = 'user' }
                if ($cr -and $out.PromptKind -ne 'command') { $out.After = $true }
            }
            if (-not $out.AiTitle) {
                $t = Find-ChatRecordBack $text '"type":"ai-title"' { param($l) & $field $l 'aiTitle' } 2
                if ($t) { $out.AiTitle = $t.Value }
            }
            if (-not $out.CustomTitle) {
                $t = Find-ChatRecordBack $text '"type":"custom-title"' { param($l) & $field $l 'customTitle' } 2
                if ($t) { $out.CustomTitle = $t.Value }
            }
            if ($out.Prompt -and ($out.AiTitle -or $out.CustomTitle)) { break }
        }
    }
    finally { $fs.Dispose() }
    return $out
}

function Find-ChatOverlayTranscript {
    # projects/<slug of cwd>/<id>.jsonl; failing that - the slug's case can
    # differ from the cwd the registry holds, which matters off Windows - the
    # one file of that name in any project
    param([string]$ClaudeHome, [string]$Cwd, [string]$SessionId)
    $root = Join-Path $ClaudeHome 'projects'
    if ($Cwd) {
        $p = Join-Path (Join-Path $root (Get-ChatSlug $Cwd)) "$SessionId.jsonl"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue)) {
        $p = Join-Path $d.FullName "$SessionId.jsonl"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Update-ChatOverlayText {
    <#
    The title and newest prompt of one open chat, kept in $Ctx.Text by session
    id. The transcript is read again only when it grew, and then only the new
    part, with 64 KB of overlap for a line cut at the old end. One that shrank
    was rewritten, and is read afresh. A chat with no transcript yet (opened,
    nothing sent) is looked for again every 30 s.
    #>
    param($Ctx, $Session)
    $sid = $Session.SessionId
    $st = $Ctx.Text[$sid]
    if (-not $st) {
        $st = @{ Path = $null; Len = -1; Prompt = $null; PromptKind = $null; Last = $null; CommandAt = $null; Pending = $null; AiTitle = $null; CustomTitle = $null; Sidecar = $null; First = $null; Mtime = $null }
        $Ctx.Text[$sid] = $st
    }
    if (-not $st.Path -or -not (Test-Path -LiteralPath $st.Path)) {
        $miss = $Ctx.Missing[$sid]
        if ($miss -and ((Get-Date) - $miss).TotalSeconds -lt 30) { return }
        $st.Path = Find-ChatOverlayTranscript $Ctx.ClaudeHome $Session.Cwd $sid
        $st.Len = -1
        if (-not $st.Path) { $Ctx.Missing[$sid] = Get-Date; return }
        $Ctx.Missing.Remove($sid)
    }
    $fi = [System.IO.FileInfo]::new($st.Path)
    if (-not $fi.Exists -or $fi.Length -eq $st.Len) { return }
    $from = 0
    if ($st.Len -gt 0 -and $fi.Length -gt $st.Len) { $from = [Math]::Max([Math]::Max(0, $st.Len - 65536), $fi.Length - 8MB) }
    else { $st.Prompt = $null; $st.PromptKind = $null; $st.Last = $null; $st.CommandAt = $null; $st.AiTitle = $null; $st.CustomTitle = $null; $st.First = $null }
    $r = Find-ChatTailRecords $st.Path -From $from
    if ($r.CustomTitle) { $st.CustomTitle = $r.CustomTitle }
    if ($r.AiTitle) { $st.AiTitle = $r.AiTitle }
    # A command found earlier stays the newest thing sent while the new part
    # holds only a last-prompt record re-written with the prompt before it -
    # Claude Code writes one after every turn, command or not. A prompt typed
    # since, even the same words again, is newer by its own timestamp.
    $typed = $r.UserAt -and $st.CommandAt -and [int64]$r.UserAt -gt [int64]$st.CommandAt
    $keep = $st.PromptKind -eq 'command' -and $r.PromptKind -eq 'last' -and -not $r.After -and $r.Last -eq $st.Last -and -not $typed
    if ($r.Prompt -and -not $keep) { $st.Prompt = $r.Prompt; $st.PromptKind = $r.PromptKind; $st.Last = $r.Last; $st.CommandAt = $r.CommandAt }
    $st.Pending = $r.Pending
    $st.Len = $r.Length
    $st.Mtime = $fi.LastWriteTime
    # a rename made in the panel sits beside the transcript
    $side = Join-Path (Join-Path $fi.DirectoryName $sid) 'custom-title.json'
    if (Test-Path -LiteralPath $side) {
        try { $st.Sidecar = [string](([System.IO.File]::ReadAllText($side, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).customTitle) } catch {}
    }
    if (-not $st.CustomTitle -and -not $st.Sidecar -and -not $st.AiTitle -and -not $st.First) {
        # nothing has titled it yet: its first prompt, as the panel would show
        $c = Read-ChatChunk $st.Path 262144
        if ($c) {
            foreach ($l in @(Get-ChatJsonLines $c.Head '"type":"user"' 4)) {
                $t = Read-ClaudePrompt $l
                if ($t) { $st.First = $t; break }
            }
        }
    }
}

function Format-ChatOverlayCutOff {
    # what a chat the limit or a 529 stopped is waiting on
    param($CutOff, [datetime]$Now = (Get-Date))
    if ($CutOff.Why -eq 'overloaded') { return '529 - waits for Claude' }
    $r = $CutOff.ResetsAt
    if ($r -and $r -gt $Now) {
        $at = if ($r.Date -eq $Now.Date) { $r.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } else { $r.ToString('ddd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) }
        return "cut off - resets $at"
    }
    return 'cut off - limit over'
}

function Get-ChatOverlayStateText {
    # the words at the right of a row: what it is doing, a queued prompt it
    # carries, and for how long
    param($Row, [datetime]$Now = (Get-Date))
    $what = switch ([string]$Row.status) {
        'waiting' { if ($Row.detail) { [string]$Row.detail } else { 'needs you' } }
        'needs-input' { 'needs you' }
        'busy' { 'working' }
        'running' { 'running' }
        'idle' { 'idle' }
        # the reset, or what it waits on, is what it says - not how long ago
        'cutoff' { return [string]$Row.detail }
        default { [string]$Row.status }
    }
    $badge = ''
    if ($Row.job) {
        $j = $Row.job
        $jt = switch ([string]$j.state) {
            'queued' {
                if (-not $j.eta) { 'queued' }
                elseif ([string]$j.eta -match '^(\d|[A-Z][a-z]{2} \d)') { "sends $($j.eta)" }
                else { [string]$j.eta }
            }
            'running' { 'running' }
            'needs-input' { 'needs you' }
            default { [string]$j.state }
        }
        if ($Row.kind -eq 'job' -or $Row.status -eq $j.state) { $what = "#$($j.seq) $jt" }
        else { $badge = "#$($j.seq) $jt $($script:ChatqDot) " }
    }
    $age = ''
    if ($Row.since -and $Row.status -ne 'queued') {
        $age = ' ' + (Get-ChatAge ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Row.since).LocalDateTime))
    }
    return "$badge$what$age"
}

function Get-ChatOverlayRows {
    <#
    One row per chat, most urgent first. A chat open in two windows is one
    row, with the more urgent of their states. A prompt queued for a chat that
    is open rides on that chat's row; any other job gets a row of its own.
    Pure - everything comes in as parameters - so the tests drive it directly.
      rank 0    waiting on you, or a job that needs input  oldest first
      rank 0.5  cut off by the limit or a 529              newest first
      rank 1    working                                    newest first
      rank 2    a job running                              newest first
      rank 3    idle                                       newest first
      rank 4    queued                                     in queue order
    -CutOff: Get-ChatqCutOffChats' rows. An open, idle chat among them takes
    the cut-off state; one not open gets a row of its own; one a job is
    queued or running for leaves it to the job.
    #>
    param([object[]]$Sessions, [hashtable]$Texts, [object[]]$Jobs, [hashtable]$Eta, [datetime]$Now = (Get-Date), [object[]]$CutOff)
    $rankOf = @{ 'waiting' = 0; 'needs-input' = 0; 'cutoff' = 0.5; 'busy' = 1; 'running' = 2; 'idle' = 3; 'queued' = 4 }
    $ms = { param($v) ConvertTo-ChatOverlayMs $v }
    $nowMs = ConvertTo-ChatOverlayMs $Now
    $bySid = [ordered]@{}
    foreach ($s in @($Sessions)) {
        if (-not $s -or -not $s.SessionId) { continue }
        $st = if ($s.Status -in 'waiting', 'busy') { [string]$s.Status } else { 'idle' }
        $since = $null
        foreach ($v in @($s.StatusUpdatedAt, $s.UpdatedAt, $s.StartedAt)) { if ($v) { $since = & $ms $v; break } }
        $wf = $s.WaitingFor
        $detail = if ($st -ne 'waiting' -or -not $wf) { $null } elseif ($wf -is [string]) { $wf } else { 'needs you' }
        $row = $bySid[$s.SessionId]
        if ($row) {
            $row.pids = @($row.pids) + @($s.Pid)
            if ($rankOf[$st] -lt $row.rank) { $row.status = $st; $row.chat = $st; $row.rank = $rankOf[$st]; $row.detail = $detail; $row.since = $since }
            continue
        }
        $t = if ($Texts) { $Texts[$s.SessionId] } else { $null }
        # A panel keeps a process for a new chat tab before anything is sent
        # in it: no transcript, nothing to show, and one for every window.
        if ($st -eq 'idle' -and $t -and -not $t.Path) { continue }
        $title = $null
        if ($t) { foreach ($c in @($t.CustomTitle, $t.Sidecar, $t.AiTitle, $t.First)) { if ($c) { $title = $c; break } } }
        if (-not $title) { $title = $s.Name }
        if (-not $since -and $t -and $t.Mtime) { $since = & $ms $t.Mtime }
        $leaf = if ($s.Cwd) { Split-Path ([string]$s.Cwd).TrimEnd('\', '/') -Leaf } else { '' }
        $prompt = if ($t -and $t.Prompt) { [string]$t.Prompt } else { $null }
        $kind = if ($t) { $t.PromptKind } else { $null }
        # working on something sent that has left no record for 3 s: not the
        # prompt before it, so that is not what to show
        if ($st -eq 'busy' -and $t -and $t.Pending -and ($nowMs - [int64]$t.Pending) -ge 3000) { $prompt = $script:ChatOverlayPendingText; $kind = 'pending' }
        if ($prompt -and $prompt.Length -gt 240) { $prompt = $prompt.Substring(0, 239) + $script:ChatqEllipsis }
        $bySid[$s.SessionId] = [pscustomobject]@{
            key = "s:$($s.SessionId)"; kind = 'session'; provider = 'claude'; status = $st; chat = $st; rank = $rankOf[$st]
            project = $leaf; title = (Format-ChatTitle $title 80); prompt = $prompt; promptKind = $kind
            detail = $detail; since = $since; sessionId = $s.SessionId; pids = @($s.Pid); cwd = [string]$s.Cwd; job = $null; order = 0; stateText = ''
        }
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $bySid.Values) { $rows.Add($r) }
    $taken = @{}
    foreach ($jw in @($Jobs)) { if ($jw -and $jw.Job.sessionId -and $jw.Job.state -in 'queued', 'running') { $taken[[string]$jw.Job.sessionId] = $true } }
    foreach ($c in @($CutOff)) {
        if (-not $c -or -not $c.Id -or $taken[[string]$c.Id]) { continue }
        $words = Format-ChatOverlayCutOff $c $Now
        $open = $bySid[[string]$c.Id]
        if ($open) {
            # an open chat that is working again has moved on
            if ($open.status -eq 'idle') { $open.status = 'cutoff'; $open.chat = 'cutoff'; $open.rank = $rankOf['cutoff']; $open.detail = $words }
            continue
        }
        $rows.Add([pscustomobject]@{
                key = "c:$($c.Id)"; kind = 'cutoff'; provider = 'claude'; status = 'cutoff'; chat = 'cutoff'; rank = $rankOf['cutoff']
                project = $(if ($c.Cwd) { Split-Path ([string]$c.Cwd).TrimEnd('\', '/') -Leaf } else { '' })
                title = (Format-ChatTitle ([string]$c.Title) 80); prompt = $null; promptKind = $null
                detail = $words; since = $(if ($c.At) { & $ms $c.At } else { $null }); sessionId = [string]$c.Id; pids = @(); cwd = [string]$c.Cwd
                job = $null; order = 0; stateText = ''; path = [string]$c.Path
            })
    }
    $order = 0
    foreach ($jw in @($Jobs)) {
        if (-not $jw) { continue }
        $j = $jw.Job
        $state = [string]$j.state
        if ($null -eq $rankOf[$state]) { continue }
        $info = [pscustomobject]@{ seq = [int]$j.seq; state = $state; eta = $(if ($Eta) { $Eta[$j.id] } else { $null }) }
        $hit = if ($j.provider -eq 'claude' -and $j.sessionId) { $bySid[[string]$j.sessionId] } else { $null }
        if ($hit) {
            if (-not $hit.job -or $rankOf[$state] -lt $rankOf[$hit.job.state]) { $hit.job = $info }
            # needs-input or running pulls the chat up; queued never pushes it down
            if ($rankOf[$state] -lt $hit.rank) { $hit.rank = $rankOf[$state]; $hit.status = $state }
            continue
        }
        $order++
        $when = switch ($state) {
            'running' { $j.startedAt }
            'needs-input' { $j.endedAt }
            default { $j.createdAt }
        }
        $since = & $ms (ConvertTo-ChatqDate $when)
        $detail = if ($state -eq 'needs-input' -and $j.result -and $j.result.reason) { [string]$j.result.reason } else { $null }
        $rows.Add([pscustomobject]@{
                key = "j:$($j.id)"; kind = 'job'; provider = [string]$j.provider; status = $state; rank = $rankOf[$state]
                project = $(if ($j.cwd) { Split-Path ([string]$j.cwd).TrimEnd('\', '/') -Leaf } else { '' })
                chat = $null; title = (Format-ChatTitle ([string]$j.title) 80); prompt = [string]$jw.First; promptKind = 'job'
                detail = $detail; since = $since; sessionId = [string]$j.sessionId; pids = @(); cwd = [string]$j.cwd
                job = $info; order = $order; stateText = ''
            })
    }
    $sorted = @($rows | Sort-Object @{ Expression = { $_.rank } }, @{ Expression = {
                $s = if ($_.since) { [double]$_.since } else { 0 }
                if ($_.rank -eq 0) { $s } elseif ($_.rank -eq 4) { [double]$_.order } else { -1 * $s }
            }
        })
    foreach ($r in $sorted) { $r.stateText = Get-ChatOverlayStateText $r $Now }
    return $sorted
}

function Get-ChatOverlayNotes {
    # The header's words beyond the usage: a watcher that stopped with
    # prompts waiting, when the next one sends, and an error the collector
    # keeps meeting. When each usage figure is from - its age, asking, a wait
    # the endpoint named, Codex's last run - is at its own line's end or
    # under its name (Get-ChatOverlayUsageStatus); those took a row each here
    # once. Only a Claude figure with no line at all to carry it is said here.
    param($Header)
    $out = [System.Collections.Generic.List[object]]::new()
    $cl = @($Header.usage | Where-Object { $_ -and $_.provider -eq 'Claude' })[0]
    if (-not $cl -and $Header.usageWhy) { $out.Add([pscustomobject]@{ text = "usage: $($Header.usageWhy)"; tone = 'dim' }) }
    if ($Header.watcher -eq 'stopped') { $out.Add([pscustomobject]@{ text = 'prompts queued, watcher stopped - chatqrun starts it'; tone = 'warn' }) }
    elseif ($Header.next) { $out.Add([pscustomobject]@{ text = "next queued prompt: $($Header.next)"; tone = 'dim' }) }
    if ($Header.error) { $out.Add([pscustomobject]@{ text = "$($Header.error) - data/logs/overlay.log"; tone = 'error' }) }
    return $out.ToArray()
}

function New-ChatOverlayContext {
    # everything the collector keeps between passes
    param([string]$ClaudeHome = $script:ChatClaudeHome)
    $never = [datetime]::MinValue
    return @{
        ClaudeHome = $ClaudeHome; Config = (Get-ChatOverlayConfig); Cycle = 0; Verbs = @()
        Registry = @{}; Alive = @{}; PidSig = $null; AliveAt = $never
        Text = @{}; Missing = @{}
        Jobs = @(); JobsSig = $null; Blocks = @{}; BlocksAt = $never
        Watcher = $false; WatcherAt = $never
        Fetch = $null; Live = $null; LiveWhy = $null; LiveFails = 0; LiveTriedAt = $null; HoldUntil = $never; HoldKind = $null; AuthStamp = $null; Refresh = $null
        CopilotFetch = $null; Copilot = $null; CopilotWhy = $null; CopilotTriedAt = $null
        Cache = $null; CacheStamp = $null; CacheAt = $never
        Codex = $null; CodexFiles = @(); CodexListAt = $never; CodexStamp = $null; CodexAt = $never
        Commands = [System.Collections.Generic.List[object]]::new(); CommandId = 0
        CutOff = @(); CutCache = @{}; CutAt = $never; CutSig = $null
        ViewSig = $null; SavedSig = $null; SavedAt = $never
    }
}

function Invoke-ChatOverlayCycle {
    <#
    One pass of the collector: what runs, what each chat said last, the queue
    and usage, turned into the snapshot a renderer draws - and saved to
    data/overlay.json when it changed, or every 10 s so a reader can tell the
    collector is alive. Cheap by construction: a file is read again only once
    it changed, and transcript reading stops when the pass has used its slice
    of time, leaving the rest for the next.
    -Sync waits for the usage endpoint; -Peek takes no commands and saves
    nothing, so chatoverlay -Print never gets in a running overlay's way.
    #>
    param($Ctx, [switch]$Sync, [switch]$Peek)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $now = Get-Date
    $Ctx.Cycle++
    $err = $null

    # commands first: a stop must not wait on a slow pass
    # @() around the if: an empty array out of a branch would assign $null
    $Ctx.Verbs = @(if (-not $Peek) { Receive-ChatOverlayCommands })
    if ($Ctx.Verbs -contains 'reload') { $Ctx.Config = Get-ChatOverlayConfig }
    if ($Ctx.Verbs -contains 'refresh') { Request-ChatOverlayUsageRefresh $Ctx }
    foreach ($v in $Ctx.Verbs) {
        if (-not $v -or $v -in 'stop', 'restart', 'reload', 'refresh') { continue }
        # for a renderer in another process (macOS), by id and time
        $Ctx.CommandId++
        $Ctx.Commands.Add([pscustomobject]@{ id = $Ctx.CommandId; verb = $v; at = (ConvertTo-ChatOverlayMs $now) })
    }
    $cut = ConvertTo-ChatOverlayMs $now.AddMinutes(-5)
    for ($i = $Ctx.Commands.Count - 1; $i -ge 0; $i--) { if ($Ctx.Commands[$i].at -lt $cut) { $Ctx.Commands.RemoveAt($i) } }

    # what runs: the registry every pass, whether each entry's process is
    # still that session every 10 s or as soon as the set of them changes
    $entries = @()
    try { $entries = @(Read-ChatqSessionRegistry (Join-Path $Ctx.ClaudeHome 'sessions') $Ctx.Registry) }
    catch { $err = "sessions: $($_.Exception.Message)" }
    $pk = { param($e) "$($e.Pid)|$($e.ProcStart)|$($e.StartedAt)" }
    $pidSig = (@($entries | ForEach-Object { & $pk $_ } | Sort-Object) -join ',')
    if ($pidSig -ne $Ctx.PidSig -or ($now - $Ctx.AliveAt).TotalSeconds -ge 10) {
        $procs = @{}
        if (-not $script:ChatqAliveSeam) {
            foreach ($p in @(Get-Process -Name 'claude*', 'node*' -EA SilentlyContinue)) { $procs[$p.Id] = $p }
        }
        $alive = @{}
        foreach ($e in $entries) { $alive[(& $pk $e)] = Test-ChatqSessionAlive $e $procs }
        $Ctx.Alive = $alive
        $Ctx.PidSig = $pidSig
        $Ctx.AliveAt = $now
    }
    # interactive only: chatq's own claude -p runs register too, and show as
    # the job they belong to
    $live = @($entries | Where-Object { $_.SessionId -and $Ctx.Alive[(& $pk $_)] -and (-not $_.Kind -or $_.Kind -eq 'interactive') })

    # what each said last - the ones working first, then the newest
    $order = @($live | Sort-Object @{ Expression = { if ($_.Status -in 'waiting', 'busy') { 0 } else { 1 } } },
        @{ Expression = { if ($_.UpdatedAt) { [double]$_.UpdatedAt } else { 0 } }; Descending = $true })
    $open = @{}
    foreach ($e in $order) {
        if ($open[$e.SessionId]) { continue }
        $open[$e.SessionId] = $true
        # past the slice, only a chat never read yet: the rest keep what they had
        if ($sw.ElapsedMilliseconds -gt $script:ChatOverlaySliceMs -and $Ctx.Text[$e.SessionId]) { continue }
        try { Update-ChatOverlayText $Ctx $e } catch { $err = "transcript: $($_.Exception.Message)" }
    }
    foreach ($k in @($Ctx.Text.Keys)) { if (-not $open[$k]) { $Ctx.Text.Remove($k) } }

    # the queue, read again only when a job file changed
    $sig = ''
    if (Test-Path -LiteralPath $script:ChatqQueueDir) {
        $max = 0L
        $files = @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Filter *.json -File -EA SilentlyContinue)
        foreach ($f in $files) { if ($f.LastWriteTimeUtc.Ticks -gt $max) { $max = $f.LastWriteTimeUtc.Ticks } }
        $sig = "$($files.Count)|$max"
    }
    if ($sig -ne $Ctx.JobsSig) {
        $Ctx.JobsSig = $sig
        try {
            $Ctx.Jobs = @(Get-ChatqJobs | Where-Object { $_.state -in 'queued', 'running', 'needs-input' } | ForEach-Object {
                    $first = if ($_.kind -eq 'continue') { 'continue' } else { (Get-ChatqPromptStats ([string](Read-ChatqPrompt $_))).First }
                    [pscustomobject]@{ Job = $_; First = $first }
                })
        }
        catch { $err = "queue: $($_.Exception.Message)" }
        $Ctx.BlocksAt = [datetime]::MinValue
    }
    if (($now - $Ctx.WatcherAt).TotalSeconds -ge 10) { $Ctx.Watcher = Test-ChatqWatcherAlive; $Ctx.WatcherAt = $now }
    $queued = @($Ctx.Jobs | Where-Object { $_.Job.state -eq 'queued' })
    if (-not $queued) { $Ctx.Blocks = @{} }
    elseif (($now - $Ctx.BlocksAt).TotalSeconds -ge 60) {
        # without a watcher this reads the recent transcripts' tails, so not
        # every pass
        $Ctx.Blocks = try { Get-ChatqBlocks } catch { @{} }
        if (-not $Ctx.Blocks) { $Ctx.Blocks = @{} }
        $Ctx.BlocksAt = $now
    }
    $jobs = @($Ctx.Jobs | ForEach-Object { $_.Job })
    $eta = if ($jobs) { Get-ChatqEta $jobs $Ctx.Blocks } else { @{} }

    # usage
    $busy = [bool](@($live | Where-Object { $_.Status -in 'busy', 'waiting' }).Count -or @($jobs | Where-Object { $_.state -eq 'running' }).Count)
    $usage = @()
    try { $usage = @(Update-ChatOverlayUsage $Ctx $busy -WaitMs $(if ($Sync) { 15000 } else { 0 }) -Blocks $Ctx.Blocks) }
    catch { $err = "usage: $($_.Exception.Message)" }

    # Chats the limit or a 529 cut off, a minute apart, reading only the
    # transcripts that moved since - and at once when a job came or went or
    # a chat started or stopped working: a continue that ran in under a
    # minute would otherwise bring its orange row back until the next look.
    $cutSig = (@($live | ForEach-Object { "$($_.SessionId)=$($_.Status)" } | Sort-Object) -join ',') + "|$($Ctx.JobsSig)"
    if ($cutSig -ne $Ctx.CutSig) { $Ctx.CutSig = $cutSig; $Ctx.CutAt = [datetime]::MinValue }
    if (-not $Ctx.Config.cutOff) { $Ctx.CutOff = @() }
    elseif (($now - $Ctx.CutAt).TotalSeconds -ge 60) {
        $Ctx.CutAt = $now
        $t0 = $sw.ElapsedMilliseconds
        # a chat at work is not cut off, and its transcript moves all the time
        $working = @($live | Where-Object { $_.Status -in 'busy', 'waiting' } | ForEach-Object { [string]$_.SessionId })
        try {
            # a week back, for a weekly limit that is still ahead; otherwise
            # only what the last 12 hours cut off
            $found = @(Get-ChatqCutOffChats @() -Hours 168 -Cache $Ctx.CutCache -Skip $working)
            $Ctx.CutOff = @($found | Where-Object { ($_.ResetsAt -and $_.ResetsAt -gt $now) -or ($_.At -and $_.At -gt $now.AddHours(-12)) })
        }
        catch { $err = "cut off: $($_.Exception.Message)" }
        $took = $sw.ElapsedMilliseconds - $t0
        if ($took -gt 250) { Write-ChatOverlayLog "the cut-off scan took $took ms" }
    }
    $rows = @(Get-ChatOverlayRows -Sessions $live -Texts $Ctx.Text -Jobs $Ctx.Jobs -Eta $eta -Now $now -CutOff $Ctx.CutOff)
    $chats = @($rows | Where-Object { $_.kind -eq 'session' } | ForEach-Object { $_.chat })
    $counts = [pscustomobject]@{
        waiting = @($chats | Where-Object { $_ -eq 'waiting' }).Count; busy = @($chats | Where-Object { $_ -eq 'busy' }).Count
        idle = @($chats | Where-Object { $_ -eq 'idle' }).Count
        running = @($jobs | Where-Object { $_.state -eq 'running' }).Count; queued = $queued.Count
        needsInput = @($jobs | Where-Object { $_.state -eq 'needs-input' }).Count
        cutOff = @($rows | Where-Object { $_.status -eq 'cutoff' }).Count
    }
    $next = $null
    foreach ($j in $jobs) { if ($j.state -eq 'queued' -and $eta[$j.id]) { $next = [string]$eta[$j.id]; break } }
    $watch = if ($Ctx.Watcher) { 'running' } elseif ($queued) { 'stopped' } else { 'none' }
    $usageText = (@($usage | ForEach-Object {
                $u = $_
                "$($u.provider) " + ((@($u.windows) | ForEach-Object { "$($_.label) $($_.percent)%" }) -join " $($script:ChatqDot) ")
            }) -join "  $($script:ChatqDot)  ")
    if ($err) { Write-ChatOverlayLog $err }
    $short = Get-ChatOverlayRefreshNote $Ctx.Refresh $Ctx.Live $now
    foreach ($u in $usage) {
        $u.status = switch ($u.provider) {
            'Claude' { Get-ChatOverlayUsageStatus $u ([bool]$Ctx.Fetch) $short $(if ($Ctx.HoldKind) { $Ctx.HoldUntil } else { $null }) $now }
            'Copilot' { Get-ChatOverlayUsageStatus $u ([bool]$Ctx.CopilotFetch) $null $null $now }
            default { Get-ChatOverlayUsageStatus $u $false $null $null $now }
        }
    }
    $header = [pscustomobject]@{
        usage = @($usage); usageText = $usageText; usageWhy = $(if ($Ctx.Config.liveUsage) { $Ctx.LiveWhy } else { $null })
        # a wait the endpoint named, so a restart keeps to it (Restore-ChatOverlayUsage)
        liveHold = $(if ($Ctx.HoldKind -eq 'server' -and $Ctx.HoldUntil -gt $now) { ConvertTo-ChatOverlayMs $Ctx.HoldUntil } else { $null })
        next = $next; watcher = $watch; error = $err; notes = @()
    }
    $header.notes = @(Get-ChatOverlayNotes $header)
    $snap = [pscustomobject]@{
        schema = 1; version = $script:ChatVersion; pid = $PID; at = 0
        header = $header; counts = $counts; config = $Ctx.Config; commands = @($Ctx.Commands); rows = @($rows)
    }
    $body = ConvertTo-Json $snap -Depth 6 -Compress
    $Ctx.ViewSig = $body
    $snap.at = ConvertTo-ChatOverlayMs (Get-Date)
    # against what was saved, not what was last seen: a -Peek pass - the
    # refresh button's - sees a change first, and the file kept the old one
    # for up to 10 s
    if (-not $Peek -and ($body -ne $Ctx.SavedSig -or ($now - $Ctx.SavedAt).TotalSeconds -ge 10)) {
        try { Save-ChatqText $script:ChatOverlayPath (ConvertTo-Json $snap -Depth 6 -Compress); $Ctx.SavedAt = $now; $Ctx.SavedSig = $body }
        catch { Write-ChatOverlayLog "overlay.json: $($_.Exception.Message)" }
    }
    return $snap
}

function Send-ChatOverlayCommand {
    # a line for the running overlay to act on: "<utc time> <verb>"
    param([string]$Verb)
    New-ChatqDir $script:ChatqData
    [System.IO.File]::AppendAllText($script:ChatOverlayCmdPath, "$(Get-ChatqStamp) $Verb`n", (New-Object System.Text.UTF8Encoding $false))
}

function Receive-ChatOverlayCommands {
    # What shells asked for since the last pass. The file is renamed away
    # first, which is atomic, so a line appended meanwhile starts a new file
    # instead of being lost. Lines older than 5 minutes are dropped: left
    # over from a time the overlay was not running to hear them.
    $p = $script:ChatOverlayCmdPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $take = "$p.$PID"
    try {
        if (Test-Path -LiteralPath $take) { Remove-Item -LiteralPath $take -Force }
        [System.IO.File]::Move($p, $take)
    }
    catch { return @() }
    $lines = try { [System.IO.File]::ReadAllLines($take) } catch { @() }
    Remove-Item -LiteralPath $take -Force -EA SilentlyContinue
    $cut = (Get-Date).ToUniversalTime().AddMinutes(-5)
    return @(foreach ($l in @($lines)) {
            if ($l -notmatch '^(\S+)\s+([a-z-]+)\s*$') { continue }
            $verb = $Matches[2]
            $at = ConvertTo-ChatqDate $Matches[1]
            if (-not $at -or $at.ToUniversalTime() -lt $cut) { continue }
            $verb
        })
}

function Invoke-ChatOverlayCollectLoop {
    # The collector on its own - for the macOS host, and the tests: a pass
    # every -IntervalMs until a stop or restart comes in, -OnCycle returns a
    # reason to end, or -MaxCycles passes have run. Returns why it ended.
    param($Ctx, [int]$IntervalMs = 2000, [int]$MaxCycles = 0, [scriptblock]$OnCycle)
    $n = 0
    while ($true) {
        $snap = $null
        try { $snap = Invoke-ChatOverlayCycle $Ctx }
        catch { Write-ChatOverlayLog "pass: $($_.Exception.Message)" }
        if (@($Ctx.Verbs) -contains 'stop') { return 'stop' }
        if (@($Ctx.Verbs) -contains 'restart') { return 'restart' }
        if ($OnCycle) {
            $why = & $OnCycle $snap
            if ($why) { return [string]$why }
        }
        $n++
        if ($MaxCycles -gt 0 -and $n -ge $MaxCycles) { return 'max' }
        Start-Sleep -Milliseconds $IntervalMs
    }
}

function Format-ChatOverlayReset {
    # when a usage window resets: a countdown inside a day, a weekday after
    param($ResetsAt, [datetime]$Now = (Get-Date))
    if (-not $ResetsAt) { return '' }
    $at = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ResetsAt).LocalDateTime
    $s = ($at - $Now).TotalSeconds
    if ($s -le 0) { return 'reset' }
    if ($s -ge 86400) { return $at.ToString('ddd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) }
    $m = [int][Math]::Floor($s / 60)
    if ($m -ge 60) { return "$([int][Math]::Floor($m / 60))h $($m % 60)m" }
    if ($m -ge 1) { return "${m}m" }
    return "$([int][Math]::Ceiling($s))s"
}

function Format-ChatOverlayTooltip {
    # the tray icon's tooltip. .NET Framework's NotifyIcon throws at 64
    # characters or more, so it is cut to 63 before it is ever assigned.
    param($Snap)
    $c = $Snap.counts
    $bits = @()
    $need = [int]$c.waiting + [int]$c.needsInput
    if ($need) { $bits += "$need need you" }
    if ($c -and $c.PSObject.Properties['cutOff'] -and [int]$c.cutOff) { $bits += "$($c.cutOff) cut off" }
    if ($c.busy) { $bits += "$($c.busy) working" }
    if ($c.running) { $bits += "$($c.running) running" }
    if ($c.idle) { $bits += "$($c.idle) idle" }
    if ($c.queued) { $bits += "$($c.queued) queued" }
    if (-not $bits) { $bits += 'no chats open' }
    $t = 'chatq: ' + ($bits -join ', ')
    $u = @($Snap.header.usage | Where-Object { $_ -and $_.provider -eq 'Claude' })[0]
    $w = if ($u) { @($u.windows | Where-Object { $_.label -eq '5h' })[0] } else { $null }
    if ($w) { $t += " - 5h $($w.percent)%" }
    if ($t.Length -gt 63) { $t = $t.Substring(0, 62) + $script:ChatqEllipsis }
    return $t
}

function Write-ChatOverlayPrint {
    # chatoverlay -Print: one pass, drawn in the console. Linux's only view,
    # and the way to see what the panel would show. ASCII marks only - a
    # CP949 console draws the round ones two cells wide. A wait the endpoint
    # named, or a live figure a running overlay just got, holds here too.
    $ctx = New-ChatOverlayContext
    Restore-ChatOverlayUsage $ctx
    $snap = Invoke-ChatOverlayCycle $ctx -Sync -Peek
    $now = Get-Date
    $sev = @{ normal = 'Cyan'; warning = 'Yellow'; critical = 'Red' }
    Write-Host ''
    foreach ($u in @($snap.header.usage)) {
        if ($snap.config.usageView -ne 'bars') {
            # one line a provider, its time at the end, as the panel has it
            Write-Host ('  {0,-8}' -f $u.provider) -NoNewline -ForegroundColor $(if ($u.stale) { 'DarkGray' } else { 'Gray' })
            $first = $true
            foreach ($w in @($u.windows)) {
                if (-not $first) { Write-Host " $($script:ChatqDot) " -NoNewline -ForegroundColor DarkGray }
                $first = $false
                Write-Host "$($w.label) " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($w.percent)%" -NoNewline -ForegroundColor $(if ($w.limited -or $w.severity -eq 'critical') { 'Red' } elseif ($w.severity -eq 'warning') { 'Yellow' } else { 'Gray' })
            }
            Write-Host "   $($u.status)" -ForegroundColor DarkGray
            continue
        }
        $first = $true
        foreach ($w in @($u.windows)) {
            $name = if ($first) { $u.provider } else { '' }
            $first = $false
            $fill = [int][Math]::Round([Math]::Min(100, [Math]::Max(0, $w.percent)) / 10)
            Write-Host ('  {0,-7}{1,-12}' -f $name, $w.label) -NoNewline -ForegroundColor $(if ($u.stale) { 'DarkGray' } else { 'Gray' })
            Write-Host ('[' + ('#' * $fill) + ('-' * (10 - $fill)) + ']') -NoNewline -ForegroundColor $sev[[string]$w.severity]
            Write-Host (' {0,4}%' -f $w.percent) -NoNewline -ForegroundColor $(if ($w.limited) { 'Red' } else { 'Gray' })
            Write-Host ('   ' + (Format-ChatOverlayReset $w.resetsAt $now) + $(if ($name -and $u.status) { "   $($u.status)" })) -ForegroundColor DarkGray
        }
    }
    foreach ($n in @($snap.header.notes)) {
        Write-Host "  $($n.text)" -ForegroundColor $(switch ($n.tone) { 'warn' { 'Yellow' } 'error' { 'Red' } default { 'DarkGray' } })
    }
    Write-Host ''
    $rows = @($snap.rows)
    if (-not $rows) { Write-Host '  no chats open' -ForegroundColor DarkGray }
    $width = Get-ChatqWidth
    $color = @{ waiting = 'Yellow'; 'needs-input' = 'Yellow'; cutoff = 'DarkYellow'; busy = 'Green'; running = 'Blue'; idle = 'DarkGray'; queued = 'Magenta' }
    foreach ($r in $rows) {
        $right = [string]$r.stateText
        $proj = if ($r.project) { "$($r.project)  " } else { '' }
        $room = $width - 6 - (Get-ChatCells $right) - (Get-ChatCells $proj)
        Write-Host ('  ' + $(if ($r.status -eq 'queued') { 'o' } else { '*' }) + ' ') -NoNewline -ForegroundColor $color[[string]$r.status]
        Write-Host $proj -NoNewline -ForegroundColor Cyan
        Write-Host (Format-ChatCell ([string]$r.title) $room) -NoNewline
        Write-Host " $right" -ForegroundColor $(if ($r.rank -eq 0) { 'Yellow' } else { 'DarkGray' })
        if ($r.prompt -and $snap.config.prompts) { Write-Host ('      ' + (Format-ChatCell ([string]$r.prompt) ($width - 8) -NoPad)) -ForegroundColor DarkGray }
    }
    Write-Host ''
}

#endregion
