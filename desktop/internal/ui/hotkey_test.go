package ui

import (
	"errors"
	"testing"

	"github.com/pointylab/pointy/desktop/internal/config"
)

func TestHotkeySaveWritesSettingsAndRegisters(t *testing.T) {
	settings := config.LoadSettings(t.TempDir())
	active := map[string]bool{}
	changes := 0
	h := NewHotkey(
		settings,
		func(acc string) error { active[acc] = true; return nil },
		func(acc string) { delete(active, acc) },
		nil,
	)
	h.OnChange(func() { changes++ })

	release := h.Hold()
	if msg := h.Save("Ctrl+Alt+K"); msg != "" {
		t.Fatalf("Save returned %q, want empty", msg)
	}
	release()

	if got := settings.Get().Hotkey; got != "Ctrl+Alt+K" {
		t.Fatalf("settings hotkey %q, want Ctrl+Alt+K", got)
	}
	if !active["Ctrl+Alt+K"] || len(active) != 1 || h.Taken() || changes == 0 {
		t.Fatalf("active %v taken %v changes %d", active, h.Taken(), changes)
	}
}

func TestHotkeySaveFailureKeepsSettingsAndRestoresAfterRecord(t *testing.T) {
	settings := config.LoadSettings(t.TempDir())
	settings.Update(func(s *config.Settings) { s.Hotkey = "Alt+Shift+Space" })
	active := map[string]bool{}
	h := NewHotkey(
		settings,
		func(acc string) error {
			if acc == "Ctrl+Alt+P" {
				return errors.New("taken")
			}
			active[acc] = true
			return nil
		},
		func(acc string) { delete(active, acc) },
		nil,
	)
	h.Apply()
	if !active["Alt+Shift+Space"] {
		t.Fatal("initial hotkey not registered")
	}

	release := h.Hold()
	if len(active) != 0 {
		t.Fatalf("hotkey stayed registered during recording: %v", active)
	}
	msg := h.Save("Ctrl+Alt+P")
	if msg != "这个组合被其他程序占用了，换一个" {
		t.Fatalf("Save error %q", msg)
	}
	if got := settings.Get().Hotkey; got != "Alt+Shift+Space" {
		t.Fatalf("settings changed on failed Save: %q", got)
	}
	release()
	if !active["Alt+Shift+Space"] || h.Taken() {
		t.Fatalf("original hotkey not restored after cancel: active %v taken %v", active, h.Taken())
	}
}
