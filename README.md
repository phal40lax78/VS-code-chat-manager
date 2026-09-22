# chatq

Hold prompts while the usage limit is hit, and deliver them to the right chats
when it resets — Claude Code and Codex, from PowerShell.

The VS Code panel already queues a message you send while Claude is working.
What it won't do is hold one you send while the subscription limit is used up:
that is refused with *"You've hit your session limit"* and dropped. So you wait,
and at the reset you go round every chat typing again. chatq is the queue for
that moment:

```
PS> chatq 'Parser rewrite and plugin unification' -Prompt 'Also update the changelog'
  -> 'Parser rewrite and plugin unification' (2h)  claude · exact title
     auto (as the chat last ran) · D:\src\parser
  queued #1  sends 13:01 (five_hour limit resets 13:00)

PS> chatq 선택<Tab>          →  chatq '선택 card UI redesign'
  -> '선택 card UI redesign' (3h)  claude · exact title
     write the prompt in the editor tab, then save and close it (empty = cancel)
  queued #2  sends after #1
```

At the reset a background watcher resumes each chat, sends its prompt, lets it
run to the end, and tells your phone how it went. Then it exits.

One file, no modules, nothing to build. A sibling of
[chatrm](https://github.com/phal40lax78/chatrm), whose chat-finding code it
reuses.

## Install

```powershell
iex (irm https://raw.githubusercontent.com/phal40lax78/chatq/main/install.ps1)
```

Then type `chatq`. That downloads `chatq.ps1` to `~/Tools/chatq`, loads it, and
writes the line into your `$PROFILE`. Set `$env:CHATQ_DIR` first to put it
somewhere else.

By hand, or with the file already on disk:

```powershell
. "$HOME\Tools\chatq\chatq.ps1"
chatqinstall
```

The leading dot matters. `. chatq.ps1` loads the commands into this shell, while
`& chatq.ps1` runs them into a scope that is thrown away. The script notices and
tells you.

**Updating:** run the one-liner again. It reports `updated 0.1.0 -> 0.2.0` or
`unchanged`. An `unchanged` right after a push is usually the CDN serving the old
copy for a few minutes.

## Commands

| | |
|---|---|
| `chatq <title\|id> [-Prompt s]` | queue a prompt for that chat; without `-Prompt` an editor tab opens |
| `chatq <title> -Continue` | queue *"Continue from where you left off."* for a chat the limit cut off |
| `chatq <n>` | open queued prompt *n* in the editor — edits count until it is sent |
| `chatqlist [-Board] [-All]` | what is queued, when it sends, what ran |
| `chatqrm <n> [-Force]` / `-Finished` | drop a job; `-Force` cancels a running one |
| `chatqrun [<n>] [-Now] [-Stop]` | requeue *n*; stop waiting and try now; stop the watcher |
| `chatqlog <n> [-Raw]` | what a run did |
| `chatqnotify` | phone alerts through Join |
| `chatqinstall` / `chatquninstall [-All]` | add to, or drop from, your profile |

`chatq` flags: `-WhatIf` (show the pick, queue nothing), `-Mode auto|acceptEdits|…`
(run in another permission mode), `-At 13:00` / `-In 2h` (not before),
`-AllProjects`, `-Provider claude|codex`.

Tab completes titles. For a fragment of several words, open a quote first:
`chatq 'card red<Tab>`.

## How it picks the chat

It picks when you queue, not when it sends. You're at the keyboard now and gone
later, so the pick is printed while a wrong one can still be undone
(`chatqrm <n>`).

1. **An id** (hex, at least 6 characters) is that chat.
2. **A title** is matched in the project you're standing in, first *exact*, then
   *contains*, then *every word in any order*. It is matched in every project
   only when this one has no match, and the output says which project.
3. **Nothing matches:** the candidates are every chat in this project. It never
   guesses across projects, because a prompt landing in another repo's chat
   would act on that repo. Standing in a folder that is no project at all, it
   refuses to guess, unless you add `-AllProjects`.
4. **Several candidates:** the newest wins, unless others were active within 5
   hours of it — one limit window, so recency can't tell them apart. Then the
   most relevant one wins. Relevance is the cosine of character pairs:
   - what you typed against the chat's title, weight 0.6
   - what you typed plus the prompt against the chat's first and latest prompts, weight 0.4

   Pure PowerShell, no model call, the same answer every time. Pairs rather than
   words, so Korean particles glued to a noun still match. The runner-up and
   both scores are printed.

## When it sends

- **The reset time** comes from the record Claude writes into a transcript when
  the limit stops it (`"quotaLimits": {"status": "rejected", "resetsAt": …}`).
  For Codex it comes from the rate-limit snapshot in its rollouts, or from the
  prose of its error ("try again at …").
- **A probe goes first.** A minute after the reset, the watcher sends a
  throwaway `ok` that saves no session: about 3 seconds and half a cent on
  haiku. Sending the real prompt while still limited would plant it, and an
  error after it, in your chat. The probe uses the chat's own model, since a
  weekly limit can belong to one model.
- **One job at a time, oldest first.** A Claude job never waits behind a Codex
  limit.
- **Each chat runs in the permission mode it last used**, read from its
  transcript. `-Mode` overrides it for one job. Anything that would ask a
  question is **denied automatically**, since nobody is there to answer.
- **Needs input.** When something was denied, or plan mode stopped at a plan,
  the job is parked as **needs input** and the queue moves on. You carry on in
  VS Code, or `chatqrun <n> -Mode acceptEdits` sends it a "continue" in a mode
  that allows it.
- **Limit hit again mid-run.** The job goes back in the queue. If its prompt
  had already reached the chat, the retry is a "continue" rather than the whole
  prompt again.
- **`API Error: 529 Overloaded`** (or any other `API Error: 5xx`) is Anthropic's
  side, not your limit. The job goes back in the queue in the same way, and
  chatq watches <https://status.claude.com>. It reads the page's JSON every
  minute and resumes as soon as the **Claude Code** component is `operational`
  again. If an overload never reaches the status page, chatq retries after 1,
  2, 5 and 10 minutes, then every 15. It also probes every 15 minutes in case
  the page lags behind the service. You get one `overloaded` alert, then the
  usual `started` when it resumes.
- **Queued while not limited.** It is sent right away.

Chats you left cut off with nothing queued show up in `chatqlist` — by the limit
or by a 529 — and `chatq <title> -Continue` queues one. A "continue" that chatq
queued itself, after a limit or a 529 mid-run, is dropped rather than sent if the
chat has moved on by then — you, or Claude's own auto-continue, got there first.
One you asked for with `-Continue` or `chatqrun <n>` is always sent.

## Status

- **`chatqlist`** is one line per job, fitted to the terminal. A long prompt
  shows its first line and a size note (`↳ 1,284 chars · 23 lines`). Its first
  line says what everything waits on, e.g.
  `Claude limited until 13:00 (five_hour)` or
  `Claude overloaded since 12:03, status.claude.com: partial outage - retrying`.
- **`chatq <n>`** opens the whole prompt, and you can edit it until it is sent.
- **`chatqlist -Board`** opens `data/queue.md`. Press **Ctrl+Shift+V** there for
  VS Code's markdown preview. The watcher rewrites the file on every change and
  the preview follows, so it works as a live board. Each prompt folds into a
  `<details>` block.

## Phone alerts (Join)

```powershell
chatqnotify -ApiKey <your Join API key> -Device group.phone
```

The key and device ids are at <https://joinjoaomgcd.appspot.com> under the
**Join API** button. `-Device` takes a device id, a group (`group.phone`,
`group.android`, `group.all`) or a device name. `chatqnotify -Test` sends one.
On Windows the key is stored DPAPI-protected, readable only by you on this
machine.

| event | priority | says |
|---|---|---|
| `chatq · started` | 0 | chat, mode, first line of the prompt |
| `chatq · needs input` | 2 | chat, what was denied, the end of the reply |
| `chatq · done` | 1 | chat, how long, the end of the reply (`asks:` when it ends on a question) |
| `chatq · failed` | 2 | chat, why |
| `chatq · limited` | 0 | the limit came back mid-run; when it continues |
| `chatq · overloaded` | 0 | a 529; what status.claude.com says; it resumes by itself when Claude is back |

**Tasker:** every title starts `chatq ·`, so a profile on the Join plugin's
event can filter on it, or match only `needs input` and `failed` for a louder
sound.

Alerts also go to `data/logs/alerts.log`, with or without Join. The text carries
the chat title and the last few lines of the reply, and it passes through Join's
and Google's push servers.

## Chats open in VS Code

The panel shows one chat, but each VS Code window keeps a `claude` process alive
for every chat you have opened in it. Clicking a chat in the history list
switches back to that live process rather than re-reading the transcript.

So a chat still alive in a window won't show what chatq ran until the window
reloads — the run *is* in the transcript. chatq handles it like this:

- **The chat is busy** (you're typing in it, or Claude's own auto-continue is
  running it): chatq waits, re-checking every 5 minutes.
- **The chat is idle:** it runs, and the done alert adds *"reload the VS Code
  window before typing in this chat"* (**Ctrl+Shift+P → Developer: Reload
  Window**). Typing into the stale view instead would continue from the old
  history.

Setting `"liveIdle": "stop"` in `data/config.json` ends the idle process before
the run instead, so the next click re-reads the transcript. That setting is not
yet tested against the panel, which is why it isn't the default.

## Codex

- A thread is found by its name in `~/.codex/session_index.jsonl`.
- It is resumed with `codex exec resume <id>` in its own folder, in the sandbox
  mode it last used.
- `codex exec` never asks for approval, so a Codex job can't report
  needs-input. It ends done or failed.

## Where it looks, and what it writes

| | |
|---|---|
| Claude Code | `~/.claude/projects/<slug>/<uuid>.jsonl` (`CLAUDE_CONFIG_DIR` honoured) |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, `~/.codex/session_index.jsonl` (`CODEX_HOME` honoured) |
| the CLIs | `claude` / `codex` on PATH, else the copy bundled in the VS Code extension; `CHATQ_CLAUDE` / `CHATQ_CODEX` override |

Everything chatq writes is in `data/` beside the script:

- `queue/` holds a job file plus its prompt as `#<n> <title>.md`
- `logs/` holds each raw run, `watcher.log` and `alerts.log`
- `queue.md` is the board
- `config.json` holds the Join key and `liveIdle`
- `chat-index.csv` is what Tab completes from

There are no registry keys, no AppData and no scheduled task.

## Things to know

- **Sleep.** While a job is due within 6 hours, the watcher keeps the machine
  from sleeping: `SetThreadExecutionState` on Windows, `caffeinate` on macOS,
  `systemd-inhibit` on Linux. The display still turns off, and closing a laptop
  lid still sleeps it.
- **Reboot.** Nothing registers with the OS, so after a reboot the watcher comes
  back when you next open a shell.
- **Weekly limits** can be days away. The job simply waits, without holding the
  machine awake.
- **API keys.** `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY`
  and `CODEX_API_KEY` are kept out of the runs, so they use your subscription.
- **Accounts.** A job queued from a shell with `CLAUDE_CONFIG_DIR` or
  `CODEX_HOME` set runs in that account. Its limit is tracked on its own, apart
  from the default account's.
- **A limit on one model** (an Opus-only weekly limit, say) doesn't hold up
  chats on other models. The probe, asked with each chat's own model, decides.
- **StrictMode.** It is fine to set it in your profile; chatq turns it off only
  inside its own commands.
- **Plan mode.** A chat last in plan mode only produces a plan. chatq says so
  when you queue, and `-Mode auto` lets it act.
- **Hooks.** Your hooks, guards and `settings.json` allowlist all apply to the
  runs, exactly as in the panel.

## Uninstall

```powershell
chatquninstall        # drop the profile line, stop the watcher, keep the folder
chatquninstall -All   # and delete the folder, queued prompts included
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7. macOS and Linux need PowerShell 7.
- Claude Code 2.1.259 or later, for `--permission-prompts none`.

## Licence

MIT
