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
check('and never after a queued run', !ext._reloadsItself({ kind: 'ran' }, true));
check('the window whose folder it is', ext._isMine({ cwd: path.resolve('/work/projA') }));
check('a folder inside it', ext._isMine({ cwd: path.resolve('/work/projA/src') }));
check('not the sibling -Mobile folder', !ext._isMine({ cwd: path.resolve('/work/projA-Mobile') }));
const files = ext._signalFiles();
check('by default only this tool\'s own folder', files.length === 1 &&
    files[0].endsWith(path.join('VS-code-chat-manager', 'data', 'reload-request')));
console.log('');
console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
process.exit(failed);
