# Sourced by the other scripts. VP_RUN is the run's directory, from up.sh.
SKILL=${0:A:h:h}
REPO=${SKILL:h:h:h}
[ -n "${VP_RUN:-}" ] && [ -d "$VP_RUN" ] || { echo "VP_RUN is not set to a run directory; start with up.sh" >&2; exit 2; }
BIN=$VP_RUN/bin
EV=$VP_RUN/evidence
SOCK=$VP_RUN/a.sock
POINTY_PORT=47397
MOCK_PORT=47398
DSH_PORT=3093
export MYGO_AUTOMATION_SESSION=verify-pointy-${VP_RUN:t}
# drive records its own input here, so `drive idle` counts only the user's.
export DRIVE_STAMP=$VP_RUN/input-stamp
# SRC is the checkout the run built (up.sh with VP_REPO); the tools come from REPO.
SRC=$(cat "$VP_RUN/src" 2>/dev/null || print -r -- $REPO)
# SOLO: the run started Pointy alone, without DSH and the mock model.
[ -e "$VP_RUN/solo" ] && SOLO=1 || SOLO=
mkdir -p "$EV"

pid() { cat "$VP_RUN/pids/$1" 2>/dev/null; }
# tree <pid>: the pid and every process under it.
tree() { print $1; local c; for c in $(pgrep -P $1); do tree $c; done }
pa() { "$BIN/mygo-automation" "$@"; }
drive() { "$BIN/drive" "$@"; }
log() { print -r -- "$*" | tee -a "$EV/run.log" >&2; }
die() { log "FAIL: $*"; exit 1; }

# js <window> <script>: evaluates the script in a page of the run's Pointy.
js() { pa open --socket "$SOCK" > /dev/null && pa eval --window "$1" "$2"; }

# win <page>: the automation id of the newest window showing that page;
# has <page>: whether one shows it.
win() { pa open --socket "$SOCK" > /dev/null && pa windows | grep "$1" | tail -1 | awk '{print $1}'; }
has() { pa open --socket "$SOCK" > /dev/null && pa windows | grep -v hidden | grep -q "$1"; }

# guard: returns once the screen is unlocked and the user has not touched
# the keyboard or mouse for VP_IDLE seconds (30), waiting up to VP_WAIT
# seconds (900); aborts the run otherwise. Call it before every mouse action.
guard() {
  local need=${VP_IDLE:-30} end=$(( SECONDS + ${VP_WAIT:-900} )) idle
  while (( SECONDS < end )); do
    idle=$(drive idle); idle=${idle%.*}
    [ "$(drive locked)" = false ] && (( idle >= need )) && return 0
    sleep 5
  done
  [ "$(drive locked)" = false ] || die "the screen stayed locked; WebKit paints nothing while it is"
  die "the user stayed active (idle ${idle}s < ${need}s); not touching the mouse"
}

# mine <x> <y> <pid>...: aborts unless the top window at x,y belongs to one of the pids.
mine() { local x=$1 y=$2 o; shift 2; o=$(drive at $x $y); (( ${@[(Ie)$o]} )) || die "the window at $x,$y is pid $o's ($(ps -p $o -o comm= 2> /dev/null)), not $*'s; not touching it"; }

# wait_until <seconds> <what> <command...>: polls the command until it succeeds.
wait_until() {
  local secs=$1 what=$2; shift 2
  local end=$(( SECONDS + secs ))
  while (( SECONDS < end )); do "$@" > /dev/null 2>&1 && return 0; sleep 0.2; done
  die "timed out after ${secs}s waiting for $what"
}

# close_doc <path>: closes the TextEdit window showing that document by its
# close button, through System Events, so TextEdit itself needs no
# Automation permission. The run's documents are never edited.
close_doc() { osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to click (first button of window \"${1:t}\" whose subrole is \"AXCloseButton\")" > /dev/null 2>&1; }

# shot_page <page> <name>: saves the newest window showing the page as
# WebKit draws it, which needs no Screen Recording.
shot_page() { pa open --socket "$SOCK" > /dev/null && pa screenshot --window "$(win $1)" "$EV/$2.png" > /dev/null; }

# shot <x> <y> <w> <h> <name>: saves that part of the screen, or logs why not.
shot() { screencapture -x -R $1,$2,$3,$4 "$EV/$5.png" 2> /dev/null || log "no $5.png: screencapture failed (is Screen Recording granted to this terminal?)"; }

# setting <key>: a value from the run's Pointy settings.json.
setting() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$VP_RUN/home/.pointy/settings.json" $1; }
