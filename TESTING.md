# Testing VS-code-chat-manager

## The self-test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1   # Windows PowerShell 5.1
pwsh -NoProfile -File tests/run-tests.ps1                                  # PowerShell 7
node tests/extension-check.js                                              # the VS Code extension
node tests/overlay-mac-check.js                                            # the overlay's macOS panel (JXA)
```

The exit code is the number of failed checks, and `-Keep` leaves the sandbox
behind for poking at. It uses no Pester, no network and no model.

- **Fake CLIs.** Every `claude`/`codex` call goes to `tests/fake-agent.ps1`
  through `tests/fake-claude.cmd`. `CHATQ_CLAUDE` and `CHATQ_CODEX` point there,
  and `FAKE_*` variables choose what it does: a stream to replay, a transcript to
  land the prompt in, a new chat's transcript written where Claude Code would
  write it for `--session-id` (`FAKE_NEW_CHAT`), live chats for `claude
  agents`, `codex archive` and `unarchive`. The `.cmd` hands its arguments over as one string, because
  `powershell -File` refuses a bare `-` (Codex's read-stdin marker).
- **A generated sandbox.** Claude, Codex and Copilot chats are written into fake
  homes under `tests/.sandbox/` with timestamps relative to now, so nothing goes
  stale. `CHAT_CODE_USER` points the Copilot provider there too — otherwise an
  index sync would read this machine's real Copilot chats.
- **A private copy.** The script and its `src/` are dot-sourced from a copy
  in the sandbox, so the run gets its own `data/`.
- **One scope, many files.** `run-tests.ps1` holds `Check`, `Section` and
  the summary; the sandbox and every section are files in `tests/sections/`,
  dot-sourced in the order its list gives, as the one file had them. A
  section uses what the sandbox and the sections before it set, so none
  runs on its own. A new section goes in that list.
- **Seams, so nothing real leaves the sandbox:** no desktop toast
  (`ChatqToastSeam`), no push service (`ChatqNtfySeam`), no idle clock
  (`ChatqIdleSeam`, as if nobody were at the PC), no real background watcher
  (`ChatqSpawn`), no ghost-watch events (`ChatNoGhostWatch`). For the overlay:
  no real overlay process (`ChatOverlaySpawn`), no usage endpoint
  (`ChatOverlayUsageSeam`), no GitHub CLI - `CHATQ_GH` names one that does
  not exist, for the child processes too, since `gh`'s login is the
  machine's and no sandbox reaches it; `ChatOverlayCopilotSeam` stands in for
  its answer - no real Windows light/dark setting
  (`ChatOverlaySystemDarkSeam`), a screen of the test's own off every real one
  for the panel's buttons (`ChatOverlayWorkAreaSeam`), no real clipboard for
  the console's paste (`ChatConsoleClipboardSeam`) and no index sync in a
  child process from it (`ChatConsoleNoSync`), and no real process
  list behind the session
  registry (`ChatqAliveSeam`) - except in the checks against a real `node`
  process, which run only where node is installed.
- **Nothing ended, nothing raised.** Showing a chat fresh ends a process and
  starts `code`, so the run sets the seams for both before any section:
  `ChatStopSeam` answers `gone` and no test can reach `taskkill`,
  `ChatParentSeam` makes every chat process a `Code.exe`'s child (pid 4242),
  and `ChatCodeSeam` answers ok. A section that needs other answers sets them
  and puts them back. `ChatWindowTitlesSeam` stands in for VS Code's window
  titles, and `ChatShowSpawnSeam` takes the command the overlay's chip would
  start. `FAKE_AGENTS_SEEN` tells whether `claude agents` ran.
- **Synthetic streams only** in `tests/fixtures/stream/`. The repo is public, so
  no real transcript goes in it.

What it covers (at 0.7.0, 475 checks in `run-tests.ps1` and 124 in
`extension-check.js`):

| area | checks |
|---|---|
| relevance | bigram cosine: identical = 1, disjoint = 0, Hangul overlap > 0 |
| resolver | exact, contains, every-word; Hangul exact and NFD-typed Hangul; the prompt breaking a tie between look-alike titles; no match stays in this project and never reaches the nested `…-Mobile` slug; a title only found in another project; hex id; a title past the 60-char clip; the 5 h edge at 4h59 (relevance) and 5h03 (newest); Codex thread names; a Copilot title named and refused, never guessed; a sentence typed where a title goes points at `-Prompt`, and a real title never does |
| metadata | cwd, last permission mode even 1.3 MB from the end, last real model, cut-off detection with its reset time, Codex cwd/sandbox |
| limits | future reset found, past one ignored; Codex full window; Codex "try again at …" prose; a cut-off chat the index has no row for yet is still listed by its title, not its uuid |
| classifier | denied → needs-input; rejected event / legacy `…\|epoch` / weekly text → limited; 529 → overloaded; a connection error → network; an expired login (401) and a plan refused (403) → auth, each reason in the API's own message — read out of the error JSON, escapes and all, else the text on one line from the refusal on, cut at 160 characters, and never from the chat's own reply; a Codex refusal the same, its `unexpected status 401` code kept; Codex "stream disconnected" → network; chatq's own time limit never counts as network; a rejected event before a successful turn → done; plan and max-turns → needs-input; error and missing result → failed; a trailing question → done with `asks` |
| overload | a 529-stopped chat recognised and listed; the status page read from a fake `status.json`; the backoff; page polled every minute; operational → probe at once; page silent 15 min → probe anyway; one alert; a reminder past 6 h |
| retries | a network drop requeued a minute out, its landed prompt as a continue that is always sent, gone after three retries; the no-reply cap counting only runs that got no reply, and starting over after one that did; a refused login holds the lane with one alert, which quotes the API, as do the watcher log (the error text whole, its type too, on a line of its own) and the status line — whether the probe met it or a run did; a block an older watcher saved, its source still `probe`, reads right |
| model and order | `-Model` kept apart from the chat's own model, used by the probe and the run (`--model`, and Codex's `-m` before the thread id); `-First` ahead of older jobs, in the list's "sends" too; `chatqrun <n> -First` |
| watcher | one full loop runs the queue and exits; a second watcher will not start; `-Now` reaches a running watcher; a restart request hands over — lock released, successor started last, state carried — and never in `-Foreground`; a cold start does not carry state |
| alerts | the toast at the PC and the phone quiet; `-Test` gets through anyway; ntfy's JSON with Hangul, the title's middle dot and priority 5; the ntfy topic never printed whole; the command hook's environment, `&` and `%PATH%` left as text; a hanging hook stopped; a pasted Join push URL gives up its key and device; `-Off`; the idle clock reads without an error; away only when known — not at the PC, not with `quietMinutes` 0, not on a clock that cannot be read |
| usage | Claude's from its cache with its age, Codex's from the newest rollout that has any, and the `chatqlist` line; a five-hour limit reads `5h limited` rather than the percent cached before it, a weekly one leaves the 5 h figure alone, and a figure an hour old is marked `stale` |
| attachments | a missing file queues nothing; `-Continue` with files refused; `-WhatIf` names them and copies none; copies in the order given, a space out of a name, the original changing later changes nothing; `chatqlist` counts them; Claude gets every path under the prompt and `--add-dir` for the job's folder; Codex gets `-i` per image and `--` before the thread id, the rest in the prompt and the image only said to be there; the same file twice goes once; a wildcard brings every match; a file locked after its check queues nothing and leaves no folder; `chatq <n> -Attach` adds to a queued job, not to one already sent, and `-Paste` of text there adds nothing; `-Paste` through a seam — a screenshot as `clip.png` without the caption that came with it, Explorer files but not folders, text as the prompt or under one, an empty clipboard refused; a pasted image beside the prompt moved in and its link rewritten; a file linked twice one copy, a look-alike name its own link; a link to a file elsewhere, `../` into chatq's data and a `\\share` all left as written and untaken; a name with parentheses and a folder named after the prompt taken, the emptied folder removed; `chatqrm` removes the job's folder |
| jobs.log | a job's queueing and its removal by `chatqrm` both land in `data/logs/jobs.log`, which outlives the job file |
| find and delete | the index holds all three providers; a Hangul Codex name read as UTF-8; an escaped Claude title unescaped; `chatfind` by title, by prompt, and `-Deep` for text past the previews; the index saved while a reader holds it for 150 ms, and a warning, not silence, when the hold outlasts the tries; `chatrm -Force` removes the transcript and every leftover (sidecars, file-history, session-env, tasks, debug, security, telemetry, todos, a job folder by the id inside it, plan files) and writes a tombstone; a plan another chat shares is kept; a locked transcript keeps its leftovers; a chat with a queued prompt is kept, and `-DropJobs` drops the job then deletes |
| archive | Claude archive → tombstone and index row gone → restore over the window's stub, leftovers and all, tombstone cleared; never over a chat with messages; not while open in a window; Codex through `codex archive` / `unarchive`; `chatuninstall -All` refuses while the archive holds one |
| reload safety | in a project of its own: all finished → idle; `busy` or `waiting` from `claude agents` → active though the transcript reads finished; a workflow started and not reported → active, where the transcript alone reads finished; the chat's process gone, or the start older than the process → idle; its `<task-notification>` → idle; a background agent, reported, then woken by SendMessage → active again; a background shell → not counted; the reload request carries `busy` either way; a chat written this minute → active, unless it is the one a queued run just wrote (`-Except`) — but that chat busy in a window still counts; a neighbour written 3 minutes ago → active over `quietMinutes`, not over one minute; a folder whose only chat is the one the run wrote → idle, not unjudged; a queued run into that chat, open and idle, with nobody at the PC → a `ran` request with `away` true and `busy` false, the one the window may take by itself |
| completion | one completer per command: `chatq 3` completes nothing, `chatq` never offers Copilot, subagent chats only with `-All`, hex completes an id, a hex-looking title still completes, a typographic apostrophe quoted; the cycler skips subagents and, for `chatq`, Copilot; a tail left mid-line comes off a `chatq` line |
| install | one profile line replaces chatrm's and chatq's; uninstall leaves the rest of the profile; `chatinstall` moves a running watcher and overlay to the new copy, and `-NoRestart` leaves them; `Test-ChatProfileLine` counts only a line loading this copy, never an old tool's; the script copied without `src/` names the parts missing and defines no command |
| extension: the terminal half | `tests/extension-check.js`, `setup.js` and `build.js` with no PowerShell started: the loader's version read, an unreadable one (`0.8.0-rc1`) no version, and compared by number; the decision - nothing there → install, older → update, the same → nothing, newer → left, a loader of no readable version → left and said once, a folder holding other files → nothing written, not even `data/`, a git work tree at the folder or above it → never written, the difference said once per version pair, no payload → nothing; when the profile is looked at at all and when asked (never after Never, after Not now at the next version, always from the palette); the lock - taken, refused, taken over once stale, and a place that cannot be written thrown rather than read as another window; `setUp` in a sandbox folder: installed parts first with no `.new` left, the same again copies nothing, settled it starts no PowerShell, updated, a newer copy left, nothing copied while another window holds the lock, a copy that fails said once a version with no `.new` and no half install; the profile step with PowerShell stood in for: Add runs `chatinstall` where the line was missing and checks again, after an update also where it was, one restart; Add with the line still missing after it → no "Added", the answer not kept, and said; a policy that would stop the line → the question says so and scripts are allowed before the line is written; a policy that will not change → no line, and said; a PowerShell that gives no answer → neither asked about nor installed into; a line already there that never runs → the policy offered once a version; Never kept until the palette asks; setup runs one at a time, a palette run after a start's rather than dropped; the build: the loader's own part list, every part present, the extension's version the script's, an SVG image caught and a link to one not, the listing README free of them; the old extension on the same file → none of it watched here and one window offers it away, another within 10 minutes not, on another file than `chatManager.folder`'s → this one handles its own; without it both files watched in the tool folder; `chatManager.folder`, `~` in it, a relative one refused for the default, the old `signalFile` taken only as a `data/reload-request`, and `chatManagerReload.*` read where the new ones are unset |
| StrictMode | dot-sourced and used from a `Set-StrictMode -Version Latest` shell — once as the tests run it, once as a real shell loads it (not the watcher, no queue yet, stop on the first error) |
| runner | stdin byte-exact on 5.1 (Hangul, quotes, `\`, `%`, newlines, no BOM); API key and `CLAUDECODE` kept out; 400 KB of stderr without deadlock; timeout kills the whole tree; argument quoting round-trips through a compiled echo exe |
| jobs | queueing records cwd and mode; the prompt file is named after the chat; done / limited / needs-input / skipped `-Continue` / busy chat deferred / idle live chat run, with a reload request for that window; 529 mid-run; an interrupted run failed and not resent; `chatqrm -Force` with no watcher |
| job core | a job `chatq` makes has the fields it always had, in their order, plus `sendNow`; a row by its id, exact and in any case, never fuzzy; `New-ChatqJob` says why and leaves nothing behind for an empty prompt, a Copilot chat, a continue with files, a chat whose transcript is gone, a file gone before it was copied; first, send now, a model, a not-before time, a staged file moved in and a pasted image; two jobs for one chat inside a second get ids of their own, and a job is found by its whole id even when the other's id starts with it (a prefix match found both and returned neither, and the watcher spun on the first); the first one put first sorts ahead; files go only to a job still waiting; `Remove-ChatqJob` takes the prompt and files; a run's log read as entries, a tail read reading fewer, and read while a run holds it open to write (`File.ReadLines` threw there); `Stop-ChatqJobRun` leaves a job that already ended as it ended; `Request-ChatqWatcher` never waits - the wake to a running watcher, a start when none runs, 'waiting' then 'failed' after 10 s, one that was running when poked and has gone since started again once |
| new chats | the job's session id chosen when it is queued and its transcript's path known, named by the prompt's first line; its first run is `--session-id` and `--name`, no `--resume`, and lands where it said; a window on that folder is offered the reload, in words of its own; the chat it made is found by id and the next prompt resumes it; limited after its prompt landed, it goes on as "continue" in that same chat, and its reload is offered when that finishes, not lost with the run the limit cut; filed by Claude under a folder that is not the slug (`CLAUDE_CODE_PROJECT_DIR_NAME` in the fake; a path over 200 characters does the same), it is found by its id, kept, and a requeue resumes it - the fake refuses a second `--session-id`, as `claude.exe` does; a title with `"` and `&` reaches `claude.cmd` whole but for those, and nothing after it is lost to cmd.exe; deleted since, its continue fails as a chat gone and nothing starts; a folder that is not there, or no prompt, makes no job; a new chat at a drive's root keeps `C:\` and Claude's slug `C--`; a job with no session never breaks the cut-off list |
| status | the board folds prompts; Hangul cell widths; a zero-width cell; Join URL length and device routing |
| extension | `tests/extension-check.js`: which window a request is for (not the `-Mobile` sibling), the wording per kind and while a chat works, `autoReload` never while one works and never alone after a queued run; a queued run reloads by itself only with `away` true and `busy` false — not at the PC, not while another chat works, not on either unjudged or missing, not with `autoReloadAfterRun` off, not in a window that is not exactly the job's one folder (a subfolder, a multi-root window), and with it unset it does; a new chat a run started is never reloaded for by itself, with `autoReload` or on an away verdict; end to end from a request file — a window just opened marks a recent run, or a recent new chat, seen and neither asks nor reloads, an open one reloads, a multi-root one asks; the file watched |
| show fresh: the old process | the registry's `entrypoint` read, its `.key` never opened; `-RegistryOnly` never starts `claude agents`; VS Code's own process told apart - `claude-vscode` under `Code` or `Code - Insiders`, an unnamed entrypoint counting, a terminal's, a shell's child, or a parent younger than the child not; `Stop-ChatIdleProcess`: idle with its registry file → ended, the window's host pid named; busy or waiting → held; a workflow the window's process started (`entrypoint` `claude-vscode`) → held, one a print-mode run started (`sdk-cli`) with that run gone → ended; a print-mode claude of the chat alive → held, a window's process beside it not ended; a terminal's claude → other, and nothing ended, not even a window's beside it; `-JudgeOnly` → live, nothing ended; busy when its file is read again → held; no file to read → kept; `liveIdle: stop` ends the process once and the window is told, and with a workflow in flight the job waits and nothing is ended |
| show fresh: the request | after a run with nobody at the PC → ended, `busy` false, the host pids in the request; at the PC → live, nothing ended; the chat itself working → held and busy; background work told apart by who started it, never by when - `Test-ChatIdle` passes over a print-mode run's leftover workflow once no such run is alive and counts it while one is, a run that left one behind still ends the process with `busy` false, and so do Show it and the chip afterwards (they had read it as held for good), while a workflow the window's own process started during the run → held, busy, nothing ended; Show it while a queued prompt runs into the chat, or a print-mode claude does → `running`, held, busy, nothing ended; a check that judged nothing (missing) says `kept`, not `none`; after a `ran` or `open` request for a chat, the next run into it waits 30 s - not counted as busy, no attempt used - and another chat's request, or one past 30 s, holds nothing; a run a window opened the chat during (the fake writes its registry file mid-run) → its process ended, a `ran` request, the alert; one in the registry from before that nothing listed live → no request; the chip's `data/open-request` BOM-less with the chat, its folder, title, verdict and window, `code` asked once for the folder, and a run's `reload-request` left byte for byte; the chip on a terminal's chat → 20, nothing written, no `code`; on a working chat → 10; with a queued prompt running in it → 15; held in a window with none exactly its folder → 25 and no `code -n`, one exactly it → `code`; not started → 30; no `code` → 40; no session id → 50; Show it's verdict one ASCII line of four fields; end to end, the alert per old process - `Show it in VS Code to see the run`, `before typing`, `open in a terminal too` |
| show fresh: code and the chip | `VSCODE_*` and `ELECTRON_*` dropped for `code`, in any case, the rest kept; `code.cmd` through cmd with `&` literal, a `%` refused, an `.exe` started itself with `-n`; `CHATQ_CODE` first, else the installers' place; with two installs, the `code.cmd` beside the running `Code.exe` before PATH, one with no `bin\` beside it passed over; the chip's child command - `'` and `’` doubled, the title only as base64, `CHATQ_OVERLAY` set, exiting with the outcome, no spawn for a non-GUID row; the chip after a 1 s rest and not before, never on a sweep, kept while on it, gone at once on another row, kept 300 ms off everything and then gone, never with a button held, collapsed, mid-drag or twice in one visit; the rest starting only when the pointer moves onto a row; a chip that came up under the pointer taking no click until the pointer has been off it; a row's last pixel in and the next out; placed flush right, centred, kept on the screen; only a Claude row with an id and a folder; the tray's words per exit; a window exactly on the folder told from its title, also with a profile's name after the folder's - only a name VS Code's `storage.json` lists is taken off - and the chip on such a window brings it forward rather than giving 25; in the STA panel test, rows carrying their row, the chip's style (tool window, no activate, layered, not click-through, no taskbar), flush with its row, and hidden by a redraw without its row and by hiding the panel |
| extension: show fresh | `tests/extension-check.js`: the plan over every verdict - a terminal's → nothing, held → a reload for a run and a focus for an open, live or kept → reload, an open no process held → focus, exact with nothing working judged 5 s ago → Reload Webviews, 30 s ago → a tab unless just clicked, unjudged or not exact → a tab, an old writer, `showFresh` off or no Claude extension → reload; the target window by live host pid, not a window when another live one held it, by folder once every holder is gone; never by itself on a held chat or a judgement over 20 s old; the words for Show it, held, terminal, old writer and after Show it; Reload Webviews runs exactly `editor.open` then the redraw, still redraws and says where to look when the chat would not open, and falls back to a tab when it throws; a tab: none open → one opened, a stale one with the chat's title → closed and opened again, a title that does not match or an editor that is no Claude tab → nothing closed, a slow new tab caught by the second look → nothing closed; two shows queued together never interleave; Show it's command quoted (curly ones too), marked as the overlay, and never built for a non-GUID; the verdict read past noise, bad JSON or wrong types none; end to end a quiet exact window shows by itself, a multi-root one asks and Show it opens a tab, a verdict a minute old asks, a failed check on a process left running offers the reload, and so does a check that judged nothing (`missing`, `bad`) - never a tab beside that process; Show it while a queued prompt goes into the chat shows nothing, reloads nothing and says why; an open in a quiet exact window redraws, one no process held only focuses, one for a window not exactly its folder does nothing, at startup only focuses, five minutes old is dropped as seen, and the same one twice acts once; `open-request` beside the signal file and following `signalFile` |
| overlay: transcripts | the newest prompt and title of a 3 MB chat from its last 256 KB, counted in bytes read; read back past a 3 MB line when no record follows it; a budget stops the search and keeps the title found; a `last-prompt` that is machinery falls back to the real prompt; a Hangul prompt cut by a block edge put back together; a rename wins over the generated title; a transcript that grew read only from where it was; `/compact` the way it goes - while it runs, the dequeue with no record after it marked pending; once written, the command newer than the prompt before, not the compaction's summary; kept while only the old `last-prompt` is written again, 100 KB on; replaced by the same words as the prompt before, typed again (by its timestamp), and by the next prompt; a prompt after `/model opus[1m]` wins, the arguments read; a skill the model loads is no command; a working row on a pending command says so, an idle one does not |
| overlay: sessions | `sessions/<pid>.json` read and the `.key` beside it never opened (held locked, so a read would fail); a dead entry, a new chat tab with no transcript, and chatq's own `claude -p` runs get no row; one chat in two windows is one row at the more urgent state, and one window closing leaves the other; the watcher's fallback reads the same registry with `waitingFor`; against a real process: matching start → alive, `procStart` an hour off, a reused pid and another machine's entry → not, a macOS date `procStart` not held against it |
| overlay: rows | waiting oldest first, then working, running, idle newest first, queued in queue order; a prompt queued for an open chat rides on its row; a job row carries its first line; the snapshot's counts match its rows |
| overlay: usage | the live answer's 5 h, week, and a model's week once used, in the server's colours; not asked again on the next pass; a window whose reset passed reads empty and is asked about at once; a 401 falls back to the cached figure and waits 10 minutes, a 429 with no Retry-After 5 and says when it asks again; the refresh button asks at once after that, but not twice in 20 s; what a click did is said at the end of Claude's usage - asking, then when Claude answered, gone 10 s on, or why it did not ask - and reaches overlay.json on the next pass; an old Codex figure says it is from Codex's last run; each provider's line ends in when its figure is from or what is happening to it (asking, checked, cached, last run, retry at the named wait) - under its name as bars - and in neither view does any of that take a row of its own, and a time over a week old shows its date (`Mar 13`, not the weekday that read six months as last Friday); Copilot's quota read from GitHub's answer on the free plan (chat, code) and a paid one (premium alone), a fraction of a percent kept as one (`[Math]::Max(0, 0.1)` had rounded it away), a Copilot line from gh's answer, and none - quietly - when gh is not logged in or not there; Retry-After read from a real `HttpResponseMessage` as seconds (2867, the figure the live endpoint sent) or as a date; a 429 with Retry-After waits that long, says `rate-limited until`, and the refresh button keeps to it; the panel's note says so over the last live figure too; a live figure 16 minutes old is not stale while idle asks are 15 apart, a cached one is; with live usage off, only the cache shows; a restart restores the last live figure and that wait from `overlay.json` and does not ask; an expired login is not used; a failed ask is logged and the token appears in no file; a machine with no Codex still gets Claude's |
| overlay: control | a running overlay is shown, never started twice; `-Stop`, `chatinstall` and `chatuninstall` reach it; commands taken once, a stale one dropped, a pass with none queues none; the collector loop ends on `restart`; `overlay.json` BOM-less with Hangul, schema 1, epoch ms; `-Unlock` / `-Reset` / `-Collapse` wait in `overlay-state.json` while it is not running, and `-Expand` undoes it; `-AutoStart on` read at shell start; hotkeys parsed and nonsense refused; `-UsageView` and `-CopilotUsage` kept, lines by default and for a view it does not know; `-Theme` and `-Opacity` kept, a percent read as one, an opacity out of range refused, an unknown theme drawn dark; `system` following the (stood-in) Windows setting; both palettes name every colour; the buttons' window on the panel's top edge flush with its right, under the panel when the screen's top leaves no room, kept on the screen side to side (on a second screen too), and left on its side when the box opens where only the buttons fit; the panel's default spot leaves room above it for them; the buttons come only after the pointer rests 350 ms on the panel or on the spot they go - their zone takes in the gap to the panel, above it or below - never with a mouse button held, stay while it is on either or a button is held or a drag runs, and go 700 ms after it leaves; placement back onto a screen; the launch line (`powershell.exe -STA`, `CHATQ_OVERLAY`); the tray tooltip under 64 characters; reset countdowns |
| overlay: cut off | an open idle chat the limit stopped says when it resets and sits just under those waiting; a working one has moved on; one not open gets a row of its own with its project; a 529 says what it waits on; a continue queued replaces the row; a limit that is over says so; the scan the overlay runs every minute reads a transcript again only once it moved (none the second time, one after it grows), never reads a chat it is told is working, and names where each chat ran; a limit record with no `cwd` of its own takes the tail's; one folder it cannot list costs only that folder |
| console: pure | When - now first and looked at every 30 s, in turn neither, at/in a time or why not; search by every word in the title or project, any case, with a cap; the line saying what Send will do - soon, a limit and when it sends, a busy chat, behind others, a new chat, a 529, the watcher starting, and a refused login in the CLI's own words or a failed probe, never as "limited until"; each job's words and colour in the queue; the limit the preview names, from a usage window marked limited, else the latest reset of the chats it cut off, and never Claude's for a Codex chat - with nothing read from disk; where it opens - where it was left while it shows, else the main screen's middle; `chatconsole` tells a running overlay, or starts one with `-Open console`; the console hotkey's default, `none`, and nonsense refused |
| console: Windows window | in its own child `powershell.exe -STA`, shown off every screen and never activated: a window that can take focus and is no tool window nor topmost; the chat index read in a runspace of its own and its rows taken once ready (on the window's thread it had cost 250 ms here each time the index changed); its lists hold the cut-off and open chats, and the search narrows them; a chat picked is the one written to; a file dropped and a screenshot pasted (through the clipboard seam) become chips, a folder dropped is turned away; Send makes the job chatq would - first, sent now, both files moved in, the box and the staging folder emptied, the status saying so; a queued prompt being edited outlives a redraw of the queue; Remove asks, the second half of a double-click is no answer - timed from when the pane has redrawn, since a slow redraw on a busy machine had used up the 0.4 s and let it delete - and a click a second later is; Continue clicked twice queues one; a Codex chat is offered no mode or model and is sent none even when picked before; a theme switch keeps what is typed; closing hides it and keeps the draft in `console-state.json` |
| overlay: Windows panel | in a child `powershell.exe -STA`, built but never shown: 10 rows draw as 8 and `+2 more · 2 idle`, none as one line; both windows shown the way the host shows them, still off every screen, and their styles read after that - WPF sets `WS_EX_APPWINDOW` again as a window shows: the panel a tool window that never activates and lets clicks through, the buttons' window one that takes clicks but never focus, neither with a taskbar button; seven buttons, the console's among them, hidden until the pointer comes, the grip at the left end and close at the corner; placed by the code the pointer check runs every 120 ms, on a stood-in screen: above the panel, 4 units off and flush with its right, where they were placed before they first showed, still there after more passes (fed their own rect where their size belonged, they had jumped between two spots each pass - the blink this caught), and moved up as the settings box opens above them, never over the panel; the refresh icon turns while an ask is out and stops after; switching to light redraws the frame and keeps the settings box open; the slider itself moved sets the window's opacity, and the next pointer pass saves it to `config.json`; collapsed, one line of counts and usage and a chevron that offers to expand; usage drawn as a line - name, the windows, when it is from - and as bars, the time under the name, once the settings box says so; while the buttons are hidden, the spot the pointer check counts is the one they then show on, with the gap to the panel |
| overlay: macOS panel | `tests/overlay-mac-check.js`: the JXA pulled out of `src/overlay-mac.ps1`, pure ASCII, free of `?.` and `??`, compiled; its countdowns, bars, lines, row cap, prompt toggle, unlocked hint, commands taken once and only when newer than the panel, the menu bar count; the theme chosen from the config and the OS, both looks with every colour, usage as a line a provider ending in its time, or as bars when set; opacity held to 0.3-1 |

## CI

`.github/workflows/test.yml` runs on `windows-latest`, once under Windows
PowerShell 5.1 and once under PowerShell 7, and fails on any failed check. The
5.1 leg also fails on a non-ASCII byte in any `.ps1` — the runner is en-US, so
the CP949 problem that rule exists for would never show there — and runs the
extension check and the overlay's macOS check with node. It also packs the
extension with `vsce package`, whose `vscode:prepublish` is `extension/build.js`:
a version that is not the script's, a script that is not ASCII, or an SVG in
the listing's README or CHANGELOG fails the run before vsce reads the manifest.

`docs/make-icon.ps1` draws `extension/icon.png`, the Marketplace icon.

On pwsh 7 `Add-Type` builds libraries only, so the argument-quoting check builds
its echo exe with .NET Framework's `csc.exe` instead. Where neither can, it says
`skip` and is not counted as passed.

## The demo frames

`docs/make-demo.ps1` draws every frame in the README: `docs/demo-queue.svg`,
`docs/demo-list.svg`, `docs/demo-overlay.png`, and the `chatrm` walk-through,
`docs/demo-1-type.svg` to `docs/demo-4-reloaded.svg`.
- **The overlay frame is the real panel,** rendered off screen by WPF from the
  real collector reading a made-up session list, so it needs Windows
  PowerShell. Only the usage endpoint is a stand-in, answering what the
  sandbox's cache says.
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

| S21 | work sent to the background, and whether the chat reads idle (Claude Code 2.1.280) | a background agent, then a one-agent workflow, were started and the turn ended each time, with a poller reading both checks every 4 s. `claude agents --json` kept the chat `busy` until the work finished, both times. The old transcript-only check called the project idle 60 s after the turn ended, for the last 50 s of each run: the bug 0.3.1 fixes. The new check said active throughout, and the transcript search held the workflow's task id until its `<task-notification>` landed. `Write-ChatGhostAdvice`, run mid-workflow from a scratch copy, printed `a chat is still active` and left `"busy":true`. Fed to the extension's own functions, that request matched the window, drew the warning, and would not auto-reload. On this machine's 111 real transcripts, 139 workflow and 74 agent starts each paired with a `<task-notification>` naming their task id, except one workflow whose process was restarted under it — later `TaskStop` found no such task. That is the case the process-start cut-off drops. The scan took 2.2 s over all 111 transcripts, and 127 ms for the largest, 26.6 MB |
| S28 | a queued prompt delivered into a chat open and idle in a VS Code panel, through a `claude -p` relay's `SendMessage` (Claude Code 2.1.280, 2026-09-24) | the relay (Haiku, `--tools SendMessage`) listed 11 live sessions, panel ones included, under the `name` each `~/.claude/sessions/<pid>.json` entry carries beside its `sessionId`, and sent verbatim with no hold. The idle panel chat began a turn within 3 s, shown live, no reload. It receives `Another Claude session sent a message: <cross-session-message …>` and a note that this is not typed by the user: act on it as a teammate's request, never edit settings, `CLAUDE.md` or config for a peer. `Reply with the single word PONG` it tried to send back to the relay, which had exited. `[chatq] … Do it here, in this chat … no reply is needed` with a file to create: done and answered in the chat, 20 s end to end. The same asking for a line in `data/spike/CLAUDE.md`: declined in the chat, with an offer to do it if asked there. One relay without `--safe-mode` cost $0.077, most of it writing its prompt cache. Sending from inside a Claude Code session in auto mode was stopped by the classifier as instruction poisoning; the user sent the last two by hand |
| S29 | the side bar, the Claude extension's open commands, and Reload Webviews (Claude Code VS Code 2.1.280, 2026-09-24) | **The commands.** The Claude Code extension registers `claude-vscode.editor.open(sessionId, prompt, …)`, which opens the session where you keep Claude - the side bar here, through `activateInSidebar(sessionId)` - and `claude-vscode.primaryEditor.open(sessionId, prompt)`, always an editor tab, through `createPanel`. `createPanel` only `reveal()`s a panel the session already has, stale; with none it makes a new webview panel, loaded from disk. Run from another extension, neither raises a dialog. Its URI handler, `vscode://anthropic.claude-code/open?session=<id>&prompt=<text>`, calls `primaryEditor.open`, but opened from outside VS Code first asks "Allow 'Claude Code for VS Code' extension to open this URI?"; `prompt=` only fills the input box (`setInputText`), it never sends. **The side bar** shows one chat at a time and keeps each chat's messages cached in its webview: picking a chat again from the history shows that copy. **Through the URI**, a headless chatq run into a chat idle in the side bar showed in a new editor tab, which got a new process - a second live `~/.claude/sessions/<pid>.json` entry, same `sessionId`, new pid - while the side bar's idle process stayed alive with the old memory. While a chat has an editor tab, picking it in the side bar history only focuses that tab: one surface per chat per window. **Ending the old process by hand** (checked as `claude.exe` by name and start time, status idle) and closing the tab: picking the chat in the side bar then showed the stale cached view, but a new process started from disk, so replies continued correctly. **Developer: Reload Webviews** (`workbench.action.webview.reloadWebviewAction`) redrew the side bar with the run. It also restarted the window's Claude processes - the active chat got a new one, the other chats' idle ones ended, to start again when opened - so it cuts a working chat off as a window reload does; terminals, other extensions and editors were untouched. By hand after it: the stale chat showed both replies of the run, and the chat being typed in at the time came back intact and could be continued. **Read-only checks:** each of the 9 live VS Code panel `claude.exe` processes was a direct child of `Code.exe` - 5 parent pids for 5 windows - running from `~/.vscode/extensions/anthropic.claude-code-<ver>-win32-x64/resources/native-binary/claude.exe`; their registry files carry `"entrypoint":"claude-vscode"` and `"kind":"interactive"` (only key names and those two values were read, no `.key` file opened, `messagingSocketPath` not read out); one window already ran 2.1.281. Every transcript record carries the `entrypoint` of the process that wrote it: over this machine's 112 top-level transcripts (only that key counted), 107 held only `claude-vscode`, 2 only `sdk-cli` and 3 both - chats a `claude -p` had written into as well (S25 saw `sdk-cli` on a print-mode run's records) - and all 230 `async_launched` records said `claude-vscode`; none a print-mode run started was there to see (S30 item 18). `code.cmd` clears `VSCODE_DEV`, sets `ELECTRON_RUN_AS_NODE=1` and runs `Code.exe` on `resources\app\out\cli.js`. Run from a Claude Code session's shell, `code` failed with "Invalid file descriptor to ICU data", exit 3. That was put down to the `VSCODE_*` and `ELECTRON_*` variables it inherited, which chatq clears for it - wrongly: the first clicks of the open chip failed the same way (0x80000003), and so did `code --version` with a bare environment. The `code` on PATH was a system install left half-updated since February - its `Code.exe` at the top, `icudtl.dat` and `resources\` in a `_\` beside it - while every window ran a per-user install whose own `code.cmd` works, from that shell too. chatq now takes the `code.cmd` beside the running `Code.exe` first (`Find-ChatCodeCommand`) |

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

The overlay ran on this machine, with ten real Claude sessions registered.
Nothing drove the mouse or keyboard: the window was read back with
`PrintWindow` and its extended style, and every command went through
`chatoverlay` or `data/overlay-cmd`.
- **Rows:** `chatoverlay` started it in 1.5 s, top right. The captured window
  showed the one chat waiting on input (amber, `input needed`) first, then
  the two working, then the idle ones. New chat tabs with nothing sent in them
  were left out. That was after a fix: they had shown as rows named like
  `as-bw-02`.
- **Usage:** the first pass asked the usage endpoint. It read 87% for the 5 h
  window while `~/.claude.json` still said 55%, fetched 153 minutes earlier.
- **Window style:** `WS_EX_TOOLWINDOW | NOACTIVATE | LAYERED | TRANSPARENT`.
  WPF had also set `WS_EX_APPWINDOW`, which would have put a button on the
  taskbar; it is now cleared.
- **Commands:** `-Unlock` dropped `TRANSPARENT` and `-Lock` put it back. `hide`
  hid it and `chatoverlay` showed it again. A `restart` handed over to a new
  process in under a second, and `-Stop` closed it in 2.2 s with its pid file
  and lock gone.
- **Cost:** one pass over the ten sessions took 40-60 ms, and the first read
  2 MB of transcripts. CPU was 0.07% of the machine over 20 s. The process held
  288 MB until WPF was switched to software rendering, then 162 MB, flat over
  90 s. A collector alone is about 115 MB.
- **Its parent:** it outlived the shell that started it, which exited at once.
  That shows only that it survives its parent exiting; closing a whole Windows
  Terminal or VS Code, which can end every process they started, is below.

`docs/make-demo.ps1` then found two more by rendering from a sandbox with no
Codex home. An `if` whose branch yields an empty array assigns `$null`, so the
usage header failed there, and every pass queued an empty command, which made
the panel redraw every 2 s. Both are fixed and in the table above.

## Review

v0.1.0 went through a four-angle review with a separate skeptic per finding;
the 30 confirmed defects are fixed. The v0.2.0 plan went through a design
critique before a line was written — 37 findings, among them leftovers removed
before the transcript was confirmed gone, network retries that dropped
themselves as "already continued", a watcher handoff that could leave nobody
watching, and StrictMode breaking at load. Each is fixed and, where a test can
hold it, in the table above.

The 0.4.0 overlay's buttons, collapse, refresh and usage waits went through a
three-angle review (WPF and Win32, PowerShell pitfalls, state and
lifecycle) with a skeptic per finding. It found 11 distinct defects, and
all are fixed. Among them:
- a panel hidden before a restart came back off every screen;
- the buttons popped up the moment the pointer crossed the panel, with ×
  nearest it, so a click meant for the window beside it could close the
  overlay;
- the `rate-limited until` note was hidden whenever a live figure showed, so
  the refresh button looked broken;
- a command sent during start-up was dropped;
- the style checks read the windows before WPF shows them, which is when it
  puts the taskbar flag back.

It missed one, found in use: the buttons blinked and could not be clicked.
Their placement was handed the window's rect where its size belonged, so
each pass put them somewhere new. The placement function's own tests passed
a size and were right; only the call was wrong, and nothing ran the call on
a shown window. The panel test now does, on a stood-in screen.

0.5.0 went through three independent reviews before release: the overlay
and the docs, the console, and the job core with the runner. Together they
made 33 findings - 29 distinct defects, four found by two of them - and
all are fixed.
Among them:
- two jobs for one chat inside a second got ids where one began the other,
  and the watcher could not look the first up by id, so it looped on it and
  held up the whole queue;
- a new chat's transcript was looked for only where its folder's slug said.
  Claude cuts and hashes a path over 200 characters, so there every retry
  passed `--session-id` again, which Claude refuses;
- a new chat's title went to `claude.cmd` through cmd.exe, where a `"` and
  an `&` in it ran the rest as a command of its own;
- a running job's log could not be read (`File.ReadLines` shares only
  Read), which left the console's details pane half drawn;
- Cancel on a job whose run had just ended, and whose watcher had gone,
  marked it failed and lost its result;
- the cut-off scan read every working chat's transcript each minute, and
  one folder it could not list ended the whole scan;
- the console parsed the whole chat index on its window's thread each time
  the index changed: 250 ms for 226 chats here, about 2 s for 2,000. It now
  reads it in a runspace of its own.
Each is in the table above where a test can hold it.

0.7.0's extension, which writes PowerShell profiles and can change an
execution policy, went through one review before release: 13 findings, 11
fixed, all in the table above. Among them:
- a stale `chatManagerReload.signalFile` became the place the scripts were
  written, so one naming `C:\reload-request` would have put them in `C:\`;
  a relative `chatManager.folder` would have written beside Code.exe;
- a loader whose version did not read as three numbers was taken for no
  loader, and overwritten;
- "Added." was said, and the answer kept, even when `chatinstall` failed;
  a PowerShell that gave no answer counted as one lacking the line;
- a failed copy said nothing, left `.new` files, and was tried again at
  every start;
- the git check looked at the folder only, not the ones above it;
- with the old extension watching another file than `chatManager.folder`'s,
  nobody handled requests;
- the policy was offered only after the line was written, and never where
  a line already there could not run.
Two are left as they are: one duplicate delete prompt at the switch, since
the new ID starts with no memory of requests seen, and a profile line that
does not spell the path out is asked about again, as `chatinstall` itself
would not recognise it.

## Still to check by hand

- **S4, a chat still open in the VS Code panel.** Open a throwaway chat, leave it
  idle, queue a prompt for it and let it run. Does the panel show the run, or
  does it need the reload the extension now offers? Then set `"liveIdle": "stop"`
  in `data/config.json` and repeat. The result decides the `liveIdle` default,
  and whether the reload offer after a run is needed at all. S29 answered the
  first half: the side bar does not show the run by itself, and keeps its
  cached view even once the process is ended. S30 item 5 closes the rest.
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
- **S22, the warning in a real window.** S21 drove the extension's functions,
  not a running window, and left its request where no window watches. Reload a
  window so it runs the new extension, start a workflow in one of its chats,
  let the turn end, then `chatrm` a throwaway chat in the same project. The
  window should show a warning with **Reload anyway**, not the plain
  **Reload** offer.
- **S23, the overlay by hand on Windows.** What reading the window back could
  not show:
  1. A click on the panel lands in the window under it, and typing stays there.
  2. Resting the pointer on it for a moment brings up the row of buttons
     on its top edge, outside it, flush with its top-right corner - under it
     once the panel is dragged to the top of the screen - grip at the left,
     × at the corner. Sweeping the pointer across it brings up nothing. They
     go a moment after the pointer leaves; moving from the panel onto them
     does not lose them. A click on the panel still goes through, and so
     does one on the empty space beside the buttons. With the panel near
     the top, opening the settings box leaves the buttons where they are.
  3. Holding the grip drags the panel, the buttons follow, and the position
     is kept after `chatoverlay -Stop` and a start.
  4. The settings box opens above the buttons, outside the panel: the slider
     changes the opacity as it moves and `config.json` has it a second after
     release; dragging past the box's edge keeps the slider. Dark, Light and
     System redraw at once; with System, switching Windows between light and
     dark mode follows within 5 s. Focus stays in the window you were typing
     in throughout.
  5. Collapse folds the panel to one line and the chevron turns; expand
     brings the rows back; collapsed survives a restart.
  6. Refresh inside a named wait asks nothing (the log shows no new
     `usage:` line) and Claude's line ends `not asked - wait`; outside one,
     the icon turns, and within seconds the line ends `checked` and the time,
     for 10 s. A second click inside 20 s says `just asked`. Codex's line
     ends `last run` and its date; with `gh` logged in, Copilot's line shows
     and its time moves on refresh. Lines and Bars in the settings box switch
     at once; in bars the same few words sit under each name, and neither
     view has a row of notes about usage.
  7. Hide to tray hides it, a balloon says the tray dot brings it back
     (once), and the tray dot does - also after `chatoverlay -Stop` and a
     start while hidden. × closes it, and `chatoverlay` starts it, shown.
  8. **Ctrl+Alt+Shift+O** unlocks it, a drag moves it (the buttons follow),
     and the key locks it again. Left unlocked, it locks itself two minutes
     after the pointer leaves.
  9. The tray dot's left click hides and shows it, and its menu's Lock, Hide,
     Collapse, Refresh usage, Move to top right and Quit work.
  10. Neither window is in Alt+Tab or on the taskbar.
  11. With a monitor unplugged, it moves onto the main one within 5 s.
  12. It survives closing a whole Windows Terminal window, and quitting VS
      Code, when started from each. If it does not, launch it through
      `Invoke-CimMethod Win32_Process Create`, outside their job object.
  13. `-AutoStart on` brings it back after signing out and in and opening a
      shell.
  14. After an hour, memory is still about 170 MB, and CPU stays under 0.2%
      with the 120 ms pointer check running; the log shows no 429 at the
      five-minute pace.
  15. `/compact` in a chat: its row reads "command running" while it runs
      and `/compact` once it ends.
  16. Rested on, the buttons stay still - no flicker between two places -
      and each one takes a click; opening the settings box never covers
      the panel.
- **S24, the overlay on macOS** (never run):
  1. The panel and `CQ` appear, focus stays where it was, and any Dock icon
     flash is noted.
  2. Clicks go through it; it shows on every Space and over full-screen apps.
  3. Unlock, drag, Lock, and the position is kept.
  4. Rows update, and the `procStart` format in `~/.claude/sessions/` is noted.
  5. Hidden for ten minutes, it is current when shown again (App Nap).
  6. `kill -9` of the pwsh host takes the panel away within 20 s.
  7. `osacompile -l JavaScript data/overlay-mac.js` succeeds.
  8. Hangul draws.
  9. `-LiveUsage on` reads the keychain once, after the password prompt.
  10. `chatinstall` restarts it and `chatuninstall` stops it.
  11. `-Theme light`, `-Theme system` (then flip macOS's appearance) and
      `-Opacity 60` each show within a few seconds.
- **S25, a new chat from `claude -p`** - half run. Claude Code 2.1.281 took
  `claude -p --session-id <uuid> --name "chatq spike"` in a scratch folder:
  the init line carried that id, the transcript landed at
  `projects/<slug of the folder>/<id>.jsonl` exactly as `Get-ChatSlug`
  predicts, its first record is a `custom-title` with the name, and the
  index reads it as that title (`renamed`). Its records say
  `entrypoint: sdk-cli`. The prompt itself got `ECONNREFUSED` - the shell
  that ran it had no network - which chatq reads as a network drop. Still
  open: **does VS Code's chat list show such a chat** after the window on
  that folder reloads? If not, the console's Write to this chat, or
  `claude --resume <id>` in a terminal, is the way in; the README would say
  so.
- **S26, the console by hand on Windows.** What the off-screen test cannot:
  1. Each way in opens it: the speech bubble on the overlay's buttons, Open
     console in the tray, Ctrl+Alt+Shift+Q, `chatconsole` from a shell (it
     may only flash its taskbar button - Windows keeps the focus where you
     were), and `chatconsole` with no overlay running, which starts one.
     The overlay's panel never takes focus throughout.
  2. Dropping files from Explorer onto the prompt makes chips, and a big
     one shows `copying` without the window stalling; dropping a folder on
     + New chat's folder box fills it in.
  3. Win+Shift+S, then Ctrl+V in the prompt: a `clip.png` chip. Ctrl+V of
     files copied in Explorer: a chip each. Ctrl+V of text: text.
  4. Typing Korean with the IME in the prompt and the search box.
  5. Send now into a chat open and idle in VS Code: it runs within
     seconds, the window offers the reload, and the reply is there after it;
     the console shows the job done with its reply.
  6. Send now into a chat working in VS Code: it waits, and goes within
     about 30 s of that chat going idle.
  7. + New chat in a folder: the job runs, a window on that folder is
     offered the reload, and the chat is in its list afterwards (S25).
  8. At a reset, Continue all queues one per cut-off chat, and the orange
     rows on the overlay turn into their jobs.
  9. Cancel on a running job stops it within seconds; Remove asks twice;
     an edit to a waiting prompt is what gets sent.
  10. Close the console mid-sentence with a file attached, restart the
      overlay (`chatinstall`, or `chatoverlay -Stop` and `chatoverlay`), and
      open it: the chat, the text and the file are all still there.
  11. Drag it to a monitor at another scale, resize it, close and reopen:
      it opens where it was, the size it was.
  12. Typing stays smooth with the collector running behind it.
- **S27, at the next lapsed subscription:** what `claude -p` prints. On
  2026-09-23 one read as `Claude is logged out` — every 401 and 403 did — and
  the CLI's words were not kept, so the shape is unknown.
  `tests/fixtures/stream/auth-403.jsonl` guesses a 403 `permission_error`. The
  watcher log's `error text:` line now keeps the whole error, type and all, to
  check it against; `codex-auth.jsonl` is a guess the same way.
- **S30, showing a chat fresh in a real window.** Everything 0.6.0 does in
  VS Code was driven through stubs only. Use throwaway chats, with the 2.1.0
  extension installed and the window reloaded once so it runs it.
  1. **Auto show.** `quietMinutes` 1, one window on exactly the folder, the
     chat idle in the side bar. Queue a prompt and leave the PC. The side bar
     shows the run, still on that chat after the redraw; `watcher.log` has
     one `show: ended idle chat process` line; the window's other idle chats
     start again when picked; a terminal's scrollback is intact.
  2. **Show it, nothing working.** The same, within seconds of the click;
     the status bar says it is checking; the old pid is gone. Before the
     click, type a line into the input box of another chat in that window
     and do not send it: is that draft still there after Reload Webviews?
  3. **Show it, another chat working** (a workflow running in another chat
     of that window). A fresh editor tab opens with the run, the status bar
     says why, and the workflow finishes.
  4. **A stale editor tab.** The chat open in a tab, a run into it, then
     Show it while another chat works. That tab closes and reopens fresh,
     and no other tab closes. Note the `viewType` and `label` the `chat
     manager` output channel logged for a Claude tab.
  5. **The process of the chat on screen ends.** What does the side bar
     show then - nothing, a banner, an error? Is an unsent draft in its
     input box lost? Typing gets a reply that knows the run, from a new pid.
     This decides whether a present user's process may be ended at the
     run's end, as an away one's is.
  6. **The chip.** A 1 s rest after moving onto a row shows **open**; a
     sweep shows nothing. A pointer left parked where a chip comes up never
     opens anything with its next click. Clicks elsewhere on the panel go
     through, and the keyboard focus stays where it was. The chip is in
     neither Alt+Tab nor the taskbar. A click brings the window forward, or
     only flashes it on the taskbar: note which.
  7. **`code` from where the overlay runs.** Start the overlay from a VS
     Code terminal, and from a Claude Code session's shell: `code` exits 0,
     with no ICU error. Half answered: from a Claude Code session's shell
     the running install's `code --version` exits 0 (S29's ICU crash was a
     broken second install). The chip's own `code -n` is still to see.
  8. **`code -n <folder>`.** On a folder already open it brings that window
     forward and opens no second one. With no window on it, it opens one and
     the chat shows as the window starts.
  9. **A folder open only inside a multi-root window.** The chip gives the
     balloon for 25 and opens no second window; check that
     `Test-ChatWindowExact`'s title rule told it right, also with a
     `window.title` of your own, and with a profile other than Default
     active in a window exactly on the folder (its name then follows the
     folder's in the title): that one is brought forward, not 25.
  10. **The chip on a working chat.** It only focuses; the turn is not cut.
  11. **The chip on a chat a terminal `claude` holds.** The balloon, and
      nothing opens.
  12. **The host pid.** The output channel logs `activated in extension host
      <pid>`; it equals the parent pid of that window's `claude.exe`, which
      is what `hostPids` names.
  13. **Later versions.** On Claude Code 2.1.281 or later both open commands
      still exist; a failed `executeCommand` is logged to the output channel.
  14. **Other web views.** A Codex chat working in the same window during
      Reload Webviews: is it cut off? And does the busy judgement see it? For
      Codex it has only the rollout's write time (`Test-ChatIdle`), so a turn
      quiet on disk for longer than the judgement looks back may read idle.
  15. **A stale cache on focus.** A chat whose process ended on its own,
      then a run into it, then the chip. Does the side bar show it fresh? If
      not, an open that no process held should use Reload Webviews too, when
      nothing is working.
  16. **`primaryEditor.open` while the same chat shows in the side bar.** A
      second surface, or only a focus?
  17. **Optional - decides deletes and new chats.** After `chatrm` in an
      exact window, does Reload Webviews drop the chat from the history, with
      no stub written back? Does `editor.open(<new id>)` show a chat the list
      does not have yet?
  18. **Who started background work.** Queue a prompt that starts a
      background agent or a workflow into a chat idle in the side bar, with
      you at the PC. Its `async_launched` record in the transcript says
      `"entrypoint":"sdk-cli"` (read that key only), and Show it afterwards
      ends the old process rather than reading the chat as held. While the
      run goes on, `sessions/` has a file for the `claude -p` process: note
      its `kind` (not `interactive` is what `Test-ChatPrintLive` counts on;
      with no file at all, only the queue tells chatq a run is under way).
  19. **Pointing straight at the overlay's buttons.** With them hidden, move
      the pointer from elsewhere on the screen directly to the spot above the
      panel's top-right corner and rest there: they come up under it in about
      a third of a second, and a click there works. Sweep the pointer across
      that spot without stopping: nothing comes up, and a click on the window
      underneath lands there. Drag an editor tab or a file across it, pausing
      there with the button held: nothing comes up, and the drop lands in the
      window underneath.
- **S31, the one-line installer from GitHub's zip.** Checked here only in
  Windows PowerShell 5.1, against a local zip laid out as GitHub's archive
  is - one `VS-code-chat-manager-main/` folder - with a scratch profile and
  empty chat homes. After the push that brings `src/`, with
  `$env:CHAT_MANAGER_DIR` on an empty folder: it prints `downloading`, the
  folder holds the script and every part in `src/`, `data/download/` is
  gone, and `chat` works in that shell. In PowerShell 7 too.
- **S32, the Marketplace extension** (docs/marketplace-spec.md). Checked here:
  `vsce package` packs 0.7.0 - the loader and all 14 parts in `payload/` -
  and, against this machine's own profile, the profile step's two read-only
  calls answer right (the line is there; the policy is RemoteSigned). Spike
  M2 on 2026-09-25: neither `vs-code-chat-manager` nor "VS Code Chat
  Manager" is taken - the page for the ID is a 404, and the Marketplace's
  search for "chat manager" has neither. Still to see, in Windows Sandbox
  or a spare Windows user:
  1. **A clean install from the Marketplace:** the scripts in
     `~/Tools/VS-code-chat-manager`, the profile question, then - from
     `Restricted` - the policy question, and `chat` in a new terminal.
  2. **An update, 0.7.0 to 0.7.1**, with three windows open: one window
     copies, the files are replaced, the watcher hands over after its job
     and the overlay restarts, and the update note says terminals keep the
     old commands.
  3. **This machine:** the folder is a git checkout, so nothing is written;
     at another version it says so once.
  4. **The old extension** (spike M3): the new one leaves requests to it,
     one window offers to uninstall it, `workbench.extensions.uninstallExtension`
     takes a copied-in, unpublished extension away, and the reload finishes it.
  5. **A Remote-SSH or WSL window:** the extension runs on the local side.
  6. **Spike M4:** after a Marketplace update, do open windows restart the
     extension by themselves, or wait for *Restart Extensions*?
- **macOS and Linux** are untested; the Unix branches are written but have never
  run.
