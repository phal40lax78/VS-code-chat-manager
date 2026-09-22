<#
chatq - hold prompts while the usage limit is hit, deliver them when it resets.

The VS Code panel already queues a message sent while Claude is working. What
it will not do is hold one sent while the subscription limit is exhausted:
that is refused with "You've hit your session limit" and simply dropped. chatq
is the queue for that moment. Aim a prompt at any existing chat by title; when
the limit resets, chatq resumes each chat in turn, sends its prompt, runs it to
the end, and tells your phone how it went.

INSTALL
    iex (irm https://raw.githubusercontent.com/phal40lax78/chatq/main/install.ps1)
  or, with the file already on disk:
    . "$HOME\Tools\chatq\chatq.ps1"
    chatqinstall
  The leading dot matters: `. file.ps1` loads the commands into this shell,
  `& file.ps1` runs them into a scope that is thrown away. Same as chatrm.

COMMANDS
    chatq <title|id> [-Prompt s]     queue a prompt for that chat; no -Prompt
                                     opens an editor tab to write it in
    chatq <title> -Continue          queue "continue" for a chat the limit cut off
    chatq <n>                        open queued prompt n in the editor
    chatqlist [-Board] [-All]        what is queued, when it sends, what ran
    chatqrm <n|id> [-Force]          drop a job (-Force cancels a running one)
    chatqrun [<n>] [-Now] [-Stop]    requeue n / skip the wait / stop the watcher
    chatqlog <n> [-Raw]              what a run did
    chatqnotify -ApiKey k -Device d  phone alerts through Join; -Test sends one
    chatqinstall / chatquninstall    add to, or drop from, your profile
    chatq                            cheat sheet and the queue

PICKING THE CHAT   decided when you queue, so you see it while you are here
  An id is that chat. Otherwise the title is matched in this project first -
  exact, then contains, then every word you typed - and in every project only
  when this one has no match. Nothing matched at all: the candidates are every
  chat in this project. Of several candidates the newest wins - unless others
  were active within 5 hours of it (one limit window), and then the most
  relevant one does: character-bigram cosine of what you typed and the prompt
  against each chat's title and prompts. Pure PowerShell, no model call, the
  same answer every time, Hangul and English alike.

WHEN IT RUNS
  A background watcher (one per machine, a hidden PowerShell) reads when the
  limit resets from the record Claude writes into the transcript it cut off
  ("quotaLimits": status rejected, resetsAt), wakes a minute after, and first
  sends a throwaway "ok" that saves nothing - sending the real prompt while
  still limited would plant it, and an error after it, in your chat. Then one
  job at a time, oldest first, each in the permission mode its chat last used,
  with anything that would ask a question auto-denied: nobody is there to
  answer, so that chat is parked as needs-input and the queue moves on.
  "API Error: 529 Overloaded" (any 5xx) is Anthropic's trouble, not a limit:
  the job goes back in the queue and waits on status.claude.com - read every
  minute, resumed the moment Claude Code shows operational again, and tried
  anyway every 15 minutes in case the page lags.

FILES   everything in data/ beside this script, nothing anywhere else
    queue/<id>.json + "#<n> <title>.md"   one job, its prompt (edit it freely)
    logs/<id>.jsonl                        the raw run
    queue.md                               live board - open it, Ctrl+Shift+V
    config.json                            Join key, DPAPI-protected on Windows
    chat-index.csv                         what Tab completes from
#>

# Bump this in the same commit that changes behaviour - chatqinstall compares it
# against data/version.txt to say whether a reinstall actually landed anything.
$script:ChatqVersion = '0.1.0'

$script:ChatqPreview = 3
$script:ChatqClaudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$script:ChatqCodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
# $IsMacOS/$IsWindows exist only on pwsh 6+; reading an undefined variable
# throws under StrictMode, and this file is dot-sourced into whatever session
# the user already has. Get-Variable answers without touching it.
$script:ChatqIsMac = [bool](Get-Variable -Name IsMacOS -ValueOnly -EA SilentlyContinue)
$script:ChatqIsWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

# Every runtime file lives in data/ beside the script, never in AppData or
# TEMP - the folder is the whole installation, and deleting it is the uninstall.
$script:ChatqData = Join-Path $PSScriptRoot 'data'
$script:ChatqIndexPath = Join-Path $script:ChatqData 'chat-index.csv'
$script:ChatqVersionPath = Join-Path $script:ChatqData 'version.txt'
$script:ChatqQueueDir = Join-Path $script:ChatqData 'queue'
$script:ChatqLogDir = Join-Path $script:ChatqData 'logs'
$script:ChatqConfigPath = Join-Path $script:ChatqData 'config.json'
$script:ChatqStatePath = Join-Path $script:ChatqData 'state.json'
$script:ChatqLockPath = Join-Path $script:ChatqData 'watcher.lock'
$script:ChatqPidPath = Join-Path $script:ChatqData 'watcher.pid'
$script:ChatqWakePath = Join-Path $script:ChatqData 'wake'
$script:ChatqStopPath = Join-Path $script:ChatqData 'stop'
$script:ChatqBoardPath = Join-Path $script:ChatqData 'queue.md'
$script:ChatqScriptPath = $PSCommandPath

# This file stays pure ASCII. Windows PowerShell 5.1 reads a .ps1 without a BOM
# in the ANSI code page - 949 on a Korean machine - so a literal middle dot or
# Hangul in a string here is mangled before a line of it runs. Non-ASCII text
# is built from code points instead; everything read from disk says UTF-8.
$script:ChatqDot = [string][char]0x00B7
$script:ChatqEllipsis = [string][char]0x2026

# What Claude Code itself sends when it resumes a turn the limit cut off - an
# isMeta user message with exactly this text. -Continue sends the same words.
$script:ChatqContinueText = 'Continue from where you left off.'

# Claude's public status page. The "Claude Code" component is what a run
# stopped by "API Error: 529 Overloaded" waits on before it is tried again.
$script:ChatqStatusUrl = 'https://status.claude.com/api/v2/components.json'
$script:ChatqStatusComponent = 'Claude Code'

# Caches and flags, set here so a caller's Set-StrictMode -Version Latest -
# which this dot-sourced file inherits - never meets one unset. Every command
# also turns StrictMode off for itself; these cover the load itself.
$script:ChatqIndexStamp = $null
$script:ChatqIndexCache = @()
$script:ChatqCodexNames = $null
$script:ChatqCodexNamesAt = 0
$script:ChatqCliVersions = @{}
$script:ChatqAwake = $false
$script:ChatqAwakeProc = $null
$script:ChatqLastAlertError = $null
$script:ChatqForeground = $false

#region index -----------------------------------------------------------------
# Lifted from chatrm (Get-ChatIndex / Save-ChatIndex / Sync-ChatIndex) and
# renamed: both files are dot-sourced into the same global scope, so a shared
# name would have chatq's index quietly overwrite chatrm's functions.
# Reading every transcript takes ~30s, so nothing does it twice: a file is only
# re-read when its size or mtime changed.

$script:ChatqIndexSep = [char]0x1F   # unit separator: never appears in prompt text

function Get-ChatqIndex {
    if (-not (Test-Path -LiteralPath $script:ChatqIndexPath)) { return @() }
    $stamp = try {
        $fi = [System.IO.FileInfo]::new($script:ChatqIndexPath)
        "$($fi.LastWriteTimeUtc.Ticks):$($fi.Length)"
    }
    catch { $null }
    if ($stamp -and $stamp -eq $script:ChatqIndexStamp) { return $script:ChatqIndexCache }
    try {
        $rows = @(Import-Csv -LiteralPath $script:ChatqIndexPath | ForEach-Object {
                [pscustomobject]@{
                    Provider = $_.Provider
                    Path     = $_.Path
                    Size     = [int64]$_.Size
                    Mtime    = [int64]$_.Mtime
                    Id       = $_.Id
                    Title    = $_.Title
                    Titled   = $_.Titled
                    Group    = $_.Group
                    Hidden   = $_.Hidden -eq 'True'
                    When     = $_.When
                    First    = @($_.First -split $script:ChatqIndexSep | Where-Object { $_ })
                    Last     = @($_.Last -split $script:ChatqIndexSep | Where-Object { $_ })
                }
            })
        $script:ChatqIndexCache = $rows
        $script:ChatqIndexStamp = $stamp
        return $rows
    }
    catch { return @() }
}

function Save-ChatqIndex {
    param([object[]]$Rows)
    try {
        $dir = Split-Path $script:ChatqIndexPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Rows | ForEach-Object {
            [pscustomobject]@{
                Provider = $_.Provider; Path = $_.Path; Size = $_.Size; Mtime = $_.Mtime
                Id = $_.Id; Title = $_.Title; Titled = $_.Titled; Group = $_.Group
                Hidden = $_.Hidden; When = $_.When
                First = (@($_.First) -join $script:ChatqIndexSep)
                Last = (@($_.Last) -join $script:ChatqIndexSep)
            }
        } | Export-Csv -LiteralPath $script:ChatqIndexPath -NoTypeInformation -Encoding UTF8
    }
    catch {}
}

function Sync-ChatqIndex {
    # returns the index rows for $Provider, re-reading only what changed
    param([string[]]$Provider, [switch]$Force)
    $names = if ($Provider) { $Provider } else { @($script:ChatqProviders.Keys) }
    $cached = @(Get-ChatqIndex)
    $old = @{}
    foreach ($r in $cached) {
        if (-not $r.Path) { continue }
        if ($Force -and $names -contains $r.Provider) { continue }
        $old[$r.Path] = $r
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $fresh = 0
    $reused = 0
    foreach ($name in $names) {
        $p = $script:ChatqProviders[$name]
        if (-not $p) { Write-Warning "unknown provider '$name'"; continue }
        foreach ($file in @(& $p.Discover)) {
            $hit = $old[$file.FullName]
            if ($hit -and $hit.Size -eq $file.Length -and $hit.Mtime -eq $file.LastWriteTimeUtc.Ticks) {
                $rows.Add($hit)
                $reused++
                continue
            }
            $rec = & $p.Describe $file
            if (-not $rec) { continue }
            $fresh++
            $rows.Add([pscustomobject]@{
                    Provider = $name
                    Path     = $file.FullName
                    Size     = $file.Length
                    Mtime    = $file.LastWriteTimeUtc.Ticks
                    Id       = $rec.Id
                    Title    = $rec.Title
                    Titled   = $rec.TitleSource
                    Group    = $rec.Group
                    Hidden   = [bool]$rec.Hidden
                    When     = $rec.When.ToString('o')
                    First    = @($rec.First)
                    Last     = @($rec.Last)
                })
        }
    }
    $others = @($cached | Where-Object { $names -notcontains $_.Provider })
    $stale = ($reused + $others.Count) -ne $cached.Count
    if ($fresh -or $stale) { Save-ChatqIndex @($others + $rows.ToArray()) }
    return $rows.ToArray()
}

#endregion

#region generic helpers (from chatrm) -----------------------------------------

function Get-ChatqAge {
    param([datetime]$When)
    $s = ([datetime]::Now - $When).TotalSeconds
    if ($s -lt 60) { return 'now' }
    if ($s -lt 3600) { return "$([math]::Floor($s / 60))m" }
    if ($s -lt 86400) { return "$([math]::Floor($s / 3600))h" }
    if ($s -lt 2592000) { return "$([math]::Floor($s / 86400))d" }
    if ($s -lt 31536000) { return "$([math]::Floor($s / 2592000))mo" }
    return "$([math]::Floor($s / 31536000))y"
}

function Format-ChatqTitle {
    param([string]$Text, [int]$Width = 60)
    if (-not $Text) { return '(empty)' }
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Width) { $t = $t.Substring(0, $Width).TrimEnd() + '...' }
    return $t
}

function Test-ChatqNoise {
    # prompts that are machinery, not something the user typed
    param([string]$Text)
    $Text.StartsWith('<') -or $Text.StartsWith('Caveat') -or $Text -like '*system-reminder*' -or
    $Text -like '`[Request interrupted*'
}

function Select-ChatqDistinctRun {
    # drop consecutive repeats - Codex re-injects the same prompt every turn
    param([string[]]$Texts)
    $out = [System.Collections.Generic.List[string]]::new()
    $prev = $null
    foreach ($t in $Texts) {
        $key = ($t -replace '[^\w]', '').ToLowerInvariant()
        $key = $key.Substring(0, [Math]::Min(80, $key.Length))
        if ($key -ne $prev) { $out.Add($t) }
        $prev = $key
    }
    return $out.ToArray()
}

function Open-ChatqRead {
    # Codex holds every rollout open for the life of the window, and Claude
    # appends to the transcript of a running chat: share what the writer holds.
    param([string]$Path)
    [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
}

function Read-ChatqAllText {
    param([string]$Path)
    $fs = Open-ChatqRead $Path
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
}

function Read-ChatqChunk {
    # head+tail only - transcripts run to megabytes and there are thousands
    param([string]$Path, [int]$Size = 524288)
    $fi = [System.IO.FileInfo]::new($Path)
    try { $fs = Open-ChatqRead $Path } catch { return $null }
    try {
        if ($fi.Length -le 2 * $Size) {
            $buf = [byte[]]::new($fi.Length)
            $fs.Read($buf, 0, $buf.Length) | Out-Null
            return [pscustomobject]@{ Head = [System.Text.Encoding]::UTF8.GetString($buf); Tail = ''; Split = $false }
        }
        $hb = [byte[]]::new($Size)
        $fs.Read($hb, 0, $Size) | Out-Null
        $tb = [byte[]]::new($Size)
        $fs.Seek(-$Size, [System.IO.SeekOrigin]::End) | Out-Null
        $fs.Read($tb, 0, $Size) | Out-Null
        return [pscustomobject]@{
            Head  = [System.Text.Encoding]::UTF8.GetString($hb)
            Tail  = [System.Text.Encoding]::UTF8.GetString($tb)
            Split = $true
        }
    }
    finally { $fs.Dispose() }
}

function Read-ChatqTail {
    # The last $Size bytes as text. Cutting mid-character only garbles the first
    # few bytes, which a caller looking for whole JSON lines skips anyway.
    param([string]$Path, [int64]$Size)
    try { $fs = Open-ChatqRead $Path } catch { return $null }
    try {
        $n = [int][Math]::Min($Size, $fs.Length)
        if ($n -le 0) { return '' }
        $fs.Seek(-$n, [System.IO.SeekOrigin]::End) | Out-Null
        $buf = [byte[]]::new($n)
        $got = 0
        while ($got -lt $n) {
            $r = $fs.Read($buf, $got, $n - $got)
            if ($r -le 0) { break }
            $got += $r
        }
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $got)
    }
    finally { $fs.Dispose() }
}

function Find-ChatqTailString {
    # The last value of a JSON string key, looking back from the end in growing
    # windows. The permission mode is written on user records only, and in a
    # 7 MB chat the last one sat 240 KB from the end - past any fixed chunk.
    param([string]$Path, [string]$Key)
    $len = try { ([System.IO.FileInfo]::new($Path)).Length } catch { 0 }
    foreach ($size in 65536, 1048576, 8388608, 67108864) {
        $t = Read-ChatqTail $Path $size
        $v = Get-ChatqJsonString $t $Key
        if ($v) { return $v }
        if ($size -ge $len) { break }
    }
    return $null
}

function Get-ChatqJsonLines {
    # index scan for a marker, not a line split + pipeline - that was 10x slower
    param([string]$Text, [string[]]$Marker, [int]$Count, [switch]$FromEnd,
        [string[]]$Skip = @('"tool_result"', '"isMeta":true', 'system-reminder'))
    $out = [System.Collections.Generic.List[string]]::new()
    if (-not $Text) { return , @() }
    $needle = $Marker | Where-Object { $Text.IndexOf($_, [StringComparison]::Ordinal) -ge 0 } | Select-Object -First 1
    if (-not $needle) { return , @() }
    $Marker = $needle
    $pos = if ($FromEnd) { $Text.Length - 1 } else { 0 }
    while ($out.Count -lt $Count) {
        $j = if ($FromEnd) { $Text.LastIndexOf($Marker, [Math]::Min($pos, $Text.Length - 1), [StringComparison]::Ordinal) }
        else { $Text.IndexOf($Marker, $pos, [StringComparison]::Ordinal) }
        if ($j -lt 0) { break }
        $s = $Text.LastIndexOf("`n", $j) + 1
        $e = $Text.IndexOf("`n", $j)
        if ($e -lt 0) { $e = $Text.Length }
        $line = $Text.Substring($s, $e - $s)
        $keep = $line.Length -lt 200000
        if ($keep) { foreach ($s2 in $Skip) { if ($line -like "*$s2*") { $keep = $false; break } } }
        if ($keep) {
            if ($FromEnd) { $out.Insert(0, $line) } else { $out.Add($line) }
        }
        $pos = if ($FromEnd) { $s - 1 } else { $e + 1 }
        if ($FromEnd -and $pos -lt 0) { break }
        if (-not $FromEnd -and $pos -ge $Text.Length) { break }
    }
    return , $out.ToArray()
}

function Get-ChatqTimestampFromText {
    param($Prompts, [System.IO.FileInfo]$File)
    foreach ($t in @($Prompts.Tail, $Prompts.Head)) {
        if (-not $t) { continue }
        $m = [regex]::Matches($t, '"timestamp":\s*"([^"]+)"')
        if ($m.Count) {
            try {
                return [datetime]::Parse($m[$m.Count - 1].Groups[1].Value,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
            }
            catch {}
        }
    }
    return $File.LastWriteTime
}

function Get-ChatqHeadTailPrompts {
    # walk head and tail for prompt lines, parse only those, and fall back to the
    # whole file when one turn is bigger than the chunk and hides every prompt
    param([string]$Path, [string[]]$Marker, [scriptblock]$Parse, [int]$Count = $script:ChatqPreview)
    $chunk = Read-ChatqChunk $Path
    if (-not $chunk) { return $null }
    $scan = $Count * 4
    $head = $chunk.Head
    $tail = if ($chunk.Split) { $chunk.Tail } else { $chunk.Head }
    $first = @(); $last = @()
    foreach ($pass in 1, 2) {
        $headLines = Get-ChatqJsonLines $head $Marker $scan
        $tailLines = Get-ChatqJsonLines $tail $Marker $scan -FromEnd
        $headTexts = Select-ChatqDistinctRun @($headLines | ForEach-Object { & $Parse $_ } | Where-Object { $_ })
        $tailTexts = Select-ChatqDistinctRun @($tailLines | ForEach-Object { & $Parse $_ } | Where-Object { $_ })
        $first = @($headTexts | Select-Object -First $Count)
        $last = @($tailTexts | Select-Object -Last $Count)
        if (-not $chunk.Split -or ($first.Count -gt 0 -and $last.Count -gt 0)) { break }
        if ($pass -eq 1) {
            $head = Read-ChatqAllText $Path
            $tail = $head
            $chunk = [pscustomobject]@{ Head = $head; Tail = ''; Split = $false }
        }
    }
    return [pscustomobject]@{ First = $first; Last = $last; Head = $chunk.Head; Tail = $chunk.Tail }
}

function Convert-ChatqJsonEscaped {
    param([string]$Text)
    if ($Text -notlike '*\*') { return $Text }
    try { return ('"' + $Text + '"') | ConvertFrom-Json } catch { return $Text }
}

function Get-ChatqJsonString {
    # index lookup rather than regex: this runs over megabyte-sized text.
    # the LAST occurrence wins - titles and modes are appended, never rewritten
    param([string]$Text, [string]$Key)
    if (-not $Text) { return $null }
    $best = -1
    $len = 0
    foreach ($anchor in @("`"$Key`":`"", "`"$Key`": `"")) {
        $i = $Text.LastIndexOf($anchor, [StringComparison]::Ordinal)
        if ($i -gt $best) { $best = $i; $len = $anchor.Length }
    }
    if ($best -lt 0) { return $null }
    $rest = $Text.Substring($best + $len)
    if ($rest -match '^((?:[^"\\]|\\.)*)"') { return $Matches[1] }
    return $null
}

function Read-ChatqJsonObjectAt {
    # The {...} that starts at $Start, by brace matching - strings honoured - so
    # one object can be lifted out of a file and parsed without parsing the rest
    param([string]$Text, [int]$Start)
    $depth = 0; $inStr = $false; $esc = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq '\') { $esc = $true }
            elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($Start, $i - $Start + 1) }
        }
    }
    return $null
}

#endregion

#region providers (Discover/Describe from chatrm) -----------------------------

function Read-ChatqClaudePrompt {
    param([string]$Line)
    if ($Line -like '*"tool_result"*' -or $Line -like '*"isMeta":true*' -or $Line -like '*system-reminder*') { return $null }
    try { $o = $Line | ConvertFrom-Json } catch { return $null }
    if ($o.type -ne 'user') { return $null }
    $c = $o.message.content
    if ($c -isnot [string]) { $c = ($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ' }
    if (-not $c) { return $null }
    $c = $c.Trim()
    if (Test-ChatqNoise $c) { return $null }
    return ($c -replace '\s+', ' ')
}

function Get-ChatqCodexThreadNames {
    # Codex keeps the thread's name in session_index.jsonl, never in the rollout
    $path = Join-Path $script:ChatqCodexHome 'session_index.jsonl'
    $f = Get-Item -LiteralPath $path -EA SilentlyContinue
    $stamp = if ($f) { $f.LastWriteTimeUtc.Ticks } else { 0 }
    if ($script:ChatqCodexNames -and $script:ChatqCodexNamesAt -eq $stamp) { return $script:ChatqCodexNames }
    $map = @{}
    if ($f) {
        foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8 -EA SilentlyContinue)) {
            $o = try { $line | ConvertFrom-Json } catch { $null }
            if ($o.id -and $o.thread_name) { $map[[string]$o.id] = [string]$o.thread_name }
        }
    }
    $script:ChatqCodexNames = $map
    $script:ChatqCodexNamesAt = $stamp
    return $map
}

function Read-ChatqCodexPrompt {
    param([string]$Line)
    try { $o = $Line | ConvertFrom-Json } catch { return $null }
    if ($o.payload.role -ne 'user') { return $null }
    $t = ($o.payload.content | Where-Object { $_.type -eq 'input_text' } | ForEach-Object { $_.text }) -join ' '
    if (-not $t) { return $null }
    $t = $t.Trim()
    $i = $t.IndexOf('## My request for Codex:')
    if ($i -ge 0) { $t = $t.Substring($i + 24).Trim() }
    if ($t.StartsWith('# AGENTS.md') -or $t.StartsWith('<') -or $t.StartsWith('# Context from my IDE')) { return $null }
    if (Test-ChatqNoise $t) { return $null }
    return ($t -replace '\s+', ' ')
}

# Copilot is chatrm's third provider and is left out on purpose: it has no CLI
# that can resume a chat headless, so there is nothing to deliver a prompt with.
$script:ChatqProviders = [ordered]@{

    claude = [pscustomobject]@{
        Root     = (Join-Path $script:ChatqClaudeHome 'projects')
        Discover = {
            # only projects/<slug>/<uuid>.jsonl - a recursive sweep also drags in
            # workflow journals and agent transcripts, which are not chats
            $root = Join-Path $script:ChatqClaudeHome 'projects'
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
                    Get-ChildItem -LiteralPath $_.FullName -Filter *.jsonl -File |
                        Where-Object { $_.BaseName -match '^[0-9a-fA-F-]{36}$' }
                }
            }
        }
        Describe = {
            param($File)
            $p = Get-ChatqHeadTailPrompts $File.FullName '"type":"user"' ${function:Read-ChatqClaudePrompt}
            if (-not $p) { return $null }
            $nl = $p.Head.IndexOf("`n")
            $firstLine = if ($nl -ge 0) { $p.Head.Substring(0, $nl) } else { $p.Head }
            $hidden = $firstLine -like '*"isSidechain":true*'
            $title = $null; $source = 'first message'
            foreach ($t in @($p.Tail, $p.Head)) {
                if (-not $title) { $title = Get-ChatqJsonString $t 'customTitle'; if ($title) { $source = 'renamed' } }
            }
            if (-not $title) {
                foreach ($t in @($p.Tail, $p.Head)) {
                    if (-not $title) { $title = Get-ChatqJsonString $t 'aiTitle'; if ($title) { $source = 'auto' } }
                }
            }
            if ($title) { $title = Convert-ChatqJsonEscaped $title }
            if (-not $title) { $title = @($p.First)[0] }
            [pscustomobject]@{
                Id          = $File.BaseName
                Title       = Format-ChatqTitle $title
                TitleSource = $source
                Group       = $File.Directory.Name
                Hidden      = $hidden
                When        = Get-ChatqTimestampFromText $p $File
                First       = $p.First
                Last        = $p.Last
            }
        }
    }

    codex  = [pscustomobject]@{
        Root     = (Join-Path $script:ChatqCodexHome 'sessions')
        Discover = {
            $root = Join-Path $script:ChatqCodexHome 'sessions'
            if (Test-Path -LiteralPath $root) { Get-ChildItem -LiteralPath $root -Filter *.jsonl -Recurse -File }
        }
        Describe = {
            param($File)
            $p = Get-ChatqHeadTailPrompts $File.FullName @('"role":"user"', '"role": "user"') ${function:Read-ChatqCodexPrompt}
            if (-not $p) { return $null }
            $id = if ($File.BaseName -match '([0-9a-fA-F-]{36})$') { $Matches[1] } else { $File.BaseName }
            $cwd = Get-ChatqJsonString $p.Head 'cwd'
            $group = if ($cwd) { Split-Path ($cwd -replace '\\\\', '\') -Leaf } else { 'codex' }
            $named = (Get-ChatqCodexThreadNames)[$id]
            $title = if ($named) { $named } else { @($p.First)[0] }
            [pscustomobject]@{
                Id          = $id
                Title       = Format-ChatqTitle $title
                TitleSource = if ($named) { 'thread name' } else { 'first message' }
                Group       = $group
                Hidden      = $false
                When        = Get-ChatqTimestampFromText $p $File
                First       = $p.First
                Last        = $p.Last
            }
        }
    }
}

#endregion

#region project scope (from chatrm) -------------------------------------------

function Get-ChatqProjectScope {
    # Claude names its project folder after the whole path with every
    # non-alphanumeric turned into a dash; Codex records the leaf folder name.
    param([string]$Path = $PWD.Path)
    $full = $Path.TrimEnd('\', '/')
    [pscustomobject]@{
        Slug = ($full -replace '[^A-Za-z0-9]', '-')
        Leaf = Split-Path $full -Leaf
    }
}

function Test-ChatqInProject {
    # Exact, never a prefix: the slug for D:\src\app is a prefix of the one for
    # D:\src\app-Mobile. Case-insensitive, since drive letters vary.
    param($Row, $Scope)
    if (-not $Row.Group) { return $false }
    if ($Row.Provider -eq 'claude') { return $Row.Group -eq $Scope.Slug }
    return $Row.Group -eq $Scope.Leaf
}

function Select-ChatqInProject {
    # Rows of the project being stood in; all rows when this directory is not a
    # project any tool knows, so running from elsewhere still offers something
    param([object[]]$Rows, [switch]$AllProjects)
    if ($AllProjects -or -not $Rows) { return $Rows }
    $scope = Get-ChatqProjectScope
    $mine = @($Rows | Where-Object { Test-ChatqInProject $_ $scope })
    if ($mine) { return $mine }
    return $Rows
}

function ConvertTo-ChatqDate {
    # Untyped on purpose. pwsh 7's ConvertFrom-Json hands ISO timestamps back
    # as [datetime] already (5.1 keeps them strings); a [string] parameter would
    # flatten that to local wall-clock time with no zone, and ToLocalTime would
    # then shift it a second time by the UTC offset.
    param($Text)
    if (-not $Text) { return $null }
    if ($Text -is [datetime]) {
        if ($Text.Kind -eq [System.DateTimeKind]::Utc) { return $Text.ToLocalTime() }
        return $Text
    }
    try {
        return [datetime]::Parse([string]$Text, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
    }
    catch { return $null }
}

#endregion

#region resolver --------------------------------------------------------------
# Runs when you queue, not when the limit resets: you are at the keyboard now
# and gone then, so the pick is printed while a wrong one can still be undone.

$script:ChatqWindowHours = 5    # one usage-limit window

function ConvertTo-ChatqNorm {
    # NFC, because macOS types Hangul decomposed (NFD) and the transcript holds
    # it composed - the same title would otherwise never compare equal
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text.Normalize([System.Text.NormalizationForm]::FormC)
    return ($t -replace '\s+', ' ').Trim()
}

function Get-ChatqBigrams {
    # Character pairs of each word, padded so a word's first and last letters
    # count too. Pairs, not words: Korean glues particles onto nouns (card +
    # object marker is one word), so whole-word matching misses what two-letter
    # overlap catches.
    # Hangul syllables are letters to IsLetterOrDigit, so no language switch.
    param([string]$Text)
    $d = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    if (-not $Text) { return , $d }
    $t = $Text.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    $sb = [System.Text.StringBuilder]::new($t.Length + 2)
    foreach ($ch in $t.ToCharArray()) {
        if ([char]::IsLetterOrDigit($ch)) { [void]$sb.Append($ch) } else { [void]$sb.Append(' ') }
    }
    foreach ($tok in $sb.ToString().Split([char[]]@(' '), [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $p = " $tok "
        for ($i = 0; $i -lt $p.Length - 1; $i++) {
            $k = $p.Substring($i, 2)
            $v = 0
            if ($d.TryGetValue($k, [ref]$v)) { $d[$k] = $v + 1 } else { $d[$k] = 1 }
        }
    }
    return , $d
}

function Get-ChatqCosine {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B -or $A.Count -eq 0 -or $B.Count -eq 0) { return 0.0 }
    $dot = 0.0
    foreach ($k in $A.Keys) {
        $v = 0
        if ($B.TryGetValue($k, [ref]$v)) { $dot += $A[$k] * $v }
    }
    if ($dot -eq 0) { return 0.0 }
    $na = 0.0; foreach ($v in $A.Values) { $na += $v * $v }
    $nb = 0.0; foreach ($v in $B.Values) { $nb += $v * $v }
    return $dot / ([Math]::Sqrt($na) * [Math]::Sqrt($nb))
}

function Get-ChatqRelevance {
    # 0.6 on the title: what was typed was meant as a title. 0.4 on the chat's
    # own opening and latest prompts against what was typed plus the prompt -
    # that is what separates two chats whose titles look alike.
    param($Row, [string]$Typed, [string]$Prompt)
    $title = Get-ChatqCosine (Get-ChatqBigrams $Typed) (Get-ChatqBigrams $Row.Title)
    $q = $Typed
    if ($Prompt) { $q += ' ' + $Prompt.Substring(0, [Math]::Min(2000, $Prompt.Length)) }
    $body = (@($Row.First) + @($Row.Last)) -join ' '
    $content = Get-ChatqCosine (Get-ChatqBigrams $q) (Get-ChatqBigrams $body)
    return [Math]::Round(0.6 * $title + 0.4 * $content, 3)
}

function Test-ChatqTitleEquals {
    # The index clips titles at 60 characters with '...', so a long title typed
    # in full never equals the stored one - its clipped stem has to count
    param([string]$Title, [string]$Typed)
    $t = ConvertTo-ChatqNorm $Title
    if ($t.Equals($Typed, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($t.EndsWith('...') -and $t.Length -gt 10) {
        return $Typed.StartsWith($t.Substring(0, $t.Length - 3), [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}

function Resolve-ChatqTarget {
    <#
    Which chat a typed target means. The rules are the user's:
      - an id is that chat
      - otherwise exact title, then contains, then every word - this project
        first, every project only when this one has no match at all
      - nothing matched anywhere: every chat in this project is a candidate
      - of several candidates the newest wins, unless others were active
        within 5 h of it - one limit window, so recency cannot tell them
        apart - and then the most relevant one does
    Never guesses across projects on a miss: a prompt landing in the wrong
    repo's chat would act on the wrong repo.
    #>
    param([string]$Target, [string]$Prompt, [string[]]$Provider, [switch]$AllProjects)
    $typed = ConvertTo-ChatqNorm ($Target.Trim().Trim("'", '"'))
    if (-not $typed) { return [pscustomobject]@{ Error = 'no target given' } }
    $all = @(Sync-ChatqIndex -Provider $Provider | Where-Object { -not $_.Hidden -and $_.Title -ne '(empty)' })
    if (-not $all) { return [pscustomobject]@{ Error = 'no chats found on this machine' } }
    $when = @{}
    foreach ($r in $all) { $when[$r.Path] = ConvertTo-ChatqDate $r.When }

    $make = {
        param($Row, $Rule, $Tier, $Score, $Runner, $RunnerScore, $Cluster, $Count, $Wide, $NoProject)
        [pscustomobject]@{
            Error = $null; Row = $Row; When = $when[$Row.Path]; Rule = $Rule; Tier = $Tier
            Score = $Score; RunnerUp = $Runner; RunnerUpScore = $RunnerScore
            RunnerUpWhen = if ($Runner) { $when[$Runner.Path] } else { $null }
            Cluster = $Cluster; Candidates = $Count; Wide = $Wide; NoProject = $NoProject; Typed = $typed
        }
    }

    # an id is exact by definition, and never scoped to a project
    if ($typed -match '^[0-9a-fA-F]{6,}(-[0-9a-fA-F-]*)?$') {
        $hit = @($all | Where-Object { $_.Id -like "$typed*" })
        if ($hit.Count -eq 1) { return & $make $hit[0] 'id' 'id' $null $null $null 1 1 $false $false }
        if ($hit.Count -gt 1) {
            return [pscustomobject]@{ Error = "'$typed' starts $($hit.Count) chat ids - type more of it" }
        }
        # no id starts with it: 'facade' is a fine title and valid hex
    }

    $scope = Get-ChatqProjectScope
    $mine = if ($AllProjects) { $all } else { @($all | Where-Object { Test-ChatqInProject $_ $scope }) }
    $noProject = -not $mine
    if ($noProject) { $mine = $all }
    $pools = @(@{ Rows = $mine; Wide = $false })
    if (-not $AllProjects -and -not $noProject) { $pools += @{ Rows = $all; Wide = $true } }

    $words = @($typed -split ' ' | Where-Object { $_ })
    $cands = @(); $tier = $null; $wide = $false
    foreach ($pool in $pools) {
        foreach ($t in 'exact', 'contains', 'words') {
            $m = @(switch ($t) {
                    'exact' { $pool.Rows | Where-Object { Test-ChatqTitleEquals $_.Title $typed } }
                    'contains' {
                        $pool.Rows | Where-Object { (ConvertTo-ChatqNorm $_.Title).IndexOf($typed, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
                    }
                    'words' {
                        if ($words.Count -gt 1) {
                            $pool.Rows | Where-Object {
                                $ti = ConvertTo-ChatqNorm $_.Title
                                -not @($words | Where-Object { $ti.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 })
                            }
                        }
                    }
                })
            if ($m.Count) { $cands = $m; $tier = $t; $wide = $pool.Wide; break }
        }
        if ($cands.Count) { break }
    }
    if (-not $cands.Count) {
        # A guess is only fair inside one project. Standing somewhere that is
        # no project at all, "the newest chat" would be any repo's on the
        # machine - refuse, unless -AllProjects asked for exactly that.
        if ($noProject -and -not $AllProjects) {
            return [pscustomobject]@{ Error = "no chat title matches '$typed', and this folder is not a project - cd into the project, type more of the title, or add -AllProjects to guess across all of them" }
        }
        $cands = $mine; $tier = 'nomatch'
    }

    $sorted = @($cands | Sort-Object { $when[$_.Path] } -Descending)
    $newest = $sorted[0]
    $cluster = @($sorted | Where-Object { ($when[$newest.Path] - $when[$_.Path]).TotalHours -le $script:ChatqWindowHours })
    if ($cluster.Count -eq 1) {
        $rule = if ($sorted.Count -gt 1) { "$tier/newest" } else { $tier }
        $runner = if ($sorted.Count -gt 1) { $sorted[1] } else { $null }
        return & $make $newest $rule $tier $null $runner $null 1 $sorted.Count $wide $noProject
    }
    $scored = @($cluster | ForEach-Object {
            [pscustomobject]@{ Row = $_; Score = (Get-ChatqRelevance $_ $typed $Prompt); When = $when[$_.Path] }
        } | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'When'; Descending = $true })
    return & $make $scored[0].Row "$tier/relevance" $tier $scored[0].Score $scored[1].Row $scored[1].Score `
        $cluster.Count $sorted.Count $wide $noProject
}

function Write-ChatqPick {
    # one line for the pick, then only what explains it
    param($Res, [string]$Lead = '  ->')
    $r = $Res.Row
    $age = if ($Res.When) { " ($(Get-ChatqAge $Res.When))" } else { '' }
    $why = switch -Wildcard ($Res.Rule) {
        'id' { 'id' }
        'exact' { 'exact title' }
        'contains' { 'title contains it' }
        'words' { 'title has every word' }
        '*/newest' { "$($Res.Tier) - newest of $($Res.Candidates)" }
        '*/relevance' { "$($Res.Tier) - relevance $($Res.Score), $($Res.Cluster) active within $($script:ChatqWindowHours)h" }
        default { $Res.Rule }
    }
    Write-Host "$Lead " -NoNewline
    Write-Host "'$($r.Title)'" -NoNewline -ForegroundColor Cyan
    Write-Host "$age  $($r.Provider) $script:ChatqDot $why" -ForegroundColor DarkGray
    if ($Res.Tier -eq 'nomatch') {
        $from = if ($Res.NoProject) { 'recent chats in every project' } else { 'this project''s recent chats' }
        Write-Host "     no title matched - this is a guess from $from" -ForegroundColor Yellow
    }
    if ($Res.RunnerUp) {
        $ra = if ($Res.RunnerUpWhen) { " ($(Get-ChatqAge $Res.RunnerUpWhen))" } else { '' }
        $rs = if ($null -ne $Res.RunnerUpScore) { " $($Res.RunnerUpScore)" } else { '' }
        Write-Host "     runner-up '$($Res.RunnerUp.Title)'$ra$rs" -ForegroundColor DarkGray
    }
    if ($Res.Wide) { Write-Host "     not in this project: $($r.Group)" -ForegroundColor DarkGray }
    elseif ($Res.NoProject) { Write-Host "     project: $($r.Group)" -ForegroundColor DarkGray }
}

#endregion

#region session metadata ------------------------------------------------------

function Find-ChatqTailMatch {
    # the last match of $Pattern's first group, looking back in growing windows
    param([string]$Path, [string]$Pattern)
    $len = try { ([System.IO.FileInfo]::new($Path)).Length } catch { 0 }
    foreach ($size in 262144, 4194304, 67108864) {
        $t = Read-ChatqTail $Path $size
        if ($t) {
            $m = [regex]::Matches($t, $Pattern)
            if ($m.Count) { return $m[$m.Count - 1].Groups[1].Value }
        }
        if ($size -ge $len) { break }
    }
    return $null
}

function Get-ChatqLastTurn {
    # The last record that carries a message, walking back past the state lines
    # (ai-title, last-prompt, queue-operation) that trail every turn. Tells a
    # chat the limit cut off - its last message is Claude's own synthetic
    # "You've hit your session limit" - from one that finished or moved on.
    param([string]$Path)
    $len = try { ([System.IO.FileInfo]::new($Path)).Length } catch { return $null }
    foreach ($size in 262144, 4194304) {
        $t = Read-ChatqTail $Path $size
        if (-not $t) { return $null }
        $lines = $t -split "`n"
        $start = if ($size -lt $len) { 1 } else { 0 }   # [0] is cut mid-line
        for ($i = $lines.Count - 1; $i -ge $start; $i--) {
            $line = $lines[$i].TrimStart([char]0xFEFF).Trim()
            if (-not $line -or $line.IndexOf('"message":', [StringComparison]::Ordinal) -lt 0) { continue }
            $o = try { $line | ConvertFrom-Json } catch { $null }
            if (-not $o -or -not $o.message -or $o.isSidechain) { continue }
            $text = ''
            $c = $o.message.content
            if ($c -is [string]) { $text = $c }
            elseif ($c) { $text = (@($c) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ' }
            $limit = ($o.error -eq 'rate_limit') -or
            ($o.isApiErrorMessage -and $text -match '(?i)hit your .*limit|usage limit')
            # the 529 turn: same synthetic shape, error server_error, apiErrorStatus 529
            $over = (-not $limit) -and $o.isApiErrorMessage -and
            (($o.apiErrorStatus -and [int]$o.apiErrorStatus -ge 500) -or $text -match $script:ChatqOverloadRx)
            $resets = $null
            if ($o.quotaLimits -and $o.quotaLimits.resetsAt) {
                $resets = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$o.quotaLimits.resetsAt).LocalDateTime
            }
            return [pscustomobject]@{
                Uuid = $o.uuid; Type = $o.type; Limit = [bool]$limit; Overloaded = [bool]$over; ResetsAt = $resets
                At = ConvertTo-ChatqDate $o.timestamp; Text = $text; StopReason = $o.message.stop_reason
            }
        }
        if ($size -ge $len) { break }
    }
    return $null
}

function Get-ChatqClaudeMeta {
    param([string]$Path, [string]$Group)
    $meta = [pscustomobject]@{ Exists = $false; Cwd = $null; Mode = $null; Model = $null; LastTurn = $null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $meta }
    $meta.Exists = $true
    $chunk = Read-ChatqChunk $Path 262144
    if ($chunk) {
        # Both d:\ and D:\ turn up for the same folder. The one whose slug is
        # this project's folder name is the one Claude filed the chat under.
        $seen = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($chunk.Head + "`n" + $chunk.Tail, '"cwd":"((?:[^"\\]|\\.)*)"')) {
            $v = Convert-ChatqJsonEscaped $m.Groups[1].Value
            if ($v -and -not $seen.Contains($v)) { $seen.Add($v) }
        }
        $meta.Cwd = @($seen | Where-Object { ($_.TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-') -eq $Group -and (Test-Path -LiteralPath $_) }) |
            Select-Object -First 1
        if (-not $meta.Cwd) { $meta.Cwd = @($seen | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1 }
    }
    $meta.Mode = Find-ChatqTailString $Path 'permissionMode'
    # the real model sits first in a real assistant message; Claude's own error
    # turns carry <synthetic> and tool inputs carry aliases, neither of which
    # starts '"message":{"model":"claude-'
    $meta.Model = Find-ChatqTailMatch $Path '"message":\{"model":"(claude-[^"]+)"'
    $meta.LastTurn = Get-ChatqLastTurn $Path
    return $meta
}

function Get-ChatqCodexMeta {
    param([string]$Path)
    $meta = [pscustomobject]@{ Exists = $false; Cwd = $null; Sandbox = $null; Network = $false; Approval = $null; Model = $null }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $meta }
    $meta.Exists = $true
    $chunk = Read-ChatqChunk $Path 262144
    if ($chunk -and $chunk.Head -match '"cwd":\s*"((?:[^"\\]|\\.)*)"') { $meta.Cwd = Convert-ChatqJsonEscaped $Matches[1] }
    $text = if ($chunk.Split) { $chunk.Tail } else { $chunk.Head }
    $lines = Get-ChatqJsonLines $text @('"type":"turn_context"', '"type": "turn_context"') 1 -FromEnd -Skip @()
    if ($lines.Count) {
        $o = try { $lines[0] | ConvertFrom-Json } catch { $null }
        if ($o.payload) {
            $meta.Sandbox = $o.payload.sandbox_policy.type
            $meta.Network = [bool]$o.payload.sandbox_policy.network_access
            $meta.Approval = $o.payload.approval_policy
            $meta.Model = $o.payload.model
            if ($o.payload.cwd) { $meta.Cwd = $o.payload.cwd }
        }
    }
    return $meta
}

function Get-ChatqCutOffChats {
    # Chats the limit - or a 529 Overloaded - stopped mid-task that nothing is
    # queued for: the ones you would otherwise walk round typing "continue"
    # into, one at a time. Only transcripts touched in the last $Hours count.
    param([object[]]$Jobs, [int]$Hours = 12)
    $root = Join-Path $script:ChatqClaudeHome 'projects'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $since = (Get-Date).AddHours(-$Hours)
    $busy = @{}
    foreach ($j in $Jobs) { if ($j.state -in 'queued', 'running') { $busy[$j.sessionId] = $true } }
    $rows = @{}
    foreach ($r in @(Get-ChatqIndex)) { $rows[$r.Path] = $r }
    $out = foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter *.jsonl -File -EA SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $since -and $_.BaseName -match '^[0-9a-fA-F-]{36}$' })) {
            if ($busy[$f.BaseName]) { continue }
            $last = Get-ChatqLastTurn $f.FullName
            if (-not $last -or -not ($last.Limit -or $last.Overloaded)) { continue }
            $title = if ($rows[$f.FullName]) { $rows[$f.FullName].Title } else { $f.BaseName }
            [pscustomobject]@{
                Id = $f.BaseName; Title = $title; Group = $d.Name; At = $last.At; ResetsAt = $last.ResetsAt
                Why = if ($last.Limit) { 'limit' } else { 'overloaded' }
            }
        }
    }
    return @($out | Sort-Object At -Descending)
}

#endregion

#region job store -------------------------------------------------------------
# One JSON file per job plus the prompt as its own .md, so the prompt can be
# opened and edited in place - it is read again at send time.
# Ownership, so nothing needs a lock: the shell creates jobs, deletes ones not
# running, and flips failed/needs-input back to queued; every move out of
# queued is the watcher's. Cancelling a running job goes through a flag file.

function New-ChatqDir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Save-ChatqText {
    # UTF-8 without a BOM, written aside and swapped in, so a reader - the
    # watcher, the board preview - never sees half a file
    param([string]$Path, [string]$Text)
    New-ChatqDir (Split-Path $Path -Parent)
    $tmp = "$Path.tmp"
    $enc = New-Object System.Text.UTF8Encoding $false
    for ($try = 1; $try -le 5; $try++) {
        try {
            [System.IO.File]::WriteAllText($tmp, $Text, $enc)
            # [NullString]::Value, not $null: PowerShell hands $null to a .NET
            # string parameter as "", and "" is not a legal backup path
            if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
            else { [System.IO.File]::Move($tmp, $Path) }
            return
        }
        catch {
            if ($try -eq 5) { throw }
            Start-Sleep -Milliseconds (100 * $try)
        }
    }
}

function Read-ChatqJson {
    param([string]$Path)
    for ($try = 1; $try -le 3; $try++) {
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    return $null
}

function Get-ChatqStamp {
    # UTC round-trip, so the strings sort in time order as they are
    (Get-Date).ToUniversalTime().ToString('o')
}

function Get-ChatqJobs {
    if (-not (Test-Path -LiteralPath $script:ChatqQueueDir)) { return @() }
    $jobs = foreach ($f in @(Get-ChildItem -LiteralPath $script:ChatqQueueDir -Filter *.json -File -EA SilentlyContinue)) {
        $j = Read-ChatqJson $f.FullName
        if ($j -and $j.id) { $j }
    }
    return @($jobs | Sort-Object createdAt)
}

function Save-ChatqJob {
    param($Job)
    Save-ChatqJson (Join-Path $script:ChatqQueueDir "$($Job.id).json") $Job
}

function Save-ChatqJson {
    param([string]$Path, $Object)
    Save-ChatqText $Path ($Object | ConvertTo-Json -Depth 8)
}

function Set-ChatqJobState {
    param($Job, [string]$State, [string]$Why)
    $Job.state = $State
    $Job.history = @(@($Job.history) + [pscustomobject]@{ at = (Get-ChatqStamp); state = $State; why = $Why })
    Save-ChatqJob $Job
}

function Find-ChatqJob {
    # by the #n shown in lists, or by (a prefix of) the id
    param([string]$Ref, [object[]]$Jobs)
    if (-not $Jobs) { $Jobs = @(Get-ChatqJobs) }
    $r = $Ref.Trim().TrimStart('#')
    if ($r -match '^\d+$') { return @($Jobs | Where-Object { [int]$_.seq -eq [int]$r }) | Select-Object -First 1 }
    $hit = @($Jobs | Where-Object { $_.id -like "$r*" })
    if ($hit.Count -eq 1) { return $hit[0] }
    return $null
}

function Get-ChatqPromptPath {
    param($Job)
    Join-Path $script:ChatqQueueDir $Job.promptFile
}

function Read-ChatqPrompt {
    # the file as it is now - edits made after queueing count
    param($Job)
    $p = Get-ChatqPromptPath $Job
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    return (Remove-ChatqPromptHeader $t)
}

function Remove-ChatqPromptHeader {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text.TrimStart([char]0xFEFF)
    $t = [regex]::Replace($t, '^\s*<!--\s*chatq:.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    return $t.Trim()
}

function Get-ChatqSafeName {
    # the prompt file is named after the chat, so the editor tab says which chat
    # it is for. % ^ & ! are legal in a filename but code.cmd hands the path
    # through cmd.exe, which would expand or eat them.
    param([string]$Text)
    $t = ($Text -replace '[\\/:*?"<>|%^&!\x00-\x1f]', '_' -replace '\s+', ' ').Trim()
    if ($t.Length -gt 50) { $t = $t.Substring(0, 50) }
    return $t.TrimEnd('.', ' ')
}

#endregion

#region external CLIs ---------------------------------------------------------

# Set in every shell a live Claude chat spawns (its Bash tool, a VS Code
# terminal it opened). A child that inherits them believes it is part of that
# session - its messaging socket, its session id, its effort - so none of them
# survive into a run. The API keys go too: with one set, claude -p bills the
# API instead of the subscription whose reset this whole tool is waiting for.
$script:ChatqEnvDrop = @(
    'CLAUDECODE', 'CLAUDE_PID', 'CLAUDE_EFFORT', 'CLAUDE_AGENT_SDK_VERSION',
    'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_EXECPATH', 'CLAUDE_CODE_SESSION_ID',
    'CLAUDE_CODE_SESSION_ATTENDED', 'CLAUDE_CODE_CHILD_SESSION', 'CLAUDE_CODE_SSE_PORT',
    'CLAUDE_CODE_MESSAGING_SOCKET', 'CLAUDE_CODE_MESSAGING_TOKEN',
    'CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING', 'CLAUDE_CODE_ENABLE_TASKS',
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'OPENAI_API_KEY', 'CODEX_API_KEY'
)
$script:ChatqClaudeMin = '2.1.259'   # --permission-prompts none

function Find-ChatqExe {
    # Not cached: VS Code deletes the old extension folder when it updates, so a
    # path found at queue time can be gone by the time the limit resets.
    param([string]$Provider)
    $name = if ($Provider -eq 'codex') { 'codex' } else { 'claude' }
    $override = if ($Provider -eq 'codex') { $env:CHATQ_CODEX } else { $env:CHATQ_CLAUDE }
    if ($override) { return $override }
    $cmd = Get-Command $name -CommandType Application -EA SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $exe = if ($script:ChatqIsWindows) { "$name.exe" } else { $name }
    foreach ($p in @((Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') $exe),
            (Join-Path (Join-Path $script:ChatqClaudeHome 'local') $exe))) {
        if ($name -eq 'claude' -and (Test-Path -LiteralPath $p)) { return $p }
    }
    # Both VS Code extensions ship their own copy and put none on PATH - on a
    # machine that only ever used the panel this is the only one there is.
    $pattern = if ($name -eq 'claude') { 'anthropic.claude-code-*' } else { 'openai.chatgpt-*' }
    $best = $null; $bestVer = $null
    foreach ($root in '.vscode', '.vscode-insiders', '.cursor', '.windsurf') {
        $ext = Join-Path (Join-Path $HOME $root) 'extensions'
        if (-not (Test-Path -LiteralPath $ext)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $ext -Directory -Filter $pattern -EA SilentlyContinue)) {
            if ($d.Name -notmatch '-(\d+(?:\.\d+){1,3})(?:-|$)') { continue }
            $ver = $null
            if (-not [version]::TryParse($Matches[1], [ref]$ver)) { continue }
            $bin = if ($name -eq 'claude') {
                Join-Path (Join-Path (Join-Path $d.FullName 'resources') 'native-binary') $exe
            }
            else {
                $b = Join-Path $d.FullName 'bin'
                if (Test-Path -LiteralPath $b) {
                    Get-ChildItem -LiteralPath $b -Recurse -Filter $exe -File -EA SilentlyContinue |
                        Select-Object -First 1 -ExpandProperty FullName
                }
            }
            if ($bin -and (Test-Path -LiteralPath $bin) -and (-not $bestVer -or $ver -gt $bestVer)) {
                $best = $bin; $bestVer = $ver
            }
        }
    }
    return $best
}

function Get-ChatqCliVersion {
    param([string]$Exe)
    if (-not $Exe) { return $null }
    if (-not $script:ChatqCliVersions) { $script:ChatqCliVersions = @{} }
    if ($script:ChatqCliVersions.ContainsKey($Exe)) { return $script:ChatqCliVersions[$Exe] }
    $v = $null
    try {
        $out = (& $Exe --version 2>$null | Select-Object -First 1)
        if ("$out" -match '(\d+\.\d+\.\d+)') { $v = $Matches[1] }
    }
    catch {}
    $script:ChatqCliVersions[$Exe] = $v
    return $v
}

function ConvertTo-ChatqArgLine {
    # The Windows command-line rules (backslashes only special before a quote),
    # which is also what .NET applies to Arguments on macOS and Linux - so one
    # string works everywhere, and PS 5.1 has no ArgumentList to fall back on.
    param([string[]]$ArgList)
    $parts = foreach ($a in $ArgList) {
        $a = [string]$a
        if ($a -eq '') { '""'; continue }
        if ($a -notmatch '[\s"]') { $a; continue }
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq '\') { $bs++; continue }
            if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"') }
            else { if ($bs) { [void]$sb.Append('\' * $bs) }; [void]$sb.Append($ch) }
            $bs = 0
        }
        if ($bs) { [void]$sb.Append('\' * ($bs * 2)) }
        [void]$sb.Append('"')
        $sb.ToString()
    }
    return ($parts -join ' ')
}

function Stop-ChatqTree {
    # the CLI starts its own children (shells, MCP servers); take them all
    param($Process)
    try {
        if ($script:ChatqIsWindows) { & taskkill.exe /PID $Process.Id /T /F 2>&1 | Out-Null }
        else { try { $Process.Kill($true) } catch { $Process.Kill() } }
    }
    catch {}
}

function Invoke-ChatqProcess {
    <#
    Run a CLI to the end, prompt on stdin, handing each stdout line to $OnLine.

    stdin is where Korean went wrong on Windows PowerShell 5.1, three ways at
    once: the console code page here is 949, $OutputEncoding is us-ascii (so
    piping turns Hangul into ?), and 5.1's ProcessStartInfo has no
    StandardInputEncoding at all - Process.Start builds the stdin writer from
    Console.InputEncoding, and under chcp 65001 that writer puts a BOM on the
    pipe the moment it is created. So: raw UTF-8 bytes onto the base stream,
    never through the writer, with the console encoding swapped to BOM-less
    UTF-8 for the instant Start takes and put back after.
    #>
    param(
        [string]$Exe, [string[]]$ArgList, [string]$WorkDir, [string]$StdIn,
        [hashtable]$SetEnv, [string]$LogPath, [scriptblock]$OnLine, [scriptblock]$OnTick,
        [int]$TimeoutSec = 14400
    )
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ConvertTo-ChatqArgLine $ArgList
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $hasInEnc = [bool]$psi.PSObject.Properties['StandardInputEncoding']
    if ($hasInEnc) { $psi.StandardInputEncoding = $utf8 }
    foreach ($k in $script:ChatqEnvDrop) {
        if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) }
    }
    # A $null value removes the variable rather than leaving what the watcher
    # inherited: a job queued with no CLAUDE_CONFIG_DIR means the default home,
    # not whichever one the shell that started the watcher had.
    if ($SetEnv) {
        foreach ($k in $SetEnv.Keys) {
            if ($SetEnv[$k]) { $psi.EnvironmentVariables[$k] = [string]$SetEnv[$k] }
            elseif ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) }
        }
    }

    $oldIn = $null
    if (-not $hasInEnc) {
        try { $oldIn = [Console]::InputEncoding; [Console]::InputEncoding = $utf8 } catch { $oldIn = $null }
    }
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    finally { if ($oldIn) { try { [Console]::InputEncoding = $oldIn } catch {} } }

    $bytes = $utf8.GetBytes([string]$StdIn)
    try {
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.BaseStream.Flush()
    }
    catch {}
    try { $p.StandardInput.Close() } catch {}
    # a .NET task, not a PowerShell event: those need a runspace the watcher's
    # pipeline thread does not hand out, and a full stderr pipe would hang it
    $errTask = $p.StandardError.ReadToEndAsync()

    $log = $null
    if ($LogPath) {
        New-ChatqDir (Split-Path $LogPath -Parent)
        $log = New-Object System.IO.StreamWriter($LogPath, $true, $utf8)
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $stopped = $null
    $lastTick = Get-Date
    # cancel, stop and the deadline are looked at every 5 s whether the run is
    # silent or chattering - a stream of quick tool calls must not hide them
    $check = {
        $lastTick = Get-Date
        if ($OnTick -and (& $OnTick)) { return 'cancelled' }
        if ((Get-Date) -gt $deadline) { return 'timeout' }
        return $null
    }
    try {
        while ($true) {
            $task = $p.StandardOutput.ReadLineAsync()
            while (-not $task.Wait(5000)) {
                $stopped = . $check
                if ($stopped) { break }
            }
            if ($stopped) { break }
            $line = $task.Result
            if ($null -eq $line) { break }
            if ($log) { $log.WriteLine($line); $log.Flush() }
            if ($OnLine) { & $OnLine $line }
            if (((Get-Date) - $lastTick).TotalSeconds -ge 5) {
                $stopped = . $check
                if ($stopped) { break }
            }
        }
    }
    finally { if ($log) { $log.Dispose() } }
    if ($stopped) { Stop-ChatqTree $p }
    [void]$p.WaitForExit(15000)
    $err = ''
    try { if ($errTask.Wait(5000)) { $err = $errTask.Result } } catch {}
    $code = try { $p.ExitCode } catch { -1 }
    return [pscustomobject]@{ ExitCode = $code; StdErr = $err; Stopped = $stopped; Pid = $p.Id }
}

#endregion

#region reading a run --------------------------------------------------------
# What the stream-json lines of claude -p say, measured on 2.1.278:
#   system/init             session_id, model, permissionMode, claude_code_version
#   system/permission_denied  tool_name - a prompt nobody could answer
#   rate_limit_event        rate_limit_info {status allowed|allowed_warning|
#                           rejected, resetsAt (epoch s), rateLimitType}
#   assistant               message.content; model <synthetic> is Claude Code's
#                           own error turn, "You've hit your session limit ..."
#   result                  subtype, is_error, result, permission_denials[],
#                           num_turns, duration_ms, total_cost_usd - its "type"
#                           key comes last, so nothing may assume key order
# user lines carry tool results and run to megabytes; they are never parsed.

$script:ChatqLimitRx = '(?i)hit your (session |usage |weekly |opus |sonnet )?limit|usage limit reached|limit (will )?reset'
# "API Error: 529 Overloaded. This is a server-side issue, usually temporary -
# try again in a moment. If it persists, check https://status.claude.com." is
# the 529 as Claude Code prints it; the other 5xx it reports are the same kind
# of trouble - on Anthropic's side, and over when the status page says so.
$script:ChatqOverloadRx = '(?i)API Error:\s*5\d\d|\boverloaded(_error)?\b'

function New-ChatqRunState {
    @{
        Init = $false; Started = $false; Session = $null; Model = $null; Mode = $null; Version = $null
        Limit = $null; Rate = $null; SyntheticLimit = $null; Overloaded = $null; Retries = 0
        Assistant = 0; LastText = ''; Tools = [System.Collections.Generic.List[string]]::new()
        Denied = [System.Collections.Generic.List[string]]::new(); Result = $null
        # codex
        Thread = $null; TurnStarted = $false; TurnDone = $false; TurnFailed = $null; Failed = $null
    }
}

function Update-ChatqClaudeState {
    param($St, [string]$Line)
    if ($Line.Length -gt 1048576) { return }
    $isAssistant = $Line.StartsWith('{"type":"assistant"')
    if (-not $isAssistant -and
        $Line.IndexOf('"type":"result"', [StringComparison]::Ordinal) -lt 0 -and
        $Line.IndexOf('"type":"rate_limit_event"', [StringComparison]::Ordinal) -lt 0 -and
        -not $Line.StartsWith('{"type":"system"')) { return }
    $o = try { $Line | ConvertFrom-Json } catch { return }
    switch ($o.type) {
        'system' {
            if ($o.subtype -eq 'init') {
                $St.Init = $true; $St.Session = $o.session_id; $St.Model = $o.model
                $St.Mode = $o.permissionMode; $St.Version = $o.claude_code_version
            }
            elseif ($o.subtype -eq 'permission_denied' -and $o.tool_name) { $St.Denied.Add([string]$o.tool_name) }
            # Claude Code retries a 529 by itself several times before it gives up
            elseif ($o.subtype -eq 'api_retry') { $St.Retries++ }
        }
        'rate_limit_event' {
            $St.Rate = $o.rate_limit_info
            if ($o.rate_limit_info.status -eq 'rejected') { $St.Limit = $o.rate_limit_info }
        }
        'assistant' {
            $texts = @($o.message.content | Where-Object { $_.type -eq 'text' -and $_.text } | ForEach-Object { $_.text })
            if ($o.message.model -eq '<synthetic>') {
                $t = $texts -join ' '
                if ($t -match $script:ChatqLimitRx) { $St.SyntheticLimit = $t }
                elseif ($t -match $script:ChatqOverloadRx) { $St.Overloaded = $t }
                return
            }
            $St.Assistant++
            if ($texts) { $St.LastText = $texts[-1] }
            foreach ($u in @($o.message.content | Where-Object { $_.type -eq 'tool_use' })) { $St.Tools.Add([string]$u.name) }
        }
        'result' { $St.Result = $o }
    }
}

function Get-ChatqExcerpt {
    # the end of the reply, where the summary or the question is - up to $Max
    # characters, markdown fences and headers dropped, cut on a paragraph
    param([string]$Text, [int]$Max = 300)
    if (-not $Text) { return '' }
    $t = [regex]::Replace($Text, '```[\s\S]*?```', ' ')
    $paras = @($t -split '\r?\n\s*\r?\n' | ForEach-Object { ($_ -replace '(?m)^\s*#+\s*', '' -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    if (-not $paras) { return '' }
    $out = ''
    for ($i = $paras.Count - 1; $i -ge 0; $i--) {
        $next = if ($out) { $paras[$i] + ' / ' + $out } else { $paras[$i] }
        if ($next.Length -gt $Max) { break }
        $out = $next
    }
    if (-not $out) { $out = $paras[-1].Substring(0, [Math]::Min($Max - 1, $paras[-1].Length)) + $script:ChatqEllipsis }
    return $out
}

function Test-ChatqAsks {
    # a reply ending on a question - the alert says so, but it is not treated
    # as needs-input: most replies end on an offer ("want me to also ...?")
    param([string]$Text)
    if (-not $Text) { return $false }
    $last = @($Text -split '\r?\n' | Where-Object { $_.Trim() })[-1]
    return [bool]($last -and $last.TrimEnd().TrimEnd('*', '_', ')').EndsWith('?') -or
        ($last -and $last.TrimEnd().EndsWith([string][char]0xFF1F)))
}

function Get-ChatqClaudeOutcome {
    # limited and overloaded before failed, failed before needs-input: those two
    # are the outcomes that go back in the queue rather than get reported
    param($St, $Proc, [string]$Mode)
    $res = $St.Result
    $text = if ($res -and $res.result) { [string]$res.result } else { [string]$St.LastText }
    $o = [ordered]@{
        kind = $null; reason = $null; excerpt = (Get-ChatqExcerpt $text); asks = $false
        denied = @($St.Denied | Select-Object -Unique); turns = $res.num_turns; durationMs = $res.duration_ms
        costUsd = $res.total_cost_usd; model = $St.Model; resetsAt = $null; limitType = $null
    }
    # A turn that ended well is not limited, whatever was said on the way: a
    # 'rejected' rate_limit_event also goes out when extra usage carries the
    # request, and the run then completes normally.
    $broke = (-not $res) -or $res.is_error
    $legacy = if ("$text $($St.SyntheticLimit)" -match 'limit reached\|(\d{9,})') { $Matches[1] } else { $null }
    $limited = $broke -and ($St.Limit -or $St.SyntheticLimit -or $legacy -or
        ($res -and ("$text" -match $script:ChatqLimitRx)))
    $status = if ($res) { $res.api_error_status } else { $null }
    $overloaded = $broke -and -not $limited -and ($St.Overloaded -or ($status -and [int]$status -ge 500) -or
        ($res -and "$text" -match $script:ChatqOverloadRx) -or (-not $res -and "$($Proc.StdErr)" -match $script:ChatqOverloadRx))
    if ($overloaded -and -not $Proc.Stopped) {
        $o.kind = 'overloaded'
        $o.reason = if ($St.Overloaded) { $St.Overloaded } elseif ($status) { "API Error: $status" } else { 'API Error: overloaded' }
        return [pscustomobject]$o
    }
    if ($limited) {
        $o.kind = 'limited'
        $o.reason = if ($St.SyntheticLimit) { $St.SyntheticLimit } else { 'usage limit' }
        if ($St.Limit -and $St.Limit.resetsAt) {
            $o.resetsAt = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$St.Limit.resetsAt).UtcDateTime.ToString('o')
            $o.limitType = $St.Limit.rateLimitType
        }
        elseif ($legacy) { $o.resetsAt = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$legacy).UtcDateTime.ToString('o') }
        return [pscustomobject]$o
    }
    if ($Proc.Stopped) { $o.kind = 'failed'; $o.reason = $Proc.Stopped; return [pscustomobject]$o }
    if (-not $res) {
        $err = ("$($Proc.StdErr)" -replace '\s+', ' ').Trim()
        if ($err.Length -gt 200) { $err = $err.Substring($err.Length - 200) }
        $o.kind = 'failed'; $o.reason = "no result (exit $($Proc.ExitCode)) $err".Trim()
        return [pscustomobject]$o
    }
    if ($res.subtype -eq 'error_max_turns') { $o.kind = 'needs-input'; $o.reason = 'stopped at the turn limit'; return [pscustomobject]$o }
    if ($res.is_error -or $res.subtype -ne 'success') {
        $o.kind = 'failed'; $o.reason = "$($res.subtype): $(Get-ChatqExcerpt $text 160)"
        return [pscustomobject]$o
    }
    $den = @($res.permission_denials)
    if ($den.Count) {
        $names = @($den | ForEach-Object {
                $n = [string]$_.tool_name
                $arg = if ($_.tool_input.file_path) { Split-Path ([string]$_.tool_input.file_path) -Leaf }
                elseif ($_.tool_input.command) { ([string]$_.tool_input.command).Split("`n")[0] }
                else { $null }
                if ($arg) {
                    if ($arg.Length -gt 40) { $arg = $arg.Substring(0, 40) + $script:ChatqEllipsis }
                    "$n($arg)"
                }
                else { $n }
            } | Select-Object -Unique -First 3)
        $o.kind = 'needs-input'; $o.reason = 'denied ' + ($names -join ', '); $o.denied = $names
        return [pscustomobject]$o
    }
    if ($Mode -eq 'plan' -or $St.Mode -eq 'plan') {
        $o.kind = 'needs-input'; $o.reason = 'plan ready - approve it in VS Code'
        return [pscustomobject]$o
    }
    $o.kind = 'done'
    $o.asks = Test-ChatqAsks $text
    return [pscustomobject]$o
}

function Update-ChatqCodexState {
    param($St, [string]$Line)
    if ($Line.Length -gt 1048576) { return }
    $o = try { $Line | ConvertFrom-Json } catch { return }
    switch ($o.type) {
        'thread.started' { $St.Init = $true; $St.Thread = $o.thread_id }
        'turn.started' { $St.TurnStarted = $true }
        'turn.completed' { $St.TurnDone = $true }
        'turn.failed' { $St.TurnFailed = [string]$o.error.message; $St.Failed = $St.TurnFailed }
        # a bare 'error' can be a reconnect notice the turn recovers from
        'error' { if (-not $St.Failed) { $St.Failed = [string]$o.message } }
        'item.completed' {
            if ($o.item.type -eq 'agent_message' -and $o.item.text) { $St.Assistant++; $St.LastText = [string]$o.item.text }
            elseif ($o.item.type) { $St.Tools.Add([string]$o.item.type) }
        }
    }
}

function ConvertFrom-ChatqLimitText {
    # Codex puts its reset time in prose only - "try again at Sep 21st, 2026
    # 8:37 AM" - with no field for it, so the prose is all there is to parse
    param([string]$Text)
    if ($Text -notmatch '(?i)try again (?:at|in) ([^.\n]+)') { return $null }
    $s = ($Matches[1] -replace '(\d+)(st|nd|rd|th)', '$1').Trim()
    if ($s -match '^(\d+)\s*(minute|min|hour|hr|day)s?') {
        $n = [int]$Matches[1]
        switch -Wildcard ($Matches[2]) {
            'min*' { return (Get-Date).AddMinutes($n) }
            'h*' { return (Get-Date).AddHours($n) }
            'day' { return (Get-Date).AddDays($n) }
        }
    }
    $d = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeLocal
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $d }
    return $null
}

function Get-ChatqCodexOutcome {
    param($St, $Proc)
    $o = [ordered]@{
        kind = $null; reason = $null; excerpt = (Get-ChatqExcerpt $St.LastText); asks = $false
        denied = @(); turns = $null; durationMs = $null; costUsd = $null; model = $null; resetsAt = $null; limitType = $null
    }
    # a turn that completed is done, whatever retry notices came before it
    if ($St.TurnDone -and -not $St.TurnFailed -and -not $Proc.Stopped) {
        $o.kind = 'done'
        $o.asks = Test-ChatqAsks $St.LastText
        return [pscustomobject]$o
    }
    $fail = "$($St.Failed) $($Proc.StdErr)"
    if ($fail -match '(?i)usage limit|hit your .*limit') {
        $o.kind = 'limited'; $o.reason = ($St.Failed -replace '\s+', ' ').Trim()
        $at = ConvertFrom-ChatqLimitText $fail
        if ($at) { $o.resetsAt = $at.ToUniversalTime().ToString('o') }
        return [pscustomobject]$o
    }
    if ($Proc.Stopped) { $o.kind = 'failed'; $o.reason = $Proc.Stopped; return [pscustomobject]$o }
    if ($St.Failed -or -not $St.TurnDone) {
        $why = if ($St.Failed) { $St.Failed } else { "no turn.completed (exit $($Proc.ExitCode))" }
        $o.kind = 'failed'; $o.reason = ($why -replace '\s+', ' ').Trim()
        return [pscustomobject]$o
    }
    $o.kind = 'done'
    $o.asks = Test-ChatqAsks $St.LastText
    return [pscustomobject]$o
}

function Test-ChatqPromptLanded {
    # Did the prompt reach the chat before the limit stopped it? If it did,
    # sending it again would put it in the chat twice and redo half-done work,
    # so the retry is a "continue" instead. Codex records the user turn when the
    # turn starts, so a run cut off before any reply has still landed there.
    param([string]$Path, [string]$Prompt, $SinceUtc, [string]$Provider = 'claude')
    if (-not $Path -or -not (Test-Path -LiteralPath $Path) -or -not $Prompt) { return $false }
    $since = ConvertTo-ChatqDate $SinceUtc
    $want = ($Prompt -replace '\s+', ' ').Trim()
    $want = $want.Substring(0, [Math]::Min(60, $want.Length))
    $text = Read-ChatqTail $Path 4194304
    # assigned, never @()-wrapped: Get-ChatqJsonLines returns its array behind a
    # comma, and @(...) around that makes an array holding one array
    $marker = if ($Provider -eq 'codex') { @('"role":"user"', '"role": "user"') } else { @('"type":"user"') }
    $lines = Get-ChatqJsonLines $text $marker 40 -FromEnd -Skip @('"tool_result"')
    foreach ($line in $lines) {
        $o = try { $line | ConvertFrom-Json } catch { continue }
        if ($since -and (ConvertTo-ChatqDate $o.timestamp) -lt $since.AddSeconds(-5)) { continue }
        $t = if ($Provider -eq 'codex') {
            (@($o.payload.content) | Where-Object { $_.type -eq 'input_text' } | ForEach-Object { $_.text }) -join ' '
        }
        else {
            $c = $o.message.content
            if ($c -is [string]) { $c } else { (@($c) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ' }
        }
        $t = (([string]$t) -replace '\s+', ' ').Trim()
        # contains, not starts-with: the IDE wraps a Codex prompt in context
        if ($t.StartsWith($want, [StringComparison]::Ordinal) -or ($Provider -eq 'codex' -and $t.Contains($want))) { return $true }
    }
    return $false
}

#endregion

#region when the limit resets -------------------------------------------------

function Get-ChatqHomeDir {
    # The config dir a job's chats live under: the one set when it was queued,
    # else the default. Never the watcher's own - that came from whichever shell
    # happened to start it, and may belong to another account.
    param([string]$Provider, [string]$Override)
    if ($Override) { return $Override }
    if ($Provider -eq 'codex') { return (Join-Path $HOME '.codex') }
    return (Join-Path $HOME '.claude')
}

# Limits that stop every chat. Others - seven_day_opus, a weekly_scoped model
# limit - stop one model only, and the probe (asked with the chat's own model)
# is what decides those.
$script:ChatqWideLimits = @('five_hour', 'seven_day', 'session', 'weekly_all', 'weekly')

function Get-ChatqRecordTime {
    # the "timestamp" of the JSONL record that holds position $At in $Text
    param([string]$Text, [int]$At)
    $s = $Text.LastIndexOf("`n", [Math]::Max(0, $At)) + 1
    $e = $Text.IndexOf("`n", $At)
    if ($e -lt 0) { $e = $Text.Length }
    if ($Text.Substring($s, $e - $s) -match '"timestamp":\s*"([^"]+)"') { return ConvertTo-ChatqDate $Matches[1] }
    return $null
}

function Get-ChatqClaudeBlock {
    <#
    The latest future reset among the "rejected" records Claude writes into a
    transcript when it stops one - read from the tails of the most recently
    touched chats, where that record always is. ~/.claude.json's usage cache is
    a hint on top: it is refreshed only when a window asks, and was 11 h stale
    on the machine this was written on. At is when the record was written, so a
    probe that said "allowed" after it wins.
    #>
    param([string]$ConfigDir)
    $now = Get-Date
    $best = $null
    $root = Join-Path (Get-ChatqHomeDir 'claude' $ConfigDir) 'projects'
    if (Test-Path -LiteralPath $root) {
        $since = $now.AddDays(-8)
        $files = @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue | ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Filter *.jsonl -File -EA SilentlyContinue
            } | Where-Object { $_.LastWriteTime -gt $since } | Sort-Object LastWriteTime -Descending | Select-Object -First 30)
        $recent = $now.AddHours(-6)
        $extra = foreach ($f in $files) {
            $sub = Join-Path (Join-Path $f.DirectoryName $f.BaseName) 'subagents'
            if (Test-Path -LiteralPath $sub) {
                Get-ChildItem -LiteralPath $sub -Filter *.jsonl -File -Recurse -EA SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $recent }
            }
        }
        foreach ($f in @($files) + @($extra)) {
            $t = Read-ChatqTail $f.FullName 262144
            if (-not $t) { continue }
            $i = $t.LastIndexOf('"quotaLimits":{', [StringComparison]::Ordinal)
            while ($i -ge 0) {
                $obj = Read-ChatqJsonObjectAt $t ($i + 14)
                $q = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
                if ($q -and $q.status -eq 'rejected' -and $q.resetsAt -and
                    (-not $q.rateLimitType -or $script:ChatqWideLimits -contains [string]$q.rateLimitType)) {
                    $until = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$q.resetsAt).LocalDateTime
                    if ($until -gt $now -and (-not $best -or $until -gt $best.Until)) {
                        $best = [pscustomobject]@{ Until = $until; Type = $q.rateLimitType; Source = 'transcript'; At = (Get-ChatqRecordTime $t $i) }
                    }
                }
                $i = if ($i -gt 0) { $t.LastIndexOf('"quotaLimits":{', $i - 1, [StringComparison]::Ordinal) } else { -1 }
            }
        }
    }
    $hint = Read-ChatqUsageCache $ConfigDir
    if ($hint -and (-not $best -or $hint.Until -gt $best.Until)) { $best = $hint }
    return $best
}

function Read-ChatqUsageCache {
    # Only the cachedUsageUtilization block is lifted out and parsed - the rest
    # of ~/.claude.json holds the account and is none of this tool's business
    param([string]$ConfigDir)
    $path = if ($ConfigDir) { Join-Path $ConfigDir '.claude.json' } else { Join-Path $HOME '.claude.json' }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $t = try { Read-ChatqAllText $path } catch { return $null }
    $i = $t.IndexOf('"cachedUsageUtilization"', [StringComparison]::Ordinal)
    if ($i -lt 0) { return $null }
    $j = $t.IndexOf('{', $i)
    $obj = if ($j -ge 0) { Read-ChatqJsonObjectAt $t $j } else { $null }
    $u = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
    if (-not $u -or -not $u.fetchedAtMs) { return $null }
    $fetched = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$u.fetchedAtMs).LocalDateTime
    $now = Get-Date
    $best = $null
    foreach ($l in @($u.utilization.limits)) {
        if (-not $l -or [double]$l.percent -lt 100 -or -not $l.resets_at) { continue }
        # one model's weekly limit ('weekly_scoped', with a scope) is not a wall
        if ($l.PSObject.Properties['scope'] -and $l.scope) { continue }
        if ($l.kind -and $script:ChatqWideLimits -notcontains [string]$l.kind) { continue }
        $until = ConvertTo-ChatqDate $l.resets_at
        # full at the time it was fetched, and that fetch was inside the window
        if ($until -and $until -gt $now -and $fetched -gt $until.AddDays(-7)) {
            if (-not $best -or $until -gt $best.Until) {
                $best = [pscustomobject]@{ Until = $until; Type = $l.kind; Source = 'usage cache'; At = $fetched }
            }
        }
    }
    return $best
}

function Get-ChatqCodexBlock {
    # Codex logs a rate_limits snapshot in every token_count event: used_percent
    # and resets_at (epoch s) per window. Which window is primary varies by plan
    # - a free plan's is 30 days - so window_minutes is what names it, and each
    # window is judged by its own used_percent.
    param([string]$ConfigDir)
    $root = Join-Path (Get-ChatqHomeDir 'codex' $ConfigDir) 'sessions'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $now = Get-Date
    $best = $null
    $files = @(Get-ChildItem -LiteralPath $root -Filter *.jsonl -File -Recurse -EA SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 10)
    foreach ($f in $files) {
        $t = Read-ChatqTail $f.FullName 262144
        if (-not $t) { continue }
        $i = $t.LastIndexOf('"rate_limits":{', [StringComparison]::Ordinal)
        if ($i -lt 0) { continue }
        $obj = Read-ChatqJsonObjectAt $t ($i + 14)
        $r = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
        if (-not $r) { continue }
        foreach ($w in @($r.primary, $r.secondary)) {
            if (-not $w -or -not $w.resets_at -or [double]$w.used_percent -lt 100) { continue }
            $until = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$w.resets_at).LocalDateTime
            if ($until -gt $now -and (-not $best -or $until -gt $best.Until)) {
                $m = [int]$w.window_minutes
                $type = if ($m -le 300) { 'five_hour' } elseif ($m -le 10080) { 'weekly' } else { 'monthly' }
                $best = [pscustomobject]@{ Until = $until; Type = $type; Source = 'rollout'; At = (Get-ChatqRecordTime $t $i) }
            }
        }
        break   # the newest snapshot is the current one
    }
    return $best
}

function Get-ChatqClaudeStatus {
    # "Claude Code" on status.claude.com: operational, degraded_performance,
    # partial_outage, major_outage or under_maintenance. $null when the page
    # cannot be read - a laptop just woken has no network yet.
    try {
        $j = if ($script:ChatqStatusUrl -notmatch '^https?://' -and (Test-Path -LiteralPath $script:ChatqStatusUrl)) {
            Get-Content -LiteralPath $script:ChatqStatusUrl -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        else {
            if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            }
            Invoke-RestMethod -Uri $script:ChatqStatusUrl -Method Get -TimeoutSec 15 -UseBasicParsing
        }
        $c = @($j.components | Where-Object { $_.name -eq $script:ChatqStatusComponent }) | Select-Object -First 1
        if (-not $c) { $c = @($j.components | Where-Object { $_.name -like 'Claude API*' }) | Select-Object -First 1 }
        if ($c) { return [string]$c.status }
    }
    catch {}
    return $null
}

function Invoke-ChatqProbe {
    <#
    Is the limit really over, or the overload? A throwaway "ok" that saves no
    session - 3 s and half a cent on haiku, measured - asked before any real
    chat is touched. Sending the real prompt while still limited would plant
    it, and an error after it, in that chat. Asked with the chat's own model: a
    weekly limit can be one model's alone, and haiku would sail through it.
    #>
    param([string]$Provider, $Job, [switch]$NoModel)
    $exe = Find-ChatqExe $Provider
    if (-not $exe) { return [pscustomobject]@{ Allowed = $false; Limited = $false; Overloaded = $false; Error = "no $Provider CLI found"; Until = $null; Type = $null } }
    $dir = if ($Job.cwd -and (Test-Path -LiteralPath $Job.cwd)) { $Job.cwd } else { $script:ChatqData }
    $st = New-ChatqRunState
    if ($Provider -eq 'codex') {
        $args2 = @('exec', '--ephemeral', '--skip-git-repo-check', '--json', '-s', 'read-only', '-')
        $proc = Invoke-ChatqProcess -Exe $exe -ArgList $args2 -WorkDir $dir -StdIn 'Reply with one word: ok' `
            -SetEnv @{ CODEX_HOME = $Job.home } -TimeoutSec 180 -OnLine { param($l) Update-ChatqCodexState $st $l }
        $out = Get-ChatqCodexOutcome $st $proc
        $ok = $out.kind -eq 'done'
    }
    else {
        # default mode: the probe asks nothing, and a settings defaultMode of
        # plan must not read as "needs input" here
        $args2 = @('-p', '--no-session-persistence', '--safe-mode', '--tools', '', '--permission-mode', 'default',
            '--output-format', 'stream-json', '--verbose')
        if ($Job.model -and -not $NoModel) { $args2 += @('--model', $Job.model) }
        $proc = Invoke-ChatqProcess -Exe $exe -ArgList $args2 -WorkDir $dir -StdIn 'Reply with one word: ok' `
            -SetEnv @{ CLAUDE_CONFIG_DIR = $Job.home } -TimeoutSec 180 -OnLine { param($l) Update-ChatqClaudeState $st $l }
        $out = Get-ChatqClaudeOutcome $st $proc 'default'
        $ok = $out.kind -notin 'limited', 'overloaded' -and $st.Result -and -not $st.Result.is_error
        # a model id from months ago may be retired; the run itself never names
        # one (a resume keeps the chat's model), so ask again without it
        if (-not $ok -and $out.kind -eq 'failed' -and $Job.model -and -not $NoModel) {
            return (Invoke-ChatqProbe $Provider $Job -NoModel)
        }
    }
    $until = if ($out.resetsAt) { ConvertTo-ChatqDate $out.resetsAt } else { $null }
    return [pscustomobject]@{
        Allowed    = [bool]$ok
        Limited    = $out.kind -eq 'limited'
        Overloaded = $out.kind -eq 'overloaded'
        Until      = $until
        Type       = $out.limitType
        Error      = if (-not $ok -and $out.kind -notin 'limited', 'overloaded') { $(if ($out.reason) { $out.reason } else { $out.kind }) } else { $null }
    }
}

#endregion

#region running one job -------------------------------------------------------

function Invoke-ChatqRun {
    # Deliver one job's prompt into its chat and read what came back. The
    # caller owns the job's state; this only runs and classifies.
    param($Job, [string]$Prompt, [scriptblock]$OnTick, [scriptblock]$OnStart)
    $exe = Find-ChatqExe $Job.provider
    if (-not $exe) { return [pscustomobject]@{ kind = 'failed'; reason = "no $($Job.provider) CLI found - install it or set CHATQ_$($Job.provider.ToUpper())" } }
    $log = Join-Path $script:ChatqLogDir "$($Job.id).jsonl"
    $st = New-ChatqRunState
    $mode = if ($Job.mode) { $Job.mode } elseif ($Job.modeAtQueue) { $Job.modeAtQueue } else { 'default' }
    if ($Job.provider -eq 'codex') {
        $sandbox = if ($Job.sandbox) { $Job.sandbox } else { 'workspace-write' }
        $a = @('exec', 'resume', '--json', '--skip-git-repo-check', '-c', "sandbox_mode=$sandbox")
        if ($Job.network) { $a += @('-c', 'sandbox_workspace_write.network_access=true') }
        $a += @($Job.sessionId, '-')
        $proc = Invoke-ChatqProcess -Exe $exe -ArgList $a -WorkDir $Job.cwd -StdIn $Prompt -LogPath $log `
            -SetEnv @{ CODEX_HOME = $Job.home } -OnTick $OnTick -OnLine {
            param($l)
            Update-ChatqCodexState $st $l
            if ($st.Init -and -not $st.Started) { $st.Started = $true; if ($OnStart) { & $OnStart $st } }
        }
        return (Get-ChatqCodexOutcome $st $proc)
    }
    $v = Get-ChatqCliVersion $exe
    if ($v -and ((Compare-ChatqVersion $v $script:ChatqClaudeMin) -eq -1)) {
        return [pscustomobject]@{ kind = 'failed'; reason = "Claude Code $v is too old for unattended runs - needs $($script:ChatqClaudeMin)+" }
    }
    $a = @('-p', '--resume', $Job.sessionId, '--output-format', 'stream-json', '--verbose',
        '--permission-mode', $mode, '--permission-prompts', 'none')
    $proc = Invoke-ChatqProcess -Exe $exe -ArgList $a -WorkDir $Job.cwd -StdIn $Prompt -LogPath $log `
        -SetEnv @{ CLAUDE_CONFIG_DIR = $Job.home } -OnTick $OnTick -OnLine {
        param($l)
        Update-ChatqClaudeState $st $l
        if ($st.Init -and -not $st.Started) { $st.Started = $true; if ($OnStart) { & $OnStart $st } }
    }
    return (Get-ChatqClaudeOutcome $st $proc $mode)
}

#endregion

#region live chats ------------------------------------------------------------
# Each VS Code window keeps a claude process alive for every chat opened in it,
# not just the one on screen, and clicking a chat in the history list switches
# back to that live process rather than re-reading the transcript. A run
# delivered from outside lands in the transcript that process never re-reads.

function Get-ChatqLiveSessions {
    # claude agents --json lists them all, panel tabs included, with no TTY.
    # ~/.claude/sessions/<pid>.json is the registry behind it - the fallback.
    param([string]$ConfigDir)
    $exe = Find-ChatqExe claude
    if ($exe) {
        $buf = [System.Collections.Generic.List[string]]::new()
        try {
            $null = Invoke-ChatqProcess -Exe $exe -ArgList @('agents', '--json') -StdIn '' -TimeoutSec 30 `
                -SetEnv @{ CLAUDE_CONFIG_DIR = $ConfigDir } -OnLine { param($l) $buf.Add($l) }
            $list = ($buf -join "`n") | ConvertFrom-Json
            if ($null -ne $list) {
                return @($list | ForEach-Object {
                        [pscustomobject]@{ SessionId = $_.sessionId; Pid = $_.pid; Status = $_.status; Kind = $_.kind; WaitingFor = $_.waitingFor; ProcStart = $null }
                    })
            }
        }
        catch {}
    }
    # A registry file can outlive its process, and the pid be reused by
    # something else - only a claude that started when the file says counts.
    $dir = Join-Path (Get-ChatqHomeDir 'claude' $ConfigDir) 'sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter *.json -File -EA SilentlyContinue)) {
            $o = Read-ChatqJson $f.FullName
            if (-not $o -or -not $o.pid) { continue }
            $pr = Get-Process -Id $o.pid -EA SilentlyContinue
            if (-not (Test-ChatqClaudeProcess $pr $o.procStart)) { continue }
            [pscustomobject]@{ SessionId = $o.sessionId; Pid = $o.pid; Status = $o.status; Kind = $o.kind; WaitingFor = $null; ProcStart = $o.procStart }
        })
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

#endregion

#region config and alerts -----------------------------------------------------

function Get-ChatqConfig {
    $c = Read-ChatqJson $script:ChatqConfigPath
    if (-not $c) { $c = [pscustomobject]@{} }
    return $c
}

function Set-ChatqProp {
    # ConvertFrom-Json objects only take assignment to properties they have
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Protect-ChatqSecret {
    # DPAPI on Windows: only this user on this machine can read it back, which
    # is exactly who the watcher runs as. Elsewhere there is no DPAPI, so it is
    # stored as given and the file is made owner-only.
    param([string]$Plain)
    if ($script:ChatqIsWindows) {
        $ss = ConvertTo-SecureString $Plain -AsPlainText -Force
        return @{ value = (ConvertFrom-SecureString $ss); protected = $true }
    }
    return @{ value = $Plain; protected = $false }
}

function Unprotect-ChatqSecret {
    param($Secret)
    if (-not $Secret -or -not $Secret.value) { return $null }
    if (-not $Secret.protected) { return [string]$Secret.value }
    try {
        $ss = ConvertTo-SecureString ([string]$Secret.value)
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    }
    catch { return $null }
}

function Get-ChatqJoinUrl {
    # Join's push API is one GET. Hangul is nine bytes per syllable once
    # escaped, so the text is trimmed until the whole URL fits.
    param([string]$Key, [string]$Device, [string]$Title, [string]$Text, [int]$Priority)
    $base = 'https://joinjoaomgcd.appspot.com/_ah/api/messaging/v1/sendPush?'
    $dev = if ($Device -match '^[0-9a-fA-F]{32}$' -or $Device -match '^group\.') { 'deviceId' } else { 'deviceNames' }
    $t = [string]$Text
    while ($true) {
        $q = [ordered]@{ apikey = $Key; $dev = $Device; title = $Title; text = $t; priority = $Priority; group = 'chatq' }
        $url = $base + (($q.GetEnumerator() | ForEach-Object { $_.Key + '=' + [Uri]::EscapeDataString([string]$_.Value) }) -join '&')
        if ($url.Length -le 1900 -or $t.Length -le 20) { return $url }
        $t = $t.Substring(0, [int]($t.Length * 0.85)).TrimEnd() + $script:ChatqEllipsis
    }
}

function Send-ChatqAlert {
    <#
    Every alert goes to logs/alerts.log; with Join set up it also reaches the
    phone. Titles all start "chatq <dot> ", so a Tasker profile on the Join
    plugin's event can filter them - or match only "needs input" and "failed".
    What the text carries (chat title, an excerpt of the reply) passes through
    Join's and Google's push servers.
    #>
    param([string]$Event, [string]$Text, [int]$Priority = 0)
    $title = "chatq $($script:ChatqDot) $Event"
    try {
        New-ChatqDir $script:ChatqLogDir
        $line = "{0}`t{1}`t{2}" -f (Get-Date).ToString('o'), $Event, ($Text -replace '\s+', ' ')
        [System.IO.File]::AppendAllText((Join-Path $script:ChatqLogDir 'alerts.log'), $line + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
    catch {}
    $cfg = Get-ChatqConfig
    if (-not $cfg.join) { return $false }
    $key = Unprotect-ChatqSecret $cfg.join.apiKey
    if (-not $key -or -not $cfg.join.device) { return $false }
    if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    $url = Get-ChatqJoinUrl $key $cfg.join.device $title $Text $Priority
    for ($try = 1; $try -le 3; $try++) {
        try {
            $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20 -UseBasicParsing
            if ($r.success) { return $true }
            $script:ChatqLastAlertError = [string]$r.errorMessage
            return $false
        }
        catch {
            $script:ChatqLastAlertError = $_.Exception.Message
            Start-Sleep -Seconds (2 * $try)
        }
    }
    return $false
}

#endregion

#region status: the list and the board ----------------------------------------

function Get-ChatqState {
    $s = Read-ChatqJson $script:ChatqStatePath
    if (-not $s) { $s = [pscustomobject]@{} }
    return $s
}

function Test-ChatqWatcherAlive {
    # The watcher holds watcher.lock open with no sharing for its whole life,
    # and the OS lets go of it even when the process dies hard - so being able
    # to open it means nobody is watching. A pid file alone would lie after a
    # crash, and pids get reused.
    if (-not (Test-Path -LiteralPath $script:ChatqLockPath)) { return $false }
    try {
        $fs = [System.IO.File]::Open($script:ChatqLockPath, 'Open', 'ReadWrite', 'None')
        $fs.Dispose()
        return $false
    }
    catch { return $true }
}

function Get-ChatqBlocks {
    # When each lane is free again, keyed like the watcher keys it: its own
    # view while it runs - limits and overloads both - a fresh scan otherwise.
    param([switch]$Scan)
    $out = @{}
    $s = Get-ChatqState
    if (-not $Scan -and (Test-ChatqWatcherAlive)) {
        if ($s.blocked) {
            foreach ($p in $s.blocked.PSObject.Properties) {
                $u = ConvertTo-ChatqDate $p.Value.until
                if ($u -and $u -gt (Get-Date)) { $out[$p.Name] = [pscustomobject]@{ Until = $u; Type = $p.Value.type; Source = $p.Value.source } }
            }
        }
        if ($s.outage) {
            foreach ($p in $s.outage.PSObject.Properties) {
                $out[$p.Name] = [pscustomobject]@{
                    Until = ConvertTo-ChatqDate $p.Value.next; Type = 'overloaded'; Status = $p.Value.status
                    Since = ConvertTo-ChatqDate $p.Value.since; Source = 'status.claude.com'
                }
            }
        }
        return $out
    }
    $lanes = @{ claude = $null; codex = $null }
    foreach ($j in @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' -and $_.home })) { $lanes[(Get-ChatqLane $j)] = $j.home }
    foreach ($lane in @($lanes.Keys)) {
        $b = if ($lane -like 'codex*') { Get-ChatqCodexBlock $lanes[$lane] } else { Get-ChatqClaudeBlock $lanes[$lane] }
        if ($b) { $out[$lane] = $b }
    }
    return $out
}

function Get-ChatqEta {
    # "sends" per queued job, the way the watcher picks: a job with a wait of
    # its own sends when that wait ends; one free now waits only behind the
    # run in progress and the free jobs queued before it - never behind a job
    # that is itself waiting, which the watcher skips
    param([object[]]$Jobs, [hashtable]$Blocks)
    $eta = @{}
    $now = Get-Date
    $running = @($Jobs | Where-Object { $_.state -eq 'running' }) | Select-Object -First 1
    $ahead = $running
    foreach ($j in @($Jobs | Where-Object { $_.state -in 'queued', 'running' })) {
        if ($j.state -eq 'running') { $eta[$j.id] = 'running'; continue }
        $lane = Get-ChatqLane $j
        $b = $Blocks[$lane]
        $times = @()
        $why = $null
        if ($b -and $b.Type -eq 'overloaded') { $why = 'overloaded' }
        elseif ($b -and $b.Until) { $times += $b.Until.AddMinutes(1) }
        $nb = ConvertTo-ChatqDate $j.notBefore
        if ($nb) { $times += $nb }
        $du = ConvertTo-ChatqDate $j.deferUntil
        if ($du -and $du -gt $now) { $times += $du; if (-not $why) { $why = 'chat busy' } }
        $at = $times | Where-Object { $_ -gt $now } | Sort-Object -Descending | Select-Object -First 1
        $eta[$j.id] = if ($why -eq 'overloaded') { 'when Claude is back' }
        elseif ($at) {
            $fmt = if ($at.Date -eq $now.Date) { 'HH:mm' } else { 'ddd HH:mm' }
            $s = $at.ToString($fmt, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($why) { "$s ($why)" } else { $s }
        }
        elseif ($ahead) { "after #$($ahead.seq)" }
        else { 'next' }
        if (-not $at -and -not $why) { $ahead = $j }
    }
    return $eta
}

function Get-ChatqPromptStats {
    param([string]$Text)
    $first = @($Text -split '\r?\n' | Where-Object { $_.Trim() })[0]
    $lines = @($Text -split '\r?\n').Count
    [pscustomobject]@{ First = if ($first) { $first.Trim() } else { '' }; Chars = $Text.Length; Lines = $lines }
}

function Get-ChatqCells {
    # width in console cells, not characters: Hangul and CJK draw two cells each
    param([string]$Text)
    $n = 0
    foreach ($c in $Text.ToCharArray()) {
        $u = [int]$c
        if (($u -ge 0x1100 -and $u -le 0x115F) -or ($u -ge 0x2E80 -and $u -le 0x303E) -or
            ($u -ge 0x3041 -and $u -le 0x33FF) -or ($u -ge 0x3400 -and $u -le 0x4DBF) -or
            ($u -ge 0x4E00 -and $u -le 0x9FFF) -or ($u -ge 0xA000 -and $u -le 0xA4CF) -or
            ($u -ge 0xAC00 -and $u -le 0xD7A3) -or ($u -ge 0xF900 -and $u -le 0xFAFF) -or
            ($u -ge 0xFE30 -and $u -le 0xFE6F) -or ($u -ge 0xFF00 -and $u -le 0xFF60) -or
            ($u -ge 0xFFE0 -and $u -le 0xFFE6)) { $n += 2 } else { $n++ }
    }
    return $n
}

function Format-ChatqCell {
    # clip to exactly $Cells console cells, padding short text out to the same
    param([string]$Text, [int]$Cells, [switch]$NoPad)
    if ($Cells -le 0) { return '' }
    $w = Get-ChatqCells $Text
    if ($w -le $Cells) {
        if ($NoPad) { return $Text }
        return $Text + (' ' * ($Cells - $w))
    }
    $len = 0
    $used = 0
    while ($len -lt $Text.Length) {
        $cw = Get-ChatqCells $Text.Substring($len, 1)
        if ($used + $cw -gt $Cells - 1) { break }
        $used += $cw
        $len++
    }
    $out = $Text.Substring(0, $len) + $script:ChatqEllipsis
    if ($NoPad) { return $out }
    return $out + (' ' * [Math]::Max(0, $Cells - $used - 1))
}

function Get-ChatqWidth {
    $w = 0
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch {}
    if (-not $w -or $w -lt 40) { $w = 100 }
    return $w
}

function Get-ChatqStatusLine {
    param([object[]]$Jobs, [hashtable]$Blocks)
    $q = @($Jobs | Where-Object { $_.state -eq 'queued' }).Count
    $parts = @("$q queued")
    $run = @($Jobs | Where-Object { $_.state -eq 'running' })
    if ($run) { $parts += "running #$($run[0].seq)" }
    foreach ($lane in @($Blocks.Keys | Sort-Object)) {
        $b = $Blocks[$lane]
        $name = Format-ChatqLane $lane
        if ($b.Type -eq 'overloaded') {
            $st = if ($b.Status) { ", status.claude.com: $($b.Status -replace '_', ' ')" } else { '' }
            $since = if ($b.Since) { " since $($b.Since.ToString('HH:mm'))" } else { '' }
            $parts += "$name overloaded$since$st - retrying"
            continue
        }
        if (-not $b.Until) { continue }
        $u = $b.Until
        $fmt = if ($u.Date -eq (Get-Date).Date) { 'HH:mm' } else { 'ddd HH:mm' }
        $parts += "$name limited until $($u.ToString($fmt, [System.Globalization.CultureInfo]::InvariantCulture)) ($($b.Type))"
    }
    $parts += if (Test-ChatqWatcherAlive) { 'watcher running' } else { 'watcher stopped' }
    return 'chatq ' + $script:ChatqDot + ' ' + ($parts -join " $($script:ChatqDot) ")
}

function Write-ChatqList {
    param([switch]$All)
    $jobs = @(Get-ChatqJobs)
    $blocks = Get-ChatqBlocks
    $eta = Get-ChatqEta $jobs $blocks
    $width = Get-ChatqWidth
    Write-Host ''
    Write-Host (' ' + (Get-ChatqStatusLine $jobs $blocks)) -ForegroundColor DarkGray

    $open = @($jobs | Where-Object { $_.state -in 'queued', 'running', 'needs-input', 'failed' })
    if ($open) {
        $sendW = 16
        $numW = 4
        $rest = [Math]::Max(30, $width - $numW - $sendW - 6)
        $chatW = [int]($rest * 0.42)
        $promptW = $rest - $chatW
        Write-Host ('  ' + (Format-ChatqCell '#' $numW) + (Format-ChatqCell 'chat' $chatW) + ' ' +
            (Format-ChatqCell 'prompt' $promptW) + ' ' + 'sends') -ForegroundColor DarkGray
        foreach ($j in $open) {
            $text = if ($j.kind -eq 'continue') { 'continue' } else { [string](Read-ChatqPrompt $j) }
            $ps = Get-ChatqPromptStats $text
            $when = ConvertTo-ChatqDate $j.chatWhen
            $age = if ($when) { " ($(Get-ChatqAge $when))" } else { '' }
            $state = switch ($j.state) {
                'queued' { $eta[$j.id] }
                'running' {
                    $s = ConvertTo-ChatqDate $j.startedAt
                    $a = if ($s) { Get-ChatqAge $s } else { 'now' }
                    if ($a -eq 'now') { 'running' } else { "running $a" }
                }
                'needs-input' { 'needs you' }
                'failed' { 'failed' }
            }
            $color = switch ($j.state) { 'needs-input' { 'Yellow' } 'failed' { 'Red' } 'running' { 'Green' } default { 'Gray' } }
            Write-Host ('  ' + (Format-ChatqCell "$($j.seq)" $numW)) -NoNewline
            Write-Host ((Format-ChatqCell "$($j.title)$age" $chatW) + ' ') -NoNewline -ForegroundColor Cyan
            Write-Host ((Format-ChatqCell $ps.First $promptW) + ' ') -NoNewline
            Write-Host $state -ForegroundColor $color
            $pad = ' ' * (2 + $numW + $chatW + 1)
            if ($ps.Lines -gt 1 -or (Get-ChatqCells $ps.First) -gt $promptW) {
                Write-Host ($pad + [char]0x21B3 + ' ' + ('{0:N0} chars {1} {2} lines' -f $ps.Chars, $script:ChatqDot, $ps.Lines)) -ForegroundColor DarkGray
            }
            if ($j.state -in 'needs-input', 'failed' -and $j.result.reason) {
                Write-Host ($pad + (Format-ChatqCell ([string]$j.result.reason) $promptW -NoPad)) -ForegroundColor DarkGray
            }
        }
    }
    else {
        Write-Host '  nothing queued' -ForegroundColor DarkGray
    }

    $cut = @(Get-ChatqCutOffChats $jobs)
    if ($cut) {
        $names = ($cut | Select-Object -First 4 | ForEach-Object {
                $w = if ($_.Why -eq 'overloaded') { '529' } else { 'limit' }
                "$($_.Title) ($w $(if ($_.At) { $_.At.ToString('HH:mm') }))"
            }) -join ', '
        Write-Host "  cut off, nothing queued:  $names" -ForegroundColor Yellow
        Write-Host "    chatq '<title>' -Continue  queues a continue for one" -ForegroundColor DarkGray
    }

    $since = if ($All) { [datetime]::MinValue } else { (Get-Date).AddHours(-24) }
    $done = @($jobs | Where-Object { $_.state -in 'done', 'skipped' -and (ConvertTo-ChatqDate $_.endedAt) -gt $since })
    foreach ($j in $done) {
        $end = ConvertTo-ChatqDate $j.endedAt
        $mark = if ($j.state -eq 'skipped') { '-' } else { [string][char]0x2713 }
        $x = if ($j.result.excerpt) { " $($script:ChatqDot) `"$($j.result.excerpt)`"" } elseif ($j.result.reason) { " $($script:ChatqDot) $($j.result.reason)" } else { '' }
        $line = "  $mark #$($j.seq) $($j.title)$x"
        Write-Host ((Format-ChatqCell $line ($width - 8) -NoPad) + '  ' + $end.ToString('HH:mm')) -ForegroundColor DarkGray
    }
    Write-Host "  chatq <n> opens prompt n $($script:ChatqDot) chatqlist -Board = live board in VS Code $($script:ChatqDot) chatqlog <n> = what a run did" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-ChatqFence {
    # a code fence longer than any backtick run inside the prompt
    param([string]$Text)
    $max = 2
    foreach ($m in [regex]::Matches($Text, '`+')) { if ($m.Length -gt $max) { $max = $m.Length } }
    return ('`' * ($max + 1))
}

function Write-ChatqBoard {
    # data/queue.md - open it once in VS Code with Ctrl+Shift+V and the preview
    # follows every change the watcher writes. Long prompts fold away.
    try {
        $jobs = @(Get-ChatqJobs)
        $blocks = Get-ChatqBlocks
        $eta = Get-ChatqEta $jobs $blocks
        # a pipe as an entity, not \| - text that already holds \| (grep
        # alternation) would otherwise end up \\| and split the cell
        $e = { param($s) ([string]$s -replace '\|', '&#124;' -replace '[\r\n]+', ' ') }
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('# chatq')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((Get-ChatqStatusLine $jobs $blocks) + " $($script:ChatqDot) updated $((Get-Date).ToString('HH:mm:ss'))")
        [void]$sb.AppendLine()
        $open = @($jobs | Where-Object { $_.state -in 'queued', 'running', 'needs-input', 'failed' })
        $recent = @($jobs | Where-Object { $_.state -in 'done', 'skipped' -and (ConvertTo-ChatqDate $_.endedAt) -gt (Get-Date).AddDays(-2) })
        if ($open -or $recent) {
            [void]$sb.AppendLine('| # | chat | state | sends | prompt |')
            [void]$sb.AppendLine('|---|------|-------|-------|--------|')
            foreach ($j in @($open) + @($recent)) {
                $text = if ($j.kind -eq 'continue') { 'continue' } else { [string](Read-ChatqPrompt $j) }
                $ps = Get-ChatqPromptStats $text
                $first = if ($ps.First.Length -gt 60) { $ps.First.Substring(0, 60) + $script:ChatqEllipsis } else { $ps.First }
                $sends = if ($j.state -eq 'queued') { $eta[$j.id] } else { '' }
                [void]$sb.AppendLine("| $($j.seq) | $(& $e $j.title) | $($j.state) | $(& $e $sends) | $(& $e $first) ($('{0:N0}' -f $ps.Chars) chars) |")
            }
            [void]$sb.AppendLine()
            foreach ($j in @($open) + @($recent)) {
                $text = if ($j.kind -eq 'continue') { $script:ChatqContinueText } else { [string](Read-ChatqPrompt $j) }
                $ps = Get-ChatqPromptStats $text
                $mode = if ($j.mode) { $j.mode } else { $j.modeAtQueue }
                [void]$sb.AppendLine("## #$($j.seq) $($script:ChatqDot) $(& $e $j.title)")
                [void]$sb.AppendLine()
                [void]$sb.AppendLine("$($j.provider) $($script:ChatqDot) $mode $($script:ChatqDot) ``$($j.cwd)`` $($script:ChatqDot) $($j.state) $($script:ChatqDot) picked by $($j.rule)")
                [void]$sb.AppendLine()
                if ($j.result -and ($j.result.reason -or $j.result.excerpt)) {
                    if ($j.result.reason) { [void]$sb.AppendLine("> **$($j.result.kind)** $(& $e $j.result.reason)") }
                    if ($j.result.excerpt) { [void]$sb.AppendLine("> $(& $e $j.result.excerpt)") }
                    [void]$sb.AppendLine()
                    [void]$sb.AppendLine("[run log](logs/$($j.id).jsonl)")
                    [void]$sb.AppendLine()
                }
                $f = Get-ChatqFence $text
                $sum = [System.Net.WebUtility]::HtmlEncode($(if ($ps.First.Length -gt 80) { $ps.First.Substring(0, 80) + $script:ChatqEllipsis } else { $ps.First }))
                [void]$sb.AppendLine("<details><summary>$sum $($script:ChatqDot) $('{0:N0}' -f $ps.Chars) chars</summary>")
                [void]$sb.AppendLine()
                [void]$sb.AppendLine("$f" + 'text')
                [void]$sb.AppendLine($text)
                [void]$sb.AppendLine($f)
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('</details>')
                [void]$sb.AppendLine()
            }
        }
        else {
            [void]$sb.AppendLine('_nothing queued_')
        }
        Save-ChatqText $script:ChatqBoardPath $sb.ToString()
    }
    catch {}
}

#endregion

#region the watcher -----------------------------------------------------------
# One per machine, a hidden PowerShell that loads this same file. It sleeps
# until a queued job's provider is free, checks with a probe, runs the job, and
# exits when nothing is left. Nothing is registered with the OS: loading the
# profile starts it again if jobs are pending, which covers a reboot.

function Get-ChatqLane {
    # What a limit or an overload applies to: the provider, and the account
    # when the job names its own config dir. Two accounts do not share a limit.
    param($Job)
    if ($Job.home) { return "$($Job.provider)|$($Job.home)" }
    return [string]$Job.provider
}

function Format-ChatqLane {
    param([string]$Lane)
    $p, $h = $Lane -split '\|', 2
    $name = (Get-Culture).TextInfo.ToTitleCase([string]$p)
    if ($h) { return "$name ($h)" }
    return $name
}

function New-ChatqWatchState {
    @{
        blocked = @{}; lastAllowed = @{}; probeFails = @{}; scannedAt = @{}; outage = @{}
        current = $null; next = $null; startedAt = $null
    }
}

function Save-ChatqWatchState {
    param($W)
    $blocked = @{}
    foreach ($k in @($W.blocked.Keys)) {
        $b = $W.blocked[$k]
        if ($b) { $blocked[$k] = @{ until = $b.Until.ToUniversalTime().ToString('o'); type = $b.Type; source = $b.Source } }
    }
    $outage = @{}
    foreach ($k in @($W.outage.Keys)) {
        $o = $W.outage[$k]
        if ($o) {
            $outage[$k] = @{
                since = $o.Since.ToUniversalTime().ToString('o'); next = $o.NextCheck.ToUniversalTime().ToString('o')
                status = $o.Status; attempts = $o.Attempts
            }
        }
    }
    $s = [ordered]@{
        pid = $PID; version = $script:ChatqVersion; startedAt = $W.startedAt; heartbeat = (Get-ChatqStamp)
        current = $W.current; next = $W.next; blocked = $blocked; outage = $outage
    }
    try { Save-ChatqJson $script:ChatqStatePath $s } catch {}
}

function Set-ChatqKeepAwake {
    # A limit resets 1-5 h out and a default power plan sleeps after 15-30
    # minutes of no input - without this, "unattended" fails in the ordinary
    # case. The display may still turn off; only system sleep is held off.
    param([bool]$On)
    if ($script:ChatqAwake -eq $On) { return }
    try {
        if ($script:ChatqIsWindows) {
            if (-not ('ChatqPower' -as [type])) {
                Add-Type -Name ChatqPower -Namespace '' -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
            }
            # ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x1), or CONTINUOUS alone to let go
            $flags = if ($On) { [uint32]2147483649 } else { [uint32]2147483648 }
            [void][ChatqPower]::SetThreadExecutionState($flags)
        }
        elseif ($On) {
            # Both inhibitors end on their own when the watcher does, however it
            # dies: caffeinate -w watches the pid, and tail --pid exits with it.
            # A plain 'sleep infinity' would hold the machine awake for good
            # after a kill -9.
            $cmd = if ($script:ChatqIsMac) { @('caffeinate', '-i', '-w', "$PID") }
            elseif (Get-Command systemd-inhibit -EA SilentlyContinue) {
                @('systemd-inhibit', '--what=sleep:idle', '--who=chatq', '--why=queued prompts', 'tail', "--pid=$PID", '-f', '/dev/null')
            }
            if ($cmd) { $script:ChatqAwakeProc = Start-Process -FilePath $cmd[0] -ArgumentList $cmd[1..($cmd.Count - 1)] -PassThru }
        }
        elseif ($script:ChatqAwakeProc) {
            try { $script:ChatqAwakeProc.Kill($true) } catch { try { $script:ChatqAwakeProc.Kill() } catch {} }
            $script:ChatqAwakeProc = $null
        }
        $script:ChatqAwake = $On
    }
    catch {}
}

function Write-ChatqWatchLog {
    param([string]$Text)
    try {
        New-ChatqDir $script:ChatqLogDir
        $p = Join-Path $script:ChatqLogDir 'watcher.log'
        if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).Length -gt 1MB) {
            Move-Item -LiteralPath $p -Destination "$p.1" -Force
        }
        [System.IO.File]::AppendAllText($p, "$((Get-Date).ToString('o'))  $Text`n", (New-Object System.Text.UTF8Encoding $false))
        if ($script:ChatqForeground) { Write-Host "  $((Get-Date).ToString('HH:mm:ss'))  $Text" -ForegroundColor DarkGray }
    }
    catch {}
}

function Update-ChatqBlock {
    # re-read when a lane is free again - at most every 10 minutes while
    # waiting, since it means reading the tails of 30 transcripts
    param($W, $Job, [switch]$Force)
    $lane = Get-ChatqLane $Job
    $at = $W.scannedAt[$lane]
    if (-not $Force -and $at -and ((Get-Date) - $at).TotalMinutes -lt 10) { return }
    $b = if ($Job.provider -eq 'codex') { Get-ChatqCodexBlock $Job.home } else { Get-ChatqClaudeBlock $Job.home }
    # a record written before a probe that said "allowed" is history, not a
    # wall - the limit was lifted early, or extra usage carries the account
    $ok = $W.lastAllowed[$lane]
    if ($b -and $ok -and (-not $b.At -or $b.At -lt $ok)) { $b = $null }
    $cur = $W.blocked[$lane]
    if ($b -and (-not $cur -or $b.Until -gt $cur.Until)) { $W.blocked[$lane] = $b }
    $W.scannedAt[$lane] = Get-Date
}

function Enter-ChatqOutage {
    # A 529 Overloaded, or another 5xx: the server's trouble, not the account's.
    # Wait for status.claude.com to show Claude Code operational again, and try
    # again at once when it does; a blip the page never shows is retried after
    # 1, 2, 5, 10, then every 15 minutes.
    param($W, $Job, [string]$Why)
    $lane = Get-ChatqLane $Job
    $now = Get-Date
    $o = $W.outage[$lane]
    if (-not $o) {
        $o = @{ Since = $now; Attempts = 0; Status = $null; Alerted = $false; LastProbe = $now; NextCheck = $now }
        $W.outage[$lane] = $o
    }
    $o.Attempts++
    $o.LastProbe = $now
    $steps = @(1, 2, 5, 10, 15)
    $o.NextCheck = $now.AddMinutes($steps[[Math]::Min($o.Attempts, $steps.Count) - 1])
    if ($Job.provider -eq 'claude') { $o.Status = Get-ChatqClaudeStatus }
    $page = if ($o.Status) { " $($script:ChatqDot) status.claude.com: $($o.Status -replace '_', ' ')" } else { '' }
    Write-ChatqWatchLog "$lane overloaded ($Why)$page - next check $($o.NextCheck.ToString('HH:mm:ss'))"
    if (-not $o.Alerted) {
        $o.Alerted = $true
        [void](Send-ChatqAlert 'overloaded' "$($Job.title) $($script:ChatqDot) $Why$page $($script:ChatqDot) resumes when Claude is back" 0)
    }
}

function Test-ChatqOutageOver {
    # Worth a probe yet? When status.claude.com shows Claude Code operational
    # again - checked every minute during an outage - or when 15 minutes went
    # by since the last try, in case the page lags behind the service.
    param($W, $Job)
    $lane = Get-ChatqLane $Job
    $o = $W.outage[$lane]
    if (-not $o) { return $true }
    $now = Get-Date
    if ($now -lt $o.NextCheck) { return $false }
    $s = if ($Job.provider -eq 'claude') { Get-ChatqClaudeStatus } else { $null }
    if ($s -ne $o.Status) { Write-ChatqWatchLog "status.claude.com: Claude Code $s" }
    $o.Status = $s
    if ($s -eq 'operational' -or ($now - $o.LastProbe).TotalMinutes -ge 15) { return $true }
    $o.NextCheck = $now.AddSeconds(60)
    return $false
}

function Confirm-ChatqAllowed {
    # A probe, unless one with this job's model and account said "allowed" in
    # the last three minutes. The model is part of the key: a weekly limit can
    # belong to one model, and a probe for another says nothing about it.
    param($W, $Job)
    $lane = Get-ChatqLane $Job
    $key = "$lane|$($Job.model)"
    $last = $W.lastAllowed[$key]
    if ($last -and ((Get-Date) - $last).TotalMinutes -lt 3 -and -not $W.outage[$lane]) { return $true }
    if ($W.outage[$lane] -and -not (Test-ChatqOutageOver $W $Job)) { return $false }
    $r = Invoke-ChatqProbe $Job.provider $Job
    if ($r.Allowed) {
        $W.lastAllowed[$key] = Get-Date
        $W.lastAllowed[$lane] = Get-Date
        $W.blocked[$lane] = $null
        $W.probeFails[$lane] = 0
        if ($W.outage[$lane]) {
            $since = $W.outage[$lane].Since
            $W.outage[$lane] = $null
            Write-ChatqWatchLog "$lane back after $([int]((Get-Date) - $since).TotalMinutes) min"
        }
        Write-ChatqWatchLog "$lane allowed"
        return $true
    }
    if ($r.Overloaded) { Enter-ChatqOutage $W $Job 'the probe got 529 Overloaded'; return $false }
    if ($r.Limited) {
        $until = $r.Until
        if (-not $until) {
            $b = if ($Job.provider -eq 'codex') { Get-ChatqCodexBlock $Job.home } else { Get-ChatqClaudeBlock $Job.home }
            if ($b) { $until = $b.Until }
        }
        if (-not $until -or $until -le (Get-Date)) { $until = (Get-Date).AddMinutes(15) }
        $W.blocked[$lane] = [pscustomobject]@{ Until = $until; Type = $r.Type; Source = 'probe' }
        $W.lastAllowed[$lane] = $null
        Write-ChatqWatchLog "$lane still limited until $($until.ToString('HH:mm'))"
        return $false
    }
    # network, login, a CLI that will not start: back off, and say so on the
    # third miss rather than the first - a laptop waking up has no network yet
    $n = [int]$W.probeFails[$lane] + 1
    $W.probeFails[$lane] = $n
    $W.blocked[$lane] = [pscustomobject]@{ Until = (Get-Date).AddMinutes(5 * [Math]::Min($n, 6)); Type = 'probe failed'; Source = $r.Error }
    Write-ChatqWatchLog "$lane probe failed ($n): $($r.Error)"
    if ($n -eq 3) { [void](Send-ChatqAlert 'failed' "can't reach $($Job.provider) to check the limit: $($r.Error)" 2) }
    return $false
}

function Repair-ChatqInterrupted {
    # A job left 'running' never finished: this watcher holds the lock, so no
    # other one can be running it - a live process at its old pid is one that
    # reused the number. Say so, and never send it again on its own: it may
    # have done half its work.
    foreach ($j in @(Get-ChatqJobs | Where-Object { $_.state -eq 'running' })) {
        if ($j.runnerPid -eq $PID) { continue }
        $cancel = Join-Path $script:ChatqQueueDir "$($j.id).cancel"
        if (Test-Path -LiteralPath $cancel) { Remove-Item -LiteralPath $cancel -Force -EA SilentlyContinue }
        if ($j.path -and (Test-ChatqPromptLanded $j.path ([string](Read-ChatqPrompt $j)) $j.startedAt $j.provider)) {
            Set-ChatqProp $j 'retryAs' 'continue'
        }
        Set-ChatqProp $j 'runnerPid' $null
        Set-ChatqProp $j 'result' ([pscustomobject]@{ kind = 'failed'; reason = "interrupted - the watcher stopped mid-run; chatqrun $($j.seq) sends it again" })
        Set-ChatqProp $j 'endedAt' (Get-ChatqStamp)
        Set-ChatqJobState $j 'failed' 'interrupted'
        [void](Send-ChatqAlert 'failed' "$($j.title) $($script:ChatqDot) interrupted mid-run" 2)
    }
}

function Test-ChatqClaudeProcess {
    # Before chatq ends a process it believes is a chat's idle claude: is it
    # one? A registry file can outlive its process and the pid be reused.
    param($Process, $ProcStart)
    if (-not $Process -or $Process.ProcessName -notmatch '^(claude|node)') { return $false }
    if ($ProcStart) {
        try {
            if ([Math]::Abs($Process.StartTime.ToFileTimeUtc() - [int64]$ProcStart) -gt 30000000) { return $false }
        }
        catch {}
    }
    return $true
}

function Complete-ChatqJob {
    # the one way a job leaves the queue for good
    param($Job, [string]$State, $Result, [string]$Why)
    Set-ChatqProp $Job 'result' $Result
    Set-ChatqProp $Job 'endedAt' (Get-ChatqStamp)
    Set-ChatqProp $Job 'runnerPid' $null
    Set-ChatqJobState $Job $State $Why
}

function Invoke-ChatqJob {
    param($W, $Job)
    $now = Get-Date
    # The file as it is now: seconds went by in the probe, and the job may have
    # been dropped or edited meanwhile - saving the old copy would undo that.
    $Job = Find-ChatqJob $Job.id
    if (-not $Job -or $Job.state -ne 'queued') { return }
    $lane = Get-ChatqLane $Job
    $sendsContinue = $Job.kind -eq 'continue' -or $Job.retryAs -eq 'continue'
    # the chat as it is now, not as it was when queued
    if ($Job.provider -eq 'claude') {
        $meta = Get-ChatqClaudeMeta $Job.path $Job.group
        if (-not $meta.Exists) {
            Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = 'the chat is gone - its transcript was deleted' }) 'chat gone'
            [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) chat is gone" 2)
            return
        }
        # A "continue" only makes sense into a chat still stopped where the
        # limit or the 529 left it. One that has moved on - you continued it,
        # or Claude's own auto-continue did - would redo finished work. A
        # requeue you asked for (chatqrun <n>) is sent regardless.
        $checkStop = $Job.kind -eq 'continue' -or ($Job.retryAs -eq 'continue' -and $Job.autoContinue)
        if ($checkStop -and $meta.LastTurn -and -not ($meta.LastTurn.Limit -or $meta.LastTurn.Overloaded)) {
            Complete-ChatqJob $Job 'skipped' ([pscustomobject]@{ kind = 'skipped'; reason = 'already continued - by you or by Claude''s own auto-continue' }) 'already continued'
            Write-ChatqWatchLog "#$($Job.seq) skipped: already continued"
            return
        }
    }
    if (-not $Job.cwd -or -not (Test-Path -LiteralPath $Job.cwd)) {
        Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = "the chat's folder is gone: $($Job.cwd)" }) 'folder gone'
        [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) folder gone" 2)
        return
    }

    $live = if ($Job.provider -eq 'claude') { @(Get-ChatqLiveSessions $Job.home) } else { @() }
    $act = Resolve-ChatqLiveAction $Job $live
    if ($act.Action -eq 'defer') {
        if (-not $Job.deferredSince) { Set-ChatqProp $Job 'deferredSince' (Get-ChatqStamp) }
        $since = ConvertTo-ChatqDate $Job.deferredSince
        $hours = ($now - $since).TotalHours
        if ($hours -ge 24) {
            Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = 'the chat stayed busy for 24 h' }) 'busy 24h'
            [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) busy for 24 h, gave up" 2)
            return
        }
        if ($hours -ge 2 -and -not $Job.busyAlerted) {
            Set-ChatqProp $Job 'busyAlerted' $true
            [void](Send-ChatqAlert 'waiting' "$($Job.title) $($script:ChatqDot) has been busy for 2 h - chatq waits until it is idle" 0)
        }
        Set-ChatqProp $Job 'deferUntil' $now.AddMinutes(5).ToUniversalTime().ToString('o')
        Save-ChatqJob $Job
        Write-ChatqWatchLog "#$($Job.seq) deferred: chat is in use"
        return
    }
    $stale = $false
    if ($act.Action -eq 'stop') {
        foreach ($l in @($act.Live)) {
            $pr = Get-Process -Id $l.Pid -EA SilentlyContinue
            if (Test-ChatqClaudeProcess $pr $l.ProcStart) { Stop-ChatqTree $pr }
        }
        Write-ChatqWatchLog "#$($Job.seq) stopped idle chat process $(@($act.Live.Pid) -join ',')"
    }
    elseif ($act.Action -eq 'warn') { $stale = $true }

    $prompt = if ($sendsContinue) { $script:ChatqContinueText } else { Read-ChatqPrompt $Job }
    if (-not $prompt) {
        Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = 'the prompt file is empty or gone' }) 'empty prompt'
        return
    }

    # once more, just before the prompt goes out: chatqrm during the checks above
    $again = Find-ChatqJob $Job.id
    if (-not $again -or $again.state -ne 'queued') { return }
    # a cancel left behind by an earlier, crashed run must not stop this one
    $cancel = Join-Path $script:ChatqQueueDir "$($Job.id).cancel"
    if (Test-Path -LiteralPath $cancel) { Remove-Item -LiteralPath $cancel -Force -EA SilentlyContinue }

    Set-ChatqProp $Job 'startedAt' (Get-ChatqStamp)
    Set-ChatqProp $Job 'attempts' ([int]$Job.attempts + 1)
    Set-ChatqProp $Job 'runnerPid' $PID
    Set-ChatqProp $Job 'deferUntil' $null
    Set-ChatqProp $Job 'deferredSince' $null
    Set-ChatqJobState $Job 'running' ("attempt $($Job.attempts)")
    $W.current = $Job.id
    Save-ChatqWatchState $W
    Write-ChatqBoard
    Write-ChatqWatchLog "#$($Job.seq) running: $($Job.title)"

    $beat = @{ At = Get-Date }
    $onTick = {
        if (((Get-Date) - $beat.At).TotalSeconds -ge 60) { $beat.At = Get-Date; Save-ChatqWatchState $W }
        (Test-Path -LiteralPath $cancel) -or (Test-Path -LiteralPath $script:ChatqStopPath)
    }
    $onStart = {
        param($st)
        $m = if ($st.Mode) { $st.Mode } else { $Job.mode }
        $what = if ($prompt -eq $script:ChatqContinueText) { 'continue' } else { (Get-ChatqPromptStats $prompt).First }
        if ($what.Length -gt 80) { $what = $what.Substring(0, 80) + $script:ChatqEllipsis }
        [void](Send-ChatqAlert 'started' "$($Job.title) $($script:ChatqDot) $m $($script:ChatqDot) $what" 0)
    }
    $out = Invoke-ChatqRun $Job $prompt $onTick $onStart
    $W.current = $null
    $wasCancelled = Test-Path -LiteralPath $cancel
    if ($wasCancelled) { Remove-Item -LiteralPath $cancel -Force -EA SilentlyContinue }
    Set-ChatqProp $Job 'runnerPid' $null
    if ($stale) { Set-ChatqProp $out 'stale' $true }

    $dur = ''
    $s0 = ConvertTo-ChatqDate $Job.startedAt
    if ($s0) { $dur = Get-ChatqAge $s0; if ($dur -eq 'now') { $dur = '<1m' } }
    $reload = if ($stale) { " $($script:ChatqDot) reload the VS Code window before typing in this chat" } else { '' }
    # limited and overloaded both go back in the queue; a prompt that already
    # reached the chat comes back as "continue", never as itself a second time
    if ($out.kind -in 'limited', 'overloaded' -and -not $wasCancelled) {
        $landed = Test-ChatqPromptLanded $Job.path $prompt $Job.startedAt $Job.provider
        if ($landed -and $prompt -ne $script:ChatqContinueText) {
            Set-ChatqProp $Job 'retryAs' 'continue'
            Set-ChatqProp $Job 'autoContinue' $true
        }
        Set-ChatqProp $Job 'result' $out
    }
    switch ($out.kind) {
        'overloaded' {
            if ($wasCancelled) { Complete-ChatqJob $Job 'failed' $out 'cancelled'; break }
            Set-ChatqJobState $Job 'queued' 'overloaded - waiting for status.claude.com'
            Enter-ChatqOutage $W $Job $out.reason
        }
        'limited' {
            if ($wasCancelled) { Complete-ChatqJob $Job 'failed' $out 'cancelled'; break }
            $until = ConvertTo-ChatqDate $out.resetsAt
            if (-not $until -and $Job.provider -eq 'claude') { $lt = Get-ChatqLastTurn $Job.path; if ($lt.ResetsAt) { $until = $lt.ResetsAt } }
            $W.lastAllowed[$lane] = $null
            if (-not $until) { Update-ChatqBlock $W $Job -Force; if ($W.blocked[$lane]) { $until = $W.blocked[$lane].Until } }
            if (-not $until -or $until -le (Get-Date)) { $until = (Get-Date).AddMinutes(15) }
            $W.blocked[$lane] = [pscustomobject]@{ Until = $until; Type = $out.limitType; Source = 'run' }
            foreach ($k in @($W.lastAllowed.Keys)) { if ($k -like "$lane|*") { $W.lastAllowed[$k] = $null } }
            Set-ChatqJobState $Job 'queued' "limited mid-run, continues at $($until.ToString('HH:mm'))"
            if ($landed) { [void](Send-ChatqAlert 'limited' "$($Job.title) $($script:ChatqDot) hit the limit mid-run, continues at $($until.ToString('HH:mm'))" 0) }
            Write-ChatqWatchLog "#$($Job.seq) limited until $($until.ToString('HH:mm'))"
        }
        'needs-input' {
            Complete-ChatqJob $Job 'needs-input' $out $out.reason
            $x = if ($out.excerpt) { " $($script:ChatqDot) `"$($out.excerpt)`"" } else { '' }
            [void](Send-ChatqAlert 'needs input' "$($Job.title) $($script:ChatqDot) $($out.reason)$x$reload" 2)
            Write-ChatqWatchLog "#$($Job.seq) needs input: $($out.reason)"
        }
        'done' {
            Complete-ChatqJob $Job 'done' $out 'finished'
            $turns = if ($out.turns) { ", $($out.turns) turns" } else { '' }
            $ask = if ($out.asks) { 'asks: ' } else { '' }
            $x = if ($out.excerpt) { " $($script:ChatqDot) $ask`"$($out.excerpt)`"" } else { '' }
            [void](Send-ChatqAlert 'done' "$($Job.title) $($script:ChatqDot) $dur$turns$x$reload" 1)
            Write-ChatqWatchLog "#$($Job.seq) done"
        }
        default {
            if ($wasCancelled) { $out.reason = 'cancelled' }
            Complete-ChatqJob $Job 'failed' $out $out.reason
            if (-not $wasCancelled) { [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) $($out.reason)" 2) }
            Write-ChatqWatchLog "#$($Job.seq) failed: $($out.reason)"
        }
    }
    Save-ChatqWatchState $W
    Write-ChatqBoard
}

function Wait-ChatqUntil {
    # wall-clock, in short steps: a machine that slept wakes up past the time
    # and goes straight on; a new job, chatqrun -Now or -Stop cut it short
    param([datetime]$When)
    $wake = if (Test-Path -LiteralPath $script:ChatqWakePath) { (Get-Item -LiteralPath $script:ChatqWakePath).LastWriteTimeUtc } else { $null }
    $end = [Math]::Min(30, [Math]::Max(1, ($When - (Get-Date)).TotalSeconds))
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $end) {
        Start-Sleep -Seconds 2
        if (Test-Path -LiteralPath $script:ChatqStopPath) { return }
        $now = if (Test-Path -LiteralPath $script:ChatqWakePath) { (Get-Item -LiteralPath $script:ChatqWakePath).LastWriteTimeUtc } else { $null }
        if ($now -ne $wake) { return }
    }
}

function Get-ChatqDueTime {
    # when the watcher may next pick this job: the latest of its lane's limit
    # (a minute after the reset), its lane's next overload check, -At/-In, and
    # a busy chat's deferral. $null means now.
    param($W, $Job, [datetime]$Now)
    $lane = Get-ChatqLane $Job
    $times = @()
    $b = $W.blocked[$lane]
    if ($b -and $b.Until -gt $Now) { $times += $b.Until.AddSeconds(60) }
    $o = $W.outage[$lane]
    if ($o -and $o.NextCheck -gt $Now) { $times += $o.NextCheck }
    $nb = ConvertTo-ChatqDate $Job.notBefore
    if ($nb -and $nb -gt $Now) { $times += $nb }
    $du = ConvertTo-ChatqDate $Job.deferUntil
    if ($du -and $du -gt $Now) { $times += $du }
    return ($times | Sort-Object -Descending | Select-Object -First 1)
}

function Invoke-ChatqWatchLoop {
    param([switch]$Foreground)
    Set-StrictMode -Off
    $script:ChatqForeground = [bool]$Foreground
    New-ChatqDir $script:ChatqData
    $lock = try { [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { $null }
    if (-not $lock) {
        if ($Foreground) { Write-Host '  a watcher is already running - chatqrun -Stop first' -ForegroundColor Yellow }
        return
    }
    $W = New-ChatqWatchState
    $W.startedAt = Get-ChatqStamp
    try {
        Set-Content -LiteralPath $script:ChatqPidPath -Value $PID -Encoding ASCII
        if (Test-Path -LiteralPath $script:ChatqStopPath) { Remove-Item -LiteralPath $script:ChatqStopPath -Force }
        Write-ChatqWatchLog "watcher $PID started ($script:ChatqVersion)"
        Repair-ChatqInterrupted
        $wakeSeen = $null
        while ($true) {
            if (Test-Path -LiteralPath $script:ChatqStopPath) {
                Remove-Item -LiteralPath $script:ChatqStopPath -Force -EA SilentlyContinue
                Write-ChatqWatchLog 'stop requested'
                break
            }
            # chatqrun -Now: forget every wait - limits, overloads, busy chats -
            # and ask again
            if (Test-Path -LiteralPath $script:ChatqWakePath) {
                $wk = Get-Item -LiteralPath $script:ChatqWakePath
                if ($wk.LastWriteTimeUtc -ne $wakeSeen) {
                    $wakeSeen = $wk.LastWriteTimeUtc
                    $what = try { (Get-Content -LiteralPath $wk.FullName -Raw).Trim() } catch { '' }
                    # a -Now is a request of the moment: one left lying around
                    # must not cancel the wait of every watcher started later
                    $fresh = ((Get-Date).ToUniversalTime() - $wk.LastWriteTimeUtc).TotalMinutes -lt 5
                    if ($what -eq 'now' -and $fresh) {
                        Send-ChatqWake 'seen'
                        $W.blocked = @{}; $W.lastAllowed = @{}; $W.outage = @{}
                        foreach ($j in @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })) {
                            $W.scannedAt[(Get-ChatqLane $j)] = Get-Date
                            if ($j.deferUntil) { Set-ChatqProp $j 'deferUntil' $null; Save-ChatqJob $j }
                        }
                        Write-ChatqWatchLog 'woken: -Now'
                    }
                }
            }
            $queued = @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })
            if (-not $queued) {
                # Tidy up first and look once more last thing: a job queued
                # while this one is on its way out gets only a poke, and a
                # watcher that has stopped listening would leave it unwatched.
                Set-ChatqKeepAwake $false
                $W.current = $null; $W.next = $null
                Save-ChatqWatchState $W
                Write-ChatqBoard
                if (@(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })) { continue }
                Write-ChatqWatchLog 'queue empty'
                break
            }
            $now = Get-Date
            $pick = $null
            $nextAt = $now.AddMinutes(15)
            foreach ($j in $queued) {
                Update-ChatqBlock $W $j
                $due = Get-ChatqDueTime $W $j $now
                if ($due) { if ($due -lt $nextAt) { $nextAt = $due }; continue }
                $pick = $j
                break
            }
            if ($pick) {
                Set-ChatqKeepAwake $true
                try {
                    if (Confirm-ChatqAllowed $W $pick) { Invoke-ChatqJob $W $pick }
                }
                catch {
                    # one job's failure must not end the watcher - the rest of
                    # the queue is still waiting on it
                    $msg = "$($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])"
                    Write-ChatqWatchLog "#$($pick.seq) error: $msg"
                    $W.current = $null
                    $j = Find-ChatqJob $pick.id
                    if ($j -and $j.state -in 'queued', 'running') {
                        try { Complete-ChatqJob $j 'failed' ([pscustomobject]@{ kind = 'failed'; reason = "chatq error: $($_.Exception.Message)" }) 'chatq error' } catch {}
                        [void](Send-ChatqAlert 'failed' "$($j.title) $($script:ChatqDot) chatq error: $($_.Exception.Message)" 2)
                    }
                }
                Save-ChatqWatchState $W
                Write-ChatqBoard
                continue
            }
            # hold the machine awake only for a wait worth holding it for: a
            # weekly limit days out should not keep a laptop from sleeping
            Set-ChatqKeepAwake (($nextAt - $now).TotalHours -le 6)
            $W.next = $nextAt.ToUniversalTime().ToString('o')
            Save-ChatqWatchState $W
            Write-ChatqBoard
            Wait-ChatqUntil $nextAt
        }
    }
    finally {
        Set-ChatqKeepAwake $false
        try { Remove-Item -LiteralPath $script:ChatqPidPath -Force -EA SilentlyContinue } catch {}
        $W.current = $null; $W.next = $null
        Save-ChatqWatchState $W
        $lock.Dispose()
        Write-ChatqWatchLog "watcher $PID stopped"
    }
}

function Send-ChatqWake {
    param([string]$What = 'poke')
    New-ChatqDir $script:ChatqData
    Set-Content -LiteralPath $script:ChatqWakePath -Value $What -Encoding ASCII
}

function Start-ChatqWatcher {
    # A hidden PowerShell of the same flavour, loading this same file. The
    # environment it needs is written into the command itself: a process
    # started this way does not have to share the calling shell's variables.
    # -Wake is what a running watcher is told: 'poke' (look again) or 'now'
    # (chatqrun -Now: stop waiting) - one write, so neither overwrites the other.
    param([string]$Wake = 'poke')
    if (Test-ChatqWatcherAlive) {
        Send-ChatqWake $Wake
        # it may have been on its way out - checked the queue, found nothing,
        # not yet let go of the lock. Give it a moment, then look again.
        Start-Sleep -Milliseconds 1500
        if (Test-ChatqWatcherAlive) { return $true }
    }
    elseif ($Wake -eq 'now') { Send-ChatqWake 'now' }
    $path = $script:ChatqScriptPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        Write-Host '  cannot start the watcher: this shell does not know where chatq.ps1 is' -ForegroundColor Yellow
        return $false
    }
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $pre = '$env:CHATQ_WATCHER=''1''; '
    foreach ($n in 'CHATQ_CLAUDE', 'CHATQ_CODEX') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $pre += "`$env:$n=$(& $q $v); " }
    }
    $cmd = "$pre. $(& $q $path); Invoke-ChatqWatchLoop"
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    $exe = (Get-Process -Id $PID).Path
    try {
        if ($script:ChatqIsWindows) {
            Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) | Out-Null
        }
        else {
            New-ChatqDir $script:ChatqLogDir
            Start-Process -FilePath 'nohup' -ArgumentList @($exe, '-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) `
                -RedirectStandardOutput (Join-Path $script:ChatqLogDir 'watcher.out') `
                -RedirectStandardError (Join-Path $script:ChatqLogDir 'watcher.err') | Out-Null
        }
    }
    catch {
        Write-Host "  cannot start the watcher: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-ChatqWatcherAlive) { return $true }
    }
    # an empty queue ends it at once, so not seeing it is not always a failure
    return (Test-ChatqWatcherAlive)
}

#endregion

#region commands --------------------------------------------------------------

function New-ChatqSeq {
    $max = 0
    foreach ($j in @(Get-ChatqJobs)) { if ([int]$j.seq -gt $max) { $max = [int]$j.seq } }
    return $max + 1
}

function ConvertFrom-ChatqWhen {
    # -At 13:00 (today, or tomorrow once that has passed) / -In 90m, 2h, 1d
    param([string]$At, [string]$In)
    if ($In) {
        if ($In -match '^\s*(\d+(?:\.\d+)?)\s*(m|min|h|hr|d)?\s*$') {
            $n = [double]$Matches[1]
            switch -Wildcard ($Matches[2]) {
                'd' { return (Get-Date).AddDays($n) }
                'h*' { return (Get-Date).AddHours($n) }
                default { return (Get-Date).AddMinutes($n) }
            }
        }
        throw "-In '$In': use 90m, 2h or 1d"
    }
    if ($At) {
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParse($At, [ref]$d)) { throw "-At '$At': use a time like 13:00" }
        if ($At -notmatch '\d{4}|/' -and $d -lt (Get-Date)) { $d = $d.AddDays(1) }
        return $d
    }
    return $null
}

function Invoke-ChatqEditor {
    # code --wait first: in VS Code's terminal it opens a tab in this window and
    # returns when the tab is closed. $CHATQ_EDITOR overrides the choice.
    param([string]$Path, [switch]$NoWait)
    $spec = if ($env:CHATQ_EDITOR) { $env:CHATQ_EDITOR }
    elseif (Get-Command code -EA SilentlyContinue) { 'code --wait' }
    elseif ($env:VISUAL) { $env:VISUAL }
    elseif ($env:EDITOR) { $env:EDITOR }
    elseif ($script:ChatqIsWindows) { 'notepad' }
    else { 'nano' }
    $parts = @($spec -split '\s+' | Where-Object { $_ })
    $exe = $parts[0]
    $rest = @($parts | Select-Object -Skip 1)
    if ($NoWait) { $rest = @($rest | Where-Object { $_ -notin '--wait', '-w' }) }
    if ($exe -match '^notepad(\.exe)?$') {
        $p = Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$Path`"" -PassThru
        if (-not $NoWait) { $p.WaitForExit() }
        return
    }
    & $exe @rest $Path
}

function Get-ChatqJobInfo {
    # what the run needs to know about the chat: where it ran, in which mode
    param($Row)
    if ($Row.Provider -eq 'codex') {
        $m = Get-ChatqCodexMeta $Row.Path
        $sb = if ($m.Sandbox) { $m.Sandbox } else { 'workspace-write' }
        return @{
            Cwd = $m.Cwd; Mode = $sb; Sandbox = $sb; Network = $m.Network; Model = $m.Model; CutOff = $false
            Error = if (-not $m.Cwd) { "can't tell which folder this Codex chat ran in" } else { $null }
        }
    }
    $m = Get-ChatqClaudeMeta $Row.Path $Row.Group
    return @{
        Cwd = $m.Cwd; Mode = if ($m.Mode) { $m.Mode } else { 'default' }; Model = $m.Model
        CutOff = [bool]($m.LastTurn -and ($m.LastTurn.Limit -or $m.LastTurn.Overloaded)); Sandbox = $null; Network = $false
        Error = if (-not $m.Exists) { 'that chat''s transcript is gone' }
        elseif (-not $m.Cwd) { "can't tell which folder this chat ran in - its recorded folder no longer exists" }
        else { $null }
    }
}

function Write-ChatqJobInfo {
    param($Info, [string]$Mode, [switch]$Continue, [string]$Provider)
    $m = if ($Mode) { $Mode } else { $Info.Mode }
    $src = if ($Mode) { 'given' } else { 'as the chat last ran' }
    Write-Host "     $m ($src) $($script:ChatqDot) $($Info.Cwd)" -ForegroundColor DarkGray
    if ($Provider -eq 'claude') {
        switch ($m) {
            'plan' { Write-Host '     plan mode: it will stop at a plan - -Mode auto lets it act' -ForegroundColor Yellow }
            'bypassPermissions' { Write-Host '     bypassPermissions: it runs everything without asking' -ForegroundColor Yellow }
            { $_ -in 'default', 'manual' } {
                Write-Host '     anything that would ask is denied unattended - -Mode auto or acceptEdits lets it edit' -ForegroundColor DarkGray
            }
        }
    }
    if ($Continue -and -not $Info.CutOff) {
        Write-Host '     this chat was not cut off by the limit or a 529 - "continue" is sent anyway' -ForegroundColor Yellow
    }
    if ($env:ANTHROPIC_API_KEY -and $Provider -eq 'claude') {
        Write-Host '     ANTHROPIC_API_KEY is set here - chatq leaves it out, so runs use your subscription' -ForegroundColor DarkGray
    }
}

function chatq {
    <#
    .SYNOPSIS
    Queue a prompt for an existing chat. It is sent when the usage limit resets.
    .DESCRIPTION
    Picks the chat now, while you are here to see the pick, and hands the job to
    a background watcher that sends it once the limit has reset - into the chat
    itself, in the permission mode that chat last used. Without -Prompt an
    editor tab opens for the prompt; save and close it to queue.

    chatq <n> opens queued prompt n in the editor instead, and chatq alone shows
    the cheat sheet and the queue.
    .PARAMETER Target
    Part or all of a chat title, or a session id. Tab completes titles.
    .PARAMETER Prompt
    The prompt, instead of writing it in the editor.
    .PARAMETER Continue
    Send "Continue from where you left off." - for a chat the limit cut off.
    .PARAMETER Mode
    Run in this permission mode instead of the one the chat last used.
    .PARAMETER At
    Not before this time (13:00 - tomorrow if already past).
    .PARAMETER In
    Not before this long from now (90m, 2h, 1d).
    .PARAMETER WhatIf
    Show which chat would be picked, queue nothing.
    .EXAMPLE
    chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'
    .EXAMPLE
    chatq card redesign -WhatIf
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Target,
        [string]$Prompt,
        [switch]$Continue,
        [ValidateSet('default', 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')][string]$Mode,
        [string]$At,
        [string]$In,
        [ValidateSet('claude', 'codex')][string[]]$Provider,
        [switch]$AllProjects,
        [switch]$WhatIf
    )
    Set-StrictMode -Off
    $t = (@($Target) -join ' ').Trim()
    if (-not $t) { Write-ChatqCheatSheet; Write-ChatqList; return }

    # chatq 3 - open queued prompt 3
    if ($t -match '^#?\d{1,4}$' -and -not $PSBoundParameters.ContainsKey('Prompt') -and -not $Continue) {
        $job = Find-ChatqJob $t
        if ($job) {
            $p = Get-ChatqPromptPath $job
            Write-Host "  #$($job.seq) '$($job.title)' $($script:ChatqDot) $($job.state) $($script:ChatqDot) $p" -ForegroundColor DarkGray
            if ($job.state -ne 'queued') { Write-Host '  already sent - editing it changes nothing now' -ForegroundColor DarkGray }
            elseif ($job.kind -eq 'continue') { Write-Host '  a -Continue job always sends "continue" - the file is only for show' -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $p) { Invoke-ChatqEditor $p -NoWait }
            return
        }
    }
    try { $notBefore = ConvertFrom-ChatqWhen $At $In } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; return }

    $res = Resolve-ChatqTarget $t $Prompt $Provider -AllProjects:$AllProjects
    if ($res.Error) { Write-Host "  $($res.Error)" -ForegroundColor Yellow; return }
    Write-ChatqPick $res
    $info = Get-ChatqJobInfo $res.Row
    if ($info.Error) { Write-Host "     $($info.Error)" -ForegroundColor Yellow; return }
    Write-ChatqJobInfo $info $Mode -Continue:$Continue $res.Row.Provider
    if ($WhatIf) { Write-Host '     -WhatIf: nothing queued' -ForegroundColor DarkGray; return }

    New-ChatqDir $script:ChatqQueueDir
    $seq = New-ChatqSeq
    # no run of dashes survives into the comment, so no title can close it early
    $safeTitle = ([string]$res.Row.Title) -replace '-{2,}', '-'
    $header = "<!-- chatq: prompt for '$safeTitle' ($($res.Row.Provider)). Everything after this comment is sent as it is when the limit resets. Save and close the tab to queue it; leave it empty to cancel. -->`n`n"
    $file = "#$seq $(Get-ChatqSafeName $res.Row.Title).md"
    $path = Join-Path $script:ChatqQueueDir $file
    $kind = if ($Continue) { 'continue' } else { 'prompt' }
    if ($Continue) {
        Save-ChatqText $path ($header + $script:ChatqContinueText)
    }
    elseif ($PSBoundParameters.ContainsKey('Prompt')) {
        if (-not $Prompt.Trim()) { Write-Host '  empty prompt - nothing queued' -ForegroundColor Yellow; return }
        Save-ChatqText $path ($header + $Prompt)
    }
    else {
        Save-ChatqText $path $header
        Write-Host '     write the prompt in the editor tab, then save and close it (empty = cancel)' -ForegroundColor DarkGray
        Invoke-ChatqEditor $path
        $text = Remove-ChatqPromptHeader ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        if (-not $text) {
            Remove-Item -LiteralPath $path -Force -EA SilentlyContinue
            Write-Host '  cancelled - nothing queued' -ForegroundColor DarkGray
            return
        }
        # relevance was scored on the title alone - now the prompt can weigh in
        if ($res.Rule -like '*/relevance') {
            $res2 = Resolve-ChatqTarget $t $text $Provider -AllProjects:$AllProjects
            if (-not $res2.Error -and $res2.Row.Path -ne $res.Row.Path) {
                $info2 = Get-ChatqJobInfo $res2.Row
                if (-not $info2.Error) {
                    Write-ChatqPick $res2 '  re-picked with the prompt ->'
                    Write-ChatqJobInfo $info2 $Mode -Continue:$Continue $res2.Row.Provider
                    $res = $res2; $info = $info2
                    $file = "#$seq $(Get-ChatqSafeName $res.Row.Title).md"
                    $new = Join-Path $script:ChatqQueueDir $file
                    Move-Item -LiteralPath $path -Destination $new -Force
                    $path = $new
                }
            }
        }
    }

    $row = $res.Row
    $job = [pscustomobject][ordered]@{
        v = 1
        id = '{0}-{1}' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $row.Id.Substring(0, [Math]::Min(4, $row.Id.Length))
        seq = $seq
        provider = $row.Provider
        sessionId = $row.Id
        title = $row.Title
        group = $row.Group
        path = $row.Path
        cwd = $info.Cwd
        # only when the user set one: pointing CLAUDE_CONFIG_DIR at the default
        # makes Claude look for .claude.json inside it, where it never lives
        home = if ($row.Provider -eq 'codex') { $env:CODEX_HOME } else { $env:CLAUDE_CONFIG_DIR }
        chatWhen = $row.When
        typed = $t
        rule = $res.Rule
        score = $res.Score
        runnerUp = if ($res.RunnerUp) { $res.RunnerUp.Title } else { $null }
        kind = $kind
        promptFile = $file
        mode = if ($Mode) { $Mode } else { $null }
        modeAtQueue = $info.Mode
        model = $info.Model
        sandbox = $info.Sandbox
        network = $info.Network
        notBefore = if ($notBefore) { $notBefore.ToUniversalTime().ToString('o') } else { $null }
        state = 'queued'
        attempts = 0
        retryAs = 'full'
        # set when the watcher itself turned the job into a "continue" (limit or
        # 529 mid-run); only then is it dropped if the chat moved on meanwhile
        autoContinue = $false
        deferUntil = $null
        deferredSince = $null
        busyAlerted = $false
        createdAt = Get-ChatqStamp
        startedAt = $null
        endedAt = $null
        runnerPid = $null
        result = $null
        history = @([pscustomobject]@{ at = (Get-ChatqStamp); state = 'queued'; why = 'added' })
    }
    Save-ChatqJob $job

    $jobs = @(Get-ChatqJobs)
    # the watcher's own view if it is running - it knows about an overload -
    # else a scan of the transcripts
    $blocks = Get-ChatqBlocks
    $eta = (Get-ChatqEta $jobs $blocks)[$job.id]
    $b = $blocks[(Get-ChatqLane $job)]
    $why = if ($b -and $b.Type -eq 'overloaded') { ' (Claude is overloaded - watching status.claude.com)' }
    elseif ($b -and $b.Until) { " ($($b.Type) limit resets $($b.Until.ToString('HH:mm')))" }
    else { ' (not limited right now)' }
    Write-Host "  queued #$seq  sends $eta$why" -ForegroundColor Green
    if (-not (Start-ChatqWatcher)) {
        Write-Host '  the watcher did not start - chatqrun to try again, chatqrun -Foreground to see why' -ForegroundColor Yellow
    }
    Write-ChatqBoard
}

function chatqlist {
    <#
    .SYNOPSIS
    What is queued, when it sends, and what already ran.
    .PARAMETER Board
    Open the live board (data/queue.md) in VS Code - Ctrl+Shift+V there for the
    preview, which follows every change. Long prompts fold away.
    .PARAMETER All
    Include every finished job, not just the last day's.
    #>
    param([switch]$Board, [switch]$All)
    Set-StrictMode -Off
    if ($Board) {
        Write-ChatqBoard
        Invoke-ChatqEditor $script:ChatqBoardPath -NoWait
        Write-Host '  opened data/queue.md - Ctrl+Shift+V there for the live preview' -ForegroundColor DarkGray
        return
    }
    Write-ChatqList -All:$All
}

function chatqrm {
    <#
    .SYNOPSIS
    Drop queued jobs by number or id. -Force cancels one that is running.
    .PARAMETER Finished
    Drop every job that is done, skipped, failed or needs input.
    #>
    param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Ref, [switch]$Force, [switch]$Finished)
    Set-StrictMode -Off
    $jobs = @(Get-ChatqJobs)
    $targets = if ($Finished) { @($jobs | Where-Object { $_.state -in 'done', 'skipped', 'failed', 'needs-input' }) }
    else { @(foreach ($r in @($Ref)) { $j = Find-ChatqJob $r $jobs; if ($j) { $j } else { Write-Host "  no job $r" -ForegroundColor Yellow } }) }
    if (-not $targets) { if (-not $Ref -and -not $Finished) { Write-Host '  usage: chatqrm <n> [-Force] | chatqrm -Finished' -ForegroundColor DarkGray }; return }
    foreach ($j in $targets) {
        if ($j.state -eq 'running') {
            if (-not $Force) { Write-Host "  #$($j.seq) is running - chatqrm $($j.seq) -Force cancels it" -ForegroundColor Yellow; continue }
            # only a live watcher reads a cancel file; a 'running' job with none
            # is left over from one that died - there is nothing to stop
            if (Test-ChatqWatcherAlive) {
                Save-ChatqText (Join-Path $script:ChatqQueueDir "$($j.id).cancel") 'cancel'
                Write-Host "  #$($j.seq) cancelling - stopped within a few seconds" -ForegroundColor DarkGray
                continue
            }
            Complete-ChatqJob $j 'failed' ([pscustomobject]@{ kind = 'failed'; reason = 'cancelled - its watcher was already gone' }) 'cancelled'
            Write-Host "  #$($j.seq) was left running by a watcher that stopped - marked failed" -ForegroundColor DarkGray
            Write-Host "    chatqrm $($j.seq) removes it, chatqrun $($j.seq) sends it again" -ForegroundColor DarkGray
            continue
        }
        foreach ($p in @((Join-Path $script:ChatqQueueDir "$($j.id).json"), (Get-ChatqPromptPath $j), (Join-Path $script:ChatqLogDir "$($j.id).jsonl"))) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -EA SilentlyContinue }
        }
        Write-Host "  removed #$($j.seq) '$($j.title)'" -ForegroundColor DarkGray
    }
    Write-ChatqBoard
}

function chatqrun {
    <#
    .SYNOPSIS
    Start the watcher, requeue a job, skip the wait, or stop.
    .PARAMETER Ref
    A failed or needs-input job to queue again. One whose prompt already reached
    the chat is sent as "continue" rather than twice.
    .PARAMETER Now
    Stop waiting for the reset: probe now, and send if the limit is over.
    .PARAMETER Foreground
    Run the watcher in this console and watch what it does.
    .PARAMETER Stop
    Stop the watcher. A running job is cut off and marked failed.
    .PARAMETER Mode
    With a job number: requeue it in this permission mode.
    #>
    param(
        [Parameter(Position = 0)][string]$Ref,
        [switch]$Now, [switch]$Foreground, [switch]$Stop,
        [ValidateSet('default', 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')][string]$Mode
    )
    Set-StrictMode -Off
    if ($Stop) {
        if (-not (Test-ChatqWatcherAlive)) { Write-Host '  the watcher is not running' -ForegroundColor DarkGray; return }
        Save-ChatqText $script:ChatqStopPath 'stop'
        Write-Host '  stopping - within a few seconds' -ForegroundColor DarkGray
        return
    }
    if ($Ref) {
        $j = Find-ChatqJob $Ref
        if (-not $j) { Write-Host "  no job $Ref" -ForegroundColor Yellow; return }
        if ($j.state -notin 'failed', 'needs-input', 'done', 'skipped') { Write-Host "  #$($j.seq) is $($j.state) - nothing to requeue" -ForegroundColor DarkGray; return }
        if ($Mode) { Set-ChatqProp $j 'mode' $Mode }
        $landed = $j.state -in 'needs-input', 'done' -or $j.retryAs -eq 'continue' -or
        (Test-ChatqPromptLanded $j.path ([string](Read-ChatqPrompt $j)) $j.startedAt $j.provider)
        Set-ChatqProp $j 'retryAs' $(if ($landed) { 'continue' } else { 'full' })
        # asked for by you: sent even if the chat has moved on since
        Set-ChatqProp $j 'autoContinue' $false
        Set-ChatqProp $j 'deferUntil' $null
        Set-ChatqProp $j 'deferredSince' $null
        Set-ChatqJobState $j 'queued' 'requeued'
        $how = if ($landed) { 'as "continue" - the prompt already reached the chat' } else { 'with its prompt' }
        Write-Host "  #$($j.seq) queued again, $how" -ForegroundColor Green
    }
    if ($Foreground) {
        if ($Now) { Send-ChatqWake 'now' }
        Invoke-ChatqWatchLoop -Foreground
        return
    }
    # -Now travels as the watcher's one wake-up write: sent separately, the
    # poke that follows would overwrite it before the watcher read it
    $wake = if ($Now) { 'now' } else { 'poke' }
    if (@(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' })) {
        if (-not (Start-ChatqWatcher -Wake $wake)) { Write-Host '  the watcher did not start - chatqrun -Foreground to see why' -ForegroundColor Yellow }
    }
    Write-ChatqList
}

function chatqlog {
    <#
    .SYNOPSIS
    What a run did: the reply, the tools it used, how it ended. -Raw for the stream.
    #>
    param([Parameter(Position = 0)][string]$Ref, [switch]$Raw)
    Set-StrictMode -Off
    $j = if ($Ref) { Find-ChatqJob $Ref } else { @(Get-ChatqJobs | Where-Object { $_.startedAt } | Sort-Object startedAt)[-1] }
    if (-not $j) { Write-Host '  no such job' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host "  #$($j.seq) '$($j.title)' $($script:ChatqDot) $($j.state)" -ForegroundColor Cyan
    foreach ($h in @($j.history)) {
        $at = ConvertTo-ChatqDate $h.at
        Write-Host ("    {0}  {1,-11} {2}" -f $at.ToString('MM-dd HH:mm'), $h.state, $h.why) -ForegroundColor DarkGray
    }
    $log = Join-Path $script:ChatqLogDir "$($j.id).jsonl"
    if (-not (Test-Path -LiteralPath $log)) { Write-Host '  no run yet'; Write-Host ''; return }
    if ($Raw) { Get-Content -LiteralPath $log -Encoding UTF8; return }
    Write-Host ''
    foreach ($line in [System.IO.File]::ReadLines($log, [System.Text.Encoding]::UTF8)) {
        if ($line.Length -gt 1048576) { continue }
        if ($line.StartsWith('{"type":"user"')) { continue }
        $o = try { $line | ConvertFrom-Json } catch { continue }
        switch ($o.type) {
            'system' {
                if ($o.subtype -eq 'init') { Write-Host "  session $($o.session_id) $($script:ChatqDot) $($o.model) $($script:ChatqDot) $($o.permissionMode) $($script:ChatqDot) Claude Code $($o.claude_code_version)" -ForegroundColor DarkGray }
                elseif ($o.subtype -eq 'permission_denied') { Write-Host "  ! denied $($o.tool_name)" -ForegroundColor Yellow }
            }
            'assistant' {
                foreach ($c in @($o.message.content)) {
                    if ($c.type -eq 'text' -and $c.text) { Write-Host ''; Write-Host $c.text }
                    elseif ($c.type -eq 'tool_use') {
                        $arg = if ($c.input.command) { $c.input.command } elseif ($c.input.file_path) { $c.input.file_path } elseif ($c.input.pattern) { $c.input.pattern } else { '' }
                        $arg = ([string]$arg -split "`n")[0]
                        Write-Host "  > $($c.name) $arg" -ForegroundColor DarkGray
                    }
                }
            }
            'result' {
                $d = if ($o.duration_ms) { [TimeSpan]::FromMilliseconds($o.duration_ms).ToString('hh\:mm\:ss') } else { '' }
                Write-Host ''
                Write-Host "  = $($o.subtype) $($script:ChatqDot) $($o.num_turns) turns $($script:ChatqDot) $d" -ForegroundColor DarkGray
            }
            'item.completed' {
                if ($o.item.type -eq 'agent_message') { Write-Host ''; Write-Host $o.item.text }
                elseif ($o.item.type -eq 'command_execution') { Write-Host "  > $($o.item.command)" -ForegroundColor DarkGray }
            }
            'turn.failed' { Write-Host "  ! $($o.error.message)" -ForegroundColor Yellow }
            'error' { Write-Host "  ! $($o.message)" -ForegroundColor Yellow }
        }
    }
    Write-Host ''
}

function chatqnotify {
    <#
    .SYNOPSIS
    Phone alerts through Join (joaomgcd): started, needs input, done, failed.
    .DESCRIPTION
    Get the API key and device id from https://joinjoaomgcd.appspot.com (the
    "Join API" button). -Device takes a device id, a group (group.phone,
    group.android, group.all) or a device name. The key is DPAPI-protected on
    Windows. Alerts always go to data/logs/alerts.log as well.

    Tasker: every title starts "chatq ", so a profile on the Join plugin's
    event can filter them, or match only "needs input" and "failed".
    .EXAMPLE
    chatqnotify -ApiKey 0123abcd... -Device group.phone
    .EXAMPLE
    chatqnotify -Test
    #>
    param([string]$ApiKey, [string]$Device, [switch]$Test, [switch]$Off)
    Set-StrictMode -Off
    $cfg = Get-ChatqConfig
    if ($Off) {
        if ($cfg.PSObject.Properties['join']) { $cfg.PSObject.Properties.Remove('join') }
        Save-ChatqJson $script:ChatqConfigPath $cfg
        Write-Host '  phone alerts off - they still go to data/logs/alerts.log' -ForegroundColor DarkGray
        return
    }
    if ($ApiKey -or $Device) {
        $j = if ($cfg.join) { $cfg.join } else { [pscustomobject]@{} }
        if ($ApiKey) { Set-ChatqProp $j 'apiKey' ([pscustomobject](Protect-ChatqSecret $ApiKey.Trim())) }
        if ($Device) { Set-ChatqProp $j 'device' $Device.Trim() }
        if (-not $j.device) { Set-ChatqProp $j 'device' 'group.phone' }
        Set-ChatqProp $cfg 'join' $j
        Save-ChatqJson $script:ChatqConfigPath $cfg
        if (-not $script:ChatqIsWindows) { try { & chmod 600 $script:ChatqConfigPath } catch {} }
        Write-Host "  saved $($script:ChatqDot) device $($j.device)$(if ($j.apiKey.protected) { " $($script:ChatqDot) key protected with DPAPI" })" -ForegroundColor Green
    }
    if ($Test -or $ApiKey) {
        if (Send-ChatqAlert 'test' "chatq reaches this device $($script:ChatqDot) $([Environment]::MachineName)" 1) {
            Write-Host '  sent - check your phone' -ForegroundColor Green
        }
        else {
            Write-Host "  not sent: $(if ($script:ChatqLastAlertError) { $script:ChatqLastAlertError } else { 'no Join key and device set' })" -ForegroundColor Yellow
        }
        return
    }
    if (-not $ApiKey -and -not $Device) {
        if ($cfg.join -and $cfg.join.apiKey) { Write-Host "  Join on $($script:ChatqDot) device $($cfg.join.device) $($script:ChatqDot) chatqnotify -Test sends one" -ForegroundColor DarkGray }
        else {
            Write-Host '  no phone alerts yet - they only go to data/logs/alerts.log' -ForegroundColor DarkGray
            Write-Host '  key and device id: https://joinjoaomgcd.appspot.com  (Join API button), then' -ForegroundColor DarkGray
            Write-Host '      chatqnotify -ApiKey <key> -Device <device id | group.phone>' -ForegroundColor Cyan
        }
    }
}

function Write-ChatqCheatSheet {
    Write-Host ''
    Write-Host '  chatq <title> [-Prompt s]   queue a prompt for that chat (no -Prompt: editor)' -ForegroundColor Cyan
    Write-Host '  chatq <title> -Continue     queue "continue" for a chat the limit cut off' -ForegroundColor Cyan
    Write-Host '  chatq <n>                   open queued prompt n' -ForegroundColor Cyan
    Write-Host '  chatqlist [-Board]          the queue; -Board = live board in VS Code' -ForegroundColor Cyan
    Write-Host '  chatqrm <n> [-Force]        drop a job; -Force cancels a running one' -ForegroundColor Cyan
    Write-Host '  chatqrun [<n>] [-Now]       requeue n / stop waiting and try now' -ForegroundColor Cyan
    Write-Host '  chatqlog <n>                what a run did' -ForegroundColor Cyan
    Write-Host '  chatqnotify                 phone alerts through Join' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  -WhatIf shows the pick only   -Mode auto|acceptEdits|...   -At 13:00 / -In 2h' -ForegroundColor DarkGray
    Write-Host '  Tab completes titles; for several words open a quote first:  chatq ''card red<Tab>' -ForegroundColor DarkGray
    Write-Host "  chatq $script:ChatqVersion $($script:ChatqDot) $script:ChatqScriptPath" -ForegroundColor DarkGray
}

#endregion

#region install ---------------------------------------------------------------

function Compare-ChatqVersion {
    # -1 A older, 0 same, 1 A newer, $null if either side will not parse
    param([string]$A, [string]$B)
    $pa = $null
    $pb = $null
    if (-not [version]::TryParse($A, [ref]$pa)) { return $null }
    if (-not [version]::TryParse($B, [ref]$pb)) { return $null }
    return $pa.CompareTo($pb)
}

function chatqinstall {
    <#
    .SYNOPSIS
    Add chatq to your PowerShell profile, so its commands - and the watcher, if
    jobs are waiting - come back in every new shell.
    #>
    [CmdletBinding()]
    param([switch]$Force)
    Set-StrictMode -Off
    $me = $script:ChatqScriptPath
    if (-not $me) {
        Write-Host '  cannot tell where this file is' -ForegroundColor Yellow
        Write-Host '  dot-source it by path first:  . C:\path\to\chatq.ps1' -ForegroundColor DarkGray
        return
    }
    if (Get-Command Unblock-File -EA SilentlyContinue) { Unblock-File -LiteralPath $me -EA SilentlyContinue }
    $was = $null
    if (Test-Path -LiteralPath $script:ChatqVersionPath) {
        $was = Get-Content -LiteralPath $script:ChatqVersionPath -TotalCount 1 -EA SilentlyContinue
        if ($was) { $was = $was.Trim() }
    }
    $dir = Split-Path $PROFILE -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = if (Test-Path -LiteralPath $PROFILE) { @(Get-Content -LiteralPath $PROFILE) } else { @() }
    $mine = @($lines | Where-Object { $_ -match 'chatq\.ps1' })
    $here = @($mine | Where-Object { $_.IndexOf($me, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($here -and -not $Force) {
        Write-Host '  already installed' -ForegroundColor DarkGray
        Write-Host "    $PROFILE" -ForegroundColor DarkGray
    }
    else {
        if (Test-Path -LiteralPath $PROFILE) { Copy-Item -LiteralPath $PROFILE -Destination "$PROFILE.bak" -Force }
        $kept = @($lines | Where-Object { $_ -notmatch 'chatq\.ps1' })
        $kept += ". `"$me`""
        Set-Content -LiteralPath $PROFILE -Value $kept -Encoding UTF8
        Write-Host '  installed' -ForegroundColor Green
        Write-Host "    $PROFILE"
        $stale = $mine.Count - $here.Count
        if ($stale -gt 0) { Write-Host "    replaced $stale line$(if ($stale -ne 1) { 's' }) from an older location" -ForegroundColor DarkGray }
        Write-Host '    ready in this shell - type chatq' -ForegroundColor Green
    }
    if (-not $was) { Write-Host "    version $script:ChatqVersion" -ForegroundColor DarkGray }
    elseif ($was -eq $script:ChatqVersion) { Write-Host "    version $script:ChatqVersion - unchanged" -ForegroundColor DarkGray }
    elseif ((Compare-ChatqVersion $was $script:ChatqVersion) -eq 1) { Write-Host "    DOWNGRADED $was -> $script:ChatqVersion" -ForegroundColor Yellow }
    else { Write-Host "    updated $was -> $script:ChatqVersion" -ForegroundColor Green }
    if (-not (Test-Path -LiteralPath $script:ChatqIndexPath)) {
        Write-Host '    building the index for Tab completion (~30s)...' -ForegroundColor DarkGray
        try {
            $n = @(Sync-ChatqIndex).Count
            Write-Host "    indexed $n chat$(if ($n -ne 1) { 's' })" -ForegroundColor DarkGray
        }
        catch { Write-Host '    could not build it - any chatq run builds it' -ForegroundColor Yellow }
    }
    if (-not (Find-ChatqExe claude) -and -not (Find-ChatqExe codex)) {
        Write-Host '    no claude or codex CLI found - install one, or set CHATQ_CLAUDE / CHATQ_CODEX' -ForegroundColor Yellow
    }
    try {
        New-ChatqDir $script:ChatqData
        Set-Content -LiteralPath $script:ChatqVersionPath -Value $script:ChatqVersion -Encoding UTF8
    }
    catch {}
}

function chatquninstall {
    <#
    .SYNOPSIS
    Take chatq back out of your profile; -All deletes its folder too, data/ and
    every queued prompt with it.
    #>
    [CmdletBinding()]
    param([switch]$All)
    Set-StrictMode -Off
    $pending = @(Get-ChatqJobs | Where-Object { $_.state -in 'queued', 'running' })
    if ($pending) { Write-Host "  $($pending.Count) job$(if ($pending.Count -ne 1) { 's' }) still queued - they will not be sent" -ForegroundColor Yellow }
    if (Test-ChatqWatcherAlive) {
        Save-ChatqText $script:ChatqStopPath 'stop'
        for ($i = 0; $i -lt 40 -and (Test-ChatqWatcherAlive); $i++) { Start-Sleep -Milliseconds 250 }
        Write-Host '  stopped the watcher' -ForegroundColor DarkGray
    }
    $lines = if (Test-Path -LiteralPath $PROFILE) { @(Get-Content -LiteralPath $PROFILE) } else { @() }
    $mine = @($lines | Where-Object { $_ -match 'chatq\.ps1' })
    if ($mine.Count) {
        Copy-Item -LiteralPath $PROFILE -Destination "$PROFILE.bak" -Force
        Set-Content -LiteralPath $PROFILE -Encoding UTF8 -Value @($lines | Where-Object { $_ -notmatch 'chatq\.ps1' })
        Write-Host "  removed $($mine.Count) line$(if ($mine.Count -ne 1) { 's' }) from the profile" -ForegroundColor Green
        Write-Host "    backup: $PROFILE.bak" -ForegroundColor DarkGray
    }
    else { Write-Host '  nothing in the profile to remove' -ForegroundColor DarkGray }
    $here = if ($script:ChatqScriptPath) { Split-Path $script:ChatqScriptPath -Parent } else { $null }
    if ($All -and $here) {
        Remove-Item -LiteralPath $here -Recurse -Force -EA SilentlyContinue
        $gone = -not (Test-Path -LiteralPath $here)
        Write-Host "  $(if ($gone) { 'deleted' } else { 'COULD NOT DELETE' })  $here" -ForegroundColor $(if ($gone) { 'Green' } else { 'Yellow' })
    }
    elseif ($here) {
        Write-Host '  the folder is still there - delete it when you want to:' -ForegroundColor DarkGray
        Write-Host "      Remove-Item -LiteralPath `"$here`" -Recurse -Force" -ForegroundColor Cyan
    }
    Write-Host '  these commands stay in this shell until you close it' -ForegroundColor DarkGray
}

#endregion

#region tab completion --------------------------------------------------------

$script:ChatqTitleCompleter = {
    # One quoted title replaces the word being typed. Scoped to this project
    # the way the resolver scopes its first pass, so Tab offers what chatq picks.
    param($cmd, $param, $word)
    Set-StrictMode -Off
    $w = ([string]$word).Trim('"', "'")
    $rows = @(Select-ChatqInProject @(Get-ChatqIndex | Where-Object { $_.Title -ne '(empty)' -and -not $_.Hidden }))
    if (-not $rows) {
        return [System.Management.Automation.CompletionResult]::new(
            $word, 'no index yet - run chatq once', 'ParameterValue', 'No index yet - any chatq search builds it (~30s)')
    }
    if ($w -match '^\d{1,4}$') { return }   # a job number - nothing to complete
    $hits = @($rows | Where-Object { -not $w -or $_.Title.StartsWith($w, [StringComparison]::OrdinalIgnoreCase) })
    if (-not $hits -and $w) { $hits = @($rows | Where-Object { $_.Title.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
    $hits | Group-Object Title | ForEach-Object { ($_.Group | Sort-Object When -Descending)[0] } |
        Sort-Object When -Descending | Select-Object -First 25 | ForEach-Object {
            $when = ConvertTo-ChatqDate $_.When
            $age = if ($when) { Get-ChatqAge $when } else { '?' }
            $first = @($_.First)[0]
            $label = (Format-ChatqCell $_.Title 44) + ' ' + (Format-ChatqCell "[$($_.Provider) $age]" 15)
            if ($first) { $label += ' > ' + (Format-ChatqCell ($first -replace '\s+', ' ') 40 -NoPad) }
            $tip = "$($_.Title)`n$($_.Provider) / $($_.Group) / $age"
            if ($first) { $tip += "`n  > $first" }
            # every single-quote PowerShell knows is doubled - typographic ones too
            $esc = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_.Title)
            [System.Management.Automation.CompletionResult]::new("'" + $esc + "'", $label, 'ParameterValue', $tip)
        }
}
Register-ArgumentCompleter -CommandName chatq -ParameterName Target -ScriptBlock $script:ChatqTitleCompleter

$script:ChatqJobCompleter = {
    param($cmd, $param, $word)
    Set-StrictMode -Off
    @(Get-ChatqJobs) | Where-Object { "$($_.seq)" -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new("$($_.seq)", "#$($_.seq) $($_.title) [$($_.state)]", 'ParameterValue', "$($_.title)`n$($_.state)")
    }
}
Register-ArgumentCompleter -CommandName chatqrm, chatqrun, chatqlog -ParameterName Ref -ScriptBlock $script:ChatqJobCompleter

#endregion

# Run instead of dot-sourced - & file.ps1, powershell -File, a double-click -
# leaves a shell with no chatq command and nothing said about why.
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host ''
    Write-Host '  nothing was loaded - this file has to be dot-sourced' -ForegroundColor Yellow
    $shown = if ($PSCommandPath) { $PSCommandPath } else { 'C:\path\to\chatq.ps1' }
    Write-Host "      . `"$shown`"" -ForegroundColor Cyan
    Write-Host '  then chatqinstall, to have every new shell do it for you' -ForegroundColor DarkGray
    Write-Host ''
}
elseif (-not $env:CHATQ_WATCHER -and -not $env:CLAUDECODE -and [Environment]::UserInteractive -and
    $Host.Name -in 'ConsoleHost', 'Visual Studio Code Host') {
    # A shell opening after a reboot picks the watcher back up. Cheap when the
    # queue is empty: one directory listing. In a child scope, so turning
    # StrictMode off here leaves the user's own setting alone.
    & {
        Set-StrictMode -Off
        try {
            if ((Test-Path -LiteralPath $script:ChatqQueueDir) -and -not (Test-ChatqWatcherAlive)) {
                $n = @(Get-ChatqJobs | Where-Object { $_.state -eq 'queued' }).Count
                if ($n -and (Start-ChatqWatcher)) { Write-Host "  chatq: $n queued - watcher started" -ForegroundColor DarkGray }
            }
        }
        catch {}
    }
}
