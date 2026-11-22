package browser

import (
	"context"
	"encoding/json/v2"
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/pointylab/pointy/desktop/internal/config"
	"github.com/pointylab/pointy/desktop/internal/contract"
	"github.com/pointylab/pointy/desktop/internal/i18n"
	"github.com/pointylab/pointy/desktop/internal/server"
)

func sendSelection(raw string) (*contract.Grab, []string) {
	var got *contract.Grab
	var hints []string
	e := New(Deps{OnSelection: func(g contract.Grab) { got = &g }, ShowHint: func(h string) { hints = append(hints, h) }})
	(&handler{e: e}).OnMessage(server.Message{Type: "selection", Raw: []byte(raw)})
	return got, hints
}

func TestSelectionOpensACardOnTheText(t *testing.T) {
	g, hints := sendSelection(`{"type":"selection","browser":"chrome","url":"https://example.com/","pageTitle":"Example","text":"a paragraph"}`)
	if len(hints) > 0 {
		t.Errorf("hinted %q on an allowed selection", hints)
	}
	if g == nil {
		t.Fatal("no card opened")
	}
	if g.Text != "a paragraph" || g.Source != (contract.GrabSource{App: "chrome", Title: "Example"}) || g.Method != contract.MethodExtension {
		t.Fatalf("grab %+v", g)
	}
}

func TestSelectionFromAPasswordFieldOpensNothingAndSaysWhy(t *testing.T) {
	g, hints := sendSelection(`{"type":"selection","browser":"chrome","url":"https://example.com/","pageTitle":"Example","blocked":"password-field"}`)
	if g != nil {
		t.Fatalf("opened a card on %+v", g)
	}
	if want, _ := i18n.BlockHint(contract.BlockPasswordField); len(hints) != 1 || hints[0] != want {
		t.Fatalf("hints %q, want [%q]", hints, want)
	}
}

func TestSelectionOnALoginPageOpensNothing(t *testing.T) {
	for _, title := range []string{"Sign in - Google Accounts", "登录 - 网上银行"} {
		g, hints := sendSelection(`{"type":"selection","browser":"chrome","pageTitle":"` + title + `","text":"user@example.com"}`)
		if g != nil {
			t.Errorf("%s: opened a card on %+v", title, g)
		}
		if want, _ := i18n.BlockHint(contract.BlockLoginWindow); len(hints) != 1 || hints[0] != want {
			t.Errorf("%s: hints %q, want [%q]", title, hints, want)
		}
	}
}

func TestPickCancelCarriesThePagesBlockReason(t *testing.T) {
	e := New(Deps{})
	p := &picking{reqID: "r1", started: make(chan struct{}), reply: make(chan pickReply, 1)}
	e.picking = p
	(&handler{e: e}).OnMessage(server.Message{Type: "pick-cancel", Raw: []byte(`{"type":"pick-cancel","reqId":"r1","blocked":"password-field"}`)})
	select {
	case r := <-p.reply:
		if r.Blocked != contract.BlockPasswordField {
			t.Fatalf("blocked %q", r.Blocked)
		}
	default:
		t.Fatal("the cancel did not reach the pick")
	}
}

func TestAuthenticateReloadsOnlyUnpackedExtensions(t *testing.T) {
	home := t.TempDir()
	bundled := t.TempDir()
	if err := os.WriteFile(filepath.Join(bundled, "manifest.json"), []byte(`{"version":"0.4.3"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := config.SaveExtensionToken(home, "ext-1", "secret-token"); err != nil {
		t.Fatal(err)
	}
	e := New(Deps{Home: home, BundledDir: bundled})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go server.Serve(ln, server.Routes{Extension: e.Authenticate})

	connect := func(installType string) *websocket.Conn {
		t.Helper()
		ws, _, err := websocket.Dial(context.Background(), "ws://"+ln.Addr().String(), nil)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { ws.CloseNow() })
		readMsg := func(timeout time.Duration) (map[string]any, error) {
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			_, data, err := ws.Read(ctx)
			if err != nil {
				return nil, err
			}
			var m map[string]any
			if err := json.Unmarshal(data, &m); err != nil {
				return nil, err
			}
			return m, nil
		}
		ch, err := readMsg(2 * time.Second)
		if err != nil || ch["type"] != "challenge" {
			t.Fatalf("challenge %v err=%v", ch, err)
		}
		nonce, _ := ch["nonce"].(string)
		hello, _ := json.Marshal(map[string]any{
			"type":        "hello",
			"role":        "extension",
			"id":          "ext-1",
			"browser":     "chrome",
			"version":     "0.4.2",
			"installType": installType,
			"nonce":       "client-nonce",
			"proof":       server.Sign("secret-token", "ext|"+nonce),
		})
		if err := ws.Write(context.Background(), websocket.MessageText, hello); err != nil {
			t.Fatal(err)
		}
		ok, err := readMsg(2 * time.Second)
		if err != nil || ok["type"] != "hello-ok" {
			t.Fatalf("hello-ok %v err=%v", ok, err)
		}
		return ws
	}

	for _, installType := range []string{"development", ""} {
		ws := connect(installType)
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_, data, err := ws.Read(ctx)
		cancel()
		if err != nil {
			t.Fatalf("installType=%q: expected reload, got err=%v", installType, err)
		}
		var m map[string]any
		if err := json.Unmarshal(data, &m); err != nil || m["type"] != "reload" {
			t.Fatalf("installType=%q: got %v err=%v, want reload", installType, m, err)
		}
	}

	ws := connect("normal")
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	_, data, err := ws.Read(ctx)
	cancel()
	if err == nil {
		t.Fatalf("installType=normal: unexpected message %s", string(data))
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("installType=normal: read err=%v, want deadline exceeded", err)
	}
}
