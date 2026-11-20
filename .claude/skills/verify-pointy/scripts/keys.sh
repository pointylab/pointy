#!/bin/zsh
# usage: keys.sh <combo> [pointy|fixture|both]   e.g. keys.sh Cmd+Alt+K
# Presses a combination with real input once the user is idle, only while
# the frontmost app is the run's Pointy, or TextEdit with the run's fixture
# document focused (fixture.sh). The page cannot get a real chord through
# eval, and a global shortcut fires only on real input.
set -u
source ${0:A:h}/env.sh
combo=$1 to=${2:-pointy}
guard
f=$(drive front)
if [[ $to != fixture && $f == $(pid pointy) ]]; then
  drive keys $combo $f || die "no $combo: the frontmost app changed"
elif [[ $to != pointy && $f == $(cat "$VP_RUN/fixture-pid" 2>/dev/null) ]]; then
  drive keys $combo -window "$(cat "$VP_RUN/fixture-title")" $f || die "no $combo: the fixture document is not TextEdit's focused window"
else
  die "no $combo: the frontmost app is pid $f, not the run's $to"
fi
log "pressed $combo in pid $f"
