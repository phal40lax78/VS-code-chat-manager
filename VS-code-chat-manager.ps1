<#
VS-code-chat-manager - find, delete and queue prompts for local AI chats.

Two tools in one file, sharing one index and one way of picking a chat:
  chatrm  - find and delete chat transcripts. Claude Code, Copilot Chat and
            Codex keep every chat on disk and none offers a per-chat delete
            (claude project purge is per-project; archiving only hides).
  chatq   - hold prompts while the usage limit is hit and deliver them when it
            resets. The VS Code panel queues a message sent while Claude is
            working, but one sent while the subscription limit is exhausted is
            refused and dropped. Aim a prompt at any existing chat by title;
            at the reset each chat is resumed in turn, sent its prompt, run to
            the end, and your phone is told how it went.

INSTALL   one line
    iex (irm https://raw.githubusercontent.com/phal40lax78/VS-code-chat-manager/main/install.ps1)
  or two, with the file already on disk - and the path need not be typed
    . "$HOME\Tools\VS-code-chat-manager\VS-code-chat-manager.ps1"
    chatinstall

  To get that first line right without typing a path at all: type a dot and a
  space, then drag the .ps1 out of Explorer and drop it on the window - or
  shift+right-click it there, "Copy as path", and paste. Enter, then chatinstall.

  Point it at the .ps1 itself, never the folder holding it. A folder gives "The
  term '...' is not recognized", because a folder is not a command - the filename
  is the part that gets left off. Quotes only start to matter once the path has a
  space in it, and "Copy as path" supplies them either way.

  The leading dot matters as much as the path does. `. file.ps1` loads the
  commands into the shell you are standing in; `& file.ps1`, or double-clicking
  the file, runs it and throws every command away again as it exits. It notices
  that itself and prints the line you meant to type, so a shell is never left
  silently empty - though a double-clicked window closes too fast to read it.

  Open a new terminal and type chat.

  chatinstall writes the profile line itself - the script knows where it is, so
  the path is only ever typed once. It calls Unblock-File for you on Windows,
  makes the profile if there is none, and backs it up to $PROFILE.bak first.
  Run it again after moving the file: it replaces the old line instead of leaving
  one that loads nothing and says nothing about it. -Force rewrites regardless.
  If even that first line will not run, the execution policy is Restricted -
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned, once, Windows only.

  One file, no modules, no dependencies. It runs from anywhere - only data/ sits
  beside it - but a folder of its own that no other tool owns is the one to pick,
  hence ~/Tools/VS-code-chat-manager above. Not .claude, .codex or .vscode: those
  belong to the tools named after them, which rewrite them on update and clear
  them on reinstall, and would take the index with them. Not a folder shared with
  other scripts either, where a second data/ would land on top of this one.
  Moving it later is fine - move data/ with it and re-run chatinstall, which
  repoints the profile line rather than leaving a dead one. $PROFILE is per host:
  Documents\WindowsPowerShell for 5.1, Documents\PowerShell for pwsh, and a
  redirected Documents folder moves both - so install once in each shell you use.
  Do not copy data/chat-index.csv - it holds absolute paths from the old machine
  and rebuilds itself on the first search (~30s).

COMMANDS
    chatfind "text" [-Deep] [-All] [-AllProjects] [-Provider codex,copilot]
    chatrm <id|prefix> [...]       unambiguous - deletes outright
    chatrm "<title>" [-Force]      walk the matches, confirm; -Force takes all
    chatrm ... -DropJobs           also drop prompts queued for that chat
    chatclean                      ghost chats (no messages, < 64 KB)
    chatproviders / chatindex      what was found / rebuild the index
    chatq <title|id> [-Prompt s]   queue a prompt for that chat; no -Prompt
                                   opens an editor tab to write it in
    chatq <title> -Continue        queue "continue" for a chat the limit cut off
    chatq <n>                      open queued prompt n in the editor
    chatqlist [-Board] [-All]      what is queued, when it sends, what ran
    chatqrm <n|id> [-Force]        drop a job (-Force cancels a running one)
    chatqrun [<n>] [-Now] [-Stop]  requeue n / skip the wait / stop the watcher
    chatqlog <n> [-Raw]            what a run did
    chatqnotify -ApiKey k -Device d  phone alerts through Join; -Test sends one
    chatinstall / chatuninstall    add to, or drop from, your profile
    chat                           cheat sheet

  chatfind emits objects:  chatfind commit | Select Provider,Title,Id,Age

SCOPE
  Titles match chats belonging to the directory you are standing in - Claude by
  its project slug, Copilot and Codex by the folder name - so a sibling repo
  never answers for this one. Those slugs nest (...-src-app is a prefix of
  ...-src-app-Mobile), so the test is exact rather than a prefix, and
  case-insensitive because the drive letter's case varies. Tab is scoped the
  same way, or it would offer chats chatrm then refused to match.
  -AllProjects widens it. Ids skip it - one id is one chat, wherever it lives.
  Standing somewhere that is no project at all narrows nothing.

TAB
    chatrm gitign<Tab>     chatrm 'Gitignore file' (21d) #1/2
    (down)                 chatrm 'Gitignore rules' (5d) #2/2
    chatrm "gitign<Tab>    chatrm 'Gitignore file' (21d) #1/2

  Tab fills in the argument - the whole of it, not the word under the cursor.
  Everything typed after the command is replaced by one quoted title, so
  quoting it yourself changes nothing: a leading " or ' is dropped before
  matching and the title always comes back in single quotes. No quote is left
  to close, and no half-typed word to finish by hand.
  Tab/down next, Shift+Tab/up previous, Enter runs it, Ctrl+Space the full
  list. Prefix match on the whole argument, spaces and all; widens to contains
  when nothing starts with it; hex matches ids. Arrows stay history unless a
  run is live, and editing the line ends the run.
  Opt out: $ChatNoKeyBindings = $true before the dot-source.

  Enter strips "(21d) #1/2" before running - and strips it on any chatrm or
  chatfind line, not only a live run, because it survives an edit. "#1/2" alone
  was a comment and safe to leave; "(21d)" is not, PowerShell would run it.

  The buffer is rewritten because nothing else can be drawn from a key handler:
  PSReadLine's reader already owns the keyboard, so a pane of our own never
  gets a keystroke.

PICKING
  One line everywhere - Tab, one match, several matches all look the same, in
  the same colours (read from PSReadLine, so it follows your theme):
    chatrm 'UI zoom in/out function' (9d) #1/2
    chatrm 'Zoom in/out functions' (3d) #2/2
  Enter deletes what is on screen, at once: no detail dump, no confirmation.
  Esc backs out. Two chats can share a title AND an age - only then does the
  line add the project and size, since nothing else would separate them.

  That is for a title you typed in full. Titles match on substring, so one hit
  is not the same as the right hit - chatrm Haiku matched 'Haiku ChatGPT Opus
  Astra'. Typing part of a title is a search, and a search must not delete, so:
  Enter fills the match in the way Tab would rather than running, and pressing
  it again deletes the title now on screen. Where no key handler can reach -
  a script, -NoProfile, no VT - the same case asks
    delete permanently?  y / Enter = yes,  n / Esc = no
  -Force skips all of it, and an id never goes near this: an id is exact.
  chatclean uses a checkbox list (space toggle, a all) so ghosts go in one pass.
  Redraws use escape sequences: under VS Code's pseudo-console CursorPosition
  is accepted and ignored. No VT -> numbered list and a typed y/N.

GHOSTS
  A chat still listed in the panel is one the window is tracking, and it
  flushes session state to disk when it reloads or closes. That recreates a
  chat deleted minutes earlier as a stub - ai-title, mode, atis-latch, no
  messages, and a brand new creation time, so it is a fresh write and not a
  failed delete. Archived chats are filtered out of that list, never tracked,
  and stay deleted first time.
  That write happens once. After the reload the window rebuilds its list from
  disk and is no longer holding the session, which is why deleting a second
  time always worked. So it is watched for rather than waited out: a
  FileSystemWatcher on newly created .jsonl files takes the rewrite back the
  moment it lands, with no second command to run. The deletion is written down
  too - data/rewritten.txt - as the backstop for shells that were not open at
  the time, swept by the next chat command.
  Either path only removes a file that is still a stub, so resuming that
  session for real ends it. Tombstones expire after 7 days.
  Deleting can also simply fail - Windows will not remove a file another
  process holds open. That prints LOCKED and is not counted as deleted.

SPEED
  Search and completion run off data/chat-index.csv next to this script; a file
  is re-read only on size/mtime change. ~30s first build, ~1.5s after.
  chatindex -Force rebuilds.

PROVIDERS   one entry each in $script:ChatProviders - Discover/Describe/Extras
    claude   <config>/projects/<slug>/<uuid>.jsonl. Title: custom-title /
             ai-title line, else sidecar custom-title.json, else first prompt.
             Extras: sidecar dir, file-history/<id>, session-env/<id>.
    copilot  <Code user>/workspaceStorage/<hash>/chatSessions/<uuid>.json, where
             <Code user> is %APPDATA%/Code/User on Windows, ~/Library/Application
             Support/Code/User on macOS and ~/.config/Code/User on Linux.
             customTitle, requests[].message.text. Extras: chatEditingSessions/<id>.
    codex    ~/.codex/sessions/YYYY/MM/DD/rollout-<iso>-<uuid>.jsonl. Title:
             thread_name in ~/.codex/session_index.jsonl, which is the name the
             panel lists; else first real prompt, IDE and AGENTS.md preambles
             filtered.
  CLAUDE_CONFIG_DIR and CODEX_HOME are honoured.

NOTES
  Transcripts are opened FileShare.ReadWrite+Delete. Codex holds every rollout
  open for the life of the window, so a plain read throws on all of them and no
  Codex chat is seen at all. Deleting one a live window still holds fails, and
  is reported LOCKED - close the window.
  Permanent, no recycle bin. Age = last real message; Touched = mtime, which is
  what the GUIs show (titles and resumes bump it). Lists are cached until
  Developer: Reload Window. hiddenSessionIds (the archive) is never touched.
  Windows PowerShell 5.1 or pwsh 7; macOS and Linux need pwsh 7. Only Windows
  holds a file against deletion, so LOCKED is a Windows-only guard - elsewhere
  unlinking a transcript a live window still has open simply succeeds, and that
  window goes on writing to a file no longer on disk.

QUEUE: PICKING THE CHAT   decided when you queue, so you see it while here
  An id is that chat. Otherwise the title is matched in this project first -
  exact, then contains, then every word you typed - and in every project only
  when this one has no match. Nothing matched at all: the candidates are every
  chat in this project. Of several candidates the newest wins - unless others
  were active within 5 hours of it (one limit window), and then the most
  relevant one does: character-bigram cosine of what you typed and the prompt
  against each chat's title and prompts. Pure PowerShell, no model call, the
  same answer every time, Hangul and English alike. A Copilot chat is found
  but refused: no CLI can resume one headless.

QUEUE: WHEN IT RUNS
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
    chat-index.csv                         what search and Tab run off
    rewritten.txt                          tombstones for the ghost watch
    reload-request                         read by the extension in extension/
    queue/<id>.json + "#<n> <title>.md"   one job, its prompt (edit it freely)
    logs/<id>.jsonl                        the raw run
    queue.md                               live board - open it, Ctrl+Shift+V
    config.json                            Join key, DPAPI-protected on Windows
#>

# Bump this in the same commit that changes behaviour - chatinstall compares it
# against data/version.txt to say whether a reinstall actually landed anything,
# and raw.githubusercontent.com serves a stale copy for minutes after a push, so
# "updated" vs "unchanged" is the only way to tell a real upgrade from the CDN
# handing back what you already had.
$script:ChatVersion = '0.2.0'

$script:ChatPreview = 3
$script:ChatClaudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$script:ChatCodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
# $IsMacOS exists only on pwsh 6+. On 5.1 it is undefined, and under StrictMode
# reading an undefined variable throws outright rather than yielding $false -
# this file is dot-sourced into whatever session the user already has, so it
# cannot assume strict mode is off. Get-Variable answers without touching it.
$script:ChatIsMac = [bool](Get-Variable -Name IsMacOS -ValueOnly -EA SilentlyContinue)

# VS Code's user dir moves per platform: APPDATA on Windows, Application Support
# on macOS, XDG on Linux. Without the middle branch a Mac falls to the Linux path
# and the copilot provider quietly finds nothing at all. CHAT_CODE_USER points
# it somewhere else - the tests and the demo use it so no real chat is read.
$script:ChatCodeUser =
if ($env:CHAT_CODE_USER) { $env:CHAT_CODE_USER }
elseif ($env:APPDATA) { Join-Path $env:APPDATA 'Code\User' }
elseif ($script:ChatIsMac) { Join-Path $HOME 'Library/Application Support/Code/User' }
else { Join-Path $HOME '.config/Code/User' }
$script:ChatWorkspaceNames = @{}
$script:ChatIndexPath = Join-Path (Join-Path $PSScriptRoot 'data') 'chat-index.csv'
$script:ChatTombPath = Join-Path (Join-Path $PSScriptRoot 'data') 'rewritten.txt'
# what the last chatinstall put in the profile. The file gets overwritten by an
# update, so its own version says what just landed and this says what it replaced.
$script:ChatVersionPath = Join-Path (Join-Path $PSScriptRoot 'data') 'version.txt'
# read by the optional VS Code extension in extension/, which is the only thing
# able to run reloadWindow - no CLI flag, URL or toast button can reach it
$script:ChatReloadPath = Join-Path (Join-Path $PSScriptRoot 'data') 'reload-request'

# Caches and flags read before anything sets them. This file is dot-sourced
# into whatever session the user already has, and under Set-StrictMode
# -Version Latest reading an unset variable throws - at load, or inside a key
# handler, which then leaves the key dead. Every command also turns StrictMode
# off for itself; these cover everything that runs outside one.
$script:ChatIndexStamp = $null
$script:ChatIndexCache = @()
$script:ChatCodexNames = $null
$script:ChatCodexNamesAt = 0
$script:ChatColors = $null
$script:ChatGhostWatcher = $null
$script:ChatNoIndex = $false
$script:ChatArrowWas = @{}
# set by the tests: a FileSystemWatcher event firing between their statements
# would delete fixtures out from under them
$script:ChatNoGhostWatch = $false

#region index -----------------------------------------------------------------
# Reading 2000+ transcripts takes ~30s, so nothing does it twice. The index
# holds everything a search needs - title, group, previews, last activity - and
# a file is only re-read when its size or mtime changed. Searches and tab
# completion both run off it.

$script:ChatIndexSep = [char]0x1F   # unit separator: never appears in prompt text

function Get-ChatIndex {
    # CSV, not JSON: ConvertTo-Json on a few thousand rows costs tens of seconds.
    # Kept in memory too, so repeated Tab presses re-parse nothing.
    if (-not (Test-Path -LiteralPath $script:ChatIndexPath)) { return @() }
    $stamp = try {
        $fi = [System.IO.FileInfo]::new($script:ChatIndexPath)
        "$($fi.LastWriteTimeUtc.Ticks):$($fi.Length)"
    }
    catch { $null }
    if ($stamp -and $stamp -eq $script:ChatIndexStamp) { return $script:ChatIndexCache }
    try {
        $rows = @(Import-Csv -LiteralPath $script:ChatIndexPath | ForEach-Object {
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
                    First    = @($_.First -split $script:ChatIndexSep | Where-Object { $_ })
                    Last     = @($_.Last -split $script:ChatIndexSep | Where-Object { $_ })
                }
            })
        $script:ChatIndexCache = $rows
        $script:ChatIndexStamp = $stamp
        return $rows
    }
    catch { return @() }
}

function Save-ChatIndex {
    param([object[]]$Rows)
    try {
        $dir = Split-Path $script:ChatIndexPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Rows | ForEach-Object {
            [pscustomobject]@{
                Provider = $_.Provider; Path = $_.Path; Size = $_.Size; Mtime = $_.Mtime
                Id = $_.Id; Title = $_.Title; Titled = $_.Titled; Group = $_.Group
                Hidden = $_.Hidden; When = $_.When
                First = (@($_.First) -join $script:ChatIndexSep)
                Last = (@($_.Last) -join $script:ChatIndexSep)
            }
        } | Export-Csv -LiteralPath $script:ChatIndexPath -NoTypeInformation -Encoding UTF8
    }
    catch {}
}

function Remove-ChatIndexRow {
    # A deleted chat has to leave the index too. Without this Tab went on
    # completing a title whose transcript was gone, and the search behind it
    # then found nothing - so the completion led straight to "no chat titled
    # like that". The index is what Tab reads; deleting the file is only half.
    #
    # Rewriting the CSV is also what drops the in-memory copy: Get-ChatIndex
    # caches against the file's mtime and length, and Save-ChatIndex leaves the
    # stamp alone, so the next read sees a new stamp and re-parses.
    param([string]$Path)
    try {
        if (-not $Path -or -not (Test-Path -LiteralPath $script:ChatIndexPath)) { return }
        $rows = @(Get-ChatIndex)
        if (-not $rows) { return }
        # -ne on paths is case-insensitive, which is what Windows needs
        $keep = @($rows | Where-Object { $_.Path -ne $Path })
        if ($keep.Count -eq $rows.Count) { return }
        Save-ChatIndex $keep
    }
    catch {}
}

function Sync-ChatIndex {
    # returns the index rows for $Provider, re-reading only what changed
    param([string[]]$Provider, [switch]$Force)
    # before indexing, so a chat the window wrote back never gets indexed
    Clear-ChatTombstones
    $names = if ($Provider) { $Provider } else { @($script:ChatProviders.Keys) }
    $cached = @(Get-ChatIndex)
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
        $p = $script:ChatProviders[$name]
        if (-not $p) { Write-Warning "unknown provider '$name'"; continue }
        foreach ($file in @(& $p.Discover)) {
            $hit = $old[$file.FullName]
            if ($hit -and $hit.Size -eq $file.Length -and $hit.Mtime -eq $file.LastWriteTimeUtc.Ticks) {
                $rows.Add($hit)     # unchanged since last time
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
    # only rewrite when something actually moved - the write is the expensive part
    $others = @($cached | Where-Object { $names -notcontains $_.Provider })
    $stale = ($reused + $others.Count) -ne $cached.Count
    if ($fresh -or $stale) {
        # silently: "new or changed" counts any transcript whose mtime moved,
        # which includes every session merely being typed in right now, so the
        # number read as "you made 4 chats" when nobody made any
        Save-ChatIndex @($others + $rows.ToArray())
    }
    return $rows.ToArray()
}

function chatindex {
    <#
    .SYNOPSIS
    Rebuild the chat index that searches and tab completion run off.
    .DESCRIPTION
    Normally unnecessary: every chatfind refreshes the index incrementally,
    re-reading only transcripts whose size or mtime changed. Use -Force to
    discard what is cached and read every transcript again.
    #>
    param([string[]]$Provider, [switch]$Force)
    Set-StrictMode -Off
    $rows = Sync-ChatIndex -Provider $Provider -Force:$Force
    $names = if ($Provider) { $Provider } else { @($script:ChatProviders.Keys) }
    Write-Host "indexed $($rows.Count) chats from: $($names -join ', ')"
}

#endregion

#region generic helpers -------------------------------------------------------

function Get-ChatAge {
    param([datetime]$When)
    $s = ([datetime]::Now - $When).TotalSeconds
    if ($s -lt 60) { return 'now' }
    if ($s -lt 3600) { return "$([math]::Floor($s / 60))m" }
    if ($s -lt 86400) { return "$([math]::Floor($s / 3600))h" }
    if ($s -lt 2592000) { return "$([math]::Floor($s / 86400))d" }
    if ($s -lt 31536000) { return "$([math]::Floor($s / 2592000))mo" }
    return "$([math]::Floor($s / 31536000))y"
}

function Format-ChatMessages {
    param([string[]]$Messages, [int]$Width = 100, [string]$Indent = '          ')
    if (-not $Messages) { return '' }
    ($Messages | ForEach-Object {
        $t = $_.Substring(0, [Math]::Min($Width, $_.Length))
        if ($_.Length -gt $Width) { $t += '...' }
        $t
    }) -join "`n$Indent"
}

function Format-ChatTitle {
    param([string]$Text, [int]$Width = 60)
    if (-not $Text) { return '(empty)' }
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Width) { $t = $t.Substring(0, $Width).TrimEnd() + '...' }
    return $t
}

function Test-ChatNoise {
    # prompts that are machinery, not something the user typed
    param([string]$Text)
    $Text.StartsWith('<') -or $Text.StartsWith('Caveat') -or $Text -like '*system-reminder*' -or
    $Text -like '`[Request interrupted*'
}

function Select-ChatDistinctRun {
    # drop consecutive repeats - Codex re-injects the same prompt every turn
    param([string[]]$Texts)
    $out = [System.Collections.Generic.List[string]]::new()
    $prev = $null
    foreach ($t in $Texts) {
        # compare on a normalized prefix: re-injections differ in punctuation
        $key = ($t -replace '[^\w]', '').ToLowerInvariant()
        $key = $key.Substring(0, [Math]::Min(80, $key.Length))
        if ($key -ne $prev) { $out.Add($t) }
        $prev = $key
    }
    # plain array, not comma-wrapped: callers pipe this straight into Select-Object
    return $out.ToArray()
}

function Open-ChatRead {
    # Codex holds every rollout open for the life of the window. OpenRead asks
    # for FileShare.Read, which collides with that writer and throws, so no
    # Codex chat ever reached the index - discovery found the files and Describe
    # then returned null on all of them. Share what the writer holds.
    param([string]$Path)
    [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
}

function Read-ChatAllText {
    # File::ReadAllText shares no better than OpenRead does
    param([string]$Path)
    $fs = Open-ChatRead $Path
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
}

function Read-ChatChunk {
    # head+tail only - transcripts run to megabytes and there are thousands
    param([string]$Path, [int]$Size = 524288)
    $fi = [System.IO.FileInfo]::new($Path)
    try { $fs = Open-ChatRead $Path } catch { return $null }  # can vanish mid-scan
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

function Get-ChatJsonLines {
    # index scan for a marker, not a line split + pipeline - that was 10x slower.
    # several markers may be given: the first one present in the text wins, which
    # covers writers that emit compact JSON and ones that pad after the colon
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
        # skip before counting, not after parsing: a chat can have hundreds of
        # tool-result lines carrying the same marker, which would fill the quota
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

function Get-ChatTimestampFromText {
    # the head/tail chunks are already in hand - no second read of the file
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

function Get-ChatLastTimestamp {
    # the last timestamp sits in the final few KB; ISO-8601, culture-invariant
    param([string]$Path)
    $fi = [System.IO.FileInfo]::new($Path)
    $tailLen = [Math]::Min(65536, $fi.Length)
    $buf = [byte[]]::new($tailLen)
    try { $fs = Open-ChatRead $Path } catch { return $fi.LastWriteTime }
    try {
        $fs.Seek(-$tailLen, [System.IO.SeekOrigin]::End) | Out-Null
        $fs.Read($buf, 0, $tailLen) | Out-Null
    }
    finally { $fs.Dispose() }
    $m = [regex]::Matches([System.Text.Encoding]::UTF8.GetString($buf), '"timestamp":\s*"([^"]+)"')
    if ($m.Count) {
        return [datetime]::Parse($m[$m.Count - 1].Groups[1].Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
    }
    return $fi.LastWriteTime
}

function Get-ChatHeadTailPrompts {
    # walk head and tail for prompt lines, parse only those, and fall back to the
    # whole file when one turn is bigger than the chunk and hides every prompt
    param([string]$Path, [string[]]$Marker, [scriptblock]$Parse, [int]$Count = $script:ChatPreview)
    $chunk = Read-ChatChunk $Path
    if (-not $chunk) { return $null }
    $scan = $Count * 4   # over-fetch: some candidates parse out as noise
    $head = $chunk.Head
    $tail = if ($chunk.Split) { $chunk.Tail } else { $chunk.Head }
    $first = @(); $last = @()
    foreach ($pass in 1, 2) {
        # assign before piping - these return comma-wrapped arrays
        $headLines = Get-ChatJsonLines $head $Marker $scan
        $tailLines = Get-ChatJsonLines $tail $Marker $scan -FromEnd
        $headTexts = Select-ChatDistinctRun @($headLines | ForEach-Object { & $Parse $_ } | Where-Object { $_ })
        $tailTexts = Select-ChatDistinctRun @($tailLines | ForEach-Object { & $Parse $_ } | Where-Object { $_ })
        $first = @($headTexts | Select-Object -First $Count)
        $last = @($tailTexts | Select-Object -Last $Count)
        if (-not $chunk.Split -or ($first.Count -gt 0 -and $last.Count -gt 0)) { break }
        if ($pass -eq 1) {
            $head = Read-ChatAllText $Path
            $tail = $head
            $chunk = [pscustomobject]@{ Head = $head; Tail = ''; Split = $false }
        }
    }
    return [pscustomobject]@{ First = $first; Last = $last; Head = $chunk.Head; Tail = $chunk.Tail }
}

function Convert-ChatJsonEscaped {
    # \n, \" and friends, without parsing the document they came from
    param([string]$Text)
    if ($Text -notlike '*\*') { return $Text }
    try { return ('"' + $Text + '"') | ConvertFrom-Json } catch { return $Text }
}

function Get-ChatJsonString {
    # index lookup rather than regex: this runs over megabyte-sized text.
    # both spacings are tried, since writers differ on the space after the colon
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

#endregion

#region provider: claude ------------------------------------------------------

function Read-ClaudePrompt {
    param([string]$Line)
    if ($Line -like '*"tool_result"*' -or $Line -like '*"isMeta":true*' -or $Line -like '*system-reminder*') { return $null }
    try { $o = $Line | ConvertFrom-Json } catch { return $null }
    if ($o.type -ne 'user') { return $null }
    $c = $o.message.content
    if ($c -isnot [string]) { $c = ($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' ' }
    if (-not $c) { return $null }
    $c = $c.Trim()
    if (Test-ChatNoise $c) { return $null }
    return ($c -replace '\s+', ' ')
}

#endregion

#region provider: copilot -----------------------------------------------------

function Get-CopilotWorkspaceName {
    # workspaceStorage/<hash>/workspace.json points at the folder the chats belong to
    param([string]$StorageDir)
    if ($script:ChatWorkspaceNames.ContainsKey($StorageDir)) { return $script:ChatWorkspaceNames[$StorageDir] }
    $name = Split-Path $StorageDir -Leaf
    $meta = Join-Path $StorageDir 'workspace.json'
    if (Test-Path -LiteralPath $meta) {
        try {
            $uri = (Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json).folder
            if ($uri) { $name = Split-Path ([Uri]::UnescapeDataString($uri)) -Leaf }
        }
        catch {}
    }
    $script:ChatWorkspaceNames[$StorageDir] = $name
    return $name
}

#endregion

#region provider: codex -------------------------------------------------------

function Get-CodexThreadNames {
    # Codex names a thread itself and keeps that name in session_index.jsonl,
    # never in the rollout. The panel lists the name, so the title has to come
    # from here - the first prompt was 'test' where the panel said 'Test task'.
    # Cached against the index mtime: a chat named after dot-source still lands.
    $path = Join-Path $script:ChatCodexHome 'session_index.jsonl'
    $f = Get-Item -LiteralPath $path -EA SilentlyContinue
    $stamp = if ($f) { $f.LastWriteTimeUtc.Ticks } else { 0 }
    if ($script:ChatCodexNames -and $script:ChatCodexNamesAt -eq $stamp) { return $script:ChatCodexNames }
    $map = @{}
    if ($f) {
        # UTF8 said outright: 5.1 reads a BOM-less file in the ANSI code page,
        # which turns a Hangul thread name into mojibake
        foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8 -EA SilentlyContinue)) {
            $o = try { $line | ConvertFrom-Json } catch { $null }
            if ($o.id -and $o.thread_name) { $map[[string]$o.id] = [string]$o.thread_name }
        }
    }
    $script:ChatCodexNames = $map
    $script:ChatCodexNamesAt = $stamp
    return $map
}

function Read-CodexPrompt {
    param([string]$Line)
    try { $o = $Line | ConvertFrom-Json } catch { return $null }
    if ($o.payload.role -ne 'user') { return $null }
    $t = ($o.payload.content | Where-Object { $_.type -eq 'input_text' } | ForEach-Object { $_.text }) -join ' '
    if (-not $t) { return $null }
    $t = $t.Trim()
    # the IDE wraps the real prompt in a context block
    $i = $t.IndexOf('## My request for Codex:')
    if ($i -ge 0) { $t = $t.Substring($i + 24).Trim() }
    # AGENTS.md preambles and environment blocks are not prompts
    if ($t.StartsWith('# AGENTS.md') -or $t.StartsWith('<') -or $t.StartsWith('# Context from my IDE')) { return $null }
    if (Test-ChatNoise $t) { return $null }
    return ($t -replace '\s+', ' ')
}

#endregion

#region provider registry -----------------------------------------------------

$script:ChatProviders = [ordered]@{

    claude  = [pscustomobject]@{
        Root     = (Join-Path $script:ChatClaudeHome 'projects')
        Discover = {
            # only projects/<slug>/<uuid>.jsonl - a recursive sweep also drags in
            # workflow journals and agent transcripts, which are not chats
            $root = Join-Path $script:ChatClaudeHome 'projects'
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
                    Get-ChildItem -LiteralPath $_.FullName -Filter *.jsonl -File |
                        Where-Object { $_.BaseName -match '^[0-9a-fA-F-]{36}$' }
                }
            }
        }
        Describe = {
            param($File)
            $p = Get-ChatHeadTailPrompts $File.FullName '"type":"user"' ${function:Read-ClaudePrompt}
            if (-not $p) { return $null }
            # subagent transcripts are flagged on line 1; the GUI hides them too
            $nl = $p.Head.IndexOf("`n")
            $firstLine = if ($nl -ge 0) { $p.Head.Substring(0, $nl) } else { $p.Head }
            $hidden = $firstLine -like '*"isSidechain":true*'
            $title = $null; $source = 'first message'
            foreach ($t in @($p.Tail, $p.Head)) {
                if (-not $title) { $title = Get-ChatJsonString $t 'customTitle'; if ($title) { $source = 'renamed' } }
            }
            if (-not $title) {
                foreach ($t in @($p.Tail, $p.Head)) {
                    if (-not $title) { $title = Get-ChatJsonString $t 'aiTitle'; if ($title) { $source = 'auto' } }
                }
            }
            # the raw JSON text: a title holding a quote came through as \"
            if ($title) { $title = Convert-ChatJsonEscaped $title }
            if (-not $title) {
                $sidecar = Join-Path (Join-Path $File.DirectoryName $File.BaseName) 'custom-title.json'
                if (Test-Path -LiteralPath $sidecar) {
                    try { $title = (Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json).customTitle; if ($title) { $source = 'renamed' } } catch {}
                }
            }
            if (-not $title) { $title = @($p.First)[0] }
            [pscustomobject]@{
                Id          = $File.BaseName
                Title       = Format-ChatTitle $title
                TitleSource = $source
                Group       = $File.Directory.Name
                Hidden      = $hidden
                When        = Get-ChatTimestampFromText $p $File
                First       = $p.First
                Last        = $p.Last
            }
        }
        IsEmpty  = {
            # a ghost holds only state lines - ai-title / mode / atis-latch - and
            # is written when the GUI opens a chat whose transcript is gone
            param($File)
            if ($File.Length -gt 65536) { return $false }
            $t = Read-ChatAllText $File.FullName
            (-not ($t -like '*"type":"user"*')) -and (-not ($t -like '*"type":"assistant"*'))
        }
        Extras   = {
            param($File, $Record)
            @(
                (Join-Path $File.DirectoryName $File.BaseName)
                (Join-Path (Join-Path $script:ChatClaudeHome 'file-history') $File.BaseName)
                (Join-Path (Join-Path $script:ChatClaudeHome 'session-env') $File.BaseName)
            )
        }
    }

    copilot = [pscustomobject]@{
        Root     = (Join-Path $script:ChatCodeUser 'workspaceStorage')
        Discover = {
            $root = Join-Path $script:ChatCodeUser 'workspaceStorage'
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
                    $dir = Join-Path $_.FullName 'chatSessions'
                    if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Filter *.json -File }
                }
            }
        }
        Describe = {
            param($File)
            # regex over head+tail, not ConvertFrom-Json: these files reach 700 KB
            # each and the metadata sits after requests[], so the tail carries it
            $chunk = Read-ChatChunk $File.FullName
            if (-not $chunk) { return $null }
            $meta = if ($chunk.Split) { $chunk.Tail } else { $chunk.Head }
            $rx = [regex]'"message":\s*\{\s*"text":\s*"((?:[^"\\]|\\.)*)"'
            $grab = {
                param($text)
                Select-ChatDistinctRun @($rx.Matches($text) | ForEach-Object {
                        $t = (Convert-ChatJsonEscaped $_.Groups[1].Value) -replace '\s+', ' '
                        $t = $t.Trim()
                        if ($t -and -not (Test-ChatNoise $t)) { $t }
                    })
            }
            $first = @(& $grab $chunk.Head | Select-Object -First $script:ChatPreview)
            $last = @(& $grab $meta | Select-Object -Last $script:ChatPreview)
            if (-not $first -and $chunk.Split) {
                $whole = Read-ChatAllText $File.FullName
                $first = @(& $grab $whole | Select-Object -First $script:ChatPreview)
                $last = @(& $grab $whole | Select-Object -Last $script:ChatPreview)
            }
            $texts = $first
            $title = Get-ChatJsonString $meta 'customTitle'
            if ($title) { $title = Convert-ChatJsonEscaped $title }
            $source = if ($title) { 'renamed' } else { 'first message' }
            if (-not $title) { $title = @($texts)[0] }
            $ms = if ($meta -match '"lastMessageDate":\s*(\d+)') { $Matches[1] }
            elseif ($meta -match '"creationDate":\s*(\d+)') { $Matches[1] }
            $when = if ($ms) { [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms).LocalDateTime } else { $File.LastWriteTime }
            [pscustomobject]@{
                Id          = $File.BaseName
                Title       = Format-ChatTitle $title
                TitleSource = $source
                Group       = Get-CopilotWorkspaceName (Split-Path $File.DirectoryName -Parent)
                Hidden      = $false
                When        = $when
                First       = $first
                Last        = $last
            }
        }
        IsEmpty  = {
            param($File)
            if ($File.Length -gt 65536) { return $false }
            $t = Read-ChatAllText $File.FullName
            [bool]($t -match '"requests":\s*\[\s*\]')   # panel opened, never used
        }
        Extras   = {
            param($File, $Record)
            @(Join-Path (Join-Path (Split-Path $File.DirectoryName -Parent) 'chatEditingSessions') $File.BaseName)
        }
    }

    codex   = [pscustomobject]@{
        Root     = (Join-Path $script:ChatCodexHome 'sessions')
        Discover = {
            $root = Join-Path $script:ChatCodexHome 'sessions'
            if (Test-Path -LiteralPath $root) { Get-ChildItem -LiteralPath $root -Filter *.jsonl -Recurse -File }
        }
        Describe = {
            param($File)
            $p = Get-ChatHeadTailPrompts $File.FullName @('"role":"user"', '"role": "user"') ${function:Read-CodexPrompt}
            if (-not $p) { return $null }
            # rollout-<iso>-<uuid>.jsonl - the id is everything after the timestamp
            $id = if ($File.BaseName -match '([0-9a-fA-F-]{36})$') { $Matches[1] } else { $File.BaseName }
            $cwd = Get-ChatJsonString $p.Head 'cwd'
            $group = if ($cwd) { Split-Path ($cwd -replace '\\\\', '\') -Leaf } else { 'codex' }
            $named = (Get-CodexThreadNames)[$id]
            $title = if ($named) { $named } else { @($p.First)[0] }
            [pscustomobject]@{
                Id          = $id
                Title       = Format-ChatTitle $title
                TitleSource = if ($named) { 'thread name' } else { 'first message' }
                Group       = $group
                Hidden      = $false
                When        = Get-ChatTimestampFromText $p $File
                First       = $p.First
                Last        = $p.Last
            }
        }
        IsEmpty  = {
            param($File)
            if ($File.Length -gt 65536) { return $false }
            $t = Read-ChatAllText $File.FullName
            -not ($t -match '"role":\s*"user"')
        }
        Extras   = { param($File, $Record) @() }
    }
}

function chatclean {
    <#
    .SYNOPSIS
    Delete ghost chats - transcripts that hold no messages at all.
    .DESCRIPTION
    Clicking a chat in the VS Code list after its transcript was deleted makes
    the extension write the session back as a stub: a title line, a mode line,
    nothing else. Those stubs then show up as ghost rows, and clicking them
    again makes more. This finds and removes them.

    A file counts as empty only if it is under 64 KB AND contains no user or
    assistant message at all, so a real chat can never match.
    .PARAMETER Force
    Delete every ghost found without asking.
    .EXAMPLE
    chatclean
    #>
    param([string[]]$Provider, [switch]$Force)
    Set-StrictMode -Off

    $candidates =@(Sync-ChatIndex -Provider $Provider | Where-Object { -not $_.First })
    $ghosts = foreach ($row in $candidates) {
        $p = $script:ChatProviders[$row.Provider]
        if (-not $p.IsEmpty) { continue }
        $file = try { Get-Item -LiteralPath $row.Path -EA Stop } catch { continue }
        if (-not (& $p.IsEmpty $file)) { continue }
        [pscustomobject]@{
            Provider = $row.Provider
            File     = $file
            Record   = [pscustomobject]@{
                Id = $row.Id; Title = $row.Title; TitleSource = $row.Titled
                Group = $row.Group; Hidden = $row.Hidden
                When = [datetime]::Parse($row.When, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)
                First = @(); Last = @()
            }
        }
    }
    $ghosts = @($ghosts)
    if (-not $ghosts) { Write-Host 'no ghost chats found'; return }

    $chosen = if ($Force) { $ghosts } else { Select-ChatItems $ghosts "$($ghosts.Count) ghost chats (no messages at all)" }
    if (-not $chosen) { Write-Host 'nothing deleted'; return }
    foreach ($g in $chosen) { $null = Remove-ChatSession $g }
    Write-Host ''
    Write-ChatGhostAdvice
}

function chatproviders {
    <#
    .SYNOPSIS
    Show which chat tools were found on this machine, and where they store chats.
    #>
    Set-StrictMode -Off
    $script:ChatProviders.GetEnumerator() | ForEach-Object {
        $files = @(& $_.Value.Discover)
        [pscustomobject]@{
            Provider = $_.Key
            Present  = Test-Path -LiteralPath $_.Value.Root
            Chats    = $files.Count
            MB       = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
            Root     = $_.Value.Root
        }
    }
}

#endregion

#region search and delete -----------------------------------------------------

function Get-ChatProjectScope {
    # What "this project" means to each tool. Claude names its project folder
    # after the whole path with every non-alphanumeric turned into a dash;
    # Copilot and Codex only ever record the leaf folder name.
    param([string]$Path = $PWD.Path)
    $full = $Path.TrimEnd('\', '/')
    [pscustomobject]@{
        Slug = ($full -replace '[^A-Za-z0-9]', '-')
        Leaf = Split-Path $full -Leaf
    }
}

function Test-ChatInProject {
    # Exact, never a prefix. Sibling repos nest - the slug for AS-RadarViewer
    # is a prefix of the one for AS-RadarViewer-Mobile - so -like or StartsWith
    # would quietly drag the neighbour in, which is the bug this exists to fix.
    param($Row, $Scope)
    if (-not $Row.Group) { return $false }
    if ($Row.Provider -eq 'claude') { return $Row.Group -eq $Scope.Slug }
    return $Row.Group -eq $Scope.Leaf
}

function Select-ChatInProject {
    # Narrow rows to the project being stood in. Returns them untouched when
    # this directory is not a project any tool knows - otherwise running from
    # anywhere else would match nothing at all.
    # -Cwd for the background watcher, whose own folder is wherever the first
    # chatq happened to be typed, not the job's
    param([object[]]$Rows, [switch]$AllProjects, [string]$Cwd = $PWD.Path)
    if ($AllProjects -or -not $Rows) { return $Rows }
    $scope = Get-ChatProjectScope $Cwd
    $mine = @($Rows | Where-Object { Test-ChatInProject $_ $scope })
    if ($mine) { return $mine }
    return $Rows
}

function Find-ChatSessions {
    param(
        [string]$Needle,
        [string[]]$Provider,
        [switch]$Deep,
        [switch]$All,
        [switch]$AllProjects,
        [switch]$TitleOnly
    )
    # match against the index; only matches are turned back into file objects
    $rows = Select-ChatInProject @(Sync-ChatIndex -Provider $Provider) -AllProjects:$AllProjects
    foreach ($row in $rows) {
        if ($row.Hidden -and -not $All) { continue }
        $hit = if ($Deep) {
            Select-String -Path $row.Path -SimpleMatch -Pattern $Needle -Quiet -EA SilentlyContinue
        }
        elseif ($TitleOnly) {
            # literal, not -like: a completed title may contain [ ] ? or *
            $row.Title.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        else {
            ($row.Title -like "*$Needle*") -or
            [bool](@($row.First) + @($row.Last) | Where-Object { $_ -like "*$Needle*" })
        }
        if (-not $hit) { continue }
        $file = try { Get-Item -LiteralPath $row.Path -EA Stop } catch { continue }
        [pscustomobject]@{
            Provider = $row.Provider
            File     = $file
            Record   = [pscustomobject]@{
                Id          = $row.Id
                Title       = $row.Title
                TitleSource = $row.Titled
                Group       = $row.Group
                Hidden      = $row.Hidden
                When        = [datetime]::Parse($row.When, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)
                First       = @($row.First)
                Last        = @($row.Last)
            }
        }
    }
}

function chatfind {
    <#
    .SYNOPSIS
    Find local AI chat transcripts by title or message text.
    .DESCRIPTION
    Searches Claude Code, Copilot Chat and Codex transcripts on this machine and
    returns one object per match, so results can be piped. Also refreshes the
    index that makes chatrm's tab completion instant.
    .PARAMETER Text
    Text to look for in the chat title and the first/last user messages.
    .PARAMETER Provider
    Limit the search: claude, copilot, codex. Defaults to all of them.
    .PARAMETER Deep
    Match anywhere in the transcript rather than title and previews. Slower.
    .PARAMETER All
    Include subagent / workflow transcripts, which are hidden by default.
    .PARAMETER AllProjects
    Search every project rather than the one this directory belongs to.
    .EXAMPLE
    chatfind "brownout"
    .EXAMPLE
    chatfind gitignore -Provider copilot | Select-Object Title, Id, Age
    .LINK
    chatrm
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Text,
        [string[]]$Provider,
        [switch]$Deep,
        [switch]$All,
        [switch]$AllProjects
    )
    Set-StrictMode -Off

    $needle = $Text -join ' '
    if (-not $needle) { Write-Error 'usage: chatfind "text" [-Provider claude,copilot,codex] [-Deep] [-All] [-AllProjects]'; return }
    # emits objects, not formatted text, so results stay pipeable
    Find-ChatSessions -Needle $needle -Provider $Provider -Deep:$Deep -All:$All -AllProjects:$AllProjects | ForEach-Object {
        $r = $_.Record
        [pscustomobject]@{
            Title    = $r.Title
            Titled   = $r.TitleSource
            Provider = $_.Provider
            Id       = $r.Id
            Group    = $r.Group
            Age      = Get-ChatAge $r.When
            LastAt   = $r.When.ToString('yyyy-MM-dd HH:mm')
            Touched  = Get-ChatAge $_.File.LastWriteTime   # mtime, as the GUIs show it
            MB       = [math]::Round($_.File.Length / 1MB, 2)
            First    = Format-ChatMessages $r.First
            Recent   = if (($r.First -join "`n") -eq ($r.Last -join "`n")) { '(same)' } else { Format-ChatMessages $r.Last }
        }
    }
}

function Get-ChatProviderForPath {
    param([string]$Path)
    foreach ($e in $script:ChatProviders.GetEnumerator()) {
        if ($e.Value.Root -and $Path.StartsWith($e.Value.Root, [StringComparison]::OrdinalIgnoreCase)) {
            return $e.Key
        }
    }
    return $null
}

function Add-ChatTombstone {
    # Remember what was deleted, because the window will write some of it back
    param([string]$Path)
    $dir = Split-Path $script:ChatTombPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    Add-Content -LiteralPath $script:ChatTombPath -Value ("{0}`t{1}" -f (Get-Date).ToString('o'), $Path)
    Start-ChatGhostWatch
}

function Test-ChatGhostWatch {
    # Asking Get-EventSubscriber for a name that is not registered raises an
    # error - and -ErrorAction SilentlyContinue hides it but still files it in
    # $Error. Listing and filtering asks the same question quietly.
    [bool]@(Get-EventSubscriber -EA SilentlyContinue |
        Where-Object { $_.SourceIdentifier -eq 'ChatGhostWatch' })
}

function Start-ChatGhostWatch {
    # Why running it a second time works: the window flushes a tracked session
    # to disk once, when it reloads. After that reload it rebuilds its list
    # from disk and is no longer holding that session, so the next delete
    # sticks. The write is a single event, not a state to out-wait - so watch
    # for it instead of polling, and take the file back the moment it lands.
    #
    # Created only, and FileName only: transcripts are appended to constantly,
    # and a rewritten ghost always arrives as a brand new file. That keeps this
    # silent until the one event that matters.
    #
    # Here, not at the call sites: tombstones and the index sweep start it too,
    # and the background watcher runs both. That process is headless and
    # outlives the shell - a second watch there would only race this one.
    if ($env:CHATQ_WATCHER -or $script:ChatNoGhostWatch) { return }
    if (Test-ChatGhostWatch) { return }
    $root = Join-Path $script:ChatClaudeHome 'projects'
    if (-not (Test-Path -LiteralPath $root)) { return }

    $fsw = New-Object System.IO.FileSystemWatcher $root, '*.jsonl'
    $fsw.IncludeSubdirectories = $true
    $fsw.NotifyFilter = [System.IO.NotifyFilters]::FileName
    $fsw.EnableRaisingEvents = $true
    $script:ChatGhostWatcher = $fsw          # a reference, or it is collected

    # self-contained: this runs in its own runspace, with none of these
    # functions loaded, and must stay silent so it cannot garble the prompt
    $null = Register-ObjectEvent -InputObject $fsw -EventName Created `
        -SourceIdentifier 'ChatGhostWatch' -MessageData $script:ChatTombPath -Action {
        $tomb = $Event.MessageData
        $path = $Event.SourceEventArgs.FullPath
        if (-not (Test-Path -LiteralPath $tomb)) { return }
        # the same seven days the sweep honours, or an entry the sweep would
        # have dropped would still be acted on here
        $cutoff = (Get-Date).AddDays(-7)
        $wanted = @(Get-Content -LiteralPath $tomb -EA SilentlyContinue | ForEach-Object {
                $parts = $_ -split "`t", 2
                if ($parts.Count -eq 2) {
                    $when = try {
                        [datetime]::Parse($parts[0], [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::RoundtripKind)
                    }
                    catch { $null }
                    if ($when -and $when -ge $cutoff) { $parts[1] }
                }
            })
        if ($wanted -notcontains $path) { return }
        Start-Sleep -Milliseconds 200        # let the writer finish the file
        $f = Get-Item -LiteralPath $path -EA SilentlyContinue
        if (-not $f -or $f.Length -gt 65536) { return }
        # runs in the watcher's own runspace, where the shared-read helpers are
        # not defined - open the handle inline, sharing what a writer may hold
        $t = try {
            $fh = [System.IO.FileStream]::new($f.FullName, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try { [System.IO.StreamReader]::new($fh).ReadToEnd() } finally { $fh.Dispose() }
        }
        catch { return }
        if ($t -like '*"type":"user"*' -or $t -like '*"type":"assistant"*') { return }
        Remove-Item -LiteralPath $path -Force -EA SilentlyContinue
    }
}

function Stop-ChatGhostWatch {
    if (Test-ChatGhostWatch) { Unregister-Event -SourceIdentifier 'ChatGhostWatch' -EA SilentlyContinue }
    if ($script:ChatGhostWatcher) {
        $script:ChatGhostWatcher.EnableRaisingEvents = $false
        $script:ChatGhostWatcher.Dispose()
        $script:ChatGhostWatcher = $null
    }
}

function Clear-ChatTombstones {
    # The window does not write a deleted session back straight away - it
    # flushes session state when it reloads or closes, minutes later, and the
    # file reappears with a brand new creation time.
    #
    # Start-ChatGhostWatch catches that write as it happens, but only while a
    # shell that loaded this file is open. This is the backstop for the rest:
    # the deletion is remembered, and taken again the next time any of these
    # commands runs, in whatever shell.
    #
    # Only ever removes a file that is still a stub, so resuming one of these
    # sessions for real makes it stop being a tombstone's business.
    if (-not (Test-Path -LiteralPath $script:ChatTombPath)) { return }
    $keep = [System.Collections.Generic.List[string]]::new()
    $took = 0
    $cutoff = (Get-Date).AddDays(-7)
    foreach ($line in @(Get-Content -LiteralPath $script:ChatTombPath -EA SilentlyContinue)) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $when = try {
            [datetime]::Parse($parts[0], [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        catch { continue }
        if ($when -lt $cutoff) { continue }        # long gone, stop watching it
        $path = $parts[1]
        if (Test-Path -LiteralPath $path) {
            $file = Get-Item -LiteralPath $path -EA SilentlyContinue
            $name = Get-ChatProviderForPath $path
            $prov = if ($name) { $script:ChatProviders[$name] } else { $null }
            if ($file -and $prov -and $prov.IsEmpty -and (& $prov.IsEmpty $file)) {
                Remove-Item -LiteralPath $path -Force -EA SilentlyContinue
                if (-not (Test-Path -LiteralPath $path)) { $took++ }
            }
            elseif ($file) { continue }            # it has real content now - leave it, drop it
        }
        $keep.Add($line)
    }
    if ($keep.Count) {
        Set-Content -LiteralPath $script:ChatTombPath -Value $keep.ToArray()
        Start-ChatGhostWatch          # a new shell picks the watch back up
    }
    else {
        Remove-Item -LiteralPath $script:ChatTombPath -Force -EA SilentlyContinue
        Stop-ChatGhostWatch           # nothing left to watch for
    }
    if ($took) {
        Write-Host "  took back $took chat$(if ($took -ne 1) { 's' }) the window had rewritten" -ForegroundColor DarkGray
    }
}

function Test-ChatJobsHold {
    # $true when a prompt queued by chatq holds this chat and it must stay.
    # Deleting it would leave a job that resumes a transcript no longer there -
    # and a claude -p still running into it would write it straight back as a
    # fragment. -DropJobs drops them first, and waits out a running one.
    param($Hit, [switch]$DropJobs)
    $mine = { @(Get-ChatqJobs | Where-Object { $_.sessionId -eq $Hit.Record.Id }) }
    $held = @(& $mine | Where-Object { $_.state -in 'queued', 'running' })
    if (-not $held) { return $false }
    $nums = ($held | ForEach-Object { "#$($_.seq)" }) -join ' '
    if (-not $DropJobs) {
        Write-Host "  KEPT     $($Hit.Record.Title)" -ForegroundColor Yellow
        Write-Host "           $nums queued for it - -DropJobs drops them first" -ForegroundColor DarkGray
        return $true
    }
    foreach ($j in $held) { chatqrm $j.seq -Force }
    # a cancel is only read by the watcher, every few seconds
    $until = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $until -and @(& $mine | Where-Object { $_.state -eq 'running' })) {
        Start-Sleep -Milliseconds 500
    }
    if (@(& $mine | Where-Object { $_.state -eq 'running' })) {
        Write-Host "  KEPT     $($Hit.Record.Title)" -ForegroundColor Yellow
        Write-Host '           its run has not stopped yet - try again in a moment' -ForegroundColor DarkGray
        return $true
    }
    # a cancelled run ends as a failed job; nothing is left to send, so it goes
    foreach ($j in @(& $mine)) { chatqrm $j.seq -Force }
    return $false
}

function Remove-ChatSession {
    # Returns $true only if the transcript is actually gone. Windows refuses to
    # delete a file another process holds open, and Remove-Item reports that as
    # a non-terminating error - so without the check afterwards this printed
    # "deleted" for a chat that was still sitting there.
    param($Hit)
    $path = $Hit.File.FullName
    Remove-Item -LiteralPath $path -Force -EA SilentlyContinue
    foreach ($p in @(& $script:ChatProviders[$Hit.Provider].Extras $Hit.File $Hit.Record)) {
        if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Recurse -Force -EA SilentlyContinue }
    }
    if (Test-Path -LiteralPath $path) {
        Write-Host "  LOCKED   $($Hit.Record.Title)" -ForegroundColor Yellow
        Write-Host '           still on disk - another process has it open' -ForegroundColor DarkGray
        return $false
    }
    Add-ChatTombstone $path
    # the index is what Tab completes from, so a row left behind offers a title
    # whose transcript is already gone
    Remove-ChatIndexRow $path
    # the title, not the full row: the row is wider than a narrow panel and wraps
    Write-Host "  deleted  $($Hit.Record.Title)" -ForegroundColor DarkGray
    return $true
}

$script:ChatIdleSeconds = 60

function Get-ChatProjectFiles {
    # The folders this project's chats live in, not the index rows themselves.
    # A chat started since the index was built is missing from the rows, and
    # that is precisely the chat most likely to be running.
    param([switch]$AllProjects, [string]$Cwd = $PWD.Path)
    $rows = Select-ChatInProject @(Get-ChatIndex) -AllProjects:$AllProjects -Cwd $Cwd
    if (-not $rows) { return @() }
    $dirs = @($rows | ForEach-Object { Split-Path $_.Path -Parent } | Sort-Object -Unique)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -EA SilentlyContinue)) { $out.Add($f) }
    }
    return $out
}

function Test-ChatTranscriptBusy {
    # Whether a transcript is parked mid-turn. $true mid-turn, $false finished,
    # $null cannot tell.
    #
    # This exists because mtime is blind to the two states that matter most: a
    # session waiting on a permission prompt, and one sitting inside a long tool
    # call. Neither writes anything, so both look finished after a minute - and
    # reloading either one throws away the pending prompt or the answer.
    # The last record carrying a message says where the turn actually got to.
    param([string]$Path)
    if ($Path -notlike '*.jsonl') { return $null }   # Claude's format only
    $c = Read-ChatChunk -Path $Path -Size 32768
    if (-not $c) { return $null }
    $text = if ($c.Split) { $c.Tail } else { $c.Head }
    # TrimStart the BOM: a chunk taken from the head of a file carries it into
    # the first line, and U+FEFF is not whitespace, so Trim leaves it there and
    # ConvertFrom-Json rejects the line
    $lines = @($text -split "`r?`n" |
        ForEach-Object { $_.TrimStart([char]0xFEFF).Trim() } |
        Where-Object { $_ })
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $o = try { $lines[$i] | ConvertFrom-Json } catch { $null }
        # ai-title, mode and atis-latch trail a turn and say nothing about it,
        # so walk back past them to the last real message
        if (-not $o -or -not $o.message) { continue }
        if ($o.type -eq 'assistant') {
            # tool_use is the agent waiting on a tool - which includes waiting
            # on you to allow one, or to answer a question it asked
            return ($o.message.stop_reason -eq 'tool_use')
        }
        if ($o.type -eq 'user') { return $true }     # a reply is owed
        return $null
    }
    return $null
}

function Test-ChatIdle {
    # $true idle, $false active, $null when it cannot be told - and $null stays
    # distinct, because "safe to reload" guessed wrong costs someone an answer.
    param([int]$Seconds = $script:ChatIdleSeconds, [switch]$AllProjects, [string]$Cwd = $PWD.Path)
    $files = @(Get-ChatProjectFiles -AllProjects:$AllProjects -Cwd $Cwd)
    if (-not $files) { return $null }

    # first layer: anything written just now is plainly live
    $cut = (Get-Date).AddSeconds(-$Seconds)
    foreach ($f in $files) { if ($f.LastWriteTime -gt $cut) { return $false } }

    # second layer: quiet on disk is not the same as finished. Only a recently
    # touched transcript can still be live, so the rest are not worth opening.
    $since = (Get-Date).AddHours(-12)
    foreach ($f in $files) {
        if ($f.LastWriteTime -lt $since) { continue }
        if ((Test-ChatTranscriptBusy $f.FullName) -eq $true) { return $false }
    }
    return $true
}

function Wait-ChatIdle {
    # Blocks the shell on purpose. Printing this from a background runspace is
    # what garbles the prompt - the ghost watcher stays silent for that reason -
    # so waiting where the caller can see it is the honest version.
    param([int]$Seconds = $script:ChatIdleSeconds, [switch]$AllProjects)
    $safe = '  all project chat is idle - safe to reload now'
    $state = Test-ChatIdle -Seconds $Seconds -AllProjects:$AllProjects
    if ($null -eq $state) {
        # waiting forever on a question that cannot be answered is worse than
        # saying so, and claiming "safe" here would be a guess wearing a fact
        Write-Host '  no index - cannot tell whether a chat is active' -ForegroundColor DarkGray
        return
    }
    if ($state) {
        Write-Host $safe -ForegroundColor Green
        return
    }
    Write-Host "  waiting for project chat to go quiet for ${Seconds}s - Ctrl+C to stop" -ForegroundColor DarkGray
    while ((Test-ChatIdle -Seconds $Seconds -AllProjects:$AllProjects) -eq $false) {
        Start-Sleep -Seconds 5
    }
    Write-Host $safe -ForegroundColor Green
}

function Write-ChatReloadRequest {
    # Left for the extension in extension/, if it is installed. Harmless when it
    # is not: an unread file in data/. The cwd is what lets each window decide
    # whether the delete was for its own workspace - so the background watcher
    # passes the job's folder, never its own. Kind is 'deleted' for chatrm and
    # 'ran' for a queued prompt that ran into a chat still open in a window.
    param([string]$Title, [string]$Cwd = (Get-Location).Path, [string]$Kind = 'deleted')
    try {
        $dir = Split-Path $script:ChatReloadPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $json = [ordered]@{
            id    = [guid]::NewGuid().ToString()
            kind  = $Kind
            cwd   = $Cwd
            title = $Title
            at    = (Get-Date).ToString('o')
        } | ConvertTo-Json -Compress
        # NOT Set-Content -Encoding UTF8: that writes a BOM on 5.1 and
        # JSON.parse rejects a BOM outright, so the extension would see nothing
        [System.IO.File]::WriteAllText($script:ChatReloadPath, $json,
            (New-Object System.Text.UTF8Encoding $false))
    }
    catch {}
}

function Write-ChatGhostAdvice {
    # Said once, after a delete, and only while a window is up to do it. macOS
    # runs VS Code as Electron and 'Code Helper (...)', never a bare Code, so the
    # name has to differ per platform or the advice never prints there at all.
    param([switch]$WaitForIdle, [switch]$AllProjects, [string]$Title)
    $procs = if ($script:ChatIsMac) { @('Electron', 'Code Helper*') } else { @('Code') }
    if (-not @(Get-Process -Name $procs -EA SilentlyContinue).Count) { return }
    Write-ChatReloadRequest -Title $Title
    Write-Host 'the session list is cached - reload to see it go:'
    Write-Host '  Ctrl+Shift+P > Developer: Reload Window'
    if (Test-ChatGhostWatch) {
        Write-Host '  the window rewrites it as it reloads; that is watched for and taken back' -ForegroundColor DarkGray
    }
    else {
        Write-Host '  then run any chat command - the window rewrites it as it reloads' -ForegroundColor DarkGray
    }

    # A reload restarts the extensions, so one taken mid-answer loses that
    # answer. Nothing out here can reload the window for you - VS Code runs that
    # command from inside an extension only - so the most this can do is say
    # whether now is a safe moment.
    if ($WaitForIdle) { Wait-ChatIdle -AllProjects:$AllProjects; return }
    switch (Test-ChatIdle -AllProjects:$AllProjects) {
        $true { Write-Host '  all project chat is idle - safe to reload now' -ForegroundColor Green }
        $false {
            Write-Host '  a chat is still active - reload once it finishes' -ForegroundColor Yellow
            Write-Host '  -WaitForIdle waits and tells you when' -ForegroundColor DarkGray
        }
        default { }   # no index to judge by: say nothing rather than guess
    }
}
function Format-ChatRow {
    param($Hit)
    $r = $Hit.Record
    '{0,-52} {1,-8} {2,-28} {3,4} {4,6} MB' -f
    $r.Title.Substring(0, [Math]::Min(52, $r.Title.Length)),
    $Hit.Provider,
    $r.Group.Substring(0, [Math]::Min(28, $r.Group.Length)),
    (Get-ChatAge $r.When),
    [math]::Round($Hit.File.Length / 1MB, 2)
}

function Test-ChatVT {
    # can the cursor be moved with escape sequences? Absolute CursorPosition is
    # not usable here: under the pseudo-console VS Code runs, setting it is
    # accepted and does nothing, so a redrawing list paints a fresh copy of
    # itself below the last one on every keypress. Relative moves work.
    if ([Console]::IsInputRedirected) { return $false }
    try { return [bool]$Host.UI.SupportsVirtualTerminal } catch { return $false }
}

function Invoke-ChatKeyLoop {
    # Every picker below is this loop: back up over what was drawn last time,
    # draw again, read one key. $Paint draws and returns how many lines it
    # wrote; $OnKey returns nothing to keep going, or @{ Value = ... } to stop
    # and hand that back. Shared state goes in a hashtable both blocks close
    # over - a plain variable assigned inside a scriptblock would only ever
    # change that block's own copy.
    param([scriptblock]$Paint, [scriptblock]$OnKey)
    $esc = [char]27
    $painted = 0
    while ($true) {
        if ($painted) { Write-Host "$esc[${painted}A" -NoNewline }
        $painted = [int](& $Paint)
        $stop = & $OnKey ([Console]::ReadKey($true))
        if ($stop) { return $stop.Value }
    }
}

# What Format-ChatPickTail writes, anchored, so Enter can take it back off.
# It has to come off: "#1/3" alone was a comment and harmless to leave, but
# "(5d)" in front of it is not - PowerShell would run it as an expression.
$script:ChatTailPattern = '\s*(\([^)]*\))?\s*#\d+/\d+\s*$'
# The same tail with more typed after it. Narrow on purpose - only an age as
# Get-ChatAge writes it - so text in a prompt is never mistaken for one.
$script:ChatMidTailPattern = '\s(?:\((?:now|\d+(?:mo|m|h|d|y))\)\s)?#\d+/\d+(?=\s)'

function Format-ChatPickTail {
    # The decoration every path shares: the age, then where you are in the run.
    # Tab puts this straight into the command line, so Enter strips it again
    # before running - see the Enter handler.
    param([string]$Age, [int]$Index, [int]$Count)
    $t = ''
    if ($Age) { $t = " ($Age)" }
    return "$t #$Index/$Count"
}

function Format-ChatWalkRow {
    # The line Tab leaves on the command line, rebuilt: the command, the full
    # title, the tail. Walking matches after Enter should look exactly like
    # walking them before it. Trimmed rather than padded so the tail stays
    # beside the title, and its width is held back before clipping so a long
    # title can never push it off the end.
    param($Hit, [int]$Index, [int]$Count, [int]$Width, [switch]$Ambiguous)
    $c = Get-ChatSyntaxColor
    $tail = Format-ChatPickTail (Get-ChatAge $Hit.Record.When) $Index $Count
    $segments = @(
        @{ Text = '  chatrm '; Color = $c.Command }
        @{ Text = "'" + $Hit.Record.Title.Replace("'", "''") + "'"; Color = $c.String }
    )
    # Only when title and age are both the same, which the line alone cannot
    # separate - and Enter deletes on the spot, so they have to be separable.
    # Project and size together, because two chats in one project can share a
    # title and an age as well.
    if ($Ambiguous) {
        $segments += @{
            Text  = "  $($Hit.Record.Group) $([math]::Round($Hit.File.Length / 1MB, 2))MB"
            Color = $c.Param
        }
    }
    # clip across the segments, measuring the text and never the escapes
    $budget = $Width - (Get-ChatCells $tail)
    $line = ''
    $used = 0
    foreach ($seg in $segments) {
        if ($used -ge $budget) { break }
        $piece = Format-ChatCell $seg.Text ($budget - $used) -NoPad
        $line += $seg.Color + $piece
        $used += Get-ChatCells $piece
    }
    return $line + $c.Comment + $tail + $c.Reset
}

function Confirm-ChatOne {
    # One match, and the words typed were only part of its title. Deleting on
    # that alone is how 'chatrm Haiku' took 'Haiku ChatGPT Opus Astra' with no
    # prompt at all. Show the whole title and make the answer deliberate.
    param($Item, [string]$Needle)
    $width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 1)
    Write-Host ''
    Write-Host "  '$Needle' is part of this title, not all of it:" -ForegroundColor Yellow
    Write-Host (Format-ChatWalkRow $Item 1 1 $width)

    # No VT means no key loop, and a confirm that only works under VT would
    # leave the weakest hosts deleting unprompted - the bug in a new costume.
    if (-not (Test-ChatVT)) {
        Write-Host ''
        return ((Read-Host "  delete it permanently? (y/N)").Trim() -match '^(y|yes)$')
    }

    $esc = [char]27
    return Invoke-ChatKeyLoop -Paint {
        Write-Host "  delete permanently?  y / Enter = yes,  n / Esc = no$esc[K"
        1
    } -OnKey {
        param($key)
        switch ($key.Key) {
            'Enter' { return @{ Value = $true } }
            'Escape' { return @{ Value = $false } }
        }
        switch ($key.KeyChar) {
            'y' { return @{ Value = $true } }
            'Y' { return @{ Value = $true } }
            'n' { return @{ Value = $false } }
            'N' { return @{ Value = $false } }
            'q' { return @{ Value = $false } }
        }
    }
}

function Select-ChatOne {
    # The same one-line walk Tab does, over the chats a title matched. Enter
    # takes the one on screen and deletes it, with nothing in between.
    param([object[]]$Items)
    $width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 1)
    # one match still shows the line, so all three paths look alike - there is
    # simply nothing to walk. The caller decides whether that one still needs
    # confirming: an exact title does not, a fragment of one does.
    if ($Items.Count -eq 1) {
        Write-Host (Format-ChatWalkRow $Items[0] 1 1 $width)
        return $Items[0]
    }
    if (-not (Test-ChatVT)) { return Select-ChatNumbered $Items -One }

    # no header, no key hints: the counter says there is more than one, and the
    # keys are the ones Tab already walks with
    $esc = [char]27
    # keyed on title AND age, because that pair is all the line shows - only a
    # pair the counter cannot separate earns the project name
    $seen = @{}
    foreach ($it in $Items) {
        $k = "$($it.Record.Title)|$(Get-ChatAge $it.Record.When)"
        $seen[$k] = 1 + $(if ($seen.ContainsKey($k)) { $seen[$k] } else { 0 })
    }
    $s = @{ I = 0 }
    return Invoke-ChatKeyLoop -Paint {
        # no highlight - it is the only line on screen, so nothing needs
        # marking, and an inverse bar the width of the terminal reads far
        # heavier than the plain line Tab leaves behind
        $it = $Items[$s.I]
        $key = "$($it.Record.Title)|$(Get-ChatAge $it.Record.When)"
        $row = Format-ChatWalkRow $it ($s.I + 1) $Items.Count $width -Ambiguous:($seen[$key] -gt 1)
        Write-Host ($row + "$esc[K")
        1
    } -OnKey {
        param($key)
        $last = $Items.Count - 1
        switch ($key.Key) {
            'UpArrow' { $s.I = [Math]::Max(0, $s.I - 1); return }
            'DownArrow' { $s.I = [Math]::Min($last, $s.I + 1); return }
            'Enter' { return @{ Value = $Items[$s.I] } }
            'Escape' { return @{ Value = $null } }
        }
        switch ($key.KeyChar) {
            'k' { $s.I = [Math]::Max(0, $s.I - 1); return }
            'j' { $s.I = [Math]::Min($last, $s.I + 1); return }
            'q' { return @{ Value = $null } }
        }
    }
}

function Select-ChatItems {
    # the same walk, but every chat can be ticked: clearing ghosts is a job you
    # want to finish in one pass
    param([object[]]$Items, [string]$Title = 'Select chats to delete')
    if (-not (Test-ChatVT) -or $Host.Name -notlike '*ConsoleHost*') {
        return Select-ChatNumbered $Items $Title
    }

    $width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 1)
    $window = [Math]::Min(15, $Items.Count)
    $s = @{ I = 0; Top = 0; Picked = New-Object bool[] $Items.Count }

    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host '  up/down move   space toggle   a all   enter delete   esc cancel' -ForegroundColor DarkGray
    return Invoke-ChatKeyLoop -Paint {
        if ($s.I -lt $s.Top) { $s.Top = $s.I }
        if ($s.I -ge $s.Top + $window) { $s.Top = $s.I - $window + 1 }
        for ($n = $s.Top; $n -lt $s.Top + $window; $n++) {
            $mark = if ($s.Picked[$n]) { '[x]' } else { '[ ]' }
            $line = Format-ChatCell "  $mark $(Format-ChatRow $Items[$n])" $width
            if ($n -eq $s.I) { Write-Host $line -ForegroundColor Black -BackgroundColor Cyan }
            else { Write-Host $line }
        }
        $count = @($s.Picked | Where-Object { $_ }).Count
        Write-Host (Format-ChatCell "  $count of $($Items.Count) selected" $width) -ForegroundColor DarkGray
        $window + 1
    } -OnKey {
        param($key)
        $last = $Items.Count - 1
        switch ($key.Key) {
            'UpArrow' { $s.I = [Math]::Max(0, $s.I - 1); return }
            'DownArrow' { $s.I = [Math]::Min($last, $s.I + 1); return }
            'Spacebar' { $s.Picked[$s.I] = -not $s.Picked[$s.I]; return }
            'Enter' { return @{ Value = @(0..$last | Where-Object { $s.Picked[$_] } | ForEach-Object { $Items[$_] }) } }
            'Escape' { return @{ Value = @() } }
        }
        switch ($key.KeyChar) {
            'k' { $s.I = [Math]::Max(0, $s.I - 1); return }
            'j' { $s.I = [Math]::Min($last, $s.I + 1); return }
            'a' {
                $all = @($s.Picked | Where-Object { $_ }).Count -lt $Items.Count
                for ($n = 0; $n -le $last; $n++) { $s.Picked[$n] = $all }
                return
            }
            'q' { return @{ Value = @() } }
        }
    }
}

function Select-ChatNumbered {
    # what both of them fall back to where there is no raw keyboard
    param([object[]]$Items, [string]$Title, [switch]$One)
    Write-Host ''
    if ($Title) { Write-Host "  $Title" -ForegroundColor Cyan }
    $width = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 1)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host (Format-ChatCell ('  {0,2}. {1}' -f ($i + 1), (Format-ChatRow $Items[$i])) $width)
    }
    if ($One) {
        $answer = (Read-Host '  which one? (empty=cancel)').Trim()
        if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $Items.Count) {
            return $Items[[int]$answer - 1]
        }
        return $null
    }
    $answer = Read-Host '  delete which? (1,3-5 / a=all / empty=cancel)'
    if (-not $answer) { return @() }
    if ($answer.Trim() -eq 'a') { return $Items }
    $idx = [System.Collections.Generic.List[int]]::new()
    foreach ($part in ($answer -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') { [int]$Matches[1]..[int]$Matches[2] | ForEach-Object { $idx.Add($_ - 1) } }
        elseif ($part -match '^\d+$') { $idx.Add([int]$part - 1) }
    }
    return @($idx | Sort-Object -Unique | Where-Object { $_ -ge 0 -and $_ -lt $Items.Count } | ForEach-Object { $Items[$_] })
}
function chatrm {
    <#
    .SYNOPSIS
    Delete a local AI chat transcript, permanently.
    .DESCRIPTION
    An id is unambiguous, so it deletes outright. A title can match several
    chats, so those are listed and walked one by one.

    Titles match on substring, so part of a title is a search, not a choice.
    A single match found that way is shown in full and asked about before
    anything goes - and at the prompt, Enter fills the title in the way Tab
    would instead of running, so the whole of it is on screen before a second
    Enter acts on it. A title typed in full deletes as it always did, and
    -Force skips the asking entirely.

    Tab fills in the whole argument - title or id, quoted or not - from the
    index that chatfind keeps warm; run chatindex to rebuild it.
    Also removes what the transcript leaves behind - sidecars, file-history and
    session-env for Claude, chatEditingSessions for Copilot.
    .PARAMETER Target
    One or more ids (prefixes are fine), or a chat title.
    .PARAMETER Provider
    Limit to claude, copilot or codex. Defaults to all of them.
    .PARAMETER Force
    Skip the confirmation prompts in title mode.
    .PARAMETER AllProjects
    Match titles from every project rather than the one this directory belongs
    to. Ids are unambiguous and always reach any project.
    .PARAMETER WaitForIdle
    Wait after deleting until nothing in this project's chats has been written
    for a minute, then say the window is safe to reload. A reload restarts the
    extensions, so one taken mid-answer loses that answer. It blocks the shell
    while it waits; Ctrl+C stops it and deletes nothing back.
    .PARAMETER DropJobs
    A chat with a prompt queued for it by chatq is kept, and the job named.
    -DropJobs drops those jobs first - cancelling one that is running and
    waiting for it to stop - and then deletes.
    .EXAMPLE
    chatrm 44e899d3
    .EXAMPLE
    chatrm "Review uncommitted changes"
    .LINK
    chatfind
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Target,
        [string[]]$Provider,
        [switch]$Force,
        [switch]$AllProjects,
        [switch]$WaitForIdle,
        [switch]$DropJobs
    )
    Set-StrictMode -Off

    if (-not $Target) { Write-Error 'usage: chatrm <id>... | "<title>" [-Force] [-AllProjects] [-WaitForIdle] [-DropJobs]'; return }
    $names = if ($Provider) { $Provider } else { @($script:ChatProviders.Keys) }
    $deleted = 0
    $lastTitle = ''
    $byId = -not ($Target | Where-Object { $_ -notmatch '^[0-9a-fA-F]{6,}(-[0-9a-fA-F-]*)?$' })

    # ids are not scoped to the project: an id names exactly one chat, so there
    # is nothing for the current directory to disambiguate
    if ($byId) {
        foreach ($id in $Target) {
            $found = $false
            foreach ($name in $names) {
                $p = $script:ChatProviders[$name]
                if (-not $p) { continue }
                foreach ($file in @(& $p.Discover)) {
                    # substring, not prefix: Codex buries the uuid after a timestamp
                    if ($file.BaseName -notlike "*$id*") { continue }
                    $rec = & $p.Describe $file
                    if (-not $rec) { continue }
                    $hit = [pscustomobject]@{ Provider = $name; File = $file; Record = $rec }
                    $found = $true
                    if (Test-ChatJobsHold $hit -DropJobs:$DropJobs) { continue }
                    if (Remove-ChatSession $hit) { $deleted++; $lastTitle = $hit.Record.Title }
                }
            }
            if (-not $found) { Write-Warning "no transcript for $id - already deleted, or wrong id" }
        }
    }
    else {
        $needle = $Target -join ' '
        $matched = @(Find-ChatSessions -Needle $needle -Provider $Provider -TitleOnly -AllProjects:$AllProjects)
        if (-not $matched) {
            $where = if ($AllProjects) { '' } else { ' here - add -AllProjects to look wider' }
            Write-Warning "no chat titled like '$needle'$where"
            return
        }

        # Titles match on substring, so one hit does NOT mean the right hit:
        # 'Haiku' matched 'Haiku ChatGPT Opus Astra' and, with a single match
        # taken as consent, deleted it outright. Typing a whole title is a
        # decision; typing a fragment is a search, and a search must not delete.
        $exact = $matched.Count -eq 1 -and
        $matched[0].Record.Title.Equals($needle, [StringComparison]::OrdinalIgnoreCase)

        $chosen = if ($Force) { $matched }
        elseif ($matched.Count -eq 1 -and -not $exact) {
            # the one guard that also covers scripts, -NoProfile and no-VT
            # hosts, where no key handler exists to fill the title in first
            if (Confirm-ChatOne $matched[0] $needle) { @($matched[0]) } else { @() }
        }
        else {
            $one = Select-ChatOne $matched
            if ($one) { @($one) } else { @() }
        }

        if (-not $chosen) { Write-Host 'nothing deleted'; return }
        foreach ($m in $chosen) {
            # already shown once - by the confirm above, or by the picker list
            if (Test-ChatJobsHold $m -DropJobs:$DropJobs) { continue }
            if (Remove-ChatSession $m) { $deleted++; $lastTitle = $m.Record.Title }
        }
    }

    if ($deleted) {
        $what = if ($deleted -eq 1) { $lastTitle } else { "$deleted chats" }
        Write-ChatGhostAdvice -WaitForIdle:$WaitForIdle -AllProjects:$AllProjects -Title $what
    }
}

#endregion

#region discoverability -------------------------------------------------------

function Compare-ChatVersion {
    # -1 A older, 0 same, 1 A newer, $null if either side will not parse.
    # $null is not "equal" - a stamp written by hand, or by some future format,
    # has to read as a change rather than silently as "unchanged".
    param([string]$A, [string]$B)
    $pa = $null
    $pb = $null
    if (-not [version]::TryParse($A, [ref]$pa)) { return $null }
    if (-not [version]::TryParse($B, [ref]$pb)) { return $null }
    return $pa.CompareTo($pb)
}

# Any profile line that loads this file under a name it has had, or loads one
# of the two tools it replaced - chatrm and chatq define the same commands.
$script:ChatProfilePattern = '(chatrm|deleteLocalChat|chatq|VS-code-chat-manager)\.ps1'

function chatinstall {
    <#
    .SYNOPSIS
    Add this script to your PowerShell profile, so the chat commands are there in
    every new shell. Dot-source the file once, then run chatinstall.
    .DESCRIPTION
    Writes the dot-source line into $PROFILE, creating the profile if there is
    none, and backing it up to $PROFILE.bak first. The script knows where it is,
    so no path has to be typed twice. A line left behind by an older copy is
    replaced rather than left to load nothing - run this again after moving the
    file.
    .PARAMETER Force
    Rewrite the line even when it is already there.
    .EXAMPLE
    . C:\tools\VS-code-chat-manager\VS-code-chat-manager.ps1
    chatinstall
    #>
    [CmdletBinding()]
    param([switch]$Force)
    Set-StrictMode -Off

    $me = $PSCommandPath
    if (-not $me) {
        Write-Host '  cannot tell where this file is' -ForegroundColor Yellow
        Write-Host '  dot-source it by path first:  . C:\path\to\VS-code-chat-manager.ps1' -ForegroundColor DarkGray
        return
    }
    # only Windows marks downloads; elsewhere the cmdlet does not exist at all
    if (Get-Command Unblock-File -EA SilentlyContinue) { Unblock-File -LiteralPath $me -EA SilentlyContinue }

    # read before anything is written: data/ outlives the .ps1 an update
    # overwrites, so this is the only trace of which copy was here before
    $was = $null
    if (Test-Path -LiteralPath $script:ChatVersionPath) {
        $was = Get-Content -LiteralPath $script:ChatVersionPath -TotalCount 1 -EA SilentlyContinue
        if ($was) { $was = $was.Trim() }
    }

    $dir = Split-Path $PROFILE -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = if (Test-Path -LiteralPath $PROFILE) { @(Get-Content -LiteralPath $PROFILE) } else { @() }

    # every name this file has had: deleteLocalChat.ps1, then chatrm.ps1, and
    # chatq.ps1 for the queue half. A profile still holding one of those lines
    # has to be repaired, not added to - and both chatrm and chatq loaded next
    # to this one would redefine the same commands
    $mine = @($lines | Where-Object { $_ -match $script:ChatProfilePattern })
    # IndexOf, not -like: a path is not a wildcard pattern, and one containing
    # [ or ] would never match itself - appending a second line every run
    $here = @($mine | Where-Object { $_.IndexOf($me, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($here -and -not $Force) {
        # Deliberately not a return: a reinstall still has to reach the index
        # check below. Bailing out here meant that deleting data/ and re-running
        # the installer left Tab with nothing to complete from, which is the
        # exact failure this was added to prevent.
        Write-Host '  already installed' -ForegroundColor DarkGray
        Write-Host "    $PROFILE" -ForegroundColor DarkGray
        Write-Host '    the script itself was just overwritten with this copy' -ForegroundColor DarkGray
    }
    else {
        # the whole file is rewritten to drop a stale line, so keep a copy: this
        # is the user's profile and may hold plenty unrelated to us
        if (Test-Path -LiteralPath $PROFILE) { Copy-Item -LiteralPath $PROFILE -Destination "$PROFILE.bak" -Force }
        $kept = @($lines | Where-Object { $_ -notmatch $script:ChatProfilePattern })
        $kept += ". `"$me`""
        Set-Content -LiteralPath $PROFILE -Value $kept -Encoding UTF8

        Write-Host '  installed' -ForegroundColor Green
        Write-Host "    $PROFILE"
        # only the lines that pointed somewhere else were really replaced - counting
        # the current one too claimed "from an older location" on a plain -Force rerun
        $stale = $mine.Count - $here.Count
        if ($stale -gt 0) {
            Write-Host "    replaced $stale line$(if ($stale -ne 1) { 's' }) from an older location" -ForegroundColor DarkGray
        }
        # Reaching this line means the file was dot-sourced - $PSCommandPath is
        # empty otherwise and it returns above - so the commands are already
        # defined right here. Saying "open a new terminal" sent people off to
        # reopen a shell that was already working.
        Write-Host '    ready in this shell - type chat' -ForegroundColor Green
        Write-Host '    every new shell picks it up from now on' -ForegroundColor DarkGray
    }

    # Both branches print this. "installed" on its own cannot tell a real upgrade
    # from the CDN handing back the copy you already had, which it does for
    # minutes after a push - so say which of the two just happened.
    if (-not $was) {
        Write-Host "    version $script:ChatVersion" -ForegroundColor DarkGray
    }
    elseif ($was -eq $script:ChatVersion) {
        Write-Host "    version $script:ChatVersion - unchanged" -ForegroundColor DarkGray
    }
    elseif ((Compare-ChatVersion $was $script:ChatVersion) -eq 1) {
        Write-Host "    DOWNGRADED $was -> $script:ChatVersion" -ForegroundColor Yellow
        Write-Host '    an older copy just overwrote a newer one' -ForegroundColor Yellow
    }
    else {
        Write-Host "    updated $was -> $script:ChatVersion" -ForegroundColor Green
    }

    # Either path, first install or reinstall. Tab reads the index and never
    # builds it - a keypress cannot afford 30s - so anything that removed data/
    # left nothing to complete from until some search happened to run.
    if (-not (Test-Path -LiteralPath $script:ChatIndexPath)) {
        Write-Host '    building the index for Tab completion (~30s)...' -ForegroundColor DarkGray
        # never let this fail the install - the index rebuilds on any search
        try {
            $n = @(Sync-ChatIndex).Count
            Write-Host "    indexed $n chat$(if ($n -ne 1) { 's' })" -ForegroundColor DarkGray
        }
        catch {
            Write-Host '    could not build it - run chatindex when convenient' -ForegroundColor Yellow
        }
    }

    # the queue half needs a CLI to resume chats with; finding and deleting do not
    if (-not (Find-ChatqExe claude) -and -not (Find-ChatqExe codex)) {
        Write-Host '    no claude or codex CLI found - chatq needs one, or CHATQ_CLAUDE / CHATQ_CODEX' -ForegroundColor Yellow
    }

    # The extension defaults to ~/Tools/VS-code-chat-manager/data/reload-request.
    # Anywhere else needs the setting, and without it the reload prompt simply
    # never appears - a silence that looks like the extension being broken.
    $defaultReload = Join-Path (Join-Path (Join-Path (Join-Path $HOME 'Tools') 'VS-code-chat-manager') 'data') 'reload-request'
    if ($script:ChatReloadPath -ne $defaultReload) {
        Write-Host '    using extension/? set chatManagerReload.signalFile to' -ForegroundColor DarkGray
        Write-Host "      $($script:ChatReloadPath)" -ForegroundColor DarkGray
    }

    # last, so a run that died earlier leaves the old stamp alone and the next
    # one still reports the real delta rather than comparing against a version
    # that never finished installing
    try {
        $vdir = Split-Path $script:ChatVersionPath -Parent
        if ($vdir -and -not (Test-Path -LiteralPath $vdir)) {
            New-Item -ItemType Directory -Path $vdir -Force | Out-Null
        }
        Set-Content -LiteralPath $script:ChatVersionPath -Value $script:ChatVersion -Encoding UTF8
    }
    catch {}
}

function chatuninstall {
    <#
    .SYNOPSIS
    Take the chat commands back out of your PowerShell profile.
    .DESCRIPTION
    Drops the dot-source line from $PROFILE, backing it up to $PROFILE.bak first,
    and leaves everything else in that file alone. Matches the old filename too,
    so a profile still carrying a deleteLocalChat line is cleaned as well.

    The commands stay defined in the shell you run this from - they are already
    in memory, and nothing can unload them. Close it and they are gone.

    The folder is left on disk by default, data/ and all, since it holds the
    index, the tombstones and any queued prompts. -All deletes it too.
    .PARAMETER All
    Also delete the script's own folder, including data/ and every queued
    prompt in it.
    .EXAMPLE
    chatuninstall
    .EXAMPLE
    chatuninstall -All
    #>
    [CmdletBinding()]
    param([switch]$All)
    Set-StrictMode -Off

    # a live watcher outlasts the file it was started for, so stop it first -
    # the ghost watch in this shell, and chatq's background one
    Stop-ChatGhostWatch
    $pending = @(Get-ChatqJobs | Where-Object { $_.state -in 'queued', 'running' })
    if ($pending) {
        Write-Host "  $($pending.Count) job$(if ($pending.Count -ne 1) { 's' }) still queued - they will not be sent" -ForegroundColor Yellow
    }
    if (Test-ChatqWatcherAlive) {
        Save-ChatqText $script:ChatqStopPath 'stop'
        for ($i = 0; $i -lt 40 -and (Test-ChatqWatcherAlive); $i++) { Start-Sleep -Milliseconds 250 }
        Write-Host '  stopped the watcher' -ForegroundColor DarkGray
    }

    $lines = if (Test-Path -LiteralPath $PROFILE) { @(Get-Content -LiteralPath $PROFILE) } else { @() }
    $mine = @($lines | Where-Object { $_ -match $script:ChatProfilePattern })
    if ($mine.Count) {
        Copy-Item -LiteralPath $PROFILE -Destination "$PROFILE.bak" -Force
        Set-Content -LiteralPath $PROFILE -Encoding UTF8 -Value `
        @($lines | Where-Object { $_ -notmatch $script:ChatProfilePattern })
        Write-Host "  removed $($mine.Count) line$(if ($mine.Count -ne 1) { 's' }) from the profile" -ForegroundColor Green
        Write-Host "    $PROFILE" -ForegroundColor DarkGray
        Write-Host "    backup: $PROFILE.bak" -ForegroundColor DarkGray
    }
    else {
        Write-Host '  nothing in the profile to remove' -ForegroundColor DarkGray
    }

    $here = if ($PSCommandPath) { Split-Path $PSCommandPath -Parent } else { $null }
    if ($All) {
        if (-not $here) {
            Write-Host '  cannot tell where this file is - delete the folder by hand' -ForegroundColor Yellow
        }
        else {
            # the .ps1 is not held open once dot-sourced, so it can delete itself
            Remove-Item -LiteralPath $here -Recurse -Force -EA SilentlyContinue
            $gone = -not (Test-Path -LiteralPath $here)
            Write-Host "  $(if ($gone) { 'deleted' } else { 'COULD NOT DELETE' })  $here" -ForegroundColor $(if ($gone) { 'Green' } else { 'Yellow' })
            if (-not $gone) { Write-Host '    something in it is open elsewhere' -ForegroundColor DarkGray }
        }
    }
    elseif ($here) {
        Write-Host "  the folder is still there - delete it when you want to:" -ForegroundColor DarkGray
        Write-Host "      Remove-Item -LiteralPath `"$here`" -Recurse -Force" -ForegroundColor Cyan
    }

    Write-Host '  these commands stay in this shell until you close it' -ForegroundColor DarkGray
}

function chat {
    <#
    .SYNOPSIS
    Cheat sheet for the chat commands. Type chat<Tab> to cycle through them.
    #>
    Set-StrictMode -Off
    Write-Host ''
    Write-Host '  find and delete' -ForegroundColor DarkGray
    Write-Host '  chatfind "text"        find chats by title or message' -ForegroundColor Cyan
    Write-Host '  chatrm <id> | "title"  delete a chat, permanently' -ForegroundColor Cyan
    Write-Host '  chatclean              delete ghost chats left by the VS Code list' -ForegroundColor Cyan
    Write-Host '  chatproviders          which tools were found, and where' -ForegroundColor Cyan
    Write-Host '  chatindex              rebuild the tab-completion index' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  queue prompts for when the usage limit resets' -ForegroundColor DarkGray
    Write-Host '  chatq "title" [-Prompt s]  queue a prompt for that chat' -ForegroundColor Cyan
    Write-Host '  chatqlist [-Board]     what is queued, when it sends, what ran' -ForegroundColor Cyan
    Write-Host '  chatqrm / chatqrun     drop a job / requeue one, or -Now' -ForegroundColor Cyan
    Write-Host '  chatqlog / chatqnotify what a run did / phone alerts' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  chatinstall            load these in every new shell (once)' -ForegroundColor DarkGray
    Write-Host '  chatuninstall [-All]   undo that; -All removes the folder too' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Tab fills in the argument: type any part of a title, no quotes needed'
    Write-Host '  -Provider claude|copilot|codex   -Deep   -All   -AllProjects   -Force'
    Write-Host '  Get-Help chatfind -Full           full help, examples and notes'
    Write-Host ''
    Write-Host "  VS-code-chat-manager $script:ChatVersion" -ForegroundColor DarkGray
    Write-Host "  $PSCommandPath" -ForegroundColor DarkGray
    Write-Host ''
}

# verb-noun aliases so Get-Command *-Chat* and Find-<Tab> surface these too
Set-Alias -Name Find-Chat -Value chatfind -Scope Global -Force
Set-Alias -Name Remove-Chat -Value chatrm -Scope Global -Force
Set-Alias -Name Get-ChatProvider -Value chatproviders -Scope Global -Force
Set-Alias -Name Update-ChatIndex -Value chatindex -Scope Global -Force

Register-ArgumentCompleter -CommandName chatfind, chatrm, chatindex -ParameterName Provider -ScriptBlock {
    param($cmd, $param, $word)
    @('claude', 'copilot', 'codex') | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

function Get-ChatCells {
    # width in console cells, not characters: Hangul and CJK draw two cells
    # each, so String.Length leaves a column of Korean titles ragged
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

function Format-ChatCell {
    # clip to exactly $Cells console cells, padding short text out to the same
    # unless -NoPad, which callers use when they are joining pieces themselves
    param([string]$Text, [int]$Cells, [switch]$NoPad)
    # a narrow terminal can hand in zero or less, and ' ' * -1 throws
    if ($Cells -le 0) { return '' }
    $w = Get-ChatCells $Text
    if ($w -le $Cells) {
        if ($NoPad) { return $Text }
        return $Text + (' ' * ($Cells - $w))
    }
    # three ASCII dots, not U+2026: the ellipsis and the middle dot draw two
    # cells wide in a CP949 console, which throws off every in-place redraw
    if ($Cells -le 3) { return '.' * $Cells }
    # one character at a time rather than re-measuring a growing prefix
    $len = 0
    $used = 0
    while ($len -lt $Text.Length) {
        $cw = Get-ChatCells $Text.Substring($len, 1)
        if ($used + $cw -gt $Cells - 3) { break }
        $used += $cw
        $len++
    }
    $out = $Text.Substring(0, $len) + '...'
    if ($NoPad) { return $out }
    return $out + (' ' * [Math]::Max(0, $Cells - $used - 3))
}

function Get-ChatSyntaxColor {
    # PSReadLine's own colours, read from the live options rather than guessed,
    # so the walked line is painted exactly like the line Tab writes into the
    # buffer - and follows the user's theme if they changed it
    if ($script:ChatColors) { return $script:ChatColors }
    $esc = [char]27
    $c = @{
        Command = "$esc[93m"; String = "$esc[36m"
        Param   = "$esc[90m"; Comment = "$esc[32m"; Reset = "$esc[0m"
    }
    $o = try { Get-PSReadLineOption -EA Stop } catch { $null }
    if ($o) {
        if ($o.CommandColor) { $c.Command = $o.CommandColor }
        if ($o.StringColor) { $c.String = $o.StringColor }
        if ($o.ParameterColor) { $c.Param = $o.ParameterColor }
        if ($o.CommentColor) { $c.Comment = $o.CommentColor }
    }
    $script:ChatColors = $c
    return $c
}

function Format-ChatMenuRow {
    # One menu row: title, owner, age, opening prompt. PSReadLine 2.0 draws no
    # tooltip, so this line is the whole preview. Fixed columns rather than
    # free text - run together, the rows read as one paragraph.
    param($Row, [int]$Extra = 0)
    $when = try {
        Get-ChatAge ([datetime]::Parse($Row.When, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind))
    }
    catch { '?' }
    $tag = if ($Extra) { "[$Extra chats $when]" } else { "[$($Row.Provider) $when]" }

    $total = [Math]::Max(24, $Host.UI.RawUI.WindowSize.Width - 4)
    $tagCells = 15
    $titleCells = [Math]::Max(12, [Math]::Min(44, [int]($total * 0.42)))
    $rest = $total - $titleCells - $tagCells - 2
    if ($rest -lt 12) {
        # too narrow for an excerpt - give the space back to the title
        $titleCells = [Math]::Max(8, $total - $tagCells - 1)
        $rest = 0
    }

    $text = (Format-ChatCell $Row.Title $titleCells) + ' ' + (Format-ChatCell $tag $tagCells)
    $first = @($Row.First)[0]
    if ($rest -and $first) {
        $text += ' ' + (Format-ChatCell ('> ' + ($first -replace '\s+', ' ')) $rest)
    }
    return $text
}

function Get-ChatCompletionPreview {
    # the multi-line tooltip - shown by Ctrl+Space and PSReadLine 2.2+
    param($Row, [int]$Extra = 0)
    $when = try {
        Get-ChatAge ([datetime]::Parse($Row.When, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind))
    }
    catch { '?' }
    $lines = @("$($Row.Title)", "$($Row.Provider) / $($Row.Group) / $when")
    if ($Extra) { $lines += "$Extra chats share this title - you pick from a list" }
    $clip = { param($t) if ($t.Length -gt 76) { $t.Substring(0, 76) + '...' } else { $t } }
    foreach ($m in @($Row.First) | Select-Object -First 2) { $lines += '  > ' + (& $clip $m) }
    $tail = @($Row.Last)
    if ($tail -and (@($Row.First) -join "`n") -ne ($tail -join "`n")) {
        $lines += '  ...'
        $lines += '  > ' + (& $clip $tail[-1])
    }
    return ($lines -join "`n")
}

$script:ChatTitleCompleter = {
    # One completer for chatrm, chatfind and chatq. All five parameters, because
    # the last one - the switches already typed - is how -All and -AllProjects
    # reach it; with three, Tab offered what the command then refused to match.
    param($cmd, $param, $word, $ast, $bound)
    Set-StrictMode -Off
    $w = ([string]$word).Trim('"', "'")
    $queue = $cmd -eq 'chatq'
    # chatq 3 means job 3 - a number is not the start of a title
    if ($queue -and $w -match '^\d{1,4}$') { return }
    $all = $bound -and [bool]$bound['All']
    $wide = $bound -and [bool]$bound['AllProjects']
    # (empty) are abandoned sessions; Hidden ones are subagents, which the
    # search skips without -All, so Tab must not offer them either
    $rows = @(Get-ChatIndex | Where-Object { $_.Title -ne '(empty)' -and ($all -or -not $_.Hidden) })
    # a queued prompt needs a CLI to resume the chat, and Copilot has none
    if ($queue) { $rows = @($rows | Where-Object { $_.Provider -in 'claude', 'codex' }) }
    if (-not $rows) {
        # Hand back what was typed, never ''. CompletionText REPLACES the word,
        # so returning '' wiped the argument and left a bare pair of quotes on
        # the line - it read as a broken completer rather than an empty index.
        # Echoing the word leaves the line alone; the hint rides in the tooltip.
        return [System.Management.Automation.CompletionResult]::new(
            $word, 'no index yet - run chatindex', 'ParameterValue',
            'No index yet - run chatindex once (~30s), or any chatfind')
    }

    # hex looks like an id - and ids are never scoped, one id is one chat. A
    # title can start with hex letters too ('add', 'cafe'), so no id match
    # falls through to titles rather than completing nothing.
    if ($w -match '^[0-9a-fA-F]{2,}$') {
        $ids = @($rows | Where-Object { $_.Id -like "$w*" })
        if ($ids) {
            return $ids | Sort-Object When -Descending | Select-Object -First 25 | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Id, (Format-ChatMenuRow $_), 'ParameterValue',
                    (Get-ChatCompletionPreview $_))
            }
        }
    }

    # titles are scoped like the search is
    $rows = @(Select-ChatInProject $rows -AllProjects:$wide)
    $starts = @($rows | Where-Object { -not $w -or $_.Title.StartsWith($w, [StringComparison]::OrdinalIgnoreCase) })
    if (-not $starts -and $w) {
        $starts = @($rows | Where-Object { $_.Title.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    }
    $starts |
        Group-Object Title | ForEach-Object {
            $newest = ($_.Group | Sort-Object When -Descending)[0]
            $extra = if ($_.Count -gt 1) { $_.Count } else { 0 }
            [pscustomobject]@{
                Title = $_.Name; When = $newest.When
                Label = Format-ChatMenuRow $newest $extra
                Tip   = Get-ChatCompletionPreview $newest $extra
            }
        } |
        Sort-Object When -Descending | Select-Object -First 25 | ForEach-Object {
            # single quotes: titles carry apostrophes, $ and braces that would
            # otherwise be interpreted when the line is run - and every quote
            # PowerShell treats as one is doubled, typographic ones included
            $quoted = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_.Title) + "'"
            [System.Management.Automation.CompletionResult]::new($quoted, $_.Label, 'ParameterValue', $_.Tip)
        }
}

# the same titles for all three, under their own parameter names
Register-ArgumentCompleter -CommandName chatrm -ParameterName Target -ScriptBlock $script:ChatTitleCompleter
Register-ArgumentCompleter -CommandName chatfind -ParameterName Text -ScriptBlock $script:ChatTitleCompleter
Register-ArgumentCompleter -CommandName chatq -ParameterName Target -ScriptBlock $script:ChatTitleCompleter

# ---------------------------- the one-line cycler ----------------------------
# Tab does not open a list, and does not complete the word under the cursor. It
# replaces the whole argument with one chat and describes it on the same line,
# in a trailing comment PowerShell ignores; arrows walk to the next one.
# It has to work this way: a preview pane of our own would have to read the
# arrow keys itself, and inside a key handler PSReadLine's key reader is
# already blocked on the console waiting for them - the two race and the pane
# never gets a keystroke. Rewriting the buffer needs no keyboard at all.

$script:ChatCycle = $null

function Get-ChatCycleRows {
    # candidates for the cycler: ids if it looks like one, else titles,
    # prefix first and only then widening to a contains-match
    param([string]$Filter, [ref]$ById, [switch]$Queue)
    # scoped like the search is: offering a chat from another project that
    # chatrm would then refuse to match is worse than offering nothing. Hidden
    # rows (subagents) too, which the search skips without -All.
    $all = @(Get-ChatIndex | Where-Object { $_.Title -ne '(empty)' -and -not $_.Hidden })
    # chatq can only resume what a CLI can: no Copilot
    if ($Queue) { $all = @($all | Where-Object { $_.Provider -in 'claude', 'codex' }) }
    $all = @(Select-ChatInProject $all)
    if ($Filter -match '^[0-9a-fA-F]{2,}$') {
        $hit = @($all | Where-Object { $_.Id -like "$Filter*" })
        if ($hit) {
            $ById.Value = $true
            return @($hit | Sort-Object When -Descending | Select-Object -First 40)
        }
    }
    $ById.Value = $false
    $rows = @($all | Where-Object { -not $Filter -or $_.Title.StartsWith($Filter, [StringComparison]::OrdinalIgnoreCase) })
    if (-not $rows -and $Filter) {
        $rows = @($all | Where-Object { $_.Title.IndexOf($Filter, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    }
    # one entry per title - chatrm sorts out duplicates itself, with its own list
    $uniq = $rows | Group-Object Title | ForEach-Object { ($_.Group | Sort-Object When -Descending)[0] }
    return @($uniq | Sort-Object When -Descending | Select-Object -First 40)
}

function Get-ChatRowAge {
    # The cycler runs off the cached index, which is only as fresh as the last
    # chatfind or chatrm - it read 2h for a chat the panel called 32m, because
    # the chat had grown 1.1 MB since the index was written. Only one row is
    # ever on screen, so re-read that one when its file has moved. The walk
    # after Enter needs none of this: Find-ChatSessions syncs first.
    param($Row)
    $when = try {
        [datetime]::Parse($Row.When, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch { $null }
    $f = Get-Item -LiteralPath $Row.Path -EA SilentlyContinue
    if ($f -and ($f.Length -ne $Row.Size -or $f.LastWriteTimeUtc.Ticks -ne $Row.Mtime)) {
        $name = Get-ChatProviderForPath $Row.Path
        $rec = if ($name) { & $script:ChatProviders[$name].Describe $f } else { $null }
        if ($rec) { $when = $rec.When }
    }
    if ($when) { return Get-ChatAge $when }
    return ''
}

function Set-ChatCycleLine {
    # move by $Step through the run and rewrite the whole buffer
    param([int]$Step)
    $c = $script:ChatCycle
    $c.Index = ($c.Index + $Step) % $c.Items.Count
    if ($c.Index -lt 0) { $c.Index += $c.Items.Count }
    $row = $c.Items[$c.Index]

    $pick = if ($c.ById) { $row.Id } else { "'" + $row.Title.Replace("'", "''") + "'" }
    $head = $c.Head + $pick
    # once per chat per run: re-reading a growing transcript costs ~300ms, and
    # arrowing back and forth would pay it again every time
    if (-not $c.Ages.ContainsKey($row.Path)) { $c.Ages[$row.Path] = Get-ChatRowAge $row }
    # the same tail the walk shows, so both look like one another
    $line = $head + (Format-ChatPickTail $c.Ages[$row.Path] ($c.Index + 1) $c.Items.Count)

    $cur = $null; $pos = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$cur, [ref]$pos)
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $cur.Length, $line)
    # leave the cursor on the chat, not out in the comment
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($head.Length)
    $c.Line = $line
}

function Test-ChatCycling {
    # still on the line we wrote last time?
    param([string]$Line)
    $script:ChatCycle -and $script:ChatCycle.Line -eq $Line
}

function Test-ChatPartialTarget {
    # Is what was typed part of a title rather than all of it? Enter fills the
    # match in instead of running when it is, so the whole title is on screen
    # before anything acts on it. Every uncertain answer is $false: Enter then
    # keeps its ordinary meaning, and chatrm's own confirm still stands behind.
    param([string]$Line)
    try {
        $m = [regex]::Match($Line, '^\s*chatrm\s+')
        if (-not $m.Success) { return $false }
        $arg = ($Line.Substring($m.Length) -replace $script:ChatTailPattern, '').Trim()
        if (-not $arg) { return $false }
        # a switch means this is not a bare title, and -Force is a decision
        # already made - neither should have Enter quietly do something else
        if ($arg -match '(^|\s)-\w') { return $false }
        $arg = $arg.Trim("'", '"').Trim()
        if (-not $arg) { return $false }
        # an id is exact by definition, and never scoped to a project
        if ($arg -match '^[0-9a-fA-F]{6,}(-[0-9a-fA-F-]*)?$') { return $false }
        if (-not (Test-Path -LiteralPath $script:ChatIndexPath)) { return $false }

        $rows = @(Select-ChatInProject @(Get-ChatIndex | Where-Object { $_.Title -ne '(empty)' -and -not $_.Hidden }))
        if (-not $rows) { return $false }
        # a title typed in full is a decision, however many others contain it
        foreach ($r in $rows) {
            if ($r.Title.Equals($arg, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        foreach ($r in $rows) {
            if ($r.Title.IndexOf($arg, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
        return $false
    }
    catch { return $false }
}

function Start-ChatCycle {
    # begin a run from whatever has been typed after the command
    param([string]$Line)
    $m = [regex]::Match($Line, '^\s*chat(rm|find|q)\s+')
    if (-not $m.Success) { return $false }
    $queue = $m.Groups[1].Value -eq 'q'
    $arg = $Line.Substring($m.Length)
    # everything after the command is the filter, spaces and quotes included - a
    # quote the user opened is dropped here and Set-ChatCycleLine puts single
    # ones back, so typing one neither helps the match nor breaks it
    $arg = ($arg -replace $script:ChatTailPattern, '').Trim().Trim("'", '"').Trim()
    if ($arg.StartsWith('-')) { return $false }        # a parameter, not a title
    # chatq 3 is job 3, and chatq 'title' -Prompt ... is past the title already
    if ($queue -and ($arg -match '^\d{1,4}$' -or $arg -match '\s-\w')) { return $false }
    $byId = $false
    # an absent index is not the same as no match, and silence made the two look
    # identical - the caller says so rather than leaving Tab looking broken
    if (-not (Test-Path -LiteralPath $script:ChatIndexPath)) {
        $script:ChatNoIndex = $true
        return $false
    }
    $script:ChatNoIndex = $false
    $rows = @(Get-ChatCycleRows $arg ([ref]$byId) -Queue:$queue)
    if (-not $rows) { return $false }
    $script:ChatCycle = @{
        Head  = $Line.Substring(0, $m.Length)
        Items = $rows
        Index = -1
        ById  = $byId
        Line  = ''
        Ages  = @{}
    }
    Set-ChatCycleLine 1
    return $true
}

# Tab starts or advances the run, Shift+Tab steps back, and the arrows do the
# same but only while a run is live - otherwise they stay history navigation.
# Opt out with $ChatNoKeyBindings = $true before the dot-source line. Read
# through Get-Variable: under StrictMode an unset one throws, and every shell
# start would lose its key handlers. Never in the background watcher, which
# has no keyboard, nor anywhere else not interactive.
if (-not (Get-Variable -Name ChatNoKeyBindings -ValueOnly -EA SilentlyContinue) -and
    -not $env:CHATQ_WATCHER -and [Environment]::UserInteractive -and
    (Get-Module PSReadLine -ListAvailable -EA SilentlyContinue)) {
    try {
        Import-Module PSReadLine -EA Stop

        # remember what the arrows did before we took them over
        $script:ChatArrowWas = @{}
        foreach ($k in 'UpArrow', 'DownArrow') {
            $bound = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq $k }
            $script:ChatArrowWas[$k] = if ($bound) { $bound.Function } else { $null }
        }

        function Invoke-ChatPSReadLine {
            # call a PSReadLine action by name, so the arrows keep doing
            # whatever they were bound to before this file was loaded
            param([string]$Name, [string]$Fallback)
            if (-not $Name) { $Name = $Fallback }
            $mi = [Microsoft.PowerShell.PSConsoleReadLine].GetMethod(
                $Name, [type[]]@([System.Nullable[System.ConsoleKeyInfo]], [object]))
            if (-not $mi) {
                $mi = [Microsoft.PowerShell.PSConsoleReadLine].GetMethod(
                    $Fallback, [type[]]@([System.Nullable[System.ConsoleKeyInfo]], [object]))
            }
            if ($mi) { [void]$mi.Invoke($null, @($null, $null)) }
        }

        Set-PSReadLineKeyHandler -Key Tab -BriefDescription 'ChatCycleNext' `
            -Description 'Fill in the next matching chat, described in a trailing comment' -ScriptBlock {
            Set-StrictMode -Off
            $line = $null; $pos = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$pos)
            if (Test-ChatCycling $line) { Set-ChatCycleLine 1; return }
            $script:ChatCycle = $null
            if (-not (Start-ChatCycle $line)) {
                # No index at all is worth saying out loud. Falling through to
                # TabCompleteNext here is what put a bare '' on the line and made
                # an empty index look like a broken completer.
                if ($script:ChatNoIndex) {
                    try {
                        [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($null)
                    }
                    catch {}
                    Write-Host ''
                    Write-Host '  no index yet - run chatindex once (~30s)' -ForegroundColor Yellow
                    # redraw, or the line is left sitting under what was printed
                    try { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() } catch {}
                    return
                }
                [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext()
            }
        }

        Set-PSReadLineKeyHandler -Key Shift+Tab -BriefDescription 'ChatCyclePrev' `
            -Description 'Step back through the matching chats' -ScriptBlock {
            Set-StrictMode -Off
            $line = $null; $pos = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$pos)
            if (Test-ChatCycling $line) { Set-ChatCycleLine -1; return }
            [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious()
        }

        Set-PSReadLineKeyHandler -Key DownArrow -BriefDescription 'ChatCycleOrHistory' `
            -Description 'Next matching chat while cycling, history otherwise' -ScriptBlock {
            Set-StrictMode -Off
            $line = $null; $pos = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$pos)
            if (Test-ChatCycling $line) { Set-ChatCycleLine 1; return }
            Invoke-ChatPSReadLine $script:ChatArrowWas['DownArrow'] 'NextHistory'
        }

        Set-PSReadLineKeyHandler -Key UpArrow -BriefDescription 'ChatCycleOrHistory' `
            -Description 'Previous matching chat while cycling, history otherwise' -ScriptBlock {
            Set-StrictMode -Off
            $line = $null; $pos = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$pos)
            if (Test-ChatCycling $line) { Set-ChatCycleLine -1; return }
            Invoke-ChatPSReadLine $script:ChatArrowWas['UpArrow'] 'PreviousHistory'
        }

        Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'ChatAcceptLine' `
            -Description 'Drop the age and counter, then run the line' -ScriptBlock {
            Set-StrictMode -Off
            $line = $null; $pos = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$pos)
            # not only while cycling: the tail survives an edit, and left on the
            # line "(5d)" would be run as an expression rather than ignored
            if ($line -match '^\s*chat(rm|find|q)\s') {
                $clean = $line -replace $script:ChatTailPattern, ''
                # chatq goes on past the title (-Prompt ...). The cursor is left
                # before the tail, but text typed after it would put -Prompt in
                # the comment and leave "(5d)" mid-line to be run
                if ($clean -match '^\s*chatq\s') { $clean = $clean -replace $script:ChatMidTailPattern, '' }
                if ($clean -ne $line) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $clean)
                    $line = $clean
                }
                $script:ChatCycle = $null

                # chatrm only, and only when the argument is part of a title
                # rather than all of it: fill the title in the way Tab would and
                # hold the line, so the whole thing is on screen before Enter
                # can act on it. chatfind is a search and deletes nothing, so it
                # runs as typed.
                # never let this break Enter: a throw inside a key handler makes
                # the key unusable, which would be far worse than the eager
                # delete it exists to prevent
                try {
                    if ($line -match '^\s*chatrm\s' -and (Test-ChatPartialTarget $line)) {
                        if (Start-ChatCycle $line) { return }
                    }
                }
                catch {}
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    catch {}
}

#endregion

#region queue: configuration --------------------------------------------

$script:ChatqIsWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

# Every runtime file lives in data/ beside the script, never in AppData or
# TEMP - the folder is the whole installation, and deleting it is the uninstall.
$script:ChatqData = Join-Path $PSScriptRoot 'data'
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
# which this dot-sourced file inherits - never meets one unset.
$script:ChatqCliVersions = @{}
$script:ChatqAwake = $false
$script:ChatqAwakeProc = $null
$script:ChatqLastAlertError = $null
$script:ChatqForeground = $false

#endregion

#region queue: readers only the queue needs ----------------------------

function Read-ChatqTail {
    # The last $Size bytes as text. Cutting mid-character only garbles the first
    # few bytes, which a caller looking for whole JSON lines skips anyway.
    param([string]$Path, [int64]$Size)
    try { $fs = Open-ChatRead $Path } catch { return $null }
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
        $v = Get-ChatJsonString $t $Key
        if ($v) { return $v }
        if ($size -ge $len) { break }
    }
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
    $all = @(Sync-ChatIndex -Provider $Provider | Where-Object { -not $_.Hidden -and $_.Title -ne '(empty)' })
    if (-not $all) { return [pscustomobject]@{ Error = 'no chats found on this machine' } }
    $when = @{}
    foreach ($r in $all) { $when[$r.Path] = ConvertTo-ChatqDate $r.When }

    $make = {
        param($Row, $Rule, $Tier, $Score, $Runner, $RunnerScore, $Cluster, $Count, $Wide, $NoProject)
        # Copilot chats are searched so that naming one says why it cannot be
        # queued, rather than quietly resolving to some other chat instead
        if ($Row.Provider -eq 'copilot') {
            return [pscustomobject]@{ Error = "'$($Row.Title)' is a Copilot chat - Copilot has no CLI that can resume a chat, so nothing can deliver a prompt to it. Type more of the title to pick a Claude or Codex chat." }
        }
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

    $scope = Get-ChatProjectScope
    $mine = if ($AllProjects) { $all } else { @($all | Where-Object { Test-ChatInProject $_ $scope }) }
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
        # a guess is never a Copilot chat - it could only end in a refusal
        $cands = @($mine | Where-Object { $_.Provider -ne 'copilot' }); $tier = 'nomatch'
        if (-not $cands.Count) { return [pscustomobject]@{ Error = "no chat title matches '$typed', and this project has no Claude or Codex chat to guess from" } }
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
    $age = if ($Res.When) { " ($(Get-ChatAge $Res.When))" } else { '' }
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
        $ra = if ($Res.RunnerUpWhen) { " ($(Get-ChatAge $Res.RunnerUpWhen))" } else { '' }
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
    $chunk = Read-ChatChunk $Path 262144
    if ($chunk) {
        # Both d:\ and D:\ turn up for the same folder. The one whose slug is
        # this project's folder name is the one Claude filed the chat under.
        $seen = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($chunk.Head + "`n" + $chunk.Tail, '"cwd":"((?:[^"\\]|\\.)*)"')) {
            $v = Convert-ChatJsonEscaped $m.Groups[1].Value
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
    $chunk = Read-ChatChunk $Path 262144
    if ($chunk -and $chunk.Head -match '"cwd":\s*"((?:[^"\\]|\\.)*)"') { $meta.Cwd = Convert-ChatJsonEscaped $Matches[1] }
    $text = if ($chunk.Split) { $chunk.Tail } else { $chunk.Head }
    $lines = Get-ChatJsonLines $text @('"type":"turn_context"', '"type": "turn_context"') 1 -FromEnd -Skip @()
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
    $root = Join-Path $script:ChatClaudeHome 'projects'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $since = (Get-Date).AddHours(-$Hours)
    $busy = @{}
    foreach ($j in $Jobs) { if ($j.state -in 'queued', 'running') { $busy[$j.sessionId] = $true } }
    $rows = @{}
    foreach ($r in @(Get-ChatIndex)) { $rows[$r.Path] = $r }
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
            (Join-Path (Join-Path $script:ChatClaudeHome 'local') $exe))) {
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
    # assigned, never @()-wrapped: Get-ChatJsonLines returns its array behind a
    # comma, and @(...) around that makes an array holding one array
    $marker = if ($Provider -eq 'codex') { @('"role":"user"', '"role": "user"') } else { @('"type":"user"') }
    $lines = Get-ChatJsonLines $text $marker 40 -FromEnd -Skip @('"tool_result"')
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
    $t = try { Read-ChatAllText $path } catch { return $null }
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
    if ($v -and ((Compare-ChatVersion $v $script:ChatqClaudeMin) -eq -1)) {
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
        Write-Host ('  ' + (Format-ChatCell '#' $numW) + (Format-ChatCell 'chat' $chatW) + ' ' +
            (Format-ChatCell 'prompt' $promptW) + ' ' + 'sends') -ForegroundColor DarkGray
        foreach ($j in $open) {
            $text = if ($j.kind -eq 'continue') { 'continue' } else { [string](Read-ChatqPrompt $j) }
            $ps = Get-ChatqPromptStats $text
            $when = ConvertTo-ChatqDate $j.chatWhen
            $age = if ($when) { " ($(Get-ChatAge $when))" } else { '' }
            $state = switch ($j.state) {
                'queued' { $eta[$j.id] }
                'running' {
                    $s = ConvertTo-ChatqDate $j.startedAt
                    $a = if ($s) { Get-ChatAge $s } else { 'now' }
                    if ($a -eq 'now') { 'running' } else { "running $a" }
                }
                'needs-input' { 'needs you' }
                'failed' { 'failed' }
            }
            $color = switch ($j.state) { 'needs-input' { 'Yellow' } 'failed' { 'Red' } 'running' { 'Green' } default { 'Gray' } }
            Write-Host ('  ' + (Format-ChatCell "$($j.seq)" $numW)) -NoNewline
            Write-Host ((Format-ChatCell "$($j.title)$age" $chatW) + ' ') -NoNewline -ForegroundColor Cyan
            Write-Host ((Format-ChatCell $ps.First $promptW) + ' ') -NoNewline
            Write-Host $state -ForegroundColor $color
            $pad = ' ' * (2 + $numW + $chatW + 1)
            if ($ps.Lines -gt 1 -or (Get-ChatCells $ps.First) -gt $promptW) {
                Write-Host ($pad + [char]0x21B3 + ' ' + ('{0:N0} chars {1} {2} lines' -f $ps.Chars, $script:ChatqDot, $ps.Lines)) -ForegroundColor DarkGray
            }
            if ($j.state -in 'needs-input', 'failed' -and $j.result.reason) {
                Write-Host ($pad + (Format-ChatCell ([string]$j.result.reason) $promptW -NoPad)) -ForegroundColor DarkGray
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
        Write-Host ((Format-ChatCell $line ($width - 8) -NoPad) + '  ' + $end.ToString('HH:mm')) -ForegroundColor DarkGray
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
        pid = $PID; version = $script:ChatVersion; startedAt = $W.startedAt; heartbeat = (Get-ChatqStamp)
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
            $cmd = if ($script:ChatIsMac) { @('caffeinate', '-i', '-w', "$PID") }
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
    # The window still holding this chat shows none of the run until it
    # reloads. The extension in extension/ offers that reload, in that window
    # only - the job's folder is what it matches on, never this process's own.
    # Not for a run that goes back in the queue: it is not finished yet.
    if ($stale -and -not $wasCancelled -and $out.kind -notin 'limited', 'overloaded') {
        Write-ChatReloadRequest -Title $Job.title -Cwd $Job.cwd -Kind 'ran'
    }

    $dur = ''
    $s0 = ConvertTo-ChatqDate $Job.startedAt
    if ($s0) { $dur = Get-ChatAge $s0; if ($dur -eq 'now') { $dur = '<1m' } }
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
        Write-ChatqWatchLog "watcher $PID started ($script:ChatVersion)"
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
        Write-Host '  cannot start the watcher: this shell does not know where VS-code-chat-manager.ps1 is' -ForegroundColor Yellow
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
    Write-Host '  Tab fills in a title from any part of it, like chatrm: chatq card red<Tab>' -ForegroundColor DarkGray
    Write-Host '  chat = every command, find and delete included' -ForegroundColor DarkGray
    Write-Host "  VS-code-chat-manager $script:ChatVersion $($script:ChatqDot) $script:ChatqScriptPath" -ForegroundColor DarkGray
}

#endregion

$script:ChatqJobCompleter = {
    param($cmd, $param, $word)
    Set-StrictMode -Off
    @(Get-ChatqJobs) | Where-Object { "$($_.seq)" -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new("$($_.seq)", "#$($_.seq) $($_.title) [$($_.state)]", 'ParameterValue', "$($_.title)`n$($_.state)")
    }
}
Register-ArgumentCompleter -CommandName chatqrm, chatqrun, chatqlog -ParameterName Ref -ScriptBlock $script:ChatqJobCompleter


# a shell opened after the delete picks the watch back up
if (Test-Path -LiteralPath $script:ChatTombPath) { Start-ChatGhostWatch }

# Run instead of dot-sourced - & file.ps1, powershell -File, a double-click.
# Everything above was defined in a scope about to be thrown away, leaving a
# shell with no chat command and nothing said about why. InvocationName is '.'
# for a real dot-source, at the prompt and from inside a profile alike, and the
# path or '&' otherwise, so this cannot fire on a legitimate load.
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host ''
    Write-Host '  nothing was loaded - this file has to be dot-sourced' -ForegroundColor Yellow
    Write-Host '  a dot and a space in front of the path is the whole difference:' -ForegroundColor DarkGray
    # iex has no file behind it, so PSCommandPath is empty there - printing
    # . "" would be advice nobody can follow, and is how an empty dot-source
    # line ends up pasted into a profile in the first place
    $shown = if ($PSCommandPath) { $PSCommandPath } else { 'C:\path\to\VS-code-chat-manager.ps1' }
    Write-Host "      . `"$shown`"" -ForegroundColor Cyan
    Write-Host '  then chatinstall, to have every new shell do it for you' -ForegroundColor DarkGray
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
