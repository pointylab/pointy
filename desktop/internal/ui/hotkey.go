package ui

import (
	"sync"
	"sync/atomic"

	"github.com/pointylab/pointy/desktop/internal/config"
	"github.com/pointylab/pointy/desktop/internal/i18n"
)

// Hotkey binds the global shortcut in Settings, pauses it while the user
// records a new one, and reports whether binding it failed.
type Hotkey struct {
	settings   *config.Store
	register   func(acc string) error
	unregister func(acc string)
	log        func(kind string, err any)

	mu         sync.Mutex
	registered string
	taken      atomic.Bool // read by the tray on the main thread, which must never wait for mu
	recording  int
	listeners  []func()
}

func NewHotkey(s *config.Store, register func(string) error, unregister func(string), log func(string, any)) *Hotkey {
	return &Hotkey{settings: s, register: register, unregister: unregister, log: log}
}

// Taken reports whether the shortcut in Settings failed to register.
func (h *Hotkey) Taken() bool {
	if h == nil {
		return false
	}
	return h.taken.Load()
}

// OnChange calls fn after the shortcut or its status changes.
func (h *Hotkey) OnChange(fn func()) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.listeners = append(h.listeners, fn)
}

func (h *Hotkey) changed() {
	h.mu.Lock()
	fns := append([]func(){}, h.listeners...)
	h.mu.Unlock()
	for _, fn := range fns {
		fn()
	}
}

// Apply unregisters the previous shortcut and registers the one in Settings.
func (h *Hotkey) Apply() {
	if h == nil {
		return
	}
	h.mu.Lock()
	acc := h.settings.Get().Hotkey
	if h.recording > 0 {
		if h.registered != "" {
			h.unregister(h.registered)
			h.registered = ""
		}
		h.taken.Store(false)
		h.mu.Unlock()
		h.changed()
		return
	}
	if acc != "" && h.registered == acc && !h.taken.Load() {
		h.mu.Unlock()
		h.changed()
		return
	}
	if h.registered != "" {
		h.unregister(h.registered)
		h.registered = ""
	}
	if acc == "" {
		h.taken.Store(false)
		h.mu.Unlock()
		h.changed()
		return
	}
	if err := h.register(acc); err != nil {
		if h.log != nil {
			h.log("shortcut", err)
		}
		h.taken.Store(true)
		h.mu.Unlock()
		h.changed()
		return
	}
	h.registered = acc
	h.taken.Store(false)
	h.mu.Unlock()
	h.changed()
}

// Hold unregisters the active shortcut while the user records a new one, and
// returns what restores the shortcut from Settings once recording ends.
func (h *Hotkey) Hold() func() {
	if h == nil {
		return func() {}
	}
	h.mu.Lock()
	h.recording++
	if h.registered != "" {
		h.unregister(h.registered)
		h.registered = ""
	}
	h.mu.Unlock()
	var once sync.Once
	return func() {
		once.Do(func() {
			h.mu.Lock()
			h.recording--
			resume := h.recording == 0
			h.mu.Unlock()
			if resume {
				h.Apply()
			}
		})
	}
}

// Save tries to register acc; on success it writes acc to Settings and
// returns "", and on failure it leaves Settings unchanged and returns the
// error message for the recorder window.
func (h *Hotkey) Save(acc string) string {
	if h == nil || acc == "" {
		return i18n.T(i18n.HotkeyRecordTaken)
	}
	h.mu.Lock()
	if h.registered != "" {
		h.unregister(h.registered)
		h.registered = ""
	}
	if err := h.register(acc); err != nil {
		if h.log != nil {
			h.log("shortcut", err)
		}
		h.mu.Unlock()
		return i18n.T(i18n.HotkeyRecordTaken)
	}
	h.registered = acc
	h.taken.Store(false)
	err := h.settings.Update(func(s *config.Settings) { s.Hotkey = acc })
	h.mu.Unlock()
	if err != nil && h.log != nil {
		h.log("settings", err)
	}
	h.changed()
	return ""
}
