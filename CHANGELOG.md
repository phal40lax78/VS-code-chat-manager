# Changelog

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
