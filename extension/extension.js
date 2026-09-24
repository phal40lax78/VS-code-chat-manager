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
    // only this tool's own folder: standalone chatrm is retired, so nothing
    // writes to ~/Tools/chatrm any more
    return [path.join(os.homedir(), 'Tools', 'VS-code-chat-manager', 'data', 'reload-request')];
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

// The script judges one folder's chats, the job's own. A window whose only
// folder is that one holds nothing it did not judge; a multi-root window, or
// one opened on a parent folder, may hold a chat elsewhere mid-answer - so
// only the first may reload without asking.
function isExactlyMine(req) {
    const folders = vscode.workspace.workspaceFolders || [];
    if (!req.cwd || folders.length !== 1) return false;
    return path.resolve(req.cwd).toLowerCase() === path.resolve(folders[0].uri.fsPath).toLowerCase();
}

// What to say, by what happened. A request written before 'kind' existed is a
// delete - that was the only thing that wrote one. 'busy' is the script's
// judgement, made as it wrote the request, that a chat in this workspace was
// still working - a turn in flight, a permission prompt, or a workflow or
// background agent that has not reported back. A reload now would cut it off.
function message(req) {
    const what = req.title ? '"' + req.title + '"' : 'a chat';
    if (req.kind === 'ran') {
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

// A queued run can finish at 3 a.m. with another chat in this window
// mid-answer, and a reload would lose that answer - or while you are typing
// in it. So it reloads by itself only on the script's word, given as the run
// ended, that nobody had used the PC for a while (away) and no other chat in
// the folder was working (busy false), and only in a window that is exactly
// that folder. Unjudged is a no. The new chat a queued run started is never
// reloaded for by itself: the script judges neither for it. A delete reloads
// by itself only with autoReload, and never while a chat works.
function reloadsItself(req, autoReload, afterRun, exact) {
    if (req.kind === 'ran') return afterRun !== false && req.away === true && req.busy === false && exact === true;
    if (req.kind === 'new') return false;
    return req.busy !== true && !!autoReload;
}

async function offer(context, req) {
    const cfg = vscode.workspace.getConfiguration('chatManagerReload');
    const auto = reloadsItself(req, cfg.get('autoReload'), cfg.get('autoReloadAfterRun'), isExactlyMine(req));

    // Marked seen BEFORE reloading: the file is still on disk afterwards, so
    // without this the same request would prompt again on every reload.
    await context.globalState.update(SEEN_KEY, req.id);

    if (auto) {
        vscode.commands.executeCommand('workbench.action.reloadWindow');
        return;
    }
    const busy = req.busy === true;
    const go = busy ? 'Reload anyway' : 'Reload';
    const pick = busy
        ? await vscode.window.showWarningMessage(message(req), go, 'Not now')
        : await vscode.window.showInformationMessage(message(req), go, 'Not now');
    if (pick === go) {
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
        // a window just opened has read every chat from disk, the run - or
        // the new chat it started - included, so it has nothing to reload
        // for; and a run's away verdict, given as it ended, is stale with
        // someone opening windows
        if (req.kind === 'ran' || req.kind === 'new') { context.globalState.update(SEEN_KEY, req.id); return; }
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

// The underscored ones are exported so the path matching, the BOM strip, the
// wording and the auto-reload rule can be driven from a test with the vscode
// module stubbed out - all of them decide whether, or how, the prompt appears,
// and fail silently when wrong.
module.exports = {
    activate, deactivate,
    _readRequest: readRequest, _isMine: isMine, _signalFiles: signalFiles, _message: message,
    _reloadsItself: reloadsItself, _isExactlyMine: isExactlyMine, _check: check
};
