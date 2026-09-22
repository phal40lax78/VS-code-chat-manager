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

## `liveIdle` default

**Why deferred:** ending an idle chat's process before a run (`liveIdle: stop`)
should make the next click re-read the transcript. Nobody has watched the panel
react to it yet, so the default stays `warn`: run, then tell the user to reload
the window.

**To close:** spike S4 in TESTING.md.

## Approve permission prompts from the phone

**Why deferred:** the chosen behaviour is to alert and park.

**To close:** a `--permission-prompt-tool` MCP bridge that pushes an Allow/Deny
alert and waits for the answer with a timeout. Join would reach it through
Tasker, or ntfy through a reply topic. This is Claude only; `codex exec` cannot
ask mid-run.

## A VS Code front end

**Why deferred:** the terminal UI was chosen.

**To close:** a small extension, in the manner of chatrm's `extension/`:
- a status-bar count of queued jobs and the next send time
- a chat picker fed from the same index
- it could also run `workbench.action.reloadWindow` after a run into a chat
  that is open in that window, which would close the stale-panel gap from the
  outside

## Copilot Chat

**Why deferred:** there is no CLI that resumes a Copilot chat headless. chatrm
can find Copilot chats, but nothing could deliver a prompt to one.

**To close:** a headless resume path from GitHub.

## Start at boot

**Why deferred:** nothing is registered with the OS, on purpose. After a reboot
the watcher returns with the next shell.

**To close:** an opt-in `chatqinstall -AtLogon` that writes a Task Scheduler /
launchd / systemd user entry and removes it again on uninstall.

## CI on PowerShell 7, macOS and Linux

**Why deferred:** the build machine has only Windows PowerShell 5.1. The
cross-platform branches — `nohup`, `caffeinate`, `systemd-inhibit`, `chmod 600`,
`Process.Kill($true)` — are written but have never run.

**To close:** a GitHub Actions matrix (windows 5.1 and 7, ubuntu, macos) running
`tests/run-tests.ps1`. On Unix it needs a `fake-claude` shell wrapper next to
the `.cmd` one.

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
Claude only. A Codex server error still fails the job.

**To close:** capture a real Codex 5xx/overload event. Then either watch
status.openai.com the same way, or just retry with the same backoff.
