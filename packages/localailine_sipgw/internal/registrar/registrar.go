// Package registrar keeps each line signed in (SIP REGISTER) to its provider.
//
// One small worker per line: it registers, refreshes before the binding expires, backs off
// (with jitter) when the provider says no or can't be reached, keeps the connection busy so
// routers don't drop it, and signs out (Expires: 0) when the line is switched off or removed,
// so the provider rings the person's other phones again.
//
// The Contact it registers is sip:<token>@<our public host>: the token is the line's secret, and
// it is how an incoming INVITE is matched to the line.
package registrar

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	"github.com/google/uuid"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/digest"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// Addressing tells the registrar how the outside world reaches us.
type Addressing interface {
	// PublicHost is the configured or STUN-learned public host, "" if unknown.
	PublicHost() string
	// ContactPort is the port to advertise for transport ("UDP"/"TCP"/"TLS").
	ContactPort(transport string) int
	// UDPLaddr is our provider-facing UDP listener (requests over UDP leave from it), or nil.
	UDPLaddr() *sip.Addr
}

// Options configure a Manager.
type Options struct {
	Client     *sipgo.Client
	Transport  *sip.TransportLayer
	Addressing Addressing
	Keepalive  time.Duration
	Metrics    *metrics.Metrics
	Log        *slog.Logger
	UserAgent  string
	// Timeout for one REGISTER exchange (default 15s).
	Timeout time.Duration
	// Backoff bounds (defaults 2s .. 5m).
	MinBackoff, MaxBackoff time.Duration
}

// Flow is the connection a line is registered over: the provider sends calls back on it.
type Flow struct {
	Transport string // UDP/TCP/TLS
	Addr      string // provider's ip:port as we see it
}

// Manager runs one worker per line.
type Manager struct {
	o       Options
	mu      sync.Mutex
	workers map[string]*worker
	wg      sync.WaitGroup
}

// New makes a Manager.
func New(o Options) *Manager {
	if o.Timeout == 0 {
		o.Timeout = 15 * time.Second
	}
	if o.MinBackoff == 0 {
		o.MinBackoff = 2 * time.Second
	}
	if o.MaxBackoff == 0 {
		o.MaxBackoff = 5 * time.Minute
	}
	if o.Keepalive == 0 {
		o.Keepalive = 25 * time.Second
	}
	if o.Metrics == nil {
		o.Metrics = &metrics.Metrics{}
	}
	if o.Log == nil {
		o.Log = slog.Default()
	}
	return &Manager{o: o, workers: map[string]*worker{}}
}

// Apply starts or updates the worker for a (with its token set).
func (m *Manager) Apply(a account.Account) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if w, ok := m.workers[a.ID]; ok {
		w.setAccount(a)
		return
	}
	w := newWorker(m, a)
	m.workers[a.ID] = w
	m.wg.Add(1)
	go func() {
		defer m.wg.Done()
		w.run()
	}()
}

// Remove signs the line out (best effort) and stops its worker.
func (m *Manager) Remove(id string) {
	m.mu.Lock()
	w, ok := m.workers[id]
	delete(m.workers, id)
	m.mu.Unlock()
	if ok {
		w.stopAndWait(true)
	}
}

// Close stops every worker, signing lines out first if unregister is set.
func (m *Manager) Close(unregister bool) {
	m.mu.Lock()
	ws := make([]*worker, 0, len(m.workers))
	for _, w := range m.workers {
		ws = append(ws, w)
	}
	m.workers = map[string]*worker{}
	m.mu.Unlock()
	var wg sync.WaitGroup
	for _, w := range ws {
		wg.Add(1)
		go func() { defer wg.Done(); w.stopAndWait(unregister) }()
	}
	wg.Wait()
	m.wg.Wait()
}

// Status is the line's sign-in state.
func (m *Manager) Status(id string) account.Status {
	m.mu.Lock()
	w, ok := m.workers[id]
	m.mu.Unlock()
	if !ok {
		return account.Status{State: account.StateOff}
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.status
}

// Flow is the connection the line is registered over, if registered.
func (m *Manager) Flow(id string) (Flow, bool) {
	m.mu.Lock()
	w, ok := m.workers[id]
	m.mu.Unlock()
	if !ok {
		return Flow{}, false
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.status.State != account.StateRegistered || w.flow.Addr == "" {
		return Flow{}, false
	}
	return w.flow, true
}

// Registered counts lines currently registered.
func (m *Manager) Registered() int {
	m.mu.Lock()
	ws := make([]*worker, 0, len(m.workers))
	for _, w := range m.workers {
		ws = append(ws, w)
	}
	m.mu.Unlock()
	n := 0
	for _, w := range ws {
		w.mu.Lock()
		if w.status.State == account.StateRegistered {
			n++
		}
		w.mu.Unlock()
	}
	return n
}

// Test makes one REGISTER attempt for a and says how it went in plain words. If a is not
// meant to be on (mode off), the binding is removed again straight away.
func (m *Manager) Test(ctx context.Context, a account.Account) (bool, string) {
	s := newSession(m, a)
	r := s.register(ctx, a, a.Expires, nil)
	if !r.ok {
		return false, r.words
	}
	if a.Mode != account.ModeOn {
		s.register(ctx, a, 0, nil)
	}
	return true, fmt.Sprintf("registered: the provider accepted the sign-in for %d seconds", r.granted)
}

// worker keeps one line registered.
type worker struct {
	m *Manager

	mu      sync.Mutex
	acc     account.Account
	status  account.Status
	flow    Flow
	changed bool // account changed since the last attempt

	wake chan struct{}
	stop chan bool // true = unregister before stopping
	done chan struct{}

	sess     *session         // the REGISTER dialog (Call-ID, CSeq, last challenge)
	boundAcc *account.Account // account used for the binding we hold, nil if none
	expires  int              // expiry to ask for (raised by 423)
	attempts int              // consecutive failures, for backoff
}

func newWorker(m *Manager, a account.Account) *worker {
	st := account.StateRegistering
	if a.Mode != account.ModeOn {
		st = account.StateOff
	}
	return &worker{
		m: m, acc: a, status: account.Status{State: st},
		wake: make(chan struct{}, 1), stop: make(chan bool, 1), done: make(chan struct{}),
		sess: newSession(m, a), expires: a.Expires,
	}
}

func (w *worker) setAccount(a account.Account) {
	w.mu.Lock()
	w.acc = a
	w.changed = true
	if a.Mode != account.ModeOn {
		w.status = account.Status{State: account.StateOff}
	} else if w.status.State == account.StateOff {
		w.status.State = account.StateRegistering
	}
	w.mu.Unlock()
	select {
	case w.wake <- struct{}{}:
	default:
	}
}

func (w *worker) account() (account.Account, bool) {
	w.mu.Lock()
	defer w.mu.Unlock()
	ch := w.changed
	w.changed = false
	return w.acc, ch
}

func (w *worker) setStatus(f func(*account.Status)) {
	w.mu.Lock()
	f(&w.status)
	w.mu.Unlock()
}

func (w *worker) stopAndWait(unregister bool) {
	select {
	case w.stop <- unregister:
	default:
	}
	<-w.done
}

// run is the worker's loop: one timer for "next REGISTER", one ticker for keepalives.
func (w *worker) run() {
	defer close(w.done)
	log := w.m.o.Log
	next := time.Now()
	ka := time.NewTicker(w.m.o.Keepalive)
	defer ka.Stop()
	for {
		timer := time.NewTimer(time.Until(next))
		select {
		case unreg := <-w.stop:
			timer.Stop()
			if unreg && w.boundAcc != nil {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				w.sess.register(ctx, *w.boundAcc, 0, nil)
				cancel()
			}
			return

		case <-w.wake:
			timer.Stop()
			next = time.Now()

		case <-ka.C:
			timer.Stop()
			if !w.keepalive() {
				log.Info("connection to provider lost; registering again", "line", w.acc.ID)
				next = time.Now()
			}

		case <-timer.C:
			acc, changed := w.account()
			if changed {
				w.expires, w.attempts = acc.Expires, 0
			}
			ctx, cancel := context.WithTimeout(context.Background(), w.m.o.Timeout+5*time.Second)
			next = w.step(ctx, acc)
			cancel()
		}
	}
}

// step does whatever the line needs now and returns when to look again.
func (w *worker) step(ctx context.Context, acc account.Account) time.Time {
	log := w.m.o.Log
	// The binding we hold belongs to different sign-in details: remove it first.
	if w.boundAcc != nil && (acc.Mode != account.ModeOn || identity(*w.boundAcc) != identity(acc)) {
		r := w.sess.register(ctx, *w.boundAcc, 0, nil)
		log.Info("line signed out", "line", acc.ID, "ok", r.ok)
		w.boundAcc = nil
		w.sess = newSession(w.m, acc)
		w.mu.Lock()
		w.flow = Flow{}
		w.mu.Unlock()
	}
	if acc.Mode != account.ModeOn {
		w.setStatus(func(s *account.Status) { *s = account.Status{State: account.StateOff} })
		return time.Now().Add(24 * time.Hour)
	}
	if identity(w.sess.acc) != identity(acc) {
		w.sess = newSession(w.m, acc)
	}

	r := w.sess.register(ctx, acc, w.expires, w.learned())
	switch {
	case r.ok:
		w.m.o.Metrics.RegistrationsOK.Add(1)
		first := w.boundAcc == nil
		a := acc
		w.boundAcc = &a
		w.attempts = 0
		now := time.Now()
		w.mu.Lock()
		w.flow = r.flow
		w.status = account.Status{State: account.StateRegistered, LastRegistered: now, ExpiresAt: now.Add(time.Duration(r.granted) * time.Second), Contact: r.contact}
		w.mu.Unlock()
		if first {
			log.Info("line registered", "line", acc.ID, "provider", acc.Domain, "transport", acc.Transport, "expires", r.granted)
		} else {
			log.Debug("registration refreshed", "line", acc.ID, "expires", r.granted)
		}
		// The provider sees us at a different public address than we advertised: say so now.
		if r.contactStale {
			log.Info("public address learned from the provider; updating the registration", "line", acc.ID)
			return now
		}
		return now.Add(refreshAfter(r.granted))

	case r.code == 423 && r.minExpires > w.expires && w.attempts < 3:
		w.expires = r.minExpires
		w.attempts++
		log.Info("provider wants a longer registration time", "line", acc.ID, "expires", r.minExpires)
		return time.Now()

	default:
		w.m.o.Metrics.RegistrationsFailed.Add(1)
		w.attempts++
		wait := backoff(w.attempts, w.m.o.MinBackoff, w.m.o.MaxBackoff)
		if r.retryAfter > 0 {
			wait = min(max(r.retryAfter, w.m.o.MinBackoff), time.Hour)
		}
		w.mu.Lock()
		w.status.State = account.StateFailed
		w.status.LastError = r.words
		w.status.ExpiresAt = time.Time{}
		w.mu.Unlock()
		log.Warn("line registration failed", "line", acc.ID, "error", r.words, "retry_in", wait.Round(time.Second))
		return time.Now().Add(wait)
	}
}

// learned is what the provider told us our address is (Via received/rport), if we have it.
func (w *worker) learned() *hostPort {
	return w.sess.learned
}

// keepalive keeps the registered connection busy. It returns false when the connection is
// gone and the line must register again.
func (w *worker) keepalive() bool {
	w.mu.Lock()
	flow, acc, st := w.flow, w.acc, w.status.State
	w.mu.Unlock()
	if st != account.StateRegistered || flow.Addr == "" {
		return true
	}
	if flow.Transport == "UDP" {
		// OPTIONS through the same socket refreshes the router's mapping; the answer doesn't matter.
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			s := newSession(w.m, acc) // its own Call-ID: never races the REGISTER dialog
			req := sip.NewRequest(sip.OPTIONS, registrarURI(acc))
			s.fill(req, acc, sip.OPTIONS, nil)
			s.side(acc).Prepare(req)
			req.SetDestination(flow.Addr)
			_, _ = sipx.Do(ctx, w.m.o.Client, req)
		}()
		return true
	}
	// TCP/TLS: a double CRLF ping (RFC 5626 §3.5.1) on the very connection we registered over.
	conn, err := w.m.o.Transport.GetConnection(flow.Transport, flow.Addr)
	if err != nil || conn == nil {
		return false
	}
	defer conn.TryClose()
	wr, ok := conn.(io.Writer)
	if !ok {
		return true
	}
	if _, err := wr.Write([]byte("\r\n\r\n")); err != nil {
		return false
	}
	return true
}

// identity is what makes a binding: if any of it changes, the old binding must go.
func identity(a account.Account) string {
	return strings.Join([]string{a.Domain, strconv.Itoa(a.Port), a.Transport, a.Username, a.AuthUser(), a.OutboundProxy, a.Token}, "|")
}

// refreshAfter: re-register well before expiry (at ~80%, at least 5s early), with a little jitter.
func refreshAfter(granted int) time.Duration {
	g := time.Duration(granted) * time.Second
	d := g * 8 / 10
	if g-d < 5*time.Second {
		d = g - 5*time.Second
	}
	if d < time.Second {
		d = time.Second
	}
	return d - time.Duration(rand.Int64N(int64(d/20)+1))
}

// backoff is exponential (min, 2min, 4min, … max) with ±20% jitter so many lines that fail
// together don't retry together.
func backoff(attempt int, lo, hi time.Duration) time.Duration {
	d := lo
	for i := 1; i < attempt && d < hi; i++ {
		d *= 2
	}
	d = min(d, hi)
	j := time.Duration(rand.Int64N(int64(d)*2/5+1)) - d/5
	return max(d+j, time.Second)
}

// hostPort is an address the provider told us it sees.
type hostPort struct {
	host string
	port int
}

// session is one REGISTER dialog: Call-ID and CSeq persist across refreshes (RFC 3261 §10.2),
// and the last challenge is reused (with a growing nonce count) until the provider changes it.
type session struct {
	m       *Manager
	acc     account.Account
	callID  string
	fromTag string
	cseq    uint32

	chal    *digest.Challenge
	proxy   bool // last challenge was 407 (Proxy-Authenticate)
	nc      uint32
	learned *hostPort
}

func newSession(m *Manager, a account.Account) *session {
	return &session{m: m, acc: a, callID: uuid.NewString(), fromTag: sip.GenerateTagN(16), cseq: uint32(rand.IntN(10000)) + 1}
}

// result of one REGISTER exchange.
type result struct {
	ok           bool
	code         int
	granted      int
	retryAfter   time.Duration
	minExpires   int
	flow         Flow
	contact      string
	contactStale bool
	words        string
}

func registrarURI(a account.Account) sip.Uri {
	u := sip.Uri{Scheme: "sip", Host: a.Domain, UriParams: sipx.URIParams(a.SIPTransport())}
	if a.Port != sip.DefaultPort(a.Transport) {
		u.Port = a.Port
	}
	return u
}

func aor(a account.Account) sip.Uri {
	return sip.Uri{Scheme: "sip", User: a.Username, Host: a.Domain}
}

// side is where this line's requests go.
func (s *session) side(a account.Account) *sipx.Side {
	side := &sipx.Side{Name: "provider", Client: s.m.o.Client, Transport: a.SIPTransport(), Dest: a.RegistrarAddr()}
	if a.Transport == "udp" && s.m.o.Addressing != nil {
		side.Laddr = s.m.o.Addressing.UDPLaddr()
	}
	host, port := s.contactAddr(a, nil)
	side.ViaHost = host
	if a.Transport == "udp" {
		side.ViaPort = port
	}
	return side
}

// contactAddr picks the host:port to advertise: configured/STUN public host, else what the
// provider told us it sees, else our local address towards the provider.
func (s *session) contactAddr(a account.Account, learned *hostPort) (string, int) {
	ad := s.m.o.Addressing
	host, port := "", 0
	if ad != nil {
		host = ad.PublicHost()
		port = ad.ContactPort(a.SIPTransport())
	}
	if host == "" && learned != nil {
		host = learned.host
		if a.Transport == "udp" && learned.port > 0 {
			port = learned.port // UDP leaves from our listener, so this is its public mapping
		}
	}
	if host == "" {
		host = localIPToward(a.RegistrarAddr())
	}
	if port == 0 {
		port = sip.DefaultPort(a.Transport)
	}
	return host, port
}

// fill adds the dialog headers of a REGISTER-dialog request.
func (s *session) fill(req *sip.Request, a account.Account, method sip.RequestMethod, contact *sip.ContactHeader) {
	s.cseq++
	to := aor(a)
	req.AppendHeader(&sip.FromHeader{Address: to, Params: sipx.Params("tag", s.fromTag)})
	req.AppendHeader(&sip.ToHeader{Address: to})
	cid := sip.CallIDHeader(s.callID)
	req.AppendHeader(&cid)
	req.AppendHeader(&sip.CSeqHeader{SeqNo: s.cseq, MethodName: method})
	mf := sip.MaxForwardsHeader(70)
	req.AppendHeader(&mf)
	if contact != nil {
		req.AppendHeader(contact)
	}
	if a.OutboundProxy != "" {
		req.AppendHeader(&sip.RouteHeader{Address: sip.Uri{Scheme: "sip", Host: hostOnly(a.OutboundProxy), Port: portOnly(a.OutboundProxy), UriParams: sipx.Params("lr", "")}})
	}
	if s.m.o.UserAgent != "" {
		req.AppendHeader(sip.NewHeader("User-Agent", s.m.o.UserAgent))
	}
}

// register sends REGISTER for a with expires (0 = sign out), answering digest challenges.
func (s *session) register(ctx context.Context, a account.Account, expires int, learned *hostPort) result {
	host, port := s.contactAddr(a, learned)
	contactURI := sip.Uri{Scheme: "sip", User: a.Token, Host: host, Port: port, UriParams: sipx.URIParams(a.SIPTransport())}
	contact := &sip.ContactHeader{Address: contactURI, Params: sipx.Params("expires", strconv.Itoa(expires))}

	build := func() *sip.Request {
		req := sip.NewRequest(sip.REGISTER, registrarURI(a))
		s.fill(req, a, sip.REGISTER, contact.Clone())
		e := sip.ExpiresHeader(expires)
		req.AppendHeader(&e)
		req.AppendHeader(sip.NewHeader("Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, INFO, UPDATE, NOTIFY, REFER"))
		side := s.side(a)
		side.ViaHost, side.ViaPort = host, 0
		if a.Transport == "udp" {
			side.ViaPort = port
		}
		side.Prepare(req)
		return req
	}

	ctx, cancel := context.WithTimeout(ctx, s.m.o.Timeout)
	defer cancel()

	req := build()
	if s.chal != nil {
		if err := s.authorize(req, a); err != nil {
			s.chal = nil
		}
	}
	var res *sip.Response
	var err error
	for challenges := 0; ; challenges++ {
		res, err = sipx.Do(ctx, s.m.o.Client, req)
		if err != nil {
			return result{words: errorWords(err, a)}
		}
		if res.StatusCode != 401 && res.StatusCode != 407 {
			break
		}
		if challenges >= 2 {
			return result{code: res.StatusCode, words: "wrong username or password (the provider refused the sign-in details)"}
		}
		hname := "WWW-Authenticate"
		if res.StatusCode == 407 {
			hname = "Proxy-Authenticate"
		}
		ch, perr := digest.ParseChallenge(sipx.Header(res, hname))
		if perr != nil {
			return result{code: res.StatusCode, words: "the provider asked for a sign-in method this gateway doesn't support"}
		}
		if a.Realm != "" && ch.Realm != a.Realm {
			return result{code: res.StatusCode, words: fmt.Sprintf("the provider asked to sign in to realm %q, not the configured %q", ch.Realm, a.Realm)}
		}
		// Same nonce as the one we just answered, and not stale: the password is wrong.
		if s.chal != nil && ch.Nonce == s.chal.Nonce && !ch.Stale && challenges > 0 {
			return result{code: res.StatusCode, words: "wrong username or password (the provider refused the sign-in details)"}
		}
		s.chal, s.proxy, s.nc = ch, res.StatusCode == 407, 0
		req = build()
		if err := s.authorize(req, a); err != nil {
			return result{code: res.StatusCode, words: "the provider asked for a sign-in method this gateway doesn't support"}
		}
	}

	r := result{code: res.StatusCode}
	switch {
	case res.StatusCode >= 200 && res.StatusCode < 300:
		r.ok = true
	case res.StatusCode == 423:
		r.minExpires, _ = strconv.Atoi(strings.TrimSpace(sipx.Header(res, "Min-Expires")))
		r.words = "the provider wants a longer registration time (423 Interval Too Brief)"
		return r
	default:
		r.retryAfter = retryAfter(res)
		r.words = statusWords(res.StatusCode, res.Reason)
		return r
	}

	// Accepted. How long for, and over which connection?
	r.granted = expires
	if v := sipx.Header(res, "Expires"); v != "" {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
			r.granted = n
		}
	}
	for _, h := range res.GetHeaders("Contact") {
		if c, ok := h.(*sip.ContactHeader); ok && c.Address.User == a.Token {
			if v, ok := c.Params.Get("expires"); ok {
				if n, err := strconv.Atoi(v); err == nil {
					r.granted = n
				}
			}
		}
	}
	if expires > 0 && r.granted <= 0 {
		r.granted = expires
	}
	r.flow = Flow{Transport: a.SIPTransport(), Addr: res.Source()}
	r.contact = contactURI.String()
	// What the provider sees as our address (rport/received on our Via).
	if v := res.Via(); v != nil {
		rh, _ := v.Params.Get("received")
		rp, _ := v.Params.Get("rport")
		rpn, _ := strconv.Atoi(rp)
		if rh != "" || rpn > 0 {
			if rh == "" {
				rh = v.Host
			}
			s.learned = &hostPort{host: rh, port: rpn}
			nh, np := s.contactAddr(a, s.learned)
			r.contactStale = expires > 0 && (nh != host || np != port)
		}
	}
	return r
}

// authorize adds Authorization/Proxy-Authorization for the stored challenge.
func (s *session) authorize(req *sip.Request, a account.Account) error {
	s.nc++
	cred, err := digest.Answer(s.chal, string(req.Method), req.Recipient.String(), a.AuthUser(), a.Password, s.nc, "")
	if err != nil {
		return err
	}
	name := "Authorization"
	if s.proxy {
		name = "Proxy-Authorization"
	}
	req.RemoveHeader(name)
	req.AppendHeader(sip.NewHeader(name, cred.String()))
	return nil
}

func retryAfter(res *sip.Response) time.Duration {
	v := strings.TrimSpace(sipx.Header(res, "Retry-After"))
	if i := strings.IndexAny(v, " ;("); i >= 0 {
		v = v[:i]
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return 0
	}
	return time.Duration(n) * time.Second
}

// statusWords explains a final REGISTER answer in plain words.
func statusWords(code int, reason string) string {
	switch {
	case code == 403:
		return "the provider refused this account (403 Forbidden): check the username and password, and that the account may register"
	case code == 404:
		return "the provider does not know this username (404 Not Found)"
	case code == 400 || code == 416 || code == 420:
		return fmt.Sprintf("the provider did not understand the sign-in (%d %s): check the domain and username", code, reason)
	case code == 408 || code == 480:
		return fmt.Sprintf("the provider did not finish the sign-in in time (%d %s)", code, reason)
	case code >= 500:
		return fmt.Sprintf("the provider had a problem (%d %s); retrying", code, reason)
	}
	return fmt.Sprintf("the provider refused the sign-in (%d %s)", code, reason)
}

// errorWords explains a network failure in plain words.
func errorWords(err error, a account.Account) string {
	msg := strings.ToLower(err.Error())
	where := a.RegistrarAddr()
	var dnsErr *net.DNSError
	switch {
	case errors.As(err, &dnsErr) || strings.Contains(msg, "no such host") || strings.Contains(msg, "lookup"):
		return fmt.Sprintf("the provider's address %q could not be found (check the domain)", hostOnly(where))
	case strings.Contains(msg, "x509") || strings.Contains(msg, "certificate") || strings.Contains(msg, "tls handshake") || strings.Contains(msg, "tls:"):
		return fmt.Sprintf("secure connection to %s failed: the certificate could not be verified or the port does not speak TLS", where)
	case strings.Contains(msg, "connection refused"):
		return fmt.Sprintf("%s refused the connection: check the port and transport (%s)", where, a.Transport)
	case strings.Contains(msg, "timeout") || strings.Contains(msg, "deadline") || strings.Contains(msg, "timer_b") || strings.Contains(msg, "timed out"):
		return fmt.Sprintf("no answer from %s over %s (unreachable, blocked by a firewall, or wrong port/transport)", where, a.Transport)
	case strings.Contains(msg, "network is unreachable") || strings.Contains(msg, "no route"):
		return "this computer has no route to the provider (no internet?)"
	}
	return fmt.Sprintf("could not reach the provider at %s", where)
}

func hostOnly(hp string) string {
	if h, _, err := net.SplitHostPort(hp); err == nil {
		return h
	}
	return strings.Trim(hp, "[]")
}

func portOnly(hp string) int {
	if _, p, err := net.SplitHostPort(hp); err == nil {
		n, _ := strconv.Atoi(p)
		return n
	}
	return 0
}

// localIPToward is the local address the OS would use to reach dest (no packet is sent).
func localIPToward(dest string) string {
	host := hostOnly(dest)
	c, err := net.Dial("udp", net.JoinHostPort(host, "9"))
	if err != nil {
		return "127.0.0.1"
	}
	defer c.Close()
	h, _, _ := net.SplitHostPort(c.LocalAddr().String())
	return h
}
