//go:build windows

package main

import (
	"errors"
	"fmt"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

func captureScreenImage(r rect) (*image.RGBA, error) {
	w := int(r.Right - r.Left)
	h := int(r.Bottom - r.Top)
	if w <= 0 || h <= 0 {
		return nil, fmt.Errorf("invalid capture size %dx%d", w, h)
	}
	screenDC, _, _ := procGetDC.Call(0)
	if screenDC == 0 {
		return nil, errors.New("GetDC(0) failed")
	}
	defer procReleaseDC.Call(0, screenDC)

	memDC, _, _ := procCreateCompatibleDC.Call(screenDC)
	if memDC == 0 {
		return nil, errors.New("CreateCompatibleDC failed")
	}
	defer procDeleteDC.Call(memDC)

	bmp, _, err := procCreateCompatibleBitmap.Call(screenDC, uintptr(w), uintptr(h))
	if bmp == 0 {
		return nil, fmt.Errorf("CreateCompatibleBitmap: %w", err)
	}
	defer procDeleteObject.Call(bmp)

	old, _, _ := procSelectObject.Call(memDC, bmp)
	ok, _, bitErr := procBitBlt.Call(memDC, 0, 0, uintptr(w), uintptr(h), screenDC, uintptr(r.Left), uintptr(r.Top), srcCopyCaptureBlt)
	// GetDIBits requires the bitmap not to be selected into a DC.
	procSelectObject.Call(memDC, old)
	if ok == 0 {
		return nil, fmt.Errorf("BitBlt: %w", bitErr)
	}

	bi := bitmapInfoHeader{
		Size:     uint32(unsafe.Sizeof(bitmapInfoHeader{})),
		Width:    int32(w),
		Height:   -int32(h), // top-down DIB
		Planes:   1,
		BitCount: 32,
	}
	buf := make([]byte, w*h*4)
	lines, _, dibErr := procGetDIBits.Call(memDC, bmp, 0, uintptr(h), uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&bi)), 0)
	if lines == 0 {
		return nil, fmt.Errorf("GetDIBits: %w", dibErr)
	}

	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for i := 0; i < len(buf); i += 4 {
		img.Pix[i+0] = buf[i+2]
		img.Pix[i+1] = buf[i+1]
		img.Pix[i+2] = buf[i+0]
		img.Pix[i+3] = 255
	}
	return img, nil
}

func savePNG(r rect, outPath string) error {
	img, err := captureScreenImage(r)
	if err != nil {
		return err
	}
	if dir := filepath.Dir(outPath); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	if err := png.Encode(f, img); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func shotWindowPNG(hwnd windows.HWND, outPath string, pad int32) error {
	if ok, _, _ := procIsWindow.Call(uintptr(hwnd)); ok == 0 {
		return fmt.Errorf("invalid window handle %d", hwnd)
	}
	r, ok := extendedFrameRect(hwnd)
	if !ok || r.Right <= r.Left || r.Bottom <= r.Top {
		return fmt.Errorf("cannot read bounds for window %d", hwnd)
	}
	r.Left -= pad
	r.Top -= pad
	r.Right += pad
	r.Bottom += pad
	r = clampRectToVirtualScreen(r)
	return savePNG(r, outPath)
}
