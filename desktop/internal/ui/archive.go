package ui

import (
	"runtime"

	"github.com/pointylab/pointy/desktop/internal/config"
	"github.com/pointylab/pointy/desktop/internal/i18n"
)

// archiveSession ends a session Pointy started, so closing the card that
// asked in it leaves nothing behind in DSH's list. A session the user
// started is the plugin's to keep: it ignores the request. The tray turns
// the whole thing off.
func (u *UI) archiveSession(sessionID string) {
	if sessionID == "" || u.deps.Agent == nil || !autoArchives(u.deps.Settings) {
		return
	}
	if !u.deps.Agent.Archive(sessionID) {
		u.log("archive", "the plugin is not connected")
	}
}

// autoArchives reports whether closing a card archives its session; the
// setting is on until the user turns it off in the tray.
func autoArchives(settings *config.Store) bool {
	return settings == nil || settings.Get().AutoArchive
}

// OnArchived explains the first session Pointy archives: it leaves DSH's
// list without the user asking, so say where it went and how to stop it.
func (u *UI) OnArchived(sessionID string) {
	if text := u.archiveHint(sessionID); text != "" {
		u.ShowHint(text)
	}
}

// archiveHint is the one-time explanation for an archived session, or ""
// once the user has seen it.
func (u *UI) archiveHint(sessionID string) string {
	if sessionID == "" || u.deps.Settings == nil || u.deps.Settings.Get().ArchiveHinted {
		return ""
	}
	if err := u.deps.Settings.Update(func(s *config.Settings) { s.ArchiveHinted = true }); err != nil {
		u.log("settings", err)
		return ""
	}
	return i18n.T(archivedHint())
}

// archivedHint names where the setting lives: the menu bar on macOS, the
// system tray on Windows.
func archivedHint() i18n.Key {
	if runtime.GOOS == "darwin" {
		return i18n.HintArchivedMac
	}
	return i18n.HintArchivedWin
}
