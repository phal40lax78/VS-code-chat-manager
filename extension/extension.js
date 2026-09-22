const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const os = require('os');

const SEEN_KEY = 'chatManagerReload.lastSeenId';

// VS-code-chat-manager writes data/reload-request after chatrm deletes a chat,
// and after chatq runs a queued prompt into a chat this window still holds.
// Everything this extension exists for is the one thing no outside process can
// do: run reloadWindow.
function signalFiles() {
    const set = vscode.workspace.getConfiguration('chatManagerReload').get('signalFile');
    if (set && String(set).trim()) return [String(set).trim()];
    const tools = path.join(os.homedir(), 'Tools');
    // the old chatrm folder too: a shell still running chatrm writes there
    return [
        path.join(tools, 'VS-code-chat-manager', 'data', 'reload-request'),
        path.join(tools, 'chatrm', 'data', 'reload-request')
    ];
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

// What to say, by what happened. A request written before 'kind' existed is a
// delete - that was the only thing that wrote one.
function message(req) {
    const what = req.title ? '"' + req.title + '"' : 'a chat';
    if (req.kind === 'ran') {
        return 'A queued prompt ran in ' + what + ', which this window still has open. Reload to show it?';
    }
    if (req.kind === 'archived') return 'Archived ' + what + '. Reload to refresh the chat list?';
    return 'Deleted ' + what + '. Reload to refresh the chat list?';
}

async function offer(context, req) {
    // Never automatic for a queued run: it can finish at 3 a.m. with another
    // chat in this window mid-answer, and a reload would lose that answer.
    const auto = req.kind !== 'ran' &&
        vscode.workspace.getConfiguration('chatManagerReload').get('autoReload');

    // Marked seen BEFORE reloading: the file is still on disk afterwards, so
    // without this the same request would prompt again on every reload.
    await context.globalState.update(SEEN_KEY, req.id);

    if (auto) {
        vscode.commands.executeCommand('workbench.action.reloadWindow');
        return;
    }
    const pick = await vscode.window.showInformationMessage(message(req), 'Reload', 'Not now');
    if (pick === 'Reload') {
        vscode.commands.executeCommand('workbench.action.reloadWindow');
    }
}

function check(context, file, onlyRecent) {
    const req = readRequest(file);
    if (!req || !req.id) return;
    if (context.globalState.get(SEEN_KEY) === req.id) return;
    if (!isMine(req)) return;
    if (onlyRecent) {
        // at startup, ignore a request left over from days ago - the list it
        // was about was rebuilt from disk when this window opened
        const at = Date.parse(req.at || '');
        if (!at || Date.now() - at > 10 * 60 * 1000) return;
    }
    offer(context, req);
}

function activate(context) {
    for (const file of signalFiles()) {
        check(context, file, true);
        // watchFile polls. createFileSystemWatcher only reaches inside workspace
        // folders, and this path is deliberately outside every one of them.
        fs.watchFile(file, { interval: 2000 }, () => check(context, file, false));
        context.subscriptions.push({ dispose: () => fs.unwatchFile(file) });
    }
}

function deactivate() { }

// The underscored ones are exported so the path matching, the BOM strip and the
// wording can be driven from a test with the vscode module stubbed out - all of
// them decide whether, or how, the prompt appears, and fail silently when wrong.
module.exports = {
    activate, deactivate,
    _readRequest: readRequest, _isMine: isMine, _signalFiles: signalFiles, _message: message
};
