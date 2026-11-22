#!/bin/zsh
# usage: dnd.sh [checkout] [keep]
# Do Not Disturb on macOS, from a fresh run to down.sh: toggle DND on in the
# menu bar, verify tooltip, shaking and a global shortcut are suppressed while
# it is on, then turn DND off and verify shaking starts pointing again.
# Prints PASS/FAIL per check; evidence stays in $VP_RUN/evidence.
set -u
S=${0:A:h:h}/scripts
export VP_REPO=${1:-${VP_REPO:-}} VP_SOLO=1
keep=${2:-}
src=${${VP_REPO:-${0:A:h:h:h:h:h}}:A}
python3 -c 'import json,sys; sys.exit(0 if "dnd" in json.load(open(sys.argv[1]))["tray"] else 1)' "$src/locales/zh-CN.json" \
  || { print "SKIP: this checkout has no Do Not Disturb item"; exit 0; }
up=$(zsh $S/up.sh zh-CN) || exit 1
export VP_RUN=${${up##*export VP_RUN=}%%$'\n'*}
source $S/env.sh

failed=0
finish() {
  local rc=$?
  (( rc && !failed )) && failed=1
  [ -n "$keep" ] || zsh $S/down.sh > /dev/null 2>&1
  log "$(( failed )) check(s) failed; evidence in $EV"
}
trap finish EXIT
expect() { local what=$1; shift; if "$@" > /dev/null 2>&1; then log "PASS $what"; else log "FAIL $what"; (( failed++ )); fi }
step() { zsh $S/$1 "${@:2}" || log "($1 ${@:2} failed)"; }
until_true() { local end=$(( SECONDS + $1 )); shift; while (( SECONDS < end )); do "$@" > /dev/null 2>&1 && return 0; sleep 0.2; done; return 1; }
logged() { tail -${2:-25} "$EV/run.log" | grep -qF -- "$1"; }
no_overlay() { ! has overlay.html; }
is_setting() { [ "$(setting $1)" = "$2" ]; }

t() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tray"].get(sys.argv[2], ""))' "$SRC/locales/zh-CN.json" "$1"; }
DND=$(t dnd)
DND_ON=$(t dndOn)
HOTKEY=$(t hotkey)

# 1. DND starts off; clicking it turns it on and updates tooltip + settings.
step tray.sh before
expect "DND is unchecked initially" logged "[ ] $DND"
expect "settings.json starts with dnd=False" is_setting dnd False
step tray.sh on "$DND"
expect "dnd is saved as True in settings.json" until_true 3 is_setting dnd True
step tray.sh on-checked
expect "the menu checks DND" logged "[x] $DND"
expect "the tooltip says DND is on" logged "$DND_ON"

# 2. Shaking over the fixture document is ignored while DND is on.
read te wx wy ww wh <<< "$(zsh $S/fixture.sh)"
cx=$(( wx + ww / 2 )) cy=$(( wy + wh / 2 ))
guard
for x in $(( cx - 70 )) $cx $(( cx + 70 )); do mine $x $cy $te; done
drive move $cx $cy; sleep 0.2
drive shake $cx $cy
sleep 1.2
expect "shaking does not start pointing while DND is on" no_overlay
expect "Pointy logs shake-ignored dnd" grep -qF '[shake-ignored] dnd' "$VP_RUN/home/.pointy/error.log"

# 3. A bound global shortcut is also ignored while DND is on.
if [ -n "$HOTKEY" ]; then
  step tray.sh hotkey-preset "$HOTKEY" ⌘⌥P
  zsh $S/fixture.sh > /dev/null
  guard; mine $cx $cy $te; drive move $cx $cy
  step keys.sh Cmd+Alt+P fixture
  sleep 1.2
  expect "a global shortcut does not start pointing while DND is on" no_overlay
fi

# 4. Turning DND off restores shaking.
step tray.sh off "$DND"
expect "dnd is saved as False in settings.json" until_true 3 is_setting dnd False
step tray.sh off-checked
expect "the menu unchecks DND" logged "[ ] $DND"
zsh $S/fixture.sh > /dev/null
guard
for x in $(( cx - 70 )) $cx $(( cx + 70 )); do mine $x $cy $te; done
drive move $cx $cy; sleep 0.2
drive shake $cx $cy
expect "shaking starts pointing once DND is off" until_true 5 has overlay.html
sleep 0.6
shot $wx $wy $ww $wh after-dnd-pointing
step keys.sh Esc both
expect "Esc ends pointing" until_true 5 no_overlay
exit $(( failed > 0 ))
