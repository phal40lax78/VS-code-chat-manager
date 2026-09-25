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
// the settings, by 'section.key': '' for anything unset, as VS Code's get
// hands back a default, and inspect saying where a value was set
const cfgVals = {};
let claudeHere = false;
let oldHere = false;
class TabInputWebview { constructor(viewType) { this.viewType = viewType; } }
class TabInputText { constructor(uri) { this.uri = uri; } }
const stub = {
    workspace: {
        getConfiguration: (sec) => ({
            get: (k) => (sec + '.' + k in cfgVals ? cfgVals[sec + '.' + k] : ''),
            inspect: (k) => (sec + '.' + k in cfgVals ? { key: k, globalValue: cfgVals[sec + '.' + k] } : { key: k })
        }),
        workspaceFolders: folders
    },
    window: {}, commands: {},
    extensions: {
        getExtension: (id) => ((claudeHere && id === 'anthropic.claude-code') || (oldHere && id === 'phal40lax78.chat-manager-reload') ? { id } : undefined)
    },
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
cfgVals['chatManager.folder'] = path.resolve('/t/tool');
check('both follow chatManager.folder', ext._signalFiles()[0] === path.resolve('/t/tool/data/reload-request') &&
    ext._openFiles()[0] === path.resolve('/t/tool/data/open-request'));
cfgVals['chatManager.folder'] = '~/elsewhere';
check('and a folder under ~ is under the home folder', ext._toolFolder() === path.join(require('os').homedir(), 'elsewhere'), ext._toolFolder());
delete cfgVals['chatManager.folder'];
cfgVals['chatManagerReload.signalFile'] = path.resolve('/x/data/reload-request');
check('unset, the old extension\'s signalFile still places them', ext._openFiles()[0] === path.resolve('/x/data/open-request'));
cfgVals['chatManager.folder'] = path.resolve('/t/tool');
check('but chatManager.folder wins over it', ext._toolFolder() === path.resolve('/t/tool'));
delete cfgVals['chatManager.folder'];
delete cfgVals['chatManagerReload.signalFile'];
cfgVals['chatManagerReload.showFresh'] = false;
const oldOff = ext._showFresh();
cfgVals['chatManager.showFresh'] = true;
const newOn = ext._showFresh();
delete cfgVals['chatManagerReload.showFresh'];
delete cfgVals['chatManager.showFresh'];
check('an old chatManagerReload setting is read where the new one is unset, and the new one wins', oldOff === false && newOn === true && ext._showFresh() === true);

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

    // --- the terminal half: setup.js and build.js -----------------------------
    const su = require(path.join(__dirname, '..', 'extension', 'setup.js'));
    const bj = require(path.join(__dirname, '..', 'extension', 'build.js'));
    check('setup: the loader\'s version read from its text', su._readVersion("# x\r\n$script:ChatVersion = '0.7.0'\r\n") === '0.7.0' &&
        su._readVersion('none') === null && su._readVersion("$script:ChatVersion = '0.8.0-rc1'") === null);
    check('setup: versions compare by number, 0.10.0 after 0.9.1', su._compareVersions('0.10.0', '0.9.1') === 1 &&
        su._compareVersions('0.7.0', '0.7.0') === 0 && su._compareVersions('0.6.9', '0.7.0') === -1);
    const dcd = (bundled, disk, git, extra) => su._decide(Object.assign({ bundled, loader: disk !== null, onDisk: disk, git, foreign: false }, extra));
    check('setup: nothing there - install; older - update; the same - nothing; newer - left alone',
        dcd('0.7.0', null, false) === 'install' && dcd('0.7.0', '0.6.0', false) === 'update' && dcd('0.7.0', '0.7.0', false) === 'none' && dcd('0.7.0', '0.8.0', false) === 'newer');
    check('setup: a git checkout is never written - another version there is only said',
        dcd('0.7.0', '0.6.0', true) === 'skew' && dcd('0.7.0', '0.7.0', true) === 'none' && dcd('0.7.0', null, true) === 'none');
    check('setup: a loader whose version cannot be read is left, never taken for no loader',
        dcd('0.7.0', null, false, { loader: true }) === 'unknown' && dcd('0.7.0', null, true, { loader: true }) === 'unknown');
    check('setup: a folder holding other things is not installed into', dcd('0.7.0', null, false, { foreign: true }) === 'foreign');
    check('setup: a build carrying no scripts does nothing', dcd(null, '0.6.0', false) === 'none' && dcd(null, null, false) === 'none');
    check('setup: the profile looked at when files changed, or when not settled for this version',
        su._needsProbe('update', { profile: 'yes' }, '0.7.0') && su._needsProbe('none', {}, '0.7.0') && !su._needsProbe('none', { profile: 'yes' }, '0.7.0') &&
        !su._needsProbe('none', { profile: 'never' }, '0.7.0') && !su._needsProbe('none', { notNowFor: '0.7.0' }, '0.7.0') && su._needsProbe('none', { notNowFor: '0.6.0' }, '0.7.0'));
    check('setup: asked only where a PowerShell lacks the line; never after Never; after Not now, at the next version; always from the palette',
        !su._shouldAsk({}, [], '0.7.0', true) && su._shouldAsk({}, ['p'], '0.7.0', false) && !su._shouldAsk({ profile: 'never' }, ['p'], '0.7.0', false) &&
        su._shouldAsk({ profile: 'never' }, ['p'], '0.7.0', true) && !su._shouldAsk({ notNowFor: '0.7.0' }, ['p'], '0.7.0', false) && su._shouldAsk({ notNowFor: '0.6.0' }, ['p'], '0.7.0', false));
    check('setup: the policies a profile line cannot run under', su._blocksProfile('Restricted') && su._blocksProfile('AllSigned') &&
        !su._blocksProfile('RemoteSigned') && !su._blocksProfile('Bypass') && !su._blocksProfile(null));
    check('setup: the last True or False a PowerShell printed, and none is no answer', su._lastBool('WARNING: x\r\nFalse\r\nTrue\r\n') === true && su._lastBool('noise') === null);
    const pa = su._psArgs("C:\\it's\\VS-code-chat-manager.ps1", 'Test-ChatProfileLine');
    const pt = Buffer.from(pa[pa.length - 1], 'base64').toString('utf16le');
    check('setup: its PowerShell loads no profile, is marked as no interactive shell, and quotes the path',
        pa.includes('-NoProfile') && pa.includes('Bypass') && pt === "$env:CHATQ_OVERLAY='1'; . 'C:\\it''s\\VS-code-chat-manager.ps1'; Test-ChatProfileLine", pt);

    // locks, folders and copies, in the sandbox
    const sbx = path.join(dir, 'ext-setup');
    fs.rmSync(sbx, { recursive: true, force: true });
    fs.mkdirSync(sbx, { recursive: true });
    const lk = path.join(sbx, 'x.lock');
    const t0 = Date.now();
    check('lock: the first window takes it, a second does not', su._takeLock(lk, t0, 60000) && !su._takeLock(lk, t0, 60000));
    check('lock: one older than its limit is taken over', su._takeLock(lk, t0 + 120000, 60000));
    su._releaseLock(lk);
    check('lock: released, it is free again', su._takeLock(lk, t0, 60000));
    su._releaseLock(lk);
    let lockThrew = false;
    try { su._takeLock(path.join(sbx, 'no-such-dir', 'x.lock'), t0, 60000); } catch (e) { lockThrew = true; }
    check('lock: a place that cannot be written throws, never reads as another window', lockThrew);
    fs.mkdirSync(path.join(sbx, 'repo', '.git'), { recursive: true });
    fs.mkdirSync(path.join(sbx, 'repo', 'Tools', 'tool'), { recursive: true });
    // the sandbox is inside this repo, so every look stops at it
    const realGit = su._inGitCheckout;
    check('setup: a folder inside a git work tree counts as one, however deep', realGit(path.join(sbx, 'repo', 'Tools', 'tool'), sbx) &&
        !realGit(path.join(sbx, 'x'), sbx));
    su._inGitCheckout = (f) => realGit(f, sbx);
    fs.mkdirSync(path.join(sbx, 'docs'), { recursive: true });
    fs.writeFileSync(path.join(sbx, 'docs', 'letter.txt'), 'x');
    fs.mkdirSync(path.join(sbx, 'empty'), { recursive: true });
    fs.mkdirSync(path.join(sbx, 'withdata', 'data'), { recursive: true });
    check('setup: someone else\'s folder is foreign; an empty or missing one, or one with data/, is not',
        su._isForeign(path.join(sbx, 'docs')) && !su._isForeign(path.join(sbx, 'empty')) && !su._isForeign(path.join(sbx, 'missing')) &&
        !su._isForeign(path.join(sbx, 'withdata')));

    // packages carrying 0.7.0 and 0.7.1, and a tool folder to put them in
    const mkPayload = (at, v) => {
        const p = path.join(at, 'payload');
        fs.mkdirSync(path.join(p, 'src'), { recursive: true });
        fs.writeFileSync(path.join(p, su.LOADER), "$script:ChatVersion = '" + v + "'\r\n");
        fs.writeFileSync(path.join(p, 'src', 'core.ps1'), '# core ' + v + '\r\n');
        return at;
    };
    const ext70 = mkPayload(path.join(sbx, 'ext70'), '0.7.0');
    const ext71 = mkPayload(path.join(sbx, 'ext71'), '0.7.1');
    const tool = path.join(sbx, 'tool');
    const steps = [];
    const realStep = su._profileStep;
    su._profileStep = async (o) => { steps.push(o.action); };
    const said = [];
    const warned = [];
    stub.window.showInformationMessage = async (m) => { said.push(m); };
    stub.window.showWarningMessage = async (m) => { warned.push(m); };
    const up = (at, force, where) => su.setUp({ extensionPath: at, folder: where || tool, log: () => { }, force });
    const diskText = () => { try { return fs.readFileSync(path.join(tool, su.LOADER), 'latin1'); } catch (e) { return ''; } };
    const coreText = () => { try { return fs.readFileSync(path.join(tool, 'src', 'core.ps1'), 'latin1'); } catch (e) { return ''; } };
    const r1s = await up(ext70);
    check('setUp: an empty folder gets the scripts, then the profile step, and says where',
        r1s === 'install' && diskText().includes("'0.7.0'") && coreText().includes('0.7.0') && steps.join() === 'install' &&
        !fs.existsSync(path.join(tool, su.LOADER + '.new')) && said.length === 1 && said[0].includes(tool), r1s + ' ' + steps.join() + ' ' + said.join('|'));
    steps.length = 0; said.length = 0;
    const r2s = await up(ext70);
    check('setUp: the same package again copies nothing; the profile question is still open', r2s === 'none' && steps.join() === 'none', r2s + ' ' + steps.join());
    steps.length = 0;
    su._writeState(tool, { profile: 'yes' });
    const r3s = await up(ext70);
    check('setUp: settled, a start runs no PowerShell at all', r3s === 'none' && steps.length === 0, r3s + ' ' + steps.join());
    const r4s = await up(ext71);
    check('setUp: a newer package updates the copy, and says so', r4s === 'update' && diskText().includes("'0.7.1'") && coreText().includes('0.7.1') &&
        steps.join() === 'update' && said.some(m => m.includes('0.7.1')), r4s + ' ' + steps.join());
    steps.length = 0;
    const r5s = await up(ext70);
    check('setUp: an older package leaves a newer copy alone', r5s === 'newer' && diskText().includes("'0.7.1'") && steps.length === 0, r5s);
    fs.writeFileSync(path.join(tool, su.LOADER), "$script:ChatVersion = '0.9.0-dev'\r\n");
    warned.length = 0;
    const u1 = await up(ext70);
    const u2 = await up(ext70);
    check('setUp: a loader of no readable version is left as it is, and said once', u1 === 'unknown' && u2 === 'unknown' &&
        diskText().includes('0.9.0-dev') && warned.length === 1 && steps.length === 0, u1 + ' ' + warned.join('|'));
    fs.writeFileSync(path.join(tool, su.LOADER), "$script:ChatVersion = '0.6.0'\r\n");
    fs.writeFileSync(path.join(tool, 'data', 'install.lock'), '1');
    const r6s = await up(ext70);
    check('setUp: while another window holds the lock, nothing is copied', r6s === 'elsewhere' && diskText().includes("'0.6.0'"), r6s);
    fs.unlinkSync(path.join(tool, 'data', 'install.lock'));
    // a copy that fails: src is a file where the folder goes
    const bad = path.join(sbx, 'bad');
    fs.mkdirSync(path.join(bad, 'data'), { recursive: true });
    fs.writeFileSync(path.join(bad, 'src'), 'not a folder');
    warned.length = 0;
    const b1 = await up(ext70, false, bad);
    const b2 = await up(ext70, false, bad);
    check('setUp: a copy that fails says so once a version, leaves no .new, and keeps no half install',
        b1 === 'failed' && b2 === 'failed' && warned.length === 1 && /could not put/.test(warned[0]) && !fs.existsSync(path.join(bad, su.LOADER)) &&
        !fs.readdirSync(bad).some(n => n.endsWith('.new')), b1 + ' ' + warned.join('|'));
    warned.length = 0;
    const f1 = await up(ext70, false, path.join(sbx, 'docs'));
    check('setUp: someone else\'s folder gets nothing, not even a data/, and is said', f1 === 'foreign' &&
        !fs.existsSync(path.join(sbx, 'docs', 'data')) && !fs.existsSync(path.join(sbx, 'docs', su.LOADER)) && warned.length === 1, f1);
    fs.mkdirSync(path.join(tool, '.git'));
    said.length = 0;
    const g1 = await up(ext70);
    const g2 = await up(ext70);
    check('setUp: a git checkout is never written, and the difference is said once',
        g1 === 'skew' && g2 === 'skew' && diskText().includes("'0.6.0'") && said.length === 1 && /pull to match/.test(said[0]), g1 + ' ' + said.join('|'));
    su._profileStep = realStep;
    su._inGitCheckout = realGit;

    // the profile step itself, with PowerShell stood in for: hosts A and B,
    // what each answers, and every command recorded
    const ps = { A: { line: true, policy: 'RemoteSigned' }, B: { line: false, policy: 'RemoteSigned' } };
    const psRan = [];
    let installWorks = true;
    const real = { hosts: su._hosts, runPs: su._runPs, policyOf: su._policyOf, allowScripts: su._allowScripts };
    su._hosts = () => Object.keys(ps);
    su._runPs = async (exe, loader, cmd) => {
        psRan.push(exe + ':' + cmd.split(' ')[0]);
        if (/Test-ChatProfileLine/.test(cmd)) return { ok: true, stdout: ps[exe].line === null ? 'garbage' : String(ps[exe].line ? 'True' : 'False') };
        if (/^chatinstall/.test(cmd) && installWorks) ps[exe].line = true;
        return { ok: true, stdout: '' };
    };
    su._policyOf = async (exe) => ps[exe].policy;
    // locked: a group policy decides it, and nothing here changes it
    su._allowScripts = async (exe) => { psRan.push(exe + ':allow'); if (!ps[exe].locked) ps[exe].policy = 'RemoteSigned'; return ps[exe].policy === 'RemoteSigned'; };
    let answer2 = 'Add';
    const asked2 = [];
    stub.window.showInformationMessage = async (m, ...b) => { asked2.push(m); return b.length ? answer2 : undefined; };
    stub.window.showWarningMessage = async (m, ...b) => { asked2.push('warn:' + m); return b.length ? 'Allow' : undefined; };
    const pf = path.join(sbx, 'pf');
    fs.mkdirSync(pf, { recursive: true });
    const step = (action, force) => su._profileStep({ folder: pf, loader: 'L', version: '0.7.0', action, force, log: () => { } });
    const reset2 = () => { psRan.length = 0; asked2.length = 0; su._writeState(pf, {}); };
    reset2();
    await step('update');
    check('profile: Add - chatinstall where the line was missing, checked again; after an update also where it was; one restart',
        psRan.filter(x => /chatinstall/.test(x)).sort().join() === 'A:chatinstall,B:chatinstall' && psRan.filter(x => /Restart-ChatBackground/.test(x)).length === 1 &&
        su._readState(pf).profile === 'yes' && asked2.includes(su.texts.added), psRan.join() + ' | ' + asked2.join(' | '));
    reset2();
    ps.B.line = false;
    installWorks = false;
    await step('none');
    installWorks = true;
    check('profile: Add, and the line still not there after - no "Added", the answer not kept as yes, and said',
        su._readState(pf).profile !== 'yes' && su._readState(pf).notNowFor === '0.7.0' && !asked2.includes(su.texts.added) &&
        asked2.includes('warn:' + su.texts.addFailed), JSON.stringify(su._readState(pf)) + ' | ' + asked2.join(' | '));
    reset2();
    ps.B = { line: false, policy: 'Restricted' };
    await step('none');
    check('profile: the policy would stop the line - the question says so, and Add allows scripts before the line is written',
        asked2[0] === su.texts.askPolicy('Restricted') && psRan.indexOf('B:allow') >= 0 && psRan.indexOf('B:allow') < psRan.indexOf('B:chatinstall') &&
        su._readState(pf).profile === 'yes', psRan.join() + ' | ' + asked2.join(' | '));
    reset2();
    ps.B = { line: false, policy: 'Restricted', locked: true };
    await step('none');
    check('profile: a policy that will not change - the line is not written, and said',
        !psRan.includes('B:chatinstall') && asked2.includes('warn:' + su.texts.policyStuck) && su._readState(pf).profile !== 'yes', psRan.join() + ' | ' + asked2.join(' | '));
    reset2();
    ps.B = { line: null, policy: 'RemoteSigned' };
    await step('none');
    check('profile: a PowerShell that gives no answer is neither asked about nor installed into', asked2.length === 0 &&
        !psRan.some(x => /chatinstall/.test(x)), psRan.join() + ' | ' + asked2.join(' | '));
    reset2();
    ps.A = { line: true, policy: 'Restricted', locked: true };
    ps.B = { line: true, policy: 'RemoteSigned' };
    await step('none');
    const firstAsk = asked2.slice();
    asked2.length = 0;
    await step('none');
    check('profile: a line already there that the policy never runs - offered once a version, tried on the click, and a refusal said',
        firstAsk[0] === 'warn:' + su.texts.policyHave('Restricted') && firstAsk.includes('warn:' + su.texts.policyStuck) &&
        psRan.includes('A:allow') && asked2.length === 0, firstAsk.join(' | ') + ' / ' + asked2.join(' | '));
    reset2();
    ps.A = { line: false, policy: 'RemoteSigned' };
    ps.B = { line: false, policy: 'RemoteSigned' };
    answer2 = 'Never';
    await step('none');
    const afterNever = su._readState(pf).profile;
    asked2.length = 0;
    await step('none');
    const askedAgain = asked2.length;
    await step('none', true);
    answer2 = 'Add';
    check('profile: Never is kept and never asked again - until the palette asks', afterNever === 'never' && askedAgain === 0 && asked2.length >= 1,
        afterNever + ' ' + askedAgain + ' ' + asked2.length);
    Object.assign(su, { _hosts: real.hosts, _runPs: real.runPs, _policyOf: real.policyOf, _allowScripts: real.allowScripts });

    check('build: the part names in the loader\'s own list, in its order', bj._partsOf("x\r\n$chatParts = 'core', 'providers', 'overlay'\r\n").join() === 'core,providers,overlay');
    check('build: an SVG image is caught; a PNG, and a plain link to an SVG, are not',
        bj._svgImages('![a](x/demo.svg) ![b](y.png) [c](z.svg) <img alt="w" src="w.SVG">').join() === 'x/demo.svg,w.SVG');
    const realLoader = fs.readFileSync(path.join(__dirname, '..', su.LOADER), 'latin1');
    const realParts = bj._partsOf(realLoader);
    check('build: the real loader lists 14 parts, each one in src/', realParts.length === 14 &&
        realParts.every(p => fs.existsSync(path.join(__dirname, '..', 'src', p + '.ps1'))), realParts.join());
    const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'extension', 'package.json'), 'utf8'));
    check('build: the extension\'s version is the script\'s', pkg.version === su._readVersion(realLoader), pkg.version + ' / ' + su._readVersion(realLoader));
    check('build: the listing README shows no SVG', bj._svgImages(fs.readFileSync(path.join(__dirname, '..', 'extension', 'README.md'), 'utf8')).length === 0);

    // the tool folder, as set
    cfgVals['chatManager.folder'] = 'Tools/relative';
    const relTo = ext._toolFolder();
    delete cfgVals['chatManager.folder'];
    cfgVals['chatManagerReload.signalFile'] = path.resolve('/c/Users/me/reload-request');
    const oddTo = ext._toolFolder();
    delete cfgVals['chatManagerReload.signalFile'];
    const dflt = path.join(require('os').homedir(), 'Tools', 'VS-code-chat-manager');
    check('the tool folder: a relative one, or a signalFile not in a data/ folder, falls back to the default - never C:\\ or C:\\Users',
        relTo === dflt && oddTo === dflt, relTo + ' | ' + oddTo);

    // runs of the setup, one at a time per window, a palette one after a
    // start's rather than dropped
    const realSetUp = su.setUp;
    const runs = [];
    su.setUp = async (o) => { runs.push(o.force ? 'force' : 'start'); await new Promise(r => setTimeout(r, 15)); return 'none'; };
    const ctxR = { extensionPath: sbx };
    const pr1 = ext._runSetup(ctxR, false);
    const pr2 = ext._runSetup(ctxR, false);
    const pr3 = ext._runSetup(ctxR, true);
    await Promise.all([pr1, pr2, pr3]);
    su.setUp = realSetUp;
    check('setup runs one at a time; a second start joins the first, the palette\'s runs after it', runs.join() === 'start,force', runs.join());

    // activation: the old extension left to handle requests where it watches
    // the same file, and one window offering it away
    const watched = [];
    const realWatch = fs.watchFile;
    fs.watchFile = (f) => { watched.push(f); };
    stub.commands.registerCommand = () => ({ dispose() { } });
    const acts = [];
    stub.commands.executeCommand = async (c, a) => { acts.push(c + (a ? ':' + a : '')); };
    const asks = [];
    stub.window.showWarningMessage = async (m, ...b) => { asks.push(m); return b[0]; };
    stub.window.showInformationMessage = async (m, ...b) => { asks.push(m); return undefined; };
    cfgVals['chatManagerReload.signalFile'] = path.join(tool, 'data', 'reload-request');
    oldHere = true;
    const ctxA = { subscriptions: [], extensionPath: path.join(sbx, 'no-payload'), globalState: context.globalState };
    ext.activate(ctxA);
    await settle();
    check('the old extension installed on the same file: none of it watched here, and the old one offered away',
        watched.length === 0 && asks[0] === ext._texts.oldThere && acts.includes('workbench.extensions.uninstallExtension:phal40lax78.chat-manager-reload') &&
        asks[1] === ext._texts.oldGone, acts.join() + ' | ' + asks.join(' | '));
    asks.length = 0;
    check('another window within 10 minutes does not ask again', (await ext._askToRemoveOld()) === 'elsewhere' && asks.length === 0);
    cfgVals['chatManager.folder'] = path.join(sbx, 'tool2');
    ext.activate(ctxA);
    await settle();
    check('the old one on another file than chatManager.folder\'s: this one handles its own', !ext._oldWatchesMine() && watched.length === 2 &&
        watched[0] === path.join(sbx, 'tool2', 'data', 'reload-request'), watched.join());
    watched.length = 0;
    delete cfgVals['chatManager.folder'];
    oldHere = false;
    ext.activate(ctxA);
    await settle();
    check('without it, both request files are watched, in the tool folder', watched.length === 2 &&
        watched[0] === path.join(tool, 'data', 'reload-request') && watched[1] === path.join(tool, 'data', 'open-request'), watched.join());
    check('and the palette has both commands', ctxA.subscriptions.length >= 4);
    fs.watchFile = realWatch;
    delete cfgVals['chatManagerReload.signalFile'];
    fs.rmSync(sbx, { recursive: true, force: true });

    try { fs.unlinkSync(file); } catch (e) { }
    try { fs.unlinkSync(ofile); } catch (e) { }
    console.log('');
    console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
    process.exit(failed);
})();
