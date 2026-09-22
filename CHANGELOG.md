# Changelog

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
