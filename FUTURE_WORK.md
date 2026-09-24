# Future work

Open problems and deliberate deferrals. Each says why it waits and what closing
it would take.

## Deliver into a live chat instead of beside it

**Why deferred:** Claude Code's cross-session messaging can put text into a live
session through its inbox pipe (`messagingSocketPath` in
`~/.claude/sessions/<pid>.json`). That would make the open panel show the run
with no reload. But two things stand in the way:

- It needs a per-session token that only that session's own hooks and Bash
  receive.
- The text arrives labelled as coming from another session, not from you, and
  it runs with less authority.

**To close:**
1. Add a user-level SessionStart hook that records each session's socket and
   token into `data/`, with the security trade-off stated.
2. Confirm that the message format works from PowerShell.
3. Confirm that a peer-framed prompt is acted on like a typed one.

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

**Why deferred:** ending an idle chat's process before a run (`liveIdle: stop`)
should make the next click re-read the transcript. Nobody has watched the panel
react to it yet, so the default stays `warn`: run, then ask that window to
reload - by the alert's text, and through the extension's Reload button.

**To close:** spike S4 in TESTING.md. If the panel turns out to refresh by
itself, the reload offer after a run goes too.

## Approve permission prompts from the phone

**Why deferred:** the chosen behaviour is to alert and park.

**To close:** a `--permission-prompt-tool` MCP bridge that pushes an Allow/Deny
alert and waits for the answer with a timeout. Join would reach it through
Tasker, or ntfy through a reply topic. This is Claude only; `codex exec` cannot
ask mid-run.

## A VS Code front end

**Why deferred:** the terminal UI was chosen.

**To close:** grow `extension/`, which already offers the reload after a
delete, an archive, or a queued run into a chat that window holds:
- a status-bar count of queued jobs and the next send time
- a chat picker fed from the same index

## The extension's signal file holds one request

**Why deferred:** `data/reload-request` is one file, and the extension polls it
every 2 seconds. Two requests inside one poll - a delete right after a queued
run, say - and the first is overwritten unseen. Rare, and the cost is one
missed button.

**To close:** make it a short array with ids, and have the extension keep the
last few ids it has seen instead of one.

## Background shells and "safe to reload"

**Why deferred:** the reload check counts workflows and background agents a
chat started that have not reported back, but not a Bash command run in the
background (`backgroundTaskId`). One is as often a dev server or a watcher as a
build, and a server never reports. Counting them would hold the project
"active" for as long as it runs, and `-WaitForIdle` would never return. A
reload still kills a background build with the chat's process.

**To close:** tell the two apart. A shell the model started with a timeout, or
one that moved to the background after its timeout ran out (`timedOutAfterMs`
in its result), is meant to end, so it could count. One started with
`run_in_background` and no end in sight would not. Before relying on that,
check the CLI keeps those fields stable.

## The overlay: what 0.4.0 left out

- **Codex and Copilot chats as live rows.** **Why deferred:** only Claude Code
  writes a list of what runs (`~/.claude/sessions/`). Codex's panel keeps a
  rollout open while a thread is shown, and Copilot records nothing at all.
  **To close:** for Codex, ask the shared app-server daemon for its threads
  (the one `codex queue` talks to; see the Codex entry above), or treat a
  rollout written in the last minute as working. Copilot waits on something
  that says a chat is running.
- **Click a row to go to its window.** **Why deferred:** the panel lets clicks
  through, and a window this tool brings forward would be stealing focus.
  **To close:** a click while unlocked runs `code <folder>`, so VS Code
  brings its own window forward. Opening the chat itself needs the extension,
  and a command that opens a session by id.
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
