# Future work

Open problems and deliberate deferrals. Each says why it waits and what closing
it would take.

## Deliver into a live chat instead of beside it

**Shelved in 0.6.0** in favour of showing the chat fresh: after a headless
run the window redraws only its web views, or opens the chat in a tab of its
own, and the chat's old process is ended so the next message starts from
disk (spike S29). That covers what this was wanted for - a window that shows
the run without a whole reload - while the prompt keeps going through the
headless run, where a permission prompt parks the job, a `CLAUDE.md` edit is
done, and the prompt is yours rather than another session's. The notes below
stay for if a live delivery is wanted again.

**Why deferred:** a chat open in a VS Code window shows a chatq run only after
a reload (since 0.5.0 one the window takes by itself when you are away).
Delivering the prompt into the open chat would show it running, live, with no
reload at all. Claude Code's cross-session messaging can do that; what its
documentation (code.claude.com/docs/en/cross-session-messaging, read
2026-09-23) settles, and what is left to try:

- **On by default** from Claude Code 2.1.234 on native Windows; every session
  binds an inbox (a named pipe on Windows). The page never mentions VS Code,
  but panel sessions here export `CLAUDE_CODE_MESSAGING_SOCKET`, so they have
  one too.
- **No token needs handling.** A `claude -p` session can send with the
  `SendMessage` tool by the target's name, and with `crossSessionInbound`
  unset, a receiver in any prompting mode (default, auto, `acceptEdits`)
  delivers a message from a sender that does not bypass permissions. The
  raw pipe, and its `CLAUDE_CODE_MESSAGING_TOKEN`, is documented only for a
  session's own child processes, so a SessionStart hook copying tokens into
  `data/` is not needed and is not the way.
- **An idle receiver starts a turn** with the message; a busy one reads it
  between tool calls, which chatq's busy check already keeps it from.
- **It arrives as from another session, not from you.** It cannot answer a
  permission prompt, and the receiving Claude is told never to change
  settings, `CLAUDE.md` or other configuration because another session asked
  — so a queued prompt that edits `CLAUDE.md` could be turned down where the
  headless run does it.
- **Permission prompts wait for you** in the panel, where the headless run
  denies and parks the job.

Spike S28 in TESTING.md (2026-09-24) settled the rest: the relay finds a panel
chat by the `name` its `~/.claude/sessions/<pid>.json` entry carries beside
its `sessionId`, the idle chat starts the turn within seconds, live, and does
ordinary work asked this way — but a message has to say to do it *here*, or
it is read as a request to answer the sender. A `CLAUDE.md` edit is declined
in the chat, as the framing says.

**To close:**
1. Send: the target's name from its registry entry; a relay `claude -p
   --safe-mode --tools SendMessage` with the prompt on stdin, never as an
   argument (`--allowedTools` takes a list and swallows a prompt placed after
   it); the message opening with what chatq is and that the work is to be done
   in this chat, not answered to the sender.
2. Detect the turn's end for the `done` alert and the queue: the receiving
   transcript's own records after the delivered message (`origin.kind` is
   `peer`, with its `msg_id`), since `claude agents` does not list VS Code
   sessions. A limit or a 529 in that turn requeues a continue as it does now.
3. A prompt that edits `CLAUDE.md`, settings or other configuration is
   declined there; say so in the alert, or send those headless.
4. Deliver this way only into a chat live and idle in a window; everything
   else stays the headless run it is now.

## Deliver into a live Codex chat through `codex queue`

**Why deferred:** found after v0.1.0.
- **The gap today.** chatq never checks whether a Codex thread is open in a
  VS Code window, and every Codex job goes through `codex exec resume`. An open
  Codex panel then goes stale, like a Claude one, and nothing says so.
- **The official way in.** `codex queue --thread <uuid|exact name> --message
  <text>` is in the bundled codex-cli 0.154.0-alpha. It sends
  `thread/queue/add` to Codex's shared local app-server daemon, as a user
  message. It needs no per-session token, and the message is not framed as
  coming from a peer. Claude's inbox pipe (above) has both problems.
- **It doesn't replace the wait.** It queues at once, so chatq still holds the
  prompt until the reset and only then hands it over.

Open questions, from `codex-rs/tui/src/session_queue_commands.rs`:
- Does the VS Code extension's chat run on that shared daemon? If not, the
  message lands in a thread nobody is looking at.
- With no daemon running, it falls back to an embedded app server. Does the
  turn then run, or is it only recorded?
- An older daemon answers "does not support thread/queue/add", so the method
  may still be experimental.
- There is no `--json` event stream. The outcome would have to be read from the
  thread's rollout file.

**To close:**
1. Spike: with a Codex chat open and idle in the panel, run
   `codex queue --thread <id> --message ok`. Does the panel show it and run it?
   Repeat with VS Code closed.
2. Detect a live Codex thread, through the daemon's thread list or the
   extension's process. Deliver to it with `codex queue`, and use
   `codex exec resume` otherwise.
3. Classify the run from the rollout: after the queued message, tail it until
   the turn completes or errors.

## Attachments: what 0.3.0 left out

`-Attach` and `-Paste` shipped in 0.3.0. What they do not cover yet:

- **`-Paste` off Windows.** The clipboard is read through Windows Forms.
  **Why deferred:** nothing here runs macOS or Linux (see the CI entry below).
  **To close:** `osascript` on macOS (`the clipboard as «class PNGf»`), and
  `wl-paste` / `xclip -selection clipboard -t image/png -o` on Linux, each
  writing the same `clip.png`.
- **A Claude image as a real attachment** rather than a path Claude Code opens
  with its Read tool. **Why deferred:** spike S18 showed the path route works —
  the model sees the picture — so there is nothing to fix yet. The one way in
  would be `--input-format stream-json`, whose user message can carry image
  blocks: a different runner from the byte-exact stdin one every test holds.
  **To close:** only if a run is ever seen to miss an image the path named.
- **Office files.** Neither CLI reads `.docx` or `.xlsx` natively; each would
  need a script to. **To close:** convert them at queue time (to PDF or text)
  if that turns out to be wanted.
- **An image pasted into a prompt tab that is then cancelled** stays in
  `data/queue/`. **Why deferred:** removing what appeared while the tab was
  open would also remove an image pasted at that moment into another shell's
  open tab. **To close:** sweep files in `data/queue/` that no prompt links to
  once they are a day old.

## `liveIdle` default

**Why deferred:** spike S29 showed the side bar keeps a chat's cached view
even once its process is ended, so ending it alone never shows the run; the
window has to redraw. Since 0.6.0 the two settings differ only in when the
process goes:
- `warn` (the default) runs, then ends the idle process after the run when
  nobody is at the PC, and on Show it otherwise.
- `stop` ends it before the run, by the same checks
  (`Stop-ChatIdleProcess`), and waits, as for a busy chat, while a workflow
  or background agent is in flight.

Still open: whether a present user's process may be ended at the run's end
too. What a side bar does when the chat on screen loses its process - and
whether an unsent draft survives - has not been watched.

**To close:** S30 item 5 in TESTING.md. If the side bar takes it quietly and
keeps the draft, end it at run end whoever is at the PC, and drop the `live`
case.

## A chat typed into while chatq runs it

**Why deferred:** found on 2026-09-23, after the fix it would need was already
under way. An open panel does not follow a chatq run: a window reloaded
mid-run shows the chat as it stood at that moment, stopped halfway, and
`continue` typed there starts a second agent on the same session while
chatq's is still working. Both edit the same files at once. The panel's agent
knows nothing of what chatq's did after the fork, only the files. chatq checks
for a busy chat before a job starts, and never while it runs. The `started`
alert says nothing about keeping out of the chat.

What 0.6.0 does about it: Show it and the chip leave a chat alone while a
queued prompt or any `claude -p` goes into it (`Show-ChatFresh`, outcome
`running`); the next run into a chat waits 30 s after a request to show it
(`Get-ChatShowHold`); and a run into a chat a window opened while the run went
on is followed by a `ran` request, as for a chat held from before
(`Invoke-ChatqJob`). What is left is someone typing into such a window before
the run ends - a window that opened the chat mid-run, a startup open more
than 30 s after the chip's click, or the side bar's idle process under
`liveIdle: warn`.

**To close:**
1. Say so up front: when the chat is open in a window, the `started` alert
   says not to type in it until `done`.
2. Watch during the run. A record from another entrypoint (`claude-vscode`)
   whose parent is outside the run's own chain is a second writer: alert at
   once, naming the chat.
3. Decide whether chatq then stops its own run or lets both finish. Stopping
   loses less when the two are editing the same files.

## Approve permission prompts from the phone

**Why deferred:** the chosen behaviour is to alert and park.

**To close:** a `--permission-prompt-tool` MCP bridge that pushes an Allow/Deny
alert and waits for the answer with a timeout. Join would reach it through
Tasker, or ntfy through a reply topic. This is Claude only; `codex exec` cannot
ask mid-run.

## The console: what 0.5.0 left out

- **A console on macOS.** **Why deferred:** the Mac panel has never run
  (S24), and a Cocoa window with text entry, drag and drop and a pasteboard
  in untested JXA would only add to that. **To close:** after S24, an
  `NSWindow` from the same host, or the console as a small local web page
  the pwsh host serves on 127.0.0.1.
- **New Codex chats.** + New chat starts Claude chats only. **Why deferred:**
  a new Codex thread's id comes back in `thread.started` rather than being
  given up front, so a retry after a limit could start a second thread.
  **To close:** capture the id from `thread.started` as the run begins, save
  it on the job, and resume it from then on.
- **`chatq -New <folder>` in a shell.** **Why deferred:** the console was
  the ask; `New-ChatqJob -Kind new` does the work already. **To close:** a
  parameter set on `chatq` that calls it, with `-Name`.
- **Changing a waiting job's mode or model** from the console. **Why
  deferred:** only the prompt is editable in place; Remove and send again
  covers the rest. **To close:** the same chips in the details pane, written
  through `Set-ChatqProp`.
- **Answering a permission prompt from the console.** A run that asks is
  parked as needs-input. **Why deferred:** the same as for the phone, above.
  **To close:** the same `--permission-prompt-tool` bridge, answered from
  the console's details pane.
- **Opening the chat in VS Code** from the console. **Why deferred:** the
  console was not in 0.6.0's scope. Since then the way exists: the overlay's
  open chip writes `data/open-request` and the extension opens the chat by
  its id. **To close:** a button in the console's details pane that calls
  `Start-ChatShowFreshProcess` for the picked chat, as the chip does.
- **The reply as it streams.** The console shows a run's reply once the run
  ends. **Why deferred:** reading a log the watcher holds open works now
  (`Get-ChatqLogEntries` shares with the writer), but redrawing the details
  pane every pass costs the window's thread while a long run writes
  megabytes. **To close:** read only what the log grew by since the last
  pass, and append it to the pane rather than redrawing it.
- **Every argument hardened for `claude.cmd`.** An npm install's
  `claude.cmd` runs through cmd.exe, which does not read `\"` as an escape.
  A new chat's `--name` has `"%!&|<>^` taken out for it. **Why deferred:**
  the other arguments are chatq's own - a session id, a mode, the tool's
  data folder - apart from `chatq -Model`, which you type yourself.
  **To close:** in `ConvertTo-ChatqArgLine`, quote any argument holding
  `&|<>^()` when the executable is a `.cmd` or `.bat`, and refuse one
  holding `"` or `%`.

## A VS Code front end

**Why deferred:** the terminal UI was chosen, and then the overlay's console.

**To close:** grow `extension/`, which already offers the reload after a
delete or an archive, and shows a queued run's chat fresh in the window that
holds it:
- a status-bar count of queued jobs and the next send time
- a chat picker fed from the same index

## The extension's signal file holds one request

**Why deferred:** `data/reload-request` is one file, and the extension polls it
every 2 seconds. Two requests inside one poll - a delete right after a queued
run, say - and the first is overwritten unseen. Rare, and the cost is one
missed button. Since 0.6.0 the overlay's open chip writes a file of its own,
`data/open-request`, so a click and a run never overwrite each other; the one
slot remains within each file.

**To close:** make it a short array with ids, and have the extension keep the
last few ids it has seen instead of one.

## Background shells and "safe to reload"

**Why deferred:** the reload check counts workflows and background agents a
chat started that have not reported back, but not a Bash command run in the
background (`backgroundTaskId`). One is as often a dev server or a watcher as a
build, and a server never reports. Counting them would hold the project
"active" for as long as it runs, and `-WaitForIdle` would never return. A
reload still kills a background build with the chat's process. So, since
0.6.0, does showing a chat fresh: `Stop-ChatIdleProcess` ends the chat's
idle process with `taskkill /T`, dev servers and all, and Reload Webviews
restarts every Claude process in the window. The open chip's tooltip says
so; nothing else warns.

**To close:** tell the two apart. A shell the model started with a timeout, or
one that moved to the background after its timeout ran out (`timedOutAfterMs`
in its result), is meant to end, so it could count. One started with
`run_in_background` and no end in sight would not. Before relying on that,
check the CLI keeps those fields stable. For the ending itself, a chat's
process with child processes other than its MCP servers could count as
`held` - once MCP servers can be told from shells the model started.

## Deletes and new chats through Reload Webviews

**Why deferred:** 0.6.0 shows a queued run's chat with Reload Webviews, but a
delete, an archive and a new chat still reload the whole window. Nothing has
shown that Reload Webviews rebuilds the chat history - it might keep a
deleted chat listed - and the processes it restarts might write a deleted
chat back as a stub.

**To close:** S30 item 17 in TESTING.md. If the history drops a deleted chat
with no stub written back, and `claude-vscode.editor.open` shows a chat the
list does not have yet, move `deleted`, `archived` and `new` requests over.

## A busy judgement per window

**Why deferred:** chatq judges a folder, not a window, so Reload Webviews is
used only in a window on exactly that one folder. A multi-root window, or one
on a parent folder, always gets the tab instead, and the overlay's chip does
not bring such a window forward (`Test-ChatWindowExact` guesses at it from
window titles).

**To close:** `hostPids` already names the `Code.exe` behind each window's
Claude processes (S30 item 12 checks it is the extension host). Judge busy
over the chats whose process has that parent, and any window where none of
its own chats is working can use Reload Webviews, whatever its folders.

## Ending a chat's process off Windows

**Why deferred:** the parent check that tells a VS Code window's `claude`
from a terminal's reads the parent through CIM, which is Windows only. Off
Windows the process is never ended (`kept`), and the window is offered a
reload instead.

**To close:** a spike on macOS and Linux for what a panel `claude`'s parent
is called there (`Code Helper (Plugin)` on macOS, most likely), then a parent
lookup through `ps -o ppid=,comm=`.

## `code -n` behaviour

**Why deferred:** the chip brings a window forward with `code -n <folder>`,
assumed to focus the window already on that folder and open none. Windows
may refuse a background process the foreground and only flash the taskbar
button.

**To close:** only if S30 item 8 shows a second window, or item 6 a flash
instead of a raise: record what happens, and which VS Code setting
(`window.openFoldersInNewWindow`) or other route changes it. Nothing that
moves the pointer, types, or calls a window API.

## A chat no process holds gets no request

**Why deferred:** a queued run writes a `ran` request only when a window's
process held the chat as the run began. A chat whose process had already
ended - by itself, or by a Reload Webviews for another chat - can still be
cached in a side bar, which then shows it stale, and nothing tells that
window. 0.5.0 was the same.

**To close:** after S30 item 15, write a `ran` request (`oldProcess` none)
after any run into a chat a window may cache - one whose transcript says
`claude-vscode` - and let the window decide.

## A `claude -p` that is not chatq's

**Why deferred:** since 0.6.0 a chat's background work is told apart by
the `entrypoint` its records carry, and a print-mode run's (`sdk-cli`) is
taken for dead once no print-mode process of the chat is alive
(`Test-ChatPrintLive`, `Get-ChatBackgroundTasks -SkipPrint`). A queued run
is also known from the queue. Someone else's `claude -p --resume` into the
same chat is known only from `~/.claude/sessions/` - and whether a
print-mode process writes a file there, and with what `kind`, has not been
watched. If it writes none, such a run going on is invisible: its workflows
would read as dead, and Show it could end the window's process beside it.

**To close:** S30 item 18. If a print-mode process leaves no registry file,
treat an `sdk-cli` record written in the last few minutes as a run still
going on.

## The overlay: what 0.4.0 left out

- **Codex and Copilot chats as live rows.** **Why deferred:** only Claude Code
  writes a list of what runs (`~/.claude/sessions/`). Codex's panel keeps a
  rollout open while a thread is shown, and Copilot records nothing at all.
  **To close:** for Codex, ask the shared app-server daemon for its threads
  (the one `codex queue` talks to; see the Codex entry above), or treat a
  rollout written in the last minute as working. Copilot waits on something
  that says a chat is running.
- **Linux.** **Why deferred:** nothing here runs Linux (see CI below), and each
  desktop has its own tray. **To close:** a GTK or tray-icon renderer reading
  the same `overlay.json`. `chatoverlay -Print` is the view until then.
- **Full screen.** **Why deferred:** a game in exclusive full screen draws
  over any window, and that is expected. **To close:** hide the panel while
  `SHQueryUserNotificationState` says full screen or presentation mode.
- **The macOS panel has never run.** **Why deferred:** no Mac here. **To
  close:** checklist S24 in TESTING.md, and `osacompile` on a `macos-latest`
  CI leg.
- **A hotkey on macOS.** **Why deferred:** a global key needs Carbon's
  `RegisterEventHotKey` or an accessibility permission, neither reachable
  cleanly from JXA. **To close:** only if the menu bar item turns out not to
  be enough.
- **The panel's buttons on macOS.** Windows has a row of buttons on the
  panel's top edge when the pointer is near it: grip, collapse, refresh,
  settings, hide, close. The Mac panel has only its menu bar item, and `-Theme`, `-Opacity`
  and `-Refresh` from a shell; it has no collapsed view. **Why deferred:** the
  Mac panel has never run, and more untested Cocoa would not help that.
  **To close:** after S24, a second small `NSPanel` beside the first, the
  way Windows uses a second window, shown from a tracking area on the panel;
  the settings and collapse as menu items, which JXA can already make.
- **Copilot usage without the GitHub CLI.** Copilot's line needs `gh`,
  logged in. **Why deferred:** VS Code writes only the plan to disk
  (`chat.setupContext` in `globalStorage/state.vscdb`, e.g.
  `free_limited_copilot`), never the quota; the figures come from GitHub
  with VS Code's GitHub login, which sits encrypted in VS Code's own secret
  store - not something another program should pry out. **To close:** if VS
  Code starts keeping the quota snapshot in its state, read it there.
- **Codex usage on demand.** Codex's figure is the `rate_limits` snapshot
  Codex writes into its own rollout during a run, so the refresh button
  cannot move it: it is as old as Codex's last run, and the panel says so.
  **Why deferred:** a fresh figure means asking OpenAI with the login Codex
  saved in `~/.codex/auth.json`, through an endpoint that is not documented
  and has not been looked into here. **To close:** find what Codex's own
  `/status` asks, and treat that token as the Claude one is treated - read
  for the one request, never stored, logged or refreshed - with the same
  waits on a refusal.
- **Usage without asking the endpoint.** Claude Code hands a status-line
  command `rate_limits.five_hour` / `seven_day` (`used_percentage`,
  `resets_at`) after every reply (code.claude.com/docs/en/statusline). That
  is current to the turn and costs no request, where the endpoint refuses
  when asked often. **Why deferred:** it means adding a command to
  `~/.claude/settings.json` - or wrapping one already there - and status
  lines are reported not to run in the VS Code extension's chat panel, which
  is where these chats live. **To close:** confirm whether the extension runs
  `statusLine`; if it does, an opt-in `chatoverlay -StatusLine on` that
  installs a one-line command writing `data/usage-statusline.json`, read by
  the collector ahead of the endpoint, and taken out again on `off` and on
  uninstall.
- **Naming a command while it runs.** While `/compact` runs, the row says only
  that a command is running. **Why deferred:** Claude Code writes the command
  down once it ends; until then its transcript holds a queue record with no
  text, and nothing else on disk names it. **To close:** if a later Claude
  Code puts the text in that record, or in `~/.claude/sessions/<pid>.json`,
  read it there.
- **More than one Claude account.** **Why deferred:** the overlay reads the
  one config dir it was started with (`CLAUDE_CONFIG_DIR`). **To close:** an
  `overlay.claudeHomes` list, a row group and a usage line per account.
- **The collector on a thread of its own.** **Why deferred:** a pass costs
  40-60 ms and the usage request never blocks, so the panel has not stuttered.
  **To close:** only if `data/logs/overlay.log` or use shows it does: a
  background runspace for the collector, handing snapshots to the UI thread.

## Copilot Chat

**Why deferred:** there is no CLI that resumes a Copilot chat headless. chatrm
can find Copilot chats, but nothing could deliver a prompt to one.

**To close:** a headless resume path from GitHub.

## Start at boot

**Why deferred:** nothing is registered with the OS, on purpose. After a reboot
the watcher returns with the next shell.

**To close:** an opt-in `chatinstall -AtLogon` that writes a Task Scheduler /
launchd / systemd user entry and removes it again on uninstall.

## CI on macOS and Linux

**Why deferred:** CI now runs the self-test on Windows under both 5.1 and
PowerShell 7. The Unix branches - `nohup`, `caffeinate`, `systemd-inhibit`,
`chmod 600`, `osascript` and `notify-send` toasts, `ioreg` idle time,
`Process.Kill($true)` - are written but have never run.

**To close:** add `ubuntu-latest` and `macos-latest` to the matrix. The tests
need a `fake-claude` shell wrapper next to the `.cmd` one, and the few
Windows-only checks (DPAPI, the echo exe) a skip on Unix.

## Codex threads archived from Codex's own panel

**Why deferred:** `chatrestore` lists what `chatrm -Archive` archived, from its
own records, plus any rollout under `~/.codex/archived_sessions/` - which spike
S16 showed is where `codex archive` moves one. Whether Codex's panel archives
the same way, rather than only in its sqlite state, has not been watched.
`chatrestore <id>` hands any id to `codex unarchive` either way.

**To close:** archive a throwaway thread from the Codex panel and look for it
under `archived_sessions/`. If it is not there, read the thread list from
Codex's app-server instead.

## Sponsorship

**Why deferred:** there is no sponsor account yet. The README carries a grey
`sponsor · coming soon` badge pointing here. There is deliberately no
`.github/FUNDING.yml` - with a placeholder handle GitHub's own Sponsor button
would open a 404.

The options:

| | fits | costs |
|---|---|---|
| GitHub Sponsors | the button sits in the repo header, one-off or monthly | enrolment and payout setup; no fee on personal accounts |
| Ko-fi | one-off tips, a simple page | no fee on tips; memberships take a cut |
| Buy Me a Coffee | one-off tips, memberships | a 5% fee |
| Patreon | monthly memberships | a platform fee; heavy for a one-file tool |
| thanks.dev | sponsors a project's dependencies at once | little to gain for a tool nobody depends on yet |

**To close:** pick one, add `.github/FUNDING.yml` with its handle, and swap the
badge for the real link.

## Social preview image

**Why deferred:** GitHub sets a repo's social preview only in the web UI
(Settings → Social preview); there is no API for it.

**To close:** upload a 1280×640 image made from `docs/demo-list.svg`.

## Weekly-limit and model-scoped limit handling

**Why deferred:** every limit seen on this machine was `five_hour`.
- A model-scoped limit (`seven_day_opus`, a `weekly_scoped` cache entry) no
  longer blocks the queue. The probe, asked with each chat's own model, decides.
- A job waiting on a real weekly limit just waits, without holding the machine
  awake.

**To close:** capture a real `seven_day` / `seven_day_opus` rejection. Check
the exact `rateLimitType` names against the list in `$script:ChatqWideLimits`.
Then decide whether a job should wait days, or alert and park.

## Overloads on Codex

**Why deferred:** the 529 handling watches status.claude.com, which covers
Claude only. A dropped Codex connection ("stream disconnected", "error sending
request") is retried like Claude's, but a Codex server error worded any other
way still fails the job.

**To close:** capture a real Codex 5xx/overload event. Then either watch
status.openai.com the same way, or just retry with the same backoff.
