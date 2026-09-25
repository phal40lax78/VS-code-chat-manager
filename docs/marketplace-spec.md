# Spec: one extension on the VS Code Marketplace

Status: accepted 2026-09-25, all three decisions as proposed; in progress.
Written against 0.6.0.

## Goal

Install and update the whole tool from the VS Code Marketplace: one
extension that carries both halves - the VS Code half that
[extension/extension.js](../extension/extension.js) is today, and the
PowerShell scripts - and sets the terminal half up from what it carries.
The one-line installer stays for anyone who wants the terminal side only.

## Why

The two halves are installed separately today, and nothing keeps them in
step. On 2026-09-25 the script was 0.6.0 while every window still ran the
2.0.0 extension, which ignores `data/open-request` - so the overlay's open
chip did nothing, and the owner did not know an extension was installed at
all: an earlier session had copied it into `~/.vscode/extensions/` by hand.
Updating the script meant `git pull` or the one-liner; updating the
extension meant copying two files and reloading every window.

## What does not change

- **The PowerShell tool stays the product.** The watcher runs with VS Code
  closed, the overlay floats over every app, and Tab completion hooks
  PSReadLine in a terminal - none of that can live inside an extension, so
  nothing is rewritten.
- **`data/` stays in the tool folder**, `~/Tools/VS-code-chat-manager` by
  default. Never in the extension's own folder, which VS Code deletes on
  every update, and never in `globalStorage`, which is AppData.
- **The one-liner** ([install.ps1](../install.ps1)) and a git checkout keep
  working, beside the extension or without it.
- **The extension never downloads code.** It installs only what is inside
  its own package.

## What ships

One VSIX, built from this repo:

```
extension.js, package.json, README.md, CHANGELOG.md, LICENSE, icon.png
payload/VS-code-chat-manager.ps1
payload/src/*.ps1
```

- `extension/build.js` (node, no dependencies) copies the loader and
  `src/` into `extension/payload/`, and `CHANGELOG.md` and `LICENSE` beside
  them, then `vsce package` packs it. `.vscodeignore` keeps the rest out.
  `payload/` is a build product and is git-ignored.
- **One version for both halves.** The extension's version is the tool's:
  `package.json` and the loader's `$script:ChatVersion` are bumped in the
  same commit, and the build fails when they differ. The first Marketplace
  release is **0.7.0**.
- **A new extension ID** (see decisions), because the old one, `chat-manager-reload`,
  names only a part, and its 2.x version numbers would be ahead of the tool's.

## Setting up the terminal half

On activation, in every window, the extension decides what to do with the
tool folder (`chatManager.folder`, default `~/Tools/VS-code-chat-manager`).
The decision is a pure function, so it can be tested:

| on disk | what the extension does |
|---|---|
| no folder, or no loader in it | **install**: copy the payload in, then ask about the profile line |
| loader older than the payload | **update**: copy the payload over it, then run `chatinstall` |
| loader the same version | nothing |
| loader newer than the payload | nothing; log it (the one-liner or a pull got there first) |
| a `.git` folder in it | **never write.** If the versions differ, say so once per version pair: "the scripts are 0.6.0, the extension 0.7.0 - pull" |

- **The loader's version** is read from the file on disk, not from
  `data/version.txt`: that file records what `chatinstall` last registered,
  not what is on disk.
- **One window acts.** Every window activates the extension, so the one
  that creates `data/install.lock` first (exclusive create) does the work;
  a lock older than 2 minutes counts as abandoned. The others see equal
  versions afterwards and do nothing.
- **Copy order is the installer's:** every `src/` part first, then the
  loader, each written beside its target and renamed over it. A run stopped
  half-way then leaves a whole old loader, or new parts under an old loader
  that lists what it loads, and the loader names any part it cannot find.
- **After an update, `chatinstall` runs** in a hidden `powershell.exe
  -NoProfile -ExecutionPolicy Bypass`, and in `pwsh` too when it exists,
  since each keeps its own `$PROFILE`. It already hands the watcher over
  after its current job and restarts the overlay on the new copy.
  Terminals that are already open keep the old commands until they are
  reopened; the update notification says so.

## Consent and safety

- **The profile line is asked for, once.** A fresh install shows: "Add
  chatrm, chatq and chatoverlay to your PowerShell profile? *Add* / *Not
  now* / *Never*". Only *Add* runs `chatinstall`, which backs the profile up
  first, as it does today. The answer is kept in `data/extension.json`,
  not in VS Code's state, so it lives beside the rest.
  **Chat Manager: Install terminal commands** in the command palette asks
  again at any time.
- **The execution policy.** On Windows the default policy for a user is
  often `Restricted`, and then the profile line cannot run at all. After
  *Add*, the extension reads the effective policy. If it is `Restricted` or
  `AllSigned`, it offers "Allow local scripts for your user
  (RemoteSigned)", and only a click runs `Set-ExecutionPolicy -Scope
  CurrentUser RemoteSigned`.
- **Nothing runs without being shown.** Every process the extension starts
  - copies, `chatinstall`, the policy change - is logged to its output
  channel with the command line, in the log folder VS Code already keeps.
- **Uninstalling the extension** leaves the tool folder and the profile
  line alone; the terminal commands keep working without the extension, as
  today. No `vscode:uninstall` hook. `chatuninstall -All` removes the rest,
  and the listing says so.

## The old extension

- On first activation the new extension looks for
  `phal40lax78.chat-manager-reload`. While it is installed, the new one
  **handles no request at all** - both would act on the same
  `reload-request`, and a window would reload twice - and offers
  "Uninstall the old Chat Manager reload extension", which runs VS Code's
  `workbench.extensions.uninstallExtension` (spike M3).
- **Settings move** from `chatManagerReload.*` to `chatManager.*`. For one
  release the old names are read when the new ones are unset.
  `signalFile` gives way to `chatManager.folder`: `data/` is always in the
  tool folder.

## Where it runs

- `"extensionKind": ["ui"]`: in a Remote-SSH, WSL or container window it
  runs on the local machine, where the tool and the chats are.
- `capabilities.untrustedWorkspaces: { supported: true }`: it runs no
  workspace code. `virtualWorkspaces: true`.
- **One universal package**, no `--target`: the payload is text.
- **Windows first.** On macOS and Linux it sets the terminal half up only
  when `pwsh` is found, and otherwise does the VS Code half alone, as the
  extension does today.

## The Marketplace listing

- **Its own `extension/README.md`.** vsce refuses SVG images in a README or
  CHANGELOG, except badges from trusted providers, and the repo README's
  demo frames are SVGs. The listing uses the overlay PNG
  (`docs/demo-overlay.png`) and PNG renders of the others, and links to
  the repo README for the rest. `docs/make-demo.ps1` gains a PNG output.
- `icon.png`, 256x256 (at least 128x128; never an SVG).
- `repository`, `homepage`, `bugs`, `license: MIT`, and
  `engines.vscode` kept at `^1.75.0`.
- The listing's CHANGELOG is the repo's, copied in by the build.

## Publishing

1. **Publisher.** Create `phal40lax78` at marketplace.visualstudio.com/manage
   with the owner's Microsoft account. The ID is permanent.
2. **First release: by hand.** Build the VSIX, then upload it on the manage
   page. That needs no token, and it proves the listing before any
   automation exists.
3. **Later releases: from CI.** Azure DevOps retires global PATs on
   **2026-12-01**, so no PAT: `.github/workflows/publish.yml`, on a `v*`
   tag:
   - runs the tests;
   - builds the VSIX;
   - checks that the tag, `package.json` and `$script:ChatVersion` agree;
   - signs in with `azure/login` using GitHub OIDC;
   - runs `vsce publish --azure-credential` (vsce 2.26.1 or later);
   - attaches the VSIX to the GitHub release.
4. **The identity for CI:** a Microsoft Entra app registration with a
   federated credential for this repo's `marketplace` environment, and no
   secret. It needs no Azure subscription (`allow-no-subscriptions`). Its
   Visual Studio profile ID is added as a member of the publisher. The docs
   say the role is **Contributor**, and one working setup used **Creator**
   (spike M1). If the publisher's page offers trusted publishing (vsce
   `--oidc`), use that instead, since it needs no Entra app at all.

## Tests

- **extension-check.js**, new pure checks:
  - the sync decision for every row of the table, the git guard, lock
    taken, held and abandoned;
  - the loader's version read from its text;
  - the settings fallback;
  - requests ignored while the old extension is installed.
- **A packaging check in CI:** build, `vsce package`, then:
  - the VSIX lists the loader and every part the loader names;
  - the versions agree;
  - every payload `.ps1` is ASCII;
  - neither README nor CHANGELOG has an SVG.
- **By hand (S32)**, in Windows Sandbox or a spare Windows user:
  1. A clean install from the Marketplace: the profile question, the policy
     question from `Restricted`, and then `chat` in a new terminal.
  2. An update from 0.7.0 to 0.7.1: the files replaced, the watcher handed
     over after its job, the overlay restarted, and one window acting,
     with three open.
  3. A git checkout left alone, and the version-skew message.
  4. The old extension found, requests held back, and removed on the
     click.
  5. A Remote-SSH window: it runs locally.

## Docs

- **README:** install from the Marketplace first, the one-liner second, and
  "update: VS Code does it" in place of "run the one-liner again".
- **CHANGELOG 0.7.0:** the move, the new ID and settings, the old extension
  retired.
- **TESTING:** the new checks, S32, and the spikes below.

## Spikes before building

- **M1: publishing works.** An Entra app with no Azure subscription, as a
  personal Microsoft account's app, made a member of the publisher, then
  `vsce publish --azure-credential` from a GitHub run. Or trusted
  publishing, if the publisher's page offers it.
- **M2: the name.** Both `name` and `displayName` must be unique on the
  Marketplace. Check the chosen ones are free before anything else is
  built around them.
- **M3: removing the old extension.** Does
  `workbench.extensions.uninstallExtension` with an ID take a copied-in,
  unpublished extension away, and does it need a reload?
- **M4: updates.** After a Marketplace update, does VS Code 1.108 restart
  the extension in open windows by itself, or wait for the owner to click
  *Restart Extensions*? The sync runs on activation either way; this only
  decides how soon.

## Decisions (taken 2026-09-25)

1. **The name:** ID `phal40lax78.vs-code-chat-manager` (the repo's name),
   display name "VS Code Chat Manager". Both are subject to M2.
2. **The profile line:** asked once, as above, rather than only through
   the command.
3. **Publishing:** by hand for 0.7.0, and from CI once M1 passes.

## Order of work

1. **The extension and its tests:** the payload build, the sync decision
   and lock, consent, the policy, the old-extension guard, settings and
   `extensionKind`.
2. **The listing:** its README, PNG frames, the icon, and the packaging
   check in CI.
3. **Spikes M2 and M3**, then 0.7.0 packaged and uploaded by hand.
4. **Spike M1**, then `publish.yml`.
