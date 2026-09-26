// Checks the macOS overlay's JXA without a Mac: lifts the here-string out of
// src/overlay-mac.ps1, compiles it, and drives its pure part (CO) - the
// countdowns, the lines the panel draws, which commands it takes. Everything
// that touches Cocoa sits in run(), which only osascript on a Mac can run;
// TESTING.md has the checklist for that.
//
//     node tests/overlay-mac-check.js
//
// The exit code is the number of failed checks.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
let failed = 0, total = 0;
const check = (name, ok) => {
    total++;
    if (!ok) failed++;
    console.log((ok ? '  ok    ' : '  FAIL  ') + name);
};
const ps1 = fs.readFileSync(path.join(__dirname, '..', 'src', 'overlay-mac.ps1'), 'utf8');
const m = ps1.match(/\$script:ChatOverlayJxa = @'\r?\n([\s\S]*?)\r?\n'@/);
check('the JXA here-string is in the script', !!m);
const js = m ? m[1] : '';
check('it is pure ASCII', /^[\x00-\x7f]*$/.test(js));
// older JavaScriptCore reads neither
check('no ?. or ??', !/\?\.|\?\?/.test(js));
const box = { module: { exports: {} } };
let CO = null;
try {
    vm.createContext(box);
    new vm.Script(js, { filename: 'overlay-mac.js' }).runInContext(box);
    CO = box.module.exports;
} catch (e) {
    console.log('  ' + e.message);
}
check('it compiles, and run() is there for osascript', !!CO && typeof box.run === 'function');
if (CO) {
    const now = Date.UTC(2026, 8, 23, 12, 0, 0);
    check('a countdown under an hour', CO.until(now + 42 * 60000 + 5000, now) === '42m');
    check('and over one', CO.until(now + 90 * 60000 + 5000, now) === '1h 30m');
    check('a day or more is a weekday and time', /^[A-Z][a-z]{2} \d\d:\d\d$/.test(CO.until(now + 3 * 86400000, now)));
    check('a reset that passed', CO.until(now - 1000, now) === 'reset');
    check('the bar is ten cells', CO.bar(42).length === 10 && CO.bar(0).length === 10 && CO.bar(150).length === 10);
    check('a snapshot goes stale', CO.stale({ at: now - 30000 }, now, 20000) && !CO.stale({ at: now - 5000 }, now, 20000) && CO.stale(null, now, 20000));
    const row = (n, status) => ({ key: 's:' + n, status: status, rank: status === 'waiting' ? 0 : 3, project: 'p', title: 'chat ' + n, prompt: 'prompt ' + n, stateText: status });
    const snap = {
        at: now, counts: { waiting: 1, needsInput: 1 }, config: { maxRows: 2, prompts: true },
        header: {
            usage: [{ provider: 'Claude', stale: false, windows: [{ label: '5h', percent: 42, resetsAt: now + 3600000, severity: 'normal', limited: false }] }],
            notes: [{ text: 'next queued prompt: 17:10', tone: 'dim' }]
        },
        rows: [row(1, 'waiting'), row(2, 'idle'), row(3, 'queued')]
    };
    const flat = CO.lines(snap, now, true).map(l => l.map(r => r[0]).join(''));
    check('usage first, then the notes', flat[0].indexOf('Claude') === 0 && flat[0].indexOf('42%') > 0 && flat[1] === 'next queued prompt: 17:10');
    // lines (the default): one a provider, its time at the end; bars: a row a window
    const two = Object.assign({}, snap, { header: { notes: [], usage: [
        { provider: 'Claude', stale: false, status: '22:22', windows: [{ label: '5h', percent: 42, severity: 'normal' }, { label: 'week', percent: 80, severity: 'warning' }] },
        { provider: 'Copilot', stale: false, status: '22:20', windows: [{ label: 'chat', percent: 5, severity: 'normal' }] }] } });
    const asLines = CO.lines(two, now, true).map(l => l.map(r => r[0]).join(''));
    const asBars = CO.lines(Object.assign({}, two, { config: { maxRows: 2, prompts: true, usageView: 'bars' } }), now, true).map(l => l.map(r => r[0]).join(''));
    check('usage as a line a provider ending in its time, or as bars when set',
        asLines[0].indexOf('Claude') === 0 && asLines[0].indexOf('5h 42% \u00B7 week 80%') > 0 && /22:22$/.test(asLines[0]) &&
        asLines[1].indexOf('Copilot') === 0 && asBars[1].indexOf('week') > 0 && asBars[2].indexOf('Copilot') === 0 &&
        /22:22$/.test(asBars[0]) && !/22:22/.test(asBars[1]));
    check('rows up to maxRows, each with its prompt, then "+N more"',
        flat.indexOf('    prompt 1') > 0 && flat.some(l => l.indexOf('chat 2') >= 0) && !flat.some(l => l.indexOf('chat 3') >= 0) && flat.indexOf('+1 more') > 0);
    const termSnap = Object.assign({}, snap, { rows: [Object.assign(row(1, 'idle'), { where: 'terminal' }), Object.assign(row(2, 'idle'), { where: 'vscode' })] });
    const termFlat = CO.lines(termSnap, now, true).map(l => l.map(r => r[0]).join(''));
    check('a chat in a terminal marked >_, one in VS Code not',
        termFlat.some(l => l.indexOf('>_ chat 1') >= 0) && termFlat.some(l => l.indexOf('chat 2') >= 0) && !termFlat.some(l => l.indexOf('>_ chat 2') >= 0));
    const newSnap = Object.assign({}, snap, { rows: [Object.assign(row(1, 'idle'), { unread: true }), row(2, 'idle')] });
    const newFlat = CO.lines(newSnap, now, true).map(l => l.map(r => r[0]).join(''));
    // unread is Windows only: no chip here clears it, so no mark is drawn
    check('no unread mark on macOS: a row that says unread draws as any other',
        newFlat.some(l => l.indexOf('chat 1') >= 0) && !newFlat.some(l => l.indexOf('* chat') >= 0));
    check('prompts hidden when turned off', !CO.lines(Object.assign({}, snap, { config: { maxRows: 8, prompts: false } }), now, true).some(l => l[0][0].indexOf('    prompt') === 0));
    check('a hint only while unlocked', !flat.some(l => l.indexOf('unlocked') === 0) && CO.lines(snap, now, false).some(l => l[0][0].indexOf('unlocked') === 0));
    check('nothing open says so', CO.lines({ at: now, rows: [], header: { usage: [], notes: [] } }, now, true).some(l => l[0][0] === 'no chats open'));
    const seen = {};
    const cmds = [{ id: 1, verb: 'lock', at: 100 }, { id: 2, verb: 'hide', at: 300 }];
    const first = CO.applyCommands(cmds, 200, seen);
    check('only commands newer than the panel, and each once', first.join() === 'hide' && CO.applyCommands(cmds, 200, seen).length === 0);
    check('the menu bar item counts what needs you', CO.menuTitle(snap) === 'CQ 2' && CO.menuTitle({ counts: {} }) === 'CQ');
    check('theme: dark by default, light when set, system follows the OS',
        CO.themeOf(null, true) === 'dark' && CO.themeOf({ theme: 'light' }, true) === 'light' &&
        CO.themeOf({ theme: 'system' }, true) === 'dark' && CO.themeOf({ theme: 'system' }, false) === 'light' &&
        CO.themeOf({ theme: 'nonsense' }, false) === 'dark');
    check('each look has every colour the lines use',
        Object.keys(CO.colors).every(k => Array.isArray(CO.light[k])) && CO.color('busy', 'light') !== CO.color('busy', 'dark') &&
        CO.color('no-such', 'light') === CO.light.text);
    check('opacity held to 0.3-1, 0.94 when unset', CO.opacityOf({ opacity: 0.1 }) === 0.3 && CO.opacityOf({ opacity: 0.8 }) === 0.8 && CO.opacityOf(null) === 0.94);
}
console.log('');
console.log('  ' + (total - failed) + ' passed, ' + failed + ' failed');
process.exit(failed);
