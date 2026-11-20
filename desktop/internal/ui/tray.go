package ui

import (
	"runtime"
	"slices"
	"strings"

	"github.com/egoist/mygo"
	"github.com/pointylab/pointy/desktop/internal/agent"
	"github.com/pointylab/pointy/desktop/internal/config"
	"github.com/pointylab/pointy/desktop/internal/i18n"
)

var presetHotkeys = []string{
	"CmdOrCtrl+Alt+P",
	"Alt+Shift+Space",
	"CmdOrCtrl+Shift+Space",
}

// TrayDeps are what the menu bar icon shows and does.
type TrayDeps struct {
	Settings           *config.Store
	Visibility         *Visibility
	Agent              func() agent.Status
	Extensions         func() int
	ShowExtensionGuide func()
	ShowWelcome        func()
	ShowHotkeyRecorder func()
	// LocaleChanged follows the language the user chose in Settings.
	LocaleChanged func()
	// HotkeyChanged rebinds the shortcut the user chose in Settings.
	HotkeyChanged func()
	// HotkeyTaken reports whether the shortcut in Settings failed to register.
	HotkeyTaken func() bool
	Quit        func()
	Log         func(kind string, err any)
}

// Tray is the whale in the menu bar.
type Tray struct {
	deps TrayDeps
	tray *mygo.Tray
}

// NewTray adds the icon; icon is a PNG.
func NewTray(d TrayDeps, icon []byte) (*Tray, error) {
	t := &Tray{deps: d}
	tray, err := mygo.NewTray(mygo.TrayOptions{ID: "pointy", Icon: icon, ToolTip: "Pointy"})
	if err != nil {
		return nil, err
	}
	t.tray = tray
	t.Update()
	return t, nil
}

// Update redraws the tooltip and the menu from the current state.
func (t *Tray) Update() {
	if t == nil {
		return
	}
	tip, items := trayContent(t.deps)
	t.tray.SetToolTip(tip)
	t.tray.SetMenu(mygo.NewMenu(items))
}

// Items builds the menu items from the current state, as opening the menu sees them.
func (t *Tray) Items() []*mygo.MenuItem {
	if t == nil {
		return nil
	}
	_, items := trayContent(t.deps)
	return items
}

func trayContent(d TrayDeps) (string, []*mygo.MenuItem) {
	st := d.Agent()
	s := d.Settings.Get()
	ext := d.Extensions()
	var status []string
	if st.PendingApprovals > 0 {
		status = append(status, i18n.T(i18n.TrayApprovals, "count", st.PendingApprovals))
	}
	if s.DND {
		status = append(status, i18n.T(i18n.TrayDNDOn))
	}
	if s.Hotkey != "" && d.HotkeyTaken != nil && d.HotkeyTaken() {
		status = append(status, i18n.T(i18n.TrayHotkeyTaken, "hotkey", formatHotkey(s.Hotkey, runtime.GOOS)))
	}
	if !st.Connected {
		status = append(status, i18n.T(i18n.TrayAgentOffline, "agent", agent.Name))
	}
	if ext == 0 {
		status = append(status, i18n.T(i18n.TrayExtensionOffline))
	}
	tip := "Pointy"
	if len(status) > 0 {
		tip += "\n" + strings.Join(status, "\n")
	}

	save := func(change func(*config.Settings)) {
		if err := d.Settings.Update(change); err != nil && d.Log != nil {
			d.Log("settings", err)
		}
	}
	shake := []*mygo.MenuItem{{Label: i18n.T(i18n.TrayShakeOff), Type: mygo.MenuItemRadio, Checked: !s.Shake, Click: func(*mygo.MenuItem, *mygo.Window) {
		save(func(s *config.Settings) { s.Shake = false })
		d.Visibility.Changed()
	}}}
	for _, l := range []struct {
		level config.ShakeLevel
		label i18n.Key
	}{{config.ShakeLow, i18n.TrayShakeLow}, {config.ShakeMedium, i18n.TrayShakeMedium}, {config.ShakeHigh, i18n.TrayShakeHigh}} {
		shake = append(shake, &mygo.MenuItem{Label: i18n.T(l.label), Type: mygo.MenuItemRadio, Checked: s.Shake && s.ShakeLevel == l.level, Click: func(*mygo.MenuItem, *mygo.Window) {
			save(func(s *config.Settings) { s.Shake, s.ShakeLevel = true, l.level })
			d.Visibility.Changed()
		}})
	}
	// Binding a shortcut waits for the main thread, so it runs off it.
	hotkeyChanged := func() {
		if d.HotkeyChanged != nil {
			go d.HotkeyChanged()
		}
	}
	hotkey := []*mygo.MenuItem{{Label: i18n.T(i18n.TrayHotkeyOff), Type: mygo.MenuItemRadio, Checked: s.Hotkey == "", Click: func(*mygo.MenuItem, *mygo.Window) {
		save(func(s *config.Settings) { s.Hotkey = "" })
		hotkeyChanged()
	}}}
	hotkeys := slices.Clone(presetHotkeys)
	if s.Hotkey != "" && !slices.ContainsFunc(hotkeys, func(p string) bool { return sameHotkey(p, s.Hotkey, runtime.GOOS) }) {
		hotkeys = append(hotkeys, s.Hotkey)
	}
	for _, acc := range hotkeys {
		hotkey = append(hotkey, &mygo.MenuItem{Label: formatHotkey(acc, runtime.GOOS), Type: mygo.MenuItemRadio, Checked: sameHotkey(s.Hotkey, acc, runtime.GOOS), Click: func(*mygo.MenuItem, *mygo.Window) {
			save(func(s *config.Settings) { s.Hotkey = acc })
			hotkeyChanged()
		}})
	}
	hotkey = append(hotkey,
		mygo.Separator(),
		&mygo.MenuItem{Label: i18n.T(i18n.TrayHotkeyCustom), Click: func(*mygo.MenuItem, *mygo.Window) {
			if d.ShowHotkeyRecorder != nil {
				go d.ShowHotkeyRecorder()
			}
		}},
	)
	languages := []*mygo.MenuItem{{Label: i18n.T(i18n.LanguageSystem), Type: mygo.MenuItemRadio, Checked: s.Locale == "", Click: func(*mygo.MenuItem, *mygo.Window) {
		save(func(s *config.Settings) { s.Locale = "" })
		d.LocaleChanged()
	}}}
	for _, lang := range i18n.Languages {
		languages = append(languages, &mygo.MenuItem{Label: i18n.In(lang, i18n.LanguageSelf), Type: mygo.MenuItemRadio, Checked: s.Locale == lang, Click: func(*mygo.MenuItem, *mygo.Window) {
			save(func(s *config.Settings) { s.Locale = lang })
			d.LocaleChanged()
		}})
	}
	extItem := &mygo.MenuItem{Label: i18n.T(i18n.TrayExtensionConnected, "count", ext), Disabled: true}
	if ext == 0 {
		extItem = &mygo.MenuItem{Label: i18n.T(i18n.TrayExtensionInstall), Click: func(*mygo.MenuItem, *mygo.Window) { go d.ShowExtensionGuide() }}
	}
	return tip, []*mygo.MenuItem{
		{Label: i18n.T(i18n.TrayShake), Submenu: shake},
		{Label: i18n.T(i18n.TrayHotkey), Submenu: hotkey},
		extItem,
		mygo.Separator(),
		{Label: i18n.T(i18n.TrayGuide), Click: func(*mygo.MenuItem, *mygo.Window) { go d.ShowWelcome() }},
		{Label: i18n.T(i18n.TrayDND), Type: mygo.MenuItemCheckbox, Checked: s.DND, Click: func(item *mygo.MenuItem, _ *mygo.Window) {
			save(func(s *config.Settings) { s.DND = item.Checked })
			d.Visibility.Changed()
		}},
		{Label: i18n.T(i18n.TrayAutoArchive), Type: mygo.MenuItemCheckbox, Checked: s.AutoArchive, Click: func(item *mygo.MenuItem, _ *mygo.Window) {
			save(func(s *config.Settings) { s.AutoArchive = item.Checked })
		}},
		{Label: i18n.T(i18n.LanguageMenu), Submenu: languages},
		mygo.Separator(),
		{Label: i18n.T(i18n.TrayQuit), Click: func(*mygo.MenuItem, *mygo.Window) { d.Quit() }},
	}
}

// Notify shows a system notification, unless Pointy keeps out of sight.
// macOS shows them only for a packaged app.
func (t *Tray) Notify(title, body string, onClick func()) {
	if t == nil || t.deps.Visibility.Suppressed() {
		return
	}
	go func() {
		if !mygo.NotificationsSupported() {
			t.log("notify", "notifications need a packaged app: "+title)
			return
		}
		n := mygo.NewNotification(mygo.NotificationOptions{Title: title, Body: body, Silent: true})
		if onClick != nil {
			n.OnClick(onClick)
		}
		if err := n.Show(); err != nil {
			t.log("notify", err)
		}
	}()
}

func (t *Tray) log(kind string, err any) {
	if t.deps.Log != nil {
		t.deps.Log(kind, err)
	}
}

func sameHotkey(a, b, goos string) bool {
	return a != "" && b != "" && (a == b || formatHotkey(a, goos) == formatHotkey(b, goos))
}

// formatHotkey spells an accelerator as menus on goos do.
func formatHotkey(acc, goos string) string {
	if acc == "" || acc == "+" {
		return acc
	}
	parts := strings.Split(acc, "+")
	if strings.HasSuffix(acc, "++") {
		parts = append(parts[:len(parts)-2], "+")
	}
	key := strings.TrimSpace(parts[len(parts)-1])
	if len([]rune(key)) == 1 {
		key = strings.ToUpper(key)
	}
	mods := parts[:len(parts)-1]
	if goos == "darwin" {
		var b strings.Builder
		for _, raw := range mods {
			switch strings.ToLower(strings.TrimSpace(raw)) {
			case "cmdorctrl", "commandorcontrol", "cmd", "command", "super", "meta":
				b.WriteString("⌘")
			case "ctrl", "control":
				b.WriteString("⌃")
			case "alt", "option", "altgr":
				b.WriteString("⌥")
			case "shift":
				b.WriteString("⇧")
			default:
				b.WriteString(strings.TrimSpace(raw) + "+")
			}
		}
		b.WriteString(key)
		return b.String()
	}
	out := make([]string, 0, len(parts))
	for _, raw := range mods {
		m := strings.TrimSpace(raw)
		switch strings.ToLower(m) {
		case "cmdorctrl", "commandorcontrol", "ctrl", "control":
			m = "Ctrl"
		case "alt", "option":
			m = "Alt"
		case "shift":
			m = "Shift"
		}
		out = append(out, m)
	}
	return strings.Join(append(out, key), "+")
}
