#!/bin/zsh
# usage: ask.sh [checkout] [keep]
# The main flow on macOS against DSH and the mock model, from a fresh run to
# down.sh: shake over the run's own document, click its paragraph, ask from
# the card in full mode and read the answer; then ask again, close the card
# mid-task into a pill, follow it to done and click it back into a card.
# Prints PASS/FAIL per check; evidence stays in $VP_RUN/evidence.
set -u
S=${0:A:h:h}/scripts
export VP_REPO=${1:-${VP_REPO:-}}
keep=${2:-}
command -v ${DSH:-dsh} > /dev/null || { print "SKIP: no dsh on PATH (or DSH=/path/to/dsh)"; exit 0; }
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
expect() { local what=$1; shift; if "$@" > /dev/null 2>&1; then log "PASS $what"; else log "FAIL $what"; (( failed++ )); fi }
until_true() { local end=$(( SECONDS + $1 )); shift; while (( SECONDS < end )); do "$@" > /dev/null 2>&1 && return 0; sleep 0.2; done; return 1; }
no_card() { ! has card.html; }
logged() { tail -${2:-30} "$EV/run.log" | grep -qF -- "$1"; }
page_has() { js $1 "if (!document.getElementById('$2').innerText.includes($(print -r -- "$3" | node -e 'process.stdout.write(JSON.stringify(require("fs").readFileSync(0, "utf8").trim()))'))) throw 'no'"; }
mock_got() { python3 -c 'import json,sys
for line in open(sys.argv[1]):
    m = json.loads(line)["body"].get("messages") or []
    if m and all(s in json.dumps(m[-1], ensure_ascii=False) for s in sys.argv[2:]): sys.exit(0)
sys.exit(1)' "$EV/mock.jsonl" "$@"; }
QUESTION=这段话在说什么
PARAGRAPH='shake the mouse, point at anything on screen'

# 1. A shake over the document starts pointing; a click opens a card that quotes it.
cw=$(zsh $S/pick.sh first) || cw=
expect "a shake and a click open a card" test -n "$cw"
[ -n "$cw" ] || exit 1
expect "the card quotes the paragraph pointed at" logged "$PARAGRAPH" 5

# 2. Full mode: a search step, the answer, DSH's title, and what the model got.
zsh $S/ask.sh $cw first $QUESTION || log "(ask.sh failed)"
expect "the card shows the search step" logged '正在搜索「pointy 指认工具」' 5
expect "the card shows the answer" page_has $cw thread 这是一段模拟回答。
expect "the card takes DSH's title" logged 'card title: Mock 标题' 3
expect "the model got the question and the paragraph" mock_got $QUESTION "$PARAGRAPH"

# 3. Closing a card mid-task keeps it as a pill, which turns done and opens the card again.
# The first card goes first, so the next pick has to open a card of its own;
# the click waits until eval has returned, as it closes the window.
js $cw "setTimeout(() => document.getElementById('close').click()); return 'closed'" > /dev/null
until_true 5 no_card || log "(the first card stayed open)"
cw=$(zsh $S/pick.sh kept) || cw=
[ -n "$cw" ] || { log "FAIL a second pick opens a card"; (( failed++ )); exit 1; }
# The closed card handed its session back to be archived, so a pick on the
# same page starts a new task instead of offering that session.
expect "a second pick on the same page starts a new task" js $cw "if (!document.getElementById('new-task').hidden) throw 'no'"
log "second card asks in: $(js $cw "const b = document.getElementById('new-task'); if (!b.hidden) b.click(); return document.getElementById('target-label').textContent")"
zsh $S/ask.sh $cw kept $QUESTION keep || log "(ask.sh keep failed)"
expect "closing the card mid-task shows a running pill" logged 'pill while running: pill run' 6
expect "the pill turns done" logged 'pill when done: pill done' 4
expect "the pill keeps DSH's title" sh -c "tail -4 '$EV/run.log' | grep -q 'pill when done: .*Mock 标题'"
# The click closes the pill window, so it waits until eval has returned.
js $(win pill.html) "setTimeout(() => [...document.querySelectorAll('.pill:not(.out)')].at(-1).click()); return 'ok'" > /dev/null
expect "clicking the pill brings the card back" until_true 5 has card.html
sleep 0.6  # the card fades in
shot_page card.html kept-restored
exit $(( failed > 0 ))
