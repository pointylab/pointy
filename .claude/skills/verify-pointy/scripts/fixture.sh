#!/bin/zsh
# usage: fixture.sh   opens fixture.txt as the run's own TextEdit document,
# brings it to the front and prints "pid x y w h" of its window. Global
# shortcuts are tried over it, so keys land in a document of the run's.
set -u
source ${0:A:h}/env.sh
doc=$VP_RUN/verify-pointy-fixture.txt
[ -e "$doc" ] || cp "$SKILL/fixture.txt" "$doc"
grep -qxF "${doc:A}" "$VP_RUN/fixtures" 2>/dev/null || print -r -- "${doc:A}" >> "$VP_RUN/fixtures"
# Opening activates TextEdit, so it waits for an idle user like the mouse does.
guard
open -a TextEdit "$doc"
te=$(pgrep -nx TextEdit)
print $te > "$VP_RUN/fixture-pid"
print -r -- ${doc:t} > "$VP_RUN/fixture-title"
wait_until 10 "the fixture window in front" sh -c "[ \"\$($BIN/drive front)\" = $te ]"
IFS=', ' read wx wy ww wh <<< "$(osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to get {position, size} of window \"${doc:t}\"")"
[ -n "${wh:-}" ] || die "could not read the fixture window's bounds"
# Wait for the window itself, not only its app, to be on top in the middle.
cx=$(( wx + ww / 2 )) cy=$(( wy + wh / 2 ))
for i in {1..25}; do [ "$(drive at $cx $cy)" = $te ] && break; sleep 0.2; done
if [ "$(drive at $cx $cy)" != $te ]; then
  o=$(drive at $cx $cy)
  log "TextEdit's windows: $(drive windows $te)"
  log "pid $o's windows: $(drive windows $o)"
  die "the window in the middle of the fixture is pid $o's ($(ps -p $o -o comm= 2> /dev/null))"
fi
log "fixture document ${doc:t} (TextEdit pid $te) at $wx,$wy ${ww}x$wh"
print $te $wx $wy $ww $wh
