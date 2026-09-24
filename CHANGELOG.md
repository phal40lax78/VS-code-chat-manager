# Changelog

## 0.6.0 — show the chat fresh

- **Show it, not Reload.** A chat a VS Code window still holds shows a
  queued run only once that window redraws it. 0.5.0 reloaded the whole
  window for that; now the window redraws only its web views (**Developer:
  Reload Webviews**) and opens the chat where you read it - the side bar
  here. It does this by itself under 0.5.0's rules: you away, nothing in the
  folder working, a window on exactly that folder, and that judgement at
  most 20 s old. Otherwise the notification offers **Show it**. The click
  ends the chat's old idle process and judges the folder again, right then;
  with a chat working it opens the chat fresh in an editor tab of its own
  instead, and nothing is cut off. Terminals, editors and other extensions
  keep running either way. Whether other web views (a Codex chat, a
  preview) and an unsent draft come through is still to be checked (S30
  items 14 and 2).
- **The old process.** Reload Webviews alone is not enough: the chat's old
  `claude` process keeps the old memory. While you are away, chatq ends it
  as the run finishes, so your next message there starts from disk even if
  nothing redraws the view. While you are at the PC it is left alone until
  you click Show it - what a side bar does when the chat on screen loses its
  process is still to be checked (S30).
- **The overlay's open chip.** Move onto a Claude row and rest a second, and
  a small **open** appears at its right end - a window of its own, like the
  buttons', that takes no focus and is in neither Alt+Tab nor the taskbar;
  the rest of the panel stays click-through. It shows once per visit to a
  row, and a pointer it came up under has to move off it before a click
  counts. A click shows the chat up to date in its window, the same way,
  and brings that window forward with `code -n <folder>` - or opens one
  there, which shows the chat as it starts. The tray says when it could not:
  a queued prompt running in that chat, a terminal holding it, a window with
  other folders open, no `code` command. A window on exactly the folder is
  told from its title, a profile's name after the folder's included.
- **The overlay's buttons can be pointed at directly.** They came up only
  after the pointer rested on the panel, so reaching them meant going to the
  panel, waiting, and crossing to them before they went. Resting on the spot
  they go - above the panel, or below it near the screen's top - brings them
  too, and the gap between them and the panel counts as theirs. The same
  350 ms rest applies: a pointer passing over that corner on its way to the
  window underneath must not find buttons that take its click. No rest
  counts while a mouse button is held, so a tab or a file dragged across
  that corner in the app below is never dropped onto them.
- **What is never ended.** Only a VS Code window's process is ever ended -
  its registry entry says `claude-vscode` and its parent is `Code.exe` -
  never a terminal's, and never one busy, waiting, or with a workflow or
  background agent in flight; its registry file is read again just before.
  A chat open in a terminal is never shown in VS Code as well: that would be
  a second writer, and the alert says to type there. `liveIdle: stop` now
  goes through the same checks, and with background work in flight it
  waits, as for a busy chat. Ending a process ends the background shells it
  runs too, dev servers included. Background work is told apart by who
  started it - each transcript record names its writer, `claude-vscode` for
  the window, `sdk-cli` for a `claude -p` run - never by when: a workflow
  the window's own process started holds it whenever it began, even during
  a queued run, and one a finished queued run left behind never holds it.
- **Never beside a run.** A queued prompt going into the chat, or any
  `claude -p` writing into it, makes Show it and the chip leave it alone
  and say so: showing it then would load it part way through. After a run's
  or the chip's request, the next queued run into that chat waits 30 s
  while the window shows it; a run into a chat a window opened while the
  run went on is followed by the same Show it, since that window loaded it
  part way.
- **The window's other idle chats.** Reload Webviews ends their processes
  as well; each starts again, from disk, when you open it.
- **The alert** says what to do by what became of the old process: `Show it
  in VS Code to see the run`, `... before typing in this chat` when it was
  left running, or to type in the terminal that holds it.
- **The extension** is 2.1.0, with `chatManagerReload.showFresh` (on); off,
  or without the Claude Code extension, it reloads as 0.5.0 did. The overlay
  asks through a file of its own, `data/open-request`, so a click and a
  run's request never overwrite each other. **Update the extension too:** a
  2.0.0 one would now offer a reload after `liveIdle: stop` runs as well.
- **Unchanged:** deletes, archives and new chats still reload the window.
  Whether Reload Webviews would do for them is S30.
- **Fixed:** the command lines chatq builds for its own child processes -
  the toast on PowerShell 7, the watcher, the console's index sync, the
  overlay - doubled only `'`. PowerShell also ends a quoted string on a
  curly quote, so a reply's excerpt with one could end the string early; all
  four are doubled now.
- **Fixed:** a new index that could not be swapped in was dropped without a
  word. Anything reading the index at that moment - the overlay's console,
  its 10-minute sync, a virus scan - fails the swap, and a restored or new
  chat then stayed missing from Tab until the next sync. The swap now tries
  five times over about 0.4 s, then warns.
- **Layout: the script and `src/`.** The one file had passed 13,000 lines.
  `VS-code-chat-manager.ps1` now loads fourteen parts from `src/`, in the
  order the file had them; nothing they do changed, and the profile line,
  the watcher and the overlay still load the same path. Copying it by hand
  means copying `src/` with it; without a part it says which and loads
  nothing. The one-line installer downloads the repo as one zip, since
  files fetched one by one from raw.githubusercontent.com can come from two
  versions for minutes after a push. The self-test is split the same way,
  into `tests/sections/`.

## 0.5.0 — chatq in a window

- **`chatconsole`**, the overlay's window for chatq: pick a chat - cut off,
  open in VS Code, recent, or found by search - write to it, and send it now
  or queue it. Also the speech bubble on the overlay's buttons, **Open
  console** in the tray, and **Ctrl+Alt+Shift+Q** (`-ConsoleHotkey`). It
  takes the keyboard only when you open it, and closing it keeps the draft -
  the chat, the text, the files, the choices - across restarts too.
- **Files by drag and paste.** Drop files on the prompt, or paste a
  screenshot or files copied in Explorer with Ctrl+V; each is copied aside at
  once, off the window's thread, and moves into the job on Send.
- **Send now.** The job goes to the front and runs within seconds; a chat
  working in VS Code is looked at every 30 s rather than every 5 minutes. A
  line says beforehand what Send will do: a limit, a busy chat, a reload.
- **New chats.** + New chat starts a Claude chat in a folder, named by you or
  by the prompt's first line. Its session id is chosen when it is queued and
  handed to `claude -p --session-id` with `--name` (spike S25), so a retry
  after a limit continues that same chat, never a second one. The extension
  offers a window on that folder a reload to pick it up; whether VS Code's
  chat list then shows it is still to be checked (S25).
- **Cut off, marked.** The overlay colours chats the limit or a 529 stopped
  orange - `cut off - resets 13:00` - and gives one not open a row of its
  own; the console continues one, or all of them. It looks a week back for
  a limit still ahead, and otherwise at the last 12 hours; it looks again
  at once when a job or a chat's state changes, never reads a chat that is
  working, and reads a transcript again only once it changed.
- **The queue as a console.** Each job says where it stands; pick one for
  its reply, its log, and Try now, First, Remove, Cancel, Requeue or Write to
  this chat; a waiting prompt can be edited in place.
- **One job core.** `chatq`, `chatqrm`, `chatqrun`, `chatqlog` and the
  console make and change jobs through the same functions, and the commands
  print exactly what they did. The index is now written whole and swapped
  in, so a reader never sees half of it.
- **Fixed:** `chatqlog` on a job still running failed with "being used by
  another process" - the run holds its log open. `chatqrm -Force` on a job
  that ended meanwhile, with no watcher left, marked it failed and lost its
  result; it now says it had already ended.
- **No Reload to click on coming back.** A chat open in a VS Code window never
  shows a chatq run until that window reloads, and until now the window only
  ever asked. It reloads by itself now when, as the run ended, nobody had used
  the PC for `quietMinutes` (5 — the same clock that sends the alert to the
  phone) and no other chat in the folder was working or had been written in
  that time. It still asks at the PC (you may be typing in that very window),
  on an idle clock that cannot be read or `quietMinutes` 0, and in a window
  with more than one folder or opened on a parent one, since only the chat's
  own folder was judged. A window opened after the run already shows it, so
  it neither asks nor reloads - nor for a new chat a run started, which it
  lists already. A new chat is never reloaded for by itself.
- **The chat the run just wrote no longer counts as busy** for having just
  been written. What Claude says of its own open process still counts: after
  the run that can only be a window's, and it may be mid-answer.
- The busy check asks the job's own Claude home (`CLAUDE_CONFIG_DIR`) for its
  open sessions, not the watcher's.
- **A refused login says what Claude said.** Every 401 and 403 read as
  `Claude is logged out · run claude, then /login`, and nothing kept what
  Claude had actually said. A subscription that has run out is refused the
  same way, so on 2026-09-23 a lapsed plan was reported as a lost login, and
  afterwards there was no telling which it had been. The alert now quotes the
  API's own message — `Claude login refused: OAuth token has expired. (401) ·
  run claude, then /login, or check the subscription` — and so do
  `data/logs/watcher.log`, the `chatqlist` status line, the console's line
  before Send (which had called it "limited until") and the job's result.
  Codex the same, with `codex login`.
- **The watcher log keeps the whole error too**, on an `error text:` line of
  its own, type and all — the message alone does not say what kind of refusal
  it was.
- **The extension** has words for a new chat, and reloads by itself after a
  queued run as above; `chatManagerReload.autoReloadAfterRun: false` makes it
  always ask. Copy its files over the installed ones to update it (see the
  README for the update line).

## 0.4.0 — every running chat at a glance

- **`chatoverlay`** keeps a small panel in the top-right corner, above other
  windows. It shows every open Claude chat: its project, title, newest prompt,
  and a dot for what it is doing. Amber is waiting on you and goes to the top,
  green is working, grey is idle. A chat open in two windows is one row.
  Queued prompts appear on their chat's row, or as a purple row of their own
  when that chat is not open.
- **A slash command is the newest thing sent.** Claude Code does not count one
  as a prompt: after `/compact` its own record of the last prompt still names
  the one before. So the overlay reads the command from the transcript. While
  `/compact` runs nothing on disk names it yet, and the row says a command is
  running instead of showing the older prompt as current.
- **Usage at the top, live.** A line each for Claude, Codex and Copilot, as
  the collapsed panel has it, ending with when that figure is from - or, from
  the settings box or `-UsageView bars`, a bar in the server's own colour and
  a reset countdown per window. Claude's five-hour and weekly windows, and one
  model's weekly window once used; Codex's; Copilot's monthly quotas. Claude
  Code caches its figure only when a window opens its usage view, and here
  that copy read 55% while the account stood at 79%. So the overlay asks
  Claude's usage endpoint itself: every five minutes while a chat works, every
  fifteen while all are idle, as a window resets, and on the refresh button.
  It uses the login Claude Code saved, reads the token for that one request,
  and never stores, logs or refreshes it. An expired login or a refusal falls
  back to the cached figure, marked with its age. `-LiveUsage off` keeps to
  the cache.
- **Copilot's quota through the GitHub CLI.** VS Code keeps only the plan on
  disk, so the overlay runs `gh api copilot_internal/user` - what VS Code's
  Copilot status reads - every fifteen minutes and on refresh. `gh` keeps its
  own login and hands the overlay no token. No `gh`, or one not logged in,
  means no Copilot line; `-CopilotUsage off` stops asking.
- **It keeps to the endpoint's own wait.** Asked once a minute, the endpoint
  refused after about an hour and said to wait 48 minutes. So the overlay now
  asks every five, and when refused it waits as long as `Retry-After` says,
  showing `retry 11:22`. The refresh button does not ask inside
  that wait. The last live figure and the wait survive a restart.
- **Out of the way.** It never takes focus and clicks go through it. The tray
  dot, in the most urgent chat's colour, shows and hides it and has a menu.
  **Ctrl+Alt+Shift+O** unlocks it for dragging (`-Hotkey` changes the key),
  and it locks itself two minutes after the pointer leaves.
- **Buttons on its top edge when you point at it,** outside the panel and
  flush with its top-right corner: a grip to drag it by, collapse to one line
  (counts and usage), refresh usage, a settings box, hide to the tray, and
  close. Refresh turns while it asks and then says when Claude answered;
  Codex's figure is never asked for - it moves when Codex runs - and says it
  is from Codex's last run, with its date once over a week old. The settings
  box has an opacity slider, the theme (Dark, Light, or System to follow
  Windows' light or dark mode), and usage as lines or bars. The buttons are a
  small window of their own, so the panel never takes a click. The choices
  are kept in `config.json`; `chatoverlay -Theme`, `-Opacity`, `-UsageView`,
  `-Collapse` and `-Refresh` do the same from a shell.
- **Cheap.** One hidden Windows PowerShell, about 160 MB and under 0.1% CPU on
  this machine with ten chats open. It re-reads a file only once it changed,
  and a transcript only from where it stopped: the first look at a 20 MB chat
  reads its last 256 KB, where Claude Code writes each turn's prompt and title.
- **`chatoverlay -AutoStart on`** brings it back with every new shell, as the
  watcher comes back. Nothing is registered with the OS. `chatinstall` restarts a
  running overlay on the new copy, and `chatuninstall` stops it.
- **`chatoverlay -Print`** draws the same in the console. That is Linux's only
  view.
- **macOS, untested:** a floating panel and a `CQ` menu bar item, drawn by
  JavaScript for Automation, so nothing needs installing. Live usage is off
  there by default, since reading the login from the keychain asks for a
  password.
- **The watcher reads the same session list.** When `claude agents` cannot
  run, its fallback now reads `~/.claude/sessions/` the overlay's way. It also
  keeps what a chat is waiting for. A macOS-style `procStart` no longer rejects
  every session as a reused pid.

## 0.3.1 — no "safe to reload" while another chat is working

- **A chat running a workflow or a background agent is no longer called
  idle.** The turn that starts one ends at once, and the work writes only to
  its own files, so a minute later the check read the chat as finished. The
  terminal then said `safe to reload now`, and a reload would have killed the
  work. Now the transcript is searched for a start with no
  `<task-notification>` after it. Only starts since the chat's process began
  count: anything older died with an earlier process.
- **Claude's own word comes first.** A chat that `claude agents` lists as
  `busy` or `waiting` is active, whatever its transcript looks like.
- **The window's Reload offer says so too.** The request left for the
  extension now carries `busy`. While a chat works, the window warns — *A chat
  in this workspace is still working, and reloading now would cut it off* —
  with **Reload anyway**, and `autoReload` does not fire. Before, the button
  appeared the same either way, and the warning was only in the terminal. Copy
  `extension/` again to get this (see the README for the update line).

## 0.3.0 — files and screenshots with a queued prompt

- **`chatq <title> -Attach a.png, spec.pdf`** sends files with the prompt —
  images, text, code, PDF, as many as you like, a wildcard too
  (`.\shots\*.png`). They are copied into the job, `data/queue/<id>/`, before
  the prompt is written, so the originals can move or change in the hours
  before it sends. A file missing, or one that cannot be copied, queues
  nothing; the same file twice goes once.
- **`chatq <title> -Paste`** takes the clipboard as it is now: a screenshot, files
  copied in Explorer, or text — which becomes the prompt, or goes under the one
  given, quotes and all, and helps pick the chat as a typed prompt does.
  Windows only.
- **Ctrl+V in the editor tab.** VS Code saves a pasted image beside the prompt
  file, in `data/queue/`, and links it; chatq moves it into the job and points
  the link there. Checked again just before the job sends, so an image pasted
  into a prompt reopened with `chatq <n>` counts too. A link to any file
  outside `data/queue/` is left exactly as written and never opened by chatq:
  it names a file where it is, for the chat to open or change there — a copy
  would have it edit a snapshot, `../config.json` would reach chatq's own data,
  and a `\\host` path would open a connection to that host.
- **`chatq <n> -Attach` / `-Paste`** adds files to a job while it waits.
- **How each chat gets them.** Claude gets every path under the prompt,
  `Attached files - read each one:`, and opens them with its own Read tool — it
  sees an image as a picture and reads PDF — with `--add-dir` for the job's
  folder. Codex gets images properly, one `-i` each and a `--` so the thread id
  is never read as another image, and the other files under the prompt. A
  "continue" sends no files; they went with the prompt.
- `chatqlist` counts a job's files (`+2 files`), `chatq <n>` names them,
  `chatqrm` removes them with the job, and more than 10 files or 20 MB draws a
  warning.

## 0.2.1 — what a first day of real use turned up

- **A prompt typed after the title is caught.** `chatq <title> <some words>`
  reads every word as the title — that is what lets a title be typed without
  quotes — so the words meant for the chat went looking for one instead, and
  the pick was a guess. When the pick is a guess and what was typed reads like
  a prompt (six words or more, or a path or URL in it), `chatq` now says so and
  shows the `-Prompt` form.
- **The cut-off list names the chat.** It fell back to the transcript's uuid
  when the index had no row for that chat yet — which is exactly the state a
  chat the limit has just stopped is in. The title is read from the transcript
  instead, so it can go straight into the `-Continue` line printed under it.
- **The usage line no longer contradicts the status line above it.**
  `Claude 5h 0%` sat next to `Claude limited until 11:50`, because both
  providers' figures come from caches that refresh only when that tool itself
  runs. The window that is blocked now reads `limited` — `5h limited` for the
  five-hour one, `week limited` for a weekly one, a 529 neither — and a figure
  an hour old or more is marked `stale`.
- **`data/logs/jobs.log`** keeps a line per job event — queued, every state it
  moves through, and removals. A job's own history goes with its file, so until
  now a `chatqrm` left no trace at all, and where a job went could only be
  guessed from the watcher logging an empty queue.
- **`chatqnotify -ApiKey` takes the whole Join push URL**, quoted, and reads the
  key and device out of it. Unquoted it never arrives — PowerShell stops at the
  first `&` — so the help now says to paste the key alone.
- `chatq`'s cheat sheet said phone alerts went through Join. They also go to a
  desktop toast and to ntfy.

## 0.2.0 — chatrm and chatq in one tool: VS-code-chat-manager

The repo was chatq; it is now VS-code-chat-manager, and chatrm 1.3.0 is inside
it. The chatrm repo stays as it was.

- **One file, one index, one install.** chatrm's proven code is the base and the
  queue sits on top of it; chatq's copy of chatrm's index, readers, providers
  and scoping is gone.
  - Every command keeps its name. `chatqinstall` and `chatquninstall` fold into
    `chatinstall` and `chatuninstall`.
  - `chatinstall` replaces a profile line for chatrm or chatq with its own,
    since they define the same commands.
- **One Tab for all three.** The completer serves `chatrm`, `chatfind` and
  `chatq`, and `chatq` gets chatrm's one-line Tab cycling, so a multi-word title
  needs no opening quote any more. Subagent chats are no longer offered (the
  search skipped them, so Tab offered what it then could not find), `chatq` is
  never offered a Copilot chat, and a title that happens to be hex (`add…`,
  `cafe…`) completes instead of nothing.
- **Fixes carried from chatq into the chatrm half:** a Hangul Codex thread name
  is read as UTF-8; a Claude title with a quote in it comes back unescaped; a
  zero-width cell no longer throws; typographic apostrophes are quoted safely;
  the whole file is StrictMode-safe at load and in every key handler.
- **The two halves know each other.**
  - `chatrm` keeps a chat that has a prompt queued for it, and names the job;
    `-DropJobs` drops the jobs first, waiting out a running one.
  - A queued run into a chat still open in a window asks that window to reload,
    through the extension.
  - A Copilot title given to `chatq` is refused with the reason, never quietly
    swapped for another chat.
- **The extension** is now `phal40lax78.chat-manager-reload` 2.0.0, with
  `chatManagerReload.*` settings. It watches the new folder and the old chatrm
  one, says what happened (deleted, archived, a queued run), and never reloads
  unasked after a queued run.
- **Delete takes every leftover:** besides the sidecar folder, `file-history`
  and `session-env`, now `tasks`, `debug`, security state, telemetry, todos, a
  background job's folder, and the plan file when no other chat in the project
  shares its slug — after
  [claude-chats-delete](https://github.com/ataleckij/claude-chats-delete)'s
  inventory. They go only once the transcript is gone, so a chat a live window
  holds open keeps them.
- **Archive and restore.** `chatrm … -Archive` moves a Claude chat and its
  leftovers into `data/archive/`, or archives a Codex thread through
  `codex archive`; `chatrestore` lists and brings them back. `chatuninstall
  -All` will not delete an archive that is the only copy.
- **Retries that know when to stop.**
  - A dropped connection is retried after 1, 2 and 5 minutes. The count lives in
    the job, and chatq's own 4-hour cap is never mistaken for one.
  - An expired login holds that account's jobs, with one alert.
  - A job that breaks before any reply `maxRetries` (5) times in a row gives up;
    one that makes progress each time never does.
  - An overload past 6 hours sends one reminder.
- **More ways to hear about it:** a desktop toast (on by default), ntfy as JSON
  so Hangul survives, and a command of your own with the alert in its
  environment. The phone stays quiet while you are at the PC.
- **`chatq -Model`** runs one job on another model, and its probe asks with that
  model. **`-First`** (and `chatqrun <n> -First`) puts a job at the front, in one
  queue order the watcher, the list and the board all share.
- **Usage in `chatqlist`**: how much of Claude's and Codex's windows are used,
  from their own caches, with how old the figure is.
- **The watcher picks up an update:** `chatinstall` asks a running one to hand
  over after its current job. The successor carries on with what it knew —
  limits, overloads, alerts already sent.
- **The repo:** README badges, demo frames made by `docs/make-demo.ps1` from the
  real commands, a comparison with similar tools, CI on Windows PowerShell 5.1
  and PowerShell 7, a v0.2.0 release, and a mock sponsor badge until one is set
  up.

## 0.1.0 — first release

- **Queue a prompt for an existing chat** while the usage limit is hit:
  `chatq <title> -Prompt …`, or with no `-Prompt` in an editor tab named after
  the chat. `-Continue` queues a "continue" for a chat the limit cut off.
- **The chat is picked when you queue, and the pick is printed.** The order is
  id, then exact title, contains and every word. It searches this project
  before any other. When nothing matches, the guess comes from this project's
  chats. The newest candidate wins unless others were active within 5 hours,
  and then relevance decides: a character-bigram cosine that works for Hangul
  and English alike, with no model call.
- **A background watcher sends at the reset.**
  - It reads the reset time from Claude's own limit record in the transcript,
    or from Codex's rate-limit snapshot.
  - It confirms with a throwaway probe that saves nothing.
  - It then resumes each chat in its own folder and in the permission mode it
    last used, one job at a time.
  - Anything that would ask a question is denied, and the job is parked as
    needs-input.
  - A limit hit again mid-run requeues the job, as "continue" if the prompt had
    already landed.
- **Status.**
  - `chatqlist` shows one line per job, with long prompts summarised.
  - `chatq <n>` opens a prompt, and edits count until it is sent.
  - `chatqlist -Board` is a live markdown board for VS Code's preview.
  - `chatqlog <n>` shows what a run did.
- **`API Error: 529 Overloaded`** (and any other 5xx) is no longer a failure.
  - The job is requeued, as "continue" if the prompt had landed.
  - chatq watches `status.claude.com`'s JSON every minute and resumes as soon as
    the Claude Code component is operational.
  - An overload the page never shows is retried after 1, 2, 5 and 10 minutes,
    then every 15.
  - Chats you left stopped on a 529 are listed next to the limit-cut ones, for
    `-Continue`.
- **Phone alerts through Join** for started, needs input, done, failed,
  limited and overloaded. The key is DPAPI-protected on Windows. Titles start
  `chatq ·`, for Tasker filters.
- **Chats still open in a VS Code window.** A busy chat waits. An idle one runs
  with a "reload the window" note, or with `liveIdle: stop` its idle process is
  ended first.
- **Built for unattended runs.**
  - The machine is kept awake while a job is due within 6 h.
  - The watcher is restarted from the profile after a reboot.
  - API keys and the parent chat's session variables are kept out of runs.
  - Prompts go to the CLI as raw UTF-8, so Hangul survives Windows PowerShell
    5.1.
- **Limits are tracked per account and per model.**
  - A job queued under `CLAUDE_CONFIG_DIR` / `CODEX_HOME` keeps that account.
    Otherwise it runs in the default account, never the watcher's inherited one.
  - An Opus-only weekly limit holds up no other model.
  - A limit record older than an "allowed" probe no longer blocks the queue
    again.
- **Guesses stay inside a project.** From a folder that is no project, a title
  that matches nothing is refused, unless `-AllProjects` is given.
- **Works under a caller's `Set-StrictMode -Version Latest`.** On pwsh 7,
  timestamps read back from job files keep their time zone.
- One file, PowerShell 5.1 and 7, everything under `data/` beside the script.
  One-line install.
