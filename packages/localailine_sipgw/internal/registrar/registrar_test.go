package registrar

import (
	"errors"
	"log/slog"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
)

type addressing struct{}

func (addressing) PublicHost() string               { return "127.0.0.1" }
func (addressing) ContactPort(transport string) int { return 5070 }
func (addressing) UDPLaddr() *sip.Addr              { return nil }

// A registrar that answers from a script: each REGISTER gets the next answer.
type scripted struct {
	mu      sync.Mutex
	answers []func(*sip.Request) *sip.Response
	got     []*sip.Request
	times   []time.Time
}

func (s *scripted) handle(req *sip.Request, tx sip.ServerTransaction) {
	s.mu.Lock()
	s.got = append(s.got, req)
	s.times = append(s.times, time.Now())
	var f func(*sip.Request) *sip.Response
	if len(s.answers) > 0 {
		f, s.answers = s.answers[0], s.answers[1:]
	}
	s.mu.Unlock()
	if f == nil {
		f = ok
	}
	_ = tx.Respond(f(req))
}

func (s *scripted) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.got)
}

func ok(req *sip.Request) *sip.Response {
	res := sip.NewResponseFromRequest(req, 200, "OK", nil)
	if e := req.GetHeader("Expires"); e != nil {
		res.AppendHeader(sip.NewHeader("Expires", e.Value()))
	}
	return res
}

func startRegistrar(t *testing.T, s *scripted) string {
	ua, _ := sipgo.NewUA()
	srv, _ := sipgo.NewServer(ua)
	srv.OnRegister(s.handle)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go srv.ServeTCP(ln)
	t.Cleanup(func() { ln.Close(); ua.Close() })
	return ln.Addr().String()
}

func newManager(t *testing.T) *Manager {
	ua, _ := sipgo.NewUA()
	cli, _ := sipgo.NewClient(ua)
	t.Cleanup(func() { ua.Close() })
	return New(Options{
		Client: cli, Transport: ua.TransportLayer(), Addressing: addressing{},
		Log: slog.New(slog.DiscardHandler), MinBackoff: 300 * time.Millisecond, MaxBackoff: time.Second, Timeout: 3 * time.Second,
	})
}

func line(addr string) account.Account {
	h, p, _ := net.SplitHostPort(addr)
	port, _ := strconv.Atoi(p)
	a := account.Account{ID: "l1", Number: "+447700900123", Domain: h, Port: port, Transport: "tcp", Username: "alice", Password: "pw", Expires: 120}
	if err := a.Normalize(); err != nil {
		panic(err)
	}
	a.Token = account.NewToken()
	return a
}

func waitFor(t *testing.T, what string, f func() bool) {
	t.Helper()
	for range 500 {
		if f() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

// 423 Interval Too Brief: the next REGISTER asks for Min-Expires.
func TestIntervalTooBrief(t *testing.T) {
	s := &scripted{answers: []func(*sip.Request) *sip.Response{func(req *sip.Request) *sip.Response {
		res := sip.NewResponseFromRequest(req, 423, "Interval Too Brief", nil)
		res.AppendHeader(sip.NewHeader("Min-Expires", "900"))
		return res
	}}}
	m := newManager(t)
	m.Apply(line(startRegistrar(t, s)))
	t.Cleanup(func() { m.Close(false) })
	waitFor(t, "registered", func() bool { return m.Status("l1").State == account.StateRegistered })
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.got) < 2 || s.got[0].GetHeader("Expires").Value() != "120" || s.got[1].GetHeader("Expires").Value() != "900" {
		t.Fatalf("expected 120 then 900, got %d requests", len(s.got))
	}
	if exp := m.Status("l1").ExpiresAt; time.Until(exp) < 800*time.Second {
		t.Fatalf("granted expiry not used: %v", exp)
	}
}

// 503 with Retry-After: wait that long (not the shorter backoff), report the failure in words.
func TestRetryAfterAndPlainWords(t *testing.T) {
	s := &scripted{answers: []func(*sip.Request) *sip.Response{func(req *sip.Request) *sip.Response {
		res := sip.NewResponseFromRequest(req, 503, "Service Unavailable", nil)
		res.AppendHeader(sip.NewHeader("Retry-After", "1"))
		return res
	}}}
	m := newManager(t)
	m.Apply(line(startRegistrar(t, s)))
	t.Cleanup(func() { m.Close(false) })
	waitFor(t, "failure reported", func() bool { return m.Status("l1").State == account.StateFailed })
	if st := m.Status("l1"); !strings.Contains(st.LastError, "provider had a problem") || !strings.Contains(st.LastError, "503") {
		t.Fatalf("last error %q", st.LastError)
	}
	waitFor(t, "registered after Retry-After", func() bool { return m.Status("l1").State == account.StateRegistered })
	s.mu.Lock()
	gap := s.times[1].Sub(s.times[0])
	s.mu.Unlock()
	if gap < 900*time.Millisecond {
		t.Fatalf("retried after %v, Retry-After was 1s", gap)
	}
}

// Losing the TCP connection is noticed by the keepalive and the line registers again.
func TestReRegisterWhenConnectionDrops(t *testing.T) {
	s := &scripted{}
	addr := startRegistrar(t, s)
	ua, _ := sipgo.NewUA()
	cli, _ := sipgo.NewClient(ua)
	t.Cleanup(func() { ua.Close() })
	m := New(Options{Client: cli, Transport: ua.TransportLayer(), Addressing: addressing{}, Log: slog.New(slog.DiscardHandler), Keepalive: 100 * time.Millisecond})
	m.Apply(line(addr))
	t.Cleanup(func() { m.Close(false) })
	waitFor(t, "registered", func() bool { return m.Status("l1").State == account.StateRegistered })
	f, _ := m.Flow("l1")
	conn, err := ua.TransportLayer().GetConnection("tcp", f.Addr)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
	waitFor(t, "second registration", func() bool { return s.count() >= 2 })
}

func TestBackoffAndRefresh(t *testing.T) {
	lo, hi := 2*time.Second, 5*time.Minute
	prev := time.Duration(0)
	for a := 1; a <= 12; a++ {
		d := backoff(a, lo, hi)
		if d < time.Second || d > hi*12/10 {
			t.Fatalf("attempt %d: %v out of range", a, d)
		}
		if a <= 6 && d < prev/2 {
			t.Fatalf("attempt %d: %v does not grow (prev %v)", a, d, prev)
		}
		prev = d
	}
	for _, g := range []int{30, 60, 600, 3600} {
		r := refreshAfter(g)
		if r <= 0 || r >= time.Duration(g)*time.Second-4*time.Second {
			t.Fatalf("refresh for %ds = %v: not safely before expiry", g, r)
		}
	}
}

func TestWords(t *testing.T) {
	a := account.Account{Domain: "sip.example.com", Port: 5061, Transport: "tls"}
	cases := map[string]string{
		"dial tcp: lookup sip.example.com: no such host":                     "could not be found",
		"dial tcp 1.2.3.4:5061: connect: connection refused":                 "refused the connection",
		"TLS handshake error: x509: certificate signed by unknown authority": "certificate",
		"transaction timeout": "no answer",
	}
	for msg, want := range cases {
		if got := errorWords(errors.New(msg), a); !strings.Contains(got, want) {
			t.Errorf("%q -> %q, want it to mention %q", msg, got, want)
		}
	}
	if !strings.Contains(statusWords(404, "Not Found"), "does not know this username") {
		t.Error("404 wording")
	}
	if !strings.Contains(statusWords(403, "Forbidden"), "username and password") {
		t.Error("403 wording")
	}
}
