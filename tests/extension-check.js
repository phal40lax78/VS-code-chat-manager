// Checks extension/extension.js's pure parts with the vscode module stubbed
// out: which window a request is for, what it says, when it reloads without
// asking, which files it watches. Each decides whether - or how - the reload
// prompt appears, and each fails silently when wrong.
//
//     node tests/extension-check.js
// or, with no node on the machine, VS Code's own Electron:
//     $env:ELECTRON_RUN_AS_NODE = 1; & "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" tests/extension-check.js
//
// The exit code is the number of failed checks.
const Module = require('module');
const path = require('path');
const folders = [{ uri: { fsPath: path.resolve('/work/projA') } }];
const stub = {
    workspace: { getConfiguration: () => ({ get: () => '' }), workspaceFolders: folders },
    window: {}, commands: {}
};
const load = Module._load;
Module._load = function (req) {
    if (req === 'vscode') return stub;
    return load.apply(this, arguments);
};
const ext = require(path.join(__dirname, '..', 'extension', 'extension.js'));
let failed = 0, total = 0;
const check = (name, ok) => {
    total++;
    if (!ok) failed++;
    console.log((ok ? '  ok    ' : '  FAIL  ') + name);
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
    try { fs.unlinkSync(file); } catch (e) { }
    console.log('');
    console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
    process.exit(failed);
})();
