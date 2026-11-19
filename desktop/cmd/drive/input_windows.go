//go:build windows

package main

import (
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unsafe"

	"golang.org/x/sys/windows"
)

func tickCount() uint32 {
	t, _, _ := procGetTickCount.Call()
	return uint32(t)
}

func lastInputTick() (uint32, error) {
	lii := lastInputInfo{Size: uint32(unsafe.Sizeof(lastInputInfo{}))}
	ok, _, err := procGetLastInputInfo.Call(uintptr(unsafe.Pointer(&lii)))
	if ok == 0 {
		return 0, fmt.Errorf("GetLastInputInfo: %w", err)
	}
	return lii.Time, nil
}

type stampData struct {
	injectTick uint32
	hasInject  bool
	userTick   uint32
	hasUser    bool
}

func readStamp(path string) stampData {
	b, err := os.ReadFile(path)
	if err != nil {
		return stampData{}
	}
	lines := strings.Split(strings.ReplaceAll(string(b), "\r\n", "\n"), "\n")
	var s stampData
	if len(lines) >= 1 {
		if v, err := strconv.ParseUint(strings.TrimSpace(lines[0]), 10, 32); err == nil && v != 0 {
			s.injectTick, s.hasInject = uint32(v), true
		}
	}
	if len(lines) >= 2 {
		if v, err := strconv.ParseUint(strings.TrimSpace(lines[1]), 10, 32); err == nil {
			s.userTick, s.hasUser = uint32(v), true
		}
	}
	return s
}

func writeStamp(path string, s stampData) {
	line1 := "0"
	if s.hasInject {
		line1 = strconv.FormatUint(uint64(s.injectTick), 10)
	}
	line2 := "0"
	if s.hasUser {
		line2 = strconv.FormatUint(uint64(s.userTick), 10)
	}
	_ = os.WriteFile(path, []byte(line1+"\n"+line2+"\n"), 0o644)
}

// snapshotPreInject preserves the real user input tick on the first injection
// if idle has not initialized the stamp file yet.
func snapshotPreInject() (string, stampData) {
	path := os.Getenv("DRIVE_STAMP")
	if path == "" {
		return "", stampData{}
	}
	s := readStamp(path)
	if !s.hasUser {
		if dw, err := lastInputTick(); err == nil {
			s.userTick, s.hasUser = dw, true
		}
	}
	return path, s
}

func commitPostInject(path string, s stampData) {
	if path == "" {
		return
	}
	t := tickCount()
	if t == 0 {
		t = 1
	}
	s.injectTick, s.hasInject = t, true
	writeStamp(path, s)
}

func elapsedSeconds(now, since uint32) float64 {
	diff := int32(now - since)
	if diff <= 0 {
		return 0
	}
	return float64(diff) / 1000.0
}

func idleSeconds() float64 {
	dwTime, err := lastInputTick()
	if err != nil {
		fail(err.Error())
	}
	now := tickCount()
	path := os.Getenv("DRIVE_STAMP")
	if path == "" {
		return elapsedSeconds(now, dwTime)
	}
	s := readStamp(path)
	changed := false
	if !s.hasUser {
		s.userTick, s.hasUser = dwTime, true
		changed = true
	} else if !s.hasInject || int32(dwTime-s.injectTick) > 500 {
		if s.userTick != dwTime {
			s.userTick = dwTime
			changed = true
		}
	}
	if changed {
		writeStamp(path, s)
	}
	return elapsedSeconds(now, s.userTick)
}

func sendInputs(in []winInput) {
	if len(in) == 0 {
		return
	}
	stampPath, stamp := snapshotPreInject()
	n, _, err := procSendInput.Call(uintptr(len(in)), uintptr(unsafe.Pointer(&in[0])), unsafe.Sizeof(in[0]))
	commitPostInject(stampPath, stamp)
	if int(n) != len(in) {
		fail(fmt.Sprintf("SendInput sent %d of %d events: %v", n, len(in), err))
	}
}

func newMouseInput(dx, dy int32, flags uint32) winInput {
	return winInput{
		Type: inputMouse,
		mi:   mouseInput{Dx: dx, Dy: dy, Flags: flags},
	}
}

func newKeyInput(ki keybdInput) winInput {
	var in winInput
	in.Type = inputKeyboard
	*(*keybdInput)(unsafe.Pointer(&in.mi)) = ki
	return in
}

func absMouseCoords(x, y int32) (int32, int32) {
	vs := virtualScreen()
	vw := vs.Right - vs.Left
	vh := vs.Bottom - vs.Top
	if vw <= 0 {
		vw = 1
	}
	if vh <= 0 {
		vh = 1
	}
	dx := int32((int64(x-vs.Left)*65536 + 32768) / int64(vw))
	dy := int32((int64(y-vs.Top)*65536 + 32768) / int64(vh))
	dx = max(0, min(dx, 65535))
	dy = max(0, min(dy, 65535))
	return dx, dy
}

func moveMouse(x, y int32) {
	dx, dy := absMouseCoords(x, y)
	sendInputs([]winInput{newMouseInput(dx, dy, mouseeventfMove|mouseeventfAbsolute|mouseeventfVirtualDesk)})
}

func shakeMouse(x, y int32) {
	for i := range 16 {
		dx := int32(60)
		if i%2 == 1 {
			dx = -60
		}
		moveMouse(x+dx, y)
		time.Sleep(25 * time.Millisecond)
	}
	moveMouse(x, y)
}

func clickMouse(x, y int32, right bool) {
	moveMouse(x, y)
	down, up := uint32(mouseeventfLeftDown), uint32(mouseeventfLeftUp)
	if right {
		down, up = mouseeventfRightDown, mouseeventfRightUp
	}
	sendInputs([]winInput{newMouseInput(0, 0, down)})
	time.Sleep(40 * time.Millisecond)
	sendInputs([]winInput{newMouseInput(0, 0, up)})
}

type cursorPoint struct {
	X int32 `json:"X"`
	Y int32 `json:"Y"`
}

func currentCursor() cursorPoint {
	p, ok := cursorPos()
	if !ok {
		fail("GetCursorPos failed")
	}
	return cursorPoint{X: p.X, Y: p.Y}
}

func isLocked() bool {
	h, _, _ := procOpenInputDesktop.Call(0, 0, desktopSwitchDesktop)
	if h == 0 {
		return true
	}
	defer procCloseDesktop.Call(h)
	ok, _, _ := procSwitchDesktop.Call(h)
	return ok == 0
}

func focusWindow(hwnd windows.HWND) bool {
	if ok, _, _ := procIsWindow.Call(uintptr(hwnd)); ok == 0 {
		return false
	}
	if ic, _, _ := procIsIconic.Call(uintptr(hwnd)); ic != 0 {
		procShowWindow.Call(uintptr(hwnd), swRestore)
	}
	if windows.GetForegroundWindow() == hwnd {
		return true
	}
	procSetForegroundWindow.Call(uintptr(hwnd))
	if windows.GetForegroundWindow() != hwnd {
		fg := windows.GetForegroundWindow()
		fgTID, _ := windows.GetWindowThreadProcessId(fg, nil)
		curTID := windows.GetCurrentThreadId()
		var attached uintptr
		if fgTID != 0 && fgTID != curTID {
			attached, _, _ = procAttachThreadInput.Call(uintptr(curTID), uintptr(fgTID), 1)
		}
		procBringWindowToTop.Call(uintptr(hwnd))
		procSetForegroundWindow.Call(uintptr(hwnd))
		if attached != 0 {
			procAttachThreadInput.Call(uintptr(curTID), uintptr(fgTID), 0)
		}
	}
	for range 10 {
		if windows.GetForegroundWindow() == hwnd {
			return true
		}
		time.Sleep(15 * time.Millisecond)
	}
	return windows.GetForegroundWindow() == hwnd
}

func requireForeground(pids []uint32) {
	fg := windows.GetForegroundWindow()
	if fg == 0 {
		fmt.Fprintf(os.Stderr, "drive: no foreground window, want pid in %v\n", pids)
		os.Exit(3)
	}
	fgPID := processOf(fg)
	if !slices.Contains(pids, fgPID) {
		fmt.Fprintf(os.Stderr, "drive: foreground window belongs to pid %d (class %q, title %q), want %v\n",
			fgPID, className(fg), windowText(fg), pids)
		os.Exit(3)
	}
}

var modifierVKs = map[string]uint16{
	"ctrl":    0x11, // VK_CONTROL
	"control": 0x11,
	"alt":     0x12, // VK_MENU
	"shift":   0x10, // VK_SHIFT
	"win":     0x5B, // VK_LWIN
}

var namedMainVKs = map[string]uint16{
	"space":     0x20,
	"enter":     0x0D,
	"return":    0x0D,
	"esc":       0x1B,
	"escape":    0x1B,
	"tab":       0x09,
	"backspace": 0x08,
	"delete":    0x2E,
	"insert":    0x2D,
	"home":      0x24,
	"end":       0x23,
	"pageup":    0x21,
	"pagedown":  0x22,
	"up":        0x26,
	"down":      0x28,
	"left":      0x25,
	"right":     0x27,
}

var oemFallbackVKs = map[byte]uint16{
	'[':  0xDB,
	']':  0xDD,
	',':  0xBC,
	'.':  0xBE,
	'/':  0xBF,
	';':  0xBA,
	'\'': 0xDE,
	'-':  0xBD,
	'=':  0xBB,
	'`':  0xC0,
	'\\': 0xDC,
}

func parseMainVK(token string) (uint16, bool) {
	low := strings.ToLower(token)
	if vk, ok := namedMainVKs[low]; ok {
		return vk, true
	}
	if len(token) == 1 {
		c := token[0]
		switch {
		case c >= 'a' && c <= 'z':
			return uint16(c - 'a' + 'A'), true
		case c >= 'A' && c <= 'Z':
			return uint16(c), true
		case c >= '0' && c <= '9':
			return uint16(c), true
		}
		if fallback, isOEM := oemFallbackVKs[c]; isOEM {
			r, _, _ := procVkKeyScanW.Call(uintptr(uint16(c)))
			if int16(uint16(r)) != -1 {
				return uint16(r & 0xFF), true
			}
			return fallback, true
		}
	}
	if len(low) >= 2 && low[0] == 'f' {
		if n, err := strconv.Atoi(low[1:]); err == nil && n >= 1 && n <= 24 {
			return uint16(0x70 + n - 1), true
		}
	}
	if vk, ok := modifierVKs[low]; ok {
		return vk, true
	}
	return 0, false
}

func isExtendedKey(vk uint16) bool {
	switch vk {
	case 0x21, 0x22, 0x23, 0x24, // PageUp, PageDown, End, Home
		0x25, 0x26, 0x27, 0x28, // Left, Up, Right, Down
		0x2D, 0x2E, // Insert, Delete
		0x5B, 0x5C, 0x5D, // LWin, RWin, Apps
		0xA3, 0xA5, // RControl, RMenu
		0x6F, 0x90, 0x2C: // Divide, NumLock, PrintScreen
		return true
	}
	return false
}

func makeKeyEvent(vk uint16, up bool) winInput {
	scan, _, _ := procMapVirtualKeyW.Call(uintptr(vk), mapvkVkToVsc)
	var flags uint32
	if isExtendedKey(vk) {
		flags |= keyeventfExtendedKey
	}
	if up {
		flags |= keyeventfKeyUp
	}
	return newKeyInput(keybdInput{
		Vk:    vk,
		Scan:  uint16(scan & 0xFF),
		Flags: flags,
	})
}

func parseCombo(combo string) ([]uint16, uint16) {
	if combo == "" {
		fail("empty key combo")
	}
	parts := strings.Split(combo, "+")
	var mods []uint16
	for i := 0; i < len(parts)-1; i++ {
		vk, ok := modifierVKs[strings.ToLower(strings.TrimSpace(parts[i]))]
		if !ok {
			fail("unknown modifier: " + parts[i])
		}
		mods = append(mods, vk)
	}
	mainTok := strings.TrimSpace(parts[len(parts)-1])
	mainVK, ok := parseMainVK(mainTok)
	if !ok {
		fail("unknown key: " + mainTok)
	}
	return mods, mainVK
}

func sendKeys(combo string, pids []uint32) {
	mods, mainVK := parseCombo(combo)
	requireForeground(pids)
	downs := make([]winInput, 0, len(mods)+1)
	for _, m := range mods {
		downs = append(downs, makeKeyEvent(m, false))
	}
	downs = append(downs, makeKeyEvent(mainVK, false))
	ups := make([]winInput, 0, len(mods)+1)
	ups = append(ups, makeKeyEvent(mainVK, true))
	for i := len(mods) - 1; i >= 0; i-- {
		ups = append(ups, makeKeyEvent(mods[i], true))
	}
	sendInputs(downs)
	time.Sleep(60 * time.Millisecond)
	sendInputs(ups)
}

func typeText(text string, pids []uint32) {
	requireForeground(pids)
	units := utf16.Encode([]rune(text))
	for i := 0; i < len(units); i++ {
		u := units[i]
		if u >= 0xD800 && u <= 0xDBFF && i+1 < len(units) {
			u2 := units[i+1]
			i++
			sendInputs([]winInput{
				newKeyInput(keybdInput{Scan: u, Flags: keyeventfUnicode}),
				newKeyInput(keybdInput{Scan: u2, Flags: keyeventfUnicode}),
				newKeyInput(keybdInput{Scan: u, Flags: keyeventfUnicode | keyeventfKeyUp}),
				newKeyInput(keybdInput{Scan: u2, Flags: keyeventfUnicode | keyeventfKeyUp}),
			})
			continue
		}
		sendInputs([]winInput{
			newKeyInput(keybdInput{Scan: u, Flags: keyeventfUnicode}),
			newKeyInput(keybdInput{Scan: u, Flags: keyeventfUnicode | keyeventfKeyUp}),
		})
	}
}
