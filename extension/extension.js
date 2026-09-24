const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');

const SEEN_KEY = 'chatManagerReload.lastSeenId';
const OPEN_SEEN_KEY = 'chatManagerReload.lastOpenId';
const GUID = /^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/;

// Every wait, in one place, so the tests can set them all to nothing.
//   openSettle     after the side bar is asked for a chat, before the redraw
//   retry          before asking the Claude extension a second time
//   tabSettle      for an editor tab to appear, or to go
//   tabRecount     a second look, for a tab slow to appear
//   startupOpen    a window just opened: the Claude extension starting
//   openMaxAge     an open request older than this is not acted on
//   judgedMaxAge   the script's busy verdict older than this is not trusted
//                  for Reload Webviews without a fresh one
//   verdictTimeout Show it's check, at most
const timing = {
    openSettle: 300, retry: 2500, tabSettle: 400, tabRecount: 1500, startupOpen: 2000,
    openMaxAge: 120000, judgedMaxAge: 20000, verdictTimeout: 20000
};

// VS-code-chat-manager writes data/reload-request after chatrm deletes a chat,
// and after chatq runs a queued prompt into a chat this window still holds;
// data/open-request when the overlay's open chip is clicked. A run's chat is
// shown fresh where the Claude Code extension can do it - Reload Webviews and
// its own open commands, which no outside process can run - and otherwise the
// window reloads, as it did before.
function signalFiles() {
    const set = vscode.workspace.getConfiguration('chatManagerReload').get('signalFile');
    if (set && String(set).trim()) return [String(set).trim()];
    // only this tool's own folder: standalone chatrm is retired, so nothing
    // writes to ~/Tools/chatrm any more
    return [path.join(os.homedir(), 'Tools', 'VS-code-chat-manager', 'data', 'reload-request')];
}

// open-request sits beside reload-request, so signalFile moves both
function openFiles() {
    return signalFiles().map(f => path.join(path.dirname(f), 'open-request'));
}

let channel = null;
function log(s) {
    try {
        if (!channel && vscode.window.createOutputChannel) channel = vscode.window.createOutputChannel('chat manager');
        if (channel) channel.appendLine(new Date().toISOString() + '  ' + s);
    } catch (e) { }
}

function readRequest(file) {
    let raw;
    try { raw = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
    // PowerShell's Set-Content -Encoding UTF8 emits a BOM on Windows PowerShell
    // and JSON.parse rejects it outright. The script writes without one, but a
    // file edited by hand may well have it.
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    try { return JSON.parse(raw); } catch (e) { return null; }
}

function isGuid(s) { return typeof s === 'string' && GUID.test(s); }

// Every window watches the same file, so each decides for itself whether the
// request was for its own workspace. This is what makes the prompt land in the
// right window - something an outside process could not work out at all.
function isMine(req) {
    if (!req.cwd) return true;                  // nothing to match on
    const folders = vscode.workspace.workspaceFolders || [];
    if (!folders.length) return false;
    const want = path.resolve(req.cwd).toLowerCase();
    return folders.some(f => {
        const have = path.resolve(f.uri.fsPath).toLowerCase();
        return want === have || want.startsWith(have + path.sep);
    });
}

// The script judges one folder's chats, the job's own. A window whose only
// folder is that one holds nothing it did not judge; a multi-root window, or
// one opened on a parent folder, may hold a chat elsewhere mid-answer - so
// only the first may reload without asking.
function isExactlyMine(req) {
    const folders = vscode.workspace.workspaceFolders || [];
    if (!req.cwd || folders.length !== 1) return false;
    return path.resolve(req.cwd).toLowerCase() === path.resolve(folders[0].uri.fsPath).toLowerCase();
}

// Is that process still there? A window that closed took its pid with it.
function alive(pid) {
    try { process.kill(pid, 0); return true; } catch (e) { return !!e && e.code === 'EPERM'; }
}

// Which windows a request is for. The script names the Code.exe each window's
// claude process of the chat runs under (hostPids) - this extension host is
// that process, as the Claude extension's is - so a window that held the chat
// knows it for certain. Failing that, by folder: the window on it for a run,
// and for an open only one on exactly it, since an open always gets a window.
function isTarget(req, aliveFn) {
    const check = aliveFn || (p => module.exports._alive(p));
    const hp = (Array.isArray(req.hostPids) ? req.hostPids : []).filter(p => Number.isInteger(p) && p > 0).filter(check);
    if (hp.length) return hp.includes(process.pid);
    return req.kind === 'open' ? isExactlyMine(req) : isMine(req);
}

function hasClaude() {
    return !!(vscode.extensions && vscode.extensions.getExtension && vscode.extensions.getExtension('anthropic.claude-code'));
}

// on unless turned off: unset reads as on
function showFresh() {
    return vscode.workspace.getConfiguration('chatManagerReload').get('showFresh') !== false;
}

function ageOf(req) {
    const at = Date.parse(req.at || '');
    return at ? Date.now() - at : Infinity;
}

function name(req) { return req.title ? '"' + req.title + '"' : 'a chat'; }

const texts = {
    terminal: req => name(req) + ' is also open in a terminal, so it was not shown here. Type there, or close it first.',
    couldNotEnd: req => 'chatq could not end the old process of ' + name(req) + ', so only a reload shows the run.',
    busyTab: 'Shown in a tab of its own: another chat in this window is working.',
    pickFromHistory: req => 'Refreshed. Pick ' + name(req) + ' from the chat history to see it.',
    staleTab: req => name(req) + ' is already open in a tab that could not be refreshed. Close that tab and open the chat again.',
    heldOpen: req => name(req) + ' is held by a process chatq could not end. Reload the window to see it up to date.',
    reloadOpen: req => 'The overlay asked for ' + name(req) + '. Reload the window to see it up to date?',
    running: req => 'A queued prompt is going into ' + name(req) + ' right now, so it was left as it is. chatq offers to show it again when that run finishes.',
    checking: '$(sync~spin) Checking the chats in this window...'
};

// What to say, by what happened. A request written before 'kind' existed is a
// delete - that was the only thing that wrote one. 'busy' is the script's
// judgement, made as it wrote the request, that a chat in this workspace was
// still working - a turn in flight, a permission prompt, or a workflow or
// background agent that has not reported back. A reload now would cut it off.
// A run's chat that can be shown fresh (fresh) is offered Show it; one held
// working, a reload for later; otherwise the reload, as before.
function message(req, fresh) {
    const what = name(req);
    if (req.kind === 'ran') {
        if (fresh === undefined) fresh = canShowFresh(req);
        if (fresh && req.oldProcess === 'other') return texts.terminal(req);
        if (fresh && req.oldProcess === 'held') {
            return 'A queued prompt ran in ' + what + ' while that chat was working in this window. Reload once it finishes to show the run.';
        }
        if (fresh) return 'A queued prompt ran in ' + what + ', which this window still has open. Show it?';
        return 'A queued prompt ran in ' + what + ', which this window still has open. Reload to show it?';
    }
    if (req.kind === 'new') {
        return 'A new chat, ' + what + ', was started in this folder by chatq. Reload to pick it up?';
    }
    const done = (req.kind === 'archived' ? 'Archived ' : 'Deleted ') + what + '.';
    if (req.busy === true) {
        return done + ' A chat in this workspace is still working, and reloading now would cut it off - reload once it finishes.';
    }
    return done + ' Reload to refresh the chat list?';
}

// a request from a script that names the chat, with the Claude extension here
// to show it, and the setting on
function canShowFresh(req) {
    return !!req.sessionId && showFresh() && hasClaude();
}

// A queued run can finish at 3 a.m. with another chat in this window
// mid-answer, and a reload would lose that answer - or while you are typing
// in it. Reload Webviews cuts a working chat off just the same (S29). So it
// acts by itself only on the script's word, given as the run ended, that
// nobody had used the PC for a while (away) and no other chat in the folder
// was working (busy false), only in a window that is exactly that folder, and
// only while that word is fresh (ageMs). Unjudged is a no. The new chat a
// queued run started is never reloaded for by itself: the script judges
// neither for it. A delete reloads by itself only with autoReload, and never
// while a chat works.
function reloadsItself(req, autoReload, afterRun, exact, ageMs) {
    if (req.kind === 'ran') {
        return afterRun !== false && req.away === true && req.busy === false && exact === true &&
            !(ageMs > timing.judgedMaxAge);
    }
    if (req.kind === 'new') return false;
    return req.busy !== true && !!autoReload;
}

// How to show the chat, from the script's verdict on it:
//   webviews  Reload Webviews and the chat where you read it - only in a
//             window exactly the judged folder with nothing working, on a
//             verdict fresh or just asked for (clicked)
//   tab       a fresh editor tab of its own, which touches no other chat
//   focus     the chat as it is: loaded fresh anyway, or held working
//   reload    the whole window - its process could not be ended, or the
//             chat cannot be shown fresh here at all
//   none      a terminal holds it: nothing, or there would be two writers
function plan(req, verdict, ctx) {
    if (!ctx.fresh || !ctx.claude || !req.sessionId) return 'reload';
    const v = verdict || {};
    if (v.oldProcess === 'other') return 'none';
    if (v.oldProcess === 'held') return req.kind === 'open' ? 'focus' : 'reload';
    if (v.oldProcess === 'live' || v.oldProcess === 'kept') return 'reload';
    // no process held it: whatever shows it next loads it from disk
    if (req.kind === 'open' && v.oldProcess === 'none') return 'focus';
    if (ctx.exact && v.busy === false && (ctx.clicked || ctx.ageMs <= timing.judgedMaxAge)) return 'webviews';
    return 'tab';
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

let tabLogged = false;
function isClaudeTab(tab) {
    const ok = !!(tab && tab.input && vscode.TabInputWebview && tab.input instanceof vscode.TabInputWebview &&
        /claude/i.test(String(tab.input.viewType || '')));
    if (ok && !tabLogged) {
        tabLogged = true;
        log('a Claude tab: viewType ' + tab.input.viewType + ', label ' + tab.label);
    }
    return ok;
}

function allTabs() {
    const g = vscode.window.tabGroups;
    if (!g || !g.all) return [];
    return [].concat(...g.all.map(x => x.tabs || []));
}

function activeTab() {
    const g = vscode.window.tabGroups;
    return g && g.activeTabGroup ? g.activeTabGroup.activeTab : undefined;
}

// Asked twice at most: the Claude extension may still be starting.
async function openWith(command, sessionId) {
    for (let i = 0; i < 2; i++) {
        try { await vscode.commands.executeCommand(command, sessionId); return true; }
        catch (e) {
            log(command + ' failed: ' + (e && e.message));
            if (i === 0) await sleep(timing.retry);
        }
    }
    return false;
}

// The chat where you read it - the side bar here - then every web view in
// the window redrawn from disk (S29). Terminals, editors and other extensions
// are untouched; the window's Claude processes start again.
async function showWebviews(req) {
    const opened = await openWith('claude-vscode.editor.open', req.sessionId);
    await sleep(timing.openSettle);
    try { await vscode.commands.executeCommand('workbench.action.webview.reloadWebviewAction'); }
    catch (e) {
        log('reloadWebviewAction failed: ' + (e && e.message));
        return showTab(req);
    }
    if (!opened) vscode.window.showInformationMessage(texts.pickFromHistory(req));
    return 'webviews';
}

// The chat in an editor tab of its own. The Claude extension makes a new
// panel, loaded from disk, when the chat has none - but only reveals one it
// has, stale. So a tab that was there already, came to the front and carries
// the chat's title is closed and opened again; anything less certain is left
// alone, and you are told.
async function showTab(req) {
    const before = allTabs().filter(isClaudeTab);
    const beforeActive = activeTab();
    await vscode.commands.executeCommand('claude-vscode.primaryEditor.open', req.sessionId);
    await sleep(timing.tabSettle);
    const grew = () => {
        const now = allTabs().filter(isClaudeTab);
        return now.length > before.length || now.some(t => !before.includes(t));
    };
    if (grew()) return 'new';
    await sleep(timing.tabRecount);
    if (grew()) return 'new';
    const t = activeTab();
    const label = req.title;
    const sure = t && before.includes(t) && isClaudeTab(t) && t.label === label &&
        (t !== beforeActive || (beforeActive && beforeActive.label === label));
    if (!sure) {
        log('not closed: active tab ' + (t ? t.label : '(none)') + ', chat ' + label);
        vscode.window.showInformationMessage(texts.staleTab(req));
        return 'stale';
    }
    await vscode.window.tabGroups.close(t);
    await sleep(timing.tabSettle);
    await vscode.commands.executeCommand('claude-vscode.primaryEditor.open', req.sessionId);
    return 'reopened';
}

function focus(req) { return openWith('claude-vscode.editor.open', req.sessionId); }

function reloadWindow() { return vscode.commands.executeCommand('workbench.action.reloadWindow'); }

// Every show goes through one chain per window, so two never interleave.
let queue = Promise.resolve();
function enqueue(fn) {
    queue = queue.then(fn).catch(e => log('show failed: ' + (e && e.message)));
    return queue;
}

async function perform(how, req) {
    log(req.kind + ' ' + (req.sessionId || '').slice(0, 8) + ': ' + how);
    switch (how) {
        case 'webviews': return showWebviews(req);
        case 'tab': return showTab(req);
        case 'focus': return focus(req);
        case 'none': vscode.window.showInformationMessage(texts.terminal(req)); return 'none';
        case 'reload': return reloadWindow();
    }
    return how;
}

// ' and the curly quotes doubled: PowerShell reads all four as a quote
function psQuote(s) {
    return "'" + String(s).replace(/['\u2018-\u201B]/g, m => m + m) + "'";
}

// Show it's check: the script's Show-ChatFresh, which ends the chat's old
// idle process and judges the folder again, printing one line of JSON.
function verdictCommand(script, req) {
    if (!isGuid(req.sessionId)) throw new Error('not a session id: ' + req.sessionId);
    let cmd = "$env:CHATQ_OVERLAY='1'; . " + psQuote(script) + '; $r = @(Show-ChatFresh -Via button -SessionId ' +
        psQuote(req.sessionId) + ' -Cwd ' + psQuote(req.cwd || '');
    if (req.home) cmd += ' -ConfigDir ' + psQuote(req.home);
    cmd += ')[-1]; [Console]::Out.WriteLine((ConvertTo-ChatFreshVerdict $r))';
    const enc = Buffer.from(cmd, 'utf16le').toString('base64');
    const exe = process.platform === 'win32'
        ? path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
        : 'pwsh';
    return [exe, ['-NoProfile', '-NonInteractive', '-EncodedCommand', enc]];
}

const OLD = ['none', 'ended', 'live', 'held', 'other', 'kept'];
// the last line that is JSON, with every field the right type - else null
function parseVerdict(stdout) {
    const lines = String(stdout || '').split(/\r?\n/).map(s => s.trim()).filter(s => s.startsWith('{'));
    if (!lines.length) return null;
    let o;
    try { o = JSON.parse(lines[lines.length - 1]); } catch (e) { return null; }
    if (!o || typeof o !== 'object') return null;
    if (!(o.busy === null || typeof o.busy === 'boolean')) return null;
    if (!OLD.includes(o.oldProcess) || typeof o.outcome !== 'string') return null;
    if (!Array.isArray(o.hostPids) || !o.hostPids.every(Number.isInteger)) return null;
    return o;
}

function getVerdict(req, file) {
    const script = path.join(path.dirname(path.dirname(file)), 'VS-code-chat-manager.ps1');
    let exe, args;
    try { [exe, args] = verdictCommand(script, req); } catch (e) { log(e.message); return Promise.resolve(null); }
    return new Promise(resolve => {
        cp.execFile(exe, args, { timeout: timing.verdictTimeout, windowsHide: true }, (err, stdout) => {
            if (err) log('Show it check failed: ' + err.message);
            resolve(parseVerdict(stdout));
        });
    });
}

// The outcomes of a check that judged the chat. Any other - missing, bad -
// returned before looking at its process at all, so what it says of that
// process is nothing to act on.
const JUDGED = ['ok', 'held', 'other', 'running'];

// Show it: the check, then the chat shown by what it found. A failed check,
// or one that judged nothing, leaves the verdict to the request's own - a
// fresh tab if the process was ended, else a reload offer; never a tab
// beside a process still running. A queued prompt going into the chat now
// leaves it alone: showing it would load it part way through.
async function showIt(req, file) {
    const bar = vscode.window.setStatusBarMessage ? vscode.window.setStatusBarMessage(texts.checking) : null;
    let v;
    try { v = await module.exports._getVerdict(req, file); }
    finally { if (bar && bar.dispose) bar.dispose(); }
    if (v && !JUDGED.includes(v.outcome)) { log('Show it check judged nothing: ' + v.outcome); v = null; }
    if (v && v.outcome === 'running') {
        vscode.window.showInformationMessage(texts.running(req));
        return 'running';
    }
    const verdict = v || { busy: null, oldProcess: req.oldProcess };
    const exact = isExactlyMine(req);
    const how = plan(req, verdict, { exact, fresh: showFresh(), claude: hasClaude(), ageMs: ageOf(req), clicked: true });
    if (how === 'reload') {
        const go = 'Reload';
        const pick = await vscode.window.showWarningMessage(texts.couldNotEnd(req), go, 'Not now');
        if (pick === go) return enqueue(() => reloadWindow());
        return 'asked';
    }
    if (how === 'tab' && exact && verdict.busy === true && vscode.window.setStatusBarMessage) {
        vscode.window.setStatusBarMessage(texts.busyTab, 6000);
    }
    return enqueue(() => perform(how, req));
}

async function offer(context, req, file) {
    // Not ours: left for the window it is for. Checked before marking it
    // seen, which every window shares.
    if (!isTarget(req)) return;
    const cfg = vscode.workspace.getConfiguration('chatManagerReload');
    const exact = isExactlyMine(req);
    const age = ageOf(req);
    const fresh = req.kind === 'ran' && canShowFresh(req);

    // Marked seen BEFORE acting: the file is still on disk afterwards, so
    // without this the same request would prompt again on every reload.
    await context.globalState.update(SEEN_KEY, req.id);

    const auto = reloadsItself(req, cfg.get('autoReload'), cfg.get('autoReloadAfterRun'), exact, age);
    if (fresh) {
        if (auto) {
            const how = plan(req, { busy: req.busy, oldProcess: req.oldProcess },
                { exact, fresh: true, claude: true, ageMs: age, clicked: false });
            return enqueue(() => perform(how, req));
        }
        if (req.oldProcess === 'other') { vscode.window.showInformationMessage(message(req, true)); return; }
        if (req.oldProcess === 'held') {
            const go = 'Reload anyway';
            const pick = await vscode.window.showWarningMessage(message(req, true), go, 'Not now');
            if (pick === go) return enqueue(() => reloadWindow());
            return;
        }
        const go = 'Show it';
        const pick = await vscode.window.showInformationMessage(message(req, true), go, 'Not now');
        if (pick === go) return showIt(req, file);
        return;
    }

    if (auto) {
        reloadWindow();
        return;
    }
    const busy = req.busy === true;
    const go = busy ? 'Reload anyway' : 'Reload';
    const pick = busy
        ? await vscode.window.showWarningMessage(message(req, false), go, 'Not now')
        : await vscode.window.showInformationMessage(message(req, false), go, 'Not now');
    if (pick === go) {
        reloadWindow();
    }
}

function check(context, file, onlyRecent) {
    const req = readRequest(file);
    if (!req || !req.id || req.kind === 'open') return;
    if (context.globalState.get(SEEN_KEY) === req.id) return;
    if (!isTarget(req)) return;
    if (onlyRecent) {
        // at startup, ignore a request left over from days ago - the list it
        // was about was rebuilt from disk when this window opened
        const at = Date.parse(req.at || '');
        if (!at || Date.now() - at > 10 * 60 * 1000) return;
        // a window just opened has read every chat from disk, the run - or
        // the new chat it started - included, so it has nothing to reload
        // for; and a run's away verdict, given as it ended, is stale with
        // someone opening windows
        if (req.kind === 'ran' || req.kind === 'new') { context.globalState.update(SEEN_KEY, req.id); return; }
    }
    return offer(context, req, file);
}

// The overlay's open chip. At startup - a window code -n just opened for it -
// the chat is loaded from disk already and only needs showing; in a running
// window it is shown fresh by the same plan as a run's.
async function checkOpen(context, file, onlyRecent) {
    const req = readRequest(file);
    if (!req || req.kind !== 'open' || !isGuid(req.sessionId) || !req.id) return;
    if (context.globalState.get(OPEN_SEEN_KEY) === req.id) return;
    if (!isTarget(req)) return;
    const age = ageOf(req);
    await context.globalState.update(OPEN_SEEN_KEY, req.id);
    if (!(age <= timing.openMaxAge)) return;
    if (!showFresh() || !hasClaude()) {
        const go = 'Reload';
        const pick = await vscode.window.showInformationMessage(texts.reloadOpen(req), go, 'Not now');
        if (pick === go) return enqueue(() => reloadWindow());
        return;
    }
    if (onlyRecent) {
        await sleep(timing.startupOpen);
        return enqueue(() => focus(req));
    }
    const how = plan(req, { busy: req.busy, oldProcess: req.oldProcess },
        { exact: isExactlyMine(req), fresh: true, claude: true, ageMs: age, clicked: false });
    if (how === 'reload') {
        const go = 'Reload';
        const pick = await vscode.window.showWarningMessage(texts.heldOpen(req), go, 'Not now');
        if (pick === go) return enqueue(() => reloadWindow());
        return;
    }
    return enqueue(() => perform(how, req));
}

function activate(context) {
    // which extension host this is: the parent of this window's claude
    // processes, as the script's hostPids name it (S30)
    log('activated in extension host ' + process.pid);
    for (const file of signalFiles()) {
        check(context, file, true);
        // watchFile polls. createFileSystemWatcher only reaches inside workspace
        // folders, and this path is deliberately outside every one of them.
        fs.watchFile(file, { interval: 2000 }, () => check(context, file, false));
        context.subscriptions.push({ dispose: () => fs.unwatchFile(file) });
    }
    for (const file of openFiles()) {
        checkOpen(context, file, true);
        fs.watchFile(file, { interval: 2000 }, () => checkOpen(context, file, false));
        context.subscriptions.push({ dispose: () => fs.unwatchFile(file) });
    }
}

function deactivate() { }

// The underscored ones are exported so the path matching, the BOM strip, the
// wording, the auto rules, the plan and the command sequences can be driven
// from a test with the vscode module stubbed out - all of them decide
// whether, or how, a chat is shown, and fail silently when wrong. _alive,
// _getVerdict and _timing are replaced by the tests.
module.exports = {
    activate, deactivate,
    _readRequest: readRequest, _isMine: isMine, _signalFiles: signalFiles, _openFiles: openFiles, _message: message,
    _texts: texts, _reloadsItself: reloadsItself, _isExactlyMine: isExactlyMine, _check: check, _checkOpen: checkOpen,
    _plan: plan, _isTarget: isTarget, _alive: alive, _timing: timing, _hasClaude: hasClaude, _showFresh: showFresh,
    _isClaudeTab: isClaudeTab, _isGuid: isGuid, _psQuote: psQuote, _verdictCommand: verdictCommand,
    _parseVerdict: parseVerdict, _getVerdict: getVerdict, _showWebviews: showWebviews, _showTab: showTab,
    _focus: focus, _enqueue: enqueue, _perform: perform, _offer: offer, _showIt: showIt, _judged: JUDGED
};
