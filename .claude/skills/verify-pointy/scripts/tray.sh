#!/bin/zsh
# usage: tray.sh <name> [item [subitem]]
# Clicks the run's Pointy icon in the menu bar and logs the menu's items,
# read through accessibility with their check marks. With items, chooses
# them, as "语言" then "English"; with one item that has a submenu, opens
# the submenu, logs it and closes the menu; without, closes the menu by
# clicking the icon again. Moves the mouse only over the icon and the menus
# it opens, which are Pointy's.
set -u
source ${0:A:h}/env.sh
name=$1; shift
p=$(pid pointy)
# marks [item]: the menu's items, or the item's submenu's, as "[x] name" or "[ ] name".
marks() {
  drive menus $p | python3 -c 'import json,sys
m = json.load(sys.stdin) or []
if len(sys.argv) > 1: m = next((i.get("Items") or [] for i in m if i["Name"] == sys.argv[1]), [])
print("\n".join(("[x] " if i.get("Checked") else "[ ] ") + i["Name"] for i in m if i["Name"]))' "$@"
}
# center <item> [subitem]: "x y" of the item's middle, as accessibility places it.
center() {
  drive menus $p | python3 -c 'import json,sys
m, i = json.load(sys.stdin) or [], None
for name in sys.argv[1:]:
    i = next((i for i in m if i["Name"] == name), None)
    if i is None: sys.exit(1)
    m = i.get("Items") or []
print(round(i["X"] + i["W"] / 2), round(i["Y"] + i["H"] / 2))' "$@"
}
# has_submenu <item>: whether the menu's item of that name has a submenu.
has_submenu() { drive menus $p | python3 -c 'import json,sys; sys.exit(0 if any(i["Name"] == sys.argv[1] and i.get("Items") for i in json.load(sys.stdin) or []) else 1)' "$1"; }
# bounds [item]: "x y w h" around the menu, and the item's open submenu, so a
# screenshot holds Pointy's menus and little else.
bounds() {
  drive menus $p | python3 -c 'import json,sys
m = json.load(sys.stdin) or []
items = m + (next((i.get("Items") or [] for i in m if i["Name"] == sys.argv[1]), []) if len(sys.argv) > 1 else [])
x0, y0 = min(i["X"] for i in items) - 6, min(i["Y"] for i in items) - 6
x1, y1 = max(i["X"] + i["W"] for i in items) + 6, max(i["Y"] + i["H"] for i in items) + 6
print(round(x0), round(y0), round(x1 - x0), round(y1 - y0))' "$@"
}

# The icon sits in a window of Control Center's; accessibility says it is ours.
icon=$(drive extras $p | python3 -c 'import json,sys; ws=json.load(sys.stdin) or []; print(json.dumps(ws[0]) if ws else "")')
[ -n "$icon" ] || die "Pointy's menu bar icon is not on screen (hidden behind the notch or by a menu bar manager?)"
log "tray icon tooltip ($name): $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["Name"])' "$icon")"
read ix iy <<< "$(python3 -c 'import json,sys; w=json.loads(sys.argv[1]); print(round(w["X"]+w["W"]/2), round(w["Y"]+w["H"]/2))' "$icon")"
icon_is_mine() { drive extras $p | python3 -c 'import json,sys; x,y=float(sys.argv[1]),float(sys.argv[2]); sys.exit(0 if any(w["X"]<=x<w["X"]+w["W"] and w["Y"]<=y<w["Y"]+w["H"] for w in json.load(sys.stdin) or []) else 1)' $ix $iy || die "the menu bar icon at $ix,$iy is no longer Pointy's"; }
close_menu() { icon_is_mine; drive click $ix $iy; }

guard
icon_is_mine
drive click $ix $iy
wait_until 5 "the tray menu" sh -c "[ \$($BIN/drive windows $p | grep -o '\"Layer\":101' | wc -l) -ge 1 ]"
sleep 0.3
log "tray menu ($name):"$'\n'"$(marks)"

if (( $# == 0 )); then shot $(bounds) $name-tray; close_menu; exit 0; fi
read mx my <<< "$(center "$1")"
[ -n "${my:-}" ] || { shot $(bounds) $name-tray; close_menu; die "the tray menu has no item \"$1\""; }
mine $mx $my $p
if ! has_submenu "$1"; then shot $(bounds) $name-tray; drive click $mx $my; log "chose $1"; exit 0; fi
drive move $mx $my
wait_until 5 "the submenu" sh -c "[ \$($BIN/drive windows $p | grep -o '\"Layer\":101' | wc -l) -ge 2 ]"
sleep 0.3
log "submenu \"$1\" ($name):"$'\n'"$(marks "$1")"
shot $(bounds "$1") $name-tray
if (( $# == 1 )); then close_menu; exit 0; fi
read sx sy <<< "$(center "$1" "$2")"
[ -n "${sy:-}" ] || { close_menu; die "the submenu has no item \"$2\""; }
# Across to the submenu along the item's row, then down, so the pointer
# never passes over another item that would open its own submenu.
mine $sx $my $p
drive move $sx $my
mine $sx $sy $p
drive click $sx $sy
log "chose $1 > $2"
