#!/bin/zsh
# usage: shake.sh [checkout] [keep]
# Shake sensitivity on macOS, from a fresh run to down.sh: turn shake off
# (a hard shake does nothing), set Low (a light shake does nothing, a hard shake
# starts pointing), set High (the same light shake starts pointing), then return
# to Medium. Prints PASS/FAIL per check; evidence stays in $VP_RUN/evidence.
set -u
S=${0:A:h:h}/scripts
export VP_REPO=${1:-${VP_REPO:-}} VP_SOLO=1
keep=${2:-}
src=${${VP_REPO:-${0:A:h:h:h:h:h}}:A}
python3 -c 'import json,sys; sys.exit(0 if "shake" in json.load(open(sys.argv[1]))["tray"] else 1)' "$src/locales/zh-CN.json" \
  || { print "SKIP: this checkout has no shake submenu"; exit 0; }
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
logged() { tail -${2:-15} "$EV/run.log" | grep -qF -- "$1"; }
no_overlay() { ! has overlay.html; }
is_setting() { [ "$(setting $1)" = "$2" ]; }

t() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tray"][sys.argv[2]])' "$SRC/locales/zh-CN.json" "$1"; }
SHAKE=$(t shake)
OFF=$(t shakeOff)
LOW=$(t shakeLow)
MED=$(t shakeMedium)
HIGH=$(t shakeHigh)

read te wx wy ww wh <<< "$(zsh $S/fixture.sh)"
cx=$(( wx + ww / 2 )) cy=$(( wy + wh / 2 ))

shake_over() {
  local amp=$1 pad=$(( $1 + 10 ))
  (( pad < 70 )) && pad=70
  zsh $S/fixture.sh > /dev/null
  guard
  for x in $(( cx - pad )) $cx $(( cx + pad )); do mine $x $cy $te; done
  drive move $cx $cy; sleep 0.2
  drive shake $cx $cy $amp
}

# 1. Off: even a hard shake (amp 60 -> span 120) does not start pointing.
step tray.sh off "$SHAKE" "$OFF"
expect "shake is saved as False in settings.json" until_true 3 is_setting shake False
step tray.sh off-checked "$SHAKE"
expect "the submenu checks Off" logged "[x] $OFF"
shake_over 60
sleep 1.2
expect "a hard shake does nothing when shake is Off" no_overlay

# 2. Low (requires >= 60 per leg): light shake (amp 20 -> span 40) is ignored;
#    hard shake (amp 60 -> span 120) starts pointing.
step tray.sh low "$SHAKE" "$LOW"
expect "shake is True in settings.json" until_true 3 is_setting shake True
expect "shakeLevel is low in settings.json" until_true 3 is_setting shakeLevel low
step tray.sh low-checked "$SHAKE"
expect "the submenu checks Low" logged "[x] $LOW"
shake_over 20
sleep 1.2
expect "a light shake does not trigger at Low sensitivity" no_overlay
shake_over 60
expect "a hard shake triggers at Low sensitivity" until_true 5 has overlay.html
sleep 0.6
shot $wx $wy $ww $wh low-pointing
step keys.sh Esc both
expect "Esc ends pointing after Low" until_true 5 no_overlay

# 3. High (requires >= 28 per leg): the same light shake (amp 20 -> span 40)
#    now starts pointing once the 1.5 s shake cooldown has passed.
step tray.sh high "$SHAKE" "$HIGH"
expect "shake is True in settings.json" until_true 3 is_setting shake True
expect "shakeLevel is high in settings.json" until_true 3 is_setting shakeLevel high
step tray.sh high-checked "$SHAKE"
expect "the submenu checks High" logged "[x] $HIGH"
sleep 1.7
shake_over 20
expect "a light shake triggers at High sensitivity" until_true 5 has overlay.html
sleep 0.6
shot $wx $wy $ww $wh high-pointing
step keys.sh Esc both
expect "Esc ends pointing after High" until_true 5 no_overlay

# 4. Medium: saved and checked.
step tray.sh medium "$SHAKE" "$MED"
expect "shakeLevel is medium in settings.json" until_true 3 is_setting shakeLevel medium
step tray.sh medium-checked "$SHAKE"
expect "the submenu checks Medium" logged "[x] $MED"
exit $(( failed > 0 ))
