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
windows() { drive windows $p; }
# rows <window json>: "y<TAB>name" for each menu item down the window's middle.
rows() {
  python3 -c '
import json, subprocess, sys
w, drive = json.loads(sys.argv[1]), sys.argv[2]
x, seen = w["X"] + w["W"] / 2, None
for y in range(int(w["Y"]) + 3, int(w["Y"] + w["H"]) - 2, 3):
    out = subprocess.run([drive, "chain", str(x), str(y)], capture_output=True, text=True).stdout
    try: item = json.loads(out)["chain"][0]
    except Exception: continue
    if item.get("control") != "ControlType.MenuItem" or not item.get("name"): continue
    r = item["rect"]
    if item["name"] != seen: print(f"{r[1] + r[3] / 2:.0f}\t{item['"'"'name'"'"']}")
    seen = item["name"]
' "$1" "$BIN/drive"
}
# marks [item]: the menu's items, or the item's submenu's, as "[x] name" or "[ ] name".
marks() {
  drive menus $p | python3 -c 'import json,sys
m = json.load(sys.stdin) or []
if len(sys.argv) > 1: m = next((i.get("Items") or [] for i in m if i["Name"] == sys.argv[1]), [])
print("\n".join(("[x] " if i.get("Checked") else "[ ] ") + i["Name"] for i in m if i["Name"]))' "$@"
}
# has_submenu <item>: whether the menu's item of that name has a submenu.
has_submenu() { drive menus $p | python3 -c 'import json,sys; sys.exit(0 if any(i["Name"] == sys.argv[1] and i.get("Items") for i in json.load(sys.stdin) or []) else 1)' "$1"; }
menus() { windows | python3 -c 'import json,sys; [print(json.dumps(w)) for w in json.load(sys.stdin) if w["Layer"] == 101]'; }

# The icon sits in a window of Control Center's; accessibility says it is ours.
icon=$(drive extras $p | python3 -c 'import json,sys; ws=json.load(sys.stdin) or []; print(json.dumps(ws[0]) if ws else "")')
[ -n "$icon" ] || die "Pointy's menu bar icon is not on screen (hidden behind the notch or by a menu bar manager?)"
log "tray icon tooltip ($name): $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["Name"])' "$icon")"
read ix iy <<< "$(python3 -c 'import json,sys; w=json.loads(sys.argv[1]); print(round(w["X"]+w["W"]/2), round(w["Y"]+w["H"]/2))' "$icon")"
icon_is_mine() { drive extras $p | python3 -c 'import json,sys; x,y=float(sys.argv[1]),float(sys.argv[2]); sys.exit(0 if any(w["X"]<=x<w["X"]+w["W"] and w["Y"]<=y<w["Y"]+w["H"] for w in json.load(sys.stdin) or []) else 1)' $ix $iy || die "the menu bar icon at $ix,$iy is no longer Pointy's"; }

guard
icon_is_mine
drive click $ix $iy
wait_until 5 "the tray menu" sh -c "$BIN/drive windows $p | grep -q '\"Layer\":101'"
sleep 0.3
menu=$(menus | head -1)
items=$(rows "$menu")
log "tray menu ($name):"$'\n'"$(marks)"
shot $(python3 -c 'import json,sys; w=json.loads(sys.argv[1]); print(" ".join(str(round(w[k])) for k in "XYWH"))' "$menu") $name-tray

mx=$(python3 -c 'import json,sys; w=json.loads(sys.argv[1]); print(w["X"]+w["W"]/2)' "$menu")
if (( $# == 0 )); then icon_is_mine; drive click $ix $iy; exit 0; fi
y=$(print -r -- "$items" | awk -F'\t' -v n="$1" '$2 == n {print $1}')
[ -n "$y" ] || { icon_is_mine; drive click $ix $iy; die "the tray menu has no item \"$1\""; }
mine $mx $y $p
if (( $# == 1 )) && ! has_submenu "$1"; then drive click $mx $y; exit 0; fi
drive move $mx $y
wait_until 5 "the submenu" sh -c "[ \$($BIN/drive windows $p | grep -o '\"Layer\":101' | wc -l) -ge 2 ]"
sleep 0.3
sub=$(menus | python3 -c 'import json,sys; m=json.loads(sys.argv[1]); print(next(l for l in sys.stdin if json.loads(l)["ID"] != m["ID"]).strip())' "$menu")
subitems=$(rows "$sub")
log "submenu \"$1\" ($name):"$'\n'"$(marks "$1")"
if (( $# == 1 )); then
  shot $(python3 -c 'import json,sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
x, y = min(a["X"], b["X"]), min(a["Y"], b["Y"])
print(round(x), round(y), round(max(a["X"] + a["W"], b["X"] + b["W"]) - x), round(max(a["Y"] + a["H"], b["Y"] + b["H"]) - y))' "$menu" "$sub") $name-tray
  icon_is_mine; drive click $ix $iy; exit 0
fi
sx=$(python3 -c 'import json,sys; w=json.loads(sys.argv[1]); print(w["X"]+w["W"]/2)' "$sub")
sy=$(print -r -- "$subitems" | awk -F'\t' -v n="$2" '$2 == n {print $1}')
[ -n "$sy" ] || { icon_is_mine; drive click $ix $iy; die "the submenu has no item \"$2\""; }
mine $sx $y $p
drive move $sx $y
mine $sx $sy $p
drive click $sx $sy
log "chose $1 > $2"
