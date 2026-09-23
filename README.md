# VS-code-chat-manager

Find, delete, archive and queue prompts for your local AI chats — Claude Code,
Codex and GitHub Copilot Chat — from PowerShell.

[![release](https://img.shields.io/github/v/release/phal40lax78/VS-code-chat-manager)](https://github.com/phal40lax78/VS-code-chat-manager/releases)
[![test](https://github.com/phal40lax78/VS-code-chat-manager/actions/workflows/test.yml/badge.svg)](https://github.com/phal40lax78/VS-code-chat-manager/actions/workflows/test.yml)
[![licence](https://img.shields.io/github/license/phal40lax78/VS-code-chat-manager)](LICENSE)
[![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)](#requirements)
[![sponsor: coming soon](https://img.shields.io/badge/sponsor-coming%20soon-lightgrey?logo=githubsponsors)](FUTURE_WORK.md#sponsorship)

![chatq queueing a prompt for a chat picked by its title, to be sent a minute after the five-hour limit resets](docs/demo-queue.svg)

![chatqlist: two queued prompts, a long one folded to its first line, the usage and when the limit resets](docs/demo-list.svg)

- **Find any chat by part of its title** and Tab-complete it: `chatfind`, `chatrm`, `chatq`.
- **Delete one chat** and everything it leaves on disk, or **archive** it and bring it back later.
- **Queue prompts while the usage limit is hit.** At the reset each chat is resumed in turn, sent its prompt, and run to the end.
- **Waits out `API Error: 529 Overloaded`** by watching status.claude.com, and resumes as soon as Claude Code is back.
- **Tells you how it went:** a desktop toast, your phone through Join or ntfy, or a command of your own.

One file, no modules, nothing to build. It was two tools — chatrm and chatq — and is now one, with one index and one install.

## Install

```powershell
iex (irm https://raw.githubusercontent.com/phal40lax78/VS-code-chat-manager/main/install.ps1)
```

Then type `chat`. The commands are live in the shell you ran that in, and the
line the installer writes into `$PROFILE` brings them back in every new one. It
downloads `VS-code-chat-manager.ps1` to `~/Tools/VS-code-chat-manager`; set
`$env:CHAT_MANAGER_DIR` first to put it somewhere else. The first install builds
the search index, about 30 seconds.

Already have the file? Load it and install:

```powershell
. "$HOME\Tools\VS-code-chat-manager\VS-code-chat-manager.ps1"
chatinstall
```

The leading dot matters: `. file.ps1` loads the commands into this shell, while
`& file.ps1` runs them into a scope that is thrown away. The script notices and
prints the line you meant.

**Coming from chatrm or chatq?** `chatinstall` replaces their profile lines with
this one — both define the same commands. The commands keep their names.

**Updating:** run the one-liner again. It says `updated 0.2.0 -> 0.3.0` or
`unchanged`; an `unchanged` right after a push is the CDN serving the old copy
for a few minutes. A background watcher that is running switches to the new
copy after its current job.

## Contents

- [Commands](#commands)
- [Find and delete](#find-and-delete)
- [Archive and restore](#archive-and-restore)
- [Queue prompts for when the limit resets](#queue-prompts-for-when-the-limit-resets)
- [Alerts](#alerts)
- [Chats open in VS Code, and the extension](#chats-open-in-vs-code-and-the-extension)
- [Codex](#codex)
- [Where it looks, and what it writes](#where-it-looks-and-what-it-writes)
- [How it compares](#how-it-compares)
- [Things to know](#things-to-know)
- [Uninstall](#uninstall) · [Requirements](#requirements) · [Sponsorship](#sponsorship)

## Commands

| | |
|---|---|
| `chatfind "text"` | find chats by title or message; emits objects |
| `chatrm <id>` / `chatrm "title"` | delete a chat, permanently |
| `chatrm ... -Archive` / `chatrestore [<title>]` | put a chat away / list the archive, bring one back |
| `chatclean` | delete ghost chats left behind by the VS Code list |
| `chatq <title\|id> [-Prompt s]` | queue a prompt for that chat; without `-Prompt` an editor tab opens |
| `chatq <title> -Continue` | queue *"Continue from where you left off."* for a chat the limit cut off |
| `chatq <title> -Attach a.png, b.pdf` / `-Paste` | send files, a screenshot or the clipboard with the prompt |
| `chatq <n>` | open queued prompt *n* in the editor — edits count until it is sent |
| `chatqlist [-Board] [-All]` | what is queued, when it sends, what ran, the usage |
| `chatqrm <n> [-Force]` | drop a job; `-Force` cancels a running one |
| `chatqrun [<n>] [-Now] [-First] [-Stop]` | requeue *n*, move it up, stop waiting and try now, stop the watcher |
| `chatqlog <n> [-Raw]` | what a run did |
| `chatqnotify` | desktop, phone and command alerts |
| `chatproviders` / `chatindex` | which tools were found / rebuild the index |
| `chatinstall` / `chatuninstall [-All]` | add to, or drop from, your profile |
| `chat` | cheat sheet |

`chatrm` flags: `-Force` `-AllProjects` `-WaitForIdle` `-DropJobs` `-Archive`
`-Provider claude|copilot|codex`. `chatfind` adds `-Deep` and `-All`.
`chatq` flags: `-WhatIf` (show the pick only), `-Mode auto|acceptEdits|…`,
`-Model <name>`, `-First`, `-At 13:00` / `-In 2h`, `-AllProjects`,
`-Provider claude|codex`, `-Attach <files>`, `-Paste`.

```powershell
chatfind commit | Select-Object Provider, Title, Id, Age
```

## Find and delete

Claude Code, Copilot Chat and Codex keep every chat on disk, and none offers a
per-chat delete: `claude project purge` works a whole project at a time, and
archiving in VS Code only hides a chat. `chatrm` deletes one chat, whichever
tool wrote it.

Type any part of a title — no quotes, no id, no exact spelling — then press Tab:

![The prompt reading "chatrm upload", with the Tab key drawn under it, beside the chat panel's session list, which holds a chat named "Flaky upload test"](docs/demo-1-type.svg)

Tab fills in the whole argument, quoted for you, with the chat's age and which
match it is: `(1d)` since it was last touched, `#1/1` the only chat that matched.
Then Enter:

![The same prompt, now reading "chatrm 'Flaky upload test' (1d) #1/1", with the Enter key drawn under it](docs/demo-2-tab.svg)

![The chat reported deleted, followed by a note that the session list is cached and needs a window reload, while the panel still lists the chat](docs/demo-3-deleted.svg)

The panel still lists it until the window reloads — VS Code caches the session
list (**Ctrl+Shift+P → Developer: Reload Window**, or the
[extension](#chats-open-in-vs-code-and-the-extension) offers a button). After
that it is gone there too:

![The panel's session list after a window reload, no longer listing the deleted chat](docs/demo-4-reloaded.svg)

### Tab

Tab fills in the **whole argument**, not the word under the cursor — for
`chatrm`, `chatfind` and `chatq` alike:

```
chatrm gitign<Tab>     chatrm 'Gitignore file' (21d) #1/2
(down)                 chatrm 'Gitignore rules' (5d) #2/2
```

Tab/down for the next match, Shift+Tab/up for the previous, Enter runs it,
Ctrl+Space opens the full list. Hex matches ids. Subagent chats are left out
unless `-All`, and `chatq` is never offered a Copilot chat. Opt out with
`$ChatNoKeyBindings = $true` before the dot-source.

### Deleting is permanent

Titles match on **substring**, so part of a title is a search, not a choice —
`chatrm Haiku` matches *Haiku ChatGPT Opus Astra*. So a fragment never deletes
on its own:

- **Part of a title:** Enter fills the match in, the way Tab would, and has to be
  pressed again on the full title. Where no key handler reaches — a script,
  `-NoProfile`, no VT — it asks `delete permanently? y / Enter = yes`.
- **A whole title** deletes. Typing all of it is the decision.
- **An id** deletes. An id is exact.
- **`-Force`** skips all of the above.

There is no recycle bin. `chatrm` removes the transcript and everything it
leaves behind — for Claude the sidecar folder (subagents, tool results),
`file-history`, `session-env`, `tasks`, `debug`, the security, telemetry and todo
files, a background job's folder, and its plan file when no other chat in the
project shares it; for Copilot `chatEditingSessions`. The inventory follows
[claude-chats-delete](https://github.com/ataleckij/claude-chats-delete)'s. The
leftovers go only once the transcript is really gone: on Windows a chat a live
window still holds open fails as `LOCKED`, and keeps all of it.

A chat with a prompt queued for it by `chatq` is kept, and the job named;
`-DropJobs` drops the jobs first.

### Scope

Titles match chats of the directory you are standing in — Claude by its project
slug, Copilot and Codex by the folder name — so a sibling repo never answers for
this one. `-AllProjects` widens it. Ids skip scoping: one id is one chat.

### Ghosts

A chat still listed in the panel is one the window is tracking, and the window
writes it back as an empty stub when it reloads. A `FileSystemWatcher` takes that
stub back the moment it lands, and `data/rewritten.txt` remembers the delete for
shells that were not open at the time. `chatclean` sweeps whatever slips past.

### Reloading safely

A reload restarts every extension in the window, so one taken mid-answer loses
that answer. Every delete ends by saying whether now is a safe moment —
`all project chat is idle - safe to reload now` — and `-WaitForIdle` blocks until
it is. A session parked on a permission prompt writes nothing, so the last record
is read as well: an unanswered `tool_use` is a turn still in flight.

## Archive and restore

```powershell
chatrm 'Old experiment' -Archive     # out of the way, not gone
chatrestore                          # what is archived
chatrestore 'Old experiment'         # back where it was
```

- **Claude:** the transcript and its leftovers move into
  `data/archive/claude/<id>/`, with a manifest of where each came from.
  `chatrestore` moves them back — replacing the empty stub the window may have
  written there meanwhile, never a real chat — and the panel shows it after a
  window reload. A chat still open in a window is not archived: it would go on
  writing to the old path.
- **Codex:** through Codex's own `codex archive` / `codex unarchive`, since Codex
  keeps thread state in its own databases. `chatrestore` lists what chatrm
  archived, and threads in Codex's `archived_sessions` folder when it has one.
- **Copilot:** VS Code archives those itself, from its chat list.

`chatuninstall -All` refuses while the archive holds anything — it is the only
copy — unless `-Force`.

## Queue prompts for when the limit resets

The VS Code panel queues a message you send while Claude is working. What it
won't do is hold one you send while the subscription limit is used up: that is
refused with *"You've hit your session limit"* and dropped. So you wait, and at
the reset you go round every chat typing again. `chatq` is the queue for that
moment:

```
PS> chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'
  -> 'Parser rewrite and plugin unification' (2h)  claude · exact title
     auto (as the chat last ran) · D:\src\parser
  queued #1  sends 13:01 (five_hour limit resets 13:00)
```

### Long prompts, files and screenshots

- **Long text, quotes, anything:** leave `-Prompt` off. An editor tab opens on
  the prompt file; paste anything into it — quotes, newlines, `$`, Hangul — then
  save and close it. `chatq <n>` reopens it, and edits count until it sends.
- **Files:** `-Attach a.png, spec.pdf, notes.txt`, with commas — after a space
  the next name would be read as part of the title — or `-Attach .\shots\*.png`.
  They are copied into the job (`data/queue/<id>/`) at once, so the originals
  can move or change; one missing or locked queues nothing.
- **The clipboard:** `-Paste` takes what is on it now — a screenshot, files
  copied in Explorer, or text, which becomes the prompt or goes under the one
  given. Windows only.
- **In the editor tab,** Ctrl+V pastes a screenshot into the prompt. VS Code
  saves it beside the prompt file, in `data/queue/`, and chatq moves it into the
  job. A link to any other file is left as it is: it names that file where it
  is, for the chat to open — or change — there, not a copy of it.
- **Forgot one?** `chatq <n> -Attach shot.png` (or `-Paste`) adds to job *n*
  while it waits.

| | images (png, jpg, gif, webp) | other files |
|---|---|---|
| Claude | named under the prompt; Claude Code opens each with its Read tool and sees the picture | named under the prompt; it reads text, code and PDF |
| Codex | attached with `-i`, as if pasted into the chat | named under the prompt |

What goes under the prompt reads `Attached files - read each one:`, then the
paths. A "continue" sends none — they went with the prompt. `chatqlist` counts
them (`+2 files`); delete one from the job's folder to drop it, and `chatqrm`
removes them with the job. Over 10 files or 20 MB draws a warning: each one
costs context, and usage.

### How it picks the chat

It picks when you queue, not when it sends — you are at the keyboard now and gone
later, so the pick is printed while a wrong one can still be undone
(`chatqrm <n>`).

1. **An id** (hex, at least 6 characters) is that chat.
2. **A title** is matched in this project first — *exact*, then *contains*, then
   *every word in any order* — and in every project only when this one has none.
3. **Nothing matches:** the candidates are this project's chats. It never guesses
   across projects, and standing in no project at all it refuses unless
   `-AllProjects`.
4. **Several candidates:** the newest wins, unless others were active within 5
   hours of it — one limit window — and then the most relevant one does: the
   cosine of character pairs between what you typed (and the prompt) and each
   chat's title and prompts. Pure PowerShell, no model call, Hangul and English
   alike. The runner-up and both scores are printed.

A Copilot chat is found but refused: no CLI can resume one.

### When it sends

- **The reset time** comes from the record Claude writes into the transcript it
  cut off, or from Codex's rate-limit snapshot.
- **A probe goes first:** a throwaway `ok` that saves no session, asked with the
  model the run will use. Sending the real prompt while still limited would
  plant it, and an error after it, in your chat.
- **One job at a time, in queue order** — oldest first, `-First` jumps the line.
  A Claude job never waits behind a Codex limit, nor one account behind another.
- **In the permission mode the chat last used**, `-Mode` overriding it for one
  job, and on the chat's own model, `-Model` overriding that. Anything that would
  ask a question is denied, since nobody is there to answer.
- **Needs input:** a denied tool, or plan mode stopping at a plan, parks the job
  and the queue moves on. `chatqrun <n> -Mode acceptEdits` sends it a "continue"
  in a mode that allows it.
- **A limit hit again mid-run** puts the job back; if its prompt had reached the
  chat, the retry is a "continue", never the prompt twice.
- **`API Error: 529 Overloaded`** (any 5xx) is Anthropic's side. The job goes back
  and chatq watches <https://status.claude.com> every minute, resuming the moment
  Claude Code is `operational` again; one the page never shows is retried after
  1, 2, 5 and 10 minutes, then every 15. One alert, and a reminder at 6 hours.
- **A dropped connection** is retried after 1, 2 and 5 minutes, then fails.
- **An expired login** holds that account's jobs, with one alert to log in
  again; they go once you have.
- **A job that keeps breaking before any reply** gives up after `maxRetries` (5)
  tries in a row. A long task that gets through several limit windows moves on
  each time and is never stopped by this.

Chats you left cut off — by the limit or a 529 — show in `chatqlist`, and
`chatq <title> -Continue` queues one. A continue chatq queued itself is dropped
if the chat moved on meanwhile; one you asked for is always sent.

### Status

- **`chatqlist`** is one line per job, fitted to the terminal; a long prompt
  shows its first line and a size note. Above them, what everything waits on and
  how much of each window is used — `usage  Claude 5h 83% · week 41% (as of
  12:10)` — read from Claude's and Codex's own caches, with their age. Those
  caches only refresh when the tool itself runs, so a reading over an hour old
  is marked `stale`, and the window that is blocked reads `limited`
  (`5h limited`) rather than a percentage from before the limit.
- **`chatq <n>`** opens the whole prompt; edit it until it is sent.
- **`data/logs/jobs.log`** keeps a line per job event — queued, every state it
  moves through, and removals — so a job that left the queue can still be
  accounted for.
- **`chatqlist -Board`** opens `data/queue.md`: **Ctrl+Shift+V** there for VS
  Code's preview, which follows every change the watcher writes.

### The watcher

One per machine, a hidden PowerShell that exits when the queue is empty and is
started again by the next shell after a reboot. While a job is due within 6
hours it keeps the machine from sleeping (the display still turns off, and a
closed lid still sleeps a laptop). `chatqrun -Foreground` runs it in the console
to watch.

## Alerts

```powershell
chatqnotify -ApiKey <Join key> -Device group.phone   # Join
chatqnotify -Ntfy <long random topic>                # ntfy.sh, free
chatqnotify -Command '<PowerShell>'                  # anything else
chatqnotify -Test
```

| channel | |
|---|---|
| desktop toast | on by default (`-Toast off`); nothing leaves the PC |
| Join | keys at <https://joinjoaomgcd.appspot.com>, the **Join API** button; DPAPI-protected on Windows |
| ntfy | published as JSON, so Hangul survives; the topic works as a password — pick a long random one, or your own server with `-NtfyServer` / `-NtfyToken` |
| your command | runs with `$env:CHATQ_EVENT`, `CHATQ_TITLE`, `CHATQ_TEXT`, `CHATQ_PRIORITY`, `CHATQ_JOB`, `CHATQ_PRESENT`; the text never goes on a command line; 30 s at most |

**The phone stays quiet while you are at the PC** — keyboard or mouse used in
the last 5 minutes (`-QuietMinutes`, 0 turns it off) — since the toast already
says it there. `chatqnotify -Test` always goes through.

| event | priority | says |
|---|---|---|
| `chatq · started` | 0 | chat, mode, first line of the prompt |
| `chatq · needs input` | 2 | chat, what was denied, the end of the reply |
| `chatq · done` | 1 | chat, how long, the end of the reply (`asks:` when it ends on a question) |
| `chatq · failed` | 2 | chat, why — including a login gone, or giving up |
| `chatq · limited` | 0 | the limit came back mid-run; when it continues |
| `chatq · overloaded` | 0 | a 529; what status.claude.com says; a reminder after 6 h |

Every title starts `chatq ·`, so a Tasker profile can filter on it. Alerts also
go to `data/logs/alerts.log`. What they carry — the chat title, the end of the
reply — passes through the push service's servers.

## Chats open in VS Code, and the extension

The panel shows one chat, but each VS Code window keeps a `claude` process alive
for every chat opened in it, and clicking one switches back to that process
rather than re-reading the transcript. So a chat still alive in a window won't
show what chatq ran until the window reloads — the run *is* in the transcript.

- **The chat is busy** (you are typing in it, or Claude's own auto-continue is
  running it): chatq waits, checking every 5 minutes.
- **The chat is idle:** it runs, and asks that window to reload — or, with
  `"liveIdle": "stop"` in `data/config.json`, ends the idle process first.

Nothing outside VS Code can reload a window: `workbench.action.reloadWindow` runs
from inside an extension only. `extension/` is that extension, and is optional:

```powershell
Copy-Item -Recurse "$HOME\Tools\VS-code-chat-manager\extension" "$HOME\.vscode\extensions\phal40lax78.chat-manager-reload-2.0.0"
```

Reload once and it is live. After a delete, an archive, or a queued run into a
chat that window still holds, *that* window — matched by its workspace folder —
offers a **Reload** button. `chatManagerReload.signalFile` points it elsewhere
if the script does not live in `~/Tools/VS-code-chat-manager`;
`chatManagerReload.autoReload` skips the question after a delete, never after a
queued run, which can finish at any hour with another chat in the window busy.

## Codex

- A thread is found by its name in `~/.codex/session_index.jsonl`, the name the
  panel shows.
- It is resumed with `codex exec resume <id>` in its own folder and sandbox mode.
- `codex exec` never asks for approval, so a Codex job ends done or failed, never
  needs-input.

## Where it looks, and what it writes

| | |
|---|---|
| Claude Code | `~/.claude/projects/<slug>/<uuid>.jsonl` (`CLAUDE_CONFIG_DIR` honoured) |
| Copilot Chat | `<Code user>/workspaceStorage/<hash>/chatSessions/<uuid>.json` |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` (`CODEX_HOME` honoured) |
| the CLIs | `claude` / `codex` on PATH, else the copy bundled in the VS Code extension; `CHATQ_CLAUDE` / `CHATQ_CODEX` override |

`<Code user>` is `%APPDATA%/Code/User` on Windows, `~/Library/Application
Support/Code/User` on macOS, `~/.config/Code/User` on Linux.

Everything it writes is in `data/` beside the script — the index, tombstones,
the archive, the queue and its logs, the board, `config.json`. No registry keys,
no AppData, no scheduled task; the one line in `$PROFILE` is the only thing
outside the folder.

## How it compares

As of September 2026 — corrections welcome.

| | queues during a limit | picks by title | several chats in turn | phone alerts | waits out a 529 | find & delete | Windows |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **this** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Claude Code's own auto-continue | the one open chat | – | – | – | – | – | ✓ |
| [claude-code-queue](https://github.com/JCSnap/claude-code-queue) | ✓ | by id | ✓ | – | – | – | ? |
| [claude-auto-resume](https://github.com/terryso/claude-auto-resume) | the last task | – | – | – | – | – | via bash |
| `codex queue` (official) | – | exact name | – | – | – | – | ✓ |
| [claude-chats-delete](https://github.com/ataleckij/claude-chats-delete) | – | – | – | – | – | ✓ | – |
| [ClaudeSessionManager](https://github.com/RudraP272812/ClaudeSessionManager) | – | – | – | – | – | ✓ | ✓ |

## Things to know

- **API keys:** `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY` and
  `CODEX_API_KEY` are kept out of the runs, so they use your subscription.
- **Accounts:** a job queued from a shell with `CLAUDE_CONFIG_DIR` or
  `CODEX_HOME` set runs, and is limited, in that account.
- **A limit on one model** (an Opus-only weekly limit) holds up no other model.
- **Plan mode:** a chat last in plan mode only produces a plan; `-Mode auto` lets
  it act.
- **Hooks:** your hooks, guards and `settings.json` allowlist apply to the runs,
  exactly as in the panel.
- **StrictMode** in your profile is fine; the commands turn it off for
  themselves only.
- **Files held open:** transcripts are read `FileShare.ReadWrite | Delete`, since
  Codex holds every rollout open for the life of its window.

## Uninstall

```powershell
chatuninstall        # drop the profile line, stop the watcher, keep the folder
chatuninstall -All   # and delete the folder - not while the archive holds a chat
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7. macOS and Linux need PowerShell 7, and
  are untested so far.
- Claude Code 2.1.259 or later for the queue (`--permission-prompts none`).

## Sponsorship

Not set up yet — the badge above is a placeholder. The options being weighed
are in [FUTURE_WORK.md](FUTURE_WORK.md#sponsorship).

## Licence

MIT
