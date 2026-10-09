package api

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
)

type fakeBackend struct {
	accts map[string]account.Account
}

func (f *fakeBackend) Upsert(a account.Account) (account.View, error) {
	if old, ok := f.accts[a.ID]; ok && a.Password == "" {
		a.Password = old.Password
	}
	if err := a.Normalize(); err != nil {
		return account.View{}, ErrInvalid{err}
	}
	f.accts[a.ID] = a
	return a.View(account.Status{State: "registering"}), nil
}
func (f *fakeBackend) Delete(id string) bool { _, ok := f.accts[id]; delete(f.accts, id); return ok }
func (f *fakeBackend) Get(id string) (account.View, bool) {
	a, ok := f.accts[id]
	return a.View(account.Status{}), ok
}
func (f *fakeBackend) List() []account.View {
	var out []account.View
	for _, a := range f.accts {
		out = append(out, a.View(account.Status{}))
	}
	return out
}
func (f *fakeBackend) Test(_ context.Context, id string) (bool, string, bool) {
	_, ok := f.accts[id]
	return false, "wrong username or password", ok
}
func (f *fakeBackend) WriteMetrics(w io.Writer) {
	(&metrics.Metrics{}).Write(w, metrics.Gauges{Accounts: len(f.accts)})
}

const tok = "0123456789abcdef-token"

func do(t *testing.T, h http.Handler, method, path, token, body string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.RemoteAddr = "10.0.0.5:1234"
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

func TestAPI(t *testing.T) {
	b := &fakeBackend{accts: map[string]account.Account{}}
	s := New(b, tok, &metrics.Metrics{}, slog.New(slog.DiscardHandler))

	if code, _ := do(t, s, "GET", "/healthz", "", ""); code != 200 {
		t.Fatalf("healthz %d", code)
	}
	if code, _ := do(t, s, "GET", "/v1/accounts", "", ""); code != 401 {
		t.Fatalf("no token: %d", code)
	}
	if code, _ := do(t, s, "GET", "/metrics", "", ""); code != 401 {
		t.Fatalf("metrics without token: %d", code)
	}

	good := `{"number":"+447700900123","domain":"sip.example.com","username":"alice","password":"hunter2","transport":"udp"}`
	code, body := do(t, s, "PUT", "/v1/accounts/line1", tok, good)
	if code != 200 || strings.Contains(body, "hunter2") || !strings.Contains(body, `"has_password": true`) {
		t.Fatalf("PUT: %d %s", code, body)
	}
	// Change without a password keeps it.
	code, _ = do(t, s, "PUT", "/v1/accounts/line1", tok, `{"number":"+447700900123","domain":"sip.example.com","username":"alice","mode":"off"}`)
	if code != 200 || b.accts["line1"].Password != "hunter2" || b.accts["line1"].Mode != "off" {
		t.Fatalf("update: %d %+v", code, b.accts["line1"])
	}
	for name, bad := range map[string]string{
		"invalid":       `{"number":"12","domain":"x","username":"u","password":"p"}`,
		"unknown field": `{"number":"+447700900123","domain":"x.com","username":"u","password":"p","colour":"red"}`,
		"not json":      `number=1`,
		"id mismatch":   `{"id":"other","number":"+447700900123","domain":"x.com","username":"u","password":"p"}`,
	} {
		if code, body := do(t, s, "PUT", "/v1/accounts/line2", tok, bad); code != 400 || !strings.Contains(body, "error") {
			t.Fatalf("%s: %d %s", name, code, body)
		}
	}
	if code, body := do(t, s, "GET", "/v1/accounts", tok, ""); code != 200 || strings.Contains(body, "hunter2") || !strings.Contains(body, "line1") {
		t.Fatalf("list: %d %s", code, body)
	}
	if code, body := do(t, s, "POST", "/v1/accounts/line1/test", tok, ""); code != 200 || !strings.Contains(body, "wrong username or password") {
		t.Fatalf("test: %d %s", code, body)
	}
	if code, _ := do(t, s, "POST", "/v1/accounts/nope/test", tok, ""); code != 404 {
		t.Fatal("test of unknown line")
	}
	if code, body := do(t, s, "GET", "/metrics", tok, ""); code != 200 || !strings.Contains(body, "sipgw_accounts 1") || !strings.Contains(body, "sipgw_active_calls") {
		t.Fatalf("metrics: %d %s", code, body)
	}
	if code, _ := do(t, s, "DELETE", "/v1/accounts/line1", tok, ""); code != 204 {
		t.Fatal("delete")
	}
	if code, _ := do(t, s, "GET", "/v1/accounts/line1", tok, ""); code != 404 {
		t.Fatal("get after delete")
	}
}

func TestWrongTokensAreRateLimited(t *testing.T) {
	m := &metrics.Metrics{}
	s := New(&fakeBackend{accts: map[string]account.Account{}}, tok, m, slog.New(slog.DiscardHandler))
	limited := false
	for i := range 20 {
		code, body := do(t, s, "GET", "/v1/accounts", fmt.Sprintf("guess-%d", i), "")
		if strings.Contains(body, tok) {
			t.Fatal("token echoed")
		}
		if code == 429 {
			limited = true
			break
		}
		if code != 401 {
			t.Fatalf("wrong token got %d", code)
		}
	}
	if !limited {
		t.Fatal("never rate limited")
	}
	// Even the right token waits now (from that address).
	if code, _ := do(t, s, "GET", "/v1/accounts", tok, ""); code != 429 {
		t.Fatalf("right token while blocked: %d", code)
	}
	if m.ControlAuthFailed.Load() < 10 {
		t.Fatal("failures not counted")
	}
}
