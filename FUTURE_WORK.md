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

## Attach an image to a queued prompt

**Why deferred:** a job carries text only. A path named in the prompt still
works for Claude - it reads PNG, JPG and PDF itself - but an unattended run
denies anything that would ask, so the file has to sit in that chat's own
project folder, and it has to still be there hours later when the job sends.

Codex has a real attach: `codex exec resume -i <FILE>`, repeatable (checked
against the bundled codex-cli 0.154). Claude Code's CLI has none. Its only way
in is `--input-format stream-json`, whose user message can carry image content
blocks - a different runner from the byte-exact stdin one.

**To close:** `chatq <title> -Image <path>`, repeatable: `-i` on Codex, and on
Claude the path written into the prompt until that runner exists. Copy the file
into `data/queue/` beside the prompt, or a job breaks when the file moves.

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
