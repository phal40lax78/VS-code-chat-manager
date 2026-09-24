// Checks extension/extension.js's parts with the vscode module stubbed out:
// which window a request is for, what it says, when it acts without asking,
// how it shows a chat fresh - the plan, and the commands each way runs - and
// which files it watches. Each decides whether - or how - a chat is shown,
// and each fails silently when wrong.
//
//     node tests/extension-check.js
// or, with no node on the machine, VS Code's own Electron:
//     $env:ELECTRON_RUN_AS_NODE = 1; & "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" tests/extension-check.js
//
// The exit code is the number of failed checks.
const Module = require('module');
const path = require('path');
const folders = [{ uri: { fsPath: path.resolve('/work/projA') } }];
// the settings: '' for anything unset, as VS Code's get hands back a default
const cfgVals = {};
let claudeHere = false;
class TabInputWebview { constructor(viewType) { this.viewType = viewType; } }
class TabInputText { constructor(uri) { this.uri = uri; } }
const stub = {
    workspace: { getConfiguration: () => ({ get: (k) => (k in cfgVals ? cfgVals[k] : '') }), workspaceFolders: folders },
    window: {}, commands: {},
    extensions: { getExtension: (id) => (claudeHere && id === 'anthropic.claude-code' ? { id } : undefined) },
    TabInputWebview, TabInputText
};
const load = Module._load;
Module._load = function (req) {
    if (req === 'vscode') return stub;
    return load.apply(this, arguments);
};
const ext = require(path.join(__dirname, '..', 'extension', 'extension.js'));
let failed = 0, total = 0;
const check = (name, ok, detail) => {
    total++;
    if (!ok) failed++;
    console.log((ok ? '  ok    ' : '  FAIL  ') + name + (ok || detail === undefined ? '' : '  ' + detail));
};
check('a queued run asks to reload to show it', /queued prompt ran in "T"/.test(ext._message({ kind: 'ran', title: 'T' })));
check('an archive says archived', ext._message({ kind: 'archived', title: 'T' }).startsWith('Archived "T"'));
check('a request without a kind is a delete, as the old ones were', ext._message({ title: 'T' }).startsWith('Deleted "T"'));
const busyMsg = ext._message({ kind: 'deleted', title: 'T', busy: true });
check('a delete while a chat works says so, and does not ask to reload now',
    busyMsg.startsWith('Deleted "T".') && /still working/.test(busyMsg) && !/Reload to refresh/.test(busyMsg));
check('busy: null, as when it could not be judged, asks as before',
    ext._message({ kind: 'archived', title: 'T', busy: null }) === 'Archived "T". Reload to refresh the chat list?');
check('autoReload reloads after a quiet delete', ext._reloadsItself({ kind: 'deleted', busy: false }, true));
check('but never while a chat works', !ext._reloadsItself({ kind: 'deleted', busy: true }, true));
check('autoReload alone never reloads after a queued run', !ext._reloadsItself({ kind: 'ran' }, true, true, true));
check('a new chat says so, and offers a reload to pick it up', /new chat, "T", was started in this folder/.test(ext._message({ kind: 'new', title: 'T' })));
check('and never reloads by itself for one - not with autoReload, nor on an away verdict',
    !ext._reloadsItself({ kind: 'new' }, true, true, true) && !ext._reloadsItself({ kind: 'new', away: true, busy: false }, false, true, true));
const ran = (x) => Object.assign({ kind: 'ran', away: true, busy: false }, x);
check('a queued run reloads itself when nobody is at the PC and nothing else works', ext._reloadsItself(ran({}), false, true, true));
check('which is the default, the setting unset', ext._reloadsItself(ran({}), false, undefined, true));
check('never with someone at the PC', !ext._reloadsItself(ran({ away: false }), false, true, true));
check('never while another chat works', !ext._reloadsItself(ran({ busy: true }), false, true, true));
check('never on what was not judged', !ext._reloadsItself(ran({ away: null }), false, true, true) &&
    !ext._reloadsItself(ran({ busy: null }), false, true, true) && !ext._reloadsItself({ kind: 'ran', busy: false }, false, true, true));
check('never with autoReloadAfterRun off', !ext._reloadsItself(ran({}), true, false, true));
check('and never in a window that is not exactly the judged folder', !ext._reloadsItself(ran({}), false, true, false));
check('exactly the folder: its one folder is the job\'s', ext._isExactlyMine({ cwd: path.resolve('/work/projA') }));
check('a folder inside it is not', !ext._isExactlyMine({ cwd: path.resolve('/work/projA/src') }));
folders.push({ uri: { fsPath: path.resolve('/work/projB') } });
check('nor is a multi-root window, though the request is its', !ext._isExactlyMine({ cwd: path.resolve('/work/projA') }) &&
    ext._isMine({ cwd: path.resolve('/work/projA') }));
folders.pop();
check('the window whose folder it is', ext._isMine({ cwd: path.resolve('/work/projA') }));
check('a folder inside it', ext._isMine({ cwd: path.resolve('/work/projA/src') }));
check('not the sibling -Mobile folder', !ext._isMine({ cwd: path.resolve('/work/projA-Mobile') }));
const files = ext._signalFiles();
check('by default only this tool\'s own folder', files.length === 1 &&
    files[0].endsWith(path.join('VS-code-chat-manager', 'data', 'reload-request')));

// --- showing a chat fresh: the pure parts -------------------------------------
const SID = '11111111-1111-4111-8111-111111111111';
const plan = (req, v, c) => ext._plan(Object.assign({ kind: 'ran', sessionId: SID }, req), v,
    Object.assign({ exact: true, fresh: true, claude: true, ageMs: 5000, clicked: false }, c));
check('plan: a terminal holds it - nothing', plan({}, { oldProcess: 'other', busy: false }) === 'none');
check('plan: held - a run reloads later, an open only focuses', plan({}, { oldProcess: 'held', busy: true }) === 'reload' &&
    plan({ kind: 'open' }, { oldProcess: 'held', busy: true }) === 'focus');
check('plan: a process left running or not checked - reload', plan({}, { oldProcess: 'live', busy: false }) === 'reload' &&
    plan({}, { oldProcess: 'kept', busy: false }) === 'reload');
check('plan: an open no process held - focus, it loads from disk', plan({ kind: 'open' }, { oldProcess: 'none', busy: false }) === 'focus');
check('plan: exactly the folder, nothing working, judged 5 s ago - Reload Webviews', plan({}, { oldProcess: 'ended', busy: false }) === 'webviews');
check('plan: judged 30 s ago - a tab; the same, just asked for by a click - Reload Webviews',
    plan({}, { oldProcess: 'ended', busy: false }, { ageMs: 30000 }) === 'tab' &&
    plan({}, { oldProcess: 'ended', busy: false }, { ageMs: 30000, clicked: true }) === 'webviews');
check('plan: unjudged, or not exactly the folder - a tab', plan({}, { oldProcess: 'ended', busy: null }) === 'tab' &&
    plan({}, { oldProcess: 'ended', busy: false }, { exact: false }) === 'tab');
check('plan: an old writer, showFresh off, or no Claude extension - reload', plan({ sessionId: undefined }, { oldProcess: 'ended', busy: false }) === 'reload' &&
    plan({}, { oldProcess: 'ended', busy: false }, { fresh: false }) === 'reload' && plan({}, { oldProcess: 'ended', busy: false }, { claude: false }) === 'reload');
const aliveSet = new Set();
ext._alive = (p) => aliveSet.has(p);
aliveSet.add(process.pid);
aliveSet.add(999991);
check('target: the window whose extension host held the chat, wherever its folder', ext._isTarget({ kind: 'ran', cwd: path.resolve('/elsewhere'), hostPids: [process.pid] }));
check('target: not a window when another live one held it', !ext._isTarget({ kind: 'ran', cwd: path.resolve('/work/projA'), hostPids: [999991] }));
check('target: every holder gone - the folder decides, exactly for an open',
    ext._isTarget({ kind: 'ran', cwd: path.resolve('/work/projA/src'), hostPids: [999992] }) &&
    ext._isTarget({ kind: 'open', cwd: path.resolve('/work/projA'), hostPids: [999992] }) &&
    !ext._isTarget({ kind: 'open', cwd: path.resolve('/work/projA/src'), hostPids: [999992] }));
aliveSet.clear();
check('auto: never on a held chat, never on a judgement over 20 s old', !ext._reloadsItself(ran({ busy: true, oldProcess: 'held' }), false, true, true, 1000) &&
    !ext._reloadsItself(ran({}), false, true, true, 30000) && ext._reloadsItself(ran({}), false, true, true, 5000));
claudeHere = true;
const fr = (x) => Object.assign({ kind: 'ran', title: 'T', sessionId: SID, oldProcess: 'ended' }, x);
check('says: Show it, for a run it can show fresh', ext._message(fr({})) === 'A queued prompt ran in "T", which this window still has open. Show it?');
check('says: reload once it finishes, for a chat held working',
    ext._message(fr({ oldProcess: 'held' })) === 'A queued prompt ran in "T" while that chat was working in this window. Reload once it finishes to show the run.');
check('says: use the terminal, for a chat a terminal holds',
    ext._message(fr({ oldProcess: 'other' })) === '"T" is also open in a terminal, so it was not shown here. Type there, or close it first.');
check('says: reload, as 0.5.0 did, for an old writer', ext._message({ kind: 'ran', title: 'T' }) === 'A queued prompt ran in "T", which this window still has open. Reload to show it?');
check('says: after Show it, what went wrong or how it was shown',
    ext._texts.couldNotEnd({ title: 'T' }) === 'chatq could not end the old process of "T", so only a reload shows the run.' &&
    ext._texts.busyTab === 'Shown in a tab of its own: another chat in this window is working.' &&
    ext._texts.pickFromHistory({ title: 'T' }) === 'Refreshed. Pick "T" from the chat history to see it.');
claudeHere = false;
const dec = (args) => Buffer.from(args[args.length - 1], 'base64').toString('utf16le');
const [vExe, vArgs] = ext._verdictCommand('C:\\t\\VS-code-chat-manager.ps1', { sessionId: SID, cwd: "D:\\it's here", home: 'D:\\h\u2019s' });
const vText = dec(vArgs);
check('Show it\'s check: marked as the overlay, every value quoted, curly ones too',
    vText.startsWith("$env:CHATQ_OVERLAY='1'") && vText.includes("-Cwd 'D:\\it''s here'") && vText.includes("-ConfigDir 'D:\\h\u2019\u2019s'") &&
    vText.includes('-Via button') && vText.includes('ConvertTo-ChatFreshVerdict') && vArgs.includes('-NoProfile') && !!vExe, vText);
let threw = false;
try { ext._verdictCommand('x.ps1', { sessionId: "x'; Remove-Item C:\\ -Recurse; '", cwd: 'C:\\' }); } catch (e) { threw = true; }
check('and a session id that is no GUID is never put in one', threw);
const good = '{"busy":false,"oldProcess":"ended","outcome":"ok","hostPids":[1234]}';
check('the verdict: the last JSON line, noise before it ignored', (ext._parseVerdict('loading\r\nWARNING: x\r\n' + good + '\r\n') || {}).oldProcess === 'ended');
check('bad JSON, or a field of the wrong type, is no verdict', ext._parseVerdict('{"busy":fals') === null &&
    ext._parseVerdict('{"busy":"no","oldProcess":"ended","outcome":"ok","hostPids":[]}') === null &&
    ext._parseVerdict('{"busy":false,"oldProcess":"gone","outcome":"ok","hostPids":[]}') === null &&
    ext._parseVerdict('{"busy":false,"oldProcess":"ended","outcome":"ok","hostPids":["1"]}') === null && ext._parseVerdict('') === null);
const of = ext._openFiles();
check('the open requests: data/open-request beside the reload one', of.length === 1 && of[0].endsWith(path.join('VS-code-chat-manager', 'data', 'open-request')));
cfgVals.signalFile = path.resolve('/x/data/reload-request');
check('and it follows signalFile', ext._openFiles()[0] === path.resolve('/x/data/open-request'));
delete cfgVals.signalFile;

// the whole path, request file to reload, with what the window would do recorded
(async () => {
    const fs = require('fs');
    const calls = [];
    stub.commands.executeCommand = (c) => { calls.push(c); };
    stub.window.showInformationMessage = async (m) => { calls.push('ask'); };
    stub.window.showWarningMessage = async (m) => { calls.push('warn'); };
    const state = {};
    const context = { globalState: { get: (k) => state[k], update: async (k, v) => { state[k] = v; } } };
    const dir = path.join(__dirname, '.sandbox');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'extension-check-request.json');
    const put = (id) => fs.writeFileSync(file, JSON.stringify(ran({ id, cwd: path.resolve('/work/projA'), at: new Date().toISOString() })));
    const tick = () => new Promise(r => setTimeout(r, 20));
    put('r1');
    ext._check(context, file, true);
    await tick();
    check('a window just opened takes a recent queued run as seen, and neither asks nor reloads',
        calls.length === 0 && state['chatManagerReload.lastSeenId'] === 'r1');
    fs.writeFileSync(file, JSON.stringify({ id: 'n1', kind: 'new', title: 'T', cwd: path.resolve('/work/projA'), at: new Date().toISOString() }));
    ext._check(context, file, true);
    await tick();
    check('and the new chat a run started too - it lists it already',
        calls.length === 0 && state['chatManagerReload.lastSeenId'] === 'n1');
    put('r2');
    ext._check(context, file, false);
    await tick();
    check('one that was open reloads by itself', calls.join() === 'workbench.action.reloadWindow' && state['chatManagerReload.lastSeenId'] === 'r2');
    calls.length = 0;
    folders.push({ uri: { fsPath: path.resolve('/work/projB') } });
    put('r3');
    ext._check(context, file, false);
    await tick();
    folders.pop();
    check('a multi-root one asks instead', calls.join() === 'ask');

    // --- the commands each way runs -------------------------------------------
    // every wait to nothing; the ages a request may have stay what they are
    for (const k of ['openSettle', 'retry', 'tabSettle', 'tabRecount', 'startupOpen']) ext._timing[k] = 0;
    claudeHere = true;
    // the Claude extension as S29 saw it: primaryEditor.open reveals a panel
    // the chat has, or makes one, loaded from disk
    const tabs = [];
    const active = { tab: undefined };
    const group = { get tabs() { return tabs; }, get activeTab() { return active.tab; } };
    const titles = { [SID]: 'T' };
    let fail = {};
    let makeLater = 0;
    let revealMode = 'normal';
    const claudeTab = (sid, label) => ({ label, sid, input: new TabInputWebview('claudeVSCodePanel'), group });
    stub.window.tabGroups = {
        get all() { return [group]; }, get activeTabGroup() { return group; },
        close: async (t) => { calls.push('close:' + t.label); tabs.splice(tabs.indexOf(t), 1); if (active.tab === t) active.tab = tabs[0]; return true; }
    };
    const bars = [];
    stub.window.setStatusBarMessage = (m, ms) => { bars.push(m); return { dispose() { } }; };
    stub.commands.executeCommand = async (c, sid) => {
        calls.push(c);
        if (fail[c]) { fail[c]--; throw new Error('boom'); }
        if (c === 'claude-vscode.primaryEditor.open') {
            const have = tabs.find(t => t.sid === sid);
            if (revealMode === 'nothing') return;
            if (have) { active.tab = have; return; }
            const make = () => { const t = claudeTab(sid, titles[sid]); tabs.push(t); active.tab = t; };
            if (makeLater) setTimeout(make, makeLater); else make();
        }
    };
    let answer;
    const asked = [];
    stub.window.showInformationMessage = async (m, ...b) => { calls.push('ask'); asked.push(m); return b.includes(answer) ? answer : undefined; };
    stub.window.showWarningMessage = async (m, ...b) => { calls.push('warn'); asked.push(m); return undefined; };
    const reqT = { kind: 'ran', sessionId: SID, title: 'T' };
    const reset = () => { calls.length = 0; asked.length = 0; tabs.length = 0; active.tab = undefined; fail = {}; makeLater = 0; revealMode = 'normal'; };

    reset();
    await ext._showWebviews(reqT);
    check('Reload Webviews: the chat where you read it, then the redraw - nothing else',
        calls.join() === 'claude-vscode.editor.open,workbench.action.webview.reloadWebviewAction', calls.join());
    reset();
    fail['claude-vscode.editor.open'] = 2;
    await ext._showWebviews(reqT);
    check('the chat not opened after two tries: the redraw still runs, and says where to find it',
        calls.join() === 'claude-vscode.editor.open,claude-vscode.editor.open,workbench.action.webview.reloadWebviewAction,ask' &&
        asked[0] === 'Refreshed. Pick "T" from the chat history to see it.', calls.join());
    reset();
    fail['workbench.action.webview.reloadWebviewAction'] = 1;
    await ext._showWebviews(reqT);
    check('Reload Webviews failing: a tab instead', calls.join() === 'claude-vscode.editor.open,workbench.action.webview.reloadWebviewAction,claude-vscode.primaryEditor.open', calls.join());

    reset();
    const r1 = await ext._showTab(reqT);
    check('a tab: none open - one open, loaded from disk, nothing closed', r1 === 'new' && calls.join() === 'claude-vscode.primaryEditor.open', calls.join());
    reset();
    const other = { label: 'notes.md', input: new TabInputText('x'), group };
    tabs.push(claudeTab(SID, 'T'), other);
    active.tab = other;
    const r2 = await ext._showTab(reqT);
    check('a stale tab brought forward, with the chat\'s title - closed and opened again',
        r2 === 'reopened' && calls.join() === 'claude-vscode.primaryEditor.open,close:T,claude-vscode.primaryEditor.open' && tabs.length === 2, calls.join());
    reset();
    tabs.push(claudeTab(SID, 'Some other title'), other);
    active.tab = other;
    const r3 = await ext._showTab(reqT);
    check('a title that does not match: nothing closed, and says so', r3 === 'stale' && !calls.some(c => c.startsWith('close:')) &&
        asked[0] === '"T" is already open in a tab that could not be refreshed. Close that tab and open the chat again.', calls.join());
    reset();
    const textT = { label: 'T', input: new TabInputText('x'), group };
    tabs.push(textT);
    active.tab = textT;
    revealMode = 'nothing';
    const r4 = await ext._showTab(reqT);
    check('an editor that is no Claude tab is never closed, whatever its title', r4 === 'stale' && !calls.some(c => c.startsWith('close:')), calls.join());
    reset();
    ext._timing.tabRecount = 40;
    makeLater = 10;
    const r5 = await ext._showTab(reqT);
    ext._timing.tabRecount = 0;
    check('a slow new tab, caught by the second look: nothing closed', r5 === 'new' && !calls.some(c => c.startsWith('close:')) && tabs.length === 1, calls.join());

    reset();
    const order = [];
    const slow = (n) => async () => { order.push(n + '1'); await new Promise(r => setTimeout(r, 15)); order.push(n + '2'); };
    const q1 = ext._enqueue(slow('a'));
    const q2 = ext._enqueue(slow('b'));
    await Promise.all([q1, q2]);
    check('two shows queued together never interleave', order.join() === 'a1,a2,b1,b2', order.join());

    // end to end, the run's request, fresh
    const fresh = (id, x) => fs.writeFileSync(file, JSON.stringify(Object.assign({ id, kind: 'ran', title: 'T', sessionId: SID, cwd: path.resolve('/work/projA'),
        away: true, busy: false, oldProcess: 'ended', hostPids: [], at: new Date().toISOString() }, x)));
    const settle = async () => { await tick(); await tick(); };
    reset();
    fresh('f1');
    ext._check(context, file, false);
    await settle();
    check('a run into a quiet exact window: the chat where you read it, and Reload Webviews, by itself',
        calls.join() === 'claude-vscode.editor.open,workbench.action.webview.reloadWebviewAction', calls.join());
    reset();
    folders.push({ uri: { fsPath: path.resolve('/work/projB') } });
    answer = 'Show it';
    ext._getVerdict = async () => ({ busy: false, oldProcess: 'ended', outcome: 'ok', hostPids: [] });
    fresh('f2');
    ext._check(context, file, false);
    await settle();
    folders.pop();
    answer = undefined;
    check('a multi-root window asks Show it, checks again, and shows it in a tab of its own',
        calls.join() === 'ask,claude-vscode.primaryEditor.open' && asked[0].endsWith('Show it?') && bars[0] === ext._texts.checking, calls.join());
    reset();
    fresh('f3', { at: new Date(Date.now() - 60000).toISOString() });
    ext._check(context, file, false);
    await settle();
    check('a verdict a minute old: it asks, it does not act', calls.join() === 'ask', calls.join());
    reset();
    answer = 'Show it';
    ext._getVerdict = async () => null;
    fresh('f4', { away: false, oldProcess: 'live' });
    ext._check(context, file, false);
    await settle();
    answer = undefined;
    check('Show it with the check failing on a process left running: the reload offer', calls.join() === 'ask,warn' &&
        asked[1] === 'chatq could not end the old process of "T", so only a reload shows the run.', calls.join());
    for (const outcome of ['missing', 'bad']) {
        reset();
        answer = 'Show it';
        // what an early return prints - before 0.6.0's fix it said none, and a tab opened beside the live process
        ext._getVerdict = async () => ({ busy: null, oldProcess: 'none', outcome, hostPids: [] });
        fresh('f5' + outcome, { away: false, oldProcess: 'live' });
        ext._check(context, file, false);
        await settle();
        answer = undefined;
        check('Show it on a check that judged nothing (' + outcome + '), a process left running: the reload offer, never a tab beside it',
            calls.join() === 'ask,warn' && !calls.includes('claude-vscode.primaryEditor.open'), calls.join());
    }
    reset();
    answer = 'Show it';
    ext._getVerdict = async () => ({ busy: true, oldProcess: 'held', outcome: 'running', hostPids: [] });
    fresh('f6', { away: false, oldProcess: 'live' });
    ext._check(context, file, false);
    await settle();
    answer = undefined;
    check('Show it while a queued prompt goes into the chat: nothing shown, nothing reloaded, and says why',
        calls.join() === 'ask,ask' && asked[1] === ext._texts.running(reqT), calls.join());

    // end to end, the overlay's open request
    const ofile = path.join(dir, 'extension-check-open.json');
    const open = (id, x) => fs.writeFileSync(ofile, JSON.stringify(Object.assign({ id, kind: 'open', title: 'T', sessionId: SID, cwd: path.resolve('/work/projA'),
        home: null, busy: false, oldProcess: 'ended', hostPids: [], at: new Date().toISOString() }, x)));
    reset();
    open('o1');
    await ext._checkOpen(context, ofile, false);
    await settle();
    check('an open in a quiet exact window: the chat, and Reload Webviews', calls.join() === 'claude-vscode.editor.open,workbench.action.webview.reloadWebviewAction', calls.join());
    reset();
    open('o2', { oldProcess: 'none' });
    await ext._checkOpen(context, ofile, false);
    await settle();
    check('an open no process held: the chat, nothing redrawn', calls.join() === 'claude-vscode.editor.open', calls.join());
    reset();
    folders.push({ uri: { fsPath: path.resolve('/work/projB') } });
    open('o3');
    await ext._checkOpen(context, ofile, false);
    await settle();
    folders.pop();
    check('an open is not for a window that is not exactly its folder', calls.length === 0 && state['chatManagerReload.lastOpenId'] !== 'o3', calls.join());
    reset();
    open('o4', { at: new Date(Date.now() - 30000).toISOString() });
    await ext._checkOpen(context, ofile, true);
    await settle();
    check('a window just opened for it shows the chat, and redraws nothing', calls.join() === 'claude-vscode.editor.open', calls.join());
    reset();
    open('o5', { at: new Date(Date.now() - 300000).toISOString() });
    await ext._checkOpen(context, ofile, true);
    await settle();
    check('one five minutes old is left, and taken as seen', calls.length === 0 && state['chatManagerReload.lastOpenId'] === 'o5', calls.join());
    reset();
    open('o6', { oldProcess: 'none' });
    await ext._checkOpen(context, ofile, false);
    await ext._checkOpen(context, ofile, false);
    await settle();
    check('the same open twice acts once', calls.join() === 'claude-vscode.editor.open', calls.join());

    try { fs.unlinkSync(file); } catch (e) { }
    try { fs.unlinkSync(ofile); } catch (e) { }
    console.log('');
    console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
    process.exit(failed);
})();
