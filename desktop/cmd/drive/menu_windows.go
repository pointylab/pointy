//go:build windows

package main

import (
	"fmt"
	"hash/fnv"
	"strings"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func ownerAt(x, y int32, skip uint32) uint32 {
	p := point{X: x, Y: y}
	if h, _, _ := procWindowFromPoint.Call(p.byValue()); h != 0 {
		root := rootOf(windows.HWND(h))
		pid := processOf(root)
		if skip == 0 || (pid != 0 && pid != skip) {
			return pid
		}
	}
	if skip == 0 {
		return 0
	}
	var found uint32
	enumTopWindows(func(h windows.HWND) bool {
		pid := processOf(h)
		if pid == 0 || pid == skip || !windows.IsWindowVisible(h) || cloaked(h) {
			return true
		}
		r, ok := windowRect(h)
		if !ok || x < r.Left || y < r.Top || x >= r.Right || y >= r.Bottom {
			return true
		}
		found = pid
		return false
	})
	return found
}

type windowInfo struct {
	HWND    uint64 `json:"HWND"`
	Class   string `json:"Class"`
	Title   string `json:"Title"`
	X       int    `json:"X"`
	Y       int    `json:"Y"`
	W       int    `json:"W"`
	H       int    `json:"H"`
	Cloaked bool   `json:"Cloaked"`
}

func windowsOf(pid uint32, all bool) []windowInfo {
	out := []windowInfo{}
	enumTopWindows(func(h windows.HWND) bool {
		if processOf(h) != pid || (!all && !windows.IsWindowVisible(h)) {
			return true
		}
		r, _ := windowRect(h)
		out = append(out, windowInfo{
			HWND:    uint64(h),
			Class:   className(h),
			Title:   windowText(h),
			X:       int(r.Left),
			Y:       int(r.Top),
			W:       int(r.Right - r.Left),
			H:       int(r.Bottom - r.Top),
			Cloaked: cloaked(h),
		})
		return true
	})
	return out
}

type displayInfo struct {
	X       int  `json:"X"`
	Y       int  `json:"Y"`
	W       int  `json:"W"`
	H       int  `json:"H"`
	WorkX   int  `json:"WorkX"`
	WorkY   int  `json:"WorkY"`
	WorkW   int  `json:"WorkW"`
	WorkH   int  `json:"WorkH"`
	Primary bool `json:"Primary"`
}

func displaysOf() []displayInfo {
	out := []displayInfo{}
	enumMonitors(func(m uintptr) {
		info := monitorInfo{Size: uint32(unsafe.Sizeof(monitorInfo{}))}
		if ok, _, _ := procGetMonitorInfoW.Call(m, uintptr(unsafe.Pointer(&info))); ok == 0 {
			return
		}
		mr, wr := info.Monitor, info.Work
		out = append(out, displayInfo{
			X:       int(mr.Left),
			Y:       int(mr.Top),
			W:       int(mr.Right - mr.Left),
			H:       int(mr.Bottom - mr.Top),
			WorkX:   int(wr.Left),
			WorkY:   int(wr.Top),
			WorkW:   int(wr.Right - wr.Left),
			WorkH:   int(wr.Bottom - wr.Top),
			Primary: info.Flags&monitorInfoPrimary != 0,
		})
	})
	return out
}

type menuItem struct {
	Index     int    `json:"Index"`
	Text      string `json:"Text"`
	Accel     string `json:"Accel"`
	Checked   bool   `json:"Checked"`
	Disabled  bool   `json:"Disabled"`
	Separator bool   `json:"Separator"`
	Submenu   bool   `json:"Submenu"`
	X         int    `json:"X"`
	Y         int    `json:"Y"`
	W         int    `json:"W"`
	H         int    `json:"H"`
}

type menuWindowInfo struct {
	HWND  uint64     `json:"HWND"`
	X     int        `json:"X"`
	Y     int        `json:"Y"`
	W     int        `json:"W"`
	H     int        `json:"H"`
	Items []menuItem `json:"Items"`
}

func stripMnemonics(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '&' {
			if i+1 < len(s) && s[i+1] == '&' {
				b.WriteByte('&')
				i++
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func readMenuWindow(h windows.HWND) (menuWindowInfo, bool) {
	wr, ok := windowRect(h)
	if !ok {
		return menuWindowInfo{}, false
	}
	hmenu, _, _ := procSendMessageW.Call(uintptr(h), mnGetHMenu, 0, 0)
	items := []menuItem{}
	if hmenu != 0 {
		rawCount, _, _ := procGetMenuItemCount.Call(hmenu)
		count := int(int32(rawCount))
		for i := 0; i < count; i++ {
			var buf [1024]uint16
			mi := menuItemInfo{
				Size:     uint32(unsafe.Sizeof(menuItemInfo{})),
				Mask:     miimState | miimSubMenu | miimFType | miimString,
				TypeData: &buf[0],
				Cch:      uint32(len(buf)),
			}
			if ok, _, _ := procGetMenuItemInfoW.Call(hmenu, uintptr(i), 1, uintptr(unsafe.Pointer(&mi))); ok == 0 {
				mi = menuItemInfo{
					Size: uint32(unsafe.Sizeof(menuItemInfo{})),
					Mask: miimState | miimSubMenu | miimFType,
				}
				procGetMenuItemInfoW.Call(hmenu, uintptr(i), 1, uintptr(unsafe.Pointer(&mi)))
			}
			raw := windows.UTF16ToString(buf[:])
			labelPart, accel, _ := strings.Cut(raw, "\t")
			var ir rect
			procGetMenuItemRect.Call(0, hmenu, uintptr(i), uintptr(unsafe.Pointer(&ir)))
			items = append(items, menuItem{
				Index:     i,
				Text:      stripMnemonics(labelPart),
				Accel:     accel,
				Checked:   mi.State&mfsChecked != 0,
				Disabled:  mi.State&mfsDisabled != 0,
				Separator: mi.Type&mftSeparator != 0,
				Submenu:   mi.SubMenu != 0,
				X:         int(ir.Left),
				Y:         int(ir.Top),
				W:         int(ir.Right - ir.Left),
				H:         int(ir.Bottom - ir.Top),
			})
		}
	}
	return menuWindowInfo{
		HWND:  uint64(h),
		X:     int(wr.Left),
		Y:     int(wr.Top),
		W:     int(wr.Right - wr.Left),
		H:     int(wr.Bottom - wr.Top),
		Items: items,
	}, true
}

func visibleMenuWindows(pid uint32) []windows.HWND {
	var out []windows.HWND
	enumTopWindows(func(h windows.HWND) bool {
		if processOf(h) == pid && windows.IsWindowVisible(h) && className(h) == "#32768" {
			out = append(out, h)
		}
		return true
	})
	return out
}

func menusOf(pid uint32) []menuWindowInfo {
	out := []menuWindowInfo{}
	for _, h := range visibleMenuWindows(pid) {
		if info, ok := readMenuWindow(h); ok {
			out = append(out, info)
		}
	}
	return out
}

func trayNumber(id string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(id))
	return h.Sum32() | 1<<31
}

func findMyGoAppWindow(pid uint32) windows.HWND {
	var found windows.HWND
	enumTopWindows(func(h windows.HWND) bool {
		if processOf(h) == pid && className(h) == "MyGoApp" {
			found = h
			return false
		}
		return true
	})
	return found
}

func closeMenus(pid uint32, appWnd windows.HWND) error {
	deadline := time.Now().Add(2 * time.Second)
	for {
		wnds := visibleMenuWindows(pid)
		if len(wnds) == 0 {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("menu of pid %d did not close", pid)
		}
		for _, w := range wnds {
			procPostMessageW.Call(uintptr(w), wmKeyDown, vkEscape, 0)
			procPostMessageW.Call(uintptr(w), wmCancelMode, 0, 0)
		}
		if appWnd != 0 {
			procPostMessageW.Call(uintptr(appWnd), wmCancelMode, 0, 0)
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func waitForMenuWindow(pid uint32, exclude windows.HWND, timeout time.Duration, retryHover func()) (windows.HWND, menuWindowInfo, error) {
	start := time.Now()
	deadline := start.Add(timeout)
	nextRetry := start.Add(650 * time.Millisecond)
	for time.Now().Before(deadline) {
		for _, h := range visibleMenuWindows(pid) {
			if h == exclude {
				continue
			}
			info, ok := readMenuWindow(h)
			if ok && info.W > 0 && info.H > 0 && len(info.Items) > 0 {
				time.Sleep(40 * time.Millisecond)
				info, _ = readMenuWindow(h)
				return h, info, nil
			}
		}
		if retryHover != nil && time.Now().After(nextRetry) {
			retryHover()
			nextRetry = time.Now().Add(800 * time.Millisecond)
		}
		time.Sleep(25 * time.Millisecond)
	}
	return 0, menuWindowInfo{}, fmt.Errorf("timed out waiting for menu window of pid %d", pid)
}

func verifyTargetPID(x, y int32, pid uint32) error {
	h, _, _ := procWindowFromPoint.Call(point{X: x, Y: y}.byValue())
	if h == 0 {
		return fmt.Errorf("no window at (%d, %d)", x, y)
	}
	root := rootOf(windows.HWND(h))
	got := processOf(root)
	if got != pid {
		return fmt.Errorf("window at (%d, %d) belongs to pid %d (class %q, title %q), want %d",
			x, y, got, className(root), windowText(root), pid)
	}
	return nil
}

func safeMove(x, y int32, pid uint32) error {
	if err := verifyTargetPID(x, y, pid); err != nil {
		return err
	}
	moveMouse(x, y)
	return nil
}

func safeClick(x, y int32, pid uint32) error {
	if err := safeMove(x, y, pid); err != nil {
		return err
	}
	time.Sleep(20 * time.Millisecond)
	if err := verifyTargetPID(x, y, pid); err != nil {
		return err
	}
	sendInputs([]winInput{newMouseInput(0, 0, mouseeventfLeftDown)})
	time.Sleep(40 * time.Millisecond)
	sendInputs([]winInput{newMouseInput(0, 0, mouseeventfLeftUp)})
	return nil
}

func findMenuItem(items []menuItem, text string) (menuItem, bool) {
	for _, it := range items {
		if !it.Separator && it.Text == text {
			return it, true
		}
	}
	return menuItem{}, false
}

func menuItemLabels(items []menuItem) []string {
	var out []string
	for _, it := range items {
		if !it.Separator {
			out = append(out, it.Text)
		}
	}
	return out
}

func padRect(r rect, pad int32) rect {
	return clampRectToVirtualScreen(rect{
		Left:   r.Left - pad,
		Top:    r.Top - pad,
		Right:  r.Right + pad,
		Bottom: r.Bottom + pad,
	})
}

func menuBoundsRect(m menuWindowInfo) rect {
	return rect{
		Left:   int32(m.X),
		Top:    int32(m.Y),
		Right:  int32(m.X + m.W),
		Bottom: int32(m.Y + m.H),
	}
}

func unionRect(a, b rect) rect {
	return rect{
		Left:   min(a.Left, b.Left),
		Top:    min(a.Top, b.Top),
		Right:  max(a.Right, b.Right),
		Bottom: max(a.Bottom, b.Bottom),
	}
}

type trayResult struct {
	Menu    []menuItem `json:"Menu"`
	Submenu []menuItem `json:"Submenu"`
	Chose   string     `json:"Chose"`
}

func runTray(pid uint32, trayID, shotPath string, path []string) (trayResult, error) {
	appWnd := findMyGoAppWindow(pid)
	if appWnd == 0 {
		return trayResult{}, fmt.Errorf("no MyGoApp window found for pid %d", pid)
	}
	origCursor, hasOrig := cursorPos()
	defer func() {
		if !hasOrig {
			return
		}
		if cur, ok := cursorPos(); !ok || cur != origCursor {
			moveMouse(origCursor.X, origCursor.Y)
		}
	}()

	_ = closeMenus(pid, appWnd)
	if ok, _, err := procPostMessageW.Call(uintptr(appWnd), wmAppTray, uintptr(trayNumber(trayID)), wmRButtonUp); ok == 0 {
		return trayResult{}, fmt.Errorf("PostMessage to MyGoApp: %w", err)
	}

	mainWnd, mainMenu, err := waitForMenuWindow(pid, 0, 5*time.Second, nil)
	if err != nil {
		return trayResult{}, err
	}

	abort := func(cause error) (trayResult, error) {
		_ = closeMenus(pid, appWnd)
		return trayResult{}, cause
	}

	if len(path) == 0 {
		if shotPath != "" {
			if err := savePNG(padRect(menuBoundsRect(mainMenu), 16), shotPath); err != nil {
				return abort(err)
			}
		}
		if err := closeMenus(pid, appWnd); err != nil {
			return trayResult{}, err
		}
		return trayResult{Menu: mainMenu.Items, Submenu: nil, Chose: ""}, nil
	}

	itemName := path[0]
	target, ok := findMenuItem(mainMenu.Items, itemName)
	if !ok {
		return abort(fmt.Errorf("no item %q in %q", itemName, menuItemLabels(mainMenu.Items)))
	}
	if target.Disabled {
		return abort(fmt.Errorf("item %q is disabled", itemName))
	}
	cx := int32(target.X + target.W/2)
	cy := int32(target.Y + target.H/2)

	if len(path) == 1 && !target.Submenu {
		if shotPath != "" {
			if err := savePNG(padRect(menuBoundsRect(mainMenu), 16), shotPath); err != nil {
				return abort(err)
			}
		}
		if err := safeClick(cx, cy, pid); err != nil {
			return abort(err)
		}
		_ = waitMenusGone(pid, time.Second)
		return trayResult{Menu: mainMenu.Items, Submenu: nil, Chose: itemName}, nil
	}

	if !target.Submenu {
		return abort(fmt.Errorf("item %q has no submenu", itemName))
	}

	// Move across another spot inside the menu first so Windows delivers a real
	// WM_MOUSEMOVE onto the submenu item and starts its hover timer.
	startX, startY := max(int32(target.X)+4, cx-10), cy
	for _, other := range mainMenu.Items {
		if other.Index != target.Index && !other.Submenu && other.W > 4 && other.H > 4 {
			startX = int32(other.X + other.W/2)
			startY = int32(other.Y + other.H/2)
			break
		}
	}
	if err := safeMove(startX, startY, pid); err != nil {
		return abort(err)
	}
	time.Sleep(30 * time.Millisecond)
	if err := safeMove(cx, cy, pid); err != nil {
		return abort(err)
	}
	if target.W > 10 {
		time.Sleep(15 * time.Millisecond)
		_ = safeMove(cx+2, cy, pid)
		time.Sleep(15 * time.Millisecond)
		if err := safeMove(cx, cy, pid); err != nil {
			return abort(err)
		}
	}

	_, subMenu, err := waitForMenuWindow(pid, mainWnd, 5*time.Second, func() {
		if target.W > 10 {
			_ = safeMove(cx-2, cy, pid)
			time.Sleep(20 * time.Millisecond)
			_ = safeMove(cx, cy, pid)
		}
	})
	if err != nil {
		return abort(fmt.Errorf("submenu for %q did not open: %w", itemName, err))
	}

	if len(path) == 1 {
		// A submenu alone is listed and shown, then closed.
		if shotPath != "" {
			if err := savePNG(padRect(unionRect(menuBoundsRect(mainMenu), menuBoundsRect(subMenu)), 16), shotPath); err != nil {
				return abort(err)
			}
		}
		if err := closeMenus(pid, appWnd); err != nil {
			return trayResult{}, err
		}
		return trayResult{Menu: mainMenu.Items, Submenu: subMenu.Items}, nil
	}

	subName := path[1]
	subTarget, ok := findMenuItem(subMenu.Items, subName)
	if !ok {
		return abort(fmt.Errorf("no submenu item %q under %q in %q", subName, itemName, menuItemLabels(subMenu.Items)))
	}
	if subTarget.Disabled {
		return abort(fmt.Errorf("submenu item %q is disabled", subName))
	}

	if shotPath != "" {
		both := unionRect(menuBoundsRect(mainMenu), menuBoundsRect(subMenu))
		if err := savePNG(padRect(both, 16), shotPath); err != nil {
			return abort(err)
		}
	}

	// Slide horizontally into the submenu before moving vertically to the target item.
	enterX := int32(subMenu.X + subMenu.W/2)
	enterY := max(int32(subMenu.Y)+4, min(cy, int32(subMenu.Y+subMenu.H)-5))
	if err := safeMove(enterX, enterY, pid); err != nil {
		return abort(err)
	}
	time.Sleep(30 * time.Millisecond)

	subCX := int32(subTarget.X + subTarget.W/2)
	subCY := int32(subTarget.Y + subTarget.H/2)
	if err := safeClick(subCX, subCY, pid); err != nil {
		return abort(err)
	}
	_ = waitMenusGone(pid, time.Second)
	return trayResult{
		Menu:    mainMenu.Items,
		Submenu: subMenu.Items,
		Chose:   itemName + " > " + subName,
	}, nil
}

func waitMenusGone(pid uint32, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if len(visibleMenuWindows(pid)) == 0 {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return len(visibleMenuWindows(pid)) == 0
}
