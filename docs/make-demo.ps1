<#
Renders the README's queue frames: docs/demo-queue.svg and docs/demo-list.svg.

    powershell -NoProfile -ExecutionPolicy Bypass -File docs\make-demo.ps1

The output is the real thing - the real commands, run against a made-up
sandbox of chats (so no real title is ever drawn) - captured by a Write-Host of
our own. Defined here, it wins over the cmdlet for the dot-sourced script, and
records each line's text and colours; the frames are drawn from that. No
window, no screen capture, nothing taken from the console.

This file is ASCII, like the script it drives.
#>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$sb = Join-Path $root 'tests\.sandbox\demo'
if (Test-Path -LiteralPath $sb) { Remove-Item -LiteralPath $sb -Recurse -Force }
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- a sandbox of chats that never existed ---------------------------------
$claudeHome = Join-Path $sb 'claude'
$codexHome = Join-Path $sb 'codex'
$proj = Join-Path $sb 'work\parser'
foreach ($d in $claudeHome, $codexHome, $proj, (Join-Path $sb 'tool'), (Join-Path $sb 'code-user')) { $null = New-Item -ItemType Directory -Path $d -Force }
Copy-Item -LiteralPath (Join-Path $root 'VS-code-chat-manager.ps1') -Destination (Join-Path $sb 'tool')
$env:CLAUDE_CONFIG_DIR = $claudeHome
$env:CODEX_HOME = $codexHome
$env:CHAT_CODE_USER = Join-Path $sb 'code-user'
$env:CHATQ_CLAUDE = Join-Path $root 'tests\fake-claude.cmd'
$env:CHATQ_CODEX = $env:CHATQ_CLAUDE
$env:CHATQ_WATCHER = '1'

$now = [DateTimeOffset]::UtcNow
$reset = $now.AddMinutes(95)
$slug = $proj.TrimEnd('\') -replace '[^A-Za-z0-9]', '-'
$pdir = Join-Path (Join-Path $claudeHome 'projects') $slug
$null = New-Item -ItemType Directory -Path $pdir -Force
function New-DemoChat([string]$Id, [string]$Title, [double]$HoursAgo, [string]$Prompt, [switch]$CutOff) {
    $t = $now.AddHours(-$HoursAgo)
    $lines = @(
        ([ordered]@{ type = 'user'; message = [ordered]@{ role = 'user'; content = $Prompt }; timestamp = $t.ToString('o'); permissionMode = 'auto'; cwd = $proj; sessionId = $Id } | ConvertTo-Json -Compress -Depth 5)
        ([ordered]@{ type = 'assistant'; message = [ordered]@{ model = 'claude-opus-5'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = 'On it.' }) }; timestamp = $t.ToString('o'); cwd = $proj; sessionId = $Id } | ConvertTo-Json -Compress -Depth 6)
        ([ordered]@{ type = 'ai-title'; aiTitle = $Title; sessionId = $Id } | ConvertTo-Json -Compress)
    )
    if ($CutOff) {
        $lines += ([ordered]@{ type = 'assistant'; timestamp = $t.ToString('o'); cwd = $proj; sessionId = $Id
                message = [ordered]@{ model = '<synthetic>'; role = 'assistant'; content = @([ordered]@{ type = 'text'; text = "You've hit your session limit" }) }
                quotaLimits = [ordered]@{ status = 'rejected'; resetsAt = $reset.ToUnixTimeSeconds(); rateLimitType = 'five_hour' }
                error = 'rate_limit'; isApiErrorMessage = $true } | ConvertTo-Json -Compress -Depth 6)
    }
    $p = Join-Path $pdir "$Id.jsonl"
    [System.IO.File]::WriteAllText($p, ($lines -join "`n") + "`n", $utf8)
    (Get-Item -LiteralPath $p).LastWriteTime = $t.LocalDateTime
}
New-DemoChat '1a2b3c4d-0000-4000-8000-000000000001' 'Parser rewrite and plugin unification' 0.4 'unify the parser entry points' -CutOff
New-DemoChat '1a2b3c4d-0000-4000-8000-000000000002' 'Card layout redesign' 1.2 'redesign the card layout' -CutOff
New-DemoChat '1a2b3c4d-0000-4000-8000-000000000003' 'Release notes for 2.4' 2.5 'draft the release notes'
New-DemoChat '1a2b3c4d-0000-4000-8000-000000000004' 'Flaky upload test' 30 'why does the upload test flake'
[System.IO.File]::WriteAllText((Join-Path $claudeHome '.claude.json'),
    ('{"cachedUsageUtilization":{"fetchedAtMs":' + $now.AddMinutes(-4).ToUnixTimeMilliseconds() + ',"utilization":{"limits":[' +
        '{"kind":"session","percent":100,"resets_at":"' + $reset.ToString('o') + '","scope":null},' +
        '{"kind":"weekly_all","percent":46,"resets_at":"' + $now.AddDays(4).ToString('o') + '","scope":null}]}}}'), $utf8)

. (Join-Path $sb 'tool\VS-code-chat-manager.ps1')
Set-Location -LiteralPath $proj
$script:ChatqToastSeam = { param($t, $x) }
$script:ChatqSpawn = { $true }
function Get-ChatqWidth { 92 }            # a fixed width, whatever this console is
# The sandbox's config dir is part of the lane's name, since a job remembers
# which account it was queued from - here that would only be a temp path.
function Format-ChatqLane { param([string]$Lane) (Get-Culture).TextInfo.ToTitleCase([string](($Lane -split '\|', 2)[0])) }

# --- recording ---------------------------------------------------------------
$script:Lines = [System.Collections.Generic.List[object]]::new()
$script:Cur = [System.Collections.Generic.List[object]]::new()
function Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments)]$Object, [switch]$NoNewline,
        $ForegroundColor, $BackgroundColor, $Separator = ' ')
    $text = (@($Object) | ForEach-Object { [string]$_ }) -join $Separator
    $script:Cur.Add([pscustomobject]@{ Text = $text; Color = [string]$ForegroundColor })
    if (-not $NoNewline) { $script:Lines.Add(@($script:Cur)); $script:Cur = [System.Collections.Generic.List[object]]::new() }
}
function Invoke-Frame([string]$Typed, [scriptblock]$Run) {
    $script:Lines.Clear()
    $script:Lines.Add(@([pscustomobject]@{ Text = 'PS> '; Color = 'DarkGray' }, [pscustomobject]@{ Text = $Typed; Color = 'White' }))
    & $Run
    return @($script:Lines)
}

# --- drawing -----------------------------------------------------------------
$palette = @{
    '' = '#d4d4d4'; 'Gray' = '#d4d4d4'; 'White' = '#ffffff'; 'DarkGray' = '#8a8a8a'; 'Cyan' = '#4fc1ff'; 'Green' = '#6ccb5f'
    'Yellow' = '#e5c07b'; 'Red' = '#f14c4c'; 'Magenta' = '#c678dd'; 'Blue' = '#61afef'
}
function ConvertTo-DemoSvg([object[]]$Frame, [string]$Path, [string]$Caption) {
    $lh = 19; $pad = 16; $top = 38
    $cols = 0
    foreach ($l in $Frame) { $n = (@($l) | ForEach-Object { $_.Text }) -join ''; if ($n.Length -gt $cols) { $cols = $n.Length } }
    $w = [int]([Math]::Max(640, $cols * 8.4 + 2 * $pad))
    $h = $top + $Frame.Count * $lh + $pad
    $x = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    $b = [System.Text.StringBuilder]::new()
    [void]$b.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$w`" height=`"$h`" viewBox=`"0 0 $w $h`" role=`"img`" aria-label=`"$(& $x $Caption)`">")
    [void]$b.AppendLine("<rect width=`"$w`" height=`"$h`" rx=`"8`" fill=`"#1e1e1e`"/>")
    foreach ($c in @(@(18, '#ff5f57'), @(38, '#febc2e'), @(58, '#28c840'))) { [void]$b.AppendLine("<circle cx=`"$($c[0])`" cy=`"16`" r=`"6`" fill=`"$($c[1])`"/>") }
    # white-space:pre, not only xml:space - browsers now ignore the attribute,
    # and collapsed spaces undo every column
    [void]$b.AppendLine('<g font-family="Cascadia Mono, Consolas, Menlo, monospace" font-size="14" xml:space="preserve" style="white-space:pre">')
    $y = $top
    foreach ($l in $Frame) {
        [void]$b.Append("<text x=`"$pad`" y=`"$y`">")
        foreach ($s in @($l)) {
            if (-not $s.Text) { continue }
            $fill = if ($palette.ContainsKey($s.Color)) { $palette[$s.Color] } else { $palette[''] }
            # the sandbox is a temp folder; the frame says where a project would be
            $t = $s.Text.Replace($proj, 'D:\src\parser')
            # no-break spaces: they hold the columns in every renderer, where
            # white-space rules on SVG text are honoured by some and not others
            [void]$b.Append("<tspan fill=`"$fill`">$((& $x $t).Replace(' ', '&#160;'))</tspan>")
        }
        [void]$b.AppendLine('</text>')
        $y += $lh
    }
    [void]$b.AppendLine('</g></svg>')
    [System.IO.File]::WriteAllText($Path, $b.ToString(), $utf8)
}

# --- the frames ----------------------------------------------------------------
# the lock held: to chatq that is a running watcher, so it starts none - and
# what that watcher knows is what it would have written: the limit, and when
New-ChatqDir $script:ChatqData
Save-ChatqJson $script:ChatqStatePath ([ordered]@{
        pid = $PID; blocked = @{ "claude|$claudeHome" = @{ until = $reset.UtcDateTime.ToString('o'); type = 'five_hour'; source = 'transcript' } }; outage = @{}
    })
$lock = [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $f1 = Invoke-Frame "chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'" {
        chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'
    }
    $long = "Assess this new card idea before we build it.`n`n" + (('It should keep the current grid, fold the detail rows away, and still read well on a narrow panel. ') * 12)
    $null = Invoke-Frame 'x' { chatq 'card layout' -Prompt $long }
    $f2 = Invoke-Frame 'chatqlist' { chatqlist }
}
finally { $lock.Dispose() }
ConvertTo-DemoSvg $f1 (Join-Path $here 'demo-queue.svg') 'chatq queueing a prompt for a chat picked by its title'
ConvertTo-DemoSvg $f2 (Join-Path $here 'demo-list.svg') 'chatqlist showing two queued prompts, the usage and the limit reset'
Set-Location -LiteralPath $here
Remove-Item -LiteralPath $sb -Recurse -Force -EA SilentlyContinue
Microsoft.PowerShell.Utility\Write-Host '  wrote docs/demo-queue.svg, docs/demo-list.svg'
