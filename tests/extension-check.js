// Checks extension/extension.js's parts with the vscode module stubbed out:
// which window a request is for, what it says, when it acts without asking,
// how it shows a chat fresh - the plan, and the commands each way runs - how
// the overlay's open chip opens one, which files it watches, and when it
// starts the overlay. Each decides whether - or how - a chat is shown, and
// each fails silently when wrong.
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
// what the extension writes to its output channel, without the time
const logged = [];
const stub = {
    workspace: {
        getConfiguration: (sec) => ({
            get: (k) => (sec + '.' + k in cfgVals ? cfgVals[sec + '.' + k] : ''),
            inspect: (k) => (sec + '.' + k in cfgVals ? { key: k, globalValue: cfgVals[sec + '.' + k] } : { key: k })
        }),
        workspaceFolders: folders
    },
    window: { createOutputChannel: () => ({ appendLine: (l) => logged.push(l.replace(/^\S+\s+/, '')), show() { } }) },
    commands: {},
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
    Object.assign({ fresh: true, claude: true }, c));
check('plan: a terminal holds it - nothing', plan({}, { oldProcess: 'other', busy: false }) === 'none');
check('plan: held working - reload later', plan({}, { oldProcess: 'held', busy: true }) === 'reload');
check('plan: a process left running or not checked - reload', plan({}, { oldProcess: 'live', busy: false }) === 'reload' &&
    plan({}, { oldProcess: 'kept', busy: false }) === 'reload');
check('plan: the old process ended, or none - a tab of its own, whatever else works, never Reload Webviews',
    ['ended', 'none'].every(o => [false, true, null].every(b => plan({}, { oldProcess: o, busy: b }) === 'tab')) &&
    plan({}, null) === 'tab');
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
check('says: after Show it, what went wrong',
    ext._texts.couldNotEnd({ title: 'T' }) === 'chatq could not end the old process of "T", so only a reload shows the run.');
check('says: for an open, no Claude extension, not opened, or open in two places',
    ext._texts.noClaude({ title: 'T' }) === 'The Claude Code extension is not in this window, so "T" cannot be opened here.' &&
    ext._texts.notOpened({ title: 'T' }) === '"T" could not be opened. Chat Manager: Show log has the details.' &&
    /^"T" was also open in this window outside its tabs .* now runs in two places\. Type in the tab, and close the other\.$/.test(ext._texts.twoPlaces({ title: 'T' })));
check('says: open in two places, the other copy idle - close the side bar\'s',
    /^"T" was also open in this window outside its tabs .* now runs in two places\. Type in the tab, and close the side bar's copy, which is idle\.$/.test(ext._texts.twoPlaces({ title: 'T', oldProcess: 'live' })),
    ext._texts.twoPlaces({ title: 'T', oldProcess: 'live' }));
check('says: working outside the tabs - not opened, and to click open again once it finishes, since nothing opens it then by itself; after a run, the side bar\'s copy stale',
    /^"T" is working outside the tabs here .* so it was not opened as a tab.* Click open again once it finishes\.$/.test(ext._texts.working({ title: 'T' })) &&
    !/opens as a tab once/.test(ext._texts.working({ title: 'T' })) &&
    /^"T" was also open in this window outside its tabs .* That copy is stale now and can be closed/.test(ext._texts.sideBarStale({ title: 'T' })));
claudeHere = false;
const ELL = '\u2026';
check('tab label: no title is "Claude Code"', ext._claudeTabLabel('') === 'Claude Code' && ext._claudeTabLabel(undefined) === 'Claude Code');
check('tab label: 25 characters stay whole, 26 are cut to 24 and an ellipsis',
    ext._claudeTabLabel('a'.repeat(25)) === 'a'.repeat(25) && ext._claudeTabLabel('a'.repeat(26)) === 'a'.repeat(24) + ELL);
check('tab label: as the Claude extension showed a real one', ext._claudeTabLabel('Extension icon IMG_8588.jpg') === 'Extension icon IMG_8588.' + ELL,
    ext._claudeTabLabel('Extension icon IMG_8588.jpg'));
check('tab label: the chat\'s, whole or shortened; an untitled chat is no tab\'s',
    ext._labelIsChat('T', 'T') && ext._labelIsChat('Extension icon IMG_8588.jpg', 'Extension icon IMG_8588.' + ELL) &&
    !ext._labelIsChat('T', 'U') && !ext._labelIsChat('', 'Claude Code') && !ext._labelIsChat(undefined, 'Claude Code'));
const cTab = { label: 'c', input: new TabInputWebview('claudeVSCodePanel') };
const fTab = { label: 'f', input: new TabInputText('x') };
check('group: unlocked only when it holds Claude tabs alone - never a mixed one, nor an empty one',
    ext._claudeOnly([cTab]) && ext._claudeOnly([cTab, cTab]) && !ext._claudeOnly([cTab, fTab]) && !ext._claudeOnly([fTab]) &&
    !ext._claudeOnly([]) && !ext._claudeOnly(undefined));
check('a Claude tab: the Claude extension\'s panel only - never Cline\'s, whose name holds "claude" too, nor a markdown preview',
    ext._isClaudeTab({ label: 'T', input: new TabInputWebview('mainThreadWebview-claudeVSCodePanel') }) &&
    !ext._isClaudeTab({ label: 'T', input: new TabInputWebview('mainThreadWebview-claude-dev.TabPanelProvider') }) &&
    !ext._isClaudeTab({ label: 'T', input: new TabInputWebview('claude-dev.TabPanelProvider') }) &&
    !ext._isClaudeTab({ label: 'Preview claude.md', input: new TabInputWebview('mainThreadWebview-markdown.preview') }) &&
    !ext._isClaudeTab({ label: 'T', input: new TabInputText('claudeVSCodePanel') }));
check('one tab of the chat: exactly one reading as it - twins, or a chat of no title, are none',
    ext._oneTabOf('T', [cTab, { label: 'T' }]).label === 'T' && ext._oneTabOf('T', [{ label: 'T' }, { label: 'T' }]) === undefined &&
    ext._oneTabOf('', [{ label: 'Claude Code' }]) === undefined && ext._oneTabOf('T', []) === undefined);
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
    // a Claude home holding no chats: a label is looked up in the folder's
    // chats, and a test never reads the real ~/.claude
    const noHome = path.join(dir, 'ext-nohome');
    process.env.CLAUDE_CONFIG_DIR = noHome;
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
    // every wait to nothing; the ages a request may have stay what they are.
    // labelBudget 0 is no limit: a slow machine never answers shared for it
    for (const k of ['retry', 'tabSettle', 'tabRecount', 'startupOpen', 'commandTimeout', 'labelBudget']) ext._timing[k] = 0;
    claudeHere = true;
    // the Claude extension as S29 saw it: primaryEditor.open reveals a panel
    // the chat has, or makes one, loaded from disk
    // two groups, side by side; the second one empty and never shown until
    // a test puts it there
    const tabs = [], tabs2 = [];
    const active = { tab: undefined }, active2 = { tab: undefined };
    // peek: called each time the first group's front tab is read, for a tab
    // that turns up between two looks
    let peek = null;
    const group = { viewColumn: 1, get tabs() { return tabs; }, get activeTab() { if (peek) peek(); return active.tab; } };
    const group2 = { viewColumn: 2, get tabs() { return tabs2; }, get activeTab() { return active2.tab; } };
    const slot = (g) => (g === group2 ? { list: tabs2, act: active2 } : { list: tabs, act: active });
    let groupsNow = [group], activeGroup = group, makeIn = group;
    const titles = { [SID]: 'T' };
    let fail = {};
    let makeLater = 0;
    let revealMode = 'normal';
    // never: the command given never settles
    let never = '';
    const claudeTab = (sid, label, g) => ({ label, sid, input: new TabInputWebview('claudeVSCodePanel'), group: g || group });
    stub.window.tabGroups = {
        get all() { return groupsNow; }, get activeTabGroup() { return activeGroup; },
        close: async (t) => {
            calls.push('close:' + t.label);
            const s = slot(t.group);
            s.list.splice(s.list.indexOf(t), 1);
            if (s.act.tab === t) s.act.tab = s.list[0];
            return true;
        }
    };
    const bars = [];
    stub.window.setStatusBarMessage = (m, ms) => { bars.push(m); return { dispose() { } }; };
    stub.commands.executeCommand = async (c, sid) => {
        calls.push(c);
        if (never === c) return new Promise(() => { });
        if (fail[c]) { fail[c]--; throw new Error('boom'); }
        if (c === 'claude-vscode.primaryEditor.open') {
            const have = tabs.concat(tabs2).find(t => t.sid === sid);
            if (revealMode === 'nothing') return;
            if (have) { slot(have.group).act.tab = have; return; }
            const make = () => { const t = claudeTab(sid, titles[sid], makeIn); const s = slot(makeIn); s.list.push(t); s.act.tab = t; };
            if (makeLater) setTimeout(make, makeLater); else make();
        }
    };
    let answer, warnAnswer;
    const asked = [];
    stub.window.showInformationMessage = async (m, ...b) => { calls.push('ask'); asked.push(m); return b.includes(answer) ? answer : undefined; };
    stub.window.showWarningMessage = async (m, ...b) => { calls.push('warn'); asked.push(m); return b.includes(warnAnswer) ? warnAnswer : undefined; };
    const reqT = { kind: 'ran', sessionId: SID, title: 'T' };
    const reset = () => {
        calls.length = 0; asked.length = 0; tabs.length = 0; tabs2.length = 0; active.tab = undefined; active2.tab = undefined; fail = {}; makeLater = 0;
        revealMode = 'normal'; peek = null; groupsNow = [group]; activeGroup = group; makeIn = group; never = ''; warnAnswer = undefined;
    };
    // the chat's tab up, and its group - Claude tabs alone - unlocked
    const OPEN = 'claude-vscode.primaryEditor.open';
    const UNLOCK = 'workbench.action.unlockEditorGroup';
    const OPENED = OPEN + ',' + UNLOCK;

    check('Reload Webviews and the side bar\'s editor.open are gone', ext._showWebviews === undefined && ext._focus === undefined);

    reset();
    const r1 = await ext._showTab(reqT);
    check('a tab: none open - one open, loaded from disk, nothing closed, and its group of Claude tabs unlocked', r1 === 'new' && calls.join() === OPENED, calls.join());
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
    // the chat of 27 characters whose tab read "Extension icon IMG_8588." and an ellipsis
    const longT = 'Extension icon IMG_8588.jpg';
    const shortT = ext._claudeTabLabel(longT);
    tabs.push(claudeTab(SID, shortT), other);
    active.tab = other;
    const r3b = await ext._showTab(Object.assign({}, reqT, { title: longT }));
    check('a stale tab whose label the Claude extension shortened - closed and opened again',
        r3b === 'reopened' && calls.join() === 'claude-vscode.primaryEditor.open,close:' + shortT + ',claude-vscode.primaryEditor.open', calls.join());
    reset();
    tabs.push(claudeTab(SID, 'Claude Code'), other);
    active.tab = other;
    const r3c = await ext._showTab(Object.assign({}, reqT, { title: '' }));
    check('a chat of no title: an untitled Claude tab is never taken for it', r3c === 'stale' && !calls.some(c => c.startsWith('close:')), calls.join());
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
    // two chats whose titles share their first 24 characters: one label for
    // both, the other chat's tab in front, and primaryEditor.open doing nothing
    const SID2 = '22222222-2222-4222-8222-222222222222';
    const twinA = claudeTab(SID, shortT), twinB = claudeTab(SID2, shortT);
    tabs.push(twinA, twinB);
    active.tab = twinB;
    revealMode = 'nothing';
    const r6 = await ext._showTab(Object.assign({}, reqT, { title: longT }));
    check('two chats of one shortened label, the other one\'s tab in front: never closed, and says so',
        r6 === 'stale' && !calls.some(c => c.startsWith('close:')) && tabs.length === 2 && asked[0] === ext._texts.staleTab({ title: longT }), r6 + ' ' + calls.join());
    reset();
    tabs.push(claudeTab(SID, 'T'));
    active.tab = tabs[0];
    ext._timing.tabRecount = 100;
    revealMode = 'nothing';
    // the chat's new tab comes only after both looks the first one takes
    setTimeout(() => { const t = claudeTab(SID2, 'T2'); tabs.push(t); active.tab = t; }, 150);
    const r7 = await ext._showTab(reqT);
    ext._timing.tabRecount = 0;
    check('the front tab unchanged: one more look before closing it, and a new tab found then is left', r7 === 'new' && !calls.some(c => c.startsWith('close:')), r7 + ' ' + calls.join());
    reset();
    const other2 = { label: 'notes.md', input: new TabInputText('x'), group };
    tabs.push(other2);
    active.tab = other2;
    const r8 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    check('a tab in a group holding other editors: the group left as it is', r8 === 'new' && calls.join() === OPEN, calls.join());
    reset();
    fail[UNLOCK] = 1;
    logged.length = 0;
    let r9, unlockThrew = false;
    try { r9 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] }); } catch (e) { unlockThrew = true; }
    check('an unlock that fails is logged, never thrown, and the tab stands', r9 === 'new' && !unlockThrew && logged.some(l => /^unlocking the group failed/.test(l)),
        r9 + ' ' + logged.join(' | '));
    // the chat's tab made in a second group, while the first stays active:
    // the command would unlock the first
    reset();
    logged.length = 0;
    groupsNow = [group, group2];
    makeIn = group2;
    tabs.push(claudeTab(SID2, 'T2'));
    active.tab = tabs[0];
    const gr1 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    const gr1Calls = calls.join();
    reset();
    groupsNow = [group, group2];
    makeIn = group2;
    activeGroup = group2;
    tabs.push(claudeTab(SID2, 'T2'));
    const gr2 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    check('group: the one holding the chat\'s tab, and only while it is the active group - the command acts on that one',
        gr1 === 'new' && gr1Calls === OPEN && logged.some(l => l === 'group left as it is: the chat\'s tab is not in the active group') &&
        gr2 === 'new' && calls.join() === OPENED, gr1Calls + ' / ' + calls.join() + ' | ' + logged.join(' | '));
    reset();
    logged.length = 0;
    activeGroup = undefined;
    const gr3 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    check('group: no active group - nothing unlocked, and logged as that', gr3 === 'new' && calls.join() === OPEN &&
        logged.includes('group left as it is: no active group'), calls.join() + ' | ' + logged.join(' | '));
    reset();
    logged.length = 0;
    cfgVals['claudeCode.lockEditorGroups'] = true;
    const gr4 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    const gr4Calls = calls.join();
    reset();
    cfgVals['claudeCode.lockEditorGroups'] = false;
    const gr5 = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    delete cfgVals['claudeCode.lockEditorGroups'];
    check('group: claudeCode.lockEditorGroups set true is the user\'s choice, and left locked; set false, or unset, it is unlocked',
        gr4 === 'new' && gr4Calls === OPEN && logged.some(l => /lockEditorGroups is set true/.test(l)) && gr5 === 'new' && calls.join() === OPENED,
        gr4Calls + ' / ' + calls.join());
    reset();
    tabs.push(claudeTab(SID, 'T'));
    active.tab = tabs[0];
    const gr6 = await ext._showTab(reqT);
    check('group: a stale tab closed and opened again - the new one\'s group of Claude tabs unlocked too',
        gr6 === 'reopened' && calls.join() === OPEN + ',close:T,' + OPENED && tabs.length === 1 && tabs[0].sid === SID, gr6 + ' ' + calls.join());
    // a new tab that turns up after the looks and before the close: the one
    // in front is not closed
    reset();
    tabs.push(claudeTab(SID, 'T'), other);
    active.tab = other;
    let looks = 0;
    peek = () => { if (++looks === 2) tabs.push(claudeTab(SID2, 'T2')); };
    const late = await ext._showTab(reqT);
    peek = null;
    check('a tab: one that came late, just before the close - taken as the chat\'s new tab, and nothing closed',
        late === 'new' && !calls.some(c => c.startsWith('close:')) && tabs.length === 3, late + ' ' + calls.join());
    // held working: a tab here is the chat's only when exactly one reads as it
    const heldHere = (x) => ext._openTab(Object.assign({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'held', hostPids: [process.pid] }, x));
    reset();
    tabs.push(claudeTab(SID, 'T'), claudeTab(SID2, 'T'));
    const w1 = await heldHere({});
    const w1Calls = calls.join();
    reset();
    tabs.push(claudeTab(SID, 'Claude Code'));
    const w2 = await heldHere({ title: '' });
    check('an open held working here, with two tabs of its label, or of no title: counted as in no tab, and not opened',
        w1 === 'working' && w1Calls === 'ask' && w2 === 'working' && calls.join() === 'ask', w1 + ' ' + w1Calls + ' / ' + w2 + ' ' + calls.join());
    // on a Mac the window cannot be told: hostPids is empty
    reset();
    const w3 = await heldHere({ hostPids: [] });
    const w3Calls = calls.join();
    reset();
    tabs.push(claudeTab(SID, 'T'));
    const w4 = await heldHere({ hostPids: [] });
    check('an open held working where no window can be told (a Mac): refused as held here - unless exactly one tab reads as it',
        w3 === 'working' && w3Calls === 'ask' && asked.length === 0 && w4 === 'revealed' && calls.join() === OPENED, w3 + ' ' + w3Calls + ' / ' + w4 + ' ' + calls.join());
    // a command that never settles: the show queue moves on
    reset();
    logged.length = 0;
    ext._timing.commandTimeout = 30;
    never = OPEN;
    const nv1 = await ext._enqueue(() => ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] }));
    const nv2 = await ext._enqueue(() => ext._showTab(reqT));
    never = '';
    const nv3 = await ext._enqueue(async () => 'next');
    ext._timing.commandTimeout = 0;
    check('a command that never settles: timed out, logged, taken as failed and not asked again - and the queue goes on',
        nv1 === 'failed' && nv2 === undefined && nv3 === 'next' && calls.filter(c => c === OPEN).length === 2 &&
        logged.filter(l => l === OPEN + ' timed out after 30 ms').length === 2 && asked[0] === ext._texts.notOpened({ title: 'T' }) &&
        logged.some(l => /^show failed: .*timed out/.test(l)), nv1 + ' ' + nv2 + ' ' + nv3 + ' ' + calls.join() + ' | ' + logged.join(' | '));

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
    check('a run into a quiet exact window: a tab of its own, by itself, and says on what',
        calls.join() === OPENED && logged.some(l => l === 'ran 11111111 by itself: busy false, oldProcess ended') && asked.length === 0, calls.join());
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
        calls.join() === 'ask,' + OPENED && asked[0].endsWith('Show it?') && bars[0] === ext._texts.checking &&
        bars.length === 1 && logged.includes('Show it 11111111: busy false, oldProcess ended, outcome ok'), calls.join());
    // the chat's old view here was outside the tabs: its process ended, and a
    // new tab made, that view is dead
    aliveSet.add(process.pid);
    reset();
    fresh('f2b', { hostPids: [process.pid] });
    ext._check(context, file, false);
    await settle();
    const f2b = calls.join(), f2bAsked = asked.slice();
    reset();
    folders.push({ uri: { fsPath: path.resolve('/work/projB') } });
    answer = 'Show it';
    ext._getVerdict = async () => ({ busy: false, oldProcess: 'ended', outcome: 'ok', hostPids: [process.pid] });
    fresh('f2c', { hostPids: [] });
    ext._check(context, file, false);
    await settle();
    folders.pop();
    answer = undefined;
    const f2c = calls.join(), f2cAsked = asked.slice();
    reset();
    tabs.push(claudeTab(SID, 'T'));
    active.tab = tabs[0];
    fresh('f2d', { hostPids: [process.pid] });
    ext._check(context, file, false);
    await settle();
    aliveSet.clear();
    check('a run\'s new tab where this window held the chat - by the request, or by Show it\'s check: the side bar\'s copy said stale, once',
        f2b === OPENED + ',ask' && f2bAsked.length === 1 && f2bAsked[0] === ext._texts.sideBarStale({ title: 'T' }) &&
        f2c === 'ask,' + OPENED + ',ask' && f2cAsked.length === 2 && f2cAsked[1] === ext._texts.sideBarStale({ title: 'T' }), f2b + ' / ' + f2c);
    check('but not when the tab here showed it, and was opened again', !asked.includes(ext._texts.sideBarStale({ title: 'T' })) &&
        calls.some(c => c.startsWith('close:')), calls.join());
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
        asked[1] === 'chatq could not end the old process of "T", so only a reload shows the run.' &&
        logged.includes('Show it 11111111: the check failed; the request\'s oldProcess live'), calls.join());
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
    // the check finds the chat held working, or another chat busy: the
    // reload the plan gives is asked as the offer asks it
    const heldSaid = ext._message(fr({ oldProcess: 'held' }), true);
    reset();
    answer = 'Show it';
    warnAnswer = 'Reload anyway';
    ext._getVerdict = async () => ({ busy: true, oldProcess: 'held', outcome: 'held', hostPids: [] });
    fresh('f7', { away: false });
    ext._check(context, file, false);
    await settle();
    const f7 = calls.join(), f7Asked = asked.slice();
    reset();
    answer = 'Show it';
    warnAnswer = 'Reload anyway';
    ext._getVerdict = async () => ({ busy: true, oldProcess: 'live', outcome: 'ok', hostPids: [] });
    fresh('f8', { away: false });
    ext._check(context, file, false);
    await settle();
    const f8 = calls.join(), f8Asked = asked.slice();
    reset();
    answer = 'Show it';
    ext._getVerdict = async () => ({ busy: true, oldProcess: 'kept', outcome: 'ok', hostPids: [] });
    fresh('f8b', { away: false });
    ext._check(context, file, false);
    await settle();
    answer = undefined;
    check('Show it finding the chat held working: the held wording and Reload anyway, never "could not end" and Reload',
        f7 === 'ask,warn,workbench.action.reloadWindow' && f7Asked[1] === heldSaid, f7 + ' | ' + f7Asked.join(' | '));
    check('Show it finding another chat busy, this one not held (live or kept): that other chat\'s work named, and Reload anyway - never the held wording, never "could not end"',
        f8 === 'ask,warn,workbench.action.reloadWindow' && f8Asked[1] === ext._texts.ranBusy(reqT) && f8Asked[1] !== heldSaid &&
        /another chat in this workspace is still working/.test(f8Asked[1]) && calls.join() === 'ask,warn' && asked[1] === ext._texts.ranBusy(reqT) &&
        !f8Asked.concat(asked).includes(ext._texts.couldNotEnd(reqT)), f8 + ' / ' + calls.join() + ' | ' + f8Asked.join(' | ') + ' | ' + asked.join(' | '));
    // the check failing, or judging nothing, on a request that found another
    // chat busy: that busy still stands
    const busyFallback = async (id, verdict) => {
        reset();
        answer = 'Show it';
        warnAnswer = 'Reload anyway';
        ext._getVerdict = async () => verdict;
        fresh(id, { away: false, busy: true, oldProcess: 'live' });
        ext._check(context, file, false);
        await settle();
        answer = undefined;
        return [calls.join(), asked.slice()];
    };
    const [f9, f9Asked] = await busyFallback('f9', null);
    const [f9b, f9bAsked] = await busyFallback('f9b', { busy: null, oldProcess: 'none', outcome: 'missing', hostPids: [] });
    check('Show it with the check failing, or judging nothing, on a request that found another chat busy: that chat\'s work named, and Reload anyway - never "could not end" and Reload',
        f9 === 'ask,warn,workbench.action.reloadWindow' && f9Asked[1] === ext._texts.ranBusy(reqT) &&
        f9b === 'ask,warn,workbench.action.reloadWindow' && f9bAsked[1] === ext._texts.ranBusy(reqT),
        f9 + ' | ' + f9Asked.join(' | ') + ' / ' + f9b + ' | ' + f9bAsked.join(' | '));
    check('says: a print-mode run going into the chat, either kind named, and no offer promised that only a queued one brings',
        [ext._texts.running(reqT), ext._texts.pickRunning(reqT)].every(t => t.startsWith('A print-mode run (a queued prompt, or claude -p) is going into "T"') &&
            !/offer|show it again|chatq/i.test(t) && /Open it once that run finishes\.$/.test(t)),
        ext._texts.running(reqT) + ' | ' + ext._texts.pickRunning(reqT));

    // end to end, the overlay's open request
    const ofile = path.join(dir, 'extension-check-open.json');
    const open = (id, x) => fs.writeFileSync(ofile, JSON.stringify(Object.assign({ id, kind: 'open', title: 'T', sessionId: SID, cwd: path.resolve('/work/projA'),
        home: null, busy: null, oldProcess: 'none', hostPids: [], at: new Date().toISOString() }, x)));
    reset();
    logged.length = 0;
    open('o1');
    const o1 = await ext._checkOpen(context, ofile, false);
    await settle();
    check('an open: a new tab, by primaryEditor.open - never editor.open, never Reload Webviews, and logged',
        o1 === 'new' && calls.join() === OPENED && tabs.length === 1 &&
        logged.includes('open 11111111: new (oldProcess none, hostPids none)'), calls.join() + ' | ' + logged.join(' | '));
    reset();
    tabs.push(claudeTab(SID, 'T'));
    open('o2', { oldProcess: 'live' });
    const o2 = await ext._checkOpen(context, ofile, false);
    await settle();
    check('an open the chat has a tab for: that tab brought forward, nothing closed, nothing said',
        o2 === 'revealed' && calls.join() === OPENED && tabs.length === 1 && asked.length === 0, calls.join());
    reset();
    aliveSet.add(process.pid);
    logged.length = 0;
    open('o2b', { oldProcess: 'live', hostPids: [process.pid] });
    const o2b = await ext._checkOpen(context, ofile, false);
    await settle();
    check('an open held idle by a process of this window, and a new tab: said once, it now runs in two places, the side bar\'s copy idle',
        o2b === 'new' && calls.join() === OPENED + ',ask' && asked.length === 1 && asked[0] === ext._texts.twoPlaces({ title: 'T', oldProcess: 'live' }) &&
        logged.includes('open 11111111: new (oldProcess live, hostPids ' + process.pid + ')'), calls.join() + ' | ' + logged.join(' | '));
    reset();
    tabs.push(claudeTab(SID, 'T'));
    open('o2c', { oldProcess: 'held', hostPids: [process.pid] });
    const o2c = await ext._checkOpen(context, ofile, false);
    await settle();
    const o2cSaid = calls.join() + ' ' + asked.length;
    reset();
    open('o2d', { oldProcess: 'none', hostPids: [process.pid] });
    const o2d = await ext._checkOpen(context, ofile, false);
    await settle();
    const o2dSaid = calls.join() + ' ' + asked.length;
    aliveSet.clear();
    reset();
    const o2e = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'live', hostPids: [999991] });
    const o2eSaid = calls.join() + ' ' + asked.length;
    check('but not when a tab here showed it, when no process held it, nor when another window\'s held it',
        o2c === 'revealed' && o2cSaid === OPENED + ' 0' && o2d === 'new' && o2dSaid === OPENED + ' 0' && o2e === 'new' && o2eSaid === OPENED + ' 0',
        o2c + ' ' + o2cSaid + ' / ' + o2d + ' ' + o2dSaid + ' / ' + o2e + ' ' + o2eSaid);
    // working here outside the tabs, most likely the side bar: a tab now
    // would start a second process mid-turn
    aliveSet.add(process.pid);
    reset();
    logged.length = 0;
    open('o2w', { oldProcess: 'held', hostPids: [process.pid] });
    const o2w = await ext._checkOpen(context, ofile, false);
    await settle();
    const o2wSaid = calls.join(), o2wAsked = asked.slice();
    reset();
    tabs.push(claudeTab(SID, shortT));
    open('o2x', { oldProcess: 'held', hostPids: [process.pid], title: longT });
    const o2x = await ext._checkOpen(context, ofile, false);
    await settle();
    aliveSet.clear();
    check('an open working in a process of this window, and no tab here of its title: not opened, and says to click open again once it finishes',
        o2w === 'working' && o2wSaid === 'ask' && o2wAsked[0] === ext._texts.working({ title: 'T' }) &&
        logged.some(l => /^open 11111111: not opened - working here outside the tabs/.test(l)), o2w + ' ' + o2wSaid + ' | ' + logged.join(' | '));
    check('but a tab of its shortened title is opened - it is the chat\'s', o2x === 'revealed' && calls.join() === OPENED, o2x + ' ' + calls.join());
    reset();
    fail['claude-vscode.primaryEditor.open'] = 2;
    const o2f = await ext._openTab({ kind: 'open', sessionId: SID, title: 'T', oldProcess: 'none', hostPids: [] });
    check('an open the Claude extension refuses twice: said, and nothing else tried',
        o2f === 'failed' && calls.join() === 'claude-vscode.primaryEditor.open,claude-vscode.primaryEditor.open,ask' && asked[0] === ext._texts.notOpened({ title: 'T' }), calls.join());
    reset();
    claudeHere = false;
    open('o2g');
    await ext._checkOpen(context, ofile, false);
    await settle();
    claudeHere = true;
    check('an open with no Claude extension here: said, no command, no reload offer',
        calls.join() === 'ask' && asked[0] === ext._texts.noClaude({ title: 'T' }), calls.join());
    reset();
    cfgVals['chatManager.showFresh'] = false;
    open('o2h');
    await ext._checkOpen(context, ofile, false);
    await settle();
    delete cfgVals['chatManager.showFresh'];
    check('showFresh off does not stop an open: nothing was ended, so a tab still', calls.join() === OPENED, calls.join());
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
    check('a window just opened for it shows the chat in a tab, and nothing else', calls.join() === OPENED, calls.join());
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
    check('the same open twice acts once', calls.join() === OPENED, calls.join());

    // --- the chat picker: Chat Manager: Open chat... ---------------------------
    // a Claude home of its own, its transcripts and its registry written here
    const os = require('os');
    const pk = path.join(dir, 'ext-pick');
    fs.rmSync(pk, { recursive: true, force: true });
    const home = path.join(pk, 'home');
    const projA = path.resolve('/work/projA'), projB = path.resolve('/work/projB');
    check('pick: a folder\'s project, named as Get-ChatSlug names it', ext._chatSlug('C:\\work\\projA') === 'C--work-projA' &&
        ext._chatSlug('C:\\work\\projA\\') === 'C--work-projA' && ext._chatSlug('C:\\') === 'C--' && ext._chatSlug('/home/me/x.y') === '-home-me-x-y' &&
        ext._chatSlug('D:\\a b\\c_d') === 'D--a-b-c-d', ext._chatSlug('C:\\'));
    check('pick: noise and titles, as Test-ChatNoise and Format-ChatTitle have them',
        ext._isNoise('<command-name>') && ext._isNoise('Caveat: x') && ext._isNoise('a <SYSTEM-REMINDER> b') && ext._isNoise('[Request interrupted by user]') &&
        !ext._isNoise('fix it') && ext._formatTitle('') === '(empty)' && ext._formatTitle('  a \n b  ') === 'a b' &&
        ext._formatTitle('x'.repeat(59) + ' yz') === 'x'.repeat(59) + '...' && ext._formatTitle('y'.repeat(60)) === 'y'.repeat(60));
    const G = (n) => n.toString(16).padStart(8, '0') + '-0000-4000-8000-000000000000';
    const jl = (o) => JSON.stringify(o) + '\n';
    const user = (content, x) => jl(Object.assign({ type: 'user', isSidechain: false, message: { role: 'user', content } }, x));
    const asst = (text) => jl({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text }] } });
    const pnow = Date.now();
    const MIN = 60000, HOUR = 3600000, DAY = 86400000;
    const mkChat = (d, id, text, ago) => {
        fs.mkdirSync(d, { recursive: true });
        const f = path.join(d, id + '.jsonl');
        fs.writeFileSync(f, text);
        const t = new Date(pnow - ago);
        fs.utimesSync(f, t, t);
        return f;
    };
    // projA's folder in lower case, as another window's Claude may have made
    // it; projB's as it is
    const dirA = path.join(home, 'projects', ext._chatSlug(projA).toLowerCase());
    const dirB = path.join(home, 'projects', ext._chatSlug(projB));
    const S = { custom: G(1), ai: G(2), prompt: G(3), side: G(4), empty: G(5), big: G(6), sidecar: G(7), long: G(8), inB: G(9), bigHead: G(10) };
    // a quarter of a megabyte and more between a big file's ends
    const filler = asst('y'.repeat(1000)).repeat(700);
    const longPrompt = 'a long first prompt that goes on and on past the sixty characters a title keeps';
    mkChat(dirA, S.custom, user('first prompt') + asst('x') + jl({ type: 'ai-title', aiTitle: 'ai name' }) +
        jl({ type: 'custom-title', customTitle: 'my name' }) + jl({ type: 'ai-title', aiTitle: 'later ai name' }), 4 * MIN);
    mkChat(dirA, S.ai, user('p') + asst('x') + jl({ type: 'ai-title', aiTitle: 'old ai' }) + jl({ type: 'ai-title', aiTitle: 'new ai' }), 3 * HOUR);
    mkChat(dirA, S.prompt, user('<command-name>/clear</command-name>') + user('Caveat: the messages below') + user('<system-reminder>x</system-reminder> hi') +
        user('[Request interrupted by user]') + user([{ type: 'tool_result', content: 'r' }]) + user('meta', { isMeta: true }) +
        user([{ type: 'text', text: '  fix the\n  bug ' }, { type: 'text', text: 'please' }]) + asst('ok') + user('a later prompt'), 2 * DAY);
    mkChat(dirA, S.side, user('agent work', { isSidechain: true }) + asst('x'), 5 * MIN);
    mkChat(dirA, S.empty, jl({ type: 'ai-title', aiTitle: 'ghost' }) + jl({ type: 'mode', mode: 'x' }), 6 * MIN);
    mkChat(dirA, S.big, user('head prompt') + jl({ type: 'ai-title', aiTitle: 'head ai' }) + filler + jl({ type: 'ai-title', aiTitle: 'tail ai' }) + asst('z'), 7 * MIN);
    mkChat(dirA, S.sidecar, user('a prompt') + jl({ type: 'ai-title', aiTitle: 'ai one' }), 8 * MIN);
    fs.mkdirSync(path.join(dirA, S.sidecar), { recursive: true });
    fs.writeFileSync(path.join(dirA, S.sidecar, 'custom-title.json'), '\uFEFF{"customTitle":"from the side"}');
    mkChat(dirA, S.bigHead, user('only in the head') + filler, 9 * MIN);
    mkChat(dirA, S.long, user(longPrompt), 10 * MIN);
    mkChat(dirB, S.inB, user('in B'), 1 * MIN);
    // not chats: another name, another type, and one a folder deeper
    mkChat(dirA, 'notes', user('n'), 0);
    fs.writeFileSync(path.join(dirA, G(11) + '.json'), user('j'));
    mkChat(path.join(dirA, 'sub'), G(12), user('deep'), 0);
    const reg = path.join(home, 'sessions');
    fs.mkdirSync(reg, { recursive: true });
    const regPut = (pid, x) => fs.writeFileSync(path.join(reg, pid + '.json'),
        JSON.stringify(Object.assign({ pid, cwd: projA, startedAt: pnow - HOUR, procStart: '1', status: 'idle', entrypoint: 'claude-vscode' }, x)));
    regPut(999101, { sessionId: S.custom });
    regPut(999102, { sessionId: S.ai, entrypoint: 'cli' });
    regPut(999112, { sessionId: S.ai });
    regPut(999103, { sessionId: S.prompt, status: 'busy' });
    regPut(999104, { sessionId: S.sidecar });
    regPut(999105, { sessionId: S.long, startedAt: pnow + HOUR });
    regPut(999106, { sessionId: S.big, status: 'waiting', startedAt: pnow - (os.uptime() + 3600) * 1000 });
    regPut(999107, { sessionId: S.inB, status: 'waiting' });
    fs.writeFileSync(path.join(reg, '999108.json'), '{not json');
    fs.writeFileSync(path.join(reg, 'x.json'), JSON.stringify({ pid: 999101, sessionId: S.bigHead, entrypoint: 'cli' }));
    // every pid but 999104's is running
    for (const p of [999101, 999102, 999112, 999103, 999105, 999106, 999107]) aliveSet.add(p);
    folders.push({ uri: { fsPath: projB } });
    const listed = await ext._listChats(home, folders);
    const newest = [S.inB, S.custom, S.side, S.empty, S.big, S.sidecar, S.bigHead, S.long, S.ai, S.prompt];
    check('pick: every folder\'s <GUID>.jsonl, newest first - a project folder of another case found, nothing else and nothing deeper listed',
        listed.map(c => c.sid).join() === newest.join() && listed[0].folder === 'projB' && listed[1].folder === 'projA',
        listed.map(c => c.sid.slice(0, 8)).join());
    ext._titleCache.clear();
    const realReadChat = ext._readChat;
    let reads = 0;
    ext._readChat = (c) => { reads++; return realReadChat(c); };
    const desc = {};
    for (const c of listed) desc[c.sid] = await ext._describeChat(c);
    const tl = (sid) => (desc[sid] || {}).title;
    check('pick: a rename first, the newest; then the newest ai-title; then the first prompt typed, past the noise',
        tl(S.custom) === 'my name' && tl(S.ai) === 'new ai' && tl(S.prompt) === 'fix the bug please' && tl(S.inB) === 'in B', JSON.stringify(desc));
    check('pick: the sidecar\'s rename over an ai-title; a big file\'s ai-title from its tail, its prompt from its head',
        tl(S.sidecar) === 'from the side' && tl(S.big) === 'tail ai' && tl(S.bigHead) === 'only in the head', JSON.stringify(desc));
    check('pick: a side transcript, and a small one holding no message, are left out',
        desc[S.side].skip === 'side' && desc[S.empty].skip === 'empty' && tl(S.long) === longPrompt, JSON.stringify(desc));
    const readsFirst = reads;
    for (const c of listed) await ext._describeChat(c);
    const readsAgain = reads;
    const tLong = new Date(pnow - 10 * MIN + 1000);
    fs.appendFileSync(path.join(dirA, S.long + '.jsonl'), jl({ type: 'ai-title', aiTitle: 'now titled' }));
    fs.utimesSync(path.join(dirA, S.long + '.jsonl'), tLong, tLong);
    const relisted = (await ext._listChats(home, folders)).find(c => c.sid === S.long);
    const retitled = await ext._describeChat(relisted);
    check('pick: titles kept by path, size and write time - read again only once the file changes',
        readsFirst === listed.length && readsAgain === readsFirst && reads === readsFirst + 1 && retitled.title === 'now titled', readsFirst + ' ' + readsAgain + ' ' + reads);
    const reg1 = ext._readRegistry(home, Date.now());
    const st = (sid) => ext._chatState(reg1.get(sid));
    check('pick: what runs each chat - a panel idle is open, busy or waiting is working, a terminal wins, and nothing is closed',
        st(S.custom) === 'open' && st(S.prompt) === 'working' && st(S.inB) === 'working' && st(S.ai) === 'terminal' && st(S.bigHead) === 'closed',
        [S.custom, S.prompt, S.inB, S.ai, S.bigHead].map(st).join());
    check('pick: an entry whose pid is gone, whose startedAt is ahead, or from before the machine started, runs nothing',
        st(S.sidecar) === 'closed' && st(S.long) === 'closed' && st(S.big) === 'closed' && !reg1.has('999108'), [S.sidecar, S.long, S.big].map(st).join());
    check('pick: a run nobody types in - a kind set and not interactive, as chatq\'s claude -p - is running, never a terminal; an interactive one still is',
        ext._chatState([{ kind: 'print', entrypoint: 'sdk-cli', status: 'busy' }]) === 'running' &&
        ext._chatState([{ kind: 'print', entrypoint: 'sdk-cli' }, { entrypoint: 'claude-vscode', status: 'idle' }]) === 'running' &&
        ext._chatState([{ kind: 'interactive', entrypoint: 'cli' }]) === 'terminal' &&
        ext._chatState([{ kind: 'interactive', entrypoint: 'claude-vscode', status: 'busy' }]) === 'working',
        ext._chatState([{ kind: 'print', entrypoint: 'sdk-cli', status: 'busy' }]));
    check('pick: an entry naming no entrypoint is no terminal - as the script\'s where has it, only another entrypoint is',
        ext._chatState([{ status: 'idle' }]) === 'open' && ext._chatState([{ entrypoint: '', status: 'busy' }]) === 'working' &&
        ext._chatState([{ status: 'idle' }, { entrypoint: 'cli' }]) === 'terminal',
        ext._chatState([{ status: 'idle' }]) + ' ' + ext._chatState([{ entrypoint: '', status: 'busy' }]));
    check('pick: only a whole codicon pattern is escaped, as VS Code\'s escapeIcons does - any other "$(" left as typed, and one escaped already kept',
        ext._noIcons('x $(a b)') === 'x $(a b)' && ext._noIcons('echo $(git rev-parse HEAD)') === 'echo $(git rev-parse HEAD)' &&
        ext._noIcons('$(terminal)') === '\\$(terminal)' && ext._noIcons('$(sync~spin) and $(x') === '\\$(sync~spin) and $(x' &&
        ext._noIcons('\\$(terminal)') === '\\$(terminal)',
        [ext._noIcons('x $(a b)'), ext._noIcons('echo $(git rev-parse HEAD)'), ext._noIcons('$(terminal)')].join(' | '));
    const escItem = ext._pickItem({ sid: G(1), mtimeMs: pnow, folder: 'f$(x)' }, { title: 'use $(terminal) here' }, 'open', true, pnow);
    check('pick: a "$(" in a title, or a folder\'s name, is kept as typed - never drawn as a codicon',
        escItem.label === '$(window) use \\$(terminal) here' && escItem.detail === 'f\\$(x)', escItem.label + ' ' + escItem.detail);
    check('pick: the age, as Get-ChatAge gives it', ext._ageText(30000) === 'now' && ext._ageText(4 * MIN) === '4m' && ext._ageText(3 * HOUR) === '3h' &&
        ext._ageText(2 * DAY) === '2d' && ext._ageText(40 * DAY) === '1mo');
    // the QuickPick, each assignment of its items recorded
    const qps = [];
    // called as each list is put in, for what a test wants to know just then
    let atSet = () => undefined;
    stub.window.createQuickPick = () => {
        let items = [];
        const qp = {
            activeItems: [], selectedItems: [], busy: false, sets: [], disposed: false,
            show() { }, hide() { if (this.hideCb) this.hideCb(); }, dispose() { this.disposed = true; },
            onDidAccept(cb) { this.acceptCb = cb; }, onDidHide(cb) { this.hideCb = cb; }
        };
        Object.defineProperty(qp, 'items', { get: () => items, set: (v) => { items = v; qp.sets.push({ at: Date.now(), labels: v.map(i => i.label), mark: atSet() }); } });
        qps.push(qp);
        return qp;
    };
    // up to 10 s: a slow machine only waits longer, it never fails for it
    const waitFor = async (fn) => {
        for (const end = Date.now() + 10000; !fn() && Date.now() < end;) await new Promise(r => setTimeout(r, 4));
        return fn();
    };
    const accept = (qp, sid) => { qp.selectedItems = [qp.items.find(i => i.chat.sid === sid)]; qp.acceptCb(); };
    reset();
    logged.length = 0;
    process.env.CLAUDE_CONFIG_DIR = home;
    warnAnswer = 'Cancel';
    const p1 = ext._openChat();
    const qp1 = qps[qps.length - 1];
    await waitFor(() => qp1.sets.length && !qp1.busy);
    const shownItems = qp1.items;
    const label = (sid) => (shownItems.find(i => i.chat.sid === sid) || {}).label;
    const descr = (sid) => (shownItems.find(i => i.chat.sid === sid) || {}).description;
    check('pick: the chats listed, newest first, each by its title, the side and empty ones left out',
        shownItems.map(i => i.chat.sid).join() === [S.inB, S.custom, S.big, S.sidecar, S.bigHead, S.long, S.ai, S.prompt].join() &&
        label(S.sidecar) === 'from the side' && label(S.long) === 'now titled', shownItems.map(i => i.label).join(' | '));
    check('pick: a codicon for what runs it - $(terminal), $(sync~spin), $(window), none when closed',
        label(S.ai) === '$(terminal) new ai' && label(S.prompt) === '$(sync~spin) fix the bug please' && label(S.inB) === '$(sync~spin) in B' &&
        label(S.custom) === '$(window) my name' && label(S.big) === 'tail ai', shownItems.map(i => i.label).join(' | '));
    check('pick: the age and what runs it beside it, nothing for closed; and the folder, in a multi-root window',
        descr(S.custom) === '4m \u00b7 open' && descr(S.ai) === '3h \u00b7 in a terminal' && descr(S.prompt) === '2d \u00b7 working' && descr(S.big) === '7m' &&
        (shownItems.find(i => i.chat.sid === S.inB) || {}).detail === 'projB' && (shownItems.find(i => i.chat.sid === S.custom) || {}).detail === 'projA',
        shownItems.map(i => i.description + ' ' + i.detail).join(' | '));
    accept(qp1, S.custom);
    const pick1 = await p1;
    check('pick: open idle elsewhere in VS Code, no tab here - asked, with Open here too and Cancel; Cancel opens nothing',
        pick1 === 'cancelled' && calls.join() === 'warn' && asked[0] === ext._texts.pickElsewhere({ title: 'my name' }) && qp1.disposed &&
        logged.includes('pick 00000001: open -> cancelled'), pick1 + ' ' + calls.join() + ' | ' + logged.join(' | '));
    const chatOf = (sid) => listed.find(c => c.sid === sid);
    Object.assign(titles, { [S.custom]: 'my name', [S.prompt]: 'fix the bug please', [S.sidecar]: 'from the side' });
    reset();
    warnAnswer = 'Open here too';
    const a1 = await ext._acceptChat(chatOf(S.custom));
    check('pick: Open here too - opened, through the open chip\'s core', a1 === 'new' && calls.join() === 'warn,' + OPENED &&
        logged.includes('open 00000001: new (picked, open)'), a1 + ' ' + calls.join());
    reset();
    tabs.push(claudeTab(S.custom, 'my name'));
    const a2 = await ext._acceptChat(chatOf(S.custom));
    check('pick: open, and its one tab here - brought forward, nothing asked', a2 === 'revealed' && calls.join() === OPENED && asked.length === 0, a2 + ' ' + calls.join());
    reset();
    logged.length = 0;
    const a3 = await ext._acceptChat(chatOf(S.ai));
    check('pick: in a terminal - refused, and said', a3 === 'refused' && calls.join() === 'ask' && asked[0] === ext._texts.pickTerminal({ title: 'new ai' }) &&
        logged.includes('pick 00000002: terminal -> refused'), a3 + ' ' + calls.join());
    reset();
    const a4 = await ext._acceptChat(chatOf(S.prompt));
    const a4Calls = calls.join(), a4Asked = asked[0];
    reset();
    tabs.push(claudeTab(S.prompt, 'fix the bug please'), claudeTab(SID2, 'fix the bug please'));
    const a5 = await ext._acceptChat(chatOf(S.prompt));
    const a5Calls = calls.join();
    reset();
    tabs.push(claudeTab(S.prompt, 'fix the bug please'));
    const a6 = await ext._acceptChat(chatOf(S.prompt));
    check('pick: working - refused and told to open it once it finishes, twin tabs too; its one tab here only brought forward',
        a4 === 'refused' && a4Calls === 'ask' && a4Asked === ext._texts.pickWorking({ title: 'fix the bug please' }) && /once it finishes/.test(a4Asked) &&
        a5 === 'refused' && a5Calls === 'ask' && a6 === 'revealed' && calls.join() === OPENED, a4 + ' ' + a5 + ' ' + a6 + ' ' + calls.join());
    reset();
    logged.length = 0;
    const a7 = await ext._acceptChat(chatOf(S.sidecar));
    check('pick: closed - opened from disk, and logged', a7 === 'new' && calls.join() === OPENED && asked.length === 0 &&
        logged.includes('pick 00000007: closed -> new') && logged.includes('open 00000007: new (picked, closed)'), a7 + ' ' + calls.join() + ' | ' + logged.join(' | '));
    // titles slow to come: the chats listed at once by their ids, filled in
    // later, the item under the cursor kept
    reset();
    ext._titleCache.clear();
    ext._timing.pickBudget = 0;
    ext._readChat = async (c) => { await new Promise(r => setTimeout(r, 150)); return realReadChat(c); };
    const p2 = ext._openChat();
    const qp2 = qps[qps.length - 1];
    await waitFor(() => qp2.sets.length);
    const firstLabels = qp2.sets[0].labels.slice();
    const cursor = qp2.items.find(i => i.chat.sid === S.sidecar);
    qp2.activeItems = [cursor];
    await waitFor(() => !qp2.busy);
    const lastLabels = qp2.items.map(i => i.label);
    const kept = qp2.activeItems[0];
    qp2.hide();
    const p2r = await p2;
    check('pick: titles slow to read - listed at once by id, filled in as they come, the item under the cursor kept',
        firstLabels.includes(S.sidecar) && firstLabels.includes(S.side) && !lastLabels.includes(S.sidecar) && !lastLabels.includes(S.side) &&
        lastLabels.includes('from the side') && kept !== cursor && kept.chat.sid === S.sidecar && p2r === 'none',
        firstLabels.join(' | ') + ' / ' + lastLabels.join(' | '));
    // the cap, and listed before every title is read: 205 chats, none read
    // before, each read taking a few ms more than it would. Timers fire in
    // the order they fall due, so a budget of 20 ms is up well before 200
    // reads 16 at a time, 5 ms each, can be done - however slow the machine
    // - and no wall-clock limit is asserted.
    const home2 = path.join(pk, 'home2');
    const dir2 = path.join(home2, 'projects', ext._chatSlug(projA));
    for (let i = 0; i < 205; i++) mkChat(dir2, G(0x1000 + i), user('chat number ' + i) + asst('x'), i * 1000);
    folders.pop();
    const capped = await ext._listChats(home2, folders);
    process.env.CLAUDE_CONFIG_DIR = home2;
    ext._titleCache.clear();
    ext._timing.pickBudget = 20;
    let readsDone = 0;
    ext._readChat = async (c) => { await new Promise(r => setTimeout(r, 5)); const d = await realReadChat(c); readsDone++; return d; };
    atSet = () => readsDone;
    const pickT0 = Date.now();
    const p3 = ext._openChat();
    const qp3 = qps[qps.length - 1];
    await waitFor(() => qp3.sets.length);
    const first3 = qp3.sets[0];
    await waitFor(() => !qp3.busy);
    const all3 = qp3.items;
    qp3.hide();
    await p3;
    atSet = () => undefined;
    ext._readChat = realReadChat;
    ext._timing.pickBudget = 250;
    check('pick: the newest 200 only, listed before every title was read - the rest by id - and then every title read',
        capped.length === 200 && capped[0].sid === G(0x1000) && capped[199].sid === G(0x1000 + 199) &&
        first3.labels.length === 200 && first3.mark < 200 && first3.labels.some(l => ext._isGuid(l)) && readsDone === 200 && all3.length === 200 &&
        all3[0].label === 'chat number 0' && all3.every(i => /^chat number \d+$/.test(i.label)) && !all3[0].detail,
        capped.length + ' first list after ' + (first3.at - pickT0) + ' ms, ' + first3.mark + ' read then, ' + readsDone + ' in all, ' + all3.length + ' listed');
    process.env.CLAUDE_CONFIG_DIR = noHome;

    // --- a tab label another chat shares ---------------------------------------
    // A Claude tab carries no session id, only its label: a lone tab of the
    // chat's label may be another chat's, of the same title or of the same
    // first 24 characters, and this chat have no tab here at all.
    const home3 = path.join(pk, 'home3');
    const dir3 = path.join(home3, 'projects', ext._chatSlug(projA));
    const L = { a: G(0x2001), b: G(0x2002), long1: G(0x2003), long2: G(0x2004), solo: G(0x2005) };
    mkChat(dir3, L.a, user('T') + asst('x'), 1 * MIN);
    mkChat(dir3, L.b, user('something else') + asst('x') + jl({ type: 'custom-title', customTitle: 'T' }), 2 * MIN);
    mkChat(dir3, L.long1, user(longT) + asst('x'), 3 * MIN);
    mkChat(dir3, L.long2, user('Extension icon IMG_8588.png') + asst('x'), 4 * MIN);
    mkChat(dir3, L.solo, user('only me') + asst('x'), 5 * MIN);
    Object.assign(titles, { [L.a]: 'T', [L.solo]: 'only me' });
    ext._titleCache.clear();
    // a window on projB alone, for a chat of projB: projA's chats are no
    // tab of it
    folders.splice(0, folders.length, { uri: { fsPath: projB } });
    const lsB = await ext._labelShared('T', projB, L.a, home3);
    folders.splice(0, folders.length, { uri: { fsPath: projA } });
    check('label: shared where another chat of the folder has the same title, or the same first 24 characters - never with itself, nor for no title, nor in a folder neither the window\'s nor the chat\'s',
        await ext._labelShared('T', projA, L.a, home3) && await ext._labelShared(longT, projA, L.long1, home3) &&
        !(await ext._labelShared('only me', projA, L.solo, home3)) && !(await ext._labelShared('', projA, L.a, home3)) &&
        !lsB && !(await ext._labelShared('T', projA, L.a)));
    // twins in two folders of a multi-root window: a tab may come from any
    const dir3b = path.join(home3, 'projects', ext._chatSlug(projB));
    const L2 = { a: G(0x2101), b: G(0x2102) };
    mkChat(dir3b, L2.b, user('Twins across the folders') + asst('x'), 6 * MIN);
    mkChat(dir3, L2.a, user('Twins across the folders') + asst('x'), 7 * MIN);
    const lsMulti1 = await ext._labelShared('Twins across the folders', projA, L2.a, home3);
    folders.push({ uri: { fsPath: projB } });
    const lsMulti2 = await ext._labelShared('Twins across the folders', projA, L2.a, home3);
    const lsMulti3 = await ext._labelShared('T', projB, L.a, home3);
    folders.pop();
    const lsOwn = await ext._labelShared('Twins across the folders', projB, L2.b, home3);
    check('label: every folder of the window looked in, and the chat\'s own beside them - a twin in another folder of a multi-root window is shared',
        !lsMulti1 && lsMulti2 && lsMulti3 && lsOwn, lsMulti1 + ' ' + lsMulti2 + ' ' + lsMulti3 + ' ' + lsOwn);
    fs.unlinkSync(path.join(dir3b, L2.b + '.jsonl'));
    fs.unlinkSync(path.join(dir3, L2.a + '.jsonl'));
    // the cost: each folder's newest 200 only, and a time budget
    ext._titleCache.clear();
    let labelReads = 0;
    ext._readChat = (c) => { labelReads++; return realReadChat(c); };
    const lsCap = await ext._labelShared('no chat has this title', projA, G(0x9999), home2);
    check('label: each folder\'s newest 200 transcripts read, what the picker lists - never all 205', !lsCap && labelReads === 200, lsCap + ' ' + labelReads);
    ext._titleCache.clear();
    ext._readChat = async (c) => { await new Promise(r => setTimeout(r, 200)); return realReadChat(c); };
    ext._timing.labelBudget = 30;
    logged.length = 0;
    const lsLate = await ext._labelShared('only me', projA, L.solo, home3);
    const lateLog = logged.slice();
    ext._timing.labelBudget = 0;
    const lsNoLimit = await ext._labelShared('only me', projA, L.solo, home3);
    ext._readChat = realReadChat;
    check('label: not all read within labelBudget - shared, the safe side, and logged; 0 is no limit',
        lsLate === true && lateLog.some(l => l === 'label ' + L.solo.slice(0, 8) + ': its folders\' chats not all read in 30 ms - taken as shared') && lsNoLimit === false,
        lsLate + ' ' + lsNoLimit + ' | ' + lateLog.join(' | '));
    ext._titleCache.clear();
    // showTab: the request names its Claude home
    reset();
    tabs.push(claudeTab(L.a, 'T'), other);
    active.tab = other;
    const ls1 = await ext._showTab({ kind: 'ran', sessionId: L.a, title: 'T', cwd: projA, home: home3 });
    const ls1Calls = calls.join(), ls1Asked = asked.slice();
    reset();
    tabs.push(claudeTab(L.solo, 'only me'), other);
    active.tab = other;
    const ls2 = await ext._showTab({ kind: 'ran', sessionId: L.solo, title: 'only me', cwd: projA, home: home3 });
    check('label shared: a stale tab of that label is never closed - stale, and says so; a label of its own is closed and opened again',
        ls1 === 'stale' && !ls1Calls.includes('close:') && ls1Asked[0] === ext._texts.staleTab({ title: 'T' }) &&
        ls2 === 'reopened' && calls.includes('close:only me'), ls1 + ' ' + ls1Calls + ' / ' + ls2 + ' ' + calls.join());
    // openTab: this window's Claude home, the request naming none
    process.env.CLAUDE_CONFIG_DIR = home3;
    const heldOpen = (sid, title) => ext._openTab({ kind: 'open', sessionId: sid, title, cwd: projA, home: null, oldProcess: 'held', hostPids: [process.pid] });
    reset();
    tabs.push(claudeTab(L.a, 'T'));
    const lw1 = await heldOpen(L.a, 'T');
    const lw1Calls = calls.join(), lw1Asked = asked.slice();
    reset();
    tabs.push(claudeTab(L.solo, 'only me'));
    const lw2 = await heldOpen(L.solo, 'only me');
    check('label shared: an open held working here, its label\'s one tab maybe another chat\'s - counted as in no tab, and not opened; a label of its own is',
        lw1 === 'working' && lw1Calls === 'ask' && lw1Asked[0] === ext._texts.working({ title: 'T' }) && lw2 === 'revealed' && calls.join() === OPENED,
        lw1 + ' ' + lw1Calls + ' / ' + lw2 + ' ' + calls.join());
    // the picker's accept: what runs each chat from home3's own registry
    const reg3 = path.join(home3, 'sessions');
    const regSet = (entries) => {
        fs.rmSync(reg3, { recursive: true, force: true });
        fs.mkdirSync(reg3, { recursive: true });
        for (const [pid, x] of entries) {
            aliveSet.add(pid);
            fs.writeFileSync(path.join(reg3, pid + '.json'), JSON.stringify(Object.assign({ pid, cwd: projA, startedAt: pnow - HOUR, status: 'idle', entrypoint: 'claude-vscode' }, x)));
        }
    };
    const chats3 = await ext._listChats(home3, folders);
    const c3 = (sid) => chats3.find(c => c.sid === sid);
    reset();
    regSet([[999201, { sessionId: L.a, status: 'busy' }]]);
    tabs.push(claudeTab(L.a, 'T'));
    const la1 = await ext._acceptChat(c3(L.a));
    const la1Calls = calls.join(), la1Asked = asked.slice();
    reset();
    regSet([[999201, { sessionId: L.a }]]);
    tabs.push(claudeTab(L.a, 'T'));
    warnAnswer = 'Cancel';
    const la2 = await ext._acceptChat(c3(L.a));
    check('label shared: a pick working, or open, whose label\'s one tab may be another chat\'s - as with no tab here: refused, or asked',
        la1 === 'refused' && la1Calls === 'ask' && la1Asked[0] === ext._texts.pickWorking({ title: 'T' }) &&
        la2 === 'cancelled' && calls.join() === 'warn' && asked[0] === ext._texts.pickElsewhere({ title: 'T' }), la1 + ' ' + la1Calls + ' / ' + la2 + ' ' + calls.join());
    // the question sits a while, and the chat begins to work meanwhile
    reset();
    regSet([[999202, { sessionId: L.solo }]]);
    warnAnswer = 'Open here too';
    const plainWarn = stub.window.showWarningMessage;
    stub.window.showWarningMessage = async (m, ...b) => { const r = await plainWarn(m, ...b); regSet([[999202, { sessionId: L.solo, status: 'busy' }]]); return r; };
    const lq1 = await ext._acceptChat(c3(L.solo));
    stub.window.showWarningMessage = plainWarn;
    const lq1Calls = calls.join(), lq1Asked = asked.slice();
    // closed when picked, and a terminal takes it while the open waits in
    // the queue behind another show
    reset();
    regSet([]);
    let release;
    const blocker = ext._enqueue(() => new Promise(r => { release = r; }));
    const pq = ext._acceptChat(c3(L.solo));
    await tick();
    regSet([[999203, { sessionId: L.solo, entrypoint: 'cli' }]]);
    release();
    await blocker;
    const lq2 = await pq;
    check('pick: read again after the question, and again right before the open - working, or in a terminal, by then: refused as it would have been at once',
        lq1 === 'refused' && lq1Calls === 'warn,ask' && lq1Asked[1] === ext._texts.pickWorking({ title: 'only me' }) &&
        lq2 === 'refused' && calls.join() === 'ask' && asked[0] === ext._texts.pickTerminal({ title: 'only me' }) && !calls.includes(OPEN),
        lq1 + ' ' + lq1Calls + ' / ' + lq2 + ' ' + calls.join());
    reset();
    logged.length = 0;
    regSet([[999204, { sessionId: L.solo, kind: 'print', entrypoint: 'sdk-cli', status: 'busy' }]]);
    const lr1 = await ext._acceptChat(c3(L.solo));
    check('pick: a queued prompt going into it (a print-mode run) - refused as running, not as a terminal',
        lr1 === 'refused' && calls.join() === 'ask' && asked[0] === ext._texts.pickRunning({ title: 'only me' }) &&
        logged.includes('pick ' + L.solo.slice(0, 8) + ': running -> refused'), lr1 + ' ' + calls.join() + ' | ' + asked.join(' | '));
    process.env.CLAUDE_CONFIG_DIR = noHome;
    aliveSet.clear();
    fs.rmSync(pk, { recursive: true, force: true });

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
    // onReady: once the loader is in place, before the profile step, which
    // waits on a question nobody may ever answer
    const tool3 = path.join(sbx, 'tool3');
    const readyAt = [];
    let stepGo = null;
    su._profileStep = () => { readyAt.push('step'); return new Promise(r => { stepGo = r; }); };
    const onReady = () => readyAt.push('ready:' + fs.existsSync(path.join(tool3, su.LOADER)));
    const pending = su.setUp({ extensionPath: ext70, folder: tool3, log: () => { }, onReady });
    for (let i = 0; i < 50 && !stepGo; i++) await tick();
    const readyWhileAsking = readyAt.join();
    if (stepGo) stepGo();
    const rr1 = await pending;
    readyAt.length = 0;
    su._profileStep = async () => { readyAt.push('step'); };
    su._writeState(tool3, {});
    const rr2 = await su.setUp({ extensionPath: ext70, folder: tool3, log: () => { }, onReady });
    const readyThere = readyAt.join();
    readyAt.length = 0;
    const rr3 = await su.setUp({ extensionPath: ext70, folder: path.join(sbx, 'docs'), log: () => { }, onReady });
    check('setUp: onReady the moment its copy put the loader there, or at once where it was there, and before the profile step, which may never end; never for a folder it did not install into',
        readyWhileAsking === 'ready:true,step' && rr1 === 'install' && readyThere === 'ready:true,step' && rr2 === 'none' && rr3 === 'foreign' && readyAt.length === 0,
        readyWhileAsking + ' / ' + readyThere + ' / ' + rr1 + ' ' + rr2 + ' ' + rr3 + ' ' + readyAt.join());
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

    // the overlay started on activation, with the platform, the config, the
    // lock and PowerShell stood in for
    const ov = path.join(sbx, 'ov');
    fs.mkdirSync(path.join(ov, 'data'), { recursive: true });
    fs.writeFileSync(path.join(ov, su.LOADER), "$script:ChatVersion = '0.7.1'\r\n");
    const lockFile = path.join(ov, 'data', 'overlay.lock');
    check('the overlay lock: missing, or there and opened by nobody, is not held', !ext._lockHeld(lockFile) &&
        (fs.writeFileSync(lockFile, ''), !ext._lockHeld(lockFile)));
    fs.unlinkSync(lockFile);
    // the real thing, as the overlay holds it: opened with no sharing
    const winPs = ext._windowsPowerShell();
    if (process.platform === 'win32' && fs.existsSync(winPs)) {
        const heldFile = path.join(ov, 'data', 'held.lock');
        const child = require('child_process').spawn(winPs, ['-NoProfile', '-NonInteractive', '-Command',
            '$f = [IO.File]::Open(' + ext._psQuote(heldFile) + ", 'OpenOrCreate', 'ReadWrite', 'None'); [Console]::Out.WriteLine('held'); Start-Sleep -Seconds 2; $f.Close()"],
            { windowsHide: true });
        const exited = new Promise(r => child.on('exit', r));
        let giveUp;
        const opened = await new Promise(r => {
            let out = '';
            child.stdout.on('data', d => { out += d; if (/held/.test(out)) r(true); });
            exited.then(() => r(false));
            giveUp = setTimeout(() => r(false), 30000);
        });
        clearTimeout(giveUp);
        const whileHeld = opened && ext._lockHeld(heldFile);
        await exited;
        const afterExit = ext._lockHeld(heldFile);
        check('the overlay lock, held for real by a PowerShell: held while it is open, free once it lets go', whileHeld && !afterExit,
            opened + ' ' + whileHeld + ' ' + afterExit);
    } else {
        console.log('  skip  the overlay lock, held for real by a PowerShell: no Windows PowerShell here');
    }
    const realIo = Object.assign({}, ext._overlayIo);
    const realPs = { hosts: su._hosts, runPs: su._runPs };
    // which PowerShell: Windows PowerShell's own path, with no look on PATH
    const hostsAsked = [];
    su._hosts = () => { hostsAsked.push(1); return ['pwsh']; };
    ext._overlayIo.exists = () => true;
    const psWin = realIo.powershell('win32');
    ext._overlayIo.exists = () => false;
    const psNone = realIo.powershell('win32');
    const winAsked = hostsAsked.length;
    const psMac = realIo.powershell('darwin');
    ext._overlayIo.exists = realIo.exists;
    check('overlay: on Windows, Windows PowerShell by its own path - never setup\'s hosts(), whose where.exe can take 5 s; elsewhere pwsh as hosts() finds it',
        psWin === ext._windowsPowerShell() && /WindowsPowerShell[\\/]v1\.0[\\/]powershell\.exe$/.test(psWin) && psNone === null && winAsked === 0 && psMac === 'pwsh',
        psWin + ' ' + psNone + ' ' + winAsked + ' ' + psMac);
    const ovRan = [];
    let ovSays = 'started';
    su._runPs = async (exe, loader, cmd) => { ovRan.push(exe + ':' + cmd + ':' + loader); if (ovSays === 'throw') throw new Error('boom'); return { ok: true, stdout: 'WARNING: x\r\n' + ovSays + '\r\n' }; };
    let ovCfg = null;
    let ovHeld = false;
    const ioError = (code) => { const e = new Error(code); e.code = code; return e; };
    Object.assign(ext._overlayIo, {
        platform: () => 'win32',
        readFile: (f) => {
            if (ovCfg === null || f !== path.join(ov, 'data', 'config.json')) throw ioError('ENOENT');
            if (ovCfg === 'EACCES') throw ioError('EACCES');
            return ovCfg;
        },
        lockHeld: (f) => ovHeld && f === lockFile,
        powershell: () => 'PS'
    });
    cfgVals['chatManager.folder'] = ov;
    const ovStart = async (x) => {
        ovRan.length = 0;
        ovCfg = x.cfg === undefined ? null : x.cfg;
        ovHeld = !!x.held;
        ext._overlayIo.platform = () => x.platform || 'win32';
        return ext._startOverlay({});
    };
    const s1 = await ovStart({});
    check('overlay: on Windows with no config.json, started - Start-ChatOverlayAuto, once, through the loader, and its word taken',
        s1 === 'started' && ovRan.length === 1 && ovRan[0] === 'PS:Start-ChatOverlayAuto:' + path.join(ov, su.LOADER), s1 + ' ' + ovRan.join());
    const ctxOv = {};
    ovRan.length = 0;
    const s2a = await ext._startOverlay(ctxOv);
    const s2b = await ext._startOverlay(ctxOv);
    check('overlay: one start per activation', s2a === 'started' && s2b === 'already' && ovRan.length === 1, s2a + ' ' + s2b + ' ' + ovRan.join());
    const s3 = await ovStart({ cfg: '\uFEFF{"overlay":{"autoStart":false}}' });
    const s3b = await ovStart({ cfg: '{"overlay":{"autoStart":false}}', platform: 'darwin' });
    check('overlay: autoStart false - not started, BOM or not', s3 === 'off' && s3b === 'off' && ovRan.length === 0, s3 + ' ' + s3b);
    const s4 = await ovStart({ platform: 'darwin' });
    const s4b = await ovStart({ platform: 'darwin', cfg: '{"overlay":{"theme":"dark"}}' });
    const s4c = await ovStart({ platform: 'darwin', cfg: '{"overlay":{"autoStart":true}}' });
    check('overlay: off by default on a Mac, started there only when turned on', s4 === 'off' && s4b === 'off' && s4c === 'started' && ovRan.length === 1, s4 + ' ' + s4b + ' ' + s4c);
    const s5 = await ovStart({ platform: 'linux', cfg: '{"overlay":{"autoStart":true}}' });
    check('overlay: never where there is no panel to draw', s5 === 'no panel' && ovRan.length === 0, s5);
    const s6 = await ovStart({ held: true });
    check('overlay: its lock held - already running, no PowerShell', s6 === 'running' && ovRan.length === 0, s6);
    cfgVals['chatManager.folder'] = path.join(sbx, 'no-loader');
    const s7 = await ovStart({});
    cfgVals['chatManager.folder'] = ov;
    check('overlay: no loader in the tool folder - not started', s7 === 'no loader' && ovRan.length === 0, s7);
    ovSays = 'running';
    const s8 = await ovStart({});
    ovSays = 'nonsense';
    const s8b = await ovStart({});
    ovSays = 'throw';
    let s8c, ovThrew = false;
    try { s8c = await ovStart({}); } catch (e) { ovThrew = true; }
    ovSays = 'started';
    check('overlay: the script\'s word as it said it; no word, or PowerShell failing, is failed and never thrown',
        s8 === 'running' && s8b === 'failed' && s8c === 'failed' && !ovThrew, s8 + ' ' + s8b + ' ' + s8c);
    const s9 = await ovStart({ cfg: '{"overlay":{"autoStart":fal' });
    const s9b = await ovStart({ cfg: 'EACCES' });
    const s9c = await ovStart({ cfg: '{"theme":"dark"}' });
    check('overlay: a config.json that does not parse, or cannot be read, is off - it may be what turned it off; a missing key is the default',
        s9 === 'off' && s9b === 'off' && s9c === 'started' && ovRan.length === 1, s9 + ' ' + s9b + ' ' + s9c);
    const ctxL = {};
    ovRan.length = 0;
    ovCfg = null;
    cfgVals['chatManager.folder'] = path.join(sbx, 'no-loader');
    const s10a = await ext._startOverlay(ctxL);
    cfgVals['chatManager.folder'] = ov;
    const s10b = await ext._startOverlay(ctxL);
    const s10c = await ext._startOverlay(ctxL);
    check('overlay: a look before the loader is there does not use up the one start; a start that ran does',
        s10a === 'no loader' && s10b === 'started' && s10c === 'already' && ovRan.length === 1, s10a + ' ' + s10b + ' ' + s10c);

    // Chat Manager: Overlay: start by itself... - On or Off picked, set
    // through the loader as chatoverlay -AutoStart sets it; Off closes a
    // running overlay too. PowerShell stood in for, answering as the script
    // prints.
    const ovRunPs = su._runPs;
    const asRan = [], asSaid = [], asPicks = [];
    let asPick = 'on', asStop = 'overlay closed', asWorks = true;
    su._runPs = async (exe, loader, cmd) => {
        asRan.push(exe + ':' + cmd + ':' + loader);
        if (/^chatoverlay -AutoStart (on|off)\b/.test(cmd)) {
            const w = /-AutoStart (on|off)/.exec(cmd)[1];
            return { ok: true, stdout: asWorks ? '  start with every shell and VS Code window: ' + w + '\r\n' : 'Set-ChatOverlayConfig : Access to the path is denied.\r\n' };
        }
        if (/^chatoverlay -Stop\b/.test(cmd)) return { ok: true, stdout: '  ' + asStop + '\r\n' };
        return { ok: true, stdout: '' };
    };
    stub.window.showQuickPick = async (items, o) => { asPicks.push(o && o.placeHolder); return items.find(i => i.value === asPick); };
    stub.window.showInformationMessage = async (m) => { asSaid.push(m); };
    stub.window.showWarningMessage = async (m) => { asSaid.push('warn:' + m); };
    const asRun = async (x) => {
        asRan.length = 0; asSaid.length = 0; asPicks.length = 0;
        asPick = x.pick === undefined ? 'on' : x.pick; asStop = x.stop || 'overlay closed'; asWorks = x.works !== false;
        ext._overlayIo.platform = () => x.platform || 'win32';
        return ext._overlayAutoStart();
    };
    const ldr = path.join(ov, su.LOADER);
    logged.length = 0;
    const as1 = await asRun({ pick: 'on' });
    check('autostart: On - chatoverlay -AutoStart on through the tool folder\'s loader, nothing stopped, said, and logged',
        as1 === 'on' && asRan.length === 1 && asRan[0] === 'PS:chatoverlay -AutoStart on *>&1 | Out-String -Width 200:' + ldr &&
        asPicks[0] === ext._texts.autoStartAsk && asSaid.join() === ext._texts.autoStartOn && logged.includes('overlay autoStart: on'),
        as1 + ' ' + asRan.join(' / ') + ' | ' + asSaid.join(' | '));
    const as2 = await asRun({ pick: 'off' });
    const as2Ran = asRan.slice(), as2Said = asSaid.slice();
    const as3 = await asRun({ pick: 'off', stop: 'asked the overlay to close - it has not yet; data/logs/overlay.log may say why' });
    const as3Said = asSaid.slice();
    const as4 = await asRun({ pick: 'off', stop: 'the overlay is not running' });
    check('autostart: Off - set off, then chatoverlay -Stop closes a running overlay; what it did said',
        as2 === 'off, the overlay closed' && as2Ran.length === 2 && as2Ran[0] === 'PS:chatoverlay -AutoStart off *>&1 | Out-String -Width 200:' + ldr &&
        as2Ran[1] === 'PS:chatoverlay -Stop *>&1 | Out-String -Width 200:' + ldr && as2Said.join() === ext._texts.autoStartOff('closed') &&
        as3 === 'off, the overlay not yet' && as3Said.join() === ext._texts.autoStartOff('not yet') &&
        as4 === 'off, the overlay not running' && asSaid.join() === ext._texts.autoStartOff('not running') &&
        /, and was closed\.$/.test(ext._texts.autoStartOff('closed')) && /by itself\.$/.test(ext._texts.autoStartOff('not running')),
        as2 + ' ' + as3 + ' ' + as4 + ' | ' + as2Ran.join(' / ') + ' | ' + as2Said.join(' | '));
    const as5 = await asRun({ pick: 'off', works: false });
    check('autostart: the script not saying it took - failed, said, and no -Stop run', as5 === 'off - failed' && asRan.length === 1 &&
        asSaid.join() === 'warn:' + ext._texts.autoStartFailed, as5 + ' ' + asRan.join(' / ') + ' | ' + asSaid.join(' | '));
    const as6 = await asRun({ pick: null });
    const as6Ran = asRan.length, as6Said = asSaid.length;
    cfgVals['chatManager.folder'] = path.join(sbx, 'no-loader');
    const as7 = await asRun({ pick: 'off' });
    cfgVals['chatManager.folder'] = ov;
    const as7Picks = asPicks.length, as7Said = asSaid.join();
    const as8 = await asRun({ pick: 'off', platform: 'linux' });
    check('autostart: nothing picked does nothing; no loader in the tool folder - said, before any question; no panel to draw - said',
        as6 === 'nothing picked' && as6Ran === 0 && as6Said === 0 &&
        as7 === 'no loader in ' + path.join(sbx, 'no-loader') && as7Picks === 0 && asRan.length === 0 &&
        as7Said === 'warn:' + ext._texts.autoStartNoLoader(path.join(sbx, 'no-loader')) &&
        as8 === 'no panel' && asSaid.join() === ext._texts.autoStartNoPanel,
        as6 + ' / ' + as7 + ' / ' + as8 + ' ' + asSaid.join(' | '));
    const asPkg = (pkg.contributes.commands || []).find(c => c.command === 'chatManager.overlayAutoStart') || {};
    check('autostart: in the palette as Chat Manager: Overlay: start by itself...', asPkg.title === 'Overlay: start by itself...' && asPkg.category === 'Chat Manager',
        JSON.stringify(asPkg));
    su._runPs = ovRunPs;
    ext._overlayIo.platform = () => 'win32';
    delete cfgVals['chatManager.folder'];
    // the activations below start it through the same stand-ins: never a
    // real PowerShell from a test
    ext._overlayIo.platform = () => 'win32';
    ext._overlayIo.readFile = realIo.readFile;
    ext._overlayIo.lockHeld = () => false;
    ovRan.length = 0;

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
    const registered = [];
    stub.commands.registerCommand = (id) => { registered.push(id); return { dispose() { } }; };
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
    // the overlay waits on the setup's run, which takes a moment of its own
    for (let i = 0; i < 100 && !ovRan.length; i++) await tick();
    const ovFirst = ovRan.slice();
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
    check('and the palette has every command - the autostart switch among them',
        ['chatManager.installTerminal', 'chatManager.showLog', 'chatManager.openChat', 'chatManager.overlayAutoStart'].every(c => registered.includes(c)),
        registered.join());
    await settle();
    check('activation, the loader in place: the overlay started once, from the tool folder\'s loader - however often it runs',
        ovFirst.join() === 'PS:Start-ChatOverlayAuto:' + path.join(tool, su.LOADER) && ovRan.length === 1, ovFirst.join() + ' / ' + ovRan.join());

    // a setup that never settles - its profile question left unanswered -
    // holds up no overlay whose loader is in place
    // - onReady called as the real setUp calls it where the loader is in
    // place and nothing is to be copied: before its first await
    let setupDone = null;
    su.setUp = (o) => { o.onReady(); return new Promise(r => { setupDone = r; }); };
    ovRan.length = 0;
    ext.activate({ subscriptions: [], extensionPath: sbx, globalState: context.globalState });
    for (let i = 0; i < 50 && !ovRan.length; i++) await tick();
    const ovWhileAsking = ovRan.slice();
    const askingStill = !!setupDone;
    if (setupDone) setupDone('none');
    await settle();
    check('activation, the loader in place and the setup waiting on its question: the overlay started at once, and only once',
        askingStill && ovWhileAsking.join() === 'PS:Start-ChatOverlayAuto:' + path.join(tool, su.LOADER) && ovRan.length === 1,
        askingStill + ' ' + ovWhileAsking.join() + ' / ' + ovRan.join());
    // a first install: no loader until the setup's copy puts it there, and
    // then the profile question, which nobody answers
    const first = path.join(sbx, 'first');
    fs.mkdirSync(first, { recursive: true });
    cfgVals['chatManager.folder'] = first;
    const firstOrder = [];
    let firstGo = null;
    su.setUp = async (o) => {
        firstOrder.push('setup');
        await tick();
        fs.writeFileSync(path.join(o.folder, su.LOADER), "$script:ChatVersion = '0.7.1'\r\n");
        firstOrder.push('copied');
        o.onReady();
        await new Promise(r => { firstGo = r; });
        return 'install';
    };
    const ranPs = su._runPs;
    su._runPs = async (...a) => { firstOrder.push('overlay'); return ranPs(...a); };
    ovRan.length = 0;
    ext.activate({ subscriptions: [], extensionPath: sbx, globalState: context.globalState });
    for (let i = 0; i < 50 && !ovRan.length; i++) await tick();
    await settle();
    const firstAsking = !!firstGo;
    const firstRan = ovRan.join();
    if (firstGo) firstGo();
    await settle();
    su._runPs = ranPs;
    su.setUp = realSetUp;
    delete cfgVals['chatManager.folder'];
    check('activation on a first install: the overlay started once the setup put the loader there, from it, once - with the profile question still unanswered',
        firstAsking && firstOrder.join() === 'setup,copied,overlay' && firstRan === 'PS:Start-ChatOverlayAuto:' + path.join(first, su.LOADER) &&
        ovRan.length === 1, firstAsking + ' ' + firstOrder.join() + ' / ' + ovRan.join());
    // the real setUp from here, each run's promise kept to be waited on, and
    // the version of the loader the overlay was started from, as it was then
    const setupRuns = [];
    su.setUp = (o) => { const p = realSetUp(o); setupRuns.push(p); return p; };
    su._inGitCheckout = (f) => realGit(f, sbx);
    su._profileStep = async () => { };
    const startedFrom = [];
    su._runPs = async (exe, loader, cmd) => { startedFrom.push(su._readVersion(fs.readFileSync(loader, 'latin1'))); return ranPs(exe, loader, cmd); };
    const activateOn = async (folder) => {
        cfgVals['chatManager.folder'] = folder;
        setupRuns.length = 0; startedFrom.length = 0; ovRan.length = 0;
        ext.activate({ subscriptions: [], extensionPath: ext71, globalState: context.globalState });
        for (let i = 0; i < 50 && !setupRuns.length; i++) await tick();
        const r = await setupRuns[0];
        await settle();
        return r;
    };
    // an update: 0.6.0 in place, and this window's setup copying 0.7.1 over it
    const upd = path.join(sbx, 'upd');
    fs.mkdirSync(path.join(upd, 'data'), { recursive: true });
    fs.writeFileSync(path.join(upd, su.LOADER), "$script:ChatVersion = '0.6.0'\r\n");
    const updR = await activateOn(upd);
    check('activation during an update: the overlay not started from the old loader, only once the copy was whole - from the new one, once',
        updR === 'update' && startedFrom.join() === '0.7.1' && ovRan.join() === 'PS:Start-ChatOverlayAuto:' + path.join(upd, su.LOADER),
        updR + ' ' + startedFrom.join() + ' / ' + ovRan.join());
    // another window holds the install lock: it may be copying right now
    const els = path.join(sbx, 'els');
    fs.mkdirSync(path.join(els, 'data'), { recursive: true });
    fs.writeFileSync(path.join(els, su.LOADER), "$script:ChatVersion = '0.6.0'\r\n");
    fs.writeFileSync(path.join(els, 'data', 'install.lock'), '1');
    const elsR = await activateOn(els);
    check('activation while another window copies an update (elsewhere): the overlay not started at all - that window starts it',
        elsR === 'elsewhere' && ovRan.length === 0 && startedFrom.length === 0, elsR + ' ' + ovRan.join());
    su._runPs = ranPs;
    su._inGitCheckout = realGit;
    su._profileStep = realStep;
    // a run with an onReady that joins a setup already going - the palette's
    // - is called once that one's loader is ready, or at once where it was
    let joinGo = null;
    su.setUp = async (o) => { await tick(); o.onReady(); await new Promise(r => { joinGo = r; }); return 'none'; };
    const ctxJ = { extensionPath: sbx };
    const joined = [];
    const j1 = ext._runSetup(ctxJ, true);
    ext._runSetup(ctxJ, false, () => joined.push('waited'));
    const joinedEarly = joined.length;
    for (let i = 0; i < 50 && !joinGo; i++) await tick();
    ext._runSetup(ctxJ, false, () => joined.push('at once'));
    const joinedReady = joined.join();
    if (joinGo) joinGo();
    await j1;
    su.setUp = realSetUp;
    delete cfgVals['chatManager.folder'];
    check('setup: an onReady joining a run already going is called once that run\'s loader is ready - at once where it was ready already',
        joinedEarly === 0 && joinedReady === 'waited,at once', joinedEarly + ' ' + joinedReady);
    Object.assign(ext._overlayIo, realIo);
    su._hosts = realPs.hosts;
    su._runPs = realPs.runPs;
    fs.watchFile = realWatch;
    delete cfgVals['chatManagerReload.signalFile'];
    fs.rmSync(sbx, { recursive: true, force: true });

    try { fs.unlinkSync(file); } catch (e) { }
    try { fs.unlinkSync(ofile); } catch (e) { }
    delete process.env.CLAUDE_CONFIG_DIR;
    console.log('');
    console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
    process.exit(failed);
})();
