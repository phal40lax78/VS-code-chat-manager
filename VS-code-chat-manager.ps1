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
    chatrm ... -Archive            put it away instead of deleting it
    chatrestore [<title|id>]       list the archive / bring one back
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
    chatoverlay [-Stop] [-Print]   every running chat, and usage, always on top
    chatconsole                    chatq in a window: write, send now, queue,
                                   continue, new chats (Windows)
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
             Extras: sidecar dir, file-history/<id>, session-env/<id>,
             tasks/<id>, debug/<id>.txt, security state, telemetry and todos
             by id, jobs/ by the id in state.json, and plans/<slug>.md when no
             other chat in the project shares the slug.
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
    queue/<id>/                            that job's files, copied in
    logs/<id>.jsonl                        the raw run
    logs/jobs.log                          every job event, including removals
    queue.md                               live board - open it, Ctrl+Shift+V
    config.json                            Join key, DPAPI-protected on Windows
    overlay.json                           what the overlay shows, rewritten as it changes
    overlay-state.json                     where the overlay sits, locked or not
    logs/overlay.log                       the overlay's own log
#>

# Bump this in the same commit that changes behaviour - chatinstall compares it
# against data/version.txt to say whether a reinstall actually landed anything,
# and raw.githubusercontent.com serves a stale copy for minutes after a push, so
# "updated" vs "unchanged" is the only way to tell a real upgrade from the CDN
# handing back what you already had.
$script:ChatVersion = '0.5.0'

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

# The index's rows from its CSV. Self-contained - it names nothing else in
# this file - because the overlay's console runs it in a runspace of its own,
# off the window's thread (Start-ChatConsoleIndexRead).
$script:ChatIndexRead = {
    param([string]$Path, [string]$Sep)
    @(Import-Csv -LiteralPath $Path | ForEach-Object {
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
                First    = @($_.First -split $Sep | Where-Object { $_ })
                Last     = @($_.Last -split $Sep | Where-Object { $_ })
            }
        })
}

function Get-ChatIndexStamp {
    # the index file's version: its time and length, or $null
    try {
        $fi = [System.IO.FileInfo]::new($script:ChatIndexPath)
        if ($fi.Exists) { "$($fi.LastWriteTimeUtc.Ticks):$($fi.Length)" } else { $null }
    }
    catch { $null }
}

function Get-ChatIndex {
    # CSV, not JSON: ConvertTo-Json on a few thousand rows costs tens of seconds.
    # Kept in memory too, so repeated Tab presses re-parse nothing.
    if (-not (Test-Path -LiteralPath $script:ChatIndexPath)) { return @() }
    $stamp = Get-ChatIndexStamp
    if ($stamp -and $stamp -eq $script:ChatIndexStamp) { return $script:ChatIndexCache }
    try {
        $rows = @(& $script:ChatIndexRead $script:ChatIndexPath $script:ChatIndexSep)
        $script:ChatIndexCache = $rows
        $script:ChatIndexStamp = $stamp
        return $rows
    }
    catch { return @() }
}

function Save-ChatIndex {
    # Written beside the index and swapped in whole: the overlay's console
    # reads it while a shell - or its own background sync - writes it, and
    # half a CSV parses as a shorter list without complaint.
    param([object[]]$Rows)
    try {
        $dir = Split-Path $script:ChatIndexPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$($script:ChatIndexPath).tmp"
        $Rows | ForEach-Object {
            [pscustomobject]@{
                Provider = $_.Provider; Path = $_.Path; Size = $_.Size; Mtime = $_.Mtime
                Id = $_.Id; Title = $_.Title; Titled = $_.Titled; Group = $_.Group
                Hidden = $_.Hidden; When = $_.When
                First = (@($_.First) -join $script:ChatIndexSep)
                Last = (@($_.Last) -join $script:ChatIndexSep)
            }
        } | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8
        # [NullString], not $null: PowerShell hands .NET an empty string for
        # $null, and an empty backup path throws
        if (Test-Path -LiteralPath $script:ChatIndexPath) { [System.IO.File]::Replace($tmp, $script:ChatIndexPath, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $script:ChatIndexPath) }
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

function Get-ChatSlug {
    # Claude's name for a project folder: the whole path, with every character
    # that is not a letter or digit turned into a dash. A drive's root keeps
    # its slash: Claude calls C:\ C--, and C: alone is another folder.
    param([string]$Path)
    $p = $Path.TrimEnd('\', '/')
    if ($p -eq '' -or $p -match '^[A-Za-z]:$') { $p = $Path }
    return ($p -replace '[^A-Za-z0-9]', '-')
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

function Read-ClaudeSlashCommand {
    # A slash command typed into a chat - "/compact", "/model opus" - as the
    # transcript keeps it: a user record Claude Code writes once the command
    # has run. A skill the model loads has no slash, and is not this.
    param([string]$Line)
    if ($Line -notlike '*<command-name>/*' -or $Line -like '*"isMeta":true*') { return $null }
    try { $o = $Line | ConvertFrom-Json } catch { return $null }
    if ($o.type -ne 'user' -or $o.message.content -isnot [string]) { return $null }
    $c = [string]$o.message.content
    if ($c -notmatch '<command-name>\s*(/[^<\s]+)\s*</command-name>') { return $null }
    $name = $Matches[1]
    $rest = if ($c -match '<command-args>([\s\S]*?)</command-args>') { ($Matches[1] -replace '\s+', ' ').Trim() } else { '' }
    if ($rest) { return "$name $rest" }
    return $name
}

function Get-ClaudeLeftovers {
    # Everything on disk that belongs to one chat and nothing else, after
    # claude-chats-delete's inventory (docs/deletion-behavior.md there). Most
    # are named by the session id; the rest are found by it. Project and user
    # memory are never on this list - they are not one chat's.
    param($File)
    $id = $File.BaseName
    $h = $script:ChatClaudeHome
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
            (Join-Path $File.DirectoryName $id)                              # subagents/, tool-results/
            (Join-Path (Join-Path $h 'file-history') $id)
            (Join-Path (Join-Path $h 'session-env') $id)
            (Join-Path (Join-Path $h 'tasks') $id)
            (Join-Path (Join-Path $h 'debug') "$id.txt")
            (Join-Path (Join-Path $h 'security') "security_warnings_state_$id.json")
            (Join-Path (Join-Path $h 'security') "security_warnings_state_$id.lock")
            (Join-Path $h "security_warnings_state_$id.json")               # older layout
        )) { $out.Add($p) }
    foreach ($d in @(@{ Dir = 'telemetry'; Like = "*$id*.json" }, @{ Dir = 'todos'; Like = "$id*.json" })) {
        $dir = Join-Path $h $d.Dir
        if (Test-Path -LiteralPath $dir) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -EA SilentlyContinue | Where-Object { $_.Name -like $d.Like })) { $out.Add($f.FullName) }
        }
    }
    # a background job's folder is named by an 8-character prefix, so its own
    # state.json says whose it is
    $jobs = Join-Path $h 'jobs'
    if (Test-Path -LiteralPath $jobs) {
        foreach ($d in @(Get-ChildItem -LiteralPath $jobs -Directory -EA SilentlyContinue)) {
            $st = Join-Path $d.FullName 'state.json'
            if (-not (Test-Path -LiteralPath $st)) { continue }
            $sid = try { (Get-Content -LiteralPath $st -Raw -Encoding UTF8 | ConvertFrom-Json).sessionId } catch { $null }
            if ($sid -eq $id) { $out.Add($d.FullName) }
        }
    }
    # A plan file is named by the chat's slug, and a resumed or forked chat can
    # share that slug with another - two here did. Only when no other chat in
    # the same project folder mentions it does the plan go with this one.
    $plans = Join-Path $h 'plans'
    if (Test-Path -LiteralPath $plans) {
        $c = Read-ChatChunk $File.FullName
        $slug = if ($c) { Get-ChatJsonString "$($c.Head)`n$($c.Tail)" 'slug' } else { $null }
        if ($slug -and $slug -match '^[A-Za-z0-9-]+$') {
            $needle = "`"slug`":`"$slug`""
            $others = @(Get-ChildItem -LiteralPath $File.DirectoryName -Filter *.jsonl -File -EA SilentlyContinue |
                Where-Object { $_.FullName -ne $File.FullName })
            $shared = $others -and [bool](Select-String -LiteralPath @($others.FullName) -SimpleMatch -Pattern $needle -List -EA SilentlyContinue | Select-Object -First 1)
            if (-not $shared) {
                foreach ($f in @(Get-ChildItem -LiteralPath $plans -File -EA SilentlyContinue |
                        Where-Object { $_.Name -eq "$slug.md" -or $_.Name -like "$slug-agent-*.md" })) { $out.Add($f.FullName) }
            }
        }
    }
    return $out.ToArray()
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
            Get-ClaudeLeftovers $File
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
        Slug = Get-ChatSlug $full
        Leaf = Split-Path $full -Leaf
    }
}

function Test-ChatInProject {
    # Exact, never a prefix. Sibling repos nest - the slug for D:\src\app is a
    # prefix of the one for D:\src\app-Mobile - so -like or StartsWith
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
    if ($env:CHATQ_WATCHER -or $env:CHATQ_OVERLAY -or $script:ChatNoGhostWatch) { return }
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
    # What the chat leaves beside it, worked out while the transcript is still
    # there to read (a plan file is found by the slug inside it), and removed
    # only once the transcript is really gone: a chat a live window still holds
    # keeps its leftovers along with itself.
    $extras = @(& $script:ChatProviders[$Hit.Provider].Extras $Hit.File $Hit.Record)
    Remove-Item -LiteralPath $path -Force -EA SilentlyContinue
    if (Test-Path -LiteralPath $path) {
        Write-Host "  LOCKED   $($Hit.Record.Title)" -ForegroundColor Yellow
        Write-Host '           still on disk - another process has it open' -ForegroundColor DarkGray
        return $false
    }
    foreach ($p in $extras) {
        if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Recurse -Force -EA SilentlyContinue }
    }
    Add-ChatTombstone $path
    # the index is what Tab completes from, so a row left behind offers a title
    # whose transcript is already gone
    Remove-ChatIndexRow $path
    # the title, not the full row: the row is wider than a narrow panel and wraps
    Write-Host "  deleted  $($Hit.Record.Title)" -ForegroundColor DarkGray
    return $true
}

#region archive and restore ---------------------------------------------------
# chatrm -Archive puts a chat out of the way without losing it: a Claude chat
# and its leftovers move into data/archive/claude/<id>/ with a manifest of where
# each came from, a Codex thread goes through codex archive (Codex keeps thread
# state in its own databases, so only its CLI can archive one properly). The
# panel's list is left to forget it the same way it forgets a deleted chat.

$script:ChatArchiveDir = Join-Path (Join-Path $PSScriptRoot 'data') 'archive'

function Move-ChatItem {
    # Move-Item, else copy-then-delete: a folder cannot be moved across drives,
    # and nothing says data/ sits on the drive ~/.claude does
    param([string]$From, [string]$To)
    $parent = Split-Path $To -Parent
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    try { Move-Item -LiteralPath $From -Destination $To -Force -EA Stop; return $true } catch {}
    try {
        Copy-Item -LiteralPath $From -Destination $To -Recurse -Force -EA Stop
        Remove-Item -LiteralPath $From -Recurse -Force -EA Stop
        return $true
    }
    catch { return $false }
}

function Save-ChatArchive {
    # $true when the chat was archived
    param($Hit)
    $title = $Hit.Record.Title
    if ($Hit.Provider -eq 'copilot') {
        Write-Host "  KEPT     $title" -ForegroundColor Yellow
        Write-Host '           VS Code archives Copilot chats itself - from the chat list there' -ForegroundColor DarkGray
        return $false
    }
    if ($Hit.Provider -eq 'codex') { return (Save-ChatCodexArchive $Hit) }
    $id = $Hit.Record.Id
    # A chat still open in a window goes on writing to the path it came from,
    # which would leave half of it here and half in the archive.
    if (@(Get-ChatqLiveSessions $env:CLAUDE_CONFIG_DIR | Where-Object { $_.SessionId -eq $id })) {
        Write-Host "  KEPT     $title" -ForegroundColor Yellow
        Write-Host '           open in a VS Code window - close it there, or reload the window, then archive' -ForegroundColor DarkGray
        return $false
    }
    $dest = Join-Path (Join-Path $script:ChatArchiveDir 'claude') $id
    if (Test-Path -LiteralPath $dest) {
        Write-Host "  KEPT     $title" -ForegroundColor Yellow
        Write-Host '           an archived copy of this chat is already there - chatrestore it first' -ForegroundColor DarkGray
        return $false
    }
    $extras = @(Get-ClaudeLeftovers $Hit.File | Where-Object { Test-Path -LiteralPath $_ })
    $items = [System.Collections.Generic.List[object]]::new()
    # the transcript first: when that will not move, nothing else does
    $rel = "files\0-$($Hit.File.Name)"
    if (-not (Move-ChatItem $Hit.File.FullName (Join-Path $dest $rel))) {
        Remove-Item -LiteralPath $dest -Recurse -Force -EA SilentlyContinue
        Write-Host "  LOCKED   $title" -ForegroundColor Yellow
        Write-Host '           another process has it open' -ForegroundColor DarkGray
        return $false
    }
    $items.Add([ordered]@{ from = $Hit.File.FullName; stored = $rel; transcript = $true })
    $n = 0
    foreach ($p in $extras) {
        $n++
        $r = "files\$n-$(Split-Path $p -Leaf)"
        if (Move-ChatItem $p (Join-Path $dest $r)) { $items.Add([ordered]@{ from = $p; stored = $r; transcript = $false }) }
    }
    Save-ChatqJson (Join-Path $dest 'manifest.json') ([ordered]@{
            v = 1; provider = 'claude'; id = $id; title = $title; group = $Hit.Record.Group
            archivedAt = (Get-Date).ToUniversalTime().ToString('o'); items = @($items)
        })
    # the window writes a listed chat back as a stub when it reloads, exactly
    # as it does a deleted one - the same tombstone takes that back
    Add-ChatTombstone $Hit.File.FullName
    Remove-ChatIndexRow $Hit.File.FullName
    Write-Host "  archived $title" -ForegroundColor DarkGray
    return $true
}

function Save-ChatCodexArchive {
    param($Hit)
    $title = $Hit.Record.Title
    $exe = Find-ChatqExe codex
    if (-not $exe) {
        Write-Host "  KEPT     $title" -ForegroundColor Yellow
        Write-Host '           no codex CLI found - only codex archive can archive a Codex thread' -ForegroundColor DarkGray
        return $false
    }
    # stdin empty and closed: a CLI that waits on it would hang here
    $p = Invoke-ChatqProcess -Exe $exe -ArgList @('archive', $Hit.Record.Id) -StdIn '' -TimeoutSec 60 -SetEnv @{ CODEX_HOME = $env:CODEX_HOME }
    if ($p.ExitCode -ne 0 -or $p.Stopped) {
        $err = ("$($p.StdErr)" -replace '\s+', ' ').Trim()
        if ($err.Length -gt 160) { $err = $err.Substring($err.Length - 160) }
        Write-Host "  KEPT     $title" -ForegroundColor Yellow
        Write-Host "           codex archive failed: $err" -ForegroundColor DarkGray
        return $false
    }
    # Codex has no command that lists what it archived, so this is the record
    # chatrestore lists it from
    Save-ChatqJson (Join-Path (Join-Path (Join-Path $script:ChatArchiveDir 'codex') $Hit.Record.Id) 'manifest.json') ([ordered]@{
            v = 1; provider = 'codex'; id = $Hit.Record.Id; title = $title; group = $Hit.Record.Group
            archivedAt = (Get-Date).ToUniversalTime().ToString('o'); items = @([ordered]@{ from = $Hit.File.FullName })
        })
    Remove-ChatIndexRow $Hit.File.FullName
    Write-Host "  archived $title" -ForegroundColor DarkGray
    return $true
}

function Remove-ChatTombstone {
    # One path's line out of rewritten.txt - before a restored chat moves back,
    # or a ghost watch in some open shell takes it for a stub and deletes it
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $script:ChatTombPath)) { return }
    $keep = @(Get-Content -LiteralPath $script:ChatTombPath -EA SilentlyContinue | Where-Object {
            $parts = $_ -split "`t", 2
            $parts.Count -ne 2 -or $parts[1] -ne $Path
        })
    if ($keep) { Set-Content -LiteralPath $script:ChatTombPath -Value $keep }
    else { Remove-Item -LiteralPath $script:ChatTombPath -Force -EA SilentlyContinue; Stop-ChatGhostWatch }
}

function Get-ChatArchive {
    # What chatrestore can bring back: every chat chatrm archived, plus any
    # thread under Codex's own archived_sessions folder, if it keeps one there.
    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    if (Test-Path -LiteralPath $script:ChatArchiveDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $script:ChatArchiveDir -Filter manifest.json -File -Recurse -EA SilentlyContinue)) {
            $m = Read-ChatqJson $f.FullName
            if (-not $m -or -not $m.id) { continue }
            $seen[[string]$m.id] = $true
            $rows.Add([pscustomobject]@{
                    Provider = $m.provider; Id = [string]$m.id; Title = [string]$m.title; Group = $m.group
                    When = ConvertTo-ChatqDate $m.archivedAt; Dir = $f.DirectoryName; Manifest = $m
                })
        }
    }
    $cx = Join-Path $script:ChatCodexHome 'archived_sessions'
    if (Test-Path -LiteralPath $cx) {
        $names = Get-CodexThreadNames
        foreach ($f in @(Get-ChildItem -LiteralPath $cx -Filter 'rollout-*.jsonl' -File -Recurse -EA SilentlyContinue)) {
            $id = if ($f.BaseName -match '([0-9a-fA-F-]{36})$') { $Matches[1] } else { continue }
            if ($seen[$id]) { continue }
            $t = if ($names[$id]) { $names[$id] } else { $id }
            $rows.Add([pscustomobject]@{ Provider = 'codex'; Id = $id; Title = $t; Group = $null; When = $f.LastWriteTime; Dir = $null; Manifest = $null })
        }
    }
    return @($rows | Sort-Object When -Descending)
}

function Restore-ChatArchive {
    # $true when the chat is back where it was
    param($Row)
    if ($Row.Provider -eq 'codex') {
        $exe = Find-ChatqExe codex
        if (-not $exe) { Write-Host '  no codex CLI found - codex unarchive is the only way back' -ForegroundColor Yellow; return $false }
        $p = Invoke-ChatqProcess -Exe $exe -ArgList @('unarchive', $Row.Id) -StdIn '' -TimeoutSec 60 -SetEnv @{ CODEX_HOME = $env:CODEX_HOME }
        if ($p.ExitCode -ne 0 -or $p.Stopped) {
            Write-Host "  codex unarchive failed: $(("$($p.StdErr)" -replace '\s+', ' ').Trim())" -ForegroundColor Yellow
            return $false
        }
        if ($Row.Dir) { Remove-Item -LiteralPath $Row.Dir -Recurse -Force -EA SilentlyContinue }
        $null = Sync-ChatIndex -Provider codex
        Write-Host "  restored $($Row.Title)" -ForegroundColor Green
        return $true
    }
    $items = @($Row.Manifest.items)
    $main = @($items | Where-Object { $_.transcript }) | Select-Object -First 1
    if (-not $main) { Write-Host '  this archive has no transcript in it' -ForegroundColor Yellow; return $false }
    if (Test-Path -LiteralPath $main.from) {
        # the window's stub, written back after the archive - that may go; a
        # real chat written since may not, and nothing is moved over it
        $f = Get-Item -LiteralPath $main.from -EA SilentlyContinue
        if ($f -and (& $script:ChatProviders['claude'].IsEmpty $f)) { Remove-Item -LiteralPath $main.from -Force -EA SilentlyContinue }
        else {
            Write-Host "  KEPT IN ARCHIVE  $($Row.Title)" -ForegroundColor Yellow
            Write-Host "                   a chat with messages is at $($main.from) now - move it away first" -ForegroundColor DarkGray
            return $false
        }
    }
    # the tombstone before anything moves, or a ghost watch takes the file back
    Remove-ChatTombstone $main.from
    foreach ($it in $items) {
        $src = Join-Path $Row.Dir $it.stored
        if (-not (Test-Path -LiteralPath $src)) { continue }
        # a leftover recreated since - a newer file-history, say - wins
        if (-not $it.transcript -and (Test-Path -LiteralPath $it.from)) { continue }
        if (-not (Move-ChatItem $src $it.from)) {
            Write-Host "  could not move $src back to $($it.from)" -ForegroundColor Yellow
            if ($it.transcript) { return $false }
        }
    }
    Remove-Item -LiteralPath $Row.Dir -Recurse -Force -EA SilentlyContinue
    $null = Sync-ChatIndex -Provider claude
    Write-Host "  restored $($Row.Title)" -ForegroundColor Green
    return $true
}

function chatrestore {
    <#
    .SYNOPSIS
    Bring back a chat that chatrm -Archive put away. With nothing typed, list
    the archive.
    .DESCRIPTION
    A Claude chat moves back to where it was, leftovers and all, and shows up in
    the panel after a window reload. A Codex thread goes through codex
    unarchive. Tab completes the archived titles.
    .EXAMPLE
    chatrestore
    .EXAMPLE
    chatrestore 'Parser rewrite'
    #>
    param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Target)
    Set-StrictMode -Off
    $all = @(Get-ChatArchive)
    $t = ((@($Target) -join ' ').Trim()).Trim("'", '"').Trim()
    if (-not $t) {
        if (-not $all) { Write-Host '  nothing archived - chatrm <title> -Archive puts a chat here' -ForegroundColor DarkGray; return }
        Write-Host ''
        foreach ($r in $all) {
            $age = if ($r.When) { Get-ChatAge $r.When } else { '?' }
            Write-Host ('  {0,-7} {1,5}  {2}' -f $r.Provider, $age, $r.Title) -ForegroundColor Cyan
        }
        Write-Host '  chatrestore <title|id> brings one back' -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    $hits = if ($t -match '^[0-9a-fA-F]{6,}(-[0-9a-fA-F-]*)?$') { @($all | Where-Object { $_.Id -like "$t*" }) } else { @() }
    if (-not $hits) { $hits = @($all | Where-Object { $_.Title.Equals($t, [StringComparison]::OrdinalIgnoreCase) }) }
    if (-not $hits) { $hits = @($all | Where-Object { $_.Title.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
    if (-not $hits) { Write-Host "  nothing archived is titled like '$t' - chatrestore lists them" -ForegroundColor Yellow; return }
    if ($hits.Count -gt 1) {
        Write-Host "  '$t' matches $($hits.Count) archived chats - type more of the title, or its id:" -ForegroundColor Yellow
        foreach ($r in $hits) { Write-Host "    $($r.Id.Substring(0, [Math]::Min(8, $r.Id.Length)))  $($r.Title)" -ForegroundColor DarkGray }
        return
    }
    if (Restore-ChatArchive $hits[0]) {
        Write-Host '  reload the VS Code window to see it in the chat list' -ForegroundColor DarkGray
    }
}

Register-ArgumentCompleter -CommandName chatrestore -ParameterName Target -ScriptBlock {
    param($cmd, $param, $word)
    Set-StrictMode -Off
    $w = ([string]$word).Trim('"', "'")
    @(Get-ChatArchive) | Where-Object { -not $w -or $_.Title.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
        Select-Object -First 25 | ForEach-Object {
            $q = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($_.Title) + "'"
            [System.Management.Automation.CompletionResult]::new($q, "$($_.Title) [$($_.Provider)]", 'ParameterValue', $_.Title)
        }
}

#endregion

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

function Get-ChatBackgroundTasks {
    # The workflows and background agents a Claude chat started that have not
    # reported back: their task ids. The turn that starts one ends at once, so
    # the transcript reads as finished and Claude calls the chat idle while the
    # work goes on - its agents write only under <id>/subagents/. A reload
    # kills all of it along with the chat's process.
    #
    # A start is a tool result whose toolUseResult is 'async_launched', with a
    # taskId (a workflow) or an agentId (an agent); SendMessage waking a
    # stopped agent is a resumedAgentId. Every end - completed, failed,
    # stopped - is a <task-notification> naming the same task id.
    #
    # Only starts after $Since count: the work dies with the process that ran
    # it, so one from before the chat was last opened is gone whether or not
    # it ever reported. A background shell is left out on purpose - as often a
    # server that never ends, which would hold the chat busy for good.
    param([string]$Path, [datetime]$Since = [datetime]::MinValue)
    $open = [System.Collections.Generic.List[string]]::new()
    try { $fs = Open-ChatRead $Path } catch { return }   # can vanish mid-scan
    try {
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        try {
            while ($null -ne ($line = $sr.ReadLine())) {
                # a cheap look first: most lines are neither, and parsing each
                # one would be the whole cost of a long chat
                if ($line.IndexOf('"async_launched"', [StringComparison]::Ordinal) -ge 0 -or
                    $line.IndexOf('"resumedAgentId"', [StringComparison]::Ordinal) -ge 0) {
                    $o = try { $line | ConvertFrom-Json } catch { $null }
                    $r = if ($o -and $o.PSObject.Properties['toolUseResult']) { $o.toolUseResult } else { $null }
                    $id = $null
                    if ($r -and $r.PSObject.Properties['status'] -and $r.status -eq 'async_launched') {
                        $id = if ($r.PSObject.Properties['taskId'] -and $r.taskId) { $r.taskId }
                        elseif ($r.PSObject.Properties['agentId']) { $r.agentId }
                    }
                    elseif ($r -and $r.PSObject.Properties['resumedAgentId']) { $id = $r.resumedAgentId }
                    if ($id) {
                        $at = ConvertTo-ChatqDate $o.timestamp
                        if ((-not $at -or $at -ge $Since) -and -not $open.Contains([string]$id)) { $open.Add([string]$id) }
                        continue
                    }
                }
                if ($open.Count -and $line.IndexOf('<task-id>', [StringComparison]::Ordinal) -ge 0) {
                    foreach ($t in @($open)) {
                        if ($line.IndexOf("<task-id>$t</task-id>", [StringComparison]::Ordinal) -ge 0) { [void]$open.Remove($t) }
                    }
                }
            }
        }
        finally { $sr.Dispose() }
    }
    finally { $fs.Dispose() }
    return $open.ToArray()
}

function Test-ChatIdle {
    # $true idle, $false active, $null when it cannot be told - and $null stays
    # distinct, because "safe to reload" guessed wrong costs someone an answer.
    # -Except leaves one transcript out of what the files alone say: the chat a
    # queued run just wrote to, which would read as live for the next minute.
    # What Claude says of that chat's own open process still counts - after
    # the run it can only be a window's, and that may be busy. -ConfigDir is
    # the Claude home whose open sessions to ask, a job's own when it has one.
    param([int]$Seconds = $script:ChatIdleSeconds, [switch]$AllProjects, [string]$Cwd = $PWD.Path, [string]$Except,
        [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR)
    $files = @(Get-ChatProjectFiles -AllProjects:$AllProjects -Cwd $Cwd)
    if (-not $files) { return $null }

    # first, what Claude says of the chats it has open: busy is a turn in
    # flight, waiting a permission prompt. A turn that started a workflow or a
    # background agent has ended, though, and reads idle there - so those
    # chats are also searched for work that has not reported back.
    $byId = @{}
    foreach ($f in $files) { if ($f.Extension -eq '.jsonl') { $byId[$f.BaseName] = $f } }
    foreach ($s in @(Get-ChatqLiveSessions $ConfigDir)) {
        $f = $byId[[string]$s.SessionId]
        if (-not $f) { continue }
        if ($s.Status -in 'busy', 'waiting') { return $false }
        $since = [datetime]::MinValue
        if ($s.StartedAt) { $since = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$s.StartedAt).LocalDateTime }
        else { try { $since = (Get-Process -Id $s.Pid -EA Stop).StartTime } catch {} }
        # untouched since this process started: it has started nothing
        if ($f.LastWriteTime -lt $since) { continue }
        if (@(Get-ChatBackgroundTasks $f.FullName $since).Count) { return $false }
    }

    # then the transcripts themselves - all there is to go on for Codex, or a
    # Claude too old to keep that list. Anything written just now is live
    if ($Except) { $files = @($files | Where-Object { $_.FullName -ne $Except }) }
    $cut = (Get-Date).AddSeconds(-$Seconds)
    foreach ($f in $files) { if ($f.LastWriteTime -gt $cut) { return $false } }

    # quiet on disk is not the same as finished, though. Only a recently
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
    # Busy is $true when a chat in the project was still working as the
    # request went out - the window then warns instead of offering a plain
    # Reload, and never reloads by itself. Away is $true when nobody had used
    # the PC for a while: after a queued run, only then may the window reload
    # without asking. $null is "not judged", for both.
    param([string]$Title, [string]$Cwd = (Get-Location).Path, [string]$Kind = 'deleted', $Busy = $null, $Away = $null)
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
            busy  = $Busy
            away  = $Away
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
    param([switch]$WaitForIdle, [switch]$AllProjects, [string]$Title, [string]$Kind = 'deleted')
    $procs = if ($script:ChatIsMac) { @('Electron', 'Code Helper*') } else { @('Code') }
    if (-not @(Get-Process -Name $procs -EA SilentlyContinue).Count) { return }
    # judged before the request goes out, so the window says it too: a bare
    # Reload button reads as "safe now" to anyone not watching this terminal
    $idle = Test-ChatIdle -AllProjects:$AllProjects
    $busy = if ($null -eq $idle) { $null } else { -not $idle }
    Write-ChatReloadRequest -Title $Title -Kind $Kind -Busy $busy
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
    switch ($idle) {
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
    .PARAMETER Archive
    Move the chat out of the way instead of deleting it; chatrestore brings it
    back. A Claude chat and its leftovers go to data/archive/, a Codex thread
    through codex archive. Copilot chats have an archive of their own in VS Code.
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
        [switch]$DropJobs,
        [switch]$Archive
    )
    Set-StrictMode -Off

    if (-not $Target) { Write-Error 'usage: chatrm <id>... | "<title>" [-Force] [-AllProjects] [-WaitForIdle] [-DropJobs] [-Archive]'; return }
    # one step for both paths below: delete, or put away
    $take = { param($h) if ($Archive) { Save-ChatArchive $h } else { Remove-ChatSession $h } }
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
                    if (& $take $hit) { $deleted++; $lastTitle = $hit.Record.Title }
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
            if (& $take $m) { $deleted++; $lastTitle = $m.Record.Title }
        }
    }

    if ($deleted) {
        $what = if ($deleted -eq 1) { $lastTitle } else { "$deleted chats" }
        $kind = if ($Archive) { 'archived' } else { 'deleted' }
        Write-ChatGhostAdvice -WaitForIdle:$WaitForIdle -AllProjects:$AllProjects -Title $what -Kind $kind
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
    # A watcher already running is still the old code. It hands over to one
    # running this copy after its current job - never in the middle of one.
    if (Test-ChatqWatcherAlive) {
        Save-ChatqText $script:ChatqRestartPath 'restart'
        Write-Host '    the running watcher switches to this copy after its current job' -ForegroundColor DarkGray
    }
    # the overlay has no job to finish: it starts again on this copy now
    if (Test-ChatOverlayAlive) {
        Send-ChatOverlayCommand 'restart'
        Write-Host '    the overlay restarts on this copy' -ForegroundColor DarkGray
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
    prompt in it. Refused while data/archive/ holds archived chats, since
    those are the only copy - chatrestore them first, or add -Force.
    .PARAMETER Force
    With -All: delete the archive too.
    .EXAMPLE
    chatuninstall
    .EXAMPLE
    chatuninstall -All
    #>
    [CmdletBinding()]
    param([switch]$All, [switch]$Force)
    Set-StrictMode -Off
    $kept = @(Get-ChatArchive | Where-Object { $_.Dir })
    if ($All -and $kept -and -not $Force) {
        Write-Host "  $($kept.Count) archived chat$(if ($kept.Count -ne 1) { 's are' } else { ' is' }) in data/archive/ - the only copy there is" -ForegroundColor Yellow
        Write-Host '  chatrestore brings them back; chatuninstall -All -Force deletes them with the rest' -ForegroundColor DarkGray
        return
    }

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
    # and the overlay, whose open lock file would keep -All from deleting data/
    if ((Test-ChatOverlayAlive) -and (Stop-ChatOverlay)) { Write-Host '  stopped the overlay' -ForegroundColor DarkGray }

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
    Write-Host '  chatrm ... -Archive    put it away instead; chatrestore brings it back' -ForegroundColor Cyan
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
    Write-Host '  see what is running' -ForegroundColor DarkGray
    Write-Host '  chatoverlay            every open chat and live usage, always on top' -ForegroundColor Cyan
    Write-Host '  chatoverlay -Print     the same, once, in this console' -ForegroundColor Cyan
    Write-Host '  chatoverlay -Theme     dark, light or system; -Opacity 85' -ForegroundColor Cyan
    Write-Host '  chatoverlay -UsageView lines, or bars with reset countdowns' -ForegroundColor Cyan
    Write-Host '  chatconsole            write, queue and continue chats in a window' -ForegroundColor Cyan
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
# start would lose its key handlers. Never in the background watcher or the
# overlay, which have no keyboard, nor anywhere else not interactive.
if (-not (Get-Variable -Name ChatNoKeyBindings -ValueOnly -EA SilentlyContinue) -and
    -not $env:CHATQ_WATCHER -and -not $env:CHATQ_OVERLAY -and [Environment]::UserInteractive -and
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
# written by chatinstall: a running watcher hands over to the new code
$script:ChatqRestartPath = Join-Path $script:ChatqData 'restart'
# tests only: a scriptblock that stands in for launching a real watcher
$script:ChatqSpawn = $null
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
$script:ChatqAlertReport = $null   # what each channel did with the last alert
$script:ChatqAlertJob = $null      # "#n" of the job an alert is about, for the hook
# seams the tests set: no real toast, no real network, no real idle clock
$script:ChatqToastSeam = $null
$script:ChatqNtfySeam = $null
$script:ChatqIdleSeam = $null
$script:ChatqHookTimeoutSec = $null
$script:ChatqClipboardSeam = $null
$script:ChatqAliveSeam = $null

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

function Write-ChatqPromptHint {
    # Everything after the command is the title, so a prompt typed bare joins
    # it, and the words meant for the chat go looking for one instead. What
    # that looks like is exactly this: a sentence that matched no title, and
    # the pick a guess. Said only then - a real title never prints it.
    param([string]$Typed, $Res, [switch]$HasPrompt, [switch]$Continue)
    if ($HasPrompt -or $Continue -or -not $Res -or $Res.Tier -ne 'nomatch') { return }
    $words = @($Typed -split '\s+' | Where-Object { $_ }).Count
    # a path or a URL in there is a prompt however short it is
    if ($words -lt 6 -and $Typed -notmatch '[\\/]|https?:') { return }
    Write-Host '     every word of that is the title - a prompt is never read from it' -ForegroundColor Yellow
    Write-Host "     did you mean:  chatq '<title>' -Prompt '<the rest>'" -ForegroundColor DarkGray
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
            # where it ran: this record's own, else the last one the tail names
            $cwd = if ($o.PSObject.Properties['cwd'] -and $o.cwd) { [string]$o.cwd }
            else {
                $cm = [regex]::Matches($t, '"cwd":"((?:[^"\\]|\\.)*)"')
                if ($cm.Count) { Convert-ChatJsonEscaped $cm[$cm.Count - 1].Groups[1].Value } else { $null }
            }
            return [pscustomobject]@{
                Uuid = $o.uuid; Type = $o.type; Limit = [bool]$limit; Overloaded = [bool]$over; ResetsAt = $resets
                At = ConvertTo-ChatqDate $o.timestamp; Text = $text; StopReason = $o.message.stop_reason; Cwd = $cwd
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
        $meta.Cwd = @($seen | Where-Object { (Get-ChatSlug $_) -eq $Group -and (Test-Path -LiteralPath $_) }) |
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

# tests: how many transcripts the cut-off scan has read
$script:ChatqCutOffReads = 0

function Get-ChatqCutOffChats {
    # Chats the limit - or a 529 Overloaded - stopped mid-task that nothing is
    # queued for: the ones you would otherwise walk round typing "continue"
    # into, one at a time. Only transcripts touched in the last $Hours count.
    # -Cache: the overlay asks every minute, so a transcript is read again
    # only once its length or time moved; the hashtable keeps what it said.
    # -Skip: session ids working right now - they are not cut off, and a
    # working chat's transcript moves all the time, so reading it would miss
    # the cache every minute.
    param([object[]]$Jobs, [int]$Hours = 12, [hashtable]$Cache, [string[]]$Skip)
    $root = Join-Path $script:ChatClaudeHome 'projects'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $since = (Get-Date).AddHours(-$Hours).ToUniversalTime()
    $busy = @{}
    # a job with no session - none should have one, but $null is no key
    foreach ($j in $Jobs) { if ($j.state -in 'queued', 'running' -and $j.sessionId) { $busy[[string]$j.sessionId] = $true } }
    foreach ($s in @($Skip)) { if ($s) { $busy[$s] = $true } }
    $rows = $null
    $seen = @{}
    $dirs = try { @([System.IO.DirectoryInfo]::new($root).EnumerateDirectories()) } catch { @() }
    $out = foreach ($d in $dirs) {
        # a folder gone since the list was taken, or a broken junction, is
        # one folder less - not the whole scan
        $files = try { @($d.EnumerateFiles('*.jsonl')) } catch { @() }
        foreach ($f in $files) {
            if ($f.LastWriteTimeUtc -le $since -or $f.Name.Length -ne 42 -or $f.BaseName -notmatch '^[0-9a-fA-F-]{36}$') { continue }
            if ($busy[$f.BaseName]) { continue }
            $sig = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
            $seen[$f.FullName] = $true
            if ($Cache -and $Cache.ContainsKey($f.FullName) -and $Cache[$f.FullName].Sig -eq $sig) {
                if ($Cache[$f.FullName].Row) { $Cache[$f.FullName].Row }
                continue
            }
            $script:ChatqCutOffReads++
            $last = Get-ChatqLastTurn $f.FullName
            $row = $null
            if ($last -and ($last.Limit -or $last.Overloaded)) {
                # The index is only as fresh as the last search, and a chat the
                # limit has just cut off is exactly the one that may be missing
                # from it. Read the title where it lives rather than printing a
                # uuid, which is not what the -Continue line below asks for.
                if ($null -eq $rows) { $rows = @{}; foreach ($r in @(Get-ChatIndex)) { $rows[$r.Path] = $r } }
                $title = if ($rows[$f.FullName]) { $rows[$f.FullName].Title }
                else {
                    $rec = try { & $script:ChatProviders['claude'].Describe $f } catch { $null }
                    if ($rec -and $rec.Title -and $rec.Title -ne '(empty)') { $rec.Title } else { $f.BaseName }
                }
                $row = [pscustomobject]@{
                    Id = $f.BaseName; Title = $title; Group = $d.Name; At = $last.At; ResetsAt = $last.ResetsAt
                    Why = if ($last.Limit) { 'limit' } else { 'overloaded' }; Path = $f.FullName; Cwd = $last.Cwd
                }
            }
            if ($Cache) { $Cache[$f.FullName] = @{ Sig = $sig; Row = $row } }
            if ($row) { $row }
        }
    }
    # what fell out of the window, or went, is forgotten
    if ($Cache) { foreach ($k in @($Cache.Keys)) { if (-not $seen[$k]) { $Cache.Remove($k) } } }
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
    # The one queue order, which the watcher, the "sends" column, the list and
    # the board all walk: jobs put first (the latest -First ahead), then oldest
    # first. A lane that is waiting is skipped as a whole, so "first" means the
    # front of its own lane.
    # Dates, not strings: pwsh 7 reads the stamps back as [datetime], whose
    # string form does not sort in time order.
    $zero = [datetime]::MinValue
    return @($jobs | Sort-Object @{ Expression = { if ($_.PSObject.Properties['first'] -and $_.first) { 0 } else { 1 } } },
        @{ Expression = { $d = if ($_.PSObject.Properties['first']) { ConvertTo-ChatqDate $_.first } else { $null }; if ($d) { $d } else { $zero } }; Descending = $true },
        @{ Expression = { $d = ConvertTo-ChatqDate $_.createdAt; if ($d) { $d } else { $zero } } })
}

function Save-ChatqJob {
    param($Job)
    Save-ChatqJson (Join-Path $script:ChatqQueueDir "$($Job.id).json") $Job
}

function Save-ChatqJson {
    param([string]$Path, $Object)
    Save-ChatqText $Path ($Object | ConvertTo-Json -Depth 8)
}

function Write-ChatqJobLog {
    # Every move a job makes, in one file that outlives it. A job's own history
    # goes with its file, so a chatqrm used to leave no trace at all - where a
    # job went could only be guessed from the watcher logging an empty queue.
    # Best effort: the watcher and a shell both append, and a line lost to a
    # collision is better than either of them stopping over a diary.
    param([string]$Text)
    try {
        New-ChatqDir $script:ChatqLogDir
        $p = Join-Path $script:ChatqLogDir 'jobs.log'
        if ((Test-Path -LiteralPath $p) -and (Get-Item -LiteralPath $p).Length -gt 1MB) {
            Move-Item -LiteralPath $p -Destination "$p.1" -Force
        }
        [System.IO.File]::AppendAllText($p, "$((Get-Date).ToString('o'))  $Text`n", (New-Object System.Text.UTF8Encoding $false))
    }
    catch {}
}

function Set-ChatqJobState {
    param($Job, [string]$State, [string]$Why)
    $Job.state = $State
    $Job.history = @(@($Job.history) + [pscustomobject]@{ at = (Get-ChatqStamp); state = $State; why = $Why })
    Save-ChatqJob $Job
    Write-ChatqJobLog "#$($Job.seq) $State$(if ($Why) { " - $Why" }) $($script:ChatqDot) $($Job.title)"
}

function Find-ChatqJob {
    # by the #n shown in lists, or by (a prefix of) the id
    param([string]$Ref, [object[]]$Jobs)
    if (-not $Jobs) { $Jobs = @(Get-ChatqJobs) }
    $r = $Ref.Trim().TrimStart('#')
    if ($r -match '^\d+$') { return @($Jobs | Where-Object { [int]$_.seq -eq [int]$r }) | Select-Object -First 1 }
    # the whole id first: a job queued for the same chat in the same second
    # is that id with -2 after it, and would make the prefix ambiguous
    $exact = @($Jobs | Where-Object { $_.id -eq $r })
    if ($exact.Count -eq 1) { return $exact[0] }
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

#region attachments -----------------------------------------------------------
# A job's files live in data/queue/<job id>/, copied there when it is queued:
# the original may move or change in the hours before the job sends, and by
# then the clipboard holds whatever was copied last. What is in that folder
# when the job sends is what goes - delete a file there to drop it.
# A link in the prompt is an attachment only when it points into data/queue/,
# where VS Code saves an image pasted into the prompt tab. A link to any other
# file names that file where it is, for the chat to open or change there.
# Neither CLI needs more than a path for most of it. Claude Code opens an
# image with its own Read tool and sees the picture, and reads text and PDF the
# same way - named in the prompt, from outside the project, in the strictest
# unattended mode (spike S18). Codex also takes images properly, with -i.

$script:ChatqImageExt = @('.png', '.jpg', '.jpeg', '.gif', '.webp')
$script:ChatqAttachWarnCount = 10
$script:ChatqAttachWarnBytes = 20MB

function Get-ChatqAttachDir {
    param($Job)
    Join-Path $script:ChatqQueueDir $Job.id
}

function Get-ChatqAttachments {
    # in the order they were added: a copy is created when it is made, whatever
    # time its original says
    param($Job)
    $d = Get-ChatqAttachDir $Job
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    return @(Get-ChildItem -LiteralPath $d -File -EA SilentlyContinue | Sort-Object CreationTimeUtc, Name)
}

function Add-ChatqAttachment {
    # One file in, under a name nothing else in the folder has, with no space
    # in it: a markdown link breaks on one. Moved rather than copied when asked
    # - a file VS Code saved beside the prompt belongs to nobody else.
    param([string]$Dir, [string]$Source, [switch]$Move)
    New-ChatqDir $Dir
    $name = ([System.IO.Path]::GetFileName($Source)) -replace '[^\w.\-]+', '-'
    if (-not $name.Trim('.', '-')) { $name = 'file' }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext = [System.IO.Path]::GetExtension($name)
    $dest = Join-Path $Dir $name
    for ($n = 2; Test-Path -LiteralPath $dest; $n++) { $dest = Join-Path $Dir "$base-$n$ext" }
    # Stop, so a file gone or locked since it was checked throws: both cmdlets
    # otherwise only print their error, and the job would go without the file
    if ($Move) { Move-Item -LiteralPath $Source -Destination $dest -ErrorAction Stop }
    else { Copy-Item -LiteralPath $Source -Destination $dest -ErrorAction Stop }
    # a copy keeps its original's times, and the order goes by when it came in
    $f = Get-Item -LiteralPath $dest -ErrorAction Stop
    try { $f.CreationTimeUtc = [datetime]::UtcNow } catch {}
    return $f
}

function Add-ChatqAttachmentBytes {
    param([string]$Dir, [string]$Name, [byte[]]$Bytes)
    New-ChatqDir $Dir
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $ext = [System.IO.Path]::GetExtension($Name)
    $dest = Join-Path $Dir $Name
    for ($n = 2; Test-Path -LiteralPath $dest; $n++) { $dest = Join-Path $Dir "$base-$n$ext" }
    [System.IO.File]::WriteAllBytes($dest, $Bytes)
    return (Get-Item -LiteralPath $dest)
}

function Get-ChatqPromptLinks {
    # The files a prompt links to inside data/queue/ - ![alt](path) or
    # [text](path), relative to the prompt file, which is what VS Code writes
    # when an image is pasted, or a media file dropped, into the prompt tab.
    # Nothing outside is even looked at. A link to a project file names it
    # where it is: copied, the chat would read and edit a snapshot instead.
    # ../config.json would reach chatq's own data, and testing a \\host path
    # opens an SMB connection to that host.
    # Every occurrence, with where its target sits in the text, so a rewrite
    # touches that link and no other - a plain replace of "(image.png" would
    # also rewrite "(image.png.bak)".
    param([string]$Text)
    if (-not $Text) { return @() }
    $queue = [System.IO.Path]::GetFullPath($script:ChatqQueueDir).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    # one level of parentheses inside a target: shot(1).png is a name
    $rx = '!?\[[^\]\r\n]*\]\(\s*(<[^>\r\n]+>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+"[^"\r\n]*")?\s*\)'
    return @(foreach ($m in [regex]::Matches($Text, $rx)) {
            $g = $m.Groups[1]
            $p = $g.Value.Trim('<', '>').Trim()
            if ($p -match '^[a-zA-Z]:[\\/]') { $cand = $p }                             # a drive path
            elseif ($p -match '^[a-zA-Z][\w+.-]*:' -or $p -match '^[\\/]{2}') { continue }   # a URL, file: too, or a share
            else { $cand = Join-Path $script:ChatqQueueDir ([uri]::UnescapeDataString($p)) }
            # decided on the string alone, before anything touches a disk; an
            # anchor like #top simply names no file in there
            $full = try { [System.IO.Path]::GetFullPath($cand) } catch { continue }
            if (-not $full.StartsWith($queue, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            [pscustomobject]@{ Index = $g.Index; Length = $g.Length; Path = $full }
        })
}

function Sync-ChatqAttachments {
    # Bring the files the prompt links to in data/queue/ into the job's own
    # folder, and point each link there. A pasted image belongs to nobody, so
    # it moves - out of a folder VS Code made for it too, which then goes if
    # empty. One in another job's folder is that job's, and is copied. Run when
    # the job is queued and again just before it sends, so an image pasted into
    # a prompt reopened with chatq <n> counts. Returns the files it could not
    # bring in.
    param($Job)
    $pp = Get-ChatqPromptPath $Job
    if (-not (Test-Path -LiteralPath $pp)) { return @() }
    $text = [System.IO.File]::ReadAllText($pp, [System.Text.Encoding]::UTF8)
    $dir = [System.IO.Path]::GetFullPath((Get-ChatqAttachDir $Job))
    $queue = [System.IO.Path]::GetFullPath($script:ChatqQueueDir).TrimEnd('\', '/')
    # read once, before anything moves - a moved file is no longer where its
    # link says, and would drop out of a second reading
    $links = @(Get-ChatqPromptLinks $text)
    $new = @{}
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $links) {
        # one copy per file, however many times the prompt links it
        $key = $l.Path.ToLowerInvariant()
        if ($new.ContainsKey($key)) { continue }
        # already the job's own
        if ($l.Path.StartsWith($dir + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $rel = $l.Path.Substring($queue.Length + 1)
        $top = ($rel -split '[\\/]', 2)[0]
        $atRoot = $rel -notmatch '[\\/]'
        # never the queue's own files - a job, its prompt, a cancel
        if ($atRoot -and [System.IO.Path]::GetExtension($rel) -in '.md', '.json', '.cancel') { continue }
        $otherJob = -not $atRoot -and (Test-Path -LiteralPath (Join-Path $script:ChatqQueueDir "$top.json"))
        $f = try { Add-ChatqAttachment $dir $l.Path -Move:(-not $otherJob) } catch { $failed.Add($l.Path); $null }
        if (-not $f) { continue }
        $new[$key] = "$($Job.id)/$($f.Name)"
        if (-not $atRoot -and -not $otherJob) {
            $from = Split-Path -Parent $l.Path
            if (-not @(Get-ChildItem -LiteralPath $from -Force -EA SilentlyContinue).Count) { Remove-Item -LiteralPath $from -Force -EA SilentlyContinue }
        }
    }
    if ($new.Count) {
        # from the end backwards, so each rewrite leaves the earlier positions true
        $sb = [System.Text.StringBuilder]::new($text)
        foreach ($l in @($links | Sort-Object Index -Descending)) {
            $to = $new[$l.Path.ToLowerInvariant()]
            if ($to) { [void]$sb.Remove($l.Index, $l.Length).Insert($l.Index, $to) }
        }
        Save-ChatqText $pp $sb.ToString()
    }
    return @($failed)
}

function Format-ChatqAttachFooter {
    # The wording both CLIs were seen to act on in spike S18: every file read,
    # the images looked at
    param([object[]]$Files)
    if (-not $Files) { return '' }
    return "`n`nAttached files - read each one:`n" + (($Files | ForEach-Object { "- $($_.FullName)" }) -join "`n")
}

function Format-ChatqAttachSummary {
    param([object[]]$Files)
    $n = @($Files).Count
    if (-not $n) { return '' }
    $bytes = ($Files | Measure-Object -Property Length -Sum).Sum
    $mb = if ($bytes -ge 1MB) { '{0:N1} MB' -f ($bytes / 1MB) } else { '{0:N0} KB' -f [Math]::Max(1, $bytes / 1KB) }
    $names = ($Files | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', '
    if ($n -gt 4) { $names += ", +$($n - 4) more" }
    return "$n file$(if ($n -ne 1) { 's' }) ($mb): $names"
}

function Read-ChatqAttachSources {
    # -Attach and -Paste, resolved while you are here: the files checked now -
    # one found missing at 3 a.m. could only fail the job - and the clipboard
    # read now, since by then it holds whatever was copied last. Nothing is
    # copied yet. Error set means nothing should be queued. Skipped: folders
    # the clipboard held, for the caller to mention.
    param([string[]]$Attach, [switch]$Paste)
    $r = [pscustomobject]@{ Error = $null; Files = [System.Collections.Generic.List[string]]::new(); Image = $null; Text = $null; Skipped = [System.Collections.Generic.List[string]]::new() }
    $seen = @{}
    foreach ($a in @($Attach | Where-Object { $_ })) {
        $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a)
        # a name with [ ] in it is a name first; only one that is not a file
        # is tried as a wildcard - -Attach .\shots\*.png
        $hits = if (Test-Path -LiteralPath $p -PathType Leaf) { @($p) }
        elseif ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($a)) {
            @(Get-ChildItem -Path $a -File -EA SilentlyContinue | Sort-Object Name | ForEach-Object { $_.FullName })
        }
        else { @() }
        if (-not $hits) { $r.Error = "no such file: $a"; return $r }
        foreach ($h in $hits) {
            # the same file twice is sent once
            if (-not $seen.ContainsKey($h.ToLowerInvariant())) { $seen[$h.ToLowerInvariant()] = $true; $r.Files.Add($h) }
        }
    }
    if ($Paste) {
        $clip = Get-ChatqClipboard
        if (-not $clip) { $r.Error = 'the clipboard cannot be read here - give the file with -Attach instead'; return $r }
        foreach ($f in @($clip.Files)) {
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $r.Skipped.Add($f); continue }
            if (-not $seen.ContainsKey($f.ToLowerInvariant())) { $seen[$f.ToLowerInvariant()] = $true; $r.Files.Add($f) }
        }
        $r.Image = $clip.Image
        # text only when nothing else came: a copied image often brings its
        # caption or HTML along, and that is not what was meant
        if (-not $r.Image -and -not @($clip.Files).Count -and $clip.Text -and $clip.Text.Trim()) { $r.Text = $clip.Text }
        if (-not $r.Image -and -not $r.Files.Count -and -not $r.Text) {
            $r.Error = 'nothing on the clipboard to paste - copy a screenshot, some files or text first'
        }
    }
    return $r
}

function Save-ChatqAttachSources {
    # Into the job's folder; throws when one cannot be copied, having taken
    # back what this call copied - and only that: adding to a queued job, the
    # folder already holds files of its own. -Move: the files are the
    # console's own staged copies, so they move in, and move back on a
    # failure. Images: more than one pasted image, as @{ Name; Bytes }.
    param([string]$Dir, $Got, [switch]$Move)
    $added = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($s in @($Got.Files)) { if ($s) { $added.Add(@{ To = (Add-ChatqAttachment $Dir $s -Move:$Move).FullName; From = $(if ($Move) { $s }) }) } }
        if ($Got.Image) { $added.Add(@{ To = (Add-ChatqAttachmentBytes $Dir 'clip.png' $Got.Image).FullName }) }
        $more = if ($Got -is [hashtable]) { $Got['Images'] } elseif ($Got.PSObject.Properties['Images']) { $Got.Images } else { $null }
        foreach ($im in @($more)) { if ($im) { $added.Add(@{ To = (Add-ChatqAttachmentBytes $Dir ([string]$im.Name) ([byte[]]$im.Bytes)).FullName }) } }
        return @($added | ForEach-Object { $_.To })
    }
    catch {
        foreach ($a in $added) {
            if ($a.From) { Move-Item -LiteralPath $a.To -Destination $a.From -Force -EA SilentlyContinue }
            else { Remove-Item -LiteralPath $a.To -Force -EA SilentlyContinue }
        }
        if (-not @(Get-ChildItem -LiteralPath $Dir -Force -EA SilentlyContinue).Count) { Remove-Item -LiteralPath $Dir -Force -EA SilentlyContinue }
        throw
    }
}

# What the clipboard holds, read where the clipboard can be read: an STA
# thread. Windows PowerShell's console is one; where this shell is not, a
# child Windows PowerShell reads it. Either way it lands as files in a folder
# of data/ - not JSON: a screenshot in base64 is past the 2 MB that 5.1's
# ConvertFrom-Json will take. A "PNG" entry first, which keeps transparency
# and the exact bytes, then the plain bitmap a screenshot puts there. Text is
# written only when there is nothing else, the one case it is used in. The
# folder comes in through the environment, never spliced into the code: a
# path is not code, whatever quotes it holds.
$script:ChatqClipCode = @'
$Out = $env:CHATQ_CLIP_OUT
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$cb = [System.Windows.Forms.Clipboard]
$u8 = New-Object System.Text.UTF8Encoding $false
$got = $false
if ($cb::ContainsFileDropList()) {
    [System.IO.File]::WriteAllLines((Join-Path $Out 'files.txt'), [string[]]@($cb::GetFileDropList()), $u8)
    $got = $true
}
else {
    $png = $cb::GetData('PNG')
    if ($png -is [System.IO.MemoryStream]) { [System.IO.File]::WriteAllBytes((Join-Path $Out 'clip.png'), $png.ToArray()); $got = $true }
    elseif ($cb::ContainsImage()) {
        $img = $cb::GetImage()
        $img.Save((Join-Path $Out 'clip.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $img.Dispose()
        $got = $true
    }
}
if (-not $got -and $cb::ContainsText()) { [System.IO.File]::WriteAllText((Join-Path $Out 'clip.txt'), $cb::GetText(), $u8) }
'@

function Get-ChatqClipboard {
    # @{ Image = [byte[]]; Files = [string[]]; Text = [string] }, or $null where
    # it cannot be read
    if ($script:ChatqClipboardSeam) { return & $script:ChatqClipboardSeam }
    if (-not $script:ChatqIsWindows) { return $null }
    # one a killed shell left behind is swept up by the next read
    Get-ChildItem -LiteralPath $script:ChatqData -Directory -Filter 'clip-*' -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } | Remove-Item -Recurse -Force -EA SilentlyContinue
    $out = Join-Path $script:ChatqData ('clip-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-ChatqDir $out
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
            $was = $env:CHATQ_CLIP_OUT
            $env:CHATQ_CLIP_OUT = $out
            try { & ([scriptblock]::Create($script:ChatqClipCode)) } finally { $env:CHATQ_CLIP_OUT = $was }
        }
        else {
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script:ChatqClipCode))
            $null = Invoke-ChatqProcess -Exe $ps -ArgList @('-NoProfile', '-NonInteractive', '-STA', '-EncodedCommand', $enc) -StdIn '' -TimeoutSec 30 `
                -SetEnv @{ CHATQ_CLIP_OUT = $out }
        }
        $img = Join-Path $out 'clip.png'
        $lst = Join-Path $out 'files.txt'
        $txt = Join-Path $out 'clip.txt'
        return [pscustomobject]@{
            Image = if (Test-Path -LiteralPath $img) { [System.IO.File]::ReadAllBytes($img) } else { $null }
            Files = if (Test-Path -LiteralPath $lst) { @([System.IO.File]::ReadAllLines($lst, [System.Text.Encoding]::UTF8) | Where-Object { $_ }) } else { @() }
            Text  = if (Test-Path -LiteralPath $txt) { [System.IO.File]::ReadAllText($txt, [System.Text.Encoding]::UTF8) } else { $null }
        }
    }
    catch { return $null }
    finally { Remove-Item -LiteralPath $out -Recurse -Force -EA SilentlyContinue }
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
# A dropped connection is worth another try; a refused login is not - every
# retry would fail the same way until someone logs in again, or renews the
# subscription, which is refused with the same 401 or 403. Both are only
# ever matched against error text, never against a reply.
$script:ChatqNetworkRx = '(?i)ECONNRESET|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|socket hang up|Connection error|fetch failed|network error|stream disconnected|error sending request|Premature close|connection reset'
$script:ChatqAuthRx = '(?i)OAuth token (has )?expired|invalid (api key|x-api-key|bearer token)|authentication_error|not logged in|please (run )?/login|401 Unauthorized|403 Forbidden'

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

function Get-ChatqAuthWords {
    # What the CLI said when it turned the login down: the API's own message
    # when the error carries one, else the text itself, cut short. An expired
    # login and a subscription that ended are both refused with a 401 or 403,
    # and only these words tell which it was. Error text only - never a reply.
    param([string]$Text, $Status)
    $t = ($Text -replace '\s+', ' ').Trim()
    $msg = $null
    if ($t -match '"message"\s*:\s*("(?:[^"\\]|\\.)*")') {
        $msg = try { [string]($Matches[1] | ConvertFrom-Json) } catch { $null }
    }
    if ($msg) {
        # Claude prints "API Error: 401", Codex "unexpected status 401"
        $code = if ($Status) { [string]$Status } elseif ($t -match '(?i)(?:API Error|status):?\s*(\d{3})\b') { $Matches[1] } else { $null }
        if ($code) { $msg = "$msg ($code)" }
    }
    else {
        # log noise ahead of the refusal would crowd it out of the cut below
        $m = [regex]::Match($t, $script:ChatqAuthRx)
        $msg = if ($m.Success -and $m.Index + $m.Length -gt 159) { $script:ChatqEllipsis + $t.Substring($m.Index) } else { $t }
    }
    if (-not $msg) { $msg = if ($Status) { "API Error $Status" } else { 'no reason given' } }
    if ($msg.Length -gt 160) { $msg = $msg.Substring(0, 159) + $script:ChatqEllipsis }
    return $msg
}

function Get-ChatqAuthDetail {
    # the error text whole, on one line, for the watcher log: the message alone
    # drops the error's type, and a new way of being refused is read from this
    param([string]$Text)
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt 1000) { $t = $t.Substring(0, 999) + $script:ChatqEllipsis }
    return $t
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
        # replies before it broke: a run that got nowhere counts toward the cap
        assistant = $St.Assistant; detail = $null
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
    # Not chatq's own stop (the 4 h cap, a cancel): that is no network trouble,
    # and a job that ran four hours must not quietly run three times more.
    if ($broke -and -not $Proc.Stopped) {
        $err = "$text $($Proc.StdErr)"
        if (($status -and [int]$status -in 401, 403) -or $err -match $script:ChatqAuthRx) {
            # $text may be the last reply, which is no part of the refusal
            $said = "$(if ($res -and $res.is_error) { [string]$res.result }) $($Proc.StdErr)"
            $o.kind = 'auth'; $o.reason = "login refused: $(Get-ChatqAuthWords $said $status)"
            $o.detail = Get-ChatqAuthDetail $said
            return [pscustomobject]$o
        }
        if ($err -match $script:ChatqNetworkRx) {
            $o.kind = 'network'; $o.reason = "network: $($Matches[0])"
            return [pscustomobject]$o
        }
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
        assistant = $St.Assistant; detail = $null
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
    if (-not $Proc.Stopped) {
        if ($fail -match $script:ChatqAuthRx) {
            $o.kind = 'auth'; $o.reason = "login refused: $(Get-ChatqAuthWords $fail)"; $o.detail = Get-ChatqAuthDetail $fail
            return [pscustomobject]$o
        }
        if ($fail -match $script:ChatqNetworkRx) { $o.kind = 'network'; $o.reason = "network: $($Matches[0])"; return [pscustomobject]$o }
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
    if (-not $exe) { return [pscustomobject]@{ Allowed = $false; Limited = $false; Overloaded = $false; Auth = $false; Error = "no $Provider CLI found"; Until = $null; Type = $null; Detail = $null } }
    $dir = if ($Job.cwd -and (Test-Path -LiteralPath $Job.cwd)) { $Job.cwd } else { $script:ChatqData }
    $st = New-ChatqRunState
    # the model the run will use: one given with -Model, else the chat's own
    $model = Get-ChatqRunModel $Job
    if ($Provider -eq 'codex') {
        $args2 = @('exec', '--ephemeral', '--skip-git-repo-check', '--json', '-s', 'read-only')
        if ($Job.runModel) { $args2 += @('-m', $Job.runModel) }
        $args2 += '-'
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
        if ($model -and -not $NoModel) { $args2 += @('--model', $model) }
        $proc = Invoke-ChatqProcess -Exe $exe -ArgList $args2 -WorkDir $dir -StdIn 'Reply with one word: ok' `
            -SetEnv @{ CLAUDE_CONFIG_DIR = $Job.home } -TimeoutSec 180 -OnLine { param($l) Update-ChatqClaudeState $st $l }
        $out = Get-ChatqClaudeOutcome $st $proc 'default'
        $ok = $out.kind -notin 'limited', 'overloaded' -and $st.Result -and -not $st.Result.is_error
        # a model id from months ago may be retired; the run itself never names
        # one (a resume keeps the chat's model), so ask again without it. Not
        # when -Model named one: the run will use exactly that, so the probe must.
        if (-not $ok -and $out.kind -eq 'failed' -and $model -and -not $Job.runModel -and -not $NoModel) {
            return (Invoke-ChatqProbe $Provider $Job -NoModel)
        }
    }
    $until = if ($out.resetsAt) { ConvertTo-ChatqDate $out.resetsAt } else { $null }
    return [pscustomobject]@{
        Allowed    = [bool]$ok
        Limited    = $out.kind -eq 'limited'
        Overloaded = $out.kind -eq 'overloaded'
        Auth       = $out.kind -eq 'auth'
        Until      = $until
        Type       = $out.limitType
        Error      = if (-not $ok -and $out.kind -notin 'limited', 'overloaded') { $(if ($out.reason) { $out.reason } else { $out.kind }) } else { $null }
        Detail     = $out.detail
    }
}

function Get-ChatqRunModel {
    # -Model for this job if given, else the chat's own - which a resume keeps
    # by itself, so it is only ever named to the probe
    param($Job)
    if ($Job.PSObject.Properties['runModel'] -and $Job.runModel) { return [string]$Job.runModel }
    return [string]$Job.model
}

#endregion

#region running one job -------------------------------------------------------

function Test-ChatqFreshChat {
    # a new chat's job whose chat does not exist yet: nothing to resume, no
    # transcript to check, and no window can have it open
    param($Job)
    return [bool]($Job.kind -eq 'new' -and -not ($Job.path -and (Test-Path -LiteralPath $Job.path)))
}

function Update-ChatqNewChatPath {
    # A new chat's transcript is where its folder's slug says, unless Claude
    # named that folder otherwise: a path over 200 characters is cut and
    # hashed, and CLAUDE_CODE_PROJECT_DIR_NAME names it outright. Looked for
    # by its id in every project, and kept on the job once found - else every
    # retry would pass --session-id again, which Claude refuses once the
    # session exists.
    param($Job)
    if ($Job.kind -ne 'new' -or $Job.provider -ne 'claude' -or -not $Job.sessionId) { return }
    if ($Job.path -and (Test-Path -LiteralPath $Job.path)) { return }
    $base = if ($Job.home) { [string]$Job.home } else { $script:ChatClaudeHome }
    $p = Find-ChatOverlayTranscript $base $null ([string]$Job.sessionId)
    if (-not $p) { return }
    Set-ChatqProp $Job 'path' $p
    Set-ChatqProp $Job 'group' (Split-Path (Split-Path $p -Parent) -Leaf)
}

function Invoke-ChatqRun {
    # Deliver one job's prompt into its chat and read what came back. The
    # caller owns the job's state; this only runs and classifies.
    param($Job, [string]$Prompt, [scriptblock]$OnTick, [scriptblock]$OnStart, [object[]]$Files)
    $exe = Find-ChatqExe $Job.provider
    if (-not $exe) { return [pscustomobject]@{ kind = 'failed'; reason = "no $($Job.provider) CLI found - install it or set CHATQ_$($Job.provider.ToUpper())" } }
    $log = Join-Path $script:ChatqLogDir "$($Job.id).jsonl"
    $st = New-ChatqRunState
    $mode = if ($Job.mode) { $Job.mode } elseif ($Job.modeAtQueue) { $Job.modeAtQueue } else { 'default' }
    # Files named under the prompt: all of them for Claude, which opens each
    # itself; for Codex the ones that are not images, which go with -i instead -
    # the shape spike S18 saw both act on
    $Files = @($Files | Where-Object { $_ })
    $imgs = @($Files | Where-Object { $_.Extension.ToLowerInvariant() -in $script:ChatqImageExt })
    if ($Job.provider -eq 'codex') {
        $Prompt += Format-ChatqAttachFooter @($Files | Where-Object { $_.Extension.ToLowerInvariant() -notin $script:ChatqImageExt })
        if ($imgs) { $Prompt += "`n`n($($imgs.Count) image$(if ($imgs.Count -ne 1) { 's are' } else { ' is' }) attached to this message.)" }
    }
    elseif ($Files) { $Prompt += Format-ChatqAttachFooter $Files }
    if ($Job.provider -eq 'codex') {
        $sandbox = if ($Job.sandbox) { $Job.sandbox } else { 'workspace-write' }
        $a = @('exec', 'resume', '--json', '--skip-git-repo-check', '-c', "sandbox_mode=$sandbox")
        if ($Job.network) { $a += @('-c', 'sandbox_workspace_write.network_access=true') }
        if ($Job.runModel) { $a += @('-m', $Job.runModel) }
        foreach ($f in $imgs) { $a += @('-i', $f.FullName) }
        # -i can take several values, so -- keeps the thread id from being read
        # as one more image
        if ($imgs) { $a += '--' }
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
    # A new chat's first run: the session id it was given when queued, and its
    # name as the title the chat list shows (spike S25). Once its transcript
    # exists - the prompt got that far before a limit or a dropped
    # connection - it is resumed like any other, never started twice.
    # A claude.cmd from npm runs through cmd.exe, which reads \" as no escape
    # at all: a quote in the title would end the argument there and hand the
    # rest - an & and what follows - to cmd as a command of its own. The
    # title shows in a list, and loses nothing it needs without these.
    $name = [string]$Job.title
    if ($exe -match '\.(cmd|bat)$') { $name = (($name -replace '["%!&|<>^]', ' ') -replace '\s+', ' ').Trim() }
    $start = if (Test-ChatqFreshChat $Job) { @('--session-id', $Job.sessionId, '--name', $name) } else { @('--resume', $Job.sessionId) }
    $a = @('-p') + $start + @('--output-format', 'stream-json', '--verbose',
        '--permission-mode', $mode, '--permission-prompts', 'none')
    # only when -Model asked for one: a resume keeps the chat's own model, and
    # naming it would pin the run to an id that may since have been retired
    if ($Job.runModel) { $a += @('--model', $Job.runModel) }
    # Claude Code 2.1.280 read files outside the project unasked (spike S18);
    # naming the job's folder keeps that true under a stricter version or a
    # settings file that limits reads to the workspace
    if ($Files) { $a += @('--add-dir', (Get-ChatqAttachDir $Job)) }
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
                        [pscustomobject]@{ SessionId = $_.sessionId; Pid = $_.pid; Status = $_.status; Kind = $_.kind; WaitingFor = $_.waitingFor; ProcStart = $null; StartedAt = $_.startedAt }
                    })
            }
        }
        catch {}
    }
    # A registry file can outlive its process, and the pid be reused by
    # something else - only a claude that started when the file says counts.
    $dir = Join-Path (Get-ChatqHomeDir 'claude' $ConfigDir) 'sessions'
    return @(Read-ChatqSessionRegistry $dir | Where-Object { Test-ChatqSessionAlive $_ } | ForEach-Object {
            [pscustomobject]@{ SessionId = $_.SessionId; Pid = $_.Pid; Status = $_.Status; Kind = $_.Kind; WaitingFor = $_.WaitingFor; ProcStart = $_.ProcStart; StartedAt = $_.StartedAt }
        })
}

function Read-ChatqSessionRegistry {
    <#
    Claude Code's own list of what runs: sessions/<pid>.json, one per process,
    rewritten as its status moves between idle, busy and waiting. Only
    <digits>.json is read. The <pid>.<hash>.key beside each one is that
    session's messaging secret, and is never opened.
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
    Every alert goes to logs/alerts.log, then to whichever channels are set up:
      toast    the desktop, on by default - free, local, nothing leaves the PC
      command  your own PowerShell, with the alert in $env:CHATQ_* (chatqnotify -Command)
      join     the phone, through Join (joaomgcd)
      ntfy     the phone, through ntfy
    The two phone channels stay quiet while you are at the PC - keyboard or
    mouse used in the last quietMinutes (5) - since the toast says it there.
    -Loud (chatqnotify -Test) goes through regardless. Titles all start
    "chatq <dot> ", so a Tasker profile can filter them - or match only "needs
    input" and "failed". What the text carries (chat title, an excerpt of the
    reply) passes through the push service's servers.
    #>
    param([string]$Event, [string]$Text, [int]$Priority = 0, [switch]$Loud)
    $title = "chatq $($script:ChatqDot) $Event"
    $script:ChatqAlertReport = [System.Collections.Generic.List[string]]::new()
    try {
        New-ChatqDir $script:ChatqLogDir
        $line = "{0}`t{1}`t{2}" -f (Get-Date).ToString('o'), $Event, ($Text -replace '\s+', ' ')
        [System.IO.File]::AppendAllText((Join-Path $script:ChatqLogDir 'alerts.log'), $line + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
    catch {}
    $cfg = Get-ChatqConfig
    $present = Test-ChatqUserPresent $cfg
    $toastOn = -not ($cfg.PSObject.Properties['toast'] -and $cfg.toast -eq $false)
    if ($toastOn) {
        try { Show-ChatqToast $title $Text; $script:ChatqAlertReport.Add('toast: shown') }
        catch { $script:ChatqAlertReport.Add("toast: $($_.Exception.Message)") }
    }
    $e = Invoke-ChatqAlertCommand $cfg $Event $title $Text $Priority $present
    if ($e) { $script:ChatqAlertReport.Add($e) }
    elseif ($cfg.PSObject.Properties['command'] -and $cfg.command) { $script:ChatqAlertReport.Add('command: ran') }

    $phones = @()
    if ($cfg.PSObject.Properties['join'] -and $cfg.join) { $phones += 'join' }
    if ($cfg.PSObject.Properties['ntfy'] -and $cfg.ntfy) { $phones += 'ntfy' }
    if (-not $phones) { $script:ChatqLastAlertError = 'no phone channel set up'; return $false }
    if ($present -and -not $Loud) {
        $script:ChatqAlertReport.Add('phone: skipped - you are at the PC')
        $script:ChatqLastAlertError = 'you are at the PC, so the phone was left alone'
        return $false
    }
    $sent = $false
    $script:ChatqLastAlertError = $null
    foreach ($ch in $phones) {
        $err = if ($ch -eq 'join') { Send-ChatqJoin $cfg $title $Text $Priority } else { Send-ChatqNtfy $cfg $title $Text $Priority }
        if ($err) { $script:ChatqAlertReport.Add("${ch}: $err"); $script:ChatqLastAlertError = "${ch}: $err" }
        else { $script:ChatqAlertReport.Add("${ch}: sent"); $sent = $true }
    }
    return $sent
}

function Send-ChatqJoin {
    # $null when sent, else what went wrong
    param($Cfg, [string]$Title, [string]$Text, [int]$Priority)
    $key = Unprotect-ChatqSecret $Cfg.join.apiKey
    if (-not $key -or -not $Cfg.join.device) { return 'no key or device set' }
    Enable-ChatqTls12
    $url = Get-ChatqJoinUrl $key $Cfg.join.device $Title $Text $Priority
    $last = $null
    for ($try = 1; $try -le 3; $try++) {
        try {
            $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20 -UseBasicParsing
            if ($r.success) { return $null }
            return [string]$r.errorMessage
        }
        catch { $last = $_.Exception.Message; Start-Sleep -Seconds (2 * $try) }
    }
    return $last
}

function Send-ChatqNtfy {
    # Published as JSON to the server root rather than with Title/Priority
    # headers: .NET Framework will not put Hangul - or the middle dot every
    # title starts with - into a header. $null when sent, else the error.
    param($Cfg, [string]$Title, [string]$Text, [int]$Priority)
    $topic = Unprotect-ChatqSecret $Cfg.ntfy.topic
    if (-not $topic) { return 'no topic set' }
    $server = if ($Cfg.ntfy.server) { ([string]$Cfg.ntfy.server).TrimEnd('/') } else { 'https://ntfy.sh' }
    $body = [ordered]@{
        topic = $topic; title = $Title; message = $Text; tags = @('robot')
        # chatq's 0/1/2 onto ntfy's default/high/urgent
        priority = @(3, 4, 5)[[Math]::Min(2, [Math]::Max(0, $Priority))]
    } | ConvertTo-Json -Compress
    $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($body)
    $headers = @{}
    $tok = if ($Cfg.ntfy.PSObject.Properties['token']) { Unprotect-ChatqSecret $Cfg.ntfy.token } else { $null }
    if ($tok) { $headers['Authorization'] = "Bearer $tok" }
    if ($script:ChatqNtfySeam) { & $script:ChatqNtfySeam $server $body $headers; return $null }   # tests
    Enable-ChatqTls12
    $last = $null
    for ($try = 1; $try -le 3; $try++) {
        try {
            $null = Invoke-RestMethod -Uri $server -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' `
                -Headers $headers -TimeoutSec 20 -UseBasicParsing
            return $null
        }
        catch { $last = $_.Exception.Message; Start-Sleep -Seconds (2 * $try) }
    }
    return $last
}

function Enable-ChatqTls12 {
    if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
}

function Invoke-ChatqAlertCommand {
    # Your own PowerShell per alert - Pushover, Telegram, a Tasker webhook. The
    # alert goes in as $env:CHATQ_EVENT/TITLE/TEXT/PRIORITY/JOB/PRESENT and the
    # command runs as -EncodedCommand, so no chat title ever lands on a command
    # line where cmd's %VAR% expansion or a stray & could make it code.
    # Capped at 30 s. $null when it ran cleanly, else what went wrong.
    param($Cfg, [string]$Event, [string]$Title, [string]$Text, [int]$Priority, [bool]$Present)
    if (-not ($Cfg.PSObject.Properties['command'] -and $Cfg.command)) { return $null }
    $exe = (Get-Process -Id $PID).Path
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes([string]$Cfg.command))
    $env2 = @{
        CHATQ_EVENT = $Event; CHATQ_TITLE = $Title; CHATQ_TEXT = $Text; CHATQ_PRIORITY = "$Priority"
        CHATQ_JOB = [string]$script:ChatqAlertJob; CHATQ_PRESENT = $(if ($Present) { '1' } else { '0' })
    }
    $limit = if ($script:ChatqHookTimeoutSec) { $script:ChatqHookTimeoutSec } else { 30 }
    try {
        $p = Invoke-ChatqProcess -Exe $exe -ArgList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) `
            -StdIn '' -SetEnv $env2 -TimeoutSec $limit
        if ($p.Stopped) { return "command: stopped after $limit s" }
        if ($p.ExitCode) { return "command: exit $($p.ExitCode)" }
        return $null
    }
    catch { return "command: $($_.Exception.Message)" }
}

function Show-ChatqToast {
    # A desktop notification. Windows PowerShell 5.1 reaches WinRT in-process;
    # pwsh 7 dropped the WinRT projection, so from there the same few lines run
    # in powershell.exe, which every Windows has. It shows under Windows
    # PowerShell's own registered app id - a toast from an unregistered id is
    # silently dropped.
    param([string]$Title, [string]$Text)
    if ($script:ChatqToastSeam) { & $script:ChatqToastSeam $Title $Text; return }   # tests
    $t = [string]$Text
    if ($t.Length -gt 300) { $t = $t.Substring(0, 299) + $script:ChatqEllipsis }
    if ($script:ChatqIsWindows) {
        $x = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
        $xml = "<toast><visual><binding template=`"ToastGeneric`"><text>$(& $x $Title)</text><text>$(& $x $t)</text></binding></visual></toast>"
        $code = @'
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$d = New-Object Windows.Data.Xml.Dom.XmlDocument
$d.LoadXml($xml)
$n = New-Object Windows.UI.Notifications.ToastNotification $d
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show($n)
'@
        if ($PSVersionTable.PSEdition -ne 'Core') { & ([scriptblock]::Create($code)); return }
        $full = "`$xml = '" + $xml.Replace("'", "''") + "'`n" + $code
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($full))
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) | Out-Null
        return
    }
    if ($script:ChatIsMac) {
        $q = { param($s) ([string]$s).Replace('\', '\\').Replace('"', '\"') }
        & osascript -e "display notification `"$(& $q $t)`" with title `"$(& $q $Title)`"" 2>$null
        return
    }
    if (Get-Command notify-send -EA SilentlyContinue) { & notify-send $Title $t 2>$null }
}

function Get-ChatqIdleSeconds {
    # Seconds since the last keyboard or mouse input in this login session, or
    # $null when that cannot be told. GetLastInputInfo answers for the whole
    # session, so the hidden watcher asks it as well as any shell could.
    if ($null -ne $script:ChatqIdleSeam) { return $script:ChatqIdleSeam }   # tests
    try {
        if ($script:ChatqIsWindows) {
            if (-not ('ChatqIdle' -as [type])) {
                # the subtraction in C#, unsigned: 5.1's [Environment]::TickCount
                # is a signed int that goes negative after 24.9 days of uptime
                Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ChatqIdle {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static double Seconds() {
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref li)) { return -1; }
        return unchecked((uint)Environment.TickCount - li.dwTime) / 1000.0;
    }
}
'@
            }
            $s = [ChatqIdle]::Seconds()
            if ($s -ge 0) { return $s }
            return $null
        }
        if ($script:ChatIsMac) {
            $l = @(& ioreg -c IOHIDSystem 2>$null) | Where-Object { $_ -match 'HIDIdleTime' } | Select-Object -First 1
            if ($l -and $l -match '=\s*(\d+)') { return [double]$Matches[1] / 1e9 }
        }
    }
    catch {}
    return $null
}

function Test-ChatqUserPresent {
    # at the PC now? config quietMinutes (default 5); 0 turns the check off
    param($Cfg)
    $m = Get-ChatqQuietMinutes $Cfg
    if ($m -le 0) { return $false }
    $s = Get-ChatqIdleSeconds
    return ($null -ne $s -and $s -lt $m * 60)
}

function Get-ChatqQuietMinutes {
    # config quietMinutes, 5 when unset; 0 turns presence off
    param($Cfg)
    if ($Cfg -and $Cfg.PSObject.Properties['quietMinutes']) { return [double]$Cfg.quietMinutes }
    return 5
}

function Test-ChatqUserAway {
    # Nobody at the PC for quietMinutes - known, not assumed. The reverse of
    # present for the phone's sake, except where it counts: an idle clock that
    # cannot be read, or quietMinutes 0, never reads as away, because away is
    # what lets a window reload under someone's hands. Only this PC's own
    # keyboard and mouse count - a chat driven from the phone is caught by the
    # transcripts instead (see Invoke-ChatqJob).
    param($Cfg)
    $m = Get-ChatqQuietMinutes $Cfg
    if ($m -le 0) { return $false }
    $s = Get-ChatqIdleSeconds
    return ($null -ne $s -and $s -ge $m * 60)
}

#endregion

#region status: the list and the board ----------------------------------------

function Get-ChatqState {
    $s = Read-ChatqJson $script:ChatqStatePath
    if (-not $s) { $s = [pscustomobject]@{} }
    return $s
}

function Test-ChatqLockHeld {
    # The watcher and the overlay each hold a lock file open with no sharing
    # for their whole life, and the OS lets go of it even when the process dies
    # hard - so being able to open it means nobody holds it. A pid file alone
    # would lie after a crash, and pids get reused.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $fs.Dispose()
        return $false
    }
    catch { return $true }
}

function Test-ChatqWatcherAlive {
    return (Test-ChatqLockHeld $script:ChatqLockPath)
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
        $ra = ConvertTo-ChatqDate $j.retryAt
        if ($ra -and $ra -gt $now) { $times += $ra; if (-not $why) { $why = 'retry' } }
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
        if ($b.Type -eq 'login needed') {
            # what the CLI said; a watcher from before it was kept says 'probe'
            $said = if ($b.Source -and $b.Source -ne 'probe') { $b.Source } else { 'login refused' }
            $parts += "$name $said - log in or check the subscription, chatq looks again every 15 min"
            continue
        }
        $u = $b.Until
        $fmt = if ($u.Date -eq (Get-Date).Date) { 'HH:mm' } else { 'ddd HH:mm' }
        $parts += "$name limited until $($u.ToString($fmt, [System.Globalization.CultureInfo]::InvariantCulture)) ($($b.Type))"
    }
    $parts += if (Test-ChatqWatcherAlive) { 'watcher running' } else { 'watcher stopped' }
    return 'chatq ' + $script:ChatqDot + ' ' + ($parts -join " $($script:ChatqDot) ")
}

function Get-ChatqUsage {
    # How much of each window is used. Claude's comes from the utilisation it
    # caches in .claude.json, Codex's from the newest rollout's rate_limits -
    # both only as fresh as their last fetch, so each says when that was. For
    # chatqlist alone: the board is rewritten on every watcher pass, and
    # re-reading the file each time is not worth a number nobody looks at there.
    $out = [System.Collections.Generic.List[object]]::new()
    $label = { param($d) if ($d.Date -eq (Get-Date).Date) { $d.ToString('HH:mm') } else { $d.ToString('ddd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } }
    try {
        $path = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' } else { Join-Path $HOME '.claude.json' }
        if (Test-Path -LiteralPath $path) {
            $t = Read-ChatAllText $path
            $i = $t.IndexOf('"cachedUsageUtilization"', [StringComparison]::Ordinal)
            $j = if ($i -ge 0) { $t.IndexOf('{', $i) } else { -1 }
            $obj = if ($j -ge 0) { Read-ChatqJsonObjectAt $t $j } else { $null }
            $u = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
            if ($u -and $u.fetchedAtMs) {
                $parts = @(foreach ($l in @($u.utilization.limits)) {
                        if (-not $l) { continue }
                        $p = [int][Math]::Round([double]$l.percent)
                        $scoped = $l.PSObject.Properties['scope'] -and $l.scope
                        switch ([string]$l.kind) {
                            'session' { "5h $p%" }
                            'five_hour' { "5h $p%" }
                            { $_ -in 'weekly_all', 'seven_day', 'weekly' } { "week $p%" }
                            default {
                                # one model's weekly limit - worth a word only once used
                                if ($scoped -and $p -gt 0) {
                                    $name = if ($l.scope.model.display_name) { $l.scope.model.display_name } else { 'model' }
                                    "$name week $p%"
                                }
                            }
                        }
                    })
                if ($parts) {
                    $at = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$u.fetchedAtMs).LocalDateTime
                    $out.Add([pscustomobject]@{ Provider = 'Claude'; Parts = $parts; AsOf = & $label $at; AsOfAt = $at })
                }
            }
        }
    }
    catch {}
    try {
        $root = Join-Path (Get-ChatqHomeDir 'codex' $env:CODEX_HOME) 'sessions'
        $files = if (Test-Path -LiteralPath $root) {
            @(Get-ChildItem -LiteralPath $root -Filter *.jsonl -File -Recurse -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10)
        }
        # the newest snapshot, which need not be in the newest rollout: a
        # thread cut off before its first reply has none
        foreach ($f in @($files)) {
            $t = Read-ChatqTail $f.FullName 262144
            $i = if ($t) { $t.LastIndexOf('"rate_limits":{', [StringComparison]::Ordinal) } else { -1 }
            $obj = if ($i -ge 0) { Read-ChatqJsonObjectAt $t ($i + 14) } else { $null }
            $r = if ($obj) { try { $obj | ConvertFrom-Json } catch { $null } } else { $null }
            if (-not $r) { continue }
            if ($r) {
                $parts = @(foreach ($w in @($r.primary, $r.secondary)) {
                        if (-not $w -or $null -eq $w.used_percent) { continue }
                        $m = [int]$w.window_minutes
                        $n = if ($m -le 300) { '5h' } elseif ($m -le 10080) { 'week' } else { 'month' }
                        $s = "$n $([int][Math]::Round([double]$w.used_percent))%"
                        if ([double]$w.used_percent -ge 100 -and $w.resets_at) {
                            $s += ", resets $(& $label ([System.DateTimeOffset]::FromUnixTimeSeconds([int64]$w.resets_at).LocalDateTime))"
                        }
                        $s
                    })
                $at = Get-ChatqRecordTime $t $i
                if ($parts) { $out.Add([pscustomobject]@{ Provider = 'Codex'; Parts = $parts; AsOf = if ($at) { & $label $at } else { $null }; AsOfAt = $at }) }
            }
            break
        }
    }
    catch {}
    return $out.ToArray()
}

function Write-ChatqList {
    param([switch]$All)
    $jobs = @(Get-ChatqJobs)
    $blocks = Get-ChatqBlocks
    $eta = Get-ChatqEta $jobs $blocks
    $width = Get-ChatqWidth
    Write-Host ''
    Write-Host (' ' + (Get-ChatqStatusLine $jobs $blocks)) -ForegroundColor DarkGray
    # The percentages come from each tool's own cache, which is refreshed only
    # when that tool runs. Two ways it then misleads, both of them here today:
    # a lane limited right now cannot be at 0% of its 5 h window - the reading
    # simply predates the limit - and a reading hours old is not news at all.
    $use = @(Get-ChatqUsage | ForEach-Object {
            $u = $_
            $parts = @($u.Parts)
            # only the window that is actually blocked: a weekly limit says
            # nothing about the 5 h one, and an overload or a logged-out
            # account is not a usage limit at all
            $kinds = @($Blocks.Keys | Where-Object { $_ -like "$($u.Provider.ToLower())|*" -or $_ -eq $u.Provider.ToLower() } |
                    Where-Object { $Blocks[$_].Until } | ForEach-Object { [string]$Blocks[$_].Type })
            if (@($kinds | Where-Object { $_ -in 'five_hour', 'session' }).Count) {
                $parts = @($parts | ForEach-Object { if ($_ -like '5h *') { '5h limited' } else { $_ } })
            }
            if (@($kinds | Where-Object { $_ -in 'seven_day', 'weekly', 'weekly_all' }).Count) {
                $parts = @($parts | ForEach-Object { if ($_ -like 'week *') { 'week limited' } else { $_ } })
            }
            $old = $u.AsOfAt -and ((Get-Date) - $u.AsOfAt).TotalHours -ge 1
            $a = if ($u.AsOf) { " (as of $($u.AsOf)$(if ($old) { ' - stale' }))" } else { '' }
            "$($u.Provider) $($parts -join " $($script:ChatqDot) ")$a"
        })
    if ($use) { Write-Host ('  usage  ' + ($use -join "  $($script:ChatqDot)  ")) -ForegroundColor DarkGray }

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
            $long = $ps.Lines -gt 1 -or (Get-ChatCells $ps.First) -gt $promptW
            $nf = @(Get-ChatqAttachments $j).Count
            if ($long -or $nf) {
                $bits = @()
                if ($long) { $bits += '{0:N0} chars {1} {2} lines' -f $ps.Chars, $script:ChatqDot, $ps.Lines }
                if ($nf) { $bits += "+$nf file$(if ($nf -ne 1) { 's' })" }
                Write-Host ($pad + [char]0x21B3 + ' ' + ($bits -join " $($script:ChatqDot) ")) -ForegroundColor DarkGray
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
        blocked = @{}; lastAllowed = @{}; probeFails = @{}; scannedAt = @{}; outage = @{}; authAlerted = @{}
        current = $null; next = $null; startedAt = $null; handoff = $false
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
                lastProbe = $o.LastProbe.ToUniversalTime().ToString('o')
                status = $o.Status; attempts = $o.Attempts; alerted = [bool]$o.Alerted; reminded = [bool]$o.Reminded
            }
        }
    }
    $auth = @(foreach ($k in @($W.authAlerted.Keys)) { if ($W.authAlerted[$k]) { $k } })
    $s = [ordered]@{
        pid = $PID; version = $script:ChatVersion; startedAt = $W.startedAt; heartbeat = (Get-ChatqStamp)
        current = $W.current; next = $W.next; blocked = $blocked; outage = $outage; authAlerted = $auth
        # set by a watcher handing over to a newer copy of itself, so the one it
        # starts carries on from here instead of from nothing
        handoff = [bool]$W.handoff
    }
    try { Save-ChatqJson $script:ChatqStatePath $s } catch {}
}

function Restore-ChatqWatchState {
    # What a watcher that handed over knew: which lanes are limited until when,
    # which are overloaded and since when, which alerts already went out. Only
    # after a handoff - a watcher starting cold asks again, as it always did.
    param($W)
    $s = Get-ChatqState
    if (-not $s.handoff) { return $false }
    if ($s.blocked) {
        foreach ($p in $s.blocked.PSObject.Properties) {
            $u = ConvertTo-ChatqDate $p.Value.until
            if ($u -and $u -gt (Get-Date)) { $W.blocked[$p.Name] = [pscustomobject]@{ Until = $u; Type = $p.Value.type; Source = $p.Value.source } }
        }
    }
    if ($s.outage) {
        foreach ($p in $s.outage.PSObject.Properties) {
            $v = $p.Value
            $since = ConvertTo-ChatqDate $v.since
            if (-not $since) { continue }
            $next = ConvertTo-ChatqDate $v.next
            $last = ConvertTo-ChatqDate $v.lastProbe
            $W.outage[$p.Name] = @{
                Since = $since; Attempts = [int]$v.attempts; Status = $v.status
                Alerted = [bool]$v.alerted; Reminded = [bool]$v.reminded
                LastProbe = if ($last) { $last } else { $since }; NextCheck = if ($next) { $next } else { Get-Date }
            }
        }
    }
    foreach ($k in @($s.authAlerted)) { if ($k) { $W.authAlerted[[string]$k] = $true } }
    return $true
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
    Send-ChatqOutageReminder $o $Job
}

function Send-ChatqOutageReminder {
    # One more word after six hours: the first alert said "resumes by itself",
    # and an outage that long is worth knowing about while it is still going.
    param($O, $Job)
    if ($O.Reminded -or ((Get-Date) - $O.Since).TotalHours -lt 6) { return }
    $O.Reminded = $true
    $page = if ($O.Status) { " $($script:ChatqDot) status.claude.com: $($O.Status -replace '_', ' ')" } else { '' }
    [void](Send-ChatqAlert 'overloaded' "still overloaded after 6 h$page $($script:ChatqDot) $($Job.title) waits, checked every minute" 1)
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
    Send-ChatqOutageReminder $o $Job
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
    $key = "$lane|$(Get-ChatqRunModel $Job)"
    $last = $W.lastAllowed[$key]
    if ($last -and ((Get-Date) - $last).TotalMinutes -lt 3 -and -not $W.outage[$lane]) { return $true }
    if ($W.outage[$lane] -and -not (Test-ChatqOutageOver $W $Job)) { return $false }
    $r = Invoke-ChatqProbe $Job.provider $Job
    if ($r.Allowed) {
        $W.lastAllowed[$key] = Get-Date
        $W.lastAllowed[$lane] = Get-Date
        $W.blocked[$lane] = $null
        $W.probeFails[$lane] = 0
        $W.authAlerted[$lane] = $false
        if ($W.outage[$lane]) {
            $since = $W.outage[$lane].Since
            $W.outage[$lane] = $null
            Write-ChatqWatchLog "$lane back after $([int]((Get-Date) - $since).TotalMinutes) min"
        }
        Write-ChatqWatchLog "$lane allowed"
        return $true
    }
    if ($r.Overloaded) { Enter-ChatqOutage $W $Job 'the probe got 529 Overloaded'; return $false }
    if ($r.Auth) { Block-ChatqLogin $W $Job $r.Error $r.Detail; return $false }
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

function Block-ChatqLogin {
    # A login that expired fails every job in that account the same way, so it
    # is the account that waits, not each job: one alert, the jobs stay queued,
    # and it is looked at again every 15 minutes until someone logs in. A
    # subscription that ran out is refused the same way, so the alert passes on
    # what the CLI said instead of guessing "logged out".
    param($W, $Job, [string]$Reason, [string]$Detail)
    $lane = Get-ChatqLane $Job
    $said = if ($Reason) { $Reason } else { 'login refused' }
    $W.blocked[$lane] = [pscustomobject]@{ Until = (Get-Date).AddMinutes(15); Type = 'login needed'; Source = $said }
    $W.lastAllowed[$lane] = $null
    Write-ChatqWatchLog "$lane $said"
    if ($Detail) { Write-ChatqWatchLog "$lane error text: $Detail" }
    if (-not $W.authAlerted[$lane]) {
        $W.authAlerted[$lane] = $true
        $how = if ($Job.provider -eq 'codex') { 'codex login' } else { 'claude, then /login' }
        [void](Send-ChatqAlert 'failed' "$(Format-ChatqLane $lane) $said $($script:ChatqDot) run $how, or check the subscription $($script:ChatqDot) queued prompts wait for it" 2)
    }
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
    # a FILETIME on Windows; macOS writes a date string, which says nothing
    # this comparison could use
    if ([string]$ProcStart -match '^\d{17,}$') {
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
    Update-ChatqNewChatPath $Job
    # a new chat not started yet: none of the chat checks below apply
    $fresh = Test-ChatqFreshChat $Job
    # the chat as it is now, not as it was when queued. A new chat whose
    # prompt landed and which is to be continued has had its transcript
    # deleted since: starting it afresh would make a chat that says only
    # "continue".
    if ($Job.provider -eq 'claude' -and (-not $fresh -or $sendsContinue)) {
        $meta = if ($fresh) { [pscustomobject]@{ Exists = $false } } else { Get-ChatqClaudeMeta $Job.path $Job.group }
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

    $live = if ($Job.provider -eq 'claude' -and -not $fresh) { @(Get-ChatqLiveSessions $Job.home) } else { @() }
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
        # sent "now" from the console: looked at again soon, not in 5 minutes
        $back = if ($Job.PSObject.Properties['sendNow'] -and $Job.sendNow) { 30 } else { 300 }
        Set-ChatqProp $Job 'deferUntil' $now.AddSeconds($back).ToUniversalTime().ToString('o')
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

    # A "continue" goes alone: the files went with the prompt the first time.
    $files = @()
    if ($sendsContinue) { $prompt = $script:ChatqContinueText }
    else {
        # an image pasted into the prompt since it was queued comes along too
        foreach ($x in @(Sync-ChatqAttachments $Job)) { Write-ChatqWatchLog "#$($Job.seq) could not take in $x - sent without it" }
        $prompt = Read-ChatqPrompt $Job
        $files = @(Get-ChatqAttachments $Job)
    }
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
    Set-ChatqProp $Job 'retryAt' $null
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
    $out = Invoke-ChatqRun $Job $prompt $onTick $onStart -Files $files
    $W.current = $null
    $wasCancelled = Test-Path -LiteralPath $cancel
    if ($wasCancelled) { Remove-Item -LiteralPath $cancel -Force -EA SilentlyContinue }
    Set-ChatqProp $Job 'runnerPid' $null
    if ($stale) { Set-ChatqProp $out 'stale' $true }
    # the new chat's transcript, if this run made it where the slug did not say
    Update-ChatqNewChatPath $Job
    # The window still holding this chat shows none of the run until it
    # reloads. The extension in extension/ offers that reload, in that window
    # only - the job's folder is what it matches on, never this process's own.
    # Not for a run that goes back in the queue: it is not finished yet.
    # Judged here, as the run ends: the window reloads by itself only when
    # nobody is at the PC to be typing in it and no other chat in the folder
    # is working - otherwise it asks, as it always did. "Working" reaches back
    # quietMinutes here, not one: a chat written that recently is someone's,
    # at this PC or driving it from the phone, which the idle clock never sees.
    if ($stale -and -not $wasCancelled -and $out.kind -notin 'limited', 'overloaded') {
        $cfg = Get-ChatqConfig
        $recent = [int][Math]::Max(60, (Get-ChatqQuietMinutes $cfg) * 60)
        $idle = Test-ChatIdle -Cwd $Job.cwd -Except $Job.path -Seconds $recent -ConfigDir $Job.home
        $busy = if ($null -eq $idle) { $null } else { -not $idle }
        Write-ChatReloadRequest -Title $Job.title -Cwd $Job.cwd -Kind 'ran' -Busy $busy -Away (Test-ChatqUserAway $cfg)
    }
    # A new chat is on disk now, and the chat list of a window on its folder
    # shows it only after a reload - the same offer, in words of its own. On
    # the first run that finishes rather than the first run: one the limit
    # cut goes back in the queue, and its continue is no longer fresh.
    elseif ($Job.kind -eq 'new' -and -not ($Job.PSObject.Properties['newOffered'] -and $Job.newOffered) -and -not $wasCancelled -and
        $out.kind -notin 'limited', 'overloaded', 'network', 'auth' -and $Job.path -and (Test-Path -LiteralPath $Job.path)) {
        Write-ChatReloadRequest -Title $Job.title -Cwd $Job.cwd -Kind 'new'
        Set-ChatqProp $Job 'newOffered' $true
    }

    $dur = ''
    $s0 = ConvertTo-ChatqDate $Job.startedAt
    if ($s0) { $dur = Get-ChatAge $s0; if ($dur -eq 'now') { $dur = '<1m' } }
    $reload = if ($stale) { " $($script:ChatqDot) reload the VS Code window before typing in this chat" } else { '' }
    # A limit, a 529, a dropped connection, a login gone: all go back in the
    # queue. A prompt that already reached the chat comes back as "continue",
    # never as itself a second time.
    if ($out.kind -in 'limited', 'overloaded', 'network', 'auth' -and -not $wasCancelled) {
        $landed = Test-ChatqPromptLanded $Job.path $prompt $Job.startedAt $Job.provider
        if ($landed -and $prompt -ne $script:ChatqContinueText) { Set-ChatqProp $Job 'retryAs' 'continue' }
        # Only a limit or a 529 leaves a record in the chat saying it was cut
        # off. After anything else "has the chat moved on?" would read that
        # missing record as yes, and drop the continue without sending it.
        if ($out.kind -in 'network', 'auth') { Set-ChatqProp $Job 'autoContinue' $false }
        elseif ($landed -and $prompt -ne $script:ChatqContinueText) { Set-ChatqProp $Job 'autoContinue' $true }
        Set-ChatqProp $Job 'result' $out
        # The cap counts runs that broke before a single reply. A long task that
        # gets through several limit windows moves on each time and never
        # meets it; one that keeps dying on the spot is going nowhere.
        $stuck = if ([int]$out.assistant -gt 0) { 0 } else { [int]$Job.noProgress + 1 }
        Set-ChatqProp $Job 'noProgress' $stuck
        $cap = Get-ChatqMaxRetries
        if ($stuck -ge $cap) {
            $why = "gave up: $stuck tries in a row got no reply ($($out.kind): $($out.reason))"
            Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = $why }) 'gave up'
            [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) $why" 2)
            Write-ChatqWatchLog "#$($Job.seq) $why"
            Save-ChatqWatchState $W
            Write-ChatqBoard
            return
        }
    }
    elseif (-not $wasCancelled) { Set-ChatqProp $Job 'noProgress' 0 }
    if ($out.kind -ne 'network') { Set-ChatqProp $Job 'netRetries' 0 }
    switch ($out.kind) {
        'network' {
            if ($wasCancelled) { Complete-ChatqJob $Job 'failed' $out 'cancelled'; break }
            $k = [int]$Job.netRetries + 1
            Set-ChatqProp $Job 'netRetries' $k
            if ($k -gt 3) {
                $out.reason = "$($out.reason) - gave up after 3 retries"
                Complete-ChatqJob $Job 'failed' $out 'network'
                [void](Send-ChatqAlert 'failed' "$($Job.title) $($script:ChatqDot) $($out.reason)" 2)
                Write-ChatqWatchLog "#$($Job.seq) $($out.reason)"
                break
            }
            # kept in the job, not in this process: a restart must not reset it
            $at = (Get-Date).AddMinutes(@(1, 2, 5)[$k - 1])
            Set-ChatqProp $Job 'retryAt' $at.ToUniversalTime().ToString('o')
            Set-ChatqJobState $Job 'queued' "network drop - retry $k/3 at $($at.ToString('HH:mm'))"
            Write-ChatqWatchLog "#$($Job.seq) $($out.reason) - retry $k/3 at $($at.ToString('HH:mm'))"
        }
        'auth' {
            if ($wasCancelled) { Complete-ChatqJob $Job 'failed' $out 'cancelled'; break }
            Block-ChatqLogin $W $Job $out.reason $out.detail
            Set-ChatqJobState $Job 'queued' 'waiting for the login to work again'
        }
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
    $ra = ConvertTo-ChatqDate $Job.retryAt
    if ($ra -and $ra -gt $Now) { $times += $ra }
    return ($times | Sort-Object -Descending | Select-Object -First 1)
}

function Get-ChatqMaxRetries {
    # config maxRetries: how many runs in a row may break before any reply
    $n = 5
    $c = Get-ChatqConfig
    if ($c.PSObject.Properties['maxRetries'] -and [int]$c.maxRetries -ge 1) { $n = [int]$c.maxRetries }
    return $n
}

function Invoke-ChatqWatchLoop {
    param([switch]$Foreground)
    Set-StrictMode -Off
    $script:ChatqForeground = [bool]$Foreground
    New-ChatqDir $script:ChatqData
    # A few tries, not one: a watcher handing over to this one lets go of the
    # lock only as it exits, and a shell checking whether one is alive holds
    # it for an instant too. Either would otherwise leave nobody watching.
    $lock = $null
    for ($try = 1; $try -le 5 -and -not $lock; $try++) {
        $lock = try { [System.IO.File]::Open($script:ChatqLockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { $null }
        if (-not $lock -and $try -lt 5) { Start-Sleep -Milliseconds 200 }
    }
    if (-not $lock) {
        if ($Foreground) { Write-Host '  a watcher is already running - chatqrun -Stop first' -ForegroundColor Yellow }
        return
    }
    $W = New-ChatqWatchState
    $W.startedAt = Get-ChatqStamp
    $restart = $false
    try {
        Set-Content -LiteralPath $script:ChatqPidPath -Value $PID -Encoding ASCII
        if (Test-Path -LiteralPath $script:ChatqStopPath) { Remove-Item -LiteralPath $script:ChatqStopPath -Force }
        Write-ChatqWatchLog "watcher $PID started ($script:ChatVersion)"
        if (Restore-ChatqWatchState $W) { Write-ChatqWatchLog 'carrying on from the watcher before it' }
        Repair-ChatqInterrupted
        $wakeSeen = $null
        while ($true) {
            if (Test-Path -LiteralPath $script:ChatqStopPath) {
                Remove-Item -LiteralPath $script:ChatqStopPath -Force -EA SilentlyContinue
                Write-ChatqWatchLog 'stop requested'
                break
            }
            # chatinstall put a newer copy of this file in place. Between jobs,
            # never in the middle of one, and never in a console someone is
            # watching: hand over to a watcher running the new code.
            if (-not $Foreground -and (Test-Path -LiteralPath $script:ChatqRestartPath)) {
                Remove-Item -LiteralPath $script:ChatqRestartPath -Force -EA SilentlyContinue
                Write-ChatqWatchLog 'a newer copy was installed - handing over'
                $W.handoff = $true
                $restart = $true
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
                $script:ChatqAlertJob = "#$($pick.seq)"
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
                $script:ChatqAlertJob = $null
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
    # Last of all, after the lock, the pid file and the state are settled: a
    # successor started any sooner would find its pid file deleted by this
    # one, or this one still holding the lock.
    if ($restart) { [void](Start-ChatqWatcherProcess) }
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
    if (-not (Start-ChatqWatcherProcess)) { return $false }
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-ChatqWatcherAlive) { return $true }
    }
    # an empty queue ends it at once, so not seeing it is not always a failure
    return (Test-ChatqWatcherAlive)
}

function Start-ChatqWatcherProcess {
    # just the launch: Start-ChatqWatcher decides whether one is needed, and a
    # watcher handing over to a newer copy of itself calls this directly
    if ($script:ChatqSpawn) { return (& $script:ChatqSpawn) }   # tests: no real process
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
    return $true
}

#endregion

#region commands --------------------------------------------------------------

function New-ChatqSeq {
    # -Jobs: a list already read, as the console has one every pass
    param([object[]]$Jobs)
    if (-not $Jobs) { $Jobs = @(Get-ChatqJobs) }
    $max = 0
    foreach ($j in $Jobs) { if ([int]$j.seq -gt $max) { $max = [int]$j.seq } }
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

#region the job core ------------------------------------------------------------
# What chatq, chatqrm, chatqrun and chatqlog do to jobs, apart from what they
# print: the overlay's console does the same things from a window, where
# there is no console to print to and no editor to wait on. Nothing here
# writes to the host or starts the watcher.

function New-ChatqJobSlot {
    # A new job's number, id and file names. An id is the time to the second
    # and the chat's first four hex digits; one already taken - two jobs for
    # one chat inside a second, which the console can make - gets -2, -3.
    param($Row, [string]$Title, [object[]]$Jobs)
    New-ChatqDir $script:ChatqQueueDir
    $seq = New-ChatqSeq -Jobs $Jobs
    $name = if ($Title) { $Title } else { [string]$Row.Title }
    $hex = if ($Row.Id) { ([string]$Row.Id).Substring(0, [Math]::Min(4, ([string]$Row.Id).Length)) } else { [guid]::NewGuid().ToString('N').Substring(0, 4) }
    $base = '{0}-{1}' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $hex
    $id = $base
    for ($n = 2; (Test-Path -LiteralPath (Join-Path $script:ChatqQueueDir "$id.json")) -or (Test-Path -LiteralPath (Join-Path $script:ChatqQueueDir $id)); $n++) { $id = "$base-$n" }
    # no run of dashes survives into the comment, so no title can close it early
    $safe = $name -replace '-{2,}', '-'
    $file = "#$seq $(Get-ChatqSafeName $name).md"
    [pscustomobject]@{
        Seq = $seq; Id = $id; File = $file; Path = (Join-Path $script:ChatqQueueDir $file); Dir = (Join-Path $script:ChatqQueueDir $id)
        Header = "<!-- chatq: prompt for '$safe' ($($Row.Provider)). Everything after this comment is sent as it is when the limit resets. Save and close the tab to queue it; leave it empty to cancel. -->`n`n"
    }
}

function New-ChatqJobRecord {
    # The job as data/queue/<id>.json holds it. Pure: nothing is written.
    # -Resolve: how Resolve-ChatqTarget picked the chat, when it did.
    param($Slot, $Row, $Info, [string]$Kind = 'prompt', [string]$Mode, [string]$Model, $NotBefore,
        [switch]$First, [switch]$SendNow, [string]$Typed, $Resolve, [string]$Rule, [string]$Title)
    [pscustomobject][ordered]@{
        v = 1
        # set before the prompt, when the files went in - the chat a re-pick
        # lands on does not rename the folder they are in
        id = $Slot.Id
        seq = $Slot.Seq
        provider = $Row.Provider
        sessionId = $(if ($Row.Id) { $Row.Id } else { $null })
        title = $(if ($Title) { $Title } else { $Row.Title })
        group = $Row.Group
        path = $(if ($Row.Path) { $Row.Path } else { $null })
        cwd = $Info.Cwd
        # only when the user set one: pointing CLAUDE_CONFIG_DIR at the default
        # makes Claude look for .claude.json inside it, where it never lives
        home = if ($Row.Provider -eq 'codex') { $env:CODEX_HOME } else { $env:CLAUDE_CONFIG_DIR }
        chatWhen = $Row.When
        typed = $(if ($Typed) { $Typed } else { $null })
        rule = $(if ($Resolve) { $Resolve.Rule } elseif ($Rule) { $Rule } else { $null })
        score = $(if ($Resolve) { $Resolve.Score } else { $null })
        runnerUp = if ($Resolve -and $Resolve.RunnerUp) { $Resolve.RunnerUp.Title } else { $null }
        kind = $Kind
        promptFile = $Slot.File
        mode = if ($Mode) { $Mode } else { $null }
        modeAtQueue = $Info.Mode
        # the chat's own model - what the probe asks with - and, apart from it,
        # the one -Model asked this run to use
        model = $Info.Model
        runModel = if ($Model) { $Model.Trim() } else { $null }
        first = if ($First) { Get-ChatqStamp } else { $null }
        sandbox = $Info.Sandbox
        network = $Info.Network
        notBefore = if ($NotBefore) { ([datetime]$NotBefore).ToUniversalTime().ToString('o') } else { $null }
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
        # "send now" from the console: a chat busy in VS Code is looked at
        # again every 30 s rather than every 5 minutes
        sendNow = [bool]$SendNow
    }
}

function Register-ChatqJob {
    # Saved, with what the prompt links to in data/queue - an image pasted in
    # the editor tab - brought into its folder, and a line in jobs.log.
    # Returns the files it has and those it could not take in.
    param($Job)
    Save-ChatqJob $Job
    $missed = @(Sync-ChatqAttachments $Job)
    $files = @(Get-ChatqAttachments $Job)
    Write-ChatqJobLog "#$($Job.seq) queued ($($Job.kind)$(if ($files) { ", $($files.Count) file$(if ($files.Count -ne 1) { 's' })" })) $($script:ChatqDot) $($Job.title)"
    return [pscustomobject]@{ Files = $files; Missed = $missed }
}

function New-ChatqJob {
    <#
    A job from a chat already picked, a prompt and files, in one call and
    without a word to the host - what chatq does once it knows the chat,
    and what the console does on Send. Returns @{ Error; Code; Job; Files;
    Missed }: Error is the line chatq prints, and nothing is left behind.
    Code: provider, kind, empty, info, copy. The watcher is not started.
    -Sources: what Read-ChatqAttachSources gives, or @{ Files; Images }.
    -MoveSources: those files are the console's staged copies; they move in.
    -Kind new, with -Cwd and no -Row: a brand-new Claude chat in that
    folder. Its session id is chosen now and handed to claude --session-id
    on the first run (spike S25), so its transcript's path is known from the
    start; -Title names it, or the prompt's first line does.
    #>
    param($Row, [string]$Prompt, [ValidateSet('prompt', 'continue', 'new')][string]$Kind = 'prompt', $Info,
        [string]$Mode, [string]$Model, $NotBefore, [switch]$First, [switch]$SendNow, $Sources, [switch]$MoveSources,
        [string]$Typed, $Resolve, [string]$Rule, [string]$Title, [object[]]$Jobs, [string]$Cwd)
    $fail = { param($c, $t) [pscustomobject]@{ Error = $t; Code = $c; Job = $null; Files = @(); Missed = @() } }
    if ($Kind -eq 'new') {
        $dir = if ($Cwd) { try { [System.IO.Path]::GetFullPath($Cwd) } catch { $null } } else { $null }
        # C:\ stays C:\ - as a working folder C: is wherever that drive last was
        if ($dir -and $dir -ne [System.IO.Path]::GetPathRoot($dir)) { $dir = $dir.TrimEnd('\', '/') }
        if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return & $fail 'info' "no such folder: $Cwd" }
        if (-not ([string]$Prompt).Trim()) { return & $fail 'empty' 'empty prompt - nothing queued' }
        $sid = [guid]::NewGuid().ToString()
        $slug = Get-ChatSlug $dir
        if (-not $Title) { $Title = Format-ChatTitle ((Get-ChatqPromptStats $Prompt).First) 60 }
        $Row = [pscustomobject]@{
            Provider = 'claude'; Id = $sid; Title = $Title; Group = $slug; When = $null
            Path = (Join-Path (Join-Path (Join-Path $script:ChatClaudeHome 'projects') $slug) "$sid.jsonl")
        }
        $Info = @{ Cwd = $dir; Mode = 'default'; Model = $null; CutOff = $false; Sandbox = $null; Network = $false; Error = $null }
        if (-not $Rule) { $Rule = 'new' }
    }
    if (-not $Row -or $Row.Provider -notin 'claude', 'codex') {
        return & $fail 'provider' "only a Claude or Codex chat can take a prompt - nothing can resume a $(if ($Row) { $Row.Provider } else { 'missing' }) chat"
    }
    $hasFiles = $Sources -and (@($Sources.Files | Where-Object { $_ }).Count -or $Sources.Image -or ($Sources -is [hashtable] -and @($Sources['Images']).Count))
    if ($Kind -eq 'continue' -and $hasFiles) { return & $fail 'kind' '-Continue sends "continue" and nothing else - give the files with -Prompt instead' }
    if ($Kind -ne 'continue' -and -not ([string]$Prompt).Trim()) { return & $fail 'empty' 'empty prompt - nothing queued' }
    if (-not $Info) { $Info = Get-ChatqJobInfo $Row }
    if ($Info.Error) { return & $fail 'info' $Info.Error }
    $slot = New-ChatqJobSlot $Row $Title $Jobs
    # the files before the prompt: one that cannot be copied stops the job
    # before anything of it is written
    if ($hasFiles) {
        try { $null = Save-ChatqAttachSources $slot.Dir $Sources -Move:$MoveSources }
        catch { return & $fail 'copy' "a file could not be copied - nothing queued: $($_.Exception.Message)" }
    }
    Save-ChatqText $slot.Path ($slot.Header + $(if ($Kind -eq 'continue') { $script:ChatqContinueText } else { $Prompt }))
    $job = New-ChatqJobRecord $slot $Row $Info -Kind $Kind -Mode $Mode -Model $Model -NotBefore $NotBefore -First:$First -SendNow:$SendNow -Typed $Typed -Resolve $Resolve -Rule $Rule -Title $Title
    $reg = Register-ChatqJob $job
    return [pscustomobject]@{ Error = $null; Code = $null; Job = $job; Files = $reg.Files; Missed = $reg.Missed }
}

function Get-ChatqRowById {
    <#
    The index's row for a chat known by its id: the console picks chats from
    lists, so nothing fuzzy, and no Sync-ChatIndex on the window's thread.
    A Claude chat not in the index yet - one the limit has just cut off often
    is not - is described from its transcript: -Path, or found by -Cwd and
    id. Hidden (sidechain) chats are not rows.
    #>
    param([string]$Id, [string]$Provider, [string]$Path, [string]$Cwd)
    if (-not $Id) { return $null }
    foreach ($r in @(Get-ChatIndex)) {
        if ($r.Id -and $r.Id -eq $Id -and (-not $Provider -or $r.Provider -eq $Provider)) {
            if ($r.Hidden) { return $null }
            return $r
        }
    }
    if ($Provider -and $Provider -ne 'claude') { return $null }
    $p = if ($Path -and (Test-Path -LiteralPath $Path)) { $Path } else { Find-ChatOverlayTranscript $script:ChatClaudeHome $Cwd $Id }
    if (-not $p) { return $null }
    $f = Get-Item -LiteralPath $p -EA SilentlyContinue
    if (-not $f) { return $null }
    $rec = try { & $script:ChatProviders['claude'].Describe $f } catch { $null }
    if (-not $rec -or $rec.Hidden) { return $null }
    [pscustomobject]@{
        Provider = 'claude'; Path = $f.FullName; Size = $f.Length; Mtime = $f.LastWriteTimeUtc.Ticks
        Id = $rec.Id; Title = $rec.Title; Titled = $rec.TitleSource; Group = $rec.Group; Hidden = $false
        When = $(if ($rec.When) { $rec.When.ToString('o') } else { $null }); First = @($rec.First); Last = @($rec.Last)
    }
}

function Remove-ChatqJob {
    # A job and everything it has: its file, prompt, log, and the copies of
    # its files - the originals were never touched. Not a running one.
    param($Job, [string]$By = 'chatqrm')
    if ($Job.state -eq 'running') { return $false }
    foreach ($p in @((Join-Path $script:ChatqQueueDir "$($Job.id).json"), (Get-ChatqPromptPath $Job), (Join-Path $script:ChatqLogDir "$($Job.id).jsonl"))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -EA SilentlyContinue }
    }
    $ad = Get-ChatqAttachDir $Job
    if (Test-Path -LiteralPath $ad) { Remove-Item -LiteralPath $ad -Recurse -Force -EA SilentlyContinue }
    Write-ChatqJobLog "#$($Job.seq) removed by $By (was $($Job.state)) $($script:ChatqDot) $($Job.title)"
    return $true
}

function Stop-ChatqJobRun {
    # A running job stopped: 'cancelling' - a cancel file its watcher reads
    # within seconds - or 'failed', when no watcher is alive to read one:
    # the job was left running by one that died, and there is nothing to stop.
    # 'not running': it ended before the click, and what it ended with stands.
    param($Job)
    if ($Job.state -ne 'running') { return 'not running' }
    if (Test-ChatqWatcherAlive) {
        Save-ChatqText (Join-Path $script:ChatqQueueDir "$($Job.id).cancel") 'cancel'
        return 'cancelling'
    }
    Complete-ChatqJob $Job 'failed' ([pscustomobject]@{ kind = 'failed'; reason = 'cancelled - its watcher was already gone' }) 'cancelled'
    return 'failed'
}

function Set-ChatqJobFirst {
    # to the front of its lane: the latest one put first goes ahead
    param($Job)
    Set-ChatqProp $Job 'first' (Get-ChatqStamp)
    Save-ChatqJob $Job
}

function Reset-ChatqJob {
    # A finished job queued again, as chatqrun <n> does. One whose prompt
    # already reached the chat goes as "continue", never the prompt twice.
    # Returns @{ Error; Landed }.
    param($Job, [string]$Mode)
    if ($Job.state -notin 'failed', 'needs-input', 'done', 'skipped') { return [pscustomobject]@{ Error = "#$($Job.seq) is $($Job.state) - nothing to requeue"; Landed = $false } }
    if ($Mode) { Set-ChatqProp $Job 'mode' $Mode }
    $landed = $Job.state -in 'needs-input', 'done' -or $Job.retryAs -eq 'continue' -or
    (Test-ChatqPromptLanded $Job.path ([string](Read-ChatqPrompt $Job)) $Job.startedAt $Job.provider)
    Set-ChatqProp $Job 'retryAs' $(if ($landed) { 'continue' } else { 'full' })
    # asked for by you: sent even if the chat has moved on since
    Set-ChatqProp $Job 'autoContinue' $false
    Set-ChatqProp $Job 'deferUntil' $null
    Set-ChatqProp $Job 'deferredSince' $null
    # asked for by hand: the retry counts start over
    Set-ChatqProp $Job 'retryAt' $null
    Set-ChatqProp $Job 'noProgress' 0
    Set-ChatqProp $Job 'netRetries' 0
    Set-ChatqJobState $Job 'queued' 'requeued'
    return [pscustomobject]@{ Error = $null; Landed = [bool]$landed }
}

function Get-ChatqJobFilesRefusal {
    # why a job can take no more files, or $null
    param($Job)
    if ($Job.state -ne 'queued') { return "#$($Job.seq) is $($Job.state) - files added now would go nowhere" }
    if ($Job.kind -eq 'continue') { return "#$($Job.seq) sends ""continue"" and nothing else - files would go nowhere" }
    return $null
}

function Add-ChatqJobFiles {
    # more files for a job still waiting - the screenshot that was forgotten.
    # Returns @{ Error; Files }.
    param($Job, $Sources, [switch]$Move)
    $no = Get-ChatqJobFilesRefusal $Job
    if ($no) { return [pscustomobject]@{ Error = $no; Files = @() } }
    $new = try { @(Save-ChatqAttachSources (Get-ChatqAttachDir $Job) $Sources -Move:$Move) }
    catch { return [pscustomobject]@{ Error = "a file could not be copied - nothing added: $($_.Exception.Message)"; Files = @() } }
    Write-ChatqJobLog "#$($Job.seq) +$($new.Count) file$(if ($new.Count -ne 1) { 's' }) $($script:ChatqDot) $($Job.title)"
    return [pscustomobject]@{ Error = $null; Files = $new }
}

function Get-ChatqLogEntries {
    <#
    What a run did, from data/logs/<id>.jsonl, as @{ Type; Text } in order:
    init, denied, text (a reply), tool, result, error. -MaxBytes reads only
    the log's tail - a long run's stream runs to megabytes, and the console
    reads it on the window's thread. The user's own lines are skipped: they
    are the prompt, and tool output fed back.
    #>
    param($Job, [int]$MaxBytes = 0)
    $log = Join-Path $script:ChatqLogDir "$($Job.id).jsonl"
    if (-not (Test-Path -LiteralPath $log)) { return @() }
    $lines = if ($MaxBytes -gt 0 -and (Get-Item -LiteralPath $log).Length -gt $MaxBytes) {
        # the first line of a tail is cut in two
        @((Read-ChatqTail $log $MaxBytes) -split "`n" | Select-Object -Skip 1)
    }
    # not File.ReadLines: it shares only Read, and a running job's log is held
    # open for writing
    else { try { @((Read-ChatAllText $log) -split '\r?\n') } catch { @() } }
    $d = $script:ChatqDot
    $out = [System.Collections.Generic.List[object]]::new()
    $add = { param($t, $x) $out.Add([pscustomobject]@{ Type = $t; Text = [string]$x }) }
    foreach ($line in $lines) {
        if (-not $line -or $line.Length -gt 1048576) { continue }
        if ($line.StartsWith('{"type":"user"')) { continue }
        $o = try { $line | ConvertFrom-Json } catch { continue }
        switch ($o.type) {
            'system' {
                if ($o.subtype -eq 'init') { & $add 'init' "session $($o.session_id) $d $($o.model) $d $($o.permissionMode) $d Claude Code $($o.claude_code_version)" }
                elseif ($o.subtype -eq 'permission_denied') { & $add 'denied' $o.tool_name }
            }
            'assistant' {
                foreach ($c in @($o.message.content)) {
                    if ($c.type -eq 'text' -and $c.text) { & $add 'text' $c.text }
                    elseif ($c.type -eq 'tool_use') {
                        $arg = if ($c.input.command) { $c.input.command } elseif ($c.input.file_path) { $c.input.file_path } elseif ($c.input.pattern) { $c.input.pattern } else { '' }
                        & $add 'tool' "$($c.name) $(([string]$arg -split "`n")[0])"
                    }
                }
            }
            'result' {
                $t = if ($o.duration_ms) { [TimeSpan]::FromMilliseconds($o.duration_ms).ToString('hh\:mm\:ss') } else { '' }
                & $add 'result' "$($o.subtype) $d $($o.num_turns) turns $d $t"
            }
            'item.completed' {
                if ($o.item.type -eq 'agent_message') { & $add 'text' $o.item.text }
                elseif ($o.item.type -eq 'command_execution') { & $add 'tool' $o.item.command }
            }
            'turn.failed' { & $add 'error' $o.error.message }
            'error' { & $add 'error' $o.message }
        }
    }
    return $out.ToArray()
}

function Request-ChatqWatcher {
    <#
    Start-ChatqWatcher for a window's thread, which it must never put to
    sleep. The wake goes first - 'poke' (look again) or 'now' (stop waiting),
    one write, as Start-ChatqWatcher does - and a process is started only
    when none holds the lock. Whether one came up is for
    Test-ChatqWatcherRequest to say, on a later tick.
    #>
    param([ValidateSet('poke', 'now')][string]$Wake = 'poke')
    $alive = [bool](Test-ChatqWatcherAlive)
    Send-ChatqWake $Wake
    $spawned = if ($alive) { $false } else { [bool](Start-ChatqWatcherProcess) }
    return [pscustomobject]@{ Alive = $alive; Spawned = $spawned; Respawned = $false; At = (Get-Date) }
}

function Test-ChatqWatcherRequest {
    <#
    What came of a Request-ChatqWatcher: 'up' once a watcher holds the lock,
    'waiting' for up to 10 s, then 'failed'. A watcher running when poked may
    have been on its way out - it had found the queue empty and not yet let
    go - so one gone with jobs still queued is started again, once. With
    nothing queued a watcher ends at once, so not seeing it is no failure.
    #>
    param($Request, [bool]$Queued)
    if (-not $Request) { return 'none' }
    if (Test-ChatqWatcherAlive) { return 'up' }
    if (-not $Queued) { return 'up' }
    if ($Request.Alive -and -not $Request.Respawned) {
        $Request.Respawned = $true
        $Request.Spawned = [bool](Start-ChatqWatcherProcess)
        $Request.At = Get-Date
        return 'waiting'
    }
    if (((Get-Date) - $Request.At).TotalSeconds -lt 10) { return 'waiting' }
    return 'failed'
}

#endregion

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
    .PARAMETER Model
    Run this one job on another model (claude --model / codex -m). Without it
    the chat keeps its own, which is what a resume does anyway.
    .PARAMETER First
    Put the job at the front of the queue instead of the back.
    .PARAMETER Attach
    Files to send with the prompt - images, text, code, PDF - comma-separated.
    They are copied into the job now, so moving or editing the originals
    changes nothing. Codex gets images as real attachments (-i); everything
    else, and everything for Claude, is named in the prompt for it to open.
    .PARAMETER Paste
    Take what is on the clipboard now: a screenshot, files copied in Explorer,
    or text. Text becomes the prompt, or is added under the one given. In the
    editor tab, Ctrl+V pastes an image into the prompt too.
    .EXAMPLE
    chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'
    .EXAMPLE
    chatq card redesign -WhatIf
    .EXAMPLE
    chatq 'Card layout redesign' -Prompt 'Match these two mock-ups' -Attach .\a.png, .\b.png
    .EXAMPLE
    chatq 'Card layout redesign' -Prompt 'What is wrong in this screenshot?' -Paste
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
        [switch]$WhatIf,
        [string]$Model,
        [switch]$First,
        [string[]]$Attach,
        [switch]$Paste
    )
    Set-StrictMode -Off
    $t = (@($Target) -join ' ').Trim()
    if (-not $t) { Write-ChatqCheatSheet; Write-ChatqList; return }

    # chatq 3 - open queued prompt 3
    if ($t -match '^#?\d{1,4}$' -and -not $PSBoundParameters.ContainsKey('Prompt') -and -not $Continue) {
        $job = Find-ChatqJob $t
        # chatq 3 -Attach / -Paste - add to it: the screenshot that was
        # forgotten. Only while it waits, and only files - text belongs in the
        # prompt, which chatq 3 opens.
        if ($job -and ($Attach -or $Paste)) {
            $no = Get-ChatqJobFilesRefusal $job
            if ($no) { Write-Host "  $no" -ForegroundColor Yellow; return }
            $got = Read-ChatqAttachSources $Attach -Paste:$Paste
            foreach ($s in @($got.Skipped)) { Write-Host "     skipped $s - only files go, not folders" -ForegroundColor DarkGray }
            if ($got.Error) { Write-Host "  $($got.Error) - nothing added" -ForegroundColor Yellow; return }
            if ($got.Text) { Write-Host "  the clipboard holds text, not files - chatq $($job.seq) opens the prompt to paste it in" -ForegroundColor Yellow; return }
            $add = Add-ChatqJobFiles $job $got
            if ($add.Error) { Write-Host "  $($add.Error)" -ForegroundColor Yellow; return }
            Write-Host "  #$($job.seq) '$($job.title)' now has $(Format-ChatqAttachSummary @(Get-ChatqAttachments $job))" -ForegroundColor Green
            Write-ChatqBoard
            return
        }
        if ($job) {
            $p = Get-ChatqPromptPath $job
            Write-Host "  #$($job.seq) '$($job.title)' $($script:ChatqDot) $($job.state) $($script:ChatqDot) $p" -ForegroundColor DarkGray
            if ($job.state -ne 'queued') { Write-Host '  already sent - editing it changes nothing now' -ForegroundColor DarkGray }
            elseif ($job.kind -eq 'continue') { Write-Host '  a -Continue job always sends "continue" - the file is only for show' -ForegroundColor DarkGray }
            $af = @(Get-ChatqAttachments $job)
            if ($af) { Write-Host "  $(Format-ChatqAttachSummary $af) $($script:ChatqDot) $(Get-ChatqAttachDir $job)" -ForegroundColor DarkGray }
            if (Test-Path -LiteralPath $p) { Invoke-ChatqEditor $p -NoWait }
            return
        }
    }
    try { $notBefore = ConvertFrom-ChatqWhen $At $In } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; return }

    # The files and the clipboard before the pick: text pasted as the prompt
    # should weigh in on which chat it is for, as a typed one does.
    if (($Attach -or $Paste) -and $Continue) {
        Write-Host '  -Continue sends "continue" and nothing else - give the files with -Prompt instead' -ForegroundColor Yellow
        return
    }
    $got = $null
    if ($Attach -or $Paste) {
        $got = Read-ChatqAttachSources $Attach -Paste:$Paste
        foreach ($s in @($got.Skipped)) { Write-Host "     skipped $s - only files go, not folders" -ForegroundColor DarkGray }
        if ($got.Error) { Write-Host "  $($got.Error) - nothing queued" -ForegroundColor Yellow; return }
    }
    $given = $PSBoundParameters.ContainsKey('Prompt')
    $textNote = $null
    if ($got -and $got.Text) {
        if ($given) { $Prompt = $Prompt.TrimEnd() + "`n`n" + $got.Text; $textNote = "the clipboard's text goes under the prompt" }
        else { $Prompt = $got.Text; $given = $true; $textNote = "the clipboard's text is the prompt" }
    }

    $res = Resolve-ChatqTarget $t $(if ($given) { $Prompt } else { '' }) $Provider -AllProjects:$AllProjects
    if ($res.Error) { Write-Host "  $($res.Error)" -ForegroundColor Yellow; return }
    Write-ChatqPick $res
    Write-ChatqPromptHint $t $res -HasPrompt:$given -Continue:$Continue
    $info = Get-ChatqJobInfo $res.Row
    if ($info.Error) { Write-Host "     $($info.Error)" -ForegroundColor Yellow; return }
    Write-ChatqJobInfo $info $Mode -Continue:$Continue $res.Row.Provider
    if ($Model) { Write-Host "     model $Model for this run (the chat's own: $(if ($info.Model) { $info.Model } else { 'unknown' }))" -ForegroundColor DarkGray }
    if ($textNote) { Write-Host "     $textNote" -ForegroundColor DarkGray }
    if ($got) {
        $pending = @(foreach ($s in $got.Files) { Get-Item -LiteralPath $s })
        if ($got.Image) { $pending += [pscustomobject]@{ Name = 'clip.png'; Length = $got.Image.Length } }
        if ($pending) {
            Write-Host "     with $(Format-ChatqAttachSummary $pending)" -ForegroundColor DarkGray
            $bytes = ($pending | Measure-Object -Property Length -Sum).Sum
            if ($pending.Count -gt $script:ChatqAttachWarnCount -or $bytes -gt $script:ChatqAttachWarnBytes) {
                Write-Host '     that is a lot for one run - every file costs context, and usage' -ForegroundColor Yellow
            }
        }
    }
    if ($WhatIf) { Write-Host '     -WhatIf: nothing queued' -ForegroundColor DarkGray; return }

    $how = @{ Mode = $Mode; Model = $Model; NotBefore = $notBefore; First = $First; Typed = $t }
    if ($Continue -or $given) {
        $made = New-ChatqJob -Row $res.Row -Prompt $Prompt -Kind $(if ($Continue) { 'continue' } else { 'prompt' }) -Info $info -Sources $got -Resolve $res @how
        if ($made.Error) { Write-Host "  $($made.Error)" -ForegroundColor Yellow; return }
        $job = $made.Job
        $missed = $made.Missed
    }
    else {
        # The editor. The files go in before the tab opens: a copy that fails -
        # one moved or locked since it was checked - then stops the job before
        # a word of it has been typed, rather than after.
        $slot = New-ChatqJobSlot $res.Row
        if ($got) {
            try { $null = Save-ChatqAttachSources $slot.Dir $got }
            catch { Write-Host "  a file could not be copied - nothing queued: $($_.Exception.Message)" -ForegroundColor Yellow; return }
        }
        Save-ChatqText $slot.Path $slot.Header
        Write-Host '     write the prompt in the editor tab, then save and close it (empty = cancel)' -ForegroundColor DarkGray
        Write-Host '     Ctrl+V there pastes a screenshot into it, and it goes with the prompt' -ForegroundColor DarkGray
        Invoke-ChatqEditor $slot.Path
        $text = Remove-ChatqPromptHeader ([System.IO.File]::ReadAllText($slot.Path, [System.Text.Encoding]::UTF8))
        if (-not $text) {
            Remove-Item -LiteralPath $slot.Path -Force -EA SilentlyContinue
            Remove-Item -LiteralPath $slot.Dir -Recurse -Force -EA SilentlyContinue
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
                    $slot.File = "#$($slot.Seq) $(Get-ChatqSafeName $res.Row.Title).md"
                    $new = Join-Path $script:ChatqQueueDir $slot.File
                    Move-Item -LiteralPath $slot.Path -Destination $new -Force
                    $slot.Path = $new
                }
            }
        }
        $job = New-ChatqJobRecord $slot $res.Row $info -Kind 'prompt' -Resolve $res @how
        $missed = (Register-ChatqJob $job).Missed
    }
    $seq = $job.seq
    # what the prompt links to in data/queue: an image pasted in the tab
    foreach ($x in @($missed)) { Write-Host "     could not take in $x - it goes without it" -ForegroundColor Yellow }
    $files = @(Get-ChatqAttachments $job)

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
    if ($files) { Write-Host "     $(Format-ChatqAttachSummary $files)" -ForegroundColor DarkGray }
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
            $stop = Stop-ChatqJobRun $j
            if ($stop -eq 'cancelling') {
                Write-Host "  #$($j.seq) cancelling - stopped within a few seconds" -ForegroundColor DarkGray
                continue
            }
            if ($stop -eq 'not running') { Write-Host "  #$($j.seq) had already ended - chatqrm $($j.seq) removes it" -ForegroundColor DarkGray; continue }
            Write-Host "  #$($j.seq) was left running by a watcher that stopped - marked failed" -ForegroundColor DarkGray
            Write-Host "    chatqrm $($j.seq) removes it, chatqrun $($j.seq) sends it again" -ForegroundColor DarkGray
            continue
        }
        $null = Remove-ChatqJob $j
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
    .PARAMETER First
    With a job number: put it at the front of the queue - a queued one moves
    up, a finished one is requeued there.
    #>
    param(
        [Parameter(Position = 0)][string]$Ref,
        [switch]$Now, [switch]$Foreground, [switch]$Stop,
        [ValidateSet('default', 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')][string]$Mode,
        [switch]$First
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
        if ($First -and $j.state -eq 'queued') {
            Set-ChatqJobFirst $j
            Write-Host "  #$($j.seq) moved to the front" -ForegroundColor Green
            Write-ChatqBoard
            Write-ChatqList
            return
        }
        # a finished one put first is requeued there
        if ($First -and $j.state -in 'failed', 'needs-input', 'done', 'skipped') { Set-ChatqProp $j 'first' (Get-ChatqStamp) }
        $again = Reset-ChatqJob $j $Mode
        if ($again.Error) { Write-Host "  $($again.Error)" -ForegroundColor DarkGray; return }
        $how = if ($again.Landed) { 'as "continue" - the prompt already reached the chat' } else { 'with its prompt' }
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
    foreach ($e in @(Get-ChatqLogEntries $j)) {
        switch ($e.Type) {
            'init' { Write-Host "  $($e.Text)" -ForegroundColor DarkGray }
            'denied' { Write-Host "  ! denied $($e.Text)" -ForegroundColor Yellow }
            'text' { Write-Host ''; Write-Host $e.Text }
            'tool' { Write-Host "  > $($e.Text)" -ForegroundColor DarkGray }
            'result' { Write-Host ''; Write-Host "  = $($e.Text)" -ForegroundColor DarkGray }
            'error' { Write-Host "  ! $($e.Text)" -ForegroundColor Yellow }
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

    Paste the key itself rather than the whole push URL that page shows. A URL
    pasted bare never reaches chatq at all - PowerShell stops at its first & -
    and one in quotes has its key and device read out of it.

    Tasker: every title starts "chatq ", so a profile on the Join plugin's
    event can filter them, or match only "needs input" and "failed".

    ntfy instead of, or as well as, Join: -Ntfy <topic>. Anyone who knows the
    topic can read the alerts, so treat it as a password - a long random one on
    ntfy.sh, or your own server with -NtfyServer and -NtfyToken.

    -Command runs your own PowerShell on every alert, with the alert in
    $env:CHATQ_EVENT, CHATQ_TITLE, CHATQ_TEXT, CHATQ_PRIORITY, CHATQ_JOB and
    CHATQ_PRESENT (1 while you are at the PC). A desktop toast is on unless
    -Toast off. The phone stays quiet while you are at the PC - keyboard or
    mouse used in the last -QuietMinutes (5; 0 turns that off).
    .EXAMPLE
    chatqnotify -ApiKey 0123abcd... -Device group.phone
    .EXAMPLE
    chatqnotify -Ntfy chatq-7f3a9c1e2b
    .EXAMPLE
    chatqnotify -Command 'Invoke-RestMethod https://example.com/hook -Method Post -Body $env:CHATQ_TEXT'
    .EXAMPLE
    chatqnotify -Test
    #>
    param(
        [string]$ApiKey, [string]$Device, [switch]$Test, [switch]$Off,
        [string]$Ntfy, [string]$NtfyServer, [string]$NtfyToken,
        [string]$Command, [ValidateSet('on', 'off')][string]$Toast, [int]$QuietMinutes = -1
    )
    Set-StrictMode -Off
    $cfg = Get-ChatqConfig
    $save = {
        Save-ChatqJson $script:ChatqConfigPath $cfg
        if (-not $script:ChatqIsWindows) { try { & chmod 600 $script:ChatqConfigPath } catch {} }
    }
    if ($Off) {
        foreach ($k in 'join', 'ntfy', 'command') { if ($cfg.PSObject.Properties[$k]) { $cfg.PSObject.Properties.Remove($k) } }
        & $save
        Write-Host '  phone alerts and the command off - they still go to data/logs/alerts.log (and the toast)' -ForegroundColor DarkGray
        return
    }
    $changed = $false
    # The Join page hands you a whole push URL, so pasting that is the obvious
    # move. Take the key and the device out of it. Unquoted it never gets this
    # far - PowerShell stops at the & itself, and nothing here can catch that -
    # so the help says to paste the key alone.
    if ($ApiKey -match '[?&]apikey=') {
        $dev = if ($ApiKey -match '[?&]device(?:Id|Names)=([^&\s]+)') { $Matches[1] } else { '' }
        $key = if ($ApiKey -match '[?&]apikey=([^&\s]+)') { $Matches[1] } else { '' }
        if ($key) {
            $ApiKey = $key
            if (-not $Device -and $dev) { $Device = [uri]::UnescapeDataString($dev) }
            Write-Host '  took the key out of the URL you pasted' -ForegroundColor DarkGray
        }
    }
    if ($ApiKey -or $Device) {
        $j = if ($cfg.join) { $cfg.join } else { [pscustomobject]@{} }
        if ($ApiKey) { Set-ChatqProp $j 'apiKey' ([pscustomobject](Protect-ChatqSecret $ApiKey.Trim())) }
        if ($Device) { Set-ChatqProp $j 'device' $Device.Trim() }
        if (-not $j.device) { Set-ChatqProp $j 'device' 'group.phone' }
        Set-ChatqProp $cfg 'join' $j
        $changed = $true
        Write-Host "  Join saved $($script:ChatqDot) device $($j.device)$(if ($j.apiKey.protected) { " $($script:ChatqDot) key protected with DPAPI" })" -ForegroundColor Green
    }
    if ($Ntfy -or $NtfyServer -or $NtfyToken) {
        $n = if ($cfg.PSObject.Properties['ntfy'] -and $cfg.ntfy) { $cfg.ntfy } else { [pscustomobject]@{} }
        if ($Ntfy) { Set-ChatqProp $n 'topic' ([pscustomobject](Protect-ChatqSecret $Ntfy.Trim())) }
        if ($NtfyServer) { Set-ChatqProp $n 'server' $NtfyServer.Trim().TrimEnd('/') }
        if ($NtfyToken) { Set-ChatqProp $n 'token' ([pscustomobject](Protect-ChatqSecret $NtfyToken.Trim())) }
        Set-ChatqProp $cfg 'ntfy' $n
        $changed = $true
        $shown = Unprotect-ChatqSecret $n.topic
        # never the whole topic: it is the password
        if ($shown) { $shown = $shown.Substring(0, [Math]::Min(3, $shown.Length)) + '...' }
        Write-Host "  ntfy saved $($script:ChatqDot) topic $shown $($script:ChatqDot) $(if ($n.server) { $n.server } else { 'https://ntfy.sh' })" -ForegroundColor Green
    }
    if ($PSBoundParameters.ContainsKey('Command')) {
        if ($Command.Trim()) { Set-ChatqProp $cfg 'command' $Command; Write-Host '  command saved - it runs on every alert' -ForegroundColor Green }
        elseif ($cfg.PSObject.Properties['command']) { $cfg.PSObject.Properties.Remove('command'); Write-Host '  command removed' -ForegroundColor DarkGray }
        $changed = $true
    }
    if ($Toast) { Set-ChatqProp $cfg 'toast' ($Toast -eq 'on'); $changed = $true; Write-Host "  desktop toast $Toast" -ForegroundColor Green }
    if ($QuietMinutes -ge 0) {
        Set-ChatqProp $cfg 'quietMinutes' $QuietMinutes; $changed = $true
        $what = if ($QuietMinutes) { "the phone stays quiet while you used the PC in the last $QuietMinutes min" } else { 'the phone is always sent to' }
        Write-Host "  $what" -ForegroundColor Green
    }
    if ($changed) { & $save }
    if ($Test -or $ApiKey -or $Ntfy) {
        # -Loud: typed at the PC by definition, and meant for the phone anyway
        $ok = Send-ChatqAlert 'test' "chatq reaches this device $($script:ChatqDot) $([Environment]::MachineName)" 1 -Loud
        foreach ($r in @($script:ChatqAlertReport)) { Write-Host "  $r" -ForegroundColor $(if ($r -match ': (sent|shown|ran)$') { 'Green' } else { 'Yellow' }) }
        if ($ok) { Write-Host '  check your phone' -ForegroundColor Green }
        return
    }
    if (-not $changed) {
        $cfg = Get-ChatqConfig
        $any = $false
        if ($cfg.PSObject.Properties['join'] -and $cfg.join -and $cfg.join.apiKey) { $any = $true; Write-Host "  Join on $($script:ChatqDot) device $($cfg.join.device)" -ForegroundColor DarkGray }
        if ($cfg.PSObject.Properties['ntfy'] -and $cfg.ntfy -and $cfg.ntfy.topic) { $any = $true; Write-Host "  ntfy on $($script:ChatqDot) $(if ($cfg.ntfy.server) { $cfg.ntfy.server } else { 'https://ntfy.sh' })" -ForegroundColor DarkGray }
        if ($cfg.PSObject.Properties['command'] -and $cfg.command) { Write-Host '  command on' -ForegroundColor DarkGray }
        $toastOn = -not ($cfg.PSObject.Properties['toast'] -and $cfg.toast -eq $false)
        $qm = if ($cfg.PSObject.Properties['quietMinutes']) { [int]$cfg.quietMinutes } else { 5 }
        Write-Host "  toast $(if ($toastOn) { 'on' } else { 'off' }) $($script:ChatqDot) phone quiet while at the PC: $(if ($qm) { "$qm min" } else { 'off' })" -ForegroundColor DarkGray
        if ($any) { Write-Host '  chatqnotify -Test sends one' -ForegroundColor DarkGray }
        else {
            Write-Host '  no phone alerts yet - Join or ntfy:' -ForegroundColor DarkGray
            Write-Host '      chatqnotify -ApiKey <key> -Device <device id | group.phone>   (https://joinjoaomgcd.appspot.com, Join API)' -ForegroundColor Cyan
            Write-Host '        the key itself, not the push URL - PowerShell stops at the & in one unless it is quoted' -ForegroundColor DarkGray
            Write-Host '      chatqnotify -Ntfy <long random topic>                        (https://ntfy.sh, free)' -ForegroundColor Cyan
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
    Write-Host '  chatqnotify                 alerts: toast here, Join or ntfy on the phone' -ForegroundColor Cyan
    Write-Host '  chatoverlay                 every open chat, the queue and usage, always on top' -ForegroundColor Cyan
    Write-Host '  chatconsole                 all of the above in a window: write, drop files, send now' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  -WhatIf shows the pick only   -Mode auto|acceptEdits|...   -At 13:00 / -In 2h' -ForegroundColor DarkGray
    Write-Host '  -Attach a.png, spec.pdf / -Paste   send files, a screenshot or the clipboard with it' -ForegroundColor DarkGray
    Write-Host '  Tab fills in a title from any part of it, like chatrm: chatq card red<Tab>' -ForegroundColor DarkGray
    Write-Host '  chat = every command, find and delete included' -ForegroundColor DarkGray
    Write-Host "  VS-code-chat-manager $script:ChatVersion $($script:ChatqDot) $script:ChatqScriptPath" -ForegroundColor DarkGray
}

#endregion

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

#region overlay: Windows window ------------------------------------------------
# WPF in a hidden powershell.exe -STA. The window never takes focus and lets
# clicks through while locked: WS_EX_NOACTIVATE, WS_EX_TRANSPARENT on top of
# the WS_EX_LAYERED a transparent WPF window has anyway, and WS_EX_TOOLWINDOW
# to keep it out of Alt+Tab and off the taskbar. Its buttons are a second
# small window beside it, shown while the pointer is near, which takes the
# mouse where it is drawn. The C# below is C# 5, which is what Windows
# PowerShell 5.1 compiles, and holds nothing that moves the pointer, types,
# or brings a window forward; the pointer is only ever read.

$script:ChatOverlayNativeCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class ChatOverlayNative {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern int GetWindowLong32(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")] static extern IntPtr GetWindowLongPtr64(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr h, int i, int v);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    const int GWL_EXSTYLE = -20;
    public const long WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_LAYERED = 0x80000, WS_EX_NOACTIVATE = 0x8000000;
    const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_NOOWNERZORDER = 0x200;

    public static long GetExStyle(IntPtr h) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(h, GWL_EXSTYLE).ToInt64() : GetWindowLong32(h, GWL_EXSTYLE);
    }
    static void SetExStyle(IntPtr h, long v) {
        if (IntPtr.Size == 8) { SetWindowLongPtr64(h, GWL_EXSTYLE, new IntPtr(v)); } else { SetWindowLong32(h, GWL_EXSTYLE, (int)v); }
    }
    // always a tool window that never activates; clicks go through only while
    // locked. WPF sets APPWINDOW for ShowInTaskbar, which would put a button
    // on the taskbar in spite of TOOLWINDOW, so it goes.
    public static void ApplyExStyle(IntPtr h, bool clickThrough) {
        long s = (GetExStyle(h) | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED) & ~WS_EX_APPWINDOW;
        s = clickThrough ? (s | WS_EX_TRANSPARENT) : (s & ~WS_EX_TRANSPARENT);
        SetExStyle(h, s);
    }
    // back above windows that took the topmost band since - without activating
    public static void KeepTopmost(IntPtr h) {
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    public static void MoveTo(IntPtr h, int x, int y) {
        SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    // where and how big, in the pixels of the screen it lands on
    public static void Place(IntPtr h, int x, int y, int w, int hgt) {
        SetWindowPos(h, IntPtr.Zero, x, y, w, hgt, SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    public static int[] GetRect(IntPtr h) {
        RECT r;
        if (!GetWindowRect(h, out r)) { return null; }
        return new int[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top };
    }
    // per-monitor v2 where Windows has it (1703+), else system-wide
    public static bool SetDpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return true; } } catch (EntryPointNotFoundException) { }
        try { return SetProcessDPIAware(); } catch (EntryPointNotFoundException) { return false; }
    }
    // a file dropped on the console, copied off the window's thread: a large
    // one would otherwise freeze the panel and the console both
    public static System.Threading.Tasks.Task CopyFileAsync(string from, string to) {
        return System.Threading.Tasks.Task.Run(() => System.IO.File.Copy(from, to, true));
    }
}

// A system-wide hotkey: a hidden window of its own to receive WM_HOTKEY,
// filtered here so PowerShell hears only the key press, not every message.
public class ChatOverlayHotkey : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    const int WM_HOTKEY = 0x312;
    const uint MOD_NOREPEAT = 0x4000;
    bool registered;
    public event EventHandler Pressed;
    public ChatOverlayHotkey() { CreateHandle(new CreateParams()); }
    public bool Register(uint mods, uint vk) {
        if (registered) { UnregisterHotKey(Handle, 1); registered = false; }
        registered = RegisterHotKey(Handle, 1, mods | MOD_NOREPEAT, vk);
        return registered;
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && Pressed != null) { Pressed(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
    public void Dispose() {
        if (registered) { UnregisterHotKey(Handle, 1); registered = false; }
        if (Handle != IntPtr.Zero) { DestroyHandle(); }
    }
}
'@

# Two looks. A state keeps its colour's meaning in both; the light look's are
# darker, to read on white. panel is the ground of the buttons and settings
# box, which sit over the rows; accent marks the choice made.
$script:ChatOverlayPalettes = @{
    dark  = @{
        waiting = '#F5B942'; 'needs-input' = '#F5B942'; busy = '#4CC38A'; running = '#4EA1FF'; idle = '#80868F'; queued = '#B48CFF'; cutoff = '#FF8A4C'
        text = '#E8EAED'; dim = '#9AA0A6'; faint = '#6B7079'; project = '#8AB8FF'; frame = '#EB1B1F24'; edge = '#2EFFFFFF'
        unlocked = '#4EA1FF'; track = '#26FFFFFF'; normal = '#5AA9E6'; warning = '#F5B942'; critical = '#FF5C5C'
        warn = '#F5B942'; error = '#FF7B72'; panel = '#F7262B33'; hover = '#33FFFFFF'; accent = '#4EA1FF'; onAccent = '#FFFFFF'
        window = '#FF1E2227'; input = '#FF15181C'; inputEdge = '#3DFFFFFF'; select = '#384EA1FF'
    }
    light = @{
        waiting = '#C98A00'; 'needs-input' = '#C98A00'; busy = '#1A8F4C'; running = '#1F6FEB'; idle = '#8C959F'; queued = '#8250DF'; cutoff = '#BC4C00'
        text = '#1F2328'; dim = '#57606A'; faint = '#8C959F'; project = '#0969DA'; frame = '#F2FAFAFB'; edge = '#26000000'
        unlocked = '#0969DA'; track = '#1F000000'; normal = '#0969DA'; warning = '#BF8700'; critical = '#CF222E'
        warn = '#9A6700'; error = '#CF222E'; panel = '#FAFFFFFF'; hover = '#1A000000'; accent = '#0969DA'; onAccent = '#FFFFFF'
        window = '#FFF6F8FA'; input = '#FFFFFFFF'; inputEdge = '#40000000'; select = '#290969DA'
    }
}
$script:ChatOverlayColors = $script:ChatOverlayPalettes.dark

function Initialize-ChatOverlayNative {
    # In the one order that works: DPI awareness is process-wide and only the
    # first call gets to set it, and WPF reads it as it loads. The AppContext
    # switch lets WPF redraw at a second monitor's own scale when the panel is
    # dragged there, instead of keeping the first one's.
    if (-not ('ChatOverlayNative' -as [type])) {
        Add-Type -TypeDefinition $script:ChatOverlayNativeCode -ReferencedAssemblies System.Windows.Forms
    }
    try { [void][ChatOverlayNative]::SetDpiAware() } catch { Write-ChatOverlayLog "dpi: $($_.Exception.Message)" }
    try { [System.AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false) } catch {}
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
    # A panel this small, redrawn every few seconds at most, gains nothing
    # from a Direct3D device - which is most of what WPF would otherwise hold.
    try { [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly } catch {}
}

function Get-ChatOverlayBrush {
    param([string]$Name)
    $hex = if ($Name.StartsWith('#')) { $Name } else { $script:ChatOverlayColors[$Name] }
    if (-not $hex) { $hex = $script:ChatOverlayColors.text }
    $b = $script:ChatOverlayBrushes[$hex]
    if (-not $b) {
        $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()
        $script:ChatOverlayBrushes[$hex] = $b
    }
    return $b
}

function New-ChatOverlayText {
    param([string]$Text, [string]$Color = 'text', [double]$Size = 0, [switch]$Bold, [switch]$Trim)
    $t = [System.Windows.Controls.TextBlock]::new()
    $t.Text = $Text
    $t.Foreground = Get-ChatOverlayBrush $Color
    if ($Size) { $t.FontSize = $Size }
    if ($Bold) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    if ($Trim) { $t.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis }
    return $t
}

function New-ChatOverlayWindow {
    # The window and its frame, built in code rather than XAML: rows come and
    # go every pass, and one way of making elements is simpler than two.
    param($H)
    $cfg = $H.Ctx.Config
    [void](Select-ChatOverlayPalette $H)
    $w = [System.Windows.Window]::new()
    $w.Title = 'chatoverlay'
    $w.WindowStyle = [System.Windows.WindowStyle]::None
    $w.AllowsTransparency = $true
    $w.Background = [System.Windows.Media.Brushes]::Transparent
    $w.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $w.Topmost = $true
    $w.ShowActivated = $false
    # true, with WS_EX_TOOLWINDOW keeping it off the taskbar: false would make
    # WPF parent the window to a hidden owner that is not topmost
    $w.ShowInTaskbar = $true
    $w.SizeToContent = [System.Windows.SizeToContent]::Height
    $w.Width = $cfg.width
    $w.Opacity = $cfg.opacity
    $w.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $w.Left = -32000
    $w.Top = -32000
    $w.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI, Malgun Gothic, Microsoft YaHei UI')
    $w.FontSize = 12
    $frame = [System.Windows.Controls.Border]::new()
    $frame.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $frame.Background = Get-ChatOverlayBrush 'frame'
    $frame.BorderBrush = Get-ChatOverlayBrush 'edge'
    $frame.BorderThickness = [System.Windows.Thickness]::new(1)
    $frame.Padding = [System.Windows.Thickness]::new(11, 8, 11, 9)
    $stack = [System.Windows.Controls.StackPanel]::new()
    $frame.Child = $stack
    $w.Content = $frame
    # only ever raised while unlocked - a locked window lets the mouse through
    $frame.add_MouseLeftButtonDown({ Invoke-ChatOverlayDrag })
    $frame.add_MouseEnter({ $script:ChatOverlayHost.PointerIn = $true })
    $frame.add_MouseLeave({ $script:ChatOverlayHost.PointerIn = $false; $script:ChatOverlayHost.LeftAt = Get-Date })
    $H.Win = $w
    $H.Frame = $frame
    $H.Stack = $stack
    $H.Hwnd = [System.Windows.Interop.WindowInteropHelper]::new($w).EnsureHandle()
    [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
    New-ChatOverlayControlsWindow $H
}

function New-ChatOverlayControlsWindow {
    <#
    The buttons and the settings box live in a small window of their own,
    on the panel's top edge rather than over its rows. So the panel stays
    click-through all over, and this one - shown only while the pointer is
    near - takes the mouse where it is drawn; its see-through parts let
    clicks through, as any layered window's do. The same styles as the panel
    less WS_EX_TRANSPARENT: it never takes focus either, and is in neither
    Alt+Tab nor the taskbar. Kept at full opacity, so the slider stays
    readable whatever it is set to.
    #>
    param($H)
    $c = [System.Windows.Window]::new()
    $c.Title = 'chatoverlay controls'
    $c.WindowStyle = [System.Windows.WindowStyle]::None
    $c.AllowsTransparency = $true
    $c.Background = [System.Windows.Media.Brushes]::Transparent
    $c.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $c.Topmost = $true
    $c.ShowActivated = $false
    # true for the same reason as the panel's: false means a hidden owner
    # that is not topmost
    $c.ShowInTaskbar = $true
    $c.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $c.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $c.Left = -32000
    $c.Top = -32000
    $c.FontFamily = $H.Win.FontFamily
    $c.FontSize = 12
    $stack = [System.Windows.Controls.StackPanel]::new()
    $c.Content = $stack
    $H.CtlWin = $c
    $H.CtlStack = $stack
    New-ChatOverlayControls $H
    $H.CtlHwnd = [System.Windows.Interop.WindowInteropHelper]::new($c).EnsureHandle()
    [ChatOverlayNative]::ApplyExStyle($H.CtlHwnd, $false)
    # the box opening or closing changes its size; the edge by the panel stays
    $c.add_SizeChanged({ param($s, $e) Set-ChatOverlayControlsPlacement $script:ChatOverlayHost $e.NewSize })
}

function Select-ChatOverlayPalette {
    # the colours for the theme set, and whether that changed the look
    param($H)
    $name = Resolve-ChatOverlayTheme $H.Ctx.Config.theme
    if ($name -eq $H.ThemeName) { return $false }
    $H.ThemeName = $name
    $script:ChatOverlayColors = $script:ChatOverlayPalettes[$name]
    return $true
}

function Update-ChatOverlayTheme {
    # the look again, after the setting or Windows' own changed: the frame,
    # the buttons and settings box made anew, the rows redrawn, the tray dot
    param($H)
    if (-not (Select-ChatOverlayPalette $H)) { return }
    $H.Frame.Background = Get-ChatOverlayBrush 'frame'
    $H.Frame.BorderBrush = Get-ChatOverlayBrush $(if ($H.Locked) { 'edge' } else { 'unlocked' })
    New-ChatOverlayControls $H
    # the console too, keeping what is typed in it
    if ($H.Con) { Initialize-ChatConsoleContent $H }
    $H.ViewKey = $null
    if ($H.Snap) {
        Update-ChatOverlayView $H $H.Snap
        if ($H.Tray) { Update-ChatOverlayTray $H $H.Snap }
    }
}

function New-ChatOverlayIcon {
    # A small button drawn as a path, so no icon font is needed: stroked for
    # lines, filled for dots, or both.
    param([string]$Tip, $Geometry, [switch]$Stroke, [switch]$Fill)
    $b = [System.Windows.Controls.Border]::new()
    $b.Width = 22
    $b.Height = 20
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    # transparent, not none: WPF sends the mouse only to what is painted
    $b.Background = [System.Windows.Media.Brushes]::Transparent
    $b.ToolTip = $Tip
    $p = [System.Windows.Shapes.Path]::new()
    $p.Data = $Geometry
    if ($Stroke) {
        $p.Stroke = Get-ChatOverlayBrush 'dim'
        $p.StrokeThickness = 1.4
        $p.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
        $p.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
    }
    if ($Fill) { $p.Fill = Get-ChatOverlayBrush 'dim' }
    $p.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $p.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $b.Child = $p
    $b.add_MouseEnter({ param($s, $e) $s.Background = Get-ChatOverlayBrush 'hover' })
    $b.add_MouseLeave({ param($s, $e) $s.Background = [System.Windows.Media.Brushes]::Transparent })
    return $b
}

function New-ChatOverlayControls {
    <#
    The controls window's content: a row of buttons - drag grip, collapse,
    refresh usage, settings, hide to the tray, close, left to right, so
    close sits at the corner as it does on any window - and the settings box
    on the far side of them from the panel. Made anew when the look changes
    or the panel folds; the box stays open or shut as it was.
    #>
    param($H)
    $H.CtlStack.Children.Clear()
    $geo = { param($d) [System.Windows.Media.Geometry]::Parse($d) }
    $dots = [System.Windows.Media.GeometryGroup]::new()
    foreach ($x in 1.5, 5.5) { foreach ($y in 1.5, 5.5, 9.5) { $dots.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new($x, $y), 1.25, 1.25)) } }
    $sliders = [System.Windows.Media.GeometryGroup]::new()
    $sliders.Children.Add((& $geo 'M0,2.5 L11,2.5 M0,8.5 L11,8.5'))
    $sliders.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new(3.5, 2.5), 1.8, 1.8))
    $sliders.Children.Add([System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new(7.5, 8.5), 1.8, 1.8))
    # a chevron pointing where the panel will go: up to fold it, down to open it
    $fold = if ($H.Collapsed) { & $geo 'M0.5,1 L4.5,5 L8.5,1' } else { & $geo 'M0.5,5 L4.5,1 L8.5,5' }
    # a circle with a gap and an arrowhead
    $again = & $geo 'M8.6,3.2 A4,4 0 1 0 9,6.5 M8.8,0.6 L8.7,3.4 L5.9,3.1'
    # an arrow down onto a line: into the tray
    $tray = & $geo 'M4.5,0.5 L4.5,6 M2,3.6 L4.5,6 L7,3.6 M0.5,9 L8.5,9'
    # a speech bubble: the console, to write to a chat
    $bubble = & $geo 'M1,1 L10,1 L10,7 L4.5,7 L2,9.5 L2,7 L1,7 Z'
    $cross = & $geo 'M0.5,0.5 L8.5,8.5 M8.5,0.5 L0.5,8.5'

    $grip = New-ChatOverlayIcon 'Drag to move' $dots -Fill
    $grip.Cursor = [System.Windows.Input.Cursors]::SizeAll
    $grip.add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Start-ChatOverlayGripDrag $s })
    $grip.add_MouseMove({ param($s, $e) Move-ChatOverlayGripDrag })
    $grip.add_MouseLeftButtonUp({ param($s, $e) Stop-ChatOverlayGripDrag $s })
    $grip.add_LostMouseCapture({ param($s, $e) Stop-ChatOverlayGripDrag $s })
    $foldB = New-ChatOverlayIcon $(if ($H.Collapsed) { 'Expand' } else { 'Collapse to one line' }) $fold -Stroke
    $foldB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Collapsed) { 'expand' } else { 'collapse' }) })
    $againB = New-ChatOverlayIcon 'Ask Claude for usage now - Codex''s moves only when Codex runs' $again -Stroke
    $againB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayRefresh })
    # turns while an ask is out (Update-ChatOverlaySpin), about the arc's centre
    $againB.Child.RenderTransform = [System.Windows.Media.RotateTransform]::new(0, 5.2, 5.3)
    $H.Spin = $againB.Child.RenderTransform
    $H.Spinning = $false
    $conB = New-ChatOverlayIcon 'Open the console - write to a chat, queue, continue' $bubble -Stroke
    $conB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb 'console' })
    $gear = New-ChatOverlayIcon 'Opacity and theme' $sliders -Stroke -Fill
    $gear.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Set-ChatOverlaySettingsOpen $script:ChatOverlayHost (-not $script:ChatOverlayHost.SettingsOpen) })
    $trayB = New-ChatOverlayIcon 'Hide to the tray - click the tray dot to show it' $tray -Stroke
    $trayB.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Hide-ChatOverlayByButton })
    $close = New-ChatOverlayIcon 'Close the overlay - chatoverlay starts it again' $cross -Stroke
    $close.add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Invoke-ChatOverlayVerb 'stop' })
    $line = [System.Windows.Controls.StackPanel]::new()
    $line.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $H.CtlButtons = @($grip, $foldB, $againB, $conB, $gear, $trayB, $close)
    foreach ($b in $H.CtlButtons) { [void]$line.Children.Add($b) }
    $H.CtlLine = $line
    $bar = [System.Windows.Controls.Border]::new()
    $bar.Background = Get-ChatOverlayBrush 'panel'
    $bar.BorderBrush = Get-ChatOverlayBrush 'edge'
    $bar.BorderThickness = [System.Windows.Thickness]::new(1)
    $bar.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $bar.Padding = [System.Windows.Thickness]::new(1)
    $bar.Child = $line
    $H.Controls = $bar
    $H.Settings = New-ChatOverlaySettings $H
    Set-ChatOverlayControlsSide $H $(if ($H.CtlSide) { $H.CtlSide } else { 'above' })
}

function New-ChatOverlaySettings {
    # the box beside the row of buttons: opacity on a slider, the theme as
    # three choices, and usage as lines or bars
    param($H)
    $theme = [string]$H.Ctx.Config.theme
    $box = [System.Windows.Controls.Border]::new()
    $box.Background = Get-ChatOverlayBrush 'panel'
    $box.BorderBrush = Get-ChatOverlayBrush 'edge'
    $box.BorderThickness = [System.Windows.Thickness]::new(1)
    $box.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $box.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $box.Width = 244
    $box.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    $box.Visibility = if ($H.SettingsOpen) { 'Visible' } else { 'Collapsed' }
    $g = [System.Windows.Controls.Grid]::new()
    foreach ($cw in 56, 0, 38) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($cw) { [System.Windows.GridLength]::new($cw) } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $g.ColumnDefinitions.Add($cd)
    }
    foreach ($i in 1..3) { $g.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) }
    $put = {
        param($el, $row, $col, $span = 1)
        [System.Windows.Controls.Grid]::SetRow($el, $row)
        [System.Windows.Controls.Grid]::SetColumn($el, $col)
        [System.Windows.Controls.Grid]::SetColumnSpan($el, $span)
        [void]$g.Children.Add($el)
    }
    $label = { param($t) $l = New-ChatOverlayText $t 'dim' 11; $l.VerticalAlignment = [System.Windows.VerticalAlignment]::Center; $l }

    & $put (& $label 'Opacity') 0 0
    $slider = [System.Windows.Controls.Slider]::new()
    $slider.Minimum = 0.3
    $slider.Maximum = 1.0
    $slider.SmallChange = 0.05
    $slider.LargeChange = 0.1
    $slider.IsMoveToPointEnabled = $true
    $slider.Value = if ($H.Win) { $H.Win.Opacity } else { $H.Ctx.Config.opacity }
    $slider.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $slider.Margin = [System.Windows.Thickness]::new(0, 2, 4, 2)
    $slider.add_ValueChanged({ param($s, $e) Set-ChatOverlayOpacity $script:ChatOverlayHost $e.NewValue })
    & $put $slider 0 1
    $H.OpacityText = New-ChatOverlayText "$([int][Math]::Round($slider.Value * 100))%" 'text' 11
    $H.OpacityText.TextAlignment = [System.Windows.TextAlignment]::Right
    $H.OpacityText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    & $put $H.OpacityText 0 2

    & $put (& $label 'Theme') 1 0
    & $put (New-ChatOverlayChips @('dark', 'light', 'system') $theme { param($s, $e) $e.Handled = $true; Set-ChatOverlayThemeChoice $script:ChatOverlayHost ([string]$s.Tag) }) 1 1 2
    & $put (& $label 'Usage') 2 0
    & $put (New-ChatOverlayChips @('lines', 'bars') ([string]$H.Ctx.Config.usageView) { param($s, $e) $e.Handled = $true; Set-ChatOverlayUsageView $script:ChatOverlayHost ([string]$s.Tag) }) 2 1 2
    $box.Child = $g
    return $box
}

function New-ChatOverlayChips {
    # a row of choices, the one in force filled in; a click hands its name
    # to -OnClick
    param([string[]]$Names, [string]$Current, [scriptblock]$OnClick)
    $chips = [System.Windows.Controls.StackPanel]::new()
    $chips.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $chips.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    foreach ($t in $Names) {
        $on = $t -eq $Current
        $c = [System.Windows.Controls.Border]::new()
        $c.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $c.BorderThickness = [System.Windows.Thickness]::new(1)
        $c.Padding = [System.Windows.Thickness]::new(8, 1, 8, 2)
        $c.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
        $c.Background = if ($on) { Get-ChatOverlayBrush 'accent' } else { [System.Windows.Media.Brushes]::Transparent }
        $c.BorderBrush = Get-ChatOverlayBrush $(if ($on) { 'accent' } else { 'edge' })
        $c.Cursor = [System.Windows.Input.Cursors]::Hand
        $c.Tag = $t
        $c.Child = New-ChatOverlayText ($t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1)) $(if ($on) { 'onAccent' } else { 'text' }) 11
        $c.add_MouseLeftButtonUp($OnClick)
        [void]$chips.Children.Add($c)
    }
    return $chips
}

function Set-ChatOverlaySettingsOpen {
    param($H, [bool]$Open)
    $H.SettingsOpen = $Open
    if ($H.Settings) { $H.Settings.Visibility = if ($Open) { 'Visible' } else { 'Collapsed' } }
}

function Show-ChatOverlayControls {
    # the controls window comes with the pointer and goes with it, closing
    # the box; placed before it shows, so it never flashes where it last was
    param($H, [bool]$Show)
    $H.ControlsShown = $Show
    if (-not $H.CtlWin) { return }
    if ($Show) {
        Set-ChatOverlayControlsPlacement $H
        $H.CtlWin.Show()
        # WPF sets WS_EX_APPWINDOW again as it shows a window
        [ChatOverlayNative]::ApplyExStyle($H.CtlHwnd, $false)
        [ChatOverlayNative]::KeepTopmost($H.CtlHwnd)
        Set-ChatOverlayControlsPlacement $H
    }
    else {
        if ($H.SettingsOpen) { Set-ChatOverlaySettingsOpen $H $false }
        $H.CtlWin.Hide()
    }
}

function Get-ChatOverlayControlsPlacement {
    <#
    Where the controls window goes, all in screen pixels (-Panel a rect,
    x y width height; -Size just width and height): its long edge along the
    panel's top, its right end at the panel's top-right corner - above the
    panel while the row of buttons (-Bar tall) fits there, else below it,
    on the side it is on already (-Prefer, above at first) while it fits.
    So the box opening, which makes the window taller away from the panel,
    never moves the buttons out from under the pointer; a box too tall for
    its side is kept on the screen instead. Kept on the screen side to side
    too. Pure, for the tests.
    #>
    param([int[]]$Panel, [int[]]$Size, $Screen, [int]$Gap = 4, [string]$Prefer = 'above', [int]$Bar = 0)
    if ($Bar -le 0) { $Bar = $Size[1] }
    $top = $Screen.Y
    $bottom = $Screen.Y + $Screen.Height
    $fitsAbove = $Panel[1] - $Gap - $Bar -ge $top
    $fitsBelow = $Panel[1] + $Panel[3] + $Gap + $Bar -le $bottom
    $side = if ($Prefer -eq 'below') { if ($fitsBelow -or -not $fitsAbove) { 'below' } else { 'above' } }
    else { if ($fitsAbove -or -not $fitsBelow) { 'above' } else { 'below' } }
    $y = if ($side -eq 'above') { [Math]::Max($top, $Panel[1] - $Gap - $Size[1]) } else { [Math]::Min($bottom - $Size[1], $Panel[1] + $Panel[3] + $Gap) }
    $x = [Math]::Max($Screen.X, [Math]::Min($Panel[0] + $Panel[2] - $Size[0], $Screen.X + $Screen.Width - $Size[0]))
    return [pscustomobject]@{ X = [int]$x; Y = [int]$y; Side = $side }
}

function Set-ChatOverlayControlsSide {
    # The row of buttons hugs the panel's edge, above it or below, flush
    # with its right; the settings box goes on the far side of the row, so
    # opening it never pushes the row off the panel's edge.
    param($H, [string]$Side)
    $H.CtlSide = $Side
    foreach ($el in @($H.Controls, $H.Settings)) { if ($el) { $el.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right } }
    if (-not $H.CtlStack -or -not $H.Controls -or -not $H.Settings) { return }
    $H.Settings.Margin = if ($Side -eq 'below') { [System.Windows.Thickness]::new(0, 4, 0, 0) } else { [System.Windows.Thickness]::new(0, 0, 0, 4) }
    $H.CtlStack.Children.Clear()
    $order = if ($Side -eq 'below') { $H.Controls, $H.Settings } else { $H.Settings, $H.Controls }
    foreach ($el in $order) { [void]$H.CtlStack.Children.Add($el) }
}

function Set-ChatOverlayControlsPlacement {
    # the controls window on the panel's top edge, wherever the panel is
    # now; -Dip the size it is about to take, in WPF's units
    param($H, $Dip)
    if (-not $H -or -not $H.CtlWin -or $H.CtlHwnd -eq [IntPtr]::Zero -or $H.Hwnd -eq [IntPtr]::Zero) { return }
    $p = [ChatOverlayNative]::GetRect($H.Hwnd)
    $c = [ChatOverlayNative]::GetRect($H.CtlHwnd)
    if (-not $p -or -not $c) { return }
    $a = if ($script:ChatOverlayWorkAreaSeam) { & $script:ChatOverlayWorkAreaSeam $p }
    else { [System.Windows.Forms.Screen]::FromRectangle([System.Drawing.Rectangle]::new($p[0], $p[1], $p[2], $p[3])).WorkingArea }
    # this screen's pixels to one of WPF's units: 4 of them between the two
    $px = $p[2] / [Math]::Max(1.0, [double]$H.Win.ActualWidth)
    $gap = [int][Math]::Round(4 * $px)
    # Its width and height - never its rect, whose first two numbers are
    # where it is: placed by those, it jumped between two spots each pass.
    # Its rect is behind in two cases. As the box opens or shuts, WPF says
    # the new size before the window takes it, so that size is passed in:
    # the window moves as it grows and is never over the panel. Hidden, it
    # keeps the size it last had, or WPF's default before it first shows, so
    # what its content will take instead: it never shows up somewhere else
    # first.
    if (-not $Dip -and -not $H.CtlWin.IsVisible) {
        $H.CtlStack.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $Dip = $H.CtlStack.DesiredSize
    }
    $size = if ($Dip) { @([int][Math]::Ceiling($Dip.Width * $px), [int][Math]::Ceiling($Dip.Height * $px)) } else { @($c[2], $c[3]) }
    # the row of buttons' own height: what has to fit beside the panel
    $rowDip = if (-not $H.Controls) { 0 } elseif ($H.Controls.ActualHeight -gt 0) { $H.Controls.ActualHeight } else { $H.Controls.DesiredSize.Height }
    $bar = [int][Math]::Round($rowDip * $px)
    $at = Get-ChatOverlayControlsPlacement $p $size ([pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height }) $gap $H.CtlSide $bar
    if ($at.Side -ne $H.CtlSide) { Set-ChatOverlayControlsSide $H $at.Side }
    if ($at.X -ne $c[0] -or $at.Y -ne $c[1]) { [ChatOverlayNative]::MoveTo($H.CtlHwnd, $at.X, $at.Y) }
}

function Start-ChatOverlayGripDrag {
    # A press on the grip: the panel follows the pointer until it is let go,
    # and the controls follow the panel. The pointer is only read; the
    # windows moved are the overlay's own.
    param($Grip)
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if (-not $r) { return }
    $m = [System.Windows.Forms.Control]::MousePosition
    $H.GripDrag = @{ Mx = $m.X; My = $m.Y; X = $r[0]; Y = $r[1] }
    $H.Dragging = $true
    [void]$Grip.CaptureMouse()
}

function Move-ChatOverlayGripDrag {
    $H = $script:ChatOverlayHost
    if (-not $H -or -not $H.GripDrag) { return }
    $d = $H.GripDrag
    $m = [System.Windows.Forms.Control]::MousePosition
    [ChatOverlayNative]::MoveTo($H.Hwnd, $d.X + $m.X - $d.Mx, $d.Y + $m.Y - $d.My)
    Set-ChatOverlayControlsPlacement $H
}

function Stop-ChatOverlayGripDrag {
    # let go - or the capture lost some other way: where it ended is kept
    param($Grip)
    $H = $script:ChatOverlayHost
    if (-not $H -or -not $H.GripDrag) { return }
    $H.GripDrag = $null
    $H.Dragging = $false
    if ($Grip.IsMouseCaptured) { $Grip.ReleaseMouseCapture() }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if ($r) { $H.State.x = $r[0]; $H.State.y = $r[1]; Save-ChatOverlayState $H.State }
}

function Set-ChatOverlayCollapsed {
    # one line - what is running, and usage - or the whole panel; kept for
    # the next start in overlay-state.json
    param($H, [bool]$Collapsed)
    $H.Collapsed = $Collapsed
    Set-ChatqProp $H.State 'collapsed' $Collapsed
    Save-ChatOverlayState $H.State
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
    # the chevron turns
    if ($H.CtlWin) { New-ChatOverlayControls $H }
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayOpacity {
    # as the slider moves; config.json gets it once the slider rests
    param($H, [double]$Value)
    if (-not $H) { return }
    $v = [Math]::Round([Math]::Max(0.3, [Math]::Min(1.0, $Value)), 2)
    $H.Win.Opacity = $v
    if ($H.OpacityText) { $H.OpacityText.Text = "$([int][Math]::Round($v * 100))%" }
    $H.PendingOpacity = $v
    $H.PendingAt = Get-Date
}

function Save-ChatOverlaySetting {
    # a choice made in the settings box, kept in config.json like one made
    # with chatoverlay, so the next start has it
    param($H, [hashtable]$Values)
    try {
        Set-ChatOverlayConfig $Values
        $H.Ctx.Config = Get-ChatOverlayConfig
    }
    catch { Write-ChatOverlayLog "settings: $($_.Exception.Message)" }
}

function Set-ChatOverlayThemeChoice {
    param($H, [string]$Theme)
    if (-not $H -or $H.Ctx.Config.theme -eq $Theme) { return }
    Save-ChatOverlaySetting $H @{ theme = $Theme }
    # made anew even when the look stays the same, so the choice shows
    $H.ThemeName = $null
    Update-ChatOverlayTheme $H
}

function Set-ChatOverlayUsageView {
    # lines or bars, from the settings box: kept in config.json, drawn now
    param($H, [string]$View)
    if (-not $H -or $H.Ctx.Config.usageView -eq $View) { return }
    Save-ChatOverlaySetting $H @{ usageView = $View }
    New-ChatOverlayControls $H
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
}

function Invoke-ChatOverlayRefresh {
    # the refresh button: a pass now, which sends the ask; the next pass,
    # two seconds on, draws the answer
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.Dragging) { return }
    Request-ChatOverlayUsageRefresh $H.Ctx
    $H.ViewKey = $null
    Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx -Peek)
    Update-ChatOverlaySpin $H
}

function Update-ChatOverlaySpin {
    # Every pointer check: the refresh icon turns while an ask is out, and an
    # answer that is in is drawn now - a pass would pick it up only up to 2 s
    # on, long enough for a click to look like it did nothing.
    param($H)
    $ready = { param($f) $f -and ($f.Done -or ($f.Task -and $f.Task.IsCompleted) -or ($f.Proc -and $f.Proc.HasExited)) }
    if (((& $ready $H.Ctx.Fetch) -or (& $ready $H.Ctx.CopilotFetch)) -and -not $H.Dragging) {
        Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx -Peek)
    }
    $out = [bool]($H.Ctx.Fetch -or $H.Ctx.CopilotFetch)
    if (-not $H.Spin -or $out -eq $H.Spinning) { return }
    $H.Spinning = $out
    $prop = [System.Windows.Media.RotateTransform]::AngleProperty
    if ($out) {
        $a = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 360, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(900)))
        $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $H.Spin.BeginAnimation($prop, $a)
    }
    else { $H.Spin.BeginAnimation($prop, $null) }
}

function Hide-ChatOverlayByButton {
    # the tray button hides the panel, and says once where it went
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    Invoke-ChatOverlayVerb 'hide'
    if ($H.Tray -and -not $H.HideTold) {
        $H.HideTold = $true
        $key = if ($H.Hotkey) { " or press $($H.HotkeyText)" } else { '' }
        $H.Tray.ShowBalloonTip(6000, 'chatoverlay', "Hidden. Click the tray dot$key to show it again.", [System.Windows.Forms.ToolTipIcon]::None)
    }
}

function Get-ChatOverlayControlsShown {
    <#
    Whether the buttons show, from where the pointer is. Not on first
    contact: a pointer crossing the click-through panel on its way to the
    window under it would meet buttons that take its click. It rests on the
    panel 350 ms first. Once up they stay while the pointer is on the panel
    or on them, while a mouse button is held (a slider dragged off the box),
    mid-drag, and 700 ms after it leaves, so crossing the gap between the
    two loses nothing. Pure, for the tests.
    #>
    param([bool]$Shown, [bool]$OnPanel, [bool]$OnControls, [bool]$Dragging, [bool]$Down, [double]$RestedMs, [double]$SinceOverMs)
    if ($Dragging) { return $true }
    if (-not $Shown) { return ($OnPanel -and $RestedMs -ge 350) }
    return ($OnPanel -or $OnControls -or $Down -or $SinceOverMs -lt 700)
}

function Test-ChatOverlayPointerIn {
    # a point, in screen pixels, inside a window's rect from GetRect
    param($At, $Rect)
    return [bool]($Rect -and $At.X -ge $Rect[0] -and $At.X -lt ($Rect[0] + $Rect[2]) -and $At.Y -ge $Rect[1] -and $At.Y -lt ($Rect[1] + $Rect[3]))
}

function Update-ChatOverlayHover {
    <#
    Every 120 ms: where the pointer is - read, never moved - against the
    panel and the controls window. Over either, the controls show, and stay
    a moment after it leaves, so crossing the gap between the two loses
    nothing; while a button is held they stay, so a slider dragged off the
    box keeps going. The controls follow a panel moved some other way, and
    an opacity the slider settled on is saved here too.
    #>
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.ShuttingDown -or $H.Hidden -or $H.Hwnd -eq [IntPtr]::Zero) { return }
    try {
        $m = [System.Windows.Forms.Control]::MousePosition
        $down = [System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::None
        $onPanel = Test-ChatOverlayPointerIn $m ([ChatOverlayNative]::GetRect($H.Hwnd))
        $onCtl = [bool]$H.ControlsShown -and (Test-ChatOverlayPointerIn $m ([ChatOverlayNative]::GetRect($H.CtlHwnd)))
        $now = Get-Date
        if (-not $onPanel) { $H.EnterAt = $null } elseif (-not $H.EnterAt) { $H.EnterAt = $now }
        if ($onPanel -or $onCtl) { $H.OverAt = $now }
        $rested = if ($H.EnterAt) { ($now - $H.EnterAt).TotalMilliseconds } else { 0 }
        $since = if ($H.OverAt) { ($now - $H.OverAt).TotalMilliseconds } else { [double]::MaxValue }
        $show = Get-ChatOverlayControlsShown ([bool]$H.ControlsShown) $onPanel $onCtl ([bool]$H.Dragging) $down $rested $since
        if ($show -ne [bool]$H.ControlsShown) { Show-ChatOverlayControls $H $show }
        # the grip's own drag places them as it goes; the unlocked panel's
        # DragMove does not
        elseif ($show -and -not $H.GripDrag) { Set-ChatOverlayControlsPlacement $H }
        if ($null -ne $H.PendingOpacity -and -not $down -and ($now - $H.PendingAt).TotalMilliseconds -ge 700) {
            $v = $H.PendingOpacity
            $H.PendingOpacity = $null
            if ($v -ne $H.Ctx.Config.opacity) { Save-ChatOverlaySetting $H @{ opacity = $v } }
        }
        Update-ChatOverlaySpin $H
    }
    catch { Write-ChatOverlayLog "hover: $($_.Exception.Message)" }
}

function Add-ChatOverlayUsage {
    # The bars: a row per usage window - window, a bar in the server's colour
    # for it, the percent, and a reset countdown that ticks every second -
    # and beside them the provider's name with, under it, when its figure is
    # from (Get-ChatOverlayUsageStatus): what took rows of its own under the
    # bars before.
    param($H, $Panel, $Usage)
    $ws = @($Usage.windows)
    $g = [System.Windows.Controls.Grid]::new()
    $g.Margin = [System.Windows.Thickness]::new(0, 1, 0, 3)
    foreach ($cw in 92, 62, 0, 38, 66) {
        $cd = [System.Windows.Controls.ColumnDefinition]::new()
        $cd.Width = if ($cw) { [System.Windows.GridLength]::new($cw) } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $g.ColumnDefinitions.Add($cd)
    }
    foreach ($w in $ws) { $g.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) }
    $tone = if ($Usage.stale) { 'faint' } else { 'text' }
    $who = [System.Windows.Controls.StackPanel]::new()
    [void]$who.Children.Add((New-ChatOverlayText ([string]$Usage.provider) $tone -Bold))
    if ($Usage.status) { [void]$who.Children.Add((New-ChatOverlayText ([string]$Usage.status) 'faint' 10.5 -Trim)) }
    [System.Windows.Controls.Grid]::SetRowSpan($who, [Math]::Max(1, $ws.Count))
    [void]$g.Children.Add($who)
    $row = 0
    foreach ($w in $ws) {
        $cells = @((New-ChatOverlayText $w.label 'dim' -Trim))
        $pct = [Math]::Max(0.0, [Math]::Min(100.0, [double]$w.percent))
        $bar = [System.Windows.Controls.Grid]::new()
        $bar.Height = 5
        $bar.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $bar.Margin = [System.Windows.Thickness]::new(2, 1, 8, 0)
        foreach ($share in $pct, (100 - $pct)) {
            $cd = [System.Windows.Controls.ColumnDefinition]::new()
            $cd.Width = [System.Windows.GridLength]::new($share, [System.Windows.GridUnitType]::Star)
            $bar.ColumnDefinitions.Add($cd)
        }
        $track = [System.Windows.Controls.Border]::new()
        $track.CornerRadius = [System.Windows.CornerRadius]::new(2.5)
        $track.Background = Get-ChatOverlayBrush 'track'
        [System.Windows.Controls.Grid]::SetColumnSpan($track, 2)
        $fill = [System.Windows.Controls.Border]::new()
        $fill.CornerRadius = [System.Windows.CornerRadius]::new(2.5)
        $fill.Background = Get-ChatOverlayBrush $(if ($Usage.stale) { 'faint' } else { [string]$w.severity })
        [void]$bar.Children.Add($track)
        [void]$bar.Children.Add($fill)
        $cells += $bar
        $p = New-ChatOverlayText "$($w.percent)%" $(if ($w.limited) { 'critical' } else { $tone }) -Bold
        $p.TextAlignment = [System.Windows.TextAlignment]::Right
        $cells += $p
        $r = New-ChatOverlayText (Format-ChatOverlayReset $w.resetsAt) 'dim' 11
        $r.TextAlignment = [System.Windows.TextAlignment]::Right
        $r.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $cells += $r
        if ($w.resetsAt) { $H.Clocks.Add(@{ Block = $r; At = $w.resetsAt }) }
        for ($i = 0; $i -lt $cells.Count; $i++) {
            [System.Windows.Controls.Grid]::SetColumn($cells[$i], $i + 1)
            [System.Windows.Controls.Grid]::SetRow($cells[$i], $row)
            [void]$g.Children.Add($cells[$i])
        }
        $row++
    }
    [void]$Panel.Children.Add($g)
}

function Add-ChatOverlayUsageLine {
    # Usage as one line a provider, as the collapsed panel has it: the name,
    # each window and its percent - in the server's colour for it, now there
    # is no bar to carry that - and at the end when the figure is from.
    param($Panel, $Usage)
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.LastChildFill = $true
    $line.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
    $tone = if ($Usage.stale) { 'faint' } else { 'text' }
    $name = New-ChatOverlayText ([string]$Usage.provider) $tone -Bold
    $name.Width = 56
    [System.Windows.Controls.DockPanel]::SetDock($name, [System.Windows.Controls.Dock]::Left)
    $end = New-ChatOverlayText ([string]$Usage.status) 'faint' 11
    $end.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $end.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($end, [System.Windows.Controls.Dock]::Right)
    $mid = [System.Windows.Controls.TextBlock]::new()
    $mid.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $first = $true
    foreach ($w in @($Usage.windows)) {
        if (-not $first) { $sep = [System.Windows.Documents.Run]::new(" $($script:ChatqDot) "); $sep.Foreground = Get-ChatOverlayBrush 'faint'; $mid.Inlines.Add($sep) }
        $first = $false
        $l = [System.Windows.Documents.Run]::new("$($w.label) ")
        $l.Foreground = Get-ChatOverlayBrush 'dim'
        $mid.Inlines.Add($l)
        $p = [System.Windows.Documents.Run]::new("$($w.percent)%")
        $p.FontWeight = [System.Windows.FontWeights]::SemiBold
        # normal reads as plain text; only warning and worse take a colour
        $p.Foreground = Get-ChatOverlayBrush $(if ($Usage.stale) { 'faint' } elseif ($w.limited) { 'critical' } elseif ($w.severity -in 'warning', 'critical') { [string]$w.severity } else { 'text' })
        $mid.Inlines.Add($p)
    }
    [void]$line.Children.Add($name)
    [void]$line.Children.Add($end)
    [void]$line.Children.Add($mid)
    [void]$Panel.Children.Add($line)
}

function Add-ChatOverlayRow {
    # a dot in the state's colour, project and title, what it is doing at the
    # right, and its newest prompt beneath
    param($Panel, $Row, $Cfg)
    $wrap = [System.Windows.Controls.StackPanel]::new()
    $wrap.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.LastChildFill = $true
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 8
    $dot.Height = 8
    $dot.Margin = [System.Windows.Thickness]::new(0, 1, 7, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $c = Get-ChatOverlayBrush ([string]$Row.status)
    if ($Row.status -eq 'queued') { $dot.Stroke = $c; $dot.StrokeThickness = 1.5 } else { $dot.Fill = $c }
    [System.Windows.Controls.DockPanel]::SetDock($dot, [System.Windows.Controls.Dock]::Left)
    $right = New-ChatOverlayText ([string]$Row.stateText) $(if ($Row.rank -eq 0) { 'warn' } else { 'dim' }) 11
    $right.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $right.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($right, [System.Windows.Controls.Dock]::Right)
    $main = [System.Windows.Controls.TextBlock]::new()
    $main.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    if ($Row.project) {
        $run = [System.Windows.Documents.Run]::new([string]$Row.project + '  ')
        $run.Foreground = Get-ChatOverlayBrush 'project'
        $run.FontWeight = [System.Windows.FontWeights]::SemiBold
        $main.Inlines.Add($run)
    }
    $run = [System.Windows.Documents.Run]::new([string]$Row.title)
    $run.Foreground = Get-ChatOverlayBrush 'text'
    $main.Inlines.Add($run)
    [void]$line.Children.Add($dot)
    [void]$line.Children.Add($right)
    [void]$line.Children.Add($main)
    [void]$wrap.Children.Add($line)
    if ($Cfg.prompts -and $Row.prompt) {
        $p = New-ChatOverlayText ([string]$Row.prompt) 'dim' 11 -Trim
        $p.Margin = [System.Windows.Thickness]::new(15, 1, 0, 0)
        [void]$wrap.Children.Add($p)
    }
    [void]$Panel.Children.Add($wrap)
}

function Update-ChatOverlayView {
    <#
    Redraw the panel from a snapshot, but only when what it shows changed -
    the rows carry their ages, so at least once a minute. In between, only
    the reset countdowns move.
    #>
    param($H, $Snap)
    $H.Snap = $Snap
    $key = "$($H.Ctx.ViewSig)|$($H.Locked)|$($H.Ctx.Config.width)|$($H.Ctx.Config.prompts)|$($H.Collapsed)"
    if ($key -eq $H.ViewKey) { Update-ChatOverlayClock $H; return }
    $H.ViewKey = $key
    $cfg = $H.Ctx.Config
    $P = $H.Stack
    $P.Children.Clear()
    $H.Clocks = [System.Collections.Generic.List[object]]::new()
    if ($H.Collapsed) { Add-ChatOverlayCompact $P $Snap; Add-ChatOverlayUnlockedHint $H $P; return }
    foreach ($u in @($Snap.header.usage)) {
        if (-not $u) { continue }
        if ($cfg.usageView -eq 'bars') { Add-ChatOverlayUsage $H $P $u } else { Add-ChatOverlayUsageLine $P $u }
    }
    foreach ($n in @($Snap.header.notes)) {
        if (-not $n) { continue }
        $t = New-ChatOverlayText ([string]$n.text) $(if ($n.tone -eq 'dim') { 'faint' } else { [string]$n.tone }) 11 -Trim
        $t.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$P.Children.Add($t)
    }
    $rows = @($Snap.rows)
    if (@($Snap.header.usage).Count -or @($Snap.header.notes).Count) {
        $sep = [System.Windows.Controls.Border]::new()
        $sep.Height = 1
        $sep.Background = Get-ChatOverlayBrush 'edge'
        $sep.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
        [void]$P.Children.Add($sep)
    }
    $shown = @($rows | Select-Object -First $cfg.maxRows)
    foreach ($r in $shown) { Add-ChatOverlayRow $P $r $cfg }
    if ($rows.Count -gt $shown.Count) {
        $rest = @($rows | Select-Object -Skip $shown.Count)
        $bits = @()
        $idle = @($rest | Where-Object { $_.status -eq 'idle' }).Count
        $q = @($rest | Where-Object { $_.status -eq 'queued' }).Count
        if ($idle) { $bits += "$idle idle" }
        if ($q) { $bits += "$q queued" }
        $more = "+$($rest.Count) more" + $(if ($bits) { " $($script:ChatqDot) " + ($bits -join ', ') } else { '' })
        [void]$P.Children.Add((New-ChatOverlayText $more 'faint' 11))
    }
    if (-not $rows) { [void]$P.Children.Add((New-ChatOverlayText 'no chats open' 'faint' 11)) }
    Add-ChatOverlayUnlockedHint $H $P
}

function Add-ChatOverlayUnlockedHint {
    param($H, $Panel)
    if ($H.Locked) { return }
    $keyName = if ($H.Hotkey) { $H.HotkeyText } else { 'the tray menu' }
    $hint = New-ChatOverlayText "unlocked - drag to move $($script:ChatqDot) $keyName locks it" 'unlocked' 11 -Trim
    $hint.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    [void]$Panel.Children.Add($hint)
}

function Add-ChatOverlayCompact {
    # Collapsed: one line - a dot in the most urgent chat's colour, how many
    # chats are in each state, and Claude's usage at the right.
    param($Panel, $Snap)
    $c = $Snap.counts
    $need = [int]$c.waiting + [int]$c.needsInput
    $bits = @()
    $cut = if ($c -and $c.PSObject.Properties['cutOff']) { [int]$c.cutOff } else { 0 }
    if ($need) { $bits += "$need waiting" }
    if ($cut) { $bits += "$cut cut off" }
    if ([int]$c.busy) { $bits += "$([int]$c.busy) working" }
    if ([int]$c.running) { $bits += "$([int]$c.running) running" }
    if ([int]$c.idle) { $bits += "$([int]$c.idle) idle" }
    if ([int]$c.queued) { $bits += "$([int]$c.queued) queued" }
    $state = if ($need) { 'waiting' } elseif ($cut) { 'cutoff' } elseif ([int]$c.busy) { 'busy' } elseif ([int]$c.running) { 'running' } else { 'idle' }
    $line = [System.Windows.Controls.DockPanel]::new()
    $line.LastChildFill = $true
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 8
    $dot.Height = 8
    $dot.Margin = [System.Windows.Thickness]::new(0, 1, 7, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $dot.Fill = Get-ChatOverlayBrush $state
    [System.Windows.Controls.DockPanel]::SetDock($dot, [System.Windows.Controls.Dock]::Left)
    $u = @($Snap.header.usage | Where-Object { $_ -and $_.provider -eq 'Claude' })[0]
    $use = if ($u) { (@($u.windows | Select-Object -First 2 | ForEach-Object { "$($_.label) $($_.percent)%" }) -join " $($script:ChatqDot) ") } else { '' }
    $right = New-ChatOverlayText $use $(if ($u -and $u.stale) { 'faint' } else { 'dim' }) 11
    $right.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $right.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($right, [System.Windows.Controls.Dock]::Right)
    $main = New-ChatOverlayText $(if ($bits) { $bits -join " $($script:ChatqDot) " } else { 'no chats open' }) 'text' -Trim
    [void]$line.Children.Add($dot)
    [void]$line.Children.Add($right)
    [void]$line.Children.Add($main)
    [void]$Panel.Children.Add($line)
}

function Update-ChatOverlayClock {
    param($H)
    $now = Get-Date
    foreach ($c in @($H.Clocks)) { $c.Block.Text = Format-ChatOverlayReset $c.At $now }
}

function Get-ChatOverlayPlacement {
    <#
    Where the panel goes: where it was left, as long as a 48 x 24 corner of it
    still shows on some screen - a monitor unplugged or a resolution changed
    can leave it nowhere - and otherwise the main screen's top-right corner.
    Screens are working areas in physical pixels. Pure, for the tests.
    #>
    param($X, $Y, [int]$Width, [int]$Height, [object[]]$Screens)
    if ($null -ne $X -and $null -ne $Y) {
        foreach ($s in @($Screens)) {
            $vw = [Math]::Min([int]$X + $Width, $s.X + $s.Width) - [Math]::Max([int]$X, $s.X)
            $vh = [Math]::Min([int]$Y + $Height, $s.Y + $s.Height) - [Math]::Max([int]$Y, $s.Y)
            if ($vw -ge 48 -and $vh -ge 24) { return [pscustomobject]@{ X = [int]$X; Y = [int]$Y; Moved = $false } }
        }
    }
    $p = @($Screens | Where-Object { $_.Primary })[0]
    if (-not $p) { $p = @($Screens)[0] }
    if (-not $p) { return [pscustomobject]@{ X = 0; Y = 0; Moved = $true } }
    # room above it for the row of buttons, even at 200%
    return [pscustomobject]@{ X = [int]($p.X + $p.Width - $Width - 16); Y = [int]($p.Y + 56); Moved = $true }
}

function Set-ChatOverlayPlacement {
    param($H, [switch]$Corner)
    if ($H.Hwnd -eq [IntPtr]::Zero) { return }
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    $wide = if ($r) { $r[2] } else { 380 }
    $tall = if ($r) { [Math]::Max($r[3], 24) } else { 120 }
    $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
            $a = $_.WorkingArea
            [pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height; Primary = $_.Primary }
        })
    $x = if ($Corner) { $null } else { $H.State.x }
    $y = if ($Corner) { $null } else { $H.State.y }
    $p = Get-ChatOverlayPlacement $x $y $wide $tall $screens
    if ($p.Moved -and $null -ne $x) { Write-ChatOverlayLog "moved back onto a screen from $x,$y" }
    [ChatOverlayNative]::MoveTo($H.Hwnd, $p.X, $p.Y)
    $H.Placed = $true
    if ($p.X -ne $H.State.x -or $p.Y -ne $H.State.y) {
        $H.State.x = $p.X
        $H.State.y = $p.Y
        Save-ChatOverlayState $H.State
    }
}

function Invoke-ChatOverlayDrag {
    # Unlocked, a press anywhere on the panel drags it (the grip has its own,
    # Start-ChatOverlayGripDrag). Passes wait meanwhile: DragMove runs its
    # own message loop, and the timer would fire inside it.
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.Locked) { return }
    $H.Dragging = $true
    try { $H.Win.DragMove() } catch {}
    $H.Dragging = $false
    $r = [ChatOverlayNative]::GetRect($H.Hwnd)
    if ($r) { $H.State.x = $r[0]; $H.State.y = $r[1]; Save-ChatOverlayState $H.State }
}

function Set-ChatOverlayLocked {
    # Locked: clicks go through to whatever is under it. Unlocked: it takes the
    # mouse so it can be dragged, shows a blue edge, and locks itself again
    # 2 minutes after the pointer leaves - a forgotten unlock would otherwise
    # go on swallowing clicks over that corner of the screen.
    param($H, [bool]$Locked)
    $H.Locked = $Locked
    if ($H.Hwnd -ne [IntPtr]::Zero) { [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $Locked) }
    $H.Frame.BorderBrush = Get-ChatOverlayBrush $(if ($Locked) { 'edge' } else { 'unlocked' })
    $H.PointerIn = $false
    $H.LeftAt = if ($Locked) { $null } else { Get-Date }
    $H.State.locked = $Locked
    Save-ChatOverlayState $H.State
    $H.ViewKey = $null
    if ($H.Snap) { Update-ChatOverlayView $H $H.Snap }
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayHidden {
    param($H, [bool]$Hidden)
    $H.Hidden = $Hidden
    if ($Hidden) {
        $H.Win.Hide()
        Show-ChatOverlayControls $H $false
    }
    else {
        $H.Win.Show()
        [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
        # one that started hidden still sits where it was made, off every screen
        if (-not $H.Placed) { Set-ChatOverlayPlacement $H }
        [ChatOverlayNative]::KeepTopmost($H.Hwnd)
    }
    $H.State.hidden = $Hidden
    Save-ChatOverlayState $H.State
    Update-ChatOverlayMenu $H
}

function Set-ChatOverlayTrayColor {
    # the tray dot takes the most urgent state's colour; the old icon handle
    # is destroyed, or every change would leak one
    param($H, [string]$Hex)
    if (-not $H.Tray -or $H.IconColor -eq $Hex) { return }
    $bmp = [System.Drawing.Bitmap]::new(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $br = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($Hex))
    $g.FillEllipse($br, 5, 5, 22, 22)
    $br.Dispose()
    $g.Dispose()
    $icon = $bmp.GetHicon()
    $bmp.Dispose()
    $H.Tray.Icon = [System.Drawing.Icon]::FromHandle($icon)
    if ($H.IconHandle -ne [IntPtr]::Zero) { [void][ChatOverlayNative]::DestroyIcon($H.IconHandle) }
    $H.IconHandle = $icon
    $H.IconColor = $Hex
}

function Update-ChatOverlayTray {
    param($H, $Snap)
    if (-not $H.Tray) { return }
    $c = $Snap.counts
    $cut = if ($c -and $c.PSObject.Properties['cutOff']) { [int]$c.cutOff } else { 0 }
    $name = if ([int]$c.waiting + [int]$c.needsInput) { 'waiting' } elseif ($cut) { 'cutoff' } elseif ($c.busy) { 'busy' } elseif ($c.running) { 'running' } else { 'idle' }
    Set-ChatOverlayTrayColor $H $script:ChatOverlayColors[$name]
    $tip = Format-ChatOverlayTooltip $Snap
    if ($H.Tray.Text -ne $tip) { $H.Tray.Text = $tip }
}

function Update-ChatOverlayMenu {
    param($H)
    if (-not $H.Menu.Lock) { return }
    $H.Menu.Lock.Text = if ($H.Locked) { 'Unlock to move' } else { 'Lock' }
    $H.Menu.Hide.Text = if ($H.Hidden) { 'Show' } else { 'Hide' }
    $H.Menu.Fold.Text = if ($H.Collapsed) { 'Expand' } else { 'Collapse to one line' }
    $H.Menu.Hotkey.Text = if ($H.Hotkey) { "hotkey  $($H.HotkeyText)" } elseif ($H.HotkeyText -and $H.HotkeyText -ne 'none') { "hotkey  $($H.HotkeyText) (taken)" } else { 'no hotkey' }
}

function New-ChatOverlayTrayIcon {
    # A dot in the notification area: left click shows or hides the panel,
    # right click has the rest. It is the one way to reach a panel that clicks
    # go through.
    param($H)
    $ni = [System.Windows.Forms.NotifyIcon]::new()
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $open = $menu.Items.Add('Open console')
    $open.Font = [System.Drawing.Font]::new($open.Font, [System.Drawing.FontStyle]::Bold)
    $open.add_Click({ Invoke-ChatOverlayVerb 'console' })
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $head = $menu.Items.Add("VS-code-chat-manager $script:ChatVersion")
    $head.Enabled = $false
    $H.Menu.Hotkey = $menu.Items.Add('hotkey')
    $H.Menu.Hotkey.Enabled = $false
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $H.Menu.Lock = $menu.Items.Add('Unlock to move')
    $H.Menu.Lock.add_Click({ Invoke-ChatOverlayVerb 'toggle' })
    $H.Menu.Hide = $menu.Items.Add('Hide')
    $H.Menu.Hide.add_Click({ Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Hidden) { 'show' } else { 'hide' }) })
    $H.Menu.Fold = $menu.Items.Add('Collapse to one line')
    $H.Menu.Fold.add_Click({ Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Collapsed) { 'expand' } else { 'collapse' }) })
    $again = $menu.Items.Add('Refresh usage')
    $again.add_Click({ Invoke-ChatOverlayRefresh })
    $corner = $menu.Items.Add('Move to top right')
    $corner.add_Click({ Invoke-ChatOverlayVerb 'reset' })
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $quit = $menu.Items.Add('Quit')
    $quit.add_Click({ Invoke-ChatOverlayVerb 'stop' })
    $ni.ContextMenuStrip = $menu
    $ni.add_MouseClick({
            param($s, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                Invoke-ChatOverlayVerb $(if ($script:ChatOverlayHost.Hidden) { 'show' } else { 'hide' })
            }
        })
    $ni.Text = 'chatq'
    $H.Tray = $ni
    Set-ChatOverlayTrayColor $H $script:ChatOverlayColors.idle
    $ni.Visible = $true
    Update-ChatOverlayMenu $H
}

function Register-ChatOverlayHotkey {
    # config hotkey (Ctrl+Alt+Shift+O): shows a hidden panel, else locks or
    # unlocks it. Another program holding the same keys gets one balloon.
    param($H)
    $text = [string]$H.Ctx.Config.hotkey
    if ($H.Hotkey -and $H.HotkeyText -eq $text) { return }
    if ($H.Hotkey) { $H.Hotkey.Dispose(); $H.Hotkey = $null }
    $H.HotkeyText = $text
    $k = try { ConvertFrom-ChatOverlayHotkey $text } catch { Write-ChatOverlayLog "hotkey: $($_.Exception.Message)"; $null }
    if ($k) {
        $hk = [ChatOverlayHotkey]::new()
        $hk.add_Pressed({ Invoke-ChatOverlayVerb 'hotkey' })
        if ($hk.Register([uint32]$k.Mods, [uint32]$k.Vk)) { $H.Hotkey = $hk }
        else {
            $hk.Dispose()
            Write-ChatOverlayLog "hotkey $text is taken by another program"
            if ($H.Tray) { $H.Tray.ShowBalloonTip(8000, 'chatoverlay', "$text is taken by another program - chatoverlay -Hotkey picks another", [System.Windows.Forms.ToolTipIcon]::Info) }
        }
    }
    Update-ChatOverlayMenu $H
}

function Invoke-ChatOverlayVerb {
    # what a command, the tray menu or the hotkey asked for
    param([string]$Verb)
    $H = $script:ChatOverlayHost
    if (-not $H) { return }
    switch ($Verb) {
        'stop' { $H.Stop = $true; Stop-ChatOverlayDispatcher $H }
        'restart' { $H.Restart = $true; Stop-ChatOverlayDispatcher $H }
        'reload' {
            $H.Ctx.Config = Get-ChatOverlayConfig
            $H.Win.Width = $H.Ctx.Config.width
            $H.Win.Opacity = $H.Ctx.Config.opacity
            Register-ChatOverlayHotkey $H
            Register-ChatConsoleHotkey $H
            $H.ViewKey = $null
            # made anew, so the settings box shows what a shell just set
            $H.ThemeName = $null
            Update-ChatOverlayTheme $H
        }
        'lock' { Set-ChatOverlayLocked $H $true }
        'unlock' { Set-ChatOverlayLocked $H $false }
        'toggle' { Set-ChatOverlayLocked $H (-not $H.Locked) }
        'show' { if ($H.Hidden) { Set-ChatOverlayHidden $H $false } }
        'hide' { if (-not $H.Hidden) { Set-ChatOverlayHidden $H $true } }
        'reset' { Set-ChatOverlayPlacement $H -Corner }
        'hotkey' { if ($H.Hidden) { Set-ChatOverlayHidden $H $false } else { Set-ChatOverlayLocked $H (-not $H.Locked) } }
        'collapse' { if (-not $H.Collapsed) { Set-ChatOverlayCollapsed $H $true } }
        'expand' { if ($H.Collapsed) { Set-ChatOverlayCollapsed $H $false } }
        'console' { Show-ChatConsole $H -Activate }
    }
}

function Stop-ChatOverlayDispatcher {
    param($H)
    if ($H.ShuttingDown) { return }
    $H.ShuttingDown = $true
    if ($H.Timer) { $H.Timer.Stop() }
    if ($H.HoverTimer) { $H.HoverTimer.Stop() }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Background)
}

function Invoke-ChatOverlayTick {
    # The 1 s timer. Every other tick is a collector pass; the ones between
    # only move the countdowns. Every 5th puts the panel back on top and moves
    # it back onto a screen if the screens changed under it.
    $H = $script:ChatOverlayHost
    if (-not $H -or $H.ShuttingDown) { return }
    try {
        $H.Tick++
        # a key just pressed in the console puts the pass off a tick - twice
        # at most - so typing there never waits behind one
        $C = $H.Con
        $typing = $C -and $C.TypedAt -and ((Get-Date) - $C.TypedAt).TotalMilliseconds -lt 400 -and $C.Skips -lt 2
        if ($H.Tick % 2 -eq 0 -and $typing) { $C.Skips++; $H.Tick-- }
        elseif ($H.Tick % 2 -eq 0 -and -not $H.Dragging) {
            if ($C) { $C.Skips = 0 }
            $snap = Invoke-ChatOverlayCycle $H.Ctx
            foreach ($v in @($H.Ctx.Verbs)) { Invoke-ChatOverlayVerb $v }
            if ($H.ShuttingDown) { return }
            Update-ChatOverlayView $H $snap
            Update-ChatOverlayTray $H $snap
            if ($C -and $C.Win.IsVisible) { Update-ChatConsole $H }
        }
        else {
            Update-ChatOverlayClock $H
            # a dropped file's copy may have finished
            if ($C -and $C.Win.IsVisible) { Update-ChatConsoleStaging $H }
        }
        if ($H.Tick % 5 -eq 0 -and -not $H.Hidden) {
            # system: follows Windows' own light or dark setting
            if ($H.Ctx.Config.theme -eq 'system') { Update-ChatOverlayTheme $H }
            [ChatOverlayNative]::KeepTopmost($H.Hwnd)
            if ($H.ControlsShown) { [ChatOverlayNative]::KeepTopmost($H.CtlHwnd) }
            $sig = (@([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.WorkingArea)" }) -join ';')
            if ($sig -ne $H.ScreenSig) {
                if ($H.ScreenSig) { Set-ChatOverlayPlacement $H }
                $H.ScreenSig = $sig
            }
        }
        if (-not $H.Locked -and -not $H.PointerIn -and $H.LeftAt -and ((Get-Date) - $H.LeftAt).TotalSeconds -ge 120) {
            Set-ChatOverlayLocked $H $true
        }
    }
    catch { Write-ChatOverlayLog "tick: $($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])" }
}

function Lock-ChatOverlay {
    # A few tries, not one: an overlay handing over to a newer copy lets go
    # of the lock only as it exits.
    for ($try = 1; $try -le 5; $try++) {
        $l = try { [System.IO.File]::Open($script:ChatOverlayLockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { $null }
        if ($l) { return $l }
        if ($try -lt 5) { Start-Sleep -Milliseconds 200 }
    }
    return $null
}

function Close-ChatOverlayWindow {
    # everything the panel holds from the OS goes back, whatever ended it
    param($H)
    try { if ($H.Timer) { $H.Timer.Stop() } } catch {}
    try { if ($H.HoverTimer) { $H.HoverTimer.Stop() } } catch {}
    try { if ($H.Hotkey) { $H.Hotkey.Dispose(); $H.Hotkey = $null } } catch {}
    try { if ($H.ConHotkey) { $H.ConHotkey.Dispose(); $H.ConHotkey = $null } } catch {}
    # the console's draft kept, then the window closed for good
    $H.ShuttingDown = $true
    try { if ($H.Con) { Save-ChatConsoleDraft $H; $H.Con.Win.Close() } } catch {}
    try { if ($H.Tray) { $H.Tray.Visible = $false; $H.Tray.Dispose(); $H.Tray = $null } } catch {}
    try { if ($H.IconHandle -ne [IntPtr]::Zero) { [void][ChatOverlayNative]::DestroyIcon($H.IconHandle); $H.IconHandle = [IntPtr]::Zero } } catch {}
    try { if ($H.CtlWin) { $H.CtlWin.Close() } } catch {}
    try { if ($H.Win) { $H.Win.Close() } } catch {}
}

function New-ChatOverlayHostState {
    @{
        Tick = 0; Ctx = $null; Win = $null; Hwnd = [IntPtr]::Zero; Frame = $null; Stack = $null
        State = $null; Locked = $true; Hidden = $false; Collapsed = $false; Dragging = $false; PointerIn = $false; LeftAt = $null
        CtlWin = $null; CtlHwnd = [IntPtr]::Zero; CtlStack = $null; CtlSide = 'above'; CtlButtons = @(); CtlLine = $null; GripDrag = $null; Spin = $null; Spinning = $false
        Placed = $false; EnterAt = $null
        Controls = $null; Settings = $null; ControlsShown = $false; SettingsOpen = $false; OverAt = $null
        HoverTimer = $null; PendingOpacity = $null; PendingAt = $null; OpacityText = $null; ThemeName = $null; HideTold = $false
        Tray = $null; IconHandle = [IntPtr]::Zero; IconColor = $null; Hotkey = $null; HotkeyText = $null
        Timer = $null; ViewKey = $null; Clocks = [System.Collections.Generic.List[object]]::new(); Snap = $null
        ScreenSig = $null; Stop = $false; Restart = $false; ShuttingDown = $false; Menu = @{}
        Con = $null; ConHotkey = $null; ConHotkeyText = $null
    }
}

function Start-ChatOverlayHost {
    <#
    The Windows overlay process: a hidden powershell.exe -STA that draws the
    panel and runs the collector on the same thread, every other tick of a
    1 s timer. One thread is enough - a pass costs tens of milliseconds, and
    nobody clicks a window that clicks go through - and it keeps every
    handler on the thread PowerShell runs on, the only one with a runspace.
    -Open console: chatconsole started it, and the console opens with it.
    #>
    param([string]$Open)
    Set-StrictMode -Off
    if (-not $script:ChatqIsWindows) { Start-ChatOverlayMacHost; return }
    New-ChatqDir $script:ChatqData
    $lock = Lock-ChatOverlay
    if (-not $lock) { Write-ChatOverlayLog "overlay $PID found one already running"; return }
    $H = New-ChatOverlayHostState
    $script:ChatOverlayHost = $H
    try {
        Set-Content -LiteralPath $script:ChatOverlayPidPath -Value $PID -Encoding ASCII
        Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID started ($script:ChatVersion)"
        Initialize-ChatOverlayNative
        $H.Ctx = New-ChatOverlayContext
        Restore-ChatOverlayUsage $H.Ctx
        $H.State = Read-ChatOverlayState
        $H.Locked = [bool]$H.State.locked
        $H.Collapsed = [bool]$H.State.collapsed
        New-ChatOverlayWindow $H
        Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx)
        if (-not $H.State.hidden) {
            $H.Win.Show()
            [ChatOverlayNative]::ApplyExStyle($H.Hwnd, $H.Locked)
            Set-ChatOverlayPlacement $H
            [ChatOverlayNative]::KeepTopmost($H.Hwnd)
        }
        else { $H.Hidden = $true }
        if (-not $H.Locked) { Set-ChatOverlayLocked $H $false }
        New-ChatOverlayTrayIcon $H
        Update-ChatOverlayTray $H $H.Snap
        Register-ChatOverlayHotkey $H
        Register-ChatConsoleHotkey $H
        $d = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $d.add_UnhandledException({
                param($s, $e)
                Write-ChatOverlayLog "ui: $($e.Exception.Message)"
                $e.Handled = $true
            })
        $H.Timer = [System.Windows.Threading.DispatcherTimer]::new()
        $H.Timer.Interval = [TimeSpan]::FromSeconds(1)
        $H.Timer.add_Tick({ Invoke-ChatOverlayTick })
        $H.Timer.Start()
        $H.HoverTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $H.HoverTimer.Interval = [TimeSpan]::FromMilliseconds(120)
        $H.HoverTimer.add_Tick({ Update-ChatOverlayHover })
        $H.HoverTimer.Start()
        # what came in while this was starting - a -Stop right after the start,
        # chatinstall's restart - was taken by the first pass above
        foreach ($v in @($H.Ctx.Verbs)) { Invoke-ChatOverlayVerb $v }
        if ($Open -eq 'console') { Show-ChatConsole $H -Activate }
        [System.Windows.Threading.Dispatcher]::Run()
    }
    catch { Write-ChatOverlayLog "overlay failed: $($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])" }
    finally {
        Close-ChatOverlayWindow $H
        try { $lock.Dispose() } catch {}
        Remove-Item -LiteralPath $script:ChatOverlayPidPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID stopped$(if ($H.Restart) { ' - restarting on the new copy' })"
    }
    # last, once the lock is released: the new copy takes it on its way up
    if ($H.Restart) { [void](Start-ChatOverlayProcess) }
}

#endregion

#region console: chatq in a window ---------------------------------------------
# Pick a chat - one open in VS Code, one the limit cut off, a recent one, or a
# new one in a folder - write to it, drop or paste files on it, and send it
# now or queue it; the queue beside it, with each job's outcome and log. A
# normal window that takes focus, in the overlay's own process and on its
# thread, drawn from the snapshot the collector makes every 2 s. Only the
# user ever opens it: the button on the overlay's bar, the tray, the console
# hotkey, or chatconsole. Windows only, like the panel's buttons.

$script:ChatConsoleStatePath = Join-Path $script:ChatqData 'console-state.json'
$script:ChatConsoleDraftDir = Join-Path (Join-Path $script:ChatqData 'console') 'draft'
# tests: what a paste finds on the clipboard; no index sync in a child
$script:ChatConsoleClipboardSeam = $null
$script:ChatConsoleNoSync = $false
$script:ChatConsoleModes = @('default', 'acceptEdits', 'auto', 'plan', 'bypassPermissions')
$script:ChatConsoleModels = @('opus', 'sonnet', 'haiku')

function ConvertFrom-ChatConsoleWhen {
    <#
    The When choice to what a job holds. now: the front of the queue, and a
    chat busy in VS Code looked at every 30 s. turn: behind what is queued.
    at / in: -Value, as chatq -At 13:00 or -In 2h reads it. Pure.
    #>
    param([string]$When, [string]$Value)
    $ok = { param($nb, $first, $now) [pscustomobject]@{ Error = $null; NotBefore = $nb; First = $first; SendNow = $now } }
    switch ($When) {
        'now' { return & $ok $null $true $true }
        'turn' { return & $ok $null $false $false }
    }
    $v = ([string]$Value).Trim()
    $example = if ($When -eq 'at') { '13:00' } else { '90m, 2h or 1d' }
    if (-not $v) { return [pscustomobject]@{ Error = "give a time - $example"; NotBefore = $null; First = $false; SendNow = $false } }
    $t = try { if ($When -eq 'at') { ConvertFrom-ChatqWhen -At $v } else { ConvertFrom-ChatqWhen -In $v } } catch { $null }
    if (-not $t) { return [pscustomobject]@{ Error = "'$v' is not a time - $example"; NotBefore = $null; First = $false; SendNow = $false } }
    return & $ok $t $false $false
}

function Select-ChatConsoleChats {
    # every word typed, anywhere in the title or the project, in any case
    param([object[]]$Chats, [string]$Search, [int]$Max = 0)
    $words = @(([string]$Search).ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    $out = @(foreach ($c in @($Chats)) {
            if (-not $c) { continue }
            $hay = "$($c.Title) $($c.Project)".ToLowerInvariant()
            $all = $true
            foreach ($w in $words) { if (-not $hay.Contains($w)) { $all = $false; break } }
            if ($all) { $c }
        })
    if ($Max -gt 0) { $out = @($out | Select-Object -First $Max) }
    return $out
}

function Get-ChatConsoleSendPreview {
    <#
    What Send will do, said before it is pressed. -Target: @{ Kind = chat |
    new; Live = busy | waiting | idle, or $null when no window has it }.
    -Plan: ConvertFrom-ChatConsoleWhen's answer. -Block: its provider's
    limit, @{ Until; Type }. -Ahead: jobs queued in front of it. Pure.
    #>
    param($Target, $Plan, $Block, [int]$Ahead, [bool]$Watcher, [datetime]$Now = (Get-Date))
    if (-not $Target) { return 'pick a chat on the left, or + New chat' }
    if ($Plan.Error) { return $Plan.Error }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $bits = @()
    if ($Plan.NotBefore) { $bits += "sends $(Format-ChatOverlayWhen ([datetime]$Plan.NotBefore) $Now) at the earliest" }
    elseif ($Block -and $Block.Type -eq 'overloaded') { $bits += 'Claude is overloaded - sends once status.claude.com has it back' }
    # a refused login and a probe that failed hold the queue too, but no limit
    # is over at their time - the watcher only looks again then
    elseif ($Block -and $Block.Type -eq 'login needed') {
        $said = if ($Block.PSObject.Properties['Why'] -and $Block.Why -and $Block.Why -notin 'probe', 'run') { [string]$Block.Why } else { 'login refused' }
        $bits += "$said - log in or check the subscription; sends once the login works again, looked at every 15 min"
    }
    elseif ($Block -and $Block.Type -eq 'probe failed' -and $Block.Until) { $bits += "the limit could not be checked - looked at again $($Block.Until.ToString('HH:mm', $inv))" }
    elseif ($Block -and $Block.Until -and $Block.Until -gt $Now) { $bits += "limited until $($Block.Until.ToString('HH:mm', $inv)) - sends $($Block.Until.AddMinutes(1).ToString('HH:mm', $inv))" }
    elseif (-not $Plan.First -and $Ahead -gt 0) { $bits += "after the $Ahead queued ahead of it" }
    else { $bits += 'sends within a few seconds' }
    if ($Target.Kind -eq 'new') { $bits += 'a new chat - a VS Code window on that folder is offered a reload to pick it up' }
    elseif ($Target.Live -in 'busy', 'waiting') { $bits += "that chat is working in VS Code - it goes once the chat is idle$(if ($Plan.SendNow) { ', looked at every 30 s' })" }
    elseif ($Target.Live -eq 'idle' -or $Target.Live -eq 'cutoff') { $bits += 'open in VS Code - reload that window to see the reply' }
    if (-not $Watcher) { $bits += 'the watcher starts for it' }
    return ($bits -join ' - ')
}

function Get-ChatConsoleJobStatus {
    # a job's words at the right of the console's queue, and their colour
    param($Job, [string]$Eta, [datetime]$Now = (Get-Date))
    $at = { param($s) $d = ConvertTo-ChatqDate $s; if ($d) { Format-ChatOverlayWhen $d $Now } else { '' } }
    $why = if ($Job.result -and $Job.result.reason) { " - $($Job.result.reason)" } else { '' }
    switch ([string]$Job.state) {
        'queued' {
            $t = if (-not $Eta) { 'queued' } elseif ($Eta -match '^(\d|[A-Z][a-z]{2} \d)') { "sends $Eta" } else { $Eta }
            return [pscustomobject]@{ Text = $t; Tone = 'queued' }
        }
        'running' { return [pscustomobject]@{ Text = "running since $(& $at $Job.startedAt)"; Tone = 'running' } }
        'needs-input' { return [pscustomobject]@{ Text = "needs you$why"; Tone = 'waiting' } }
        'done' { return [pscustomobject]@{ Text = "done $(& $at $Job.endedAt)"; Tone = 'busy' } }
        'failed' { return [pscustomobject]@{ Text = "failed$why"; Tone = 'error' } }
        'skipped' { return [pscustomobject]@{ Text = "skipped$why"; Tone = 'faint' } }
    }
    return [pscustomobject]@{ Text = [string]$Job.state; Tone = 'dim' }
}

function Get-ChatConsolePlacement {
    # Where the console opens, in screen pixels: where it was left, while
    # 120 x 60 of it is on some screen, else the middle of the main one. Pure.
    param($Saved, [object[]]$Screens, [double]$Width = 980, [double]$Height = 680)
    if ($Saved -and $null -ne $Saved.x -and [double]$Saved.w -ge 400 -and [double]$Saved.h -ge 300) {
        foreach ($s in @($Screens)) {
            $vw = [Math]::Min([double]$Saved.x + [double]$Saved.w, $s.X + $s.Width) - [Math]::Max([double]$Saved.x, $s.X)
            $vh = [Math]::Min([double]$Saved.y + [double]$Saved.h, $s.Y + $s.Height) - [Math]::Max([double]$Saved.y, $s.Y)
            if ($vw -ge 120 -and $vh -ge 60) { return [pscustomobject]@{ X = [double]$Saved.x; Y = [double]$Saved.y; W = [double]$Saved.w; H = [double]$Saved.h } }
        }
    }
    $p = @($Screens | Where-Object { $_.Primary })[0]
    if (-not $p) { $p = @($Screens)[0] }
    if (-not $p) { return [pscustomobject]@{ X = 40; Y = 40; W = $Width; H = $Height } }
    $w = [Math]::Min($Width, $p.Width - 40)
    $h = [Math]::Min($Height, $p.Height - 40)
    return [pscustomobject]@{ X = $p.X + ($p.Width - $w) / 2; Y = $p.Y + ($p.Height - $h) / 2; W = $w; H = $h }
}

function Read-ChatConsoleState {
    # console-state.json: where it was, and the draft - what was being
    # written, to which chat, with which files - so a restart keeps it
    $s = Read-ChatqJson $script:ChatConsoleStatePath
    if (-not $s) { $s = [pscustomobject]@{} }
    foreach ($k in 'x', 'y', 'w', 'h', 'draft') { if (-not $s.PSObject.Properties[$k]) { Set-ChatqProp $s $k $null } }
    foreach ($k in @(@('max', $false), @('left', 300), @('queue', 230))) { if (-not $s.PSObject.Properties[$k[0]]) { Set-ChatqProp $s $k[0] $k[1] } }
    if (-not $s.PSObject.Properties['folders']) { Set-ChatqProp $s 'folders' @() }
    return $s
}

function New-ChatConsoleButton {
    # a flat button, drawn as a border: WPF's own Button brings the system's
    # light look into a dark console
    param([string]$Text, [scriptblock]$OnClick, [switch]$Accent, [string]$Tip, $Tag, [switch]$Small)
    $b = [System.Windows.Controls.Border]::new()
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $b.Padding = if ($Small) { [System.Windows.Thickness]::new(7, 1, 7, 2) } else { [System.Windows.Thickness]::new(11, 3, 11, 4) }
    $b.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Background = if ($Accent) { Get-ChatOverlayBrush 'accent' } else { [System.Windows.Media.Brushes]::Transparent }
    $b.BorderBrush = Get-ChatOverlayBrush $(if ($Accent) { 'accent' } else { 'inputEdge' })
    $b.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $b.Child = New-ChatOverlayText $Text $(if ($Accent) { 'onAccent' } else { 'text' }) $(if ($Small) { 11 } else { 12 })
    if ($Tip) { $b.ToolTip = $Tip }
    $b.Tag = $Tag
    if (-not $Accent) {
        $b.add_MouseEnter({ param($s, $e) $s.Background = Get-ChatOverlayBrush 'hover' })
        $b.add_MouseLeave({ param($s, $e) $s.Background = [System.Windows.Media.Brushes]::Transparent })
    }
    if ($OnClick) { $b.add_MouseLeftButtonUp($OnClick) }
    return $b
}

function New-ChatConsoleInput {
    param([switch]$Multi, [string]$Tip)
    $t = [System.Windows.Controls.TextBox]::new()
    $t.Background = Get-ChatOverlayBrush 'input'
    $t.Foreground = Get-ChatOverlayBrush 'text'
    $t.BorderBrush = Get-ChatOverlayBrush 'inputEdge'
    $t.CaretBrush = Get-ChatOverlayBrush 'text'
    $t.SelectionBrush = Get-ChatOverlayBrush 'accent'
    $t.Padding = [System.Windows.Thickness]::new(6, 4, 6, 4)
    $t.FontSize = 12.5
    if ($Tip) { $t.ToolTip = $Tip }
    if ($Multi) {
        $t.AcceptsReturn = $true
        $t.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $t.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $t.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Top
    }
    return $t
}

function New-ChatConsoleChips {
    # a row of choices, the one in force filled; a click hands the chip to
    # -OnClick, whose Tag is its value
    param([string[]]$Values, [string[]]$Labels, [string]$Current, [scriptblock]$OnClick)
    $row = [System.Windows.Controls.WrapPanel]::new()
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $on = $Values[$i] -eq $Current
        $c = [System.Windows.Controls.Border]::new()
        $c.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $c.BorderThickness = [System.Windows.Thickness]::new(1)
        $c.Padding = [System.Windows.Thickness]::new(8, 1, 8, 2)
        $c.Margin = [System.Windows.Thickness]::new(0, 2, 4, 2)
        $c.Background = if ($on) { Get-ChatOverlayBrush 'accent' } else { [System.Windows.Media.Brushes]::Transparent }
        $c.BorderBrush = Get-ChatOverlayBrush $(if ($on) { 'accent' } else { 'inputEdge' })
        $c.Cursor = [System.Windows.Input.Cursors]::Hand
        $c.Tag = $Values[$i]
        $c.Child = New-ChatOverlayText $Labels[$i] $(if ($on) { 'onAccent' } else { 'text' }) 11.5
        $c.add_MouseLeftButtonUp($OnClick)
        [void]$row.Children.Add($c)
    }
    return $row
}

function New-ChatConsoleWindow {
    <#
    The window, made once, the first time it is opened; hidden, never closed,
    until the overlay stops - closing it keeps the draft. Its content is
    built by Initialize-ChatConsoleContent, again when the theme changes.
    #>
    param($H)
    $C = @{
        # Sigs, not Keys: $C.Keys is the hashtable's own list of its keys
        Win = $null; Hwnd = [IntPtr]::Zero; State = (Read-ChatConsoleState); Sigs = @{}; Target = $null
        Staged = [System.Collections.Generic.List[object]]::new(); When = 'now'; WhenValue = ''; Mode = ''; Model = ''
        Text = ''; NewCwd = ''; NewName = ''; Search = ''; Sel = $null; ShowLog = $false; Jobs = @(); JobsSig = $null
        Index = @(); IndexStamp = $null; IndexParsed = $false; IndexRead = $null; Sync = $null; SyncAt = [datetime]::MinValue; Info = @{}
        Request = $null; WatchSays = ''; TypedAt = $null; Skips = 0; Dirty = $null; Modal = $false; Confirm = @{}; Blocks = $null; BlocksAt = [datetime]::MinValue
    }
    $H.Con = $C
    $w = [System.Windows.Window]::new()
    $w.Title = 'chatq console'
    $w.Width = 980
    $w.Height = 680
    $w.MinWidth = 640
    $w.MinHeight = 420
    $w.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $w.Left = -32000
    $w.Top = -32000
    $w.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $w.FontSize = 12.5
    $w.ShowInTaskbar = $true
    $w.add_Closing({
            param($s, $e)
            $H = $script:ChatOverlayHost
            if ($H -and -not $H.ShuttingDown) { $e.Cancel = $true; Hide-ChatConsole $H }
        })
    # a key pressed here holds off the next collector pass a moment, so
    # typing never stutters behind one
    $w.add_PreviewKeyDown({ $H = $script:ChatOverlayHost; if ($H.Con) { $H.Con.TypedAt = Get-Date } })
    $C.Win = $w
    $C.Hwnd = [System.Windows.Interop.WindowInteropHelper]::new($w).EnsureHandle()
    Restore-ChatConsoleDraft $H
    Initialize-ChatConsoleContent $H
}

function Initialize-ChatConsoleContent {
    # everything in the window, from scratch - a theme change comes through
    # here too - keeping what is typed
    param($H)
    $C = $H.Con
    if ($C.Prompt) { $C.Text = $C.Prompt.Text }
    if ($C.FolderBox) { $C.NewCwd = $C.FolderBox.Text }
    if ($C.NameBox) { $C.NewName = $C.NameBox.Text }
    if ($C.WhenBox) { $C.WhenValue = $C.WhenBox.Text }
    $w = $C.Win
    $w.Background = Get-ChatOverlayBrush 'window'
    $w.Foreground = Get-ChatOverlayBrush 'text'
    $gl = { param($v) if ($v -gt 0) { [System.Windows.GridLength]::new($v) } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) } }
    $root = [System.Windows.Controls.Grid]::new()
    foreach ($r in 'auto', 'star', 'auto') {
        $rd = [System.Windows.Controls.RowDefinition]::new()
        $rd.Height = if ($r -eq 'auto') { [System.Windows.GridLength]::Auto } else { & $gl 0 }
        $root.RowDefinitions.Add($rd)
    }
    $C.Header = New-ChatOverlayText '' 'dim' 12 -Trim
    $C.Header.Margin = [System.Windows.Thickness]::new(12, 8, 12, 8)
    [void]$root.Children.Add($C.Header)

    $body = [System.Windows.Controls.Grid]::new()
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    foreach ($cw in [Math]::Max(200, [double]$C.State.left), 6, 0) { $cd = [System.Windows.Controls.ColumnDefinition]::new(); $cd.Width = & $gl $cw; $body.ColumnDefinitions.Add($cd) }
    $body.ColumnDefinitions[0].MinWidth = 200
    $C.LeftCol = $body.ColumnDefinitions[0]
    [void]$root.Children.Add($body)

    # left: search, + New chat, and the chats
    $left = [System.Windows.Controls.DockPanel]::new()
    $left.Margin = [System.Windows.Thickness]::new(10, 0, 0, 8)
    $top = [System.Windows.Controls.DockPanel]::new()
    $top.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    [System.Windows.Controls.DockPanel]::SetDock($top, [System.Windows.Controls.Dock]::Top)
    $newB = New-ChatConsoleButton '+ New chat' { Select-ChatConsoleNew $script:ChatOverlayHost } -Tip 'Start a new Claude chat in a folder'
    $newB.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($newB, [System.Windows.Controls.Dock]::Right)
    [void]$top.Children.Add($newB)
    $C.SearchBox = New-ChatConsoleInput -Tip 'Search chats: every word, in the title or the project'
    $C.SearchBox.Text = $C.Search
    # what the box is for, faint inside it while it is empty
    $hint = New-ChatOverlayText 'Search chats' 'faint' 12
    $hint.IsHitTestVisible = $false
    $hint.Margin = [System.Windows.Thickness]::new(9, 0, 0, 0)
    $hint.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $hint.Visibility = if ($C.Search) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $C.SearchHint = $hint
    $C.SearchBox.add_TextChanged({
            param($s, $e)
            $H = $script:ChatOverlayHost
            $H.Con.Search = $s.Text
            $H.Con.SearchHint.Visibility = if ($s.Text) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
            Update-ChatConsoleChats $H
        })
    $sg = [System.Windows.Controls.Grid]::new()
    [void]$sg.Children.Add($C.SearchBox)
    [void]$sg.Children.Add($hint)
    [void]$top.Children.Add($sg)
    [void]$left.Children.Add($top)
    $sv = [System.Windows.Controls.ScrollViewer]::new()
    $sv.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $C.Chats = [System.Windows.Controls.StackPanel]::new()
    $sv.Content = $C.Chats
    [void]$left.Children.Add($sv)
    [void]$body.Children.Add($left)
    $split = [System.Windows.Controls.GridSplitter]::new()
    $split.Width = 6
    $split.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $split.Background = [System.Windows.Media.Brushes]::Transparent
    [System.Windows.Controls.Grid]::SetColumn($split, 1)
    [void]$body.Children.Add($split)

    # right: compose above, the queue below
    $right = [System.Windows.Controls.Grid]::new()
    [System.Windows.Controls.Grid]::SetColumn($right, 2)
    foreach ($rh in 0, 6, [Math]::Max(140, [double]$C.State.queue)) { $rd = [System.Windows.Controls.RowDefinition]::new(); $rd.Height = & $gl $rh; $right.RowDefinitions.Add($rd) }
    $right.RowDefinitions[0].MinHeight = 200
    $right.RowDefinitions[2].MinHeight = 120
    $C.QueueRow = $right.RowDefinitions[2]
    [void]$body.Children.Add($right)

    $compose = [System.Windows.Controls.DockPanel]::new()
    $compose.Margin = [System.Windows.Thickness]::new(4, 0, 12, 6)
    $C.To = [System.Windows.Controls.StackPanel]::new()
    $C.To.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    [System.Windows.Controls.DockPanel]::SetDock($C.To, [System.Windows.Controls.Dock]::Top)
    [void]$compose.Children.Add($C.To)
    # a new chat's folder and name
    $C.NewBox = [System.Windows.Controls.StackPanel]::new()
    $C.NewBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    [System.Windows.Controls.DockPanel]::SetDock($C.NewBox, [System.Windows.Controls.Dock]::Top)
    $fr = [System.Windows.Controls.DockPanel]::new()
    $fl = New-ChatOverlayText 'Folder' 'dim' 12
    $fl.Width = 52
    $fl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($fl, [System.Windows.Controls.Dock]::Left)
    [void]$fr.Children.Add($fl)
    $browse = New-ChatConsoleButton 'Browse' { Invoke-ChatConsoleBrowse $script:ChatOverlayHost } -Tip 'Pick the folder the new chat works in'
    $browse.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($browse, [System.Windows.Controls.Dock]::Right)
    [void]$fr.Children.Add($browse)
    $C.FolderBox = New-ChatConsoleInput -Tip 'The folder the new chat works in - or drop a folder here'
    $C.FolderBox.Text = $C.NewCwd
    $C.FolderBox.AllowDrop = $true
    $C.FolderBox.add_PreviewDragOver({ param($s, $e) if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { $e.Effects = [System.Windows.DragDropEffects]::Copy; $e.Handled = $true } })
    $C.FolderBox.add_PreviewDrop({
            param($s, $e)
            if (-not $e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { return }
            $e.Handled = $true
            $d = @([string[]]$e.Data.GetData([System.Windows.DataFormats]::FileDrop) | Where-Object { Test-Path -LiteralPath $_ -PathType Container })[0]
            if ($d) { $s.Text = $d }
        })
    $C.FolderBox.add_TextChanged({ $H = $script:ChatOverlayHost; if ($H.Con.Target -and $H.Con.Target.Kind -eq 'new') { $H.Con.Target.Cwd = $H.Con.FolderBox.Text; $H.Con.Dirty = Get-Date; Update-ChatConsolePreview $H } })
    [void]$fr.Children.Add($C.FolderBox)
    [void]$C.NewBox.Children.Add($fr)
    $C.Recent = [System.Windows.Controls.WrapPanel]::new()
    $C.Recent.Margin = [System.Windows.Thickness]::new(52, 3, 0, 3)
    [void]$C.NewBox.Children.Add($C.Recent)
    $nr = [System.Windows.Controls.DockPanel]::new()
    $nl = New-ChatOverlayText 'Name' 'dim' 12
    $nl.Width = 52
    $nl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($nl, [System.Windows.Controls.Dock]::Left)
    [void]$nr.Children.Add($nl)
    $C.NameBox = New-ChatConsoleInput -Tip 'What the chat list calls it - the prompt''s first line if left empty'
    $C.NameBox.Text = $C.NewName
    [void]$nr.Children.Add($C.NameBox)
    [void]$C.NewBox.Children.Add($nr)
    [void]$compose.Children.Add($C.NewBox)
    # the foot: when, mode, model; what Send will do; Send
    $foot = [System.Windows.Controls.StackPanel]::new()
    $foot.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($foot, [System.Windows.Controls.Dock]::Bottom)
    $C.Opts = [System.Windows.Controls.StackPanel]::new()
    [void]$foot.Children.Add($C.Opts)
    $sendRow = [System.Windows.Controls.DockPanel]::new()
    $sendRow.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $C.SendBtn = New-ChatConsoleButton 'Send now' { Invoke-ChatConsoleSend $script:ChatOverlayHost } -Accent -Tip 'Ctrl+Enter'
    $C.SendBtn.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($C.SendBtn, [System.Windows.Controls.Dock]::Right)
    [void]$sendRow.Children.Add($C.SendBtn)
    $C.Preview = New-ChatOverlayText '' 'dim' 11.5
    $C.Preview.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $C.Preview.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$sendRow.Children.Add($C.Preview)
    [void]$foot.Children.Add($sendRow)
    [void]$compose.Children.Add($foot)
    # the prompt, and its files under it
    $pg = [System.Windows.Controls.Grid]::new()
    foreach ($r in 'star', 'auto') { $rd = [System.Windows.Controls.RowDefinition]::new(); $rd.Height = if ($r -eq 'auto') { [System.Windows.GridLength]::Auto } else { & $gl 0 }; $pg.RowDefinitions.Add($rd) }
    $C.Prompt = New-ChatConsoleInput -Multi -Tip 'The prompt. Ctrl+Enter sends; drop files here or paste a screenshot to send them with it'
    $C.Prompt.MinHeight = 80
    $C.Prompt.AllowDrop = $true
    $C.Prompt.Text = $C.Text
    $C.Prompt.add_TextChanged({ $H = $script:ChatOverlayHost; $H.Con.Dirty = Get-Date })
    $C.Prompt.add_PreviewKeyDown({
            param($s, $e)
            $H = $script:ChatOverlayHost
            $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Return) { $e.Handled = $true; Invoke-ChatConsoleSend $H; return }
            # a screenshot or copied files: the box would take neither - text
            # is left to its own paste
            if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::V) {
                $clip = Get-ChatConsoleClipboard
                if ($clip -and (@($clip.Files).Count -or $clip.Image)) { $e.Handled = $true; Invoke-ChatConsolePaste $H $clip }
            }
        })
    # the box would take a drop as text: files are taken here first
    $C.Prompt.add_PreviewDragEnter({ param($s, $e) if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { $e.Effects = [System.Windows.DragDropEffects]::Copy; $e.Handled = $true } })
    $C.Prompt.add_PreviewDragOver({ param($s, $e) if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { $e.Effects = [System.Windows.DragDropEffects]::Copy; $e.Handled = $true } })
    $C.Prompt.add_PreviewDrop({
            param($s, $e)
            if (-not $e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { return }
            $e.Handled = $true
            Add-ChatConsoleDrop $script:ChatOverlayHost ([string[]]$e.Data.GetData([System.Windows.DataFormats]::FileDrop))
        })
    [void]$pg.Children.Add($C.Prompt)
    $C.Files = [System.Windows.Controls.WrapPanel]::new()
    $C.Files.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($C.Files, 1)
    [void]$pg.Children.Add($C.Files)
    [void]$compose.Children.Add($pg)
    [void]$right.Children.Add($compose)

    $hs = [System.Windows.Controls.GridSplitter]::new()
    $hs.Height = 6
    $hs.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
    $hs.Background = [System.Windows.Media.Brushes]::Transparent
    [System.Windows.Controls.Grid]::SetRow($hs, 1)
    [void]$right.Children.Add($hs)

    # the queue: the jobs, and the one picked in full beside them
    $qg = [System.Windows.Controls.Grid]::new()
    $qg.Margin = [System.Windows.Thickness]::new(4, 0, 12, 4)
    [System.Windows.Controls.Grid]::SetRow($qg, 2)
    foreach ($cw in 0, 8, 340) { $cd = [System.Windows.Controls.ColumnDefinition]::new(); $cd.Width = & $gl $cw; $qg.ColumnDefinitions.Add($cd) }
    $ql = [System.Windows.Controls.DockPanel]::new()
    $qh = New-ChatOverlayText 'Queue - open jobs and the last day''s' 'dim' 11.5
    $qh.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    [System.Windows.Controls.DockPanel]::SetDock($qh, [System.Windows.Controls.Dock]::Top)
    [void]$ql.Children.Add($qh)
    $qs = [System.Windows.Controls.ScrollViewer]::new()
    $qs.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $C.Queue = [System.Windows.Controls.StackPanel]::new()
    $qs.Content = $C.Queue
    [void]$ql.Children.Add($qs)
    [void]$qg.Children.Add($ql)
    $ds = [System.Windows.Controls.ScrollViewer]::new()
    $ds.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    [System.Windows.Controls.Grid]::SetColumn($ds, 2)
    $C.Details = [System.Windows.Controls.StackPanel]::new()
    $ds.Content = $C.Details
    [void]$qg.Children.Add($ds)
    [void]$right.Children.Add($qg)

    # the status line: what the last action did, and the watcher
    $sb = [System.Windows.Controls.DockPanel]::new()
    $sb.Margin = [System.Windows.Thickness]::new(12, 2, 12, 6)
    [System.Windows.Controls.Grid]::SetRow($sb, 2)
    $C.WatchText = New-ChatOverlayText '' 'faint' 11
    [System.Windows.Controls.DockPanel]::SetDock($C.WatchText, [System.Windows.Controls.Dock]::Right)
    [void]$sb.Children.Add($C.WatchText)
    $C.Status = New-ChatOverlayText '' 'dim' 11.5 -Trim
    [void]$sb.Children.Add($C.Status)
    [void]$root.Children.Add($sb)
    $w.Content = $root

    $C.Sigs = @{}
    $C.WhenBox = $null
    Update-ChatConsoleTarget $H
    Update-ChatConsoleFiles $H
    if ($C.Win.IsVisible) { Update-ChatConsole $H }
}

function Set-ChatConsoleStatus {
    # what the last action did, in the status line; tone warn for a refusal
    param($H, [string]$Text, [string]$Tone = 'dim')
    if (-not $H.Con -or -not $H.Con.Status) { return }
    $H.Con.Status.Text = $Text
    $H.Con.Status.Foreground = Get-ChatOverlayBrush $Tone
}

function Show-ChatConsole {
    # opened, where it was left; -Activate brings it forward with the
    # prompt box ready, when the user asked for it
    param($H, [switch]$Activate)
    if (-not $H.Con) { New-ChatConsoleWindow $H }
    $C = $H.Con
    if (-not $C.Win.IsVisible) {
        # In screen pixels, as the panel is placed: WPF's units differ from
        # one monitor to the next, and a window left on a 100% screen beside
        # a 150% one reopened in the wrong place. Shown off every screen
        # first, then put where it goes - Windows rescales it on the way.
        $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
                $a = $_.WorkingArea
                [pscustomobject]@{ X = $a.X; Y = $a.Y; Width = $a.Width; Height = $a.Height; Primary = $_.Primary }
            })
        $scale = try { $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $v = $g.DpiX / 96.0; $g.Dispose(); $v } catch { 1.0 }
        $at = Get-ChatConsolePlacement $C.State $screens (980 * $scale) (680 * $scale)
        $C.Win.WindowState = [System.Windows.WindowState]::Normal
        $C.Win.Left = -32000
        $C.Win.Top = -32000
        $C.Win.ShowActivated = [bool]$Activate
        $C.Win.Show()
        [ChatOverlayNative]::Place($C.Hwnd, [int]$at.X, [int]$at.Y, [int]$at.W, [int]$at.H)
        if ($C.State.max) { $C.Win.WindowState = [System.Windows.WindowState]::Maximized }
        # a fresh look at what the limit cut off, and at the chats
        $H.Ctx.CutAt = [datetime]::MinValue
        $C.Sigs = @{}
        Update-ChatConsole $H
    }
    if ($Activate) {
        if ($C.Win.WindowState -eq [System.Windows.WindowState]::Minimized) { $C.Win.WindowState = [System.Windows.WindowState]::Normal }
        [void]$C.Win.Activate()
        [void]$C.Prompt.Focus()
    }
}

function Hide-ChatConsole {
    param($H)
    if (-not $H.Con) { return }
    Save-ChatConsoleDraft $H
    $H.Con.Win.Hide()
}

function Save-ChatConsoleDraft {
    # where the window is and what is being written, for the next time it
    # opens - after a restart too
    param($H)
    $C = $H.Con
    if (-not $C) { return }
    try {
        $s = $C.State
        $max = $C.Win.WindowState -eq [System.Windows.WindowState]::Maximized
        # its rect in screen pixels, while it is neither maximized nor
        # minimized - those keep the last normal one
        if ($C.Win.IsVisible) {
            $s.max = $max
            if ($C.Win.WindowState -eq [System.Windows.WindowState]::Normal) {
                $r = [ChatOverlayNative]::GetRect($C.Hwnd)
                if ($r -and $r[2] -gt 0 -and $r[0] -gt -30000) { $s.x = $r[0]; $s.y = $r[1]; $s.w = $r[2]; $s.h = $r[3] }
            }
        }
        if ($C.LeftCol -and $C.LeftCol.ActualWidth -gt 0) { $s.left = [Math]::Round($C.LeftCol.ActualWidth) }
        if ($C.QueueRow -and $C.QueueRow.ActualHeight -gt 0) { $s.queue = [Math]::Round($C.QueueRow.ActualHeight) }
        $t = $C.Target
        $s.draft = [pscustomobject]@{
            target = $(if ($t) { [pscustomobject]@{ Kind = $t.Kind; Id = $t.Id; Provider = $t.Provider; Title = $t.Title; Project = $t.Project; Cwd = $t.Cwd; Path = $t.Path } } else { $null })
            text = $(if ($C.Prompt) { $C.Prompt.Text } else { $C.Text })
            files = @($C.Staged | Where-Object { -not $_.Error -and -not $_.Task } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.Path; Dir = $_.Dir; Size = $_.Size } })
            when = $C.When; whenValue = $(if ($C.WhenBox) { $C.WhenBox.Text } else { $C.WhenValue }); mode = $C.Mode; model = $C.Model
            newCwd = $(if ($C.FolderBox) { $C.FolderBox.Text } else { $C.NewCwd }); newName = $(if ($C.NameBox) { $C.NameBox.Text } else { $C.NewName })
        }
        New-ChatqDir $script:ChatqData
        Save-ChatqJson $script:ChatConsoleStatePath $s
        $C.Dirty = $null
    }
    catch { Write-ChatOverlayLog "console state: $($_.Exception.Message)" }
}

function Restore-ChatConsoleDraft {
    # the draft console-state.json kept; staged files it no longer names -
    # left by a crash, or sent - are swept from data/console/draft
    param($H)
    $C = $H.Con
    $d = $C.State.draft
    $keep = @{}
    if ($d) {
        if ($d.target) { $C.Target = @{ Kind = $d.target.Kind; Id = $d.target.Id; Provider = $d.target.Provider; Title = $d.target.Title; Project = $d.target.Project; Cwd = $d.target.Cwd; Path = $d.target.Path; Live = $null } }
        $C.Text = [string]$d.text
        foreach ($f in @($d.files)) {
            if ($f -and $f.Path -and (Test-Path -LiteralPath $f.Path)) {
                $C.Staged.Add(@{ Name = $f.Name; Path = $f.Path; Dir = $f.Dir; Size = [int64]$f.Size; Task = $null; Error = $null })
                $keep[([string]$f.Dir).ToLowerInvariant()] = $true
            }
        }
        if ($d.when) { $C.When = [string]$d.when }
        $C.WhenValue = [string]$d.whenValue
        $C.Mode = [string]$d.mode
        $C.Model = [string]$d.model
        $C.NewCwd = [string]$d.newCwd
        $C.NewName = [string]$d.newName
    }
    if (Test-Path -LiteralPath $script:ChatConsoleDraftDir) {
        foreach ($x in @(Get-ChildItem -LiteralPath $script:ChatConsoleDraftDir -Directory -EA SilentlyContinue)) {
            if (-not $keep[$x.FullName.ToLowerInvariant()]) { Remove-Item -LiteralPath $x.FullName -Recurse -Force -EA SilentlyContinue }
        }
    }
}

function Update-ChatConsole {
    # after every collector pass while it shows: each part redrawn only when
    # what it shows changed
    param($H)
    $C = $H.Con
    # minimized, nobody sees it: nothing drawn until it is restored
    if (-not $C -or -not $C.Win.IsVisible -or $C.Modal -or $C.Win.WindowState -eq [System.Windows.WindowState]::Minimized) { return }
    try {
        Update-ChatConsoleIndex $H
        Update-ChatConsoleStaging $H
        $jsig = [string]$H.Ctx.JobsSig
        if ($jsig -ne $C.JobsSig) { $C.JobsSig = $jsig; $C.Jobs = @(Get-ChatqJobs) }
        Update-ChatConsoleHeader $H
        Update-ChatConsoleChats $H
        Update-ChatConsoleQueue $H
        Update-ChatConsolePreview $H
        Update-ChatConsoleWatcher $H
        if ($C.Dirty -and ((Get-Date) - $C.Dirty).TotalSeconds -ge 1) { Save-ChatConsoleDraft $H }
    }
    catch { Write-ChatOverlayLog "console: $($_.Exception.Message) @ $(($_.ScriptStackTrace -split "`n")[0])" }
}

function Update-ChatConsoleIndex {
    # The chats the index knows, for Recent and the search: read when the
    # window first shows and again whenever the file changes - each time in
    # a runspace of its own, never on this thread - and brought up to date
    # by a hidden PowerShell every 10 minutes, since Sync-ChatIndex reads
    # transcripts.
    param($H)
    $C = $H.Con
    $C.IndexParsed = $true
    $stamp = Get-ChatIndexStamp
    if ($stamp -and $stamp -ne $C.IndexStamp) { Start-ChatConsoleIndexRead $H $stamp }
    if ($C.Sync) {
        if ($C.Sync.HasExited) { try { $C.Sync.Dispose() } catch {}; $C.Sync = $null }
        return
    }
    if ($script:ChatConsoleNoSync) { return }
    $old = try { ((Get-Date) - [System.IO.File]::GetLastWriteTime($script:ChatIndexPath)).TotalMinutes -ge 10 } catch { $true }
    if ($old -and ((Get-Date) - $C.SyncAt).TotalMinutes -ge 10) { Start-ChatConsoleIndexSync $H }
}

function Start-ChatConsoleIndexRead {
    # Get-ChatIndex's parse, in a runspace of its own: on the window's thread
    # it took 250 ms for 226 chats here, and about 2 s for 2,000, each time
    # the index changed. Starting the runspace costs this thread 10-50 ms; a
    # timer takes the rows once they are ready. One read at a time - a file
    # changed meanwhile is read on the pass after.
    param($H, [string]$Stamp)
    $C = $H.Con
    if ($C.IndexRead) { return }
    try {
        $rs = [runspacefactory]::CreateRunspace([System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2())
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:ChatIndexRead.ToString()).AddArgument($script:ChatIndexPath).AddArgument($script:ChatIndexSep)
        $C.IndexRead = @{ Ps = $ps; Async = $ps.BeginInvoke(); Stamp = $Stamp; At = Get-Date }
    }
    catch {
        Write-ChatOverlayLog "console: the index could not be read: $($_.Exception.Message)"
        # not tried again until the file changes
        $C.IndexStamp = $Stamp
        return
    }
    $t = [System.Windows.Threading.DispatcherTimer]::new()
    $t.Interval = [TimeSpan]::FromMilliseconds(100)
    $t.add_Tick({
            param($s, $e)
            $H = $script:ChatOverlayHost
            if (-not $H.Con.IndexRead -or $H.Con.IndexRead.Async.IsCompleted) { $s.Stop(); Complete-ChatConsoleIndexRead $H }
        })
    $t.Start()
}

function Complete-ChatConsoleIndexRead {
    # the rows a read brought back, into the console - and into Get-ChatIndex's
    # own copy while the file is still that version, so a Send does not parse
    # it again on this thread
    param($H)
    $C = $H.Con
    $r = $C.IndexRead
    if (-not $r) { return }
    $C.IndexRead = $null
    $rows = $null
    try {
        $got = $r.Ps.EndInvoke($r.Async)
        if ($r.Ps.HadErrors) { Write-ChatOverlayLog "console: the index could not be read: $(@($r.Ps.Streams.Error)[0])" }
        else { $rows = @($got) }
    }
    catch { Write-ChatOverlayLog "console: the index could not be read: $($_.Exception.Message)" }
    finally {
        try { $r.Ps.Runspace.Dispose() } catch {}
        try { $r.Ps.Dispose() } catch {}
    }
    $ms = [int]((Get-Date) - $r.At).TotalMilliseconds
    if ($ms -gt 2000) { Write-ChatOverlayLog "console: the index took $ms ms to read, off the window's thread" }
    # a file that would not parse is not read again until it changes
    $C.IndexStamp = $r.Stamp
    if ($null -eq $rows) { return }
    $C.Index = $rows
    if ($r.Stamp -and $r.Stamp -eq (Get-ChatIndexStamp)) { $script:ChatIndexCache = $rows; $script:ChatIndexStamp = $r.Stamp }
    $C.Sigs.Chats = $null
    if ($C.Win -and $C.Win.IsVisible) { Update-ChatConsoleChats $H }
}

function Start-ChatConsoleIndexSync {
    # Sync-ChatIndex in a hidden Windows PowerShell of its own, with this
    # process's view of where the chats are
    param($H)
    $C = $H.Con
    $C.SyncAt = Get-Date
    $path = $script:ChatqScriptPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $pre = '$env:CHATQ_OVERLAY=''1''; '
    foreach ($n in 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'CHAT_CODE_USER') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $pre += "`$env:$n=$(& $q $v); " }
    }
    $cmd = "$pre. $(& $q $path); `$null = Sync-ChatIndex -Provider claude, codex"
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
    $exe = Join-Path $(if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try { $C.Sync = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru }
    catch { Write-ChatOverlayLog "console: index sync: $($_.Exception.Message)" }
}

function Update-ChatConsoleHeader {
    param($H)
    $C = $H.Con
    $bits = @()
    foreach ($u in @($H.Snap.header.usage)) {
        if (-not $u) { continue }
        $bits += "$($u.provider) " + ((@($u.windows) | ForEach-Object { "$($_.label) $($_.percent)%" }) -join " $($script:ChatqDot) ")
    }
    # $n, not $c: PowerShell's names ignore case, and $C is the console
    $n = $H.Snap.counts
    if ($n) {
        $q = @()
        if ([int]$n.queued) { $q += "$([int]$n.queued) queued" }
        if ([int]$n.running) { $q += "$([int]$n.running) running" }
        if ($n.PSObject.Properties['cutOff'] -and [int]$n.cutOff) { $q += "$([int]$n.cutOff) cut off" }
        if ($q) { $bits += ($q -join ', ') }
    }
    $C.Header.Text = $bits -join "    $($script:ChatqDot)    "
}

function Get-ChatConsoleChatItems {
    # what the list shows: cut off first, then open in VS Code, then recent -
    # each chat once, as the snapshot and the index have it
    param($H)
    $C = $H.Con
    $cut = [System.Collections.Generic.List[object]]::new()
    $open = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($r in @($H.Snap.rows)) {
        if (-not $r -or $r.kind -notin 'session', 'cutoff' -or -not $r.sessionId) { continue }
        $path = if ($r.PSObject.Properties['path'] -and $r.path) { [string]$r.path } elseif ($H.Ctx.Text[[string]$r.sessionId]) { [string]$H.Ctx.Text[[string]$r.sessionId].Path } else { $null }
        $item = [pscustomobject]@{
            Key = "$($r.kind):$($r.sessionId)"; Kind = $(if ($r.status -eq 'cutoff') { 'cutoff' } else { 'open' }); Provider = 'claude'; Id = [string]$r.sessionId
            Title = [string]$r.title; Project = [string]$r.project; Cwd = [string]$r.cwd; Path = $path; State = [string]$r.stateText
            Status = [string]$r.status; Live = $(if ($r.kind -eq 'session') { [string]$r.chat } else { $null })
        }
        $seen[$item.Id] = $true
        if ($item.Kind -eq 'cutoff') { $cut.Add($item) } else { $open.Add($item) }
    }
    # The index's chats newest first, sorted once per version of the index -
    # not every pass: that walked every row of it, 1 s for 2,000 chats. Each
    # pass takes only the first 30 (50 when searching) that are not listed
    # above and that the search matches.
    if ($null -eq $C.Pool -or $C.PoolStamp -ne $C.IndexStamp) {
        $C.Pool = @($C.Index | Where-Object { $_.Provider -in 'claude', 'codex' -and -not $_.Hidden -and $_.Title -and $_.Title -ne '(empty)' } |
                ForEach-Object { [pscustomobject]@{ Row = $_; When = (ConvertTo-ChatqDate $_.When); Hay = ([string]$_.Title).ToLowerInvariant() } } |
                Sort-Object { if ($_.When) { $_.When } else { [datetime]::MinValue } } -Descending)
        $C.PoolStamp = $C.IndexStamp
    }
    $words = @(([string]$C.Search).ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    $max = if ($words) { 50 } else { 30 }
    $recent = [System.Collections.Generic.List[object]]::new()
    foreach ($x in $C.Pool) {
        if ($recent.Count -ge $max) { break }
        $r = $x.Row
        if ($seen[[string]$r.Id]) { continue }
        $all = $true
        foreach ($w in $words) { if (-not $x.Hay.Contains($w)) { $all = $false; break } }
        if (-not $all) { continue }
        $recent.Add([pscustomobject]@{
                Key = "recent:$($r.Id)"; Kind = 'recent'; Provider = [string]$r.Provider; Id = [string]$r.Id; Title = [string]$r.Title
                Project = ''; Cwd = $null; Path = [string]$r.Path; State = "$($r.Provider)$(if ($x.When) { " $($script:ChatqDot) $(Get-ChatAge $x.When)" })"; Status = 'idle'; Live = $null
            })
    }
    return [pscustomobject]@{ CutOff = $cut.ToArray(); Open = $open.ToArray(); Recent = $recent.ToArray() }
}

function Update-ChatConsoleChats {
    param($H)
    $C = $H.Con
    if (-not $C.Chats) { return }
    $all = Get-ChatConsoleChatItems $H
    $cut = @(Select-ChatConsoleChats $all.CutOff $C.Search)
    $open = @(Select-ChatConsoleChats $all.Open $C.Search)
    # searched and cut to length as it was gathered
    $recent = @($all.Recent)
    $sel = if ($C.Target) { "$($C.Target.Kind)|$($C.Target.Id)|$($C.Target.Cwd)" } else { '' }
    $key = (@($cut + $open + $recent | ForEach-Object { "$($_.Key)=$($_.State)" }) -join ';') + "|$sel"
    if ($key -eq $C.Sigs.Chats) { return }
    $C.Sigs.Chats = $key
    $C.Chats.Children.Clear()
    $C.ChatItems = @($cut + $open + $recent)
    $section = {
        param($title, $items, [scriptblock]$extra)
        if (-not $items) { return }
        $hd = [System.Windows.Controls.DockPanel]::new()
        $hd.Margin = [System.Windows.Thickness]::new(0, 8, 0, 3)
        if ($extra) { $x = & $extra; [System.Windows.Controls.DockPanel]::SetDock($x, [System.Windows.Controls.Dock]::Right); [void]$hd.Children.Add($x) }
        $tb = New-ChatOverlayText "$title ($(@($items).Count))" 'dim' 11.5 -Bold
        $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$hd.Children.Add($tb)
        [void]$C.Chats.Children.Add($hd)
        foreach ($i in $items) { [void]$C.Chats.Children.Add((New-ChatConsoleChatItem $H $i)) }
    }
    & $section 'Cut off' $cut { New-ChatConsoleButton 'Continue all' { Invoke-ChatConsoleContinue $script:ChatOverlayHost @($script:ChatOverlayHost.Con.ChatItems | Where-Object { $_.Kind -eq 'cutoff' }) } -Small -Tip 'Queue "Continue from where you left off." for each of them' }
    & $section 'Open in VS Code' $open $null
    & $section 'Recent' $recent $null
    if (-not ($cut -or $open -or $recent)) {
        [void]$C.Chats.Children.Add((New-ChatOverlayText $(if ($C.Search) { 'no chat matches' } elseif (-not $C.Index -and ($C.IndexRead -or -not $C.IndexParsed)) { 'reading the chats...' } else { 'no chats' }) 'faint' 12))
    }
}

function New-ChatConsoleChatItem {
    # one chat in the list: a dot in its state's colour, project and title,
    # what it is doing; a click makes it the one written to
    param($H, $Item)
    $C = $H.Con
    $b = [System.Windows.Controls.Border]::new()
    $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $b.Padding = [System.Windows.Thickness]::new(6, 3, 6, 4)
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.Tag = $Item
    $on = $C.Target -and $C.Target.Kind -ne 'new' -and $C.Target.Id -eq $Item.Id
    $b.Background = if ($on) { Get-ChatOverlayBrush 'select' } else { [System.Windows.Media.Brushes]::Transparent }
    $g = [System.Windows.Controls.DockPanel]::new()
    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 8
    $dot.Height = 8
    $dot.Margin = [System.Windows.Thickness]::new(0, 5, 7, 0)
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $dot.Fill = Get-ChatOverlayBrush $(if ($Item.Kind -eq 'recent') { 'faint' } else { [string]$Item.Status })
    [System.Windows.Controls.DockPanel]::SetDock($dot, [System.Windows.Controls.Dock]::Left)
    [void]$g.Children.Add($dot)
    if ($Item.Kind -eq 'cutoff') {
        $cb = New-ChatConsoleButton 'Continue' { param($s, $e) $e.Handled = $true; Invoke-ChatConsoleContinue $script:ChatOverlayHost @($s.Tag) } -Small -Tag $Item -Tip 'Queue "Continue from where you left off." for this chat'
        [System.Windows.Controls.DockPanel]::SetDock($cb, [System.Windows.Controls.Dock]::Right)
        [void]$g.Children.Add($cb)
    }
    $txt = [System.Windows.Controls.StackPanel]::new()
    $t1 = [System.Windows.Controls.TextBlock]::new()
    $t1.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    if ($Item.Project) {
        $r = [System.Windows.Documents.Run]::new("$($Item.Project)  ")
        $r.Foreground = Get-ChatOverlayBrush 'project'
        $r.FontWeight = [System.Windows.FontWeights]::SemiBold
        $t1.Inlines.Add($r)
    }
    $r = [System.Windows.Documents.Run]::new([string]$Item.Title)
    $r.Foreground = Get-ChatOverlayBrush 'text'
    $t1.Inlines.Add($r)
    [void]$txt.Children.Add($t1)
    [void]$txt.Children.Add((New-ChatOverlayText ([string]$Item.State) $(if ($Item.Kind -eq 'cutoff') { 'cutoff' } else { 'faint' }) 11 -Trim))
    [void]$g.Children.Add($txt)
    $b.Child = $g
    $b.add_MouseEnter({ param($s, $e) if ($s.Background -eq [System.Windows.Media.Brushes]::Transparent) { $s.Background = Get-ChatOverlayBrush 'hover' } })
    $b.add_MouseLeave({ param($s, $e) $H = $script:ChatOverlayHost; $t = $H.Con.Target; if (-not ($t -and $t.Kind -ne 'new' -and $t.Id -eq $s.Tag.Id)) { $s.Background = [System.Windows.Media.Brushes]::Transparent } })
    $b.add_MouseLeftButtonUp({ param($s, $e) Select-ChatConsoleTarget $script:ChatOverlayHost $s.Tag })
    return $b
}

function Select-ChatConsoleTarget {
    # the chat Send goes to
    param($H, $Item)
    $C = $H.Con
    $C.Target = @{ Kind = 'chat'; Id = $Item.Id; Provider = $Item.Provider; Title = $Item.Title; Project = $Item.Project; Cwd = $Item.Cwd; Path = $Item.Path; Live = $Item.Live }
    $C.Sigs.Chats = $null
    $C.Dirty = Get-Date
    Update-ChatConsoleTarget $H
    Update-ChatConsoleChats $H
    [void]$C.Prompt.Focus()
}

function Select-ChatConsoleNew {
    param($H)
    $C = $H.Con
    $cwd = if ($C.FolderBox -and $C.FolderBox.Text) { $C.FolderBox.Text } elseif (@($C.State.folders).Count) { [string]@($C.State.folders)[0] } else { '' }
    $C.Target = @{ Kind = 'new'; Id = $null; Provider = 'claude'; Title = $null; Project = $null; Cwd = $cwd; Path = $null; Live = $null }
    if ($C.FolderBox) { $C.FolderBox.Text = $cwd }
    $C.Sigs.Chats = $null
    $C.Dirty = Get-Date
    Update-ChatConsoleTarget $H
    Update-ChatConsoleChats $H
    [void]$C.FolderBox.Focus()
}

function Get-ChatConsoleRow {
    # the index's row for the chat picked, and what the run needs to know of
    # it - read once per version of its transcript
    param($H, $Target)
    $row = Get-ChatqRowById $Target.Id $Target.Provider $Target.Path $Target.Cwd
    if (-not $row) { return $null }
    $len = try { ([System.IO.FileInfo]::new($row.Path)).Length } catch { 0 }
    $k = "$($row.Path)|$len"
    $info = $H.Con.Info[$k]
    if (-not $info) { $info = Get-ChatqJobInfo $row; $H.Con.Info[$k] = $info }
    return [pscustomobject]@{ Row = $row; Info = $info }
}

function Update-ChatConsoleTarget {
    # the To line - or a new chat's folder and name - and the choices
    param($H)
    $C = $H.Con
    $C.To.Children.Clear()
    $t = $C.Target
    $isNew = $t -and $t.Kind -eq 'new'
    $C.NewBox.Visibility = if ($isNew) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $line = [System.Windows.Controls.TextBlock]::new()
    $line.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $add = { param($x, $tone, [switch]$b) $r = [System.Windows.Documents.Run]::new($x); $r.Foreground = Get-ChatOverlayBrush $tone; if ($b) { $r.FontWeight = [System.Windows.FontWeights]::SemiBold }; $line.Inlines.Add($r) }
    & $add 'To  ' 'faint'
    $sub = ''
    if (-not $t) { & $add 'pick a chat on the left, or + New chat' 'dim' }
    elseif ($isNew) {
        & $add 'a new Claude chat' 'text' -b
        $sub = 'it starts in the folder below, in default mode unless you pick another'
        $C.Recent.Children.Clear()
        foreach ($f in @($C.State.folders | Select-Object -First 6)) {
            if (-not $f) { continue }
            [void]$C.Recent.Children.Add((New-ChatConsoleButton (Split-Path ([string]$f).TrimEnd('\', '/') -Leaf) { param($s, $e) $s.Tag.Text = [string]$s.ToolTip } -Small -Tip ([string]$f) -Tag $C.FolderBox))
        }
    }
    else {
        if ($t.Project) { & $add "$($t.Project)  " 'project' -b }
        & $add ([string]$t.Title) 'text' -b
        $got = try { Get-ChatConsoleRow $H $t } catch { $null }
        if (-not $got) { $sub = Get-ChatConsoleMissingSay $t }
        elseif ($got.Info.Error) { $sub = [string]$got.Info.Error }
        else {
            $t.Cwd = $got.Info.Cwd
            $t.Mode = $got.Info.Mode
            $sub = "$($got.Row.Provider) $($script:ChatqDot) $($got.Info.Mode) as it last ran $($script:ChatqDot) $($got.Info.Cwd)"
        }
    }
    [void]$C.To.Children.Add($line)
    if ($sub) { [void]$C.To.Children.Add((New-ChatOverlayText $sub 'faint' 11 -Trim)) }
    Update-ChatConsoleOptions $H
}

function Update-ChatConsoleOptions {
    # When, mode and model, as chips
    param($H)
    $C = $H.Con
    if ($C.WhenBox) { $C.WhenValue = $C.WhenBox.Text }
    $C.Opts.Children.Clear()
    $row = {
        param($label, $chips, $extra)
        $d = [System.Windows.Controls.DockPanel]::new()
        $l = New-ChatOverlayText $label 'dim' 12
        $l.Width = 52
        $l.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.DockPanel]::SetDock($l, [System.Windows.Controls.Dock]::Left)
        [void]$d.Children.Add($l)
        if ($extra) { [System.Windows.Controls.DockPanel]::SetDock($extra, [System.Windows.Controls.Dock]::Right); [void]$d.Children.Add($extra) }
        [void]$d.Children.Add($chips)
        [void]$C.Opts.Children.Add($d)
    }
    $wb = $null
    if ($C.When -in 'at', 'in') {
        $wb = New-ChatConsoleInput -Tip $(if ($C.When -eq 'at') { 'a time: 13:00, or 2026-10-01 09:00' } else { 'how long from now: 90m, 2h, 1d' })
        $wb.Width = 150
        $wb.Text = $C.WhenValue
        $wb.add_TextChanged({ $H = $script:ChatOverlayHost; $H.Con.WhenValue = $H.Con.WhenBox.Text; $H.Con.Dirty = Get-Date; Update-ChatConsolePreview $H })
    }
    $C.WhenBox = $wb
    & $row 'When' (New-ChatConsoleChips @('now', 'turn', 'at', 'in') @('Now', 'In turn', 'At', 'In') $C.When {
            param($s, $e) $H = $script:ChatOverlayHost; $H.Con.When = [string]$s.Tag; $H.Con.Dirty = Get-Date; Update-ChatConsoleOptions $H
            if ($H.Con.WhenBox) { [void]$H.Con.WhenBox.Focus() }
        }) $wb
    $isNew = $C.Target -and $C.Target.Kind -eq 'new'
    if ($C.Target -and $C.Target.Provider -eq 'codex') {
        # Codex runs in the sandbox it last used, on its own model: Claude's
        # modes and models are not offered, and are never sent with it
        $cx = New-ChatOverlayText 'a Codex chat runs in the sandbox and on the model it last used' 'faint' 11 -Trim
        $cx.Margin = [System.Windows.Thickness]::new(52, 2, 0, 0)
        [void]$C.Opts.Children.Add($cx)
        Update-ChatConsolePreview $H
        return
    }
    $asRan = if ($isNew) { 'default' } else { 'as it ran' }
    & $row 'Mode' (New-ChatConsoleChips (@('') + $script:ChatConsoleModes) (@($asRan) + $script:ChatConsoleModes) $C.Mode {
            param($s, $e) $H = $script:ChatOverlayHost; $H.Con.Mode = [string]$s.Tag; $H.Con.Dirty = Get-Date; Update-ChatConsoleOptions $H
        }) $null
    & $row 'Model' (New-ChatConsoleChips (@('') + $script:ChatConsoleModels) (@($(if ($isNew) { 'default' } else { 'its own' })) + $script:ChatConsoleModels) $C.Model {
            param($s, $e) $H = $script:ChatOverlayHost; $H.Con.Model = [string]$s.Tag; $H.Con.Dirty = Get-Date; Update-ChatConsoleOptions $H
        }) $null
    # what the mode means for a run with nobody there to answer
    $m = if ($C.Mode) { $C.Mode } elseif ($isNew) { 'default' } elseif ($C.Target) { [string]$C.Target.Mode } else { '' }
    $hint = switch ($m) {
        'plan' { 'plan mode stops at a plan - auto lets it act' }
        'bypassPermissions' { 'bypassPermissions runs everything without asking' }
        { $_ -in 'default', 'manual' } { 'anything that would ask is denied unattended - acceptEdits or auto lets it edit' }
        default { $null }
    }
    if ($hint) {
        $ht = New-ChatOverlayText $hint 'faint' 11 -Trim
        $ht.Margin = [System.Windows.Thickness]::new(52, 1, 0, 0)
        [void]$C.Opts.Children.Add($ht)
    }
    Update-ChatConsolePreview $H
}

function Get-ChatConsoleBlock {
    <#
    The provider's limit, for the preview, from what the collector already
    holds: the watcher's blocks while jobs wait, a usage window marked
    limited, and the latest reset among the chats the limit cut off. Nothing
    is read here: Get-ChatqBlocks with no watcher running scans the
    transcripts, which stalled the window for half a second each minute.
    #>
    param($H, [string]$Provider)
    $p = if ($Provider) { $Provider } else { 'claude' }
    $now = Get-Date
    $b = $H.Ctx.Blocks
    if ($b -and $b.Count) {
        foreach ($k in @($b.Keys)) {
            # Why: what the watcher kept of it - for a refused login, the CLI's words
            if (($k -eq $p -or $k -like "$p|*") -and $b[$k].Until) { return [pscustomobject]@{ Until = $b[$k].Until; Type = [string]$b[$k].Type; Why = [string]$b[$k].Source } }
        }
    }
    $name = if ($p -eq 'codex') { 'Codex' } else { 'Claude' }
    $u = @($H.Snap.header.usage | Where-Object { $_ -and $_.provider -eq $name })[0]
    foreach ($w in @($u.windows)) {
        if (-not $w -or -not $w.limited -or -not $w.resetsAt) { continue }
        $until = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$w.resetsAt).LocalDateTime
        if ($until -gt $now) { return [pscustomobject]@{ Until = $until; Type = [string]$w.label } }
    }
    if ($p -eq 'claude') {
        # one account, one limit: the chats it stopped wait for its latest reset
        $cut = @($H.Ctx.CutOff | Where-Object { $_.Why -eq 'limit' -and $_.ResetsAt -and $_.ResetsAt -gt $now } | Sort-Object ResetsAt -Descending)[0]
        if ($cut) { return [pscustomobject]@{ Until = $cut.ResetsAt; Type = 'limit' } }
    }
    return $null
}

function Update-ChatConsolePreview {
    param($H)
    $C = $H.Con
    if (-not $C.Preview) { return }
    $plan = ConvertFrom-ChatConsoleWhen $C.When $(if ($C.WhenBox) { $C.WhenBox.Text } else { $C.WhenValue })
    $t = $C.Target
    if ($t -and $t.Kind -eq 'chat') {
        # open in VS Code now, or not: as the collector last saw it
        $r = @($H.Snap.rows | Where-Object { $_ -and $_.kind -eq 'session' -and $_.sessionId -eq $t.Id })[0]
        $t.Live = if ($r) { [string]$r.chat } else { $null }
    }
    $prov = if ($t) { $t.Provider } else { 'claude' }
    $ahead = @($C.Jobs | Where-Object { $_.state -eq 'queued' -and $_.provider -eq $prov }).Count
    $text = Get-ChatConsoleSendPreview $t $plan (Get-ChatConsoleBlock $H $prov) $ahead ([bool]$H.Ctx.Watcher)
    $C.Preview.Text = $text
    $C.Preview.Foreground = Get-ChatOverlayBrush $(if ($plan.Error -or -not $t) { 'warn' } else { 'dim' })
    $C.SendBtn.Child.Text = if ($C.When -eq 'now') { 'Send now' } else { 'Queue' }
}

function Update-ChatConsoleWatcher {
    param($H)
    $C = $H.Con
    $queued = [bool](@($C.Jobs | Where-Object { $_.state -eq 'queued' }).Count)
    if ($C.Request) {
        switch (Test-ChatqWatcherRequest $C.Request $queued) {
            'up' { $C.Request = $null }
            'failed' { $C.Request = $null; Set-ChatConsoleStatus $H 'the watcher did not start - chatqrun -Foreground in a shell shows why' 'warn' }
        }
    }
    $C.WatchText.Text = if ($C.Request) { 'starting the watcher...' } elseif ($H.Ctx.Watcher) { 'watcher running' } elseif ($queued) { 'watcher stopped - jobs wait' } else { 'watcher idle' }
}

function Get-ChatConsoleClipboard {
    # what a paste would bring: files copied in Explorer, or an image - a
    # PNG as the snipping tool writes it, else the bitmap - or $null for
    # text, which the box pastes itself
    if ($script:ChatConsoleClipboardSeam) { return (& $script:ChatConsoleClipboardSeam) }
    try {
        if ([System.Windows.Clipboard]::ContainsFileDropList()) { return [pscustomobject]@{ Files = @([System.Windows.Clipboard]::GetFileDropList()); Image = $null } }
        # text wins: cells copied from Excel bring a picture of themselves
        # along, a screenshot brings no text
        if ([System.Windows.Clipboard]::ContainsText()) { return $null }
        if ([System.Windows.Clipboard]::ContainsData('PNG')) {
            $st = [System.Windows.Clipboard]::GetData('PNG')
            if ($st -is [System.IO.Stream]) { $ms = [System.IO.MemoryStream]::new(); $st.CopyTo($ms); return [pscustomobject]@{ Files = @(); Image = $ms.ToArray() } }
        }
        if ([System.Windows.Clipboard]::ContainsImage()) {
            $img = [System.Windows.Clipboard]::GetImage()
            $enc = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($img))
            $ms = [System.IO.MemoryStream]::new()
            $enc.Save($ms)
            return [pscustomobject]@{ Files = @(); Image = $ms.ToArray() }
        }
    }
    catch { Write-ChatOverlayLog "console: clipboard: $($_.Exception.Message)" }
    return $null
}

function Invoke-ChatConsolePaste {
    param($H, $Clip)
    if (@($Clip.Files).Count) { Add-ChatConsoleDrop $H @($Clip.Files) }
    if ($Clip.Image) { Add-ChatConsoleImage $H ([byte[]]$Clip.Image) }
}

function Add-ChatConsoleDrop {
    # what was dropped or pasted: files go with the prompt; a folder names a
    # new chat's folder, or is turned away
    param($H, [string[]]$Paths)
    $C = $H.Con
    $files = @()
    foreach ($p in @($Paths)) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            if ($C.Target -and $C.Target.Kind -eq 'new') { $C.FolderBox.Text = $p }
            else { Set-ChatConsoleStatus $H "$(Split-Path $p -Leaf) is a folder - only files go with a prompt" 'warn' }
            continue
        }
        if (Test-Path -LiteralPath $p -PathType Leaf) { $files += $p }
    }
    if ($files) { Add-ChatConsoleFiles $H $files }
}

function Add-ChatConsoleFiles {
    # Staged: copied into data/console/draft off this thread - the original
    # may move or change before the job sends - each into a folder of its
    # own so it keeps its name; Send waits for every copy.
    param($H, [string[]]$Paths)
    $C = $H.Con
    foreach ($p in @($Paths)) {
        $fi = Get-Item -LiteralPath $p -EA SilentlyContinue
        if (-not $fi -or $fi.PSIsContainer) { continue }
        $dir = Join-Path $script:ChatConsoleDraftDir ([guid]::NewGuid().ToString('N').Substring(0, 12))
        New-ChatqDir $dir
        $dest = Join-Path $dir $fi.Name
        $task = $null
        $err = $null
        try { $task = [ChatOverlayNative]::CopyFileAsync($fi.FullName, $dest) } catch { $err = $_.Exception.Message }
        $C.Staged.Add(@{ Name = $fi.Name; Path = $dest; Dir = $dir; Size = $fi.Length; Task = $task; Error = $err })
    }
    $C.Dirty = Get-Date
    Update-ChatConsoleFiles $H
}

function Add-ChatConsoleImage {
    # a pasted screenshot, kept as clip.png - clip-2.png for a second
    param($H, [byte[]]$Bytes)
    $C = $H.Con
    $n = @($C.Staged | Where-Object { $_.Name -like 'clip*.png' }).Count
    $name = if ($n) { "clip-$($n + 1).png" } else { 'clip.png' }
    $dir = Join-Path $script:ChatConsoleDraftDir ([guid]::NewGuid().ToString('N').Substring(0, 12))
    New-ChatqDir $dir
    $dest = Join-Path $dir $name
    [System.IO.File]::WriteAllBytes($dest, $Bytes)
    $C.Staged.Add(@{ Name = $name; Path = $dest; Dir = $dir; Size = [int64]$Bytes.Length; Task = $null; Error = $null })
    $C.Dirty = Get-Date
    Update-ChatConsoleFiles $H
}

function Update-ChatConsoleStaging {
    # Copies that have finished, or failed, since the last look - the draft
    # is saved again with them, or a crash now would sweep them away. A file
    # x'd out while it was still copying is deleted once the copy lets go.
    param($H)
    $C = $H.Con
    $moved = $false
    foreach ($s in @($C.Staged)) {
        if (-not $s.Task -or -not $s.Task.IsCompleted) { continue }
        if ($s.Task.IsFaulted) { $s.Error = $s.Task.Exception.GetBaseException().Message }
        $s.Task = $null
        $moved = $true
    }
    if ($C.Trash) {
        foreach ($x in @($C.Trash)) {
            if ($x.Task -and -not $x.Task.IsCompleted) { continue }
            Remove-Item -LiteralPath $x.Dir -Recurse -Force -EA SilentlyContinue
            [void]$C.Trash.Remove($x)
        }
    }
    if ($moved) { $C.Dirty = Get-Date; Update-ChatConsoleFiles $H }
}

function Update-ChatConsoleFiles {
    # the files going with the prompt, as chips with their size and a x
    param($H)
    $C = $H.Con
    $C.Files.Children.Clear()
    foreach ($s in @($C.Staged)) {
        $kb = if ($s.Size -ge 1MB) { '{0:N1} MB' -f ($s.Size / 1MB) } else { '{0:N0} KB' -f [Math]::Max(1, $s.Size / 1KB) }
        $what = if ($s.Error) { " - $($s.Error)" } elseif ($s.Task) { ' - copying' } else { '' }
        $chip = [System.Windows.Controls.Border]::new()
        $chip.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $chip.BorderThickness = [System.Windows.Thickness]::new(1)
        $chip.BorderBrush = Get-ChatOverlayBrush $(if ($s.Error) { 'error' } else { 'inputEdge' })
        $chip.Padding = [System.Windows.Thickness]::new(7, 1, 3, 2)
        $chip.Margin = [System.Windows.Thickness]::new(0, 0, 5, 3)
        $sp = [System.Windows.Controls.StackPanel]::new()
        $sp.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        [void]$sp.Children.Add((New-ChatOverlayText "$($s.Name) ($kb)$what" $(if ($s.Error) { 'error' } else { 'text' }) 11.5))
        $x = New-ChatConsoleButton ([string][char]0x00D7) { param($o, $e) $e.Handled = $true; Remove-ChatConsoleFile $script:ChatOverlayHost $o.Tag } -Small -Tag $s -Tip 'Leave this file out'
        $x.BorderThickness = [System.Windows.Thickness]::new(0)
        $x.Margin = [System.Windows.Thickness]::new(3, 0, 0, 0)
        [void]$sp.Children.Add($x)
        $chip.Child = $sp
        [void]$C.Files.Children.Add($chip)
    }
    $n = @($C.Staged).Count
    $bytes = (@($C.Staged) | ForEach-Object { [int64]$_.Size } | Measure-Object -Sum).Sum
    if ($n -gt $script:ChatqAttachWarnCount -or $bytes -gt $script:ChatqAttachWarnBytes) {
        [void]$C.Files.Children.Add((New-ChatOverlayText 'that is a lot for one run - every file costs context, and usage' 'warn' 11))
    }
}

function Remove-ChatConsoleFile {
    param($H, $Staged)
    $C = $H.Con
    [void]$C.Staged.Remove($Staged)
    # still being copied: the copy holds the file open, so it goes when done
    if ($Staged.Task -and -not $Staged.Task.IsCompleted) {
        if (-not $C.Trash) { $C.Trash = [System.Collections.Generic.List[object]]::new() }
        $C.Trash.Add(@{ Dir = $Staged.Dir; Task = $Staged.Task })
    }
    elseif ($Staged.Dir -and (Test-Path -LiteralPath $Staged.Dir)) { Remove-Item -LiteralPath $Staged.Dir -Recurse -Force -EA SilentlyContinue }
    $C.Dirty = Get-Date
    Update-ChatConsoleFiles $H
}

function Invoke-ChatConsoleBrowse {
    # the folder picker, over the console; the console is not redrawn under it
    param($H)
    $C = $H.Con
    $d = [System.Windows.Forms.FolderBrowserDialog]::new()
    $d.Description = 'The folder the new chat works in'
    if ($C.FolderBox.Text -and (Test-Path -LiteralPath $C.FolderBox.Text)) { $d.SelectedPath = $C.FolderBox.Text }
    $own = [System.Windows.Forms.NativeWindow]::new()
    $C.Modal = $true
    try {
        $own.AssignHandle($C.Hwnd)
        if ($d.ShowDialog($own) -eq [System.Windows.Forms.DialogResult]::OK) { $C.FolderBox.Text = $d.SelectedPath }
    }
    finally { $C.Modal = $false; try { $own.ReleaseHandle() } catch {}; $d.Dispose() }
}

function Invoke-ChatConsoleSend {
    <#
    Send: the prompt, its files and the choices made, to the chat picked or
    a new one - New-ChatqJob, the same job chatq makes - then the watcher
    asked for without a wait. The box empties for the next one; the chat
    stays picked.
    #>
    param($H)
    $C = $H.Con
    $t = $C.Target
    # the second click of a double-click finds the box it just emptied
    if (-not $C.Prompt.Text.Trim() -and $C.SentAt -and ((Get-Date) - $C.SentAt).TotalSeconds -lt 2) { return }
    if (-not $t) { Set-ChatConsoleStatus $H 'pick a chat on the left, or + New chat' 'warn'; return }
    if (@($C.Staged | Where-Object { $_.Task }).Count) { Set-ChatConsoleStatus $H 'a file is still being copied - a moment' 'warn'; return }
    if (@($C.Staged | Where-Object { $_.Error }).Count) { Set-ChatConsoleStatus $H 'a file could not be copied - x it out, or drop it again' 'warn'; return }
    $plan = ConvertFrom-ChatConsoleWhen $C.When $(if ($C.WhenBox) { $C.WhenBox.Text } else { $C.WhenValue })
    if ($plan.Error) { Set-ChatConsoleStatus $H $plan.Error 'warn'; return }
    $text = $C.Prompt.Text
    $src = @{ Files = @($C.Staged | ForEach-Object { $_.Path }) }
    # the job list read afresh for its number: a shell may have queued one
    # since the last pass
    # Claude's modes and models mean nothing to Codex, which runs in the
    # sandbox it last used: -m opus would fail the run
    $codex = $t.Provider -eq 'codex'
    $how = @{
        Prompt = $text; Mode = $(if ($codex) { '' } else { $C.Mode }); Model = $(if ($codex) { '' } else { $C.Model })
        NotBefore = $plan.NotBefore; First = $plan.First; SendNow = $plan.SendNow; Sources = $src; MoveSources = $true
    }
    if ($t.Kind -eq 'new') {
        $made = New-ChatqJob -Kind new -Cwd $C.FolderBox.Text -Title $C.NameBox.Text.Trim() @how
    }
    else {
        $got = Get-ChatConsoleRow $H $t
        if (-not $got) { Set-ChatConsoleStatus $H (Get-ChatConsoleMissingSay $t) 'warn'; return }
        $made = New-ChatqJob -Row $got.Row -Info $got.Info -Rule 'picked' @how
    }
    if ($made.Error) { Set-ChatConsoleStatus $H $made.Error 'warn'; return }
    $j = $made.Job
    # what was staged went in with it
    foreach ($s in @($C.Staged)) { if ($s.Dir -and (Test-Path -LiteralPath $s.Dir)) { Remove-Item -LiteralPath $s.Dir -Recurse -Force -EA SilentlyContinue } }
    $C.Staged.Clear()
    $C.Prompt.Text = ''
    if ($t.Kind -eq 'new') {
        $folders = @(@($j.cwd) + @($C.State.folders | Where-Object { $_ -and $_ -ne $j.cwd }) | Select-Object -First 10)
        $C.State.folders = $folders
        $C.NameBox.Text = ''
        # the new chat is the one picked now, for what goes to it next
        $C.Target = @{ Kind = 'chat'; Id = $j.sessionId; Provider = 'claude'; Title = $j.title; Project = (Split-Path ([string]$j.cwd).TrimEnd('\', '/') -Leaf); Cwd = $j.cwd; Path = $j.path; Live = $null }
    }
    $C.Request = Request-ChatqWatcher -Wake poke
    $C.Sel = $j.id
    $C.SentAt = Get-Date
    $C.Confirm = @{}
    Save-ChatConsoleDraft $H
    Update-ChatConsoleTarget $H
    Update-ChatConsoleFiles $H
    $miss = if (@($made.Missed).Count) { " - could not take in $(@($made.Missed).Count) file(s)" } else { '' }
    Set-ChatConsoleStatus $H "queued #$($j.seq) for '$($j.title)'$(if (@($made.Files).Count) { " with $(Format-ChatqAttachSummary @($made.Files))" })$miss" $(if ($miss) { 'warn' } else { 'dim' })
    Update-ChatConsoleNow $H
}

function Get-ChatConsoleMissingSay {
    # why a chat picked has no row to send to: a new chat not made yet - its
    # first run makes it - or one the index has not seen
    param($Target)
    $first = @(Get-ChatqJobs | Where-Object { $_.kind -eq 'new' -and $_.sessionId -eq $Target.Id -and $_.state -in 'queued', 'running' })[0]
    if ($first) { return "this chat is made when #$($first.seq) runs - write to it after that" }
    return "that chat is not in the index yet - chatindex in a shell, or wait for the console's own sync"
}

function Invoke-ChatConsoleContinue {
    # "Continue from where you left off." for each chat the limit or a 529
    # stopped - one New-ChatqJob each, in turn, then the watcher asked once.
    # A chat that already has one waiting or running is left alone: the list
    # is redrawn only on the next pass, and a second click would queue it twice.
    param($H, [object[]]$Items)
    $n = 0
    $had = 0
    $fails = @()
    $taken = @{}
    foreach ($j in @(Get-ChatqJobs)) { if ($j.state -in 'queued', 'running' -and $j.sessionId) { $taken[[string]$j.sessionId] = $true } }
    foreach ($i in @($Items)) {
        if (-not $i) { continue }
        if ($taken[[string]$i.Id]) { $had++; continue }
        $row = Get-ChatqRowById $i.Id 'claude' $i.Path $i.Cwd
        if (-not $row) { $fails += "$($i.Title): not found"; continue }
        $made = New-ChatqJob -Row $row -Kind continue -Rule 'continue'
        if ($made.Error) { $fails += "$($i.Title): $($made.Error)" } else { $n++; $taken[[string]$i.Id] = $true }
    }
    if ($n) { $H.Con.Request = Request-ChatqWatcher -Wake poke }
    $say = "queued $n continue$(if ($n -ne 1) { 's' }) - each goes when its limit is over$(if ($had) { "; $had had one already" })"
    Set-ChatConsoleStatus $H $(if ($fails) { "$say; $($fails -join '; ')" } else { $say }) $(if ($fails) { 'warn' } else { 'dim' })
    Update-ChatConsoleNow $H
}

function Update-ChatConsoleNow {
    # a pass now, not in up to 2 s: what was just queued shows at once, and
    # the rows it answers - a cut-off chat continued - leave the list
    param($H)
    $H.Con.JobsSig = $null
    $H.Con.Sigs = @{}
    try { Update-ChatOverlayView $H (Invoke-ChatOverlayCycle $H.Ctx -Peek) } catch { Write-ChatOverlayLog "console: $($_.Exception.Message)" }
    Update-ChatConsole $H
}

function Update-ChatConsoleQueue {
    # the jobs: open ones and those that ended in the last day, newest work
    # first, each with where it stands; the one picked in full beside them
    param($H)
    $C = $H.Con
    if (-not $C.Queue) { return }
    $eta = @{}
    foreach ($r in @($H.Snap.rows)) { if ($r -and $r.job -and $r.job.eta) { $eta[[int]$r.job.seq] = [string]$r.job.eta } }
    $day = (Get-Date).AddDays(-1)
    $list = @($C.Jobs | Where-Object { $_.state -in 'queued', 'running', 'needs-input' -or ((ConvertTo-ChatqDate $_.endedAt) -gt $day) })
    $key = (@($list | ForEach-Object { "$($_.id)=$($_.state)=$($eta[[int]$_.seq])" }) -join ';') + "|$($C.Sel)|$($C.ShowLog)|$(@($C.Confirm.Keys) -join ',')"
    if ($key -eq $C.Sigs.Queue) { return }
    $C.Sigs.Queue = $key
    $C.Queue.Children.Clear()
    if (-not $list) { [void]$C.Queue.Children.Add((New-ChatOverlayText 'nothing queued' 'faint' 12)) }
    $open = @($list | Where-Object { $_.state -in 'queued', 'running', 'needs-input' })
    $shut = @($list | Where-Object { $_.state -notin 'queued', 'running', 'needs-input' } | Sort-Object { ConvertTo-ChatqDate $_.endedAt } -Descending)
    foreach ($j in @($open + $shut)) {
        $st = Get-ChatConsoleJobStatus $j $eta[[int]$j.seq]
        $b = [System.Windows.Controls.Border]::new()
        $b.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $b.Padding = [System.Windows.Thickness]::new(6, 2, 6, 3)
        $b.Cursor = [System.Windows.Input.Cursors]::Hand
        $b.Tag = $j.id
        $b.Background = if ($C.Sel -eq $j.id) { Get-ChatOverlayBrush 'select' } else { [System.Windows.Media.Brushes]::Transparent }
        $d = [System.Windows.Controls.DockPanel]::new()
        $right = New-ChatOverlayText $st.Text $st.Tone 11 -Trim
        $right.MaxWidth = 260
        $right.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        [System.Windows.Controls.DockPanel]::SetDock($right, [System.Windows.Controls.Dock]::Right)
        [void]$d.Children.Add($right)
        $l = [System.Windows.Controls.TextBlock]::new()
        $l.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $r1 = [System.Windows.Documents.Run]::new("#$($j.seq)  ")
        $r1.Foreground = Get-ChatOverlayBrush 'faint'
        $l.Inlines.Add($r1)
        $r2 = [System.Windows.Documents.Run]::new("$(if ($j.kind -eq 'new') { 'new: ' })$($j.title)")
        $r2.Foreground = Get-ChatOverlayBrush 'text'
        $l.Inlines.Add($r2)
        $first = if ($j.kind -eq 'continue' -or $j.retryAs -eq 'continue') { 'continue' } else { (Get-ChatqPromptStats ([string](Read-ChatqPrompt $j))).First }
        if ($first) { $r3 = [System.Windows.Documents.Run]::new("   $first"); $r3.Foreground = Get-ChatOverlayBrush 'dim'; $l.Inlines.Add($r3) }
        [void]$d.Children.Add($l)
        $b.Child = $d
        # another job picked: a Remove asked about the last one no longer stands
        $b.add_MouseLeftButtonUp({ param($s, $e) $H = $script:ChatOverlayHost; $H.Con.Sel = [string]$s.Tag; $H.Con.ShowLog = $false; $H.Con.Confirm = @{}; $H.Con.Sigs.Queue = $null; Update-ChatConsoleQueue $H })
        [void]$C.Queue.Children.Add($b)
    }
    Show-ChatConsoleDetails $H
}

function Show-ChatConsoleDetails {
    # the job picked: where it stands, what came of it, the buttons for what
    # can be done to it now, its prompt - editable while it waits - and its
    # reply or log
    param($H)
    $C = $H.Con
    # A prompt being edited outlives the redraw: any job's state or send
    # time moving redraws this pane, and the edit went with it. Kept while
    # it differs from the file and is for the same job.
    $typed = $null
    if ($C.EditBox -and $C.EditFor -and $C.EditBox.Text -ne $C.EditWas) { $typed = @{ For = $C.EditFor; Text = $C.EditBox.Text; Was = $C.EditWas } }
    $C.EditBox = $null
    $C.EditFor = $null
    $C.Details.Children.Clear()
    $j = if ($C.Sel) { @($C.Jobs | Where-Object { $_.id -eq $C.Sel })[0] } else { $null }
    if (-not $j) { [void]$C.Details.Children.Add((New-ChatOverlayText 'pick a job to see it in full' 'faint' 12)); return }
    $add = { param($x) [void]$C.Details.Children.Add($x) }
    $h1 = New-ChatOverlayText "#$($j.seq)  $($j.title)" 'text' 13 -Bold -Trim
    & $add $h1
    $st = Get-ChatConsoleJobStatus $j $null
    $w = New-ChatOverlayText "$($st.Text)" $st.Tone 11.5
    $w.TextWrapping = [System.Windows.TextWrapping]::Wrap
    & $add $w
    & $add (New-ChatOverlayText "$($j.provider) $($script:ChatqDot) $($j.kind)$(if ($j.mode) { " $($script:ChatqDot) $($j.mode)" }) $($script:ChatqDot) $($j.cwd)" 'faint' 11 -Trim)
    $acts = [System.Windows.Controls.WrapPanel]::new()
    $acts.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
    $act = { param($label, $what, $tip) [void]$acts.Children.Add((New-ChatConsoleButton $label { param($s, $e) Invoke-ChatConsoleJobAction $script:ChatOverlayHost ([string]$s.Tag.Id) ([string]$s.Tag.Act) } -Small -Tag @{ Id = $j.id; Act = $what } -Tip $tip)) }
    switch ([string]$j.state) {
        'queued' {
            & $act 'Try now' 'now' 'Stop waiting for a reset: ask now, and send if the limit is over'
            & $act 'First' 'first' 'To the front of the queue'
            & $act $(if ($C.Confirm[$j.id]) { 'Remove - sure?' } else { 'Remove' }) 'remove' 'Drop it, its prompt and its files'
        }
        'running' { & $act 'Cancel' 'cancel' 'Stop the run - it is marked failed' }
        default {
            & $act 'Requeue' 'requeue' 'Send it again - as "continue" if its prompt already reached the chat'
            & $act $(if ($C.Confirm[$j.id]) { 'Remove - sure?' } else { 'Remove' }) 'remove' 'Drop it, its prompt and its files'
        }
    }
    if ($j.sessionId) { & $act 'Write to this chat' 'write' 'Pick this chat to write to' }
    if (Test-Path -LiteralPath (Join-Path $script:ChatqLogDir "$($j.id).jsonl")) { & $act $(if ($C.ShowLog) { 'Reply' } else { 'Log' }) 'log' 'What the run did' }
    & $add $acts
    if ($j.state -eq 'queued' -and $j.kind -ne 'continue' -and $j.retryAs -ne 'continue') {
        $ed = New-ChatConsoleInput -Multi -Tip 'Edits count until it sends'
        $ed.MinHeight = 60
        $ed.MaxHeight = 220
        $C.EditWas = [string](Read-ChatqPrompt $j)
        $ed.Text = if ($typed -and $typed.For -eq $j.id) { $typed.Text } else { $C.EditWas }
        $C.EditBox = $ed
        $C.EditFor = $j.id
        & $add $ed
        $sv = New-ChatConsoleButton 'Save the prompt' { param($s, $e) Invoke-ChatConsoleJobAction $script:ChatOverlayHost ([string]$s.Tag) 'save' } -Small -Tag $j.id
        $sv.Margin = [System.Windows.Thickness]::new(0, 4, 0, 6)
        $sv.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        & $add $sv
    }
    $files = @(Get-ChatqAttachments $j)
    if ($files) { & $add (New-ChatOverlayText (Format-ChatqAttachSummary $files) 'faint' 11 -Trim) }
    # the log read once per length: a long run's is megabytes of JSON
    $lp = Join-Path $script:ChatqLogDir "$($j.id).jsonl"
    $ll = try { ([System.IO.FileInfo]::new($lp)).Length } catch { 0 }
    if (-not $C.LogCache) { $C.LogCache = @{} }
    $lc = $C.LogCache[$j.id]
    if (-not $lc -or $lc.Len -ne $ll) { $lc = @{ Len = $ll; Entries = @(Get-ChatqLogEntries $j -MaxBytes 2MB) }; $C.LogCache[$j.id] = $lc }
    if ($C.ShowLog) {
        foreach ($e in @($lc.Entries)) {
            $tone = switch ($e.Type) { 'text' { 'text' } 'denied' { 'warn' } 'error' { 'error' } default { 'faint' } }
            $prefix = switch ($e.Type) { 'tool' { '> ' } 'denied' { '! denied ' } 'error' { '! ' } 'result' { '= ' } default { '' } }
            $tb = New-ChatOverlayText "$prefix$($e.Text)" $tone 11.5
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tb.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
            & $add $tb
        }
    }
    elseif ($j.result) {
        # the reply: the log's last words, else the excerpt the job kept
        $reply = @($lc.Entries | Where-Object { $_.Type -eq 'text' } | ForEach-Object { $_.Text })
        $text = if ($reply) { $reply[-1] } elseif ($j.result.excerpt) { [string]$j.result.excerpt } else { '' }
        if ($text) {
            $tb = New-ChatOverlayText $text 'text' 12
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            & $add $tb
        }
        if ($j.result.PSObject.Properties['stale'] -and $j.result.stale) { & $add (New-ChatOverlayText 'the chat is open in VS Code - reload that window to see this there' 'warn' 11) }
    }
    foreach ($h in @($j.history | Select-Object -Last 6)) {
        $at = ConvertTo-ChatqDate $h.at
        & $add (New-ChatOverlayText "$(if ($at) { $at.ToString('MM-dd HH:mm') })  $($h.state)  $($h.why)" 'faint' 10.5 -Trim)
    }
}

function Invoke-ChatConsoleJobAction {
    # what a button in the details does - the same core chatqrm, chatqrun
    # and chatq <n> call
    param($H, [string]$Id, [string]$Act)
    $C = $H.Con
    $j = Find-ChatqJob $Id
    if (-not $j) { Set-ChatConsoleStatus $H 'that job is gone' 'warn'; $C.JobsSig = $null; return }
    $say = ''
    switch ($Act) {
        'now' { Set-ChatqJobFirst $j; $C.Request = Request-ChatqWatcher -Wake now; $say = "#$($j.seq) tried now - it sends if nothing holds it" }
        'first' { Set-ChatqJobFirst $j; $C.Request = Request-ChatqWatcher -Wake poke; $say = "#$($j.seq) moved to the front" }
        'remove' {
            # Twice, and on purpose: a first click only asks, and the second
            # counts from 0.4 s to 5 s after it - the second half of a
            # double-click lands on "sure?" at once, and an old ask is stale.
            $asked = $C.Confirm[$j.id]
            $age = if ($asked) { ((Get-Date) - $asked).TotalSeconds } else { -1 }
            if ($age -ge 0 -and $age -lt 0.4) { return }
            # the ask's time is taken again once the pane is redrawn: the
            # second half of a double-click waits in the queue while it draws,
            # and a slow redraw would otherwise use up the 0.4 s
            if ($age -lt 0 -or $age -gt 5) { $C.Confirm = @{ $j.id = (Get-Date) }; $C.Sigs.Queue = $null; Update-ChatConsoleQueue $H; $C.Confirm[$j.id] = Get-Date; return }
            $C.Confirm.Remove($j.id)
            if (Remove-ChatqJob $j 'the console') { $say = "removed #$($j.seq)"; $C.Sel = $null } else { $say = "#$($j.seq) is running - cancel it first" }
        }
        'cancel' {
            $say = switch (Stop-ChatqJobRun $j) {
                'cancelling' { "#$($j.seq) cancelling - stopped within a few seconds" }
                'not running' { "#$($j.seq) had already ended - $($j.state)" }
                default { "#$($j.seq) was left running by a watcher that stopped - marked failed" }
            }
        }
        'requeue' {
            $r = Reset-ChatqJob $j
            if ($r.Error) { $say = $r.Error } else { $C.Request = Request-ChatqWatcher -Wake poke; $say = "#$($j.seq) queued again$(if ($r.Landed) { ', as "continue" - the prompt already reached the chat' })" }
        }
        'write' {
            $C.Target = @{ Kind = 'chat'; Id = [string]$j.sessionId; Provider = [string]$j.provider; Title = [string]$j.title; Project = (Split-Path ([string]$j.cwd).TrimEnd('\', '/') -Leaf); Cwd = $j.cwd; Path = $j.path; Live = $null }
            $C.Sigs.Chats = $null
            Update-ChatConsoleTarget $H
            [void]$C.Prompt.Focus()
            return
        }
        'log' { $C.ShowLog = -not $C.ShowLog; $C.Sigs.Queue = $null; Update-ChatConsoleQueue $H; return }
        'save' {
            if ($j.state -ne 'queued') { $say = "#$($j.seq) is $($j.state) - an edit now changes nothing"; break }
            $p = Get-ChatqPromptPath $j
            $old = if (Test-Path -LiteralPath $p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) } else { '' }
            $head = [regex]::Match($old, '^\s*<!--\s*chatq:.*?-->\s*', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            Save-ChatqText $p ($head + $C.EditBox.Text)
            $say = "#$($j.seq) prompt saved"
        }
    }
    $C.Confirm.Clear()
    $C.JobsSig = $null
    $C.Jobs = @(Get-ChatqJobs)
    $C.Sigs.Queue = $null
    Update-ChatConsoleQueue $H
    if ($say) { Set-ChatConsoleStatus $H $say }
}

function Register-ChatConsoleHotkey {
    # config consoleHotkey (Ctrl+Alt+Shift+Q): opens the console. Taken by
    # another program, it is logged and the tray item still works.
    param($H)
    $text = [string]$H.Ctx.Config.consoleHotkey
    if ($H.ConHotkey -and $H.ConHotkeyText -eq $text) { return }
    if ($H.ConHotkey) { $H.ConHotkey.Dispose(); $H.ConHotkey = $null }
    $H.ConHotkeyText = $text
    $k = try { ConvertFrom-ChatOverlayHotkey $text } catch { Write-ChatOverlayLog "console hotkey: $($_.Exception.Message)"; $null }
    if (-not $k) { return }
    $hk = [ChatOverlayHotkey]::new()
    $hk.add_Pressed({ Invoke-ChatOverlayVerb 'console' })
    if ($hk.Register([uint32]$k.Mods, [uint32]$k.Vk)) { $H.ConHotkey = $hk }
    else { $hk.Dispose(); Write-ChatOverlayLog "console hotkey $text is taken by another program" }
}

#endregion

#region overlay: macOS panel ---------------------------------------------------
# UNTESTED - nothing here has run on a Mac yet; TESTING.md has the checklist.
# JavaScript for Automation, run by osascript, which every Mac has: a
# borderless floating NSPanel that never activates, and a menu bar item. It
# draws data/overlay.json, which the pwsh host beside it rewrites. The pure
# part (CO) is checked under node by tests/overlay-mac-check.js; everything
# that touches Cocoa is inside run(). ASCII only, and no ?. or ?? - older
# JavaScriptCore reads neither.

$script:ChatOverlayJxa = @'
var CO = {
  clamp: function (v, lo, hi) { return Math.max(lo, Math.min(hi, v)); },
  pad: function (n) { return (n < 10 ? '0' : '') + n; },
  until: function (ms, now) {
    if (!ms) { return ''; }
    var s = (ms - now) / 1000;
    if (s <= 0) { return 'reset'; }
    if (s >= 86400) {
      var d = new Date(ms);
      return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()] + ' ' + CO.pad(d.getHours()) + ':' + CO.pad(d.getMinutes());
    }
    var m = Math.floor(s / 60);
    if (m >= 60) { return Math.floor(m / 60) + 'h ' + (m % 60) + 'm'; }
    if (m >= 1) { return m + 'm'; }
    return Math.ceil(s) + 's';
  },
  colors: {
    waiting: [0.96, 0.73, 0.26], 'needs-input': [0.96, 0.73, 0.26], busy: [0.30, 0.76, 0.54],
    running: [0.31, 0.63, 1.0], idle: [0.50, 0.53, 0.56], queued: [0.71, 0.55, 1.0], cutoff: [1.0, 0.54, 0.30],
    text: [0.91, 0.92, 0.93], dim: [0.60, 0.63, 0.65], faint: [0.42, 0.44, 0.47], project: [0.54, 0.72, 1.0],
    normal: [0.35, 0.66, 0.90], warning: [0.96, 0.73, 0.26], critical: [1.0, 0.36, 0.36],
    warn: [0.96, 0.73, 0.26], error: [1.0, 0.48, 0.45], unlocked: [0.31, 0.63, 1.0]
  },
  // the light look: the same meanings, darker to read on white
  light: {
    waiting: [0.79, 0.54, 0.0], 'needs-input': [0.79, 0.54, 0.0], busy: [0.10, 0.56, 0.30],
    running: [0.12, 0.44, 0.92], idle: [0.55, 0.58, 0.62], queued: [0.51, 0.31, 0.87], cutoff: [0.74, 0.30, 0.0],
    text: [0.12, 0.14, 0.16], dim: [0.34, 0.38, 0.42], faint: [0.55, 0.58, 0.62], project: [0.04, 0.41, 0.85],
    normal: [0.04, 0.41, 0.85], warning: [0.75, 0.53, 0.0], critical: [0.81, 0.13, 0.18],
    warn: [0.60, 0.40, 0.0], error: [0.81, 0.13, 0.18], unlocked: [0.04, 0.41, 0.85]
  },
  // config.theme - dark, light or system - to the look drawn
  themeOf: function (config, systemDark) {
    var t = (config && config.theme) || 'dark';
    if (t === 'system') { return systemDark ? 'dark' : 'light'; }
    return t === 'light' ? 'light' : 'dark';
  },
  opacityOf: function (config) { return CO.clamp((config && config.opacity) || 0.94, 0.3, 1); },
  color: function (name, theme) {
    var p = theme === 'light' ? CO.light : CO.colors;
    return p[name] || p.text;
  },
  bar: function (pct) {
    var n = Math.round(CO.clamp(pct, 0, 100) / 10);
    return new Array(n + 1).join('\u2588') + new Array(11 - n).join('\u2591');
  },
  stale: function (snap, now, ms) { return !snap || !snap.at || (now - snap.at) > ms; },
  // the panel as lines of runs: [[text, colour name, bold], ...]
  lines: function (snap, now, locked, hotkey) {
    var out = [], i, j;
    var usage = (snap && snap.header && snap.header.usage) || [];
    var bars = !!(snap && snap.config && snap.config.usageView === 'bars');
    for (i = 0; i < usage.length; i++) {
      var u = usage[i];
      if (!bars) {
        // one line a provider, when its figure is from at the end
        var line = [[(u.provider + '        ').slice(0, 8), u.stale ? 'faint' : 'text', true]];
        for (j = 0; j < u.windows.length; j++) {
          var v = u.windows[j];
          if (j) { line.push([' \u00B7 ', 'faint', false]); }
          line.push([v.label + ' ', 'dim', false]);
          line.push([v.percent + '%', u.stale ? 'faint' : (v.limited ? 'critical' : (v.severity === 'warning' || v.severity === 'critical' ? v.severity : 'text')), true]);
        }
        if (u.status) { line.push(['   ' + u.status, 'faint', false]); }
        out.push(line);
        continue;
      }
      for (j = 0; j < u.windows.length; j++) {
        var w = u.windows[j];
        var name = j === 0 ? u.provider : '';
        out.push([[(name + '       ').slice(0, 7), u.stale ? 'faint' : 'text', true],
          [(w.label + '            ').slice(0, 12), 'dim', false],
          [CO.bar(w.percent), u.stale ? 'faint' : w.severity, false],
          [('    ' + w.percent + '%').slice(-5), w.limited ? 'critical' : 'text', true],
          ['  ' + CO.until(w.resetsAt, now), 'dim', false],
          // when the figure is from, on the provider's first row
          [j === 0 && u.status ? '   ' + u.status : '', 'faint', false]]);
      }
    }
    var notes = (snap && snap.header && snap.header.notes) || [];
    for (i = 0; i < notes.length; i++) { out.push([[notes[i].text, notes[i].tone === 'dim' ? 'faint' : notes[i].tone, false]]); }
    if (usage.length || notes.length) { out.push([['', 'faint', false]]); }
    var rows = (snap && snap.rows) || [];
    var max = (snap && snap.config && snap.config.maxRows) || 8;
    for (i = 0; i < rows.length && i < max; i++) {
      var r = rows[i];
      out.push([[r.status === 'queued' ? '\u25CB ' : '\u25CF ', r.status, false],
        [r.project ? r.project + '  ' : '', 'project', true],
        [r.title + '   ', 'text', false],
        [r.stateText, r.rank === 0 ? 'warn' : 'dim', false]]);
      if (r.prompt && (!snap.config || snap.config.prompts !== false)) { out.push([['    ' + r.prompt, 'dim', false]]); }
    }
    if (rows.length > max) { out.push([['+' + (rows.length - max) + ' more', 'faint', false]]); }
    if (!rows.length) { out.push([['no chats open', 'faint', false]]); }
    if (!locked) { out.push([['unlocked - drag to move, Lock in the menu bar item', 'unlocked', false]]); }
    return out;
  },
  // verbs meant for this panel: newer than its start, each only once
  applyCommands: function (cmds, startedAt, seen) {
    var out = [];
    for (var i = 0; i < (cmds || []).length; i++) {
      var c = cmds[i];
      if (c.at > startedAt && !seen[c.id]) { seen[c.id] = true; out.push(c.verb); }
    }
    return out;
  },
  menuTitle: function (snap) {
    var c = (snap && snap.counts) || {};
    var need = (c.waiting || 0) + (c.needsInput || 0);
    return need ? 'CQ ' + need : 'CQ';
  }
};

function run(argv) {
  ObjC.import('Cocoa');
  var dataDir = argv[0];
  var snapPath = dataDir + '/overlay.json', statePath = dataDir + '/overlay-state.json', cmdPath = dataDir + '/overlay-cmd';
  var startedAt = Date.now(), seen = {}, snap = null, shownKey = '';
  // Cocoa's enum values as numbers: the names the bridge knows vary with
  // the macOS version, the values never do
  var UTF8 = 4, ACCESSORY = 1, BORDERLESS = 0, NONACTIVATING = 128, BUFFERED = 2, FLOATING = 3, TRUNCATE_TAIL = 4;
  var app = $.NSApplication.sharedApplication;
  // no Dock icon and no menu of its own; the first thing, or the icon flashes
  app.setActivationPolicy(ACCESSORY);
  // App Nap would slow the 1 s timer to a crawl while the panel is hidden
  $.NSProcessInfo.processInfo.beginActivityWithOptionsReason(0x00EFFFFF, 'chatoverlay keeps its panel current');

  var read = function (path) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(path, UTF8, null);
    if (!s || s.isNil()) { return null; }
    try { return JSON.parse(s.js); } catch (e) { return null; }
  };
  var write = function (path, text) {
    $.NSString.alloc.initWithUTF8String(text).writeToFileAtomicallyEncodingError(path, true, UTF8, null);
  };
  var append = function (path, text) {
    var fm = $.NSFileManager.defaultManager;
    if (!fm.fileExistsAtPath(path)) { fm.createFileAtPathContentsAttributes(path, $.NSData.data, $()); }
    var fh = $.NSFileHandle.fileHandleForWritingAtPath(path);
    if (!fh || fh.isNil()) { return; }
    fh.seekToEndOfFile;
    fh.writeData($.NSString.alloc.initWithUTF8String(text).dataUsingEncoding(UTF8));
    fh.closeFile;
  };
  var st = read(statePath) || {};
  var locked = st.locked !== false, hidden = st.hidden === true;
  var saveState = function () {
    var f = panel.frame;
    write(statePath, JSON.stringify({ x: f.origin.x, y: f.origin.y + f.size.height, locked: locked, hidden: hidden }));
  };

  var width = 380;
  var screen = $.NSScreen.mainScreen.visibleFrame;
  var panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, width, 60), BORDERLESS | NONACTIVATING, BUFFERED, false);
  panel.setLevel(FLOATING);
  // every Space, stays put through Expose, and over full-screen apps
  panel.setCollectionBehavior(1 | 16 | 256);
  panel.setHidesOnDeactivate(false);
  panel.setOpaque(false);
  panel.setBackgroundColor($.NSColor.clearColor);
  panel.setHasShadow(true);
  panel.setIgnoresMouseEvents(locked);
  panel.setMovableByWindowBackground(true);
  var fx = $.NSVisualEffectView.alloc.initWithFrame($.NSMakeRect(0, 0, width, 60));
  fx.setMaterial(13);
  fx.setBlendingMode(0);
  fx.setState(1);
  fx.setWantsLayer(true);
  fx.layer.setCornerRadius(8);
  fx.layer.setMasksToBounds(true);
  var label = $.NSTextField.alloc.initWithFrame($.NSMakeRect(11, 8, width - 22, 44));
  label.setEditable(false);
  label.setSelectable(false);
  label.setBordered(false);
  label.setDrawsBackground(false);
  label.cell.setLineBreakMode(TRUNCATE_TAIL);
  fx.addSubview(label);
  panel.setContentView(fx);

  var top = (typeof st.y === 'number') ? st.y : screen.origin.y + screen.size.height - 16;
  var left = (typeof st.x === 'number') ? st.x : screen.origin.x + screen.size.width - width - 16;

  var font = $.NSFont.monospacedDigitSystemFontOfSizeWeight(12, 0);
  var bold = $.NSFont.monospacedDigitSystemFontOfSizeWeight(12, 0.3);
  // macOS's own light or dark setting, for theme: system
  var systemDark = function () {
    var s = $.NSUserDefaults.standardUserDefaults.stringForKey('AppleInterfaceStyle');
    return !!(s && !s.isNil() && s.js === 'Dark');
  };
  var look = '';
  var applyLook = function (theme, opacity) {
    var key = theme + '|' + opacity;
    if (key === look) { return; }
    look = key;
    // HUD material for dark; the popover one follows the appearance given
    fx.setMaterial(theme === 'light' ? 6 : 13);
    fx.setAppearance($.NSAppearance.appearanceNamed(theme === 'light' ? 'NSAppearanceNameVibrantLight' : 'NSAppearanceNameVibrantDark'));
    panel.setAlphaValue(opacity);
  };
  var paint = function (now) {
    var cfg = snap && snap.config;
    var theme = CO.themeOf(cfg, cfg && cfg.theme === 'system' ? systemDark() : false);
    applyLook(theme, CO.opacityOf(cfg));
    var lines = CO.lines(snap, now, locked);
    var text = $.NSMutableAttributedString.alloc.init;
    for (var i = 0; i < lines.length; i++) {
      for (var j = 0; j < lines[i].length; j++) {
        var seg = lines[i][j], c = CO.color(seg[1], theme);
        // the values of NSForegroundColorAttributeName and NSFontAttributeName
        var attrs = $.NSDictionary.dictionaryWithObjectsForKeys(
          [$.NSColor.colorWithSRGBRedGreenBlueAlpha(c[0], c[1], c[2], 1), seg[2] ? bold : font],
          ['NSColor', 'NSFont']);
        text.appendAttributedString($.NSAttributedString.alloc.initWithStringAttributes(seg[0], attrs));
      }
      if (i < lines.length - 1) { text.appendAttributedString($.NSAttributedString.alloc.initWithString('\n')); }
    }
    label.setAttributedStringValue(text);
    var h = Math.ceil(label.cell.cellSizeForBounds($.NSMakeRect(0, 0, width - 22, 10000)).height) + 16;
    var f = panel.frame;
    // keep the top edge where it is, as the rows come and go
    var t = f.size.height > 0 && f.origin.y ? f.origin.y + f.size.height : top;
    panel.setFrameDisplay($.NSMakeRect(f.origin.x || left, t - h, width, h), true);
    fx.setFrame($.NSMakeRect(0, 0, width, h));
    label.setFrame($.NSMakeRect(11, 8, width - 22, h - 16));
  };

  var item = $.NSStatusBar.systemStatusBar.statusItemWithLength(-1);
  item.button.setTitle('CQ');
  var menu = $.NSMenu.alloc.init;
  var add = function (title, sel) {
    var m = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(title, sel, '');
    if (sel) { m.setTarget(target); }
    menu.addItem(m);
    return m;
  };
  var apply = function (verb) {
    if (verb === 'lock' || verb === 'unlock' || verb === 'toggle') {
      locked = verb === 'lock' ? true : (verb === 'unlock' ? false : !locked);
      panel.setIgnoresMouseEvents(locked);
    } else if (verb === 'hide' || verb === 'show') {
      hidden = verb === 'hide';
      if (hidden) { panel.orderOut(null); } else { panel.orderFrontRegardless; }
    } else if (verb === 'reset') {
      var s = $.NSScreen.mainScreen.visibleFrame, f = panel.frame;
      panel.setFrameOrigin($.NSMakePoint(s.origin.x + s.size.width - width - 16, s.origin.y + s.size.height - 16 - f.size.height));
    }
    lockItem.setTitle(locked ? 'Unlock to move' : 'Lock');
    hideItem.setTitle(hidden ? 'Show' : 'Hide');
    shownKey = '';
    saveState();
  };
  var lastFrame = '';
  var tick = function () {
    var now = Date.now();
    var s = read(snapPath);
    if (s) { snap = s; }
    // the host that feeds it is gone - never leave a panel behind
    if (now - startedAt > 20000 && CO.stale(snap, now, 20000)) { app.terminate(null); return; }
    var verbs = CO.applyCommands(snap && snap.commands, startedAt, seen);
    for (var i = 0; i < verbs.length; i++) { apply(verbs[i]); }
    item.button.setTitle(CO.menuTitle(snap));
    if (!hidden) { paint(now); }
    var f = panel.frame, key = f.origin.x + ',' + f.origin.y;
    if (lastFrame && key !== lastFrame) { saveState(); }
    lastFrame = key;
  };

  ObjC.registerSubclass({
    name: 'ChatOverlayTarget',
    methods: {
      'tick:': { types: ['void', ['id']], implementation: function (t) { tick(); } },
      'toggleLock:': { types: ['void', ['id']], implementation: function (m) { apply('toggle'); } },
      'toggleHide:': { types: ['void', ['id']], implementation: function (m) { apply(hidden ? 'show' : 'hide'); } },
      'moveHome:': { types: ['void', ['id']], implementation: function (m) { apply('reset'); } },
      'quit:': { types: ['void', ['id']], implementation: function (m) { append(cmdPath, new Date().toISOString() + ' stop\n'); app.terminate(null); } }
    }
  });
  var target = $.ChatOverlayTarget.alloc.init;
  add('VS-code-chat-manager overlay', null);
  menu.addItem($.NSMenuItem.separatorItem);
  var lockItem = add(locked ? 'Unlock to move' : 'Lock', 'toggleLock:');
  var hideItem = add(hidden ? 'Show' : 'Hide', 'toggleHide:');
  add('Move to top right', 'moveHome:');
  menu.addItem($.NSMenuItem.separatorItem);
  add('Quit', 'quit:');
  item.setMenu(menu);

  snap = read(snapPath);
  paint(Date.now());
  if (!hidden) { panel.orderFrontRegardless; }
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(1.0, target, 'tick:', $(), true);
  app.run;
}

if (typeof module !== 'undefined') { module.exports = CO; }
'@

function Start-ChatOverlayMacHost {
    <#
    UNTESTED. The macOS overlay: this pwsh collects every 2 s and a JXA child
    draws the panel and menu bar item from overlay.json. A child that dies
    without a stop is started again, three times in ten minutes at most; the
    child quits by itself when the snapshot goes 20 s stale, so a host killed
    outright leaves no panel behind.
    #>
    Set-StrictMode -Off
    New-ChatqDir $script:ChatqData
    $lock = Lock-ChatOverlay
    if (-not $lock) { Write-ChatOverlayLog "overlay $PID found one already running"; return }
    $S = @{ Child = $null; Starts = [System.Collections.Generic.List[datetime]]::new() }
    $why = $null
    try {
        Set-Content -LiteralPath $script:ChatOverlayPidPath -Value $PID -Encoding ASCII
        Remove-Item -LiteralPath $script:ChatOverlayCmdPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID started ($script:ChatVersion, macOS)"
        $js = $script:ChatOverlayJxa
        $old = if (Test-Path -LiteralPath $script:ChatOverlayMacJsPath) { [System.IO.File]::ReadAllText($script:ChatOverlayMacJsPath) } else { '' }
        if ($old -ne $js) { Save-ChatqText $script:ChatOverlayMacJsPath $js }
        $ctx = New-ChatOverlayContext
        Restore-ChatOverlayUsage $ctx
        # a snapshot on disk before the panel first looks for one
        [void](Invoke-ChatOverlayCycle $ctx)
        $launch = {
            # quoted by hand: Start-Process joins these with spaces as they are
            $S.Child = Start-Process -FilePath 'osascript' -PassThru -ArgumentList @('-l', 'JavaScript',
                "`"$($script:ChatOverlayMacJsPath)`"", "`"$($script:ChatqData)`"")
            $S.Starts.Add((Get-Date))
        }
        # a stop or restart that came in while this was starting, taken by
        # that first pass
        $why = @(@($ctx.Verbs) | Where-Object { $_ -in 'stop', 'restart' })[0]
        if (-not $why) {
            & $launch
            $why = Invoke-ChatOverlayCollectLoop $ctx -OnCycle {
                param($snap)
                if ($S.Child -and $S.Child.HasExited) {
                    $recent = @($S.Starts | Where-Object { $_ -gt (Get-Date).AddMinutes(-10) })
                    if ($recent.Count -ge 3) { Write-ChatOverlayLog 'the panel keeps exiting - stopping; see data/logs/overlay.err'; return 'panel' }
                    Write-ChatOverlayLog "the panel exited ($($S.Child.ExitCode)) - starting it again"
                    & $launch
                }
                return $null
            }
        }
    }
    catch { Write-ChatOverlayLog "overlay failed: $($_.Exception.Message)" }
    finally {
        try { if ($S.Child -and -not $S.Child.HasExited) { $S.Child.Kill() } } catch {}
        try { $lock.Dispose() } catch {}
        Remove-Item -LiteralPath $script:ChatOverlayPidPath -Force -EA SilentlyContinue
        Write-ChatOverlayLog "overlay $PID stopped ($why)"
    }
    if ($why -eq 'restart') { [void](Start-ChatOverlayProcess) }
}

#endregion

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
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
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
elseif (-not $env:CHATQ_WATCHER -and -not $env:CHATQ_OVERLAY -and -not $env:CLAUDECODE -and [Environment]::UserInteractive -and
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
        # chatoverlay -AutoStart on: the same way back after a reboot, and only
        # when asked for - one file read when it is not
        try {
            if ((Test-ChatOverlayAutoStart) -and -not (Test-ChatOverlayAlive) -and (Start-ChatOverlayProcess)) {
                Write-Host '  chatoverlay started' -ForegroundColor DarkGray
            }
        }
        catch {}
    }
}
