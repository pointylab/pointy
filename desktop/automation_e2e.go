//go:build e2e

package main

import (
	"fmt"
	"time"

	"github.com/egoist/mygo"
	_ "github.com/egoist/mygo/plugins/automation"
	"github.com/pointylab/pointy/desktop/internal/contract"
	"github.com/pointylab/pointy/desktop/internal/ui"
)

// E2E opens Pointy's windows on request, for tests driving the app through
// mygo-automation: `eval --window <e2e> "mygo.call('E2E.OpenGrab', grab)"`.
type E2E struct{}

func (E2E) OpenGrab(g contract.Grab) { windows.OpenGrab(g, nil) }
func (E2E) OpenPair(code string)     { windows.OpenCard(contract.CardInit{Mode: "pair", Code: code}, nil) }
func (E2E) ShowHint(text string)     { windows.ShowHint(text) }
func (E2E) ShowIntro()               { go windows.ShowIntro() }
func (E2E) ShowWelcome()             { go windows.ShowWelcome() }
func (E2E) ShowExtensionGuide()      { go windows.ShowExtensionGuide() }
func (E2E) ShowNotice(n contract.NoticeInit, ms int) {
	windows.ShowNotice(n, time.Duration(ms)*time.Millisecond)
}

var e2eOverlays []*ui.Overlay

// Overlay covers the display holding x, y with a pointing overlay and
// returns the bounds it asked for, to compare with where it lands.
func (E2E) Overlay(x, y int) mygo.Rectangle {
	b := mygo.Screen.DisplayNearestPoint(mygo.Point{X: x, Y: y}).Bounds
	e2eOverlays = append(e2eOverlays, windows.OpenOverlay(b))
	return b
}

func (E2E) CloseOverlays() {
	for _, o := range e2eOverlays {
		o.Close()
	}
	e2eOverlays = nil
}

// TrayItem describes an entry in the tray menu.
type TrayItem struct {
	Label     string     `json:"label"`
	Checked   bool       `json:"checked"`
	Disabled  bool       `json:"disabled"`
	Separator bool       `json:"separator"`
	Submenu   []TrayItem `json:"submenu"`
}

func trayItems(items []*mygo.MenuItem) []TrayItem {
	out := make([]TrayItem, 0, len(items))
	for _, it := range items {
		if it == nil || it.Hidden {
			continue
		}
		var sub []TrayItem
		if len(it.Submenu) > 0 {
			sub = trayItems(it.Submenu)
		}
		out = append(out, TrayItem{
			Label:     it.Label,
			Checked:   it.Checked,
			Disabled:  it.Disabled,
			Separator: it.Type == mygo.MenuItemSeparator,
			Submenu:   sub,
		})
	}
	return out
}

func (E2E) TrayMenu() []TrayItem {
	var out []TrayItem
	mygo.RunOnMain(func() {
		out = trayItems(appTray.Items())
	})
	return out
}

func (E2E) ChooseTray(path []string) string {
	if len(path) == 0 {
		return "empty path"
	}
	var errMsg string
	mygo.RunOnMain(func() {
		if appTray == nil {
			errMsg = "tray is not ready"
			return
		}
		items := appTray.Items()
		for i, want := range path {
			var found *mygo.MenuItem
			var labels []string
			for _, it := range items {
				if it == nil || it.Hidden || it.Type == mygo.MenuItemSeparator {
					continue
				}
				labels = append(labels, it.Label)
				if found == nil && it.Label == want {
					found = it
				}
			}
			if found == nil {
				errMsg = fmt.Sprintf("no item %q in %v", want, labels)
				return
			}
			if i < len(path)-1 {
				if len(found.Submenu) == 0 {
					errMsg = fmt.Sprintf("item %q has no submenu", want)
					return
				}
				items = found.Submenu
				continue
			}
			if len(found.Submenu) > 0 || found.Type == mygo.MenuItemSubmenu {
				errMsg = fmt.Sprintf("item %q is a submenu", want)
				return
			}
			if found.Disabled {
				errMsg = fmt.Sprintf("item %q is disabled", want)
				return
			}
			switch found.Type {
			case mygo.MenuItemCheckbox:
				found.Checked = !found.Checked
			case mygo.MenuItemRadio:
				found.Checked = true
			}
			if found.Click != nil {
				found.Click(found, nil)
			}
			appTray.Update()
		}
	})
	return errMsg
}

func init() {
	mygo.Bind(E2E{})
	mygo.App.WhenReady(func() {
		w := mygo.NewWindow(mygo.WindowOptions{Title: "e2e", Hidden: true, Width: 200, Height: 100})
		w.Page().LoadHTML("<!doctype html><title>e2e</title>", "")
	})
}
