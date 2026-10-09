package gateway

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"log/slog"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/config"
)

const (
	controlToken = "test-control-token-0123456789"
	lkUser       = "livekit-in"
	lkPass       = "livekit-in-secret"
	outUser      = "livekit-out"
	outPass      = "livekit-out-secret"
	provUser     = "alice"
	provPass     = "provider-secret"
	lineNumber   = "+447700900123"
)

type harness struct {
	t    *testing.T
	gw   *Gateway
	prov *fakeProvider
	lk   *fakeLiveKit
	logs *bytes.Buffer
	logw *lockedWriter
	stop func()
}

func newHarness(t *testing.T, mutate ...func(*config.Config)) *harness {
	t.Helper()
	prov := newFakeProvider(t, provUser, provPass)
	lk := newFakeLiveKit(t, lkUser, lkPass)

	cfg := config.Default()
	cfg.SIPUDP, cfg.SIPTCP, cfg.SIPTLS = "127.0.0.1:0", "127.0.0.1:0", ""
	cfg.PublicHost = "127.0.0.1"
	cfg.InternalListen = "127.0.0.1:0"
	cfg.LiveKitAddr = lk.addr
	cfg.LiveKitUser, cfg.LiveKitPass = lkUser, lkPass
	cfg.OutboundUser, cfg.OutboundPass = outUser, outPass
	cfg.ControlListen = "127.0.0.1:0"
	cfg.ControlToken = controlToken
	cfg.LogLevel = "debug"
	cfg.CallProbeInterval = config.Duration{}
	for _, m := range mutate {
		m(&cfg)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}

	// Logs go to a buffer (checked for secrets) and, with SIPGW_TEST_LOG=1, to stderr.
	logs := &bytes.Buffer{}
	lw := &lockedWriter{w: logs}
	var w io.Writer = lw
	if os.Getenv("SIPGW_TEST_LOG") != "" {
		w = io.MultiWriter(w, os.Stderr)
	}
	log := slog.New(slog.NewTextHandler(w, &slog.HandlerOptions{Level: slog.LevelDebug}))

	gw, err := New(&cfg, log, Options{})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { _ = gw.Run(ctx); close(done) }()
	h := &harness{t: t, gw: gw, prov: prov, lk: lk, logs: logs, logw: lw}
	var once sync.Once
	h.stop = func() { once.Do(func() { cancel(); <-done }) }
	t.Cleanup(func() {
		h.stop()
		h.checkNoSecretsLogged()
	})
	return h
}

type lockedWriter struct {
	mu sync.Mutex
	w  *bytes.Buffer
}

func (l *lockedWriter) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.w.Write(p)
}

func (h *harness) checkNoSecretsLogged() {
	h.logw.mu.Lock()
	l := h.logs.String()
	h.logw.mu.Unlock()
	for _, s := range []string{provPass, lkPass, outPass, controlToken, "response="} {
		if strings.Contains(l, s) {
			h.t.Errorf("a secret (%q) appeared in the logs", s)
		}
	}
}

// addLine creates the test line through the control API.
func (h *harness) addLine(mode string) account.View {
	h.t.Helper()
	body := map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": portOf(h.prov.addr), "transport": "tcp",
		"username": provUser, "password": provPass, "mode": mode, "tenant": "tenant-7", "expires": 300,
	}
	var v account.View
	code := h.api("PUT", "/v1/accounts/line1", body, &v)
	if code != 200 {
		h.t.Fatalf("PUT account: %d", code)
	}
	return v
}

func (h *harness) api(method, path string, body any, out any) int {
	h.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, "http://"+h.gw.ControlAddr()+path, rd)
	req.Header.Set("Authorization", "Bearer "+controlToken)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	if out != nil && len(data) > 0 {
		if err := json.Unmarshal(data, out); err != nil {
			h.t.Fatalf("%s %s: bad JSON %q", method, path, data)
		}
	}
	return res.StatusCode
}

// waitRegistered waits for the line to be registered and returns the provider's binding.
func (h *harness) waitRegistered() *binding {
	h.t.Helper()
	eventually(h.t, "registration", func() bool {
		v, _ := h.gw.Get("line1")
		return v.Status.State == account.StateRegistered && h.prov.currentBinding() != nil
	})
	return h.prov.currentBinding()
}

func portOf(hp string) int { _, p := splitHP(hp); return p }

// 1. REGISTER with digest auth (401, then SHA-256 credentials), token Contact, status.
func TestRegisterWithAuth(t *testing.T) {
	h := newHarness(t)
	v := h.addLine("on")
	if v.HasPassword != true || v.Number != lineNumber {
		t.Fatalf("view: %+v", v)
	}
	first := recv(t, h.prov.register, "first REGISTER")
	if first.GetHeader("Authorization") != nil {
		t.Fatal("first REGISTER should come without credentials")
	}
	second := recv(t, h.prov.register, "authenticated REGISTER")
	if second.GetHeader("Authorization") == nil {
		t.Fatal("second REGISTER has no credentials")
	}
	if !strings.Contains(second.GetHeader("Authorization").Value(), "algorithm=SHA-256") {
		t.Fatal("did not answer with SHA-256")
	}
	b := h.waitRegistered()
	if !regexp.MustCompile(`^[a-z2-7]{32}$`).MatchString(b.contact.User) {
		t.Fatalf("contact user %q is not a 160-bit base32 token", b.contact.User)
	}
	if b.contact.User == provUser || b.contact.Host != "127.0.0.1" || b.contact.Port != portOf(h.gw.ProviderAddr("tcp")) {
		t.Fatalf("contact %s", b.contact.String())
	}
	if tr, _ := b.contact.UriParams.Get("transport"); tr != "tcp" {
		t.Fatalf("contact transport %q", tr)
	}
	if b.expires != 300 {
		t.Fatalf("asked for %d seconds, want 300", b.expires)
	}
	var got account.View
	h.api("GET", "/v1/accounts/line1", nil, &got)
	if got.Status.State != "registered" || got.Status.LastRegistered.IsZero() || got.Status.LastError != "" {
		t.Fatalf("status: %+v", got.Status)
	}
	// The API never shows the password or the token.
	req, _ := http.NewRequest("GET", "http://"+h.gw.ControlAddr()+"/v1/accounts", nil)
	req.Header.Set("Authorization", "Bearer "+controlToken)
	res, _ := http.DefaultClient.Do(req)
	all, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if strings.Contains(string(all), provPass) || strings.Contains(string(all), `"password"`) {
		t.Fatalf("account list leaks the password: %s", all)
	}
	if h.gw.Metrics().RegistrationsOK.Load() < 1 {
		t.Fatal("registrations_ok not counted")
	}
}

// 2a/2b. Inbound call: relayed with the right headers, answered, then hung up from each side.
func TestInboundCallByeFromCaller(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	b := h.waitRegistered()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, b.contact, b.source, "07700 900999", "+447700900123",
		sip.NewHeader("P-Asserted-Identity", `"Alice" <sip:+447700900999@provider.test;user=phone>`))
	if err != nil {
		t.Fatal(err)
	}
	inv := recv(t, h.lk.invites, "INVITE at LiveKit")
	if inv.Recipient.User != lineNumber {
		t.Fatalf("LiveKit Request-URI user %q, want the line's number", inv.Recipient.User)
	}
	if inv.From().Address.User != "+447700900999" {
		t.Fatalf("LiveKit From user %q, want the caller in E.164", inv.From().Address.User)
	}
	if inv.From().DisplayName != "Alice Caller" {
		t.Fatalf("display name %q", inv.From().DisplayName)
	}
	if v := inv.GetHeader("X-LL-Line"); v == nil || v.Value() != "line1" {
		t.Fatal("X-LL-Line missing or wrong")
	}
	if v := inv.GetHeader("X-LL-Tenant"); v == nil || v.Value() != "tenant-7" {
		t.Fatal("X-LL-Tenant missing or wrong")
	}
	if string(inv.Body()) != offerSDP {
		t.Fatal("SDP offer changed on the way")
	}
	if inv.GetHeader("P-Asserted-Identity") != nil {
		t.Fatal("provider headers leaked to LiveKit")
	}

	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatalf("caller did not get an answer: %v", err)
	}
	if string(call.InviteResponse.Body()) != answerSDP {
		t.Fatal("SDP answer changed on the way")
	}
	if err := call.Ack(ctx); err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.acks, "ACK at LiveKit")
	if h.gw.ActiveCalls() != 1 {
		t.Fatalf("active calls %d", h.gw.ActiveCalls())
	}

	if err := call.Bye(ctx); err != nil {
		t.Fatalf("BYE from caller: %v", err)
	}
	bye := recv(t, h.lk.byes, "BYE at LiveKit")
	if bye.CallID().Value() != inv.CallID().Value() {
		t.Fatal("BYE for the wrong call")
	}
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
	m := h.gw.Metrics()
	if m.CallsIn.Load() != 1 || m.CallsAnswered.Load() != 1 {
		t.Fatalf("metrics: in=%d answered=%d", m.CallsIn.Load(), m.CallsAnswered.Load())
	}
}

func TestInboundCallByeFromLiveKit(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	b := h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	inv := recv(t, h.lk.invites, "INVITE at LiveKit")
	if inv.From().Address.User != "+15550100777" {
		t.Fatalf("From user %q", inv.From().Address.User)
	}
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = call.Ack(ctx)
	recv(t, h.lk.acks, "ACK at LiveKit")

	// The agent hangs up.
	if err := h.lk.lastSession().Bye(ctx); err != nil {
		t.Fatalf("BYE from LiveKit: %v", err)
	}
	bye := recv(t, h.prov.byes, "BYE at the provider")
	if bye.CallID().Value() != call.InviteRequest.CallID().Value() {
		t.Fatal("BYE for the wrong call")
	}
	select {
	case <-call.Context().Done():
	case <-time.After(5 * time.Second):
		t.Fatal("caller's dialog did not end")
	}
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
}

// 3. CANCEL while ringing: LiveKit gets CANCEL, the caller gets 487.
func TestInboundCancelWhileRinging(t *testing.T) {
	h := newHarness(t)
	h.lk.ringOnly = true
	h.addLine("on")
	b := h.waitRegistered()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.invites, "INVITE at LiveKit")
	ringCtx, stopRinging := context.WithCancel(ctx)
	got180 := make(chan struct{}, 1)
	errc := make(chan error, 1)
	go func() {
		errc <- call.WaitAnswer(ringCtx, sipgo.AnswerOptions{OnResponse: func(r *sip.Response) error {
			if r.StatusCode == 180 {
				got180 <- struct{}{}
			}
			return nil
		}})
	}()
	recv(t, got180, "180 Ringing relayed to the caller")
	stopRinging() // the caller hangs up: sipgo sends CANCEL
	recv(t, h.lk.cancels, "CANCEL at LiveKit")
	if err := <-errc; err == nil {
		t.Fatal("call was answered after CANCEL")
	}
	if call.InviteResponse == nil || call.InviteResponse.StatusCode != 487 {
		code := 0
		if call.InviteResponse != nil {
			code = call.InviteResponse.StatusCode
		}
		t.Fatalf("caller got %d, want 487", code)
	}
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
	if h.gw.Metrics().CallsAnswered.Load() != 0 {
		t.Fatal("cancelled call counted as answered")
	}
}

// 4. INVITE with a wrong token: 404, nothing reaches LiveKit.
func TestInboundWrongToken(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	b := h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for _, user := range []string{account.NewToken(), provUser, lineNumber, strings.ToUpper(b.contact.User), ""} {
		ruri := b.contact
		ruri.User = user
		call, err := h.prov.ring(ctx, ruri, b.source, "+15550100777", "nobody")
		if err != nil {
			t.Fatal(err)
		}
		err = call.WaitAnswer(ctx, sipgo.AnswerOptions{})
		var de *sipgo.ErrDialogResponse
		if !errors.As(err, &de) || (de.Res.StatusCode != 404 && de.Res.StatusCode != 403) {
			t.Fatalf("user %q: got %v, want 403/404", user, err)
		}
	}
	select {
	case inv := <-h.lk.invites:
		t.Fatalf("LiveKit got a call for a wrong token: %s", inv.Recipient.String())
	case <-time.After(200 * time.Millisecond):
	}
	if h.gw.Metrics().CallsRejected.Load() < 5 {
		t.Fatalf("rejected %d", h.gw.Metrics().CallsRejected.Load())
	}
}

// 5. Outbound call: LiveKit -> internal listener -> provider, with the line's number as From.
func TestOutboundCall(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Spoofed identity in the request must not reach the provider.
	spoofFrom := &sip.FromHeader{Address: sip.Uri{Scheme: "sip", User: "+19999999999", Host: "evil.test"}, Params: params("tag", "x1")}
	call, err := h.lk.dial(ctx, h.gw.InternalAddr(), "+15550100888", outUser, outPass,
		sip.NewHeader("X-LL-Line", "line1"), spoofFrom,
		sip.NewHeader("P-Asserted-Identity", "<sip:+19999999999@evil.test>"))
	if err != nil {
		t.Fatalf("outbound call failed: %v", err)
	}
	inv := recv(t, h.prov.invites, "INVITE at the provider")
	if inv.Recipient.User != "+15550100888" {
		t.Fatalf("provider Request-URI user %q", inv.Recipient.User)
	}
	if inv.From().Address.User != lineNumber {
		t.Fatalf("provider From user %q, want the line's number", inv.From().Address.User)
	}
	pai := inv.GetHeaders("P-Asserted-Identity")
	if len(pai) != 1 || !strings.Contains(pai[0].Value(), lineNumber) {
		t.Fatalf("P-Asserted-Identity %v", pai)
	}
	if strings.Contains(inv.String(), "+19999999999") || strings.Contains(inv.String(), "X-LL-Line") {
		t.Fatal("request-supplied identity or internal headers leaked to the provider")
	}
	if inv.Source() != h.prov.currentBinding().source {
		t.Fatalf("outbound INVITE came over %s, not the registered connection %s", inv.Source(), h.prov.currentBinding().source)
	}
	if string(call.InviteResponse.Body()) != answerSDP {
		t.Fatal("answer SDP changed")
	}
	if err := call.Ack(ctx); err != nil {
		t.Fatal(err)
	}
	if err := call.Bye(ctx); err != nil {
		t.Fatalf("BYE: %v", err)
	}
	recv(t, h.prov.byes, "BYE at the provider")
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
	if h.gw.Metrics().CallsOut.Load() != 1 {
		t.Fatal("calls_out not counted")
	}
}

// Outbound is never an open relay: no credentials, wrong credentials, unknown line.
func TestOutboundRefused(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cases := []struct {
		user, pass, line string
		want             int
	}{
		{"", "", "line1", 407}, // no credentials: challenged, can't answer
		{outUser, "wrong-password", "line1", 403},
		{outUser, outPass, "no-such-line", 404},
	}
	for _, c := range cases {
		_, err := h.lk.dial(ctx, h.gw.InternalAddr(), "+15550100888", c.user, c.pass, sip.NewHeader("X-LL-Line", c.line))
		var de *sipgo.ErrDialogResponse
		if !errors.As(err, &de) || de.Res.StatusCode != c.want {
			t.Fatalf("%+v: got %v, want %d", c, err, c.want)
		}
	}
	select {
	case inv := <-h.prov.invites:
		t.Fatalf("provider got a call it should not have: %s", inv.Recipient.String())
	case <-time.After(200 * time.Millisecond):
	}
	// Outbound INVITEs on the provider-facing listener are not calls out: they need a token.
	if h.gw.Metrics().CallsOut.Load() != 0 {
		t.Fatal("refused call counted")
	}
}

// 6. Mode off: REGISTER with Expires 0, status off; back on registers again.
func TestModeOffUnregisters(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	old := h.waitRegistered()
	drain(h.prov.accepted)

	// Switch off without resending the password.
	var v account.View
	if code := h.api("PUT", "/v1/accounts/line1", map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": portOf(h.prov.addr), "transport": "tcp",
		"username": provUser, "mode": "off", "expires": 300,
	}, &v); code != 200 {
		t.Fatalf("PUT: %d", code)
	}
	for {
		req := recv(t, h.prov.accepted, "un-REGISTER")
		if e := req.GetHeader("Expires"); e != nil && e.Value() == "0" {
			if c := req.Contact(); c == nil || c.Params.GetOr("expires", "") != "0" {
				t.Fatal("Contact of the un-REGISTER lacks expires=0")
			}
			break
		}
	}
	eventually(t, "binding removed", func() bool { return h.prov.currentBinding() == nil })
	h.api("GET", "/v1/accounts/line1", nil, &v)
	if v.Status.State != "off" {
		t.Fatalf("state %q, want off", v.Status.State)
	}

	// A call to the old Contact is refused now (the provider should not send one, but if it does).
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, old.contact, old.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	var de *sipgo.ErrDialogResponse
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); !errors.As(err, &de) || de.Res.StatusCode != 404 {
		t.Fatalf("call to a line that is off: %v, want 404", err)
	}

	// Back on: registers again, with the same token.
	h.addLine("on")
	b := h.waitRegistered()
	if b.contact.User != old.contact.User {
		t.Fatal("token changed when the line was switched back on")
	}
}

// Deleting a line signs it out too.
func TestDeleteUnregisters(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	h.waitRegistered()
	if code := h.api("DELETE", "/v1/accounts/line1", nil, nil); code != 204 {
		t.Fatalf("DELETE: %d", code)
	}
	eventually(t, "binding removed", func() bool { return h.prov.currentBinding() == nil })
	if code := h.api("GET", "/v1/accounts/line1", nil, nil); code != 404 {
		t.Fatalf("GET after delete: %d", code)
	}
}

// The test endpoint reports outcomes in plain words.
func TestTestEndpoint(t *testing.T) {
	h := newHarness(t)
	h.addLine("off")
	var out struct {
		OK     bool   `json:"ok"`
		Result string `json:"result"`
	}
	if code := h.api("POST", "/v1/accounts/line1/test", nil, &out); code != 200 || !out.OK {
		t.Fatalf("test: %d %+v", code, out)
	}
	// mode off: the test binding is removed again.
	eventually(t, "test binding removed", func() bool { return h.prov.currentBinding() == nil })

	// Wrong password: plain words.
	h.api("PUT", "/v1/accounts/line1", map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": portOf(h.prov.addr), "transport": "tcp",
		"username": provUser, "password": "not-it", "mode": "off",
	}, nil)
	h.api("POST", "/v1/accounts/line1/test", nil, &out)
	if out.OK || !strings.Contains(out.Result, "password") {
		t.Fatalf("wrong password reported as %+v", out)
	}
	// Nothing listening: plain words.
	h.api("PUT", "/v1/accounts/line1", map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": 1, "transport": "tcp",
		"username": provUser, "password": "x", "mode": "off",
	}, nil)
	h.api("POST", "/v1/accounts/line1/test", nil, &out)
	if out.OK || !strings.Contains(out.Result, "refused the connection") {
		t.Fatalf("unreachable reported as %+v", out)
	}
}

func drain[T any](ch chan T) {
	for {
		select {
		case <-ch:
		default:
			return
		}
	}
}

// In-call requests pass through: re-INVITE (hold) with its SDP and ACK, and INFO (DTMF).
func TestInCallReinviteAndInfo(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	b := h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.invites, "INVITE at LiveKit")
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = call.Ack(ctx)
	recv(t, h.lk.acks, "ACK at LiveKit")

	// Hold: re-INVITE with a=sendonly.
	holdSDP := strings.Replace(offerSDP, "a=rtpmap:0", "a=sendonly\r\na=rtpmap:0", 1)
	reinv := sip.NewRequest(sip.INVITE, call.InviteResponse.Contact().Address)
	reinv.AppendHeader(sip.NewHeader("Content-Type", "application/sdp"))
	reinv.SetBody([]byte(holdSDP))
	res, err := call.Do(ctx, reinv)
	if err != nil {
		t.Fatalf("re-INVITE: %v", err)
	}
	if res.StatusCode != 200 || !strings.Contains(string(res.Body()), "a=recvonly") {
		t.Fatalf("re-INVITE answer %d %q", res.StatusCode, res.Body())
	}
	got := recv(t, h.lk.inCall, "re-INVITE at LiveKit")
	if got.Method != sip.INVITE || string(got.Body()) != holdSDP {
		t.Fatalf("LiveKit got %s with body %q", got.Method, got.Body())
	}
	if got.CallID().Value() != h.lk.lastSession().InviteRequest.CallID().Value() {
		t.Fatal("re-INVITE sent outside the call's dialog")
	}
	recv(t, h.lk.acks, "ACK for the re-INVITE at LiveKit")
	ack := sip.NewRequest(sip.ACK, call.InviteResponse.Contact().Address)
	if err := call.WriteRequest(ack); err != nil {
		t.Fatal(err)
	}

	// DTMF over SIP INFO.
	info := sip.NewRequest(sip.INFO, call.InviteResponse.Contact().Address)
	info.AppendHeader(sip.NewHeader("Content-Type", "application/dtmf-relay"))
	info.SetBody([]byte("Signal=5\r\nDuration=160\r\n"))
	res, err = call.Do(ctx, info)
	if err != nil || res.StatusCode != 200 {
		t.Fatalf("INFO: %v %v", res, err)
	}
	got = recv(t, h.lk.inCall, "INFO at LiveKit")
	if got.Method != sip.INFO || string(got.Body()) != "Signal=5\r\nDuration=160\r\n" || got.GetHeader("Content-Type").Value() != "application/dtmf-relay" {
		t.Fatalf("LiveKit got %s %q", got.Method, got.Body())
	}
	if h.gw.ActiveCalls() != 1 {
		t.Fatal("call ended by in-call requests")
	}
	_ = call.Bye(ctx)
	recv(t, h.lk.byes, "BYE at LiveKit")
}

// No leaked calls: when LiveKit has lost the call (restart), the in-call probe finds out and
// the caller gets a BYE.
func TestVanishedSideIsHungUp(t *testing.T) {
	h := newHarness(t, func(c *config.Config) { c.CallProbeInterval = config.Duration{Duration: 5 * time.Second} })
	h.addLine("on")
	b := h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	call, err := h.prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = call.Ack(ctx)
	h.lk.mu.Lock()
	h.lk.forgetCalls = true
	h.lk.mu.Unlock()

	select {
	case bye := <-h.prov.byes:
		if bye.CallID().Value() != call.InviteRequest.CallID().Value() {
			t.Fatal("BYE for the wrong call")
		}
	case <-time.After(15 * time.Second):
		t.Fatal("the caller was never hung up after LiveKit lost the call")
	}
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
}

// TLS end to end: the line registers over TLS (certificate checked against provider_ca_file),
// and the provider's call comes back over that same TLS connection.
func TestTLSRegisterAndCall(t *testing.T) {
	cert, caFile := selfSigned(t)
	prov := newFakeProviderTLS(t, provUser, provPass, &cert)
	h := newHarness(t, func(c *config.Config) { c.ProviderCAFile = caFile })
	h.prov = prov
	body := map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": portOf(prov.addr), "transport": "tls",
		"username": provUser, "password": provPass,
	}
	if code := h.api("PUT", "/v1/accounts/line1", body, nil); code != 200 {
		t.Fatalf("PUT %d", code)
	}
	b := h.waitRegistered()
	if b.transport != "TLS" {
		t.Fatalf("registered over %s", b.transport)
	}
	if tr, _ := b.contact.UriParams.Get("transport"); tr != "tls" {
		t.Fatalf("contact transport %q", tr)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.invites, "INVITE at LiveKit")
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = call.Ack(ctx)
	_ = call.Bye(ctx)
	recv(t, h.lk.byes, "BYE at LiveKit")

	// Without the CA, the certificate is refused, in plain words.
	h2 := newHarness(t)
	h2.api("PUT", "/v1/accounts/line1", body, nil)
	var out struct {
		OK     bool   `json:"ok"`
		Result string `json:"result"`
	}
	h2.api("POST", "/v1/accounts/line1/test", nil, &out)
	if out.OK || !strings.Contains(out.Result, "certificate") {
		t.Fatalf("untrusted certificate reported as %+v", out)
	}
}

// selfSigned makes a certificate for 127.0.0.1 and writes it as a CA file.
func selfSigned(t *testing.T) (tls.Certificate, string) {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "fake provider"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, IsCA: true, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	kb, _ := x509.MarshalECPrivateKey(key)
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: kb})
	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "ca.pem")
	if err := os.WriteFile(path, certPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	return cert, path
}

// UDP: REGISTER leaves from the gateway's UDP listener (so the Contact port is the one the
// router maps), and the provider's call to that address is relayed.
func TestUDPRegisterAndCall(t *testing.T) {
	prov := newFakeProviderOn(t, provUser, provPass, "udp", nil)
	h := newHarness(t)
	h.prov = prov
	if code := h.api("PUT", "/v1/accounts/line1", map[string]any{
		"number": lineNumber, "domain": "127.0.0.1", "port": portOf(prov.addr), "transport": "udp",
		"username": provUser, "password": provPass,
	}, nil); code != 200 {
		t.Fatalf("PUT %d", code)
	}
	b := h.waitRegistered()
	if b.source != h.gw.ProviderAddr("udp") {
		t.Fatalf("REGISTER came from %s, not the UDP listener %s", b.source, h.gw.ProviderAddr("udp"))
	}
	if b.contact.Port != portOf(h.gw.ProviderAddr("udp")) {
		t.Fatalf("contact port %d", b.contact.Port)
	}
	if _, has := b.contact.UriParams.Get("transport"); has {
		t.Fatal("UDP contact should carry no transport parameter")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	call, err := prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.invites, "INVITE at LiveKit")
	if err := call.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = call.Ack(ctx)
	recv(t, h.lk.acks, "ACK at LiveKit")
	if err := h.lk.lastSession().Bye(ctx); err != nil {
		t.Fatal(err)
	}
	recv(t, prov.byes, "BYE at the provider over UDP")
	eventually(t, "call cleanup", func() bool { return h.gw.ActiveCalls() == 0 })
}

// Shutdown: answered calls get BYE on both sides, ringing calls are cancelled (the caller
// hears 503), and the line is signed out.
func TestShutdownEndsCallsAndSignsOut(t *testing.T) {
	h := newHarness(t)
	h.addLine("on")
	b := h.waitRegistered()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	answered, err := h.prov.ring(ctx, b.contact, b.source, "+15550100777", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	if err := answered.WaitAnswer(ctx, sipgo.AnswerOptions{}); err != nil {
		t.Fatal(err)
	}
	_ = answered.Ack(ctx)
	recv(t, h.lk.invites, "first INVITE at LiveKit")

	h.lk.mu.Lock()
	h.lk.ringOnly = true
	h.lk.mu.Unlock()
	ringing, err := h.prov.ring(ctx, b.contact, b.source, "+15550100778", lineNumber)
	if err != nil {
		t.Fatal(err)
	}
	recv(t, h.lk.invites, "second INVITE at LiveKit")
	ringErr := make(chan error, 1)
	go func() { ringErr <- ringing.WaitAnswer(ctx, sipgo.AnswerOptions{}) }()
	eventually(t, "two calls", func() bool { return h.gw.ActiveCalls() == 2 })
	drain(h.prov.accepted)

	h.stop()

	recv(t, h.prov.byes, "BYE to the caller of the answered call")
	recv(t, h.lk.byes, "BYE to LiveKit for the answered call")
	recv(t, h.lk.cancels, "CANCEL to LiveKit for the ringing call")
	var de *sipgo.ErrDialogResponse
	if err := recv(t, ringErr, "final answer to the ringing caller"); !errors.As(err, &de) || de.Res.StatusCode != 503 {
		t.Fatalf("ringing caller got %v, want 503", err)
	}
	unreg := recv(t, h.prov.accepted, "un-REGISTER on shutdown")
	if unreg.GetHeader("Expires").Value() != "0" {
		t.Fatalf("shutdown REGISTER has Expires %s", unreg.GetHeader("Expires").Value())
	}
}
