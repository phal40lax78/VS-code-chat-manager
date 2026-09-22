# Testing chatq

## The self-test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1   # Windows PowerShell 5.1
pwsh -NoProfile -File tests/run-tests.ps1                                  # PowerShell 7
```

The exit code is the number of failed checks, and `-Keep` leaves the sandbox
behind for poking at. It uses no Pester, no network and no model.

- **Fake CLIs.** Every `claude`/`codex` call goes to `tests/fake-agent.ps1`
  through `tests/fake-claude.cmd`. `CHATQ_CLAUDE` and `CHATQ_CODEX` point there,
  and `FAKE_*` variables choose what it does.
- **A generated sandbox.** Chats are written into fake Claude and Codex homes
  under `tests/.sandbox/`, with timestamps relative to now, so nothing goes
  stale.
- **A private copy.** chatq itself is dot-sourced from a copy in the sandbox,
  so the run gets its own `data/`.
- **Synthetic streams only** in `tests/fixtures/stream/`. The repo is public,
  so no real transcript goes in it.

What it covers:

| area | checks |
|---|---|
| relevance | bigram cosine: identical = 1, disjoint = 0, Hangul overlap > 0 |
| resolver | exact, contains, every-word; Hangul exact and NFD-typed Hangul; the prompt breaking a tie between look-alike titles; no match stays in this project and never reaches the nested `…-Mobile` slug; a title only found in another project; hex id; a title past the 60-char clip; the 5 h edge at 4h59 (relevance) and 5h03 (newest); Codex thread names |
| metadata | cwd, last permission mode even 1.3 MB from the end, last real model, cut-off detection with its reset time, Codex cwd/sandbox |
| limits | future reset found, past one ignored; Codex full window; Codex "try again at …" prose |
| classifier | denied → needs-input; rejected event / legacy `…\|epoch` / weekly text → limited; 529 Overloaded → overloaded; a rejected event before a successful turn → done; plan and max-turns → needs-input; error and missing result → failed; a trailing question → done with `asks`; excerpts drop code; Codex: a reconnect notice before `turn.completed` → done |
| overload | a chat stopped by a 529 is recognised and listed as cut off; the status page is read from a fake `status.json` (`$script:ChatqStatusUrl`); first retry after 1 min; page shows an outage → no probe, polled every minute; operational → probe at once; page silent 15 min → probe anyway; a good probe ends the outage; one `overloaded` alert |
| review regressions | a pwsh-7 `[datetime]` is not shifted; an Opus-only weekly limit blocks nothing; a limit record older than an allowed probe is ignored; a free job is never shown "after" a waiting one; no project and no match → refused; a dash-heavy title cannot close the prompt header; typographic apostrophes complete safely; dot-sourced and used from a `Set-StrictMode -Version Latest` shell |
| runner | stdin byte-exact on 5.1 (Hangul, quotes, `\`, `%`, newlines, no BOM); API key and `CLAUDECODE` kept out; 400 KB of stderr without deadlock; timeout kills the whole tree; argument quoting round-trips through a compiled echo exe |
| jobs | queueing records cwd and mode; the prompt file is named after the chat; done / limited (requeued as continue, lane blocked) / needs-input / skipped `-Continue` / busy chat deferred / idle live chat run with a reload warning; 529 mid-run → requeued as an automatic continue with its lane waiting on the status page, sent while the chat still ends on the 529, dropped once the chat moved on; an interrupted run is failed and not resent even when its old pid is alive again; `chatqrm -Force` with no watcher fails the job at once |
| watcher | one full loop runs the queue and exits; a second watcher will not start; `-Now` reaches a running watcher intact |
| status | the board folds prompts; Hangul cell widths; Join URL length and device routing |

## Spikes against the real CLIs

These ran once while building v0.1.0, against Claude Code 2.1.278 and the Codex
bundled with openai.chatgpt 26.908. All of them used throwaway chats under
`data/spike/` only.

| | question | answer |
|---|---|---|
| S1 | stream-json shapes | `system/init`, `rate_limit_event` (sent even when allowed, with utilisation per window), `assistant`, and `result`, whose `type` key comes **last**. Captured to shape the fixtures |
| S2 | are auto-denied tools reported? | yes, twice: a `system/permission_denied` event, and `result.permission_denials[]` with the tool name and input |
| S3 | `--permission-mode default` | accepted; `manual` is recorded as `default`, so they are aliases |
| S6 | Hangul through stdin on 5.1 | arrives intact in the transcript as long as the text is read from a UTF-8 file. A Hangul **literal** in a BOM-less `.ps1` is mangled by 5.1 itself, which is why `chatq.ps1` is pure ASCII |
| S7 | the probe | 3 s and $0.0045 on haiku, reports the limit status, writes no transcript |
| S8 | model on `-p --resume` | the chat's own model is kept, so runs never pass `--model` |
| S9 | the watcher outlives its parent | yes: queued with `-In 1m` from a shell that then exited, the job ran on time |
| S11 | Codex `exec resume --json -c sandbox_mode=… <id> -` | works; same thread id, appended to the same rollout |

The end-to-end run on a throwaway chat went probe → run → done, with started
and done alerts logged and `chatqlog` showing the reply. It was repeated after
the review fixes through the background watcher, including a real
`claude agents --json`, and took 10 s from queueing to done.
`Get-ChatqClaudeStatus` read the live status.claude.com (`operational`).

## Review

v0.1.0 went through a four-angle review before release: the watcher and its
state machine, PowerShell 5.1/7 pitfalls, the resolver and UI, and CLI
integration and safety. A separate skeptic checked each finding. The 30
confirmed defects are fixed, and the ones a test can hold are in the
"review regressions" and "jobs" rows above.

One finding the skeptic refuted by testing on 5.1 was fixed anyway: pwsh 7's
`ConvertFrom-Json` does turn ISO strings into `[datetime]`, so
`ConvertTo-ChatqDate` takes either.

## Still to check by hand

- **S4, a chat still open in the VS Code panel.**
  1. Open a throwaway chat and leave it idle.
  2. Queue a prompt for it and let it run.
  3. Switch back to the chat. Does the panel show the run, or does it need
     Developer: Reload Window?
  4. Then set `"liveIdle": "stop"` in `data/config.json` and repeat. Does the
     panel recover cleanly when its idle process was ended?

  The result decides the default for `liveIdle`.
- **S9, closing the terminal, and quitting VS Code, while the watcher waits.**
  The watcher is started with `Start-Process -WindowStyle Hidden`. If it dies
  with the terminal, the fallback is creating it through `Win32_Process`.
- **S10, Join.** `chatqnotify -ApiKey … -Device … -Test` confirms the endpoint
  path and that Hangul arrives.
- **S12, at the next real limit.** Queue something, then check three things:
  `chatqrun -Foreground` reports the probe rejected with the right reset time;
  it sends a minute after; the target transcript holds no stray prompt or error
  from the wait.
- **S13, at the next real 529.** Check what `claude -p` actually prints: an
  `api_retry` event per retry, then a synthetic `API Error: 529` turn and an
  `is_error` result with `api_error_status: 529`, the shape
  `tests/fixtures/stream/overloaded.jsonl` assumes. Then check that the job
  resumes on its own once status.claude.com is operational again.
- **PowerShell 7** is not installed on the build machine. Run the self-test
  under pwsh before claiming it, and on macOS/Linux before claiming those.
