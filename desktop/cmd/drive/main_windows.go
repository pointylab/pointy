//go:build windows

// Command drive posts real mouse and keyboard input and reads what Windows
// shows on screen, for tests of Pointy:
//
//	drive move X Y                                        move the mouse
//	drive shake X Y [AMP]                                 shake it around X, Y (default half-span 60)
//	drive click X Y [right]                               click there
//	drive at X Y [PID]                                    the pid owning the top window at X, Y, skipping PID
//	drive front                                           the foreground window's pid
//	drive fronthwnd                                       the foreground window's handle
//	drive idle                                            seconds since the last keyboard or mouse input
//	drive locked                                          whether the screen is locked
//	drive windows PID [-all]                              the visible (or all) top-level windows of PID, front to back
//	drive displays                                        the displays' bounds and work areas
//	drive menus PID                                       the visible popup menus of PID
//	drive tray PID [-id TRAYID] [-shot OUT.png] [IT [SB]] open the tray menu, list it (and IT's submenu), choose IT or IT > SB
//	drive keys COMBO PID [PID...]                         send a key combination if PID is in front
//	drive type TEXT PID [PID...]                          type text if PID is in front
//	drive shot X Y W H OUT.png                            capture a screen rectangle to a PNG file
//	drive shotwin HWND OUT.png [PAD]                      capture a window's bounds to a PNG file
//	drive focus HWND                                      bring a window to the foreground
//	drive cursor                                          the cursor position in pixels
package main

import (
	"encoding/json/v2"
	"fmt"
	"math"
	"os"
	"runtime"
	"strconv"

	"golang.org/x/sys/windows"
)

func init() { runtime.LockOSThread() }

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "drive:", msg)
	os.Exit(1)
}

func printJSON(v any) {
	b, err := json.Marshal(v)
	if err != nil {
		fail(err.Error())
	}
	fmt.Println(string(b))
}

func coord(args []string, i int) int32 {
	if i >= len(args) {
		fail("missing coordinate argument")
	}
	f, err := strconv.ParseFloat(args[i], 64)
	if err != nil {
		fail(err.Error())
	}
	return int32(math.Round(f))
}

func pidArg(args []string, i int) uint32 {
	if i >= len(args) {
		fail("missing PID argument")
	}
	v, err := strconv.ParseUint(args[i], 10, 32)
	if err != nil {
		fail(err.Error())
	}
	return uint32(v)
}

func pidList(args []string, from int) []uint32 {
	if from >= len(args) {
		fail("missing PID argument")
	}
	out := make([]uint32, 0, len(args)-from)
	for i := from; i < len(args); i++ {
		out = append(out, pidArg(args, i))
	}
	return out
}

func hwndArg(args []string, i int) windows.HWND {
	if i >= len(args) {
		fail("missing HWND argument")
	}
	v, err := strconv.ParseUint(args[i], 0, 64)
	if err != nil {
		fail(err.Error())
	}
	return windows.HWND(v)
}

func strArg(args []string, i int, name string) string {
	if i >= len(args) {
		fail("missing " + name + " argument")
	}
	return args[i]
}

func parseTrayArgs(args []string) (pid uint32, trayID, shotPath string, path []string) {
	pid = pidArg(args, 1)
	trayID = "pointy"
	for i := 2; i < len(args); i++ {
		switch args[i] {
		case "-id":
			i++
			trayID = strArg(args, i, "-id")
		case "-shot":
			i++
			shotPath = strArg(args, i, "-shot")
		default:
			path = append(path, args[i])
		}
	}
	if len(path) > 2 {
		fail("tray accepts at most ITEM and SUBITEM")
	}
	return pid, trayID, shotPath, path
}

func main() {
	initDPI()
	args := os.Args[1:]
	if len(args) == 0 {
		fail("usage: drive move|shake|click|at|front|fronthwnd|idle|locked|windows|displays|menus|tray|keys|type|shot|shotwin|focus|cursor")
	}
	switch args[0] {
	case "move":
		moveMouse(coord(args, 1), coord(args, 2))
	case "shake":
		amp := int32(60)
		if len(args) > 3 {
			amp = coord(args, 3)
		}
		shakeMouse(coord(args, 1), coord(args, 2), amp)
	case "click":
		right := false
		if len(args) > 3 {
			if args[3] != "right" {
				fail("expected 'right', got " + args[3])
			}
			right = true
		}
		clickMouse(coord(args, 1), coord(args, 2), right)
	case "at":
		var skip uint32
		if len(args) > 3 {
			skip = pidArg(args, 3)
		}
		printJSON(ownerAt(coord(args, 1), coord(args, 2), skip))
	case "front":
		fg := windows.GetForegroundWindow()
		if fg == 0 {
			printJSON(0)
		} else {
			printJSON(processOf(fg))
		}
	case "fronthwnd":
		printJSON(uint64(windows.GetForegroundWindow()))
	case "idle":
		printJSON(idleSeconds())
	case "locked":
		printJSON(isLocked())
	case "windows":
		printJSON(windowsOf(pidArg(args, 1), len(args) > 2 && args[2] == "-all"))
	case "displays":
		printJSON(displaysOf())
	case "menus":
		printJSON(menusOf(pidArg(args, 1)))
	case "tray":
		pid, trayID, shotPath, path := parseTrayArgs(args)
		res, err := runTray(pid, trayID, shotPath, path)
		if err != nil {
			fail(err.Error())
		}
		printJSON(res)
	case "keys":
		combo := strArg(args, 1, "COMBO")
		sendKeys(combo, pidList(args, 2))
	case "type":
		text := strArg(args, 1, "TEXT")
		typeText(text, pidList(args, 2))
	case "shot":
		x, y := coord(args, 1), coord(args, 2)
		w, h := coord(args, 3), coord(args, 4)
		out := strArg(args, 5, "OUT.png")
		if err := savePNG(rect{Left: x, Top: y, Right: x + w, Bottom: y + h}, out); err != nil {
			fail(err.Error())
		}
	case "shotwin":
		hwnd := hwndArg(args, 1)
		out := strArg(args, 2, "OUT.png")
		var pad int32
		if len(args) > 3 {
			pad = coord(args, 3)
		}
		if err := shotWindowPNG(hwnd, out, pad); err != nil {
			fail(err.Error())
		}
	case "focus":
		printJSON(focusWindow(hwndArg(args, 1)))
	case "cursor":
		printJSON(currentCursor())
	default:
		fail("unknown command " + args[0])
	}
}
