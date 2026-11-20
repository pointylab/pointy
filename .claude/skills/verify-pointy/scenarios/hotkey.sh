#!/bin/zsh
# usage: hotkey.sh [checkout] [keep]
# The keyboard shortcut (#39) on macOS, from a fresh run to down.sh: choose
# a preset in the tray, start pointing with it over the run's own document,
# record ⌘⌥K in the recorder, and start pointing with that. Prints PASS/FAIL
# per check; evidence stays in $VP_RUN/evidence.
set -u
S=${0:A:h:h}/scripts
export VP_REPO=${1:-${VP_REPO:-}} VP_SOLO=1
keep=${2:-}
src=${${VP_REPO:-${0:A:h:h:h:h:h}}:A}
python3 -c 'import json,sys; sys.exit(0 if "hotkey" in json.load(open(sys.argv[1]))["tray"] else 1)' $src/locales/zh-CN.json \
  || { print "SKIP: this checkout has no keyboard shortcut (no tray.hotkey text)"; exit 0; }
up=$(zsh $S/up.sh zh-CN) || exit 1
export VP_RUN=${${up##*export VP_RUN=}%%$'\n'*}
source $S/env.sh

failed=0
finish() {
  local rc=$?
  (( rc && !failed )) && failed=1  # a die in a helper stopped the scenario
  [ -n "$keep" ] || zsh $S/down.sh > /dev/null 2>&1
  log "$(( failed )) check(s) failed; evidence in $EV"
}
trap finish EXIT
# expect <what> <command...>: logs PASS or FAIL as the command succeeds.
expect() { local what=$1; shift; if "$@" > /dev/null 2>&1; then log "PASS $what"; else log "FAIL $what"; (( failed++ )); fi }
# step <script> <args...>: runs one of the scripts; a failed one fails the check after it.
step() { zsh $S/$1 "${@:2}" || log "($1 ${@:2} failed)"; }
until_true() { local end=$(( SECONDS + $1 )); shift; while (( SECONDS < end )); do "$@" > /dev/null 2>&1 && return 0; sleep 0.2; done; return 1; }
logged() { tail -${2:-30} "$EV/run.log" | grep -qF -- "$1"; }
keys_shown() { [ "$(js $(win notice.html) "return document.getElementById('keys').textContent")" = "$1" ]; }
no_overlay() { ! has overlay.html; }
no_notice() { ! has notice.html; }
is_setting() { [ "$(setting $1)" = "$2" ]; }
front_is() { [ "$(drive front)" = "$1" ]; }

t() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tray"][sys.argv[2]])' "$SRC/locales/zh-CN.json" $1; }
HOTKEY=$(t hotkey) CUSTOM=$(t hotkeyCustom)
pointy=$(pid pointy)

# 1. A preset from the tray is saved and bound.
step tray.sh preset "$HOTKEY" ⌘⌥P
expect "the preset is saved in settings.json" until_true 3 is_setting hotkey CmdOrCtrl+Alt+P
step tray.sh preset-checked "$HOTKEY"
expect "the tray checks ⌘⌥P" logged "[x] ⌘⌥P"

# 2. The shortcut starts pointing over the run's own document; Esc ends it.
read te wx wy ww wh <<< "$(zsh $S/fixture.sh)"
cx=$(( wx + ww / 2 )) cy=$(( wy + wh / 2 ))
guard; mine $cx $cy $te; drive move $cx $cy
step keys.sh Cmd+Alt+P fixture
expect "⌘⌥P starts pointing" until_true 5 has overlay.html
sleep 0.6
log "pointing at: $(js $(win overlay.html) "return document.getElementById('what')?.textContent")"
shot $wx $wy $ww $wh preset-pointing
step keys.sh Esc both
expect "Esc ends pointing" until_true 5 no_overlay

# 3. Custom…: the recorder takes focus, records ⌘⌥K, Return saves it.
step tray.sh custom "$HOTKEY" "$CUSTOM"
expect "the recorder opens" until_true 5 has notice.html
sleep 0.5
expect "the recorder is the frontmost app" front_is $pointy
shot_page notice.html custom-open
step keys.sh Cmd+Alt+K pointy
sleep 0.3
log "recorder shows: $(js $(win notice.html) "return document.getElementById('keys').textContent")"
expect "the recorder shows ⌘⌥K" keys_shown ⌘⌥K
shot_page notice.html custom-recorded
step keys.sh Return pointy
expect "Return saves and closes the recorder" until_true 5 no_notice
expect "the shortcut is saved as Cmd+Alt+K" until_true 3 is_setting hotkey Cmd+Alt+K
expect "Pointy logs no registration error" sh -c "! grep -q 'cannot register' '$VP_RUN/home/.pointy/error.log'"
step tray.sh custom-checked "$HOTKEY"
expect "the tray lists and checks ⌘⌥K" logged "[x] ⌘⌥K"

# 4. ⌘⌥K starts pointing too.
zsh $S/fixture.sh > /dev/null
guard; mine $cx $cy $te; drive move $cx $cy
step keys.sh Cmd+Alt+K fixture
expect "⌘⌥K starts pointing" until_true 5 has overlay.html
sleep 0.6
shot $wx $wy $ww $wh custom-pointing
step keys.sh Esc both
until_true 5 no_overlay
exit $(( failed > 0 ))
