package gateway

// In-process fake SIP endpoints, built with sipgo, for the integration tests:
//
//   - fakeProvider: a registrar that challenges REGISTER with 401 (SHA-256 digest), records
//     bindings, can ring the gateway's registered Contact over the registered connection, and
//     answers the gateway's outbound INVITEs (after a 407 challenge).
//   - fakeLiveKit: a UAS that challenges with 407 (MD5) and answers 200 with SDP (or only
//     rings), and a UAC that places outbound calls into the gateway's internal listener.
//
// Digest answers are checked with github.com/icholy/digest, an implementation independent of
// the gateway's own.

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	icholy "github.com/icholy/digest"
)

const offerSDP = "v=0\r\no=- 1 1 IN IP4 192.0.2.10\r\ns=-\r\nc=IN IP4 192.0.2.10\r\nt=0 0\r\nm=audio 40000 RTP/AVP 0 101\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:101 telephone-event/8000\r\n"
const answerSDP = "v=0\r\no=- 2 2 IN IP4 198.51.100.20\r\ns=-\r\nc=IN IP4 198.51.100.20\r\nt=0 0\r\nm=audio 50000 RTP/AVP 0 101\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:101 telephone-event/8000\r\n"

// checkDigest verifies an Authorization value the way a real server would, using icholy/digest.
func checkDigest(t *testing.T, hdr, method, realm, nonce, alg, user, pass string) bool {
	t.Helper()
	cred, err := icholy.ParseCredentials(hdr)
	if err != nil {
		t.Errorf("unparsable credentials: %v", err)
		return false
	}
	if cred.Nonce != nonce || cred.Realm != realm || cred.Username != user {
		return false
	}
	want, err := icholy.Digest(&icholy.Challenge{Realm: realm, Nonce: nonce, Algorithm: alg, QOP: []string{"auth"}},
		icholy.Options{Method: method, URI: cred.URI, Username: user, Password: pass, Cnonce: cred.Cnonce, Count: cred.Nc})
	return err == nil && want.Response == cred.Response
}

type binding struct {
	contact   sip.Uri
	expires   int
	source    string // the gateway's address as the provider sees it (the flow)
	transport string
}

type fakeProvider struct {
	t         *testing.T
	ua        *sipgo.UserAgent
	srv       *sipgo.Server
	cli       *sipgo.Client
	ln        net.Listener
	addr      string
	user      string
	pass      string
	realm     string
	nonce     string
	server    *sipgo.DialogServerCache
	transport string // "tcp" or "tls"

	mu       sync.Mutex
	binding  *binding
	calls    []*sipgo.DialogClientSession
	register chan *sip.Request // every REGISTER, as received
	accepted chan *sip.Request // REGISTERs that passed auth
	invites  chan *sip.Request // outbound INVITEs (after auth)
	byes     chan *sip.Request
}

func newFakeProvider(t *testing.T, user, pass string) *fakeProvider {
	return newFakeProviderTLS(t, user, pass, nil)
}

// newFakeProviderTLS serves TLS with cert when it is not nil, else TCP.
func newFakeProviderTLS(t *testing.T, user, pass string, cert *tls.Certificate) *fakeProvider {
	transport := "tcp"
	if cert != nil {
		transport = "tls"
	}
	return newFakeProviderOn(t, user, pass, transport, cert)
}

// newFakeProviderOn serves on transport "udp", "tcp" or "tls" (with cert).
func newFakeProviderOn(t *testing.T, user, pass, transport string, cert *tls.Certificate) *fakeProvider {
	ua, err := sipgo.NewUA(sipgo.WithUserAgent("FakeProvider"))
	if err != nil {
		t.Fatal(err)
	}
	var ln net.Listener
	var pc net.PacketConn
	addr := ""
	if transport == "udp" {
		if pc, err = net.ListenPacket("udp", "127.0.0.1:0"); err != nil {
			t.Fatal(err)
		}
		addr = pc.LocalAddr().String()
	} else {
		if ln, err = net.Listen("tcp", "127.0.0.1:0"); err != nil {
			t.Fatal(err)
		}
		if transport == "tls" {
			ln = tls.NewListener(ln, &tls.Config{Certificates: []tls.Certificate{*cert}})
		}
		addr = ln.Addr().String()
	}
	p := &fakeProvider{
		t: t, ua: ua, ln: ln, addr: addr, user: user, pass: pass,
		realm: "provider.test", nonce: "prov-nonce-" + strconv.FormatInt(time.Now().UnixNano(), 36),
		register: make(chan *sip.Request, 32), accepted: make(chan *sip.Request, 32),
		invites: make(chan *sip.Request, 8), byes: make(chan *sip.Request, 8), transport: transport,
	}
	p.srv, _ = sipgo.NewServer(ua)
	p.cli, _ = sipgo.NewClient(ua)
	host, port := splitHP(p.addr)
	p.server = sipgo.NewDialogServerCache(p.cli, sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: "provider", Host: host, Port: port, UriParams: params("transport", transport)}})

	p.srv.OnRegister(p.onRegister)
	p.srv.OnInvite(p.onInvite)
	p.srv.OnAck(func(req *sip.Request, tx sip.ServerTransaction) { _ = p.server.ReadAck(req, tx) })
	p.srv.OnBye(func(req *sip.Request, tx sip.ServerTransaction) {
		p.byes <- req
		if err := p.server.ReadBye(req, tx); err == nil {
			return
		}
		p.mu.Lock()
		calls := append([]*sipgo.DialogClientSession{}, p.calls...)
		p.mu.Unlock()
		for _, c := range calls {
			if c.InviteRequest.CallID().Value() == req.CallID().Value() {
				_ = c.ReadBye(req, tx)
				return
			}
		}
		_ = tx.Respond(sip.NewResponseFromRequest(req, 481, "No Dialog", nil))
	})
	p.srv.OnOptions(func(req *sip.Request, tx sip.ServerTransaction) {
		_ = tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
	})
	switch transport {
	case "udp":
		go p.srv.ServeUDP(pc)
		t.Cleanup(func() { pc.Close(); ua.Close() })
	case "tls":
		go p.srv.ServeTLS(ln)
		t.Cleanup(func() { ln.Close(); ua.Close() })
	default:
		go p.srv.ServeTCP(ln)
		t.Cleanup(func() { ln.Close(); ua.Close() })
	}
	return p
}

func (p *fakeProvider) onRegister(req *sip.Request, tx sip.ServerTransaction) {
	p.register <- req
	auth := req.GetHeader("Authorization")
	if auth == nil {
		res := sip.NewResponseFromRequest(req, 401, "Unauthorized", nil)
		res.AppendHeader(sip.NewHeader("WWW-Authenticate", fmt.Sprintf(`Digest realm="%s", nonce="%s", algorithm=SHA-256, qop="auth"`, p.realm, p.nonce)))
		_ = tx.Respond(res)
		return
	}
	if !checkDigest(p.t, auth.Value(), "REGISTER", p.realm, p.nonce, "SHA-256", p.user, p.pass) {
		_ = tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return
	}
	ct := req.Contact()
	expires := 3600
	if v := req.GetHeader("Expires"); v != nil {
		expires, _ = strconv.Atoi(v.Value())
	}
	if ct != nil {
		if v, ok := ct.Params.Get("expires"); ok {
			expires, _ = strconv.Atoi(v)
		}
	}
	p.mu.Lock()
	if expires == 0 {
		p.binding = nil
	} else if ct != nil {
		p.binding = &binding{contact: ct.Address, expires: expires, source: req.Source(), transport: req.Transport()}
	}
	p.mu.Unlock()
	p.accepted <- req
	res := sip.NewResponseFromRequest(req, 200, "OK", nil)
	if ct != nil && expires > 0 {
		c := ct.Clone()
		c.Params.Add("expires", strconv.Itoa(expires))
		res.AppendHeader(c)
	}
	_ = tx.Respond(res)
}

// onInvite answers the gateway's outbound calls: 407 first, then 180 and 200 with SDP.
func (p *fakeProvider) onInvite(req *sip.Request, tx sip.ServerTransaction) {
	auth := req.GetHeader("Proxy-Authorization")
	if auth == nil {
		res := sip.NewResponseFromRequest(req, 407, "Proxy Authentication Required", nil)
		res.AppendHeader(sip.NewHeader("Proxy-Authenticate", fmt.Sprintf(`Digest realm="%s", nonce="%s", algorithm=SHA-256, qop="auth"`, p.realm, p.nonce)))
		_ = tx.Respond(res)
		return
	}
	if !checkDigest(p.t, auth.Value(), "INVITE", p.realm, p.nonce, "SHA-256", p.user, p.pass) {
		_ = tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return
	}
	p.invites <- req
	d, err := p.server.ReadInvite(req, tx)
	if err != nil {
		p.t.Errorf("provider ReadInvite: %v", err)
		return
	}
	_ = d.Respond(180, "Ringing", nil)
	_ = d.RespondSDP([]byte(answerSDP))
	<-d.Context().Done()
}

func (p *fakeProvider) currentBinding() *binding {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.binding == nil {
		return nil
	}
	b := *p.binding
	return &b
}

// ring places a call to the gateway: to Request-URI ruri, over the registered connection.
func (p *fakeProvider) ring(ctx context.Context, ruri sip.Uri, flow, from, to string, hdrs ...sip.Header) (*sipgo.DialogClientSession, error) {
	req := sip.NewRequest(sip.INVITE, ruri)
	req.AppendHeader(&sip.FromHeader{DisplayName: "Alice Caller", Address: sip.Uri{Scheme: "sip", User: from, Host: "provider.test"}, Params: params("tag", sip.GenerateTagN(10))})
	req.AppendHeader(&sip.ToHeader{Address: sip.Uri{Scheme: "sip", User: to, Host: "provider.test"}, Params: sip.NewParams()})
	for _, h := range hdrs {
		req.AppendHeader(h)
	}
	req.AppendHeader(sip.NewHeader("Content-Type", "application/sdp"))
	req.SetBody([]byte(offerSDP))
	req.SetTransport(strings.ToUpper(p.transport))
	req.SetDestination(flow)
	host, port := splitHP(p.addr)
	ua := sipgo.DialogUA{Client: p.cli, RewriteContact: true,
		ContactHDR: sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: "caller", Host: host, Port: port, UriParams: params("transport", p.transport)}}}
	s, err := ua.WriteInvite(ctx, req)
	if err != nil {
		return nil, err
	}
	p.mu.Lock()
	p.calls = append(p.calls, s)
	p.mu.Unlock()
	return s, nil
}

// fakeLiveKit is LiveKit SIP as the gateway sees it.
type fakeLiveKit struct {
	t       *testing.T
	ua      *sipgo.UserAgent
	srv     *sipgo.Server
	cli     *sipgo.Client
	addr    string
	user    string
	pass    string
	realm   string
	nonce   string
	cache   *sipgo.DialogServerCache
	contact sip.ContactHeader

	mu            sync.Mutex
	ringOnly      bool // ring but never answer
	forgetCalls   bool // act as if restarted: in-call OPTIONS get 481
	inCallHandler sipgo.RequestHandler
	sessions      []*sipgo.DialogServerSession
	out           []*sipgo.DialogClientSession
	invites       chan *sip.Request // INVITEs that passed auth
	cancels       chan *sip.Request
	byes          chan *sip.Request
	acks          chan *sip.Request
	inCall        chan *sip.Request // re-INVITE / UPDATE / INFO inside a call
}

func newFakeLiveKit(t *testing.T, user, pass string) *fakeLiveKit {
	ua, err := sipgo.NewUA(sipgo.WithUserAgent("FakeLiveKit"))
	if err != nil {
		t.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	lk := &fakeLiveKit{
		t: t, ua: ua, addr: ln.Addr().String(), user: user, pass: pass, realm: "livekit.test", nonce: "lk-nonce-1",
		invites: make(chan *sip.Request, 8), cancels: make(chan *sip.Request, 8), byes: make(chan *sip.Request, 8), acks: make(chan *sip.Request, 8),
		inCall: make(chan *sip.Request, 8),
	}
	lk.srv, _ = sipgo.NewServer(ua)
	lk.cli, _ = sipgo.NewClient(ua)
	host, port := splitHP(lk.addr)
	lk.contact = sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: "livekit", Host: host, Port: port, UriParams: params("transport", "tcp")}}
	lk.cache = sipgo.NewDialogServerCache(lk.cli, lk.contact)
	lk.srv.OnInvite(lk.onInvite)
	inCall := func(req *sip.Request, tx sip.ServerTransaction) {
		lk.inCall <- req
		res := sip.NewResponseFromRequest(req, 200, "OK", nil)
		if req.IsInvite() || req.Method == sip.UPDATE {
			res = sip.NewSDPResponseFromRequest(req, []byte(strings.Replace(answerSDP, "a=rtpmap:0", "a=recvonly\r\na=rtpmap:0", 1)))
			res.AppendHeader(lk.contact.Clone())
		}
		_ = tx.Respond(res)
	}
	lk.srv.OnInfo(inCall)
	lk.srv.OnUpdate(inCall)
	lk.inCallHandler = inCall
	lk.srv.OnAck(func(req *sip.Request, tx sip.ServerTransaction) {
		lk.acks <- req
		_ = lk.cache.ReadAck(req, tx)
	})
	lk.srv.OnBye(func(req *sip.Request, tx sip.ServerTransaction) {
		lk.byes <- req
		if err := lk.cache.ReadBye(req, tx); err == nil {
			return
		}
		lk.mu.Lock()
		out := append([]*sipgo.DialogClientSession{}, lk.out...)
		lk.mu.Unlock()
		for _, c := range out {
			if c.InviteRequest.CallID().Value() == req.CallID().Value() {
				_ = c.ReadBye(req, tx)
				return
			}
		}
		_ = tx.Respond(sip.NewResponseFromRequest(req, 481, "No Dialog", nil))
	})
	lk.srv.OnOptions(func(req *sip.Request, tx sip.ServerTransaction) {
		lk.mu.Lock()
		forgot := lk.forgetCalls
		lk.mu.Unlock()
		if tag, _ := req.To().Params.Get("tag"); tag != "" && forgot {
			_ = tx.Respond(sip.NewResponseFromRequest(req, 481, "Call/Transaction Does Not Exist", nil))
			return
		}
		_ = tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
	})
	go lk.srv.ServeTCP(ln)
	t.Cleanup(func() { ln.Close(); ua.Close() })
	return lk
}

func (lk *fakeLiveKit) onInvite(req *sip.Request, tx sip.ServerTransaction) {
	if tag, _ := req.To().Params.Get("tag"); tag != "" {
		lk.inCallHandler(req, tx) // re-INVITE
		return
	}
	auth := req.GetHeader("Proxy-Authorization")
	if auth == nil {
		res := sip.NewResponseFromRequest(req, 407, "Proxy Authentication Required", nil)
		res.AppendHeader(sip.NewHeader("Proxy-Authenticate", fmt.Sprintf(`Digest realm="%s", nonce="%s", algorithm=MD5, qop="auth"`, lk.realm, lk.nonce)))
		_ = tx.Respond(res)
		return
	}
	if !checkDigest(lk.t, auth.Value(), "INVITE", lk.realm, lk.nonce, "MD5", lk.user, lk.pass) {
		_ = tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return
	}
	tx.OnCancel(func(r *sip.Request) { lk.cancels <- r })
	lk.invites <- req
	d, err := lk.cache.ReadInvite(req, tx)
	if err != nil {
		lk.t.Errorf("livekit ReadInvite: %v", err)
		return
	}
	lk.mu.Lock()
	lk.sessions = append(lk.sessions, d)
	ringOnly := lk.ringOnly
	lk.mu.Unlock()
	_ = d.Respond(180, "Ringing", nil)
	if ringOnly {
		<-tx.Done()
		return
	}
	_ = d.RespondSDP([]byte(answerSDP))
	<-d.Context().Done()
}

// lastSession is the most recent inbound call LiveKit answered.
func (lk *fakeLiveKit) lastSession() *sipgo.DialogServerSession {
	lk.mu.Lock()
	defer lk.mu.Unlock()
	if len(lk.sessions) == 0 {
		return nil
	}
	return lk.sessions[len(lk.sessions)-1]
}

// dial places an outbound call through the gateway's internal listener.
func (lk *fakeLiveKit) dial(ctx context.Context, gwInternal, number string, user, pass string, hdrs ...sip.Header) (*sipgo.DialogClientSession, error) {
	host, port := splitHP(gwInternal)
	lhost, lport := splitHP(lk.addr)
	ua := sipgo.DialogUA{Client: lk.cli, ContactHDR: sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: "livekit", Host: lhost, Port: lport, UriParams: params("transport", "tcp")}}}
	req := sip.NewRequest(sip.INVITE, sip.Uri{Scheme: "sip", User: number, Host: host, Port: port, UriParams: params("transport", "tcp")})
	for _, h := range hdrs {
		req.AppendHeader(h)
	}
	req.AppendHeader(sip.NewHeader("Content-Type", "application/sdp"))
	req.SetBody([]byte(offerSDP))
	req.SetTransport("TCP")
	s, err := ua.WriteInvite(ctx, req)
	if err != nil {
		return nil, err
	}
	lk.mu.Lock()
	lk.out = append(lk.out, s)
	lk.mu.Unlock()
	return s, s.WaitAnswer(ctx, sipgo.AnswerOptions{Username: user, Password: pass})
}

func params(kv ...string) sip.HeaderParams {
	p := sip.NewParams()
	for i := 0; i+1 < len(kv); i += 2 {
		p.Add(kv[i], kv[i+1])
	}
	return p
}

func splitHP(hp string) (string, int) {
	h, p, _ := net.SplitHostPort(hp)
	n, _ := strconv.Atoi(p)
	return h, n
}

// recv waits for one value from ch.
func recv[T any](t *testing.T, ch <-chan T, what string) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(10 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
		var zero T
		return zero
	}
}

// eventually polls cond until it holds.
func eventually(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}
