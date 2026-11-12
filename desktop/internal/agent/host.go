package agent

import (
	"encoding/json/v2"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const orphanPoll = 5 * time.Second

// Variables so tests can shorten them.
var (
	quitGrace = 10 * time.Second
	// DSH updates a plugin by removing it and then installing the new
	// version, which can take a while to download. A plugin that looks
	// removed gets this long to come back before Pointy quits and cleans up.
	removalGrace = 2 * time.Minute
	removalPoll  = 2 * time.Second
)

// HostOptions describe how DSH runs Pointy.
type HostOptions struct {
	// Managed is POINTY_MANAGED: DSH started Pointy, and Pointy quits
	// without it.
	Managed bool
	// HostPID is POINTY_HOST_PID, the DSH process.
	HostPID int
	// PluginRoot is the plugin's install directory (POINTY_PLUGIN_ROOT, or
	// inferred from the executable path).
	PluginRoot string
	// Cleanup lists what goes with the plugin: Pointy's home and data.
	Cleanup []string
	// RemoveAfterExit deletes paths once Pointy has exited.
	RemoveAfterExit func([]string) error
	Quit            func()
}

type host struct {
	opts      HostOptions
	connected func() bool
	log       func(string, any)

	mu   sync.Mutex
	quit *time.Timer
}

func newHost(o HostOptions, connected func() bool, log func(string, any)) *host {
	if log == nil {
		log = func(string, any) {}
	}
	if o.Quit == nil {
		o.Quit = func() {}
	}
	h := &host{opts: o, connected: connected, log: log}
	if o.Managed && o.HostPID > 0 {
		go func() {
			for range time.Tick(orphanPoll) {
				if h.orphaned() {
					h.log("orphan", fmt.Sprintf("DSH host %d is gone and no plugin is connected; quitting", o.HostPID))
					o.Quit()
					return
				}
			}
		}()
	}
	return h
}

func (h *host) orphaned() bool { return !h.connected() && !processAlive(h.opts.HostPID) }

func (h *host) linked() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.quit != nil {
		h.quit.Stop()
	}
}

func (h *host) unlinked(everConnected bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.quit != nil {
		h.quit.Stop()
	}
	if everConnected && h.opts.Managed {
		deadline := time.Now().Add(removalGrace)
		var check func()
		check = func() {
			if h.connected() {
				return
			}
			if h.uninstalled() && time.Now().Before(deadline) {
				h.mu.Lock()
				h.quit = time.AfterFunc(removalPoll, check)
				h.mu.Unlock()
				return
			}
			h.opts.Quit()
		}
		h.quit = time.AfterFunc(quitGrace, check)
	}
}

const pluginPackage = "@pointylab/dsh"

var pluginDir = regexp.MustCompile(`(?i)[\\/]node_modules[\\/]@pointylab[\\/]dsh$`)

// uninstalled reports whether DSH removed the plugin: its package.json is
// gone and the profile manifest no longer lists @pointylab/dsh (a failed
// in-place update can leave the package directory without package.json while
// the dependency remains in the manifest).
func (h *host) uninstalled() bool {
	if h.opts.PluginRoot == "" {
		return false
	}
	root := filepath.Clean(h.opts.PluginRoot)
	if !pluginDir.MatchString(root) {
		return false
	}
	if _, err := os.Stat(filepath.Join(root, "package.json")); !os.IsNotExist(err) {
		return false
	}
	manifest := filepath.Join(root, "..", "..", "..", "package.json")
	return !hasPluginDep(manifest)
}

func hasPluginDep(manifest string) bool {
	b, err := os.ReadFile(manifest)
	if err != nil {
		return false
	}
	var pkg struct {
		Dependencies         map[string]any `json:"dependencies"`
		DevDependencies      map[string]any `json:"devDependencies"`
		OptionalDependencies map[string]any `json:"optionalDependencies"`
	}
	if json.Unmarshal(b, &pkg) != nil {
		return false
	}
	_, dep := pkg.Dependencies[pluginPackage]
	_, dev := pkg.DevDependencies[pluginPackage]
	_, opt := pkg.OptionalDependencies[pluginPackage]
	return dep || dev || opt
}

func (h *host) willQuit() {
	if !h.opts.Managed || !h.uninstalled() || h.opts.RemoveAfterExit == nil {
		return
	}
	var targets []string
	for _, p := range append(h.opts.Cleanup, h.opts.PluginRoot) {
		if _, err := os.Stat(p); err == nil {
			targets = append(targets, p)
		}
	}
	h.log("uninstall", "plugin removed; cleaning "+strings.Join(targets, ", "))
	if err := h.opts.RemoveAfterExit(targets); err != nil {
		h.log("uninstall", err)
	}
}

// FindPluginRoot returns the plugin directory that holds exe, or "".
func FindPluginRoot(exe string) string {
	for dir := filepath.Dir(exe); ; {
		if pluginDir.MatchString(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}
