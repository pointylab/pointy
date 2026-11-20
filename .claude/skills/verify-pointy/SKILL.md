---
name: verify-pointy
description: Drive the Go (mygo) build of Pointy the way a user does and capture screenshots and logs as proof, on macOS against an isolated DSH with a mock model, and on Windows with Pointy alone. Use to verify any change to the desktop runtime, the pages (card, pill, notices, overlay), the plugin, or the language of Pointy's texts before calling it done.
---

# verify-pointy

Pointy is a menu bar app: shake the mouse over any window, point at something, and a card asks DSH about it. The Go runtime in `desktop/` draws the tray, hints and notifications and opens web pages from `build/app/` (card, pill, notice, overlay). The DSH plugin in `plugin/` relays between DSH and Pointy over `127.0.0.1:$POINTY_PORT`.

A run here starts its own Pointy, DSH and model on scratch homes and ports, and never touches Jesse's: his Pointy (47321), his DSH (3080) and his `~/.pointy` stay as they are. Everything up to "Windows" below is the macOS half; the Windows half has scripts of its own in `scripts/win/`.

## Safety rules

These were learned from runs that went wrong. Every script enforces them; keep them when you add one.

- **Never type into other apps.** A previous run's typing landed in Jesse's apps. Text goes into pages through `mygo-automation eval`, never `type` or `key`, never `osascript ... keystroke`. The one exception is `keys.sh`, for what only real input reaches (a recorded chord, a global shortcut): it presses a combination only while the frontmost app is the run's Pointy or TextEdit with the run's fixture document focused, after `guard`.
- **Wait until the user has been idle for at least 30 s, and abort otherwise.** `guard` in `scripts/env.sh` does this before every batch of mouse input. It waits up to 15 min (`VP_WAIT`), then gives up. If it gives up, report that and stop. Don't lower `VP_IDLE` to get a run through.
- **Wait while the screen is locked.** `guard` checks `CGSSessionScreenIsLocked` (`drive locked`). WebKit paints nothing while the screen is locked, so screenshots come out blank and page heights read 0.
- **Move the mouse only over windows the run created.** `mine X Y PID` checks the window owner before each click. The tray icon sits in a Control Center window on macOS 26, so `tray.sh` checks it through accessibility (`drive extras PID`) instead.
- **Space is a global shortcut while pointing.** If the user types during a pick, their Space confirms the pick, and their `[`/`]`/Esc reach Pointy instead of their app. Keep picks short and always run `guard` first.
- **Kill only processes the run started, by PID.** `down.sh` kills the PIDs `up.sh` recorded and their children. It never kills by name.

## Launch

Run once per session from the repo root. Needs Go, Node 24+, `dsh` on PATH (or `DSH=/path/to/dsh`), Accessibility and Screen Recording granted to the terminal, and ports 47397, 47398 and 3093 free.

```sh
eval "$(zsh .claude/skills/verify-pointy/scripts/up.sh zh-CN)"   # or "en", or "" to follow the system
```

`up.sh` does the following:

1. Makes `VP_RUN=/tmp/verify-pointy.XXXXXX`.
2. Builds the pages and the plugin (`node tools/build.ts`), the e2e build of Pointy, `desktop/cmd/drive` and `mygo-automation`, and packs the plugin with `npm pack ./plugin`.
3. Seeds a DSH workspace and a Pointy `settings.json` whose `locale` is the argument.
4. Installs the plugin into `DSH_HOME=$VP_RUN/dsh-home` with `HOME=$VP_RUN/home`.
5. Starts `tools/mock-llm.ts` on 47398, then Pointy on 47397 with `MYGO_AUTOMATION=$VP_RUN/a.sock`, then `dsh web --port 3093`.

It is ready when it prints `export VP_RUN=...`, which means the plugin connected (`dsh-ui` in `$VP_RUN/home/.pointy/error.log`). Pointy must be up before DSH. Otherwise the plugin starts the Pointy.app it carries.

Two traps `up.sh` already handles:

- `settings.json` gets `welcomedVersion` set to the repo's `package.json` version. Otherwise Pointy plays a full-screen intro, which covers every window for 8 s, and `mine` refuses to click.
- `VP_RUN` is the resolved path (`/private/tmp/...`). DSH refuses a workspace whose path is a symlink to the session's cwd.

Pointy reads `locale` from `settings.json` only at start. Jesse's Mac lists `en-US` first, so `""` shows English there. Pass `zh-CN` to check the Chinese UI.

Two switches, for runs that do not need DSH:

- `VP_SOLO=1` starts Pointy alone, without DSH and the mock model, so `dsh` need not be installed.
- `VP_REPO=<checkout>` builds Pointy, its pages and the plugin from another checkout, such as a pull request's worktree, with the tools of this one.

Screenshots of pages come from `shot_page` (`mygo-automation screenshot`), which needs no Screen Recording. Screenshots of the menu bar and the fixture come from `screencapture` and are skipped, with a line in `run.log`, where Screen Recording is not granted.

## Doctor

```sh
zsh .claude/skills/verify-pointy/scripts/doctor.sh
```

Read-only. It checks that the three processes live, that each port is held by this run's PID, that the plugin connected, that the automation socket answers, that the binary is newer than `go.mod`, and that the screen is unlocked. Run it first whenever anything looks off.

## Drive

Every script sources `scripts/env.sh`, which needs `VP_RUN` and gives `pa` (mygo-automation on this run's session), `js <window> <script>`, `win <page>`, `has <page>`, `drive`, `guard`, `mine` and `log`.

| Script | Does |
| --- | --- |
| `pick.sh <name>` | Opens `fixture.txt` as a new TextEdit document, shakes over it, clicks its first paragraph, and prints the card's window id. |
| `ask.sh <card> <name> <question> [keep]` | Asks in full mode through the card page and logs every progress line. With `keep`, closes the card mid-task and follows the pill to done. |
| `tray.sh <name> [item [subitem]]` | Opens the tray menu with a real click, logs its items with their check marks (read through AX) and the icon's tooltip, then chooses `item` > `subitem` or closes the menu. With one item that has a submenu, it logs the submenu and closes the menu. |
| `fixture.sh` | Opens `fixture.txt` as the run's own TextEdit document, brings it to the front and prints `pid x y w h` of its window. |
| `keys.sh <combo> [pointy\|fixture\|both]` | Presses a combination such as `Cmd+Alt+K` or `Esc` with real input, under the rule above. |

Page windows are `[page]` lines in `pa windows`, as `w3 [page] "Pointy" url=.../card/card.html`. Read page state with `js`, for example `js $(win card.html) "return document.getElementById('activity').innerText"`. Grab data comes from `js $cw "return window.mygo.call('Card.Init')"`.

Desktop input goes only through `$VP_RUN/bin/drive` (`move`, `shake`, `click`, `keys`, `chain`, `at`, `windows`, `extras`, `menus`, `idle`, `locked`). `drive` records its own input in `$VP_RUN/input-stamp`, so `drive idle` counts only the user's. Page input goes only through `eval`. The e2e build also binds `E2E.OpenGrab`, `E2E.ShowWelcome` and others (`desktop/automation_e2e.go`), which `pa eval --window <the e2e window> "mygo.call('E2E.ShowWelcome')"` reaches. They skip the user path, so use them only to set up a state the feature under test does not cover.

## Evidence

Everything goes to `$VP_RUN/evidence/`. `run.log` gets every logged step, `mock.jsonl` gets every model request, and each script adds its `<name>-*.png` screenshots. A proof:

- Takes the user path: a shake and a click, the card's own buttons, the tray menu. It does not use test hooks or internal setters.
- Records the action and the state it led to. For example, the progress lines the card showed, the pill before and after the task finished, and the menu before and after the language switch.
- Checks side effects next to what is visible: `settings.json` after a tray choice, `mock.jsonl` for what DSH sent the model, `error.log` for Pointy's own account.
- Mocks only the model. DSH, the plugin and Pointy are real.

## Cleanup

```sh
zsh .claude/skills/verify-pointy/scripts/down.sh
```

Kills the recorded PIDs and their children and closes the fixture documents the run opened. Deletes the scratch homes, the binaries and the socket. `$VP_RUN/evidence` stays. Run it after every run, failed ones too. `up.sh` and `up.ps1` delete run directories older than the last two, except one whose recorded process still lives, so evidence does not pile up.

## Windows

`scripts/win/` holds the Windows half: PowerShell 7 scripts and the Windows build of `desktop/cmd/drive`. It starts the e2e build of Pointy alone, without DSH or the mock model, so it covers what Pointy does by itself: the tray, the pointing overlay, notices and Settings. Run the scripts with `pwsh -NoProfile -File`. They need Go and Node on PATH, a desktop session that is unlocked, and port 47397 free.

```powershell
pwsh -NoProfile -File .claude/skills/verify-pointy/scripts/win/up.ps1 -Locale zh-CN   # -Repo <checkout> builds another checkout
pwsh -NoProfile -File .claude/skills/verify-pointy/scripts/win/doctor.ps1
pwsh -NoProfile -File .claude/skills/verify-pointy/scripts/win/down.ps1
```

`up.ps1` makes a run directory under `%TEMP%\verify-pointy\` and records it in `%TEMP%\verify-pointy\current`, so every later script, each in a fresh shell, finds the run without `VP_RUN`. It builds the pages, the e2e Pointy and `mygo-automation` from the checkout (`-Repo`, default this one) and `drive` from this checkout, so an older branch can be tested with the current tools. It then seeds `settings.json` as the macOS half does and starts Pointy with `POINTY_HOME`, `POINTY_PORT=47397`, `POINTY_ROOT` and `MYGO_AUTOMATION` set. `down.ps1` stops the recorded processes with their WebView2 children, copies Pointy's `settings.json` and logs into the evidence, and deletes the rest.

| Script | Does |
| --- | --- |
| `tray.ps1 <name> [item [subitem]]` | Opens the tray menu as a right click on the icon does, logs its items with their check marks, saves `<name>-tray.png`, then clicks `item` > `subitem`. With an item that has a submenu and no subitem, it opens the submenu, lists and shows it, and closes the menu. |
| `keys.ps1 <combo> [-To pointy\|fixture\|both]` | Presses a key combination such as `Ctrl+Alt+K` or `Esc` with real input, only while the foreground window is Pointy's (or the fixture's). |
| `fixture.ps1` | Opens the run's own window with `fixture.txt` in a text box, brings it to the front and prints its HWND and bounds. Notepad is no fixture on Windows 11: it opens files as tabs of a window the user may own. |
| `hold-hotkey.ps1 <mods> <vk> <ready file>` | Registers a global shortcut from another process, as an app that already holds it does. |

`env.ps1` gives the same helpers as `env.sh`: `Drive`, `Pa`, `Js`, `Win-Of`, `Has-Page`, `Shot-Page`, `Read-Settings`, `Guard`, `Mine`, `Wait-Until` and `Log`.

`drive` on Windows takes `move`, `shake`, `click`, `at`, `front`, `idle`, `locked`, `windows`, `displays` and `cursor` as on macOS, and adds `tray`, `menus`, `keys`, `type`, `focus`, `shot` and `shotwin` (usage at the top of `desktop/cmd/drive/main_windows.go`). Coordinates are physical pixels.

How the Windows half differs from the rules above:

- **Real keys are allowed, into the run's windows only.** WebView2 sees no `KeyboardEvent.code` from `eval`, so recording a shortcut needs real input. `drive keys` sends nothing unless the foreground window belongs to a PID it was given, and it sends scan codes, without which `code` is empty. A combination another app has registered goes to that app, never to the page.
- **`Guard` still waits for 30 s of idle.** `drive` records its own input in `$VP_RUN\input-stamp`, so `drive idle` does not count it as the user's.
- **The tray opens without a click on the icon.** Windows hides tray icons in the overflow by default, so `drive tray` posts the message the icon would send to Pointy's `MyGoApp` window. It then clicks the menu items with the real mouse and checks before each move that the point is a menu of Pointy's. A submenu opens on hover only after the cursor really moves, which `drive tray` does.
- Screenshots of pages come from `Pa screenshot`. Screenshots of native windows, menus and the overlay come from `drive shot` and `drive shotwin`.

### E2E tray entries

The e2e build binds `E2E.TrayMenu()`, which returns the tray's items as a tree with their check marks, and `E2E.ChooseTray(path)`, which acts as a click on the item at that label path, for example `["Language", "English"]`. It returns an error string when there is no such item. They reach the tray where a test cannot click it, such as a macOS runner without Accessibility, so they skip the user path. Keep a real click for every feature as well.

```powershell
$e = ((Pa windows | Where-Object { $_ -match '"e2e"' }) -split '\s+')[0]
Pa eval --window $e "return window.mygo.call('E2E.ChooseTray', ['Do Not Disturb'])"
```

### Scenarios

`scenarios/` holds whole runs that go from `up` to `down` in one command and print `PASS`/`FAIL` per check, for example:

```powershell
pwsh -NoProfile -File .claude/skills/verify-pointy/scenarios/hotkey.ps1 [-Repo <checkout>] [-Keep]
```

`-Keep` leaves the run up for a look; run `down.ps1` after.

The macOS half has the same scenario, run from Terminal or over SSH once the terminal (or `sshd-keygen-wrapper`) has Accessibility:

```sh
zsh .claude/skills/verify-pointy/scenarios/hotkey.sh [<checkout>] [keep]
```

## Feature map

`features/README.md` lists what to drive and how to tell that it worked. Before you call a change verified, cover every entry point the map lists for the feature you touched.
