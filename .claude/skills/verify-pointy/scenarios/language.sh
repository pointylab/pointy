#!/bin/zsh
# usage: language.sh [checkout] [keep]
# Switching languages through the menu bar on macOS, from a fresh run to
# down.sh: verify the Chinese menu, switch to English, check the English menu,
# tooltip and a newly opened English notice, switch back to Chinese, and return
# to Same as System. Prints PASS/FAIL per check; evidence stays in $VP_RUN/evidence.
set -u
S=${0:A:h:h}/scripts
export VP_REPO=${1:-${VP_REPO:-}} VP_SOLO=1
keep=${2:-}
src=${${VP_REPO:-${0:A:h:h:h:h:h}}:A}
python3 -c 'import json,sys; sys.exit(0 if "language" in json.load(open(sys.argv[1])) else 1)' "$src/locales/zh-CN.json" \
  || { print "SKIP: this checkout has no language menu"; exit 0; }
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
logged_all() { local n=$1; shift; for s in "$@"; do tail -$n "$EV/run.log" | grep -qF -- "$s" || return 1; done; }
no_notice() { ! has notice.html; }
is_setting() { [ "$(setting $1)" = "$2" ]; }
contains() { [[ "$1" == *"$2"* ]]; }

loc() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]][sys.argv[3]])' "$SRC/locales/$1.json" "$2" "$3"; }
ZH_MENU=$(loc zh-CN language menu)
ZH_SELF=$(loc zh-CN language self)
ZH_SYS=$(loc zh-CN language system)
ZH_SHAKE=$(loc zh-CN tray shake)
ZH_DND=$(loc zh-CN tray dnd)
ZH_QUIT=$(loc zh-CN tray quit)
EN_MENU=$(loc en language menu)
EN_SELF=$(loc en language self)
EN_SHAKE=$(loc en tray shake)
EN_GUIDE=$(loc en tray guide)
EN_DND=$(loc en tray dnd)
EN_QUIT=$(loc en tray quit)
EN_EXT=$(loc en tray extensionOffline)
EN_WELCOME=$(loc en welcome title)

# 1. Starts in Chinese.
step tray.sh zh
expect "the initial menu is in Chinese" logged_all 25 "$ZH_SHAKE" "$ZH_DND" "$ZH_MENU" "$ZH_QUIT"

# 2. Switch to English via the menu bar.
step tray.sh to-en "$ZH_MENU" "$EN_SELF"
expect "locale is saved as en in settings.json" until_true 3 is_setting locale en

# 3. Menu, submenu and tooltip update to English at once.
step tray.sh en "$EN_MENU"
expect "the menu switches to English" logged_all 30 "$EN_SHAKE" "$EN_GUIDE" "$EN_DND" "$EN_QUIT"
expect "the tooltip updates to English" logged "$EN_EXT" 30
expect "the Language submenu checks English" logged "[x] $EN_SELF" 15

# 4. A notice opened after the switch uses English.
step tray.sh en-guide "$EN_GUIDE"
expect "the welcome notice opens" until_true 5 has notice.html
sleep 0.4
nw=$(win notice.html)
shot_page notice.html en-notice
notice_text=$(js $nw "return document.getElementById('box').innerText")
log "English notice text: $(print -r -- "$notice_text" | tr '\n' ' ')"
expect "the notice shows English welcome title" contains "$notice_text" "$EN_WELCOME"
expect "the notice shows English welcome body" contains "$notice_text" "Shake the mouse"
js $nw "setTimeout(() => document.getElementById('x').click(), 50); return 'ok'" > /dev/null 2>&1
expect "the notice closes" until_true 5 no_notice

# 5. Switch back to Chinese.
step tray.sh to-zh "$EN_MENU" "$ZH_SELF"
expect "locale is saved as zh-CN in settings.json" until_true 3 is_setting locale zh-CN
step tray.sh zh-again
expect "the menu returns to Chinese" logged_all 25 "$ZH_SHAKE" "$ZH_QUIT"

# 6. Return to Same as System clears locale from settings.json.
step tray.sh to-system "$ZH_MENU" "$ZH_SYS"
expect "locale leaves settings.json after Same as System" until_true 3 is_setting locale ""
exit $(( failed > 0 ))
