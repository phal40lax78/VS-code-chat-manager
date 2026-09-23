# Testing VS-code-chat-manager

## The self-test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1   # Windows PowerShell 5.1
pwsh -NoProfile -File tests/run-tests.ps1                                  # PowerShell 7
node tests/extension-check.js                                              # the VS Code extension
```

The exit code is the number of failed checks, and `-Keep` leaves the sandbox
behind for poking at. It uses no Pester, no network and no model.

- **Fake CLIs.** Every `claude`/`codex` call goes to `tests/fake-agent.ps1`
  through `tests/fake-claude.cmd`. `CHATQ_CLAUDE` and `CHATQ_CODEX` point there,
  and `FAKE_*` variables choose what it does: a stream to replay, a transcript to
  land the prompt in, live chats for `claude agents`, `codex archive` and
  `unarchive`. The `.cmd` hands its arguments over as one string, because
  `powershell -File` refuses a bare `-` (Codex's read-stdin marker).
- **A generated sandbox.** Claude, Codex and Copilot chats are written into fake
  homes under `tests/.sandbox/` with timestamps relative to now, so nothing goes
  stale. `CHAT_CODE_USER` points the Copilot provider there too — otherwise an
  index sync would read this machine's real Copilot chats.
- **A private copy.** The script is dot-sourced from a copy in the sandbox, so
  the run gets its own `data/`.
- **Seams, so nothing real leaves the sandbox:** no desktop toast
  (`ChatqToastSeam`), no push service (`ChatqNtfySeam`), no idle clock
  (`ChatqIdleSeam`, as if nobody were at the PC), no real background watcher
  (`ChatqSpawn`), no ghost-watch events (`ChatNoGhostWatch`).
- **Synthetic streams only** in `tests/fixtures/stream/`. The repo is public, so
  no real transcript goes in it.

What it covers:

| area | checks |
|---|---|
| relevance | bigram cosine: identical = 1, disjoint = 0, Hangul overlap > 0 |
| resolver | exact, contains, every-word; Hangul exact and NFD-typed Hangul; the prompt breaking a tie between look-alike titles; no match stays in this project and never reaches the nested `…-Mobile` slug; a title only found in another project; hex id; a title past the 60-char clip; the 5 h edge at 4h59 (relevance) and 5h03 (newest); Codex thread names; a Copilot title named and refused, never guessed; a sentence typed where a title goes points at `-Prompt`, and a real title never does |
| metadata | cwd, last permission mode even 1.3 MB from the end, last real model, cut-off detection with its reset time, Codex cwd/sandbox |
| limits | future reset found, past one ignored; Codex full window; Codex "try again at …" prose; a cut-off chat the index has no row for yet is still listed by its title, not its uuid |
| classifier | denied → needs-input; rejected event / legacy `…\|epoch` / weekly text → limited; 529 → overloaded; a connection error → network; an expired login → auth; Codex "stream disconnected" → network; chatq's own time limit never counts as network; a rejected event before a successful turn → done; plan and max-turns → needs-input; error and missing result → failed; a trailing question → done with `asks` |
| overload | a 529-stopped chat recognised and listed; the status page read from a fake `status.json`; the backoff; page polled every minute; operational → probe at once; page silent 15 min → probe anyway; one alert; a reminder past 6 h |
| retries | a network drop requeued a minute out, its landed prompt as a continue that is always sent, gone after three retries; the no-reply cap counting only runs that got no reply, and starting over after one that did; a login gone holds the lane with one alert |
| model and order | `-Model` kept apart from the chat's own model, used by the probe and the run (`--model`, and Codex's `-m` before the thread id); `-First` ahead of older jobs, in the list's "sends" too; `chatqrun <n> -First` |
| watcher | one full loop runs the queue and exits; a second watcher will not start; `-Now` reaches a running watcher; a restart request hands over — lock released, successor started last, state carried — and never in `-Foreground`; a cold start does not carry state |
| alerts | the toast at the PC and the phone quiet; `-Test` gets through anyway; ntfy's JSON with Hangul, the title's middle dot and priority 5; the ntfy topic never printed whole; the command hook's environment, `&` and `%PATH%` left as text; a hanging hook stopped; a pasted Join push URL gives up its key and device; `-Off`; the idle clock reads without an error |
| usage | Claude's from its cache with its age, Codex's from the newest rollout that has any, and the `chatqlist` line; a five-hour limit reads `5h limited` rather than the percent cached before it, a weekly one leaves the 5 h figure alone, and a figure an hour old is marked `stale` |
| attachments | a missing file queues nothing; `-Continue` with files refused; `-WhatIf` names them and copies none; copies in the order given, a space out of a name, the original changing later changes nothing; `chatqlist` counts them; Claude gets every path under the prompt and `--add-dir` for the job's folder; Codex gets `-i` per image and `--` before the thread id, the rest in the prompt and the image only said to be there; the same file twice goes once; a wildcard brings every match; a file locked after its check queues nothing and leaves no folder; `chatq <n> -Attach` adds to a queued job, not to one already sent, and `-Paste` of text there adds nothing; `-Paste` through a seam — a screenshot as `clip.png` without the caption that came with it, Explorer files but not folders, text as the prompt or under one, an empty clipboard refused; a pasted image beside the prompt moved in and its link rewritten; a file linked twice one copy, a look-alike name its own link; a link to a file elsewhere, `../` into chatq's data and a `\\share` all left as written and untaken; a name with parentheses and a folder named after the prompt taken, the emptied folder removed; `chatqrm` removes the job's folder |
| jobs.log | a job's queueing and its removal by `chatqrm` both land in `data/logs/jobs.log`, which outlives the job file |
| find and delete | the index holds all three providers; a Hangul Codex name read as UTF-8; an escaped Claude title unescaped; `chatfind` by title, by prompt, and `-Deep` for text past the previews; `chatrm -Force` removes the transcript and every leftover (sidecars, file-history, session-env, tasks, debug, security, telemetry, todos, a job folder by the id inside it, plan files) and writes a tombstone; a plan another chat shares is kept; a locked transcript keeps its leftovers; a chat with a queued prompt is kept, and `-DropJobs` drops the job then deletes |
| archive | Claude archive → tombstone and index row gone → restore over the window's stub, leftovers and all, tombstone cleared; never over a chat with messages; not while open in a window; Codex through `codex archive` / `unarchive`; `chatuninstall -All` refuses while the archive holds one |
| completion | one completer per command: `chatq 3` completes nothing, `chatq` never offers Copilot, subagent chats only with `-All`, hex completes an id, a hex-looking title still completes, a typographic apostrophe quoted; the cycler skips subagents and, for `chatq`, Copilot; a tail left mid-line comes off a `chatq` line |
| install | one profile line replaces chatrm's and chatq's; uninstall leaves the rest of the profile |
| StrictMode | dot-sourced and used from a `Set-StrictMode -Version Latest` shell — once as the tests run it, once as a real shell loads it (not the watcher, no queue yet, stop on the first error) |
| runner | stdin byte-exact on 5.1 (Hangul, quotes, `\`, `%`, newlines, no BOM); API key and `CLAUDECODE` kept out; 400 KB of stderr without deadlock; timeout kills the whole tree; argument quoting round-trips through a compiled echo exe |
| jobs | queueing records cwd and mode; the prompt file is named after the chat; done / limited / needs-input / skipped `-Continue` / busy chat deferred / idle live chat run, with a reload request for that window; 529 mid-run; an interrupted run failed and not resent; `chatqrm -Force` with no watcher |
| status | the board folds prompts; Hangul cell widths; a zero-width cell; Join URL length and device routing |
| extension | `tests/extension-check.js`: which window a request is for (not the `-Mobile` sibling), the wording per kind, the two files watched |

## CI

`.github/workflows/test.yml` runs on `windows-latest`, once under Windows
PowerShell 5.1 and once under PowerShell 7, and fails on any failed check. The
5.1 leg also fails on a non-ASCII byte in any `.ps1` — the runner is en-US, so
the CP949 problem that rule exists for would never show there — and runs the
extension check with node.

On pwsh 7 `Add-Type` builds libraries only, so the argument-quoting check builds
its echo exe with .NET Framework's `csc.exe` instead. Where neither can, it says
`skip` and is not counted as passed.

## The demo frames

`docs/make-demo.ps1` draws every frame in the README: `docs/demo-queue.svg`,
`docs/demo-list.svg`, and the `chatrm` walk-through, `docs/demo-1-type.svg` to
`docs/demo-4-reloaded.svg`.
- **The terminal is real output:** the real commands against a sandbox of
  made-up chats, captured by a `Write-Host` of its own, which also reads the
  colour escapes the walk row carries.
- **Two steps are rebuilt:** the line Tab leaves, and the line Enter runs, are
  made with the cycler's own functions, because the PSReadLine buffer they
  write into exists only at a real prompt.
- **Two things are made to look like a real shell:** a VS Code window, since
  the reload advice prints only while one is up, and the ghost watch.
- **The panel beside the terminal is a sketch:** the sandbox's Claude chats as
  the index lists them, before and after the delete. VS Code itself is never
  captured.

Run it again after a change to what `chatq`, `chatqlist` or `chatrm` print.

## Spikes against the real CLIs

These ran once while building, against Claude Code 2.1.278 and the Codex bundled
with openai.chatgpt 26.908 (codex-cli 0.154), on throwaway chats only.

| | question | answer |
|---|---|---|
| S1 | stream-json shapes | `system/init`, `rate_limit_event` (sent even when allowed), `assistant`, and `result`, whose `type` key comes **last**. Captured to shape the fixtures |
| S2 | are auto-denied tools reported? | yes, twice: a `system/permission_denied` event, and `result.permission_denials[]` |
| S3 | `--permission-mode default` | accepted; `manual` is recorded as `default` |
| S6 | Hangul through stdin on 5.1 | intact, read from a UTF-8 file. A Hangul **literal** in a BOM-less `.ps1` is mangled by 5.1 itself — hence pure ASCII |
| S7 | the probe | 3 s and $0.0045 on haiku, reports the limit status, writes no transcript |
| S8 | model on `-p --resume` | the chat's own model is kept, so a run names one only when `-Model` asks |
| S9 | the watcher outlives its parent | yes: queued with `-In 1m` from a shell that then exited, the job ran on time |
| S11 | Codex `exec resume --json -c sandbox_mode=… <id> -` | same thread id, appended to the same rollout; `exec resume` also takes `-m` |
| S14 | `codex queue`, `archive`, `unarchive` | present in codex-cli 0.154 (`--help`); `queue` goes through the shared app-server daemon |
| S15 | the usage cache | `~/.claude.json` → `cachedUsageUtilization.utilization.limits[]`: `kind` (`session`, `weekly_all`, `weekly_scoped` with a model scope), `percent`, `resets_at`, plus `fetchedAtMs` |
| S16 | `codex archive` on a real thread | the rollout moves out of `sessions/YYYY/MM/DD/` into a flat `~/.codex/archived_sessions/`, which `chatrestore` lists; `codex unarchive` puts it back under `sessions/`. `codex delete` refuses without a terminal unless given `--force` and a UUID |
| — | archive → restore of a real Claude chat | the transcript moved into `data/archive/` and back, and the archive folder was gone after |
| — | the toast, from a shell on 5.1 | shown in-process; the idle clock read 145 s since the last input, so the phone would have stayed quiet |
| S18 | files into a resumed chat (Claude Code 2.1.280, codex-cli 0.154) | Claude, `--permission-mode default --permission-prompts none`, two PNGs, a `.txt` and a `.pdf` named in the prompt from **outside** the project: all read, the images seen as pictures, nothing denied — with `--add-dir` and without it. Codex, `-i a.png -i b.png -- <id> -`: both images seen, the text and PDF read from the prompt; it logged one `CreateProcessWithLogonW failed: 267` from its sandbox on a shell command and answered anyway |

The end-to-end run on a throwaway chat went probe → run → done through the
background watcher in 10 s, with a real `claude agents --json`. The merged file
indexed this machine's 218 real chats in 15 s and resolved a real title.

Attachments went end to end the same way, through the built code rather than
the spike's: `chatq <id> -Prompt … -Attach 'otter shot.png', plum.pdf` for a
throwaway Claude chat and a throwaway Codex thread, each job sent by
`Invoke-ChatqJob`. Both answered `IMAGE=OTTER 88 PDF=PLUM 3`. The clipboard
reader read this machine's clipboard the same both ways: in-process from 5.1's
STA console, and - from a shell started with `-MTA`, which cannot - through the
`-STA` child Windows PowerShell it starts for that. It left no folder behind.

## Review

v0.1.0 went through a four-angle review with a separate skeptic per finding;
the 30 confirmed defects are fixed. The v0.2.0 plan went through a design
critique before a line was written — 37 findings, among them leftovers removed
before the transcript was confirmed gone, network retries that dropped
themselves as "already continued", a watcher handoff that could leave nobody
watching, and StrictMode breaking at load. Each is fixed and, where a test can
hold it, in the table above.

## Still to check by hand

- **S4, a chat still open in the VS Code panel.** Open a throwaway chat, leave it
  idle, queue a prompt for it and let it run. Does the panel show the run, or
  does it need the reload the extension now offers? Then set `"liveIdle": "stop"`
  in `data/config.json` and repeat. The result decides the `liveIdle` default,
  and whether the reload offer after a run is needed at all.
- **S9, closing the terminal and quitting VS Code while the watcher waits.**
- **S10, Join**, and **ntfy**: `chatqnotify … -Test` reaches the phone, Hangul
  intact.
- **S12, at the next real limit:** the probe reports rejected with the right
  reset time, the job sends a minute after, and the transcript holds no stray
  prompt or error from the wait.
- **S13, at the next real 529:** what `claude -p` prints — an `api_retry` per
  retry, then an `is_error` result with `api_error_status: 529`, the shape
  `overloaded.jsonl` assumes — and the resume once status.claude.com is
  operational.
- **After S16:** that a thread archived and unarchived shows in the Codex panel
  again, and that one archived from the panel itself lands in the same
  `archived_sessions/`.
- **S17, the toast from the hidden watcher,** a separate hidden process rather
  than the shell.
- **S19, a screenshot through `-Paste`.** Win+Shift+S, then
  `chatq '<title>' -Prompt x -Paste -WhatIf` should say `with 1 file (… KB):
  clip.png`. Not run here: putting an image on the clipboard would have
  overwritten whatever was on it.
- **S20, Ctrl+V in the prompt tab.** Paste a screenshot into the tab `chatq
  '<title>'` opens, save and close it: the job should list `+1 file` and its
  prompt link `<job id>/image.png`. VS Code decides where the image is saved;
  chatq takes it from anywhere under `data/queue/` - beside the prompt by
  default, or in a folder named after it - so only a setting that saves it
  outside `data/queue/` would leave it behind.
- **macOS and Linux** are untested; the Unix branches are written but have never
  run.
