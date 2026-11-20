//go:build windows

package main

import (
	"sync"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	user32   = windows.NewLazySystemDLL("user32.dll")
	gdi32    = windows.NewLazySystemDLL("gdi32.dll")
	kernel32 = windows.NewLazySystemDLL("kernel32.dll")
	dwmapi   = windows.NewLazySystemDLL("dwmapi.dll")

	procSetProcessDpiAwarenessContext = user32.NewProc("SetProcessDpiAwarenessContext")
	procSetProcessDPIAware            = user32.NewProc("SetProcessDPIAware")
	procGetSystemMetrics              = user32.NewProc("GetSystemMetrics")
	procSendInput                     = user32.NewProc("SendInput")
	procGetCursorPos                  = user32.NewProc("GetCursorPos")
	procWindowFromPoint               = user32.NewProc("WindowFromPoint")
	procGetAncestor                   = user32.NewProc("GetAncestor")
	procGetWindowRect                 = user32.NewProc("GetWindowRect")
	procGetWindowTextW                = user32.NewProc("GetWindowTextW")
	procIsWindow                      = user32.NewProc("IsWindow")
	procIsIconic                      = user32.NewProc("IsIconic")
	procShowWindow                    = user32.NewProc("ShowWindow")
	procSetForegroundWindow           = user32.NewProc("SetForegroundWindow")
	procBringWindowToTop              = user32.NewProc("BringWindowToTop")
	procAttachThreadInput             = user32.NewProc("AttachThreadInput")
	procGetLastInputInfo              = user32.NewProc("GetLastInputInfo")
	procOpenInputDesktop              = user32.NewProc("OpenInputDesktop")
	procSwitchDesktop                 = user32.NewProc("SwitchDesktop")
	procCloseDesktop                  = user32.NewProc("CloseDesktop")
	procEnumDisplayMonitors           = user32.NewProc("EnumDisplayMonitors")
	procGetMonitorInfoW               = user32.NewProc("GetMonitorInfoW")
	procSendMessageW                  = user32.NewProc("SendMessageW")
	procPostMessageW                  = user32.NewProc("PostMessageW")
	procGetMenuItemCount              = user32.NewProc("GetMenuItemCount")
	procGetMenuItemInfoW              = user32.NewProc("GetMenuItemInfoW")
	procGetMenuItemRect               = user32.NewProc("GetMenuItemRect")
	procMapVirtualKeyW                = user32.NewProc("MapVirtualKeyW")
	procVkKeyScanW                    = user32.NewProc("VkKeyScanW")
	procGetDC                         = user32.NewProc("GetDC")
	procReleaseDC                     = user32.NewProc("ReleaseDC")

	procCreateCompatibleDC     = gdi32.NewProc("CreateCompatibleDC")
	procDeleteDC               = gdi32.NewProc("DeleteDC")
	procCreateCompatibleBitmap = gdi32.NewProc("CreateCompatibleBitmap")
	procDeleteObject           = gdi32.NewProc("DeleteObject")
	procSelectObject           = gdi32.NewProc("SelectObject")
	procBitBlt                 = gdi32.NewProc("BitBlt")
	procGetDIBits              = gdi32.NewProc("GetDIBits")

	procGetTickCount = kernel32.NewProc("GetTickCount")
)

const (
	dpiAwarenessPerMonitorV2 = ^uintptr(3) // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (-4)

	smXVirtualScreen  = 76
	smYVirtualScreen  = 77
	smCXVirtualScreen = 78
	smCYVirtualScreen = 79

	gaRoot = 2

	swRestore = 9

	desktopSwitchDesktop = 0x0100

	monitorInfoPrimary = 1

	dwmwaExtendedFrameBounds = 9
	dwmwaCloaked             = 14

	inputMouse    = 0
	inputKeyboard = 1

	mouseeventfMove        = 0x0001
	mouseeventfLeftDown    = 0x0002
	mouseeventfLeftUp      = 0x0004
	mouseeventfRightDown   = 0x0008
	mouseeventfRightUp     = 0x0010
	mouseeventfVirtualDesk = 0x4000
	mouseeventfAbsolute    = 0x8000

	keyeventfExtendedKey = 0x0001
	keyeventfKeyUp       = 0x0002
	keyeventfUnicode     = 0x0004

	mapvkVkToVsc = 0

	wmCancelMode = 0x001F
	wmKeyDown    = 0x0100
	wmRButtonUp  = 0x0205
	wmAppTray    = 0x8003
	mnGetHMenu   = 0x01E1

	vkEscape = 0x1B

	miimState   = 0x0001
	miimSubMenu = 0x0004
	miimString  = 0x0040
	miimFType   = 0x0100

	mftSeparator = 0x0800
	mfsDisabled  = 0x0003
	mfsChecked   = 0x0008

	srcCopyCaptureBlt = 0x00CC0020 | 0x40000000
)

type point struct{ X, Y int32 }

func (p point) byValue() uintptr {
	return uintptr(uint32(p.X)) | uintptr(uint32(p.Y))<<32
}

type rect struct{ Left, Top, Right, Bottom int32 }

type monitorInfo struct {
	Size    uint32
	Monitor rect
	Work    rect
	Flags   uint32
}

type mouseInput struct {
	Dx        int32
	Dy        int32
	MouseData uint32
	Flags     uint32
	Time      uint32
	ExtraInfo uintptr
}

type keybdInput struct {
	Vk        uint16
	Scan      uint16
	Flags     uint32
	Time      uint32
	ExtraInfo uintptr
}

// winInput matches Win32 INPUT (40 bytes on 64-bit Windows, 28 on 32-bit).
type winInput struct {
	Type uint32
	mi   mouseInput
}

var _ = [1]struct{}{}[unsafe.Sizeof(winInput{})-(16+3*unsafe.Sizeof(uintptr(0)))]

type lastInputInfo struct {
	Size uint32
	Time uint32
}

type menuItemInfo struct {
	Size         uint32
	Mask         uint32
	Type         uint32
	State        uint32
	ID           uint32
	SubMenu      uintptr
	BmpChecked   uintptr
	BmpUnchecked uintptr
	ItemData     uintptr
	TypeData     *uint16
	Cch          uint32
	BmpItem      uintptr
}

type bitmapInfoHeader struct {
	Size          uint32
	Width         int32
	Height        int32
	Planes        uint16
	BitCount      uint16
	Compression   uint32
	SizeImage     uint32
	XPelsPerMeter int32
	YPelsPerMeter int32
	ClrUsed       uint32
	ClrImportant  uint32
}

func initDPI() {
	if procSetProcessDpiAwarenessContext.Find() == nil {
		if ok, _, _ := procSetProcessDpiAwarenessContext.Call(dpiAwarenessPerMonitorV2); ok != 0 {
			return
		}
	}
	if procSetProcessDPIAware.Find() == nil {
		procSetProcessDPIAware.Call()
	}
}

func systemMetric(idx uintptr) int32 {
	v, _, _ := procGetSystemMetrics.Call(idx)
	return int32(v)
}

func virtualScreen() rect {
	x := systemMetric(smXVirtualScreen)
	y := systemMetric(smYVirtualScreen)
	w := systemMetric(smCXVirtualScreen)
	h := systemMetric(smCYVirtualScreen)
	return rect{Left: x, Top: y, Right: x + w, Bottom: y + h}
}

func clampRectToVirtualScreen(r rect) rect {
	vs := virtualScreen()
	if vs.Right <= vs.Left || vs.Bottom <= vs.Top {
		return r
	}
	if r.Left < vs.Left {
		r.Left = vs.Left
	}
	if r.Top < vs.Top {
		r.Top = vs.Top
	}
	if r.Right > vs.Right {
		r.Right = vs.Right
	}
	if r.Bottom > vs.Bottom {
		r.Bottom = vs.Bottom
	}
	return r
}

func windowText(h windows.HWND) string {
	var buf [512]uint16
	n, _, _ := procGetWindowTextW.Call(uintptr(h), uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	return windows.UTF16ToString(buf[:n])
}

func className(h windows.HWND) string {
	var buf [256]uint16
	n, _ := windows.GetClassName(h, &buf[0], int32(len(buf)))
	return windows.UTF16ToString(buf[:n])
}

func rootOf(h windows.HWND) windows.HWND {
	r, _, _ := procGetAncestor.Call(uintptr(h), gaRoot)
	if r == 0 {
		return h
	}
	return windows.HWND(r)
}

func windowRect(h windows.HWND) (rect, bool) {
	var r rect
	ok, _, _ := procGetWindowRect.Call(uintptr(h), uintptr(unsafe.Pointer(&r)))
	return r, ok != 0
}

func extendedFrameRect(h windows.HWND) (rect, bool) {
	var r rect
	err := windows.DwmGetWindowAttribute(h, dwmwaExtendedFrameBounds, unsafe.Pointer(&r), uint32(unsafe.Sizeof(r)))
	if err == nil && r.Right > r.Left && r.Bottom > r.Top {
		return r, true
	}
	return windowRect(h)
}

func processOf(h windows.HWND) uint32 {
	var pid uint32
	windows.GetWindowThreadProcessId(h, &pid)
	return pid
}

func cloaked(h windows.HWND) bool {
	var c uint32
	return windows.DwmGetWindowAttribute(h, dwmwaCloaked, unsafe.Pointer(&c), uint32(unsafe.Sizeof(c))) == nil && c != 0
}

func cursorPos() (point, bool) {
	var p point
	ok, _, _ := procGetCursorPos.Call(uintptr(unsafe.Pointer(&p)))
	return p, ok != 0
}

var (
	enumWinMu   sync.Mutex
	enumWinSink func(windows.HWND) bool
	enumWinCB   = syscall.NewCallback(func(h windows.HWND, _ uintptr) uintptr {
		if enumWinSink(h) {
			return 1
		}
		return 0
	})
)

func enumTopWindows(visit func(windows.HWND) bool) {
	enumWinMu.Lock()
	defer enumWinMu.Unlock()
	enumWinSink = visit
	windows.EnumWindows(enumWinCB, nil)
	enumWinSink = nil
}

var (
	enumMonMu   sync.Mutex
	enumMonSink func(uintptr)
	enumMonCB   = syscall.NewCallback(func(m, _, _, _ uintptr) uintptr {
		enumMonSink(m)
		return 1
	})
)

func enumMonitors(visit func(uintptr)) {
	enumMonMu.Lock()
	defer enumMonMu.Unlock()
	enumMonSink = visit
	procEnumDisplayMonitors.Call(0, 0, enumMonCB, 0)
	enumMonSink = nil
}
