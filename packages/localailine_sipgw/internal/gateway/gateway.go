// Package gateway puts the pieces together: the provider-facing SIP listeners, the internal
// listener LiveKit talks to, the registrar, the call bridge, the control API and the store.
//
// Two separate SIP stacks keep the two worlds apart: the provider stack faces the internet
// (registrations, inbound calls, outbound legs to providers); the internal stack faces LiveKit
// (inbound legs to LiveKit, and the only place outbound calls are accepted).
package gateway

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/api"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/bridge"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/config"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/digest"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/dnscache"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/outbound"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/ratelimit"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/registrar"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/store"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/stun"
)

// UserAgent is the name the gateway gives itself in SIP.
const UserAgent = "LocalAILine-SIPGW"

var sipLogOnce sync.Once

// InitSIPLogging routes sipgo's own logs through h: demoted to debug, with raw messages and
// credentials removed. sipgo's logger is process-wide, so the first call wins; call it before
// any SIP stack starts (New does).
func InitSIPLogging(h slog.Handler) {
	sipLogOnce.Do(func() { sip.SetDefaultLogger(slog.New(sipx.QuietHandler{H: h})) })
}

// Options beyond the config file (for tests).
type Options struct {
	DNS      dnscache.Resolver // nil = system resolver
	Registry *registrar.Options
}

// Gateway is one running instance.
type Gateway struct {
	cfg     *config.Config
	log     *slog.Logger
	metrics *metrics.Metrics

	accounts *account.Registry
	store    *store.Store
	reg      *registrar.Manager
	core     *bridge.Core
	trust    *bridge.ProviderTrust
	inbound  *bridge.Inbound
	outbound *outbound.Handler
	api      *api.Server

	provUA, intUA         *sipgo.UserAgent
	provSrv, intSrv       *sipgo.Server
	provClient, intClient *sipgo.Client

	// Listeners (bound in New, served in Run).
	provUDP          net.PacketConn
	provTCP, provTLS net.Listener
	intUDP           net.PacketConn
	intTCP           net.Listener
	control          net.Listener
	httpSrv          *http.Server

	udpLaddr    *sip.Addr // provider UDP listener as a sipgo local address
	intUDPLaddr *sip.Addr
	stunHost    atomic.Value // string

	callCtx    context.Context
	callCancel context.CancelFunc
	persistMu  sync.Mutex
}

// New binds every listener and loads saved lines; nothing is served until Run.
func New(cfg *config.Config, log *slog.Logger, opt Options) (*Gateway, error) {
	g := &Gateway{cfg: cfg, log: log, metrics: &metrics.Metrics{}, accounts: account.NewRegistry()}
	g.stunHost.Store("")
	g.callCtx, g.callCancel = context.WithCancel(context.Background())
	ok := false
	defer func() {
		if !ok {
			g.closeListeners()
		}
	}()

	InitSIPLogging(log.Handler())

	if cfg.StoreFile != "" {
		key, err := store.ParseKey(cfg.StoreKey)
		if err != nil {
			return nil, err
		}
		if g.store, err = store.New(cfg.StoreFile, key); err != nil {
			return nil, err
		}
	}

	// SIP stacks.
	tlsConf, err := providerTLS(cfg)
	if err != nil {
		return nil, err
	}
	stray := func(r *sip.Response) {
		if g.core != nil {
			g.core.StrayResponse(r)
		}
	}
	newUA := func(tc *tls.Config) (*sipgo.UserAgent, error) {
		p := sip.NewParser()
		p.MaxMessageLength = cfg.MaxMessageBytes
		opts := []sipgo.UserAgentOption{
			sipgo.WithUserAgent(UserAgent),
			sipgo.WithUserAgentParser(p),
			sipgo.WithUserAgentTransactionLayerOptions(
				sip.WithTransactionLayerUnhandledResponseHandler(stray),
				sip.WithTransactionLayerTerminateOnConnClose(),
			),
		}
		if tc != nil {
			opts = append(opts, sipgo.WithUserAgenTLSConfig(tc))
		}
		return sipgo.NewUA(opts...)
	}
	if g.provUA, err = newUA(tlsConf); err != nil {
		return nil, err
	}
	if g.intUA, err = newUA(nil); err != nil {
		return nil, err
	}
	g.provSrv, _ = sipgo.NewServer(g.provUA)
	g.intSrv, _ = sipgo.NewServer(g.intUA)
	g.provClient, _ = sipgo.NewClient(g.provUA)
	g.intClient, _ = sipgo.NewClient(g.intUA)

	if err := g.bind(); err != nil {
		return nil, err
	}

	// Registrar, trust, bridge.
	ro := registrar.Options{}
	if opt.Registry != nil {
		ro = *opt.Registry
	}
	ro.Client, ro.Transport, ro.Addressing = g.provClient, g.provUA.TransportLayer(), g
	ro.Keepalive, ro.Metrics, ro.Log, ro.UserAgent = cfg.KeepaliveInterval.Duration, g.metrics, log, UserAgent
	g.reg = registrar.New(ro)
	g.trust = &bridge.ProviderTrust{DNS: dnscache.New(opt.DNS), Flows: g.reg.Flow}
	g.core = bridge.NewCore(bridge.Options{
		Log: log, Metrics: g.metrics, UserAgent: UserAgent,
		RingTimeout: cfg.RingTimeout.Duration, MaxDuration: cfg.MaxCallDuration.Duration, ProbeInterval: cfg.CallProbeInterval.Duration,
	})
	intHost, _ := cfg.InternalAdvertised()
	var lkAuth *bridge.Creds
	if cfg.LiveKitUser != "" {
		lkAuth = &bridge.Creds{Username: cfg.LiveKitUser, Password: cfg.LiveKitPass}
	}
	g.inbound = &bridge.Inbound{
		Core: g.core, Accounts: g.accounts, Trust: g.trust, Metrics: g.metrics, Log: log, Ctx: g.callCtx,
		Limit:        ratelimit.New(cfg.InboundRate, cfg.InboundBurst),
		ProviderSide: g.providerSide, LiveKitSide: g.liveKitSide, LiveKitAuth: lkAuth,
		InternalHost: intHost, DefaultCountryCode: cfg.DefaultCountryCode,
	}
	g.outbound = &outbound.Handler{
		Core: g.core, Accounts: g.accounts, Flows: g.reg.Flow, Trust: g.trust, Metrics: g.metrics, Log: log, Ctx: g.callCtx,
		User: cfg.OutboundUser, Password: cfg.OutboundPass, Challenger: digest.NewServer(cfg.OutboundRealm, "MD5"),
		FailLimit:    ratelimit.New(1.0/10, 5),
		ProviderSide: g.providerSide, InternalSide: g.internalSide, DefaultCountryCode: cfg.DefaultCountryCode,
	}
	g.routes()
	g.api = api.New(g, cfg.ControlToken, g.metrics, log)

	// Saved lines.
	if g.store != nil {
		saved, err := g.store.Load()
		if err != nil {
			return nil, err
		}
		for _, a := range saved {
			if err := a.Normalize(); err != nil {
				log.Warn("saved line skipped", "line", a.ID, "error", err)
				continue
			}
			g.accounts.Put(a)
		}
		if len(saved) > 0 {
			log.Info("lines loaded from the store", "count", g.accounts.Len())
		}
	}
	if cfg.OutboundPass == "" {
		log.Warn("no outbound credentials: outbound calls are refused")
	}
	ok = true
	return g, nil
}

// providerTLS is the client TLS config for providers: system roots plus provider_ca_file.
func providerTLS(cfg *config.Config) (*tls.Config, error) {
	tc := &tls.Config{MinVersion: tls.VersionTLS12}
	if cfg.ProviderCAFile != "" {
		pool, err := x509.SystemCertPool()
		if err != nil || pool == nil {
			pool = x509.NewCertPool()
		}
		pem, err := os.ReadFile(cfg.ProviderCAFile)
		if err != nil {
			return nil, err
		}
		if !pool.AppendCertsFromPEM(pem) {
			return nil, errors.New("provider_ca_file has no PEM certificates")
		}
		tc.RootCAs = pool
	}
	return tc, nil
}

// bind opens every listener.
func (g *Gateway) bind() error {
	cfg := g.cfg
	var err error
	if cfg.SIPUDP != "" {
		if g.provUDP, err = net.ListenPacket("udp", cfg.SIPUDP); err != nil {
			return fmt.Errorf("sip_udp %s: %w", cfg.SIPUDP, err)
		}
		g.udpLaddr = laddrOf(g.provUDP.LocalAddr().String())
	}
	if cfg.SIPTCP != "" {
		if g.provTCP, err = net.Listen("tcp", cfg.SIPTCP); err != nil {
			return fmt.Errorf("sip_tcp %s: %w", cfg.SIPTCP, err)
		}
	}
	if cfg.SIPTLS != "" && cfg.TLSCert != "" {
		cert, err := tls.LoadX509KeyPair(cfg.TLSCert, cfg.TLSKey)
		if err != nil {
			return fmt.Errorf("tls_cert/tls_key: %w", err)
		}
		l, err := net.Listen("tcp", cfg.SIPTLS)
		if err != nil {
			return fmt.Errorf("sip_tls %s: %w", cfg.SIPTLS, err)
		}
		g.provTLS = tls.NewListener(l, &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12})
	}
	if g.intTCP, err = net.Listen("tcp", cfg.InternalListen); err != nil {
		return fmt.Errorf("internal_listen %s: %w", cfg.InternalListen, err)
	}
	// UDP on the same port as TCP (so a LiveKit trunk set to either transport works).
	if g.intUDP, err = net.ListenPacket("udp", g.intTCP.Addr().String()); err != nil {
		return fmt.Errorf("internal_listen (udp) %s: %w", cfg.InternalListen, err)
	}
	g.intUDPLaddr = laddrOf(g.intUDP.LocalAddr().String())
	if g.control, err = net.Listen("tcp", cfg.ControlListen); err != nil {
		return fmt.Errorf("control_listen %s: %w", cfg.ControlListen, err)
	}
	return nil
}

func laddrOf(s string) *sip.Addr {
	h, p, _ := net.SplitHostPort(s)
	port, _ := strconv.Atoi(p)
	return &sip.Addr{IP: net.ParseIP(h), Port: port, Hostname: h}
}

func (g *Gateway) closeListeners() {
	for _, c := range []io.Closer{g.provUDP, g.provTCP, g.provTLS, g.intUDP, g.intTCP, g.control} {
		if c != nil {
			c.Close()
		}
	}
}

// routes installs the SIP handlers on both stacks.
func (g *Gateway) routes() {
	inDialog := func(side string) sipgo.RequestHandler {
		return func(req *sip.Request, tx sip.ServerTransaction) { g.core.InDialog(side, req, tx) }
	}
	for _, s := range []struct {
		srv  *sipgo.Server
		side string
		inv  sipgo.RequestHandler
	}{
		{g.provSrv, "provider", g.inbound.HandleInvite},
		{g.intSrv, "internal", g.outbound.HandleInvite},
	} {
		h, newCall := inDialog(s.side), s.inv
		s.srv.OnInvite(func(req *sip.Request, tx sip.ServerTransaction) {
			if bridge.IsInDialog(req) {
				h(req, tx)
				return
			}
			newCall(req, tx)
		})
		for _, m := range []sip.RequestMethod{sip.ACK, sip.BYE, sip.CANCEL, sip.UPDATE, sip.INFO, sip.NOTIFY, sip.REFER, sip.MESSAGE, sip.PRACK} {
			s.srv.OnRequest(m, h)
		}
		limit := g.inbound.Limit
		s.srv.OnOptions(func(req *sip.Request, tx sip.ServerTransaction) {
			if bridge.IsInDialog(req) {
				h(req, tx)
				return
			}
			// A ping (provider health check or LiveKit). Answer, unless someone is flooding us.
			if src, ok := sipx.SourceAddr(req.Source()); ok && !limit.Allow(src.Addr().String()) {
				return
			}
			bridge.Respond(tx, req, 200, "OK", sip.NewHeader("Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, INFO, UPDATE, NOTIFY, REFER, MESSAGE"))
		})
	}
}

// Run serves until ctx ends, then hangs up calls, signs lines out (if configured) and stops.
func (g *Gateway) Run(ctx context.Context) error {
	errc := make(chan error, 8)
	serve := func(name string, f func() error) {
		go func() {
			if err := f(); err != nil && ctx.Err() == nil && !errors.Is(err, net.ErrClosed) && !errors.Is(err, http.ErrServerClosed) {
				errc <- fmt.Errorf("%s: %w", name, err)
			}
		}()
	}
	if g.provUDP != nil {
		serve("sip udp", func() error { return g.provSrv.ServeUDP(g.provUDP) })
	}
	if g.provTCP != nil {
		serve("sip tcp", func() error { return g.provSrv.ServeTCP(g.provTCP) })
	}
	if g.provTLS != nil {
		serve("sip tls", func() error { return g.provSrv.ServeTLS(g.provTLS) })
	}
	serve("internal tcp", func() error { return g.intSrv.ServeTCP(g.intTCP) })
	serve("internal udp", func() error { return g.intSrv.ServeUDP(g.intUDP) })
	g.waitUDPReady()

	g.httpSrv = &http.Server{
		Handler: g.api, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second,
		WriteTimeout: 60 * time.Second, IdleTimeout: 2 * time.Minute, MaxHeaderBytes: 16 << 10,
		ErrorLog: slog.NewLogLogger(g.log.Handler(), slog.LevelDebug),
	}
	if g.cfg.ControlTLSCert != "" {
		tc, err := g.controlTLS()
		if err != nil {
			return err
		}
		g.httpSrv.TLSConfig = tc
		serve("control api", func() error { return g.httpSrv.ServeTLS(g.control, "", "") })
	} else {
		serve("control api", func() error { return g.httpSrv.Serve(g.control) })
	}

	if g.cfg.PublicHost == "" && g.cfg.STUNServer != "" {
		go g.stunLoop(ctx)
	}
	for _, a := range g.accounts.All() {
		g.reg.Apply(a)
		g.trust.Warm(a)
	}
	g.log.Info("sipgw running", "provider_udp", addrOf(g.provUDP), "provider_tcp", addrOf(g.provTCP), "provider_tls", addrOf(g.provTLS),
		"internal", g.intTCP.Addr().String(), "livekit", g.cfg.LiveKitAddr, "control", g.control.Addr().String(), "lines", g.accounts.Len())

	var runErr error
	select {
	case <-ctx.Done():
	case runErr = <-errc:
		g.log.Error("listener failed", "error", runErr)
	}
	g.shutdown()
	return runErr
}

func (g *Gateway) shutdown() {
	g.log.Info("stopping: ending calls")
	g.callCancel()
	g.core.HangupAll()
	unreg := g.cfg.UnregisterOnShutdown == nil || *g.cfg.UnregisterOnShutdown
	g.reg.Close(unreg)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if g.httpSrv != nil {
		_ = g.httpSrv.Shutdown(ctx)
	}
	g.provSrv.Close()
	g.intSrv.Close()
	g.provUA.Close()
	g.intUA.Close()
	g.closeListeners()
	g.log.Info("stopped")
}

// waitUDPReady waits until sipgo has our UDP listeners in its pool, so the first REGISTER
// leaves from the listener and not from a random port.
func (g *Gateway) waitUDPReady() {
	check := func(ua *sipgo.UserAgent, la *sip.Addr) {
		if la == nil {
			return
		}
		for range 200 {
			if c, err := ua.TransportLayer().GetConnection("udp", la.String()); err == nil && c != nil {
				c.TryClose()
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
	}
	if g.provUDP != nil {
		check(g.provUA, g.udpLaddr)
	}
	check(g.intUA, g.intUDPLaddr)
}

func (g *Gateway) controlTLS() (*tls.Config, error) {
	cert, err := tls.LoadX509KeyPair(g.cfg.ControlTLSCert, g.cfg.ControlTLSKey)
	if err != nil {
		return nil, fmt.Errorf("control_tls_cert/key: %w", err)
	}
	tc := &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12}
	if g.cfg.ControlClientCA != "" {
		pem, err := os.ReadFile(g.cfg.ControlClientCA)
		if err != nil {
			return nil, err
		}
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM(pem) {
			return nil, errors.New("control_client_ca has no PEM certificates")
		}
		tc.ClientCAs, tc.ClientAuth = pool, tls.RequireAndVerifyClientCert
	}
	return tc, nil
}

// stunLoop learns the public IP every few minutes; a change makes every line re-register.
func (g *Gateway) stunLoop(ctx context.Context) {
	for {
		sctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		ap, err := stun.PublicAddr(sctx, g.cfg.STUNServer)
		cancel()
		if err == nil {
			h := ap.Addr().String()
			if old := g.stunHost.Swap(h); old != h {
				g.log.Info("public address from STUN", "host", h)
				for _, a := range g.accounts.All() {
					g.reg.Apply(a)
				}
			}
		} else {
			g.log.Debug("STUN failed", "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(5 * time.Minute):
		}
	}
}

func addrOf(x any) string {
	switch v := x.(type) {
	case net.PacketConn:
		if v != nil {
			return v.LocalAddr().String()
		}
	case net.Listener:
		if v != nil {
			return v.Addr().String()
		}
	}
	return ""
}

// --- Addressing (for the registrar) ---

// PublicHost is the configured public host, else the STUN-learned one.
func (g *Gateway) PublicHost() string {
	if g.cfg.PublicHost != "" {
		return g.cfg.PublicHost
	}
	return g.stunHost.Load().(string)
}

// ContactPort is the port to advertise for transport.
func (g *Gateway) ContactPort(transport string) int {
	switch strings.ToUpper(transport) {
	case "UDP":
		if g.cfg.PublicUDPPort > 0 {
			return g.cfg.PublicUDPPort
		}
		if g.udpLaddr != nil {
			return g.udpLaddr.Port
		}
	case "TCP":
		if g.cfg.PublicTCPPort > 0 {
			return g.cfg.PublicTCPPort
		}
		if g.provTCP != nil {
			return g.provTCP.Addr().(*net.TCPAddr).Port
		}
	case "TLS":
		if g.cfg.PublicTLSPort > 0 {
			return g.cfg.PublicTLSPort
		}
		if g.provTLS != nil {
			return g.provTLS.Addr().(*net.TCPAddr).Port
		}
	}
	return sip.DefaultPort(transport)
}

// UDPLaddr is the provider UDP listener.
func (g *Gateway) UDPLaddr() *sip.Addr { return g.udpLaddr }

// --- Sides ---

// providerSide is how a call leg talks to line a's provider: our Contact is the line's
// registered Contact (token user), and UDP leaves from our listener.
func (g *Gateway) providerSide(a account.Account, transport, dest string) *sipx.Side {
	transport = strings.ToUpper(transport)
	host, port := "", 0
	if st := g.reg.Status(a.ID); st.Contact != "" {
		var u sip.Uri
		if sip.ParseUri(st.Contact, &u) == nil {
			host, port = u.Host, u.Port
		}
	}
	if host == "" {
		host = g.PublicHost()
		port = g.ContactPort(transport)
	}
	if host == "" {
		if ap, ok := sipx.SourceAddr(dest); ok {
			host = localIPToward(ap.Addr())
		}
	}
	s := &sipx.Side{
		Name: "provider", Client: g.provClient, Transport: transport, Dest: dest, ViaHost: host,
		Contact: sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: a.Token, Host: host, Port: port, UriParams: sipx.URIParams(transport)}},
	}
	if transport == "UDP" && g.udpLaddr != nil {
		s.Laddr, s.ViaPort = g.udpLaddr, port
	}
	return s
}

// liveKitSide is the leg to LiveKit SIP for inbound calls.
func (g *Gateway) liveKitSide() *sipx.Side {
	return g.internalSide(g.cfg.LiveKitTransport, g.cfg.LiveKitAddr)
}

// internalSide is a leg on the LiveKit side, sending to dest.
func (g *Gateway) internalSide(transport, dest string) *sipx.Side {
	transport = strings.ToUpper(transport)
	host, port := g.cfg.InternalAdvertised()
	if port == 0 {
		port = g.intTCP.Addr().(*net.TCPAddr).Port
	}
	s := &sipx.Side{
		Name: "internal", Client: g.intClient, Transport: transport, Dest: dest, ViaHost: host,
		Contact: sip.ContactHeader{Address: sip.Uri{Scheme: "sip", User: "sipgw", Host: host, Port: port, UriParams: sipx.URIParams(transport)}},
	}
	if transport == "UDP" {
		s.Laddr, s.ViaPort = g.intUDPLaddr, port
	}
	return s
}

func localIPToward(ip netip.Addr) string {
	c, err := net.Dial("udp", netip.AddrPortFrom(ip, 9).String())
	if err != nil {
		return "127.0.0.1"
	}
	defer c.Close()
	h, _, _ := net.SplitHostPort(c.LocalAddr().String())
	return h
}

// --- api.Backend ---

// Upsert adds or changes a line.
func (g *Gateway) Upsert(a account.Account) (account.View, error) {
	if old, ok := g.accounts.Get(a.ID); ok && a.Password == "" {
		a.Password = old.Password
	}
	a.Token = "" // never from outside
	if err := a.Normalize(); err != nil {
		return account.View{}, api.ErrInvalid{Err: err}
	}
	if a.Transport == "udp" && g.udpLaddr == nil {
		return account.View{}, api.ErrInvalid{Err: errors.New("transport udp needs the gateway's UDP listener (sip_udp)")}
	}
	stored := g.accounts.Put(a)
	if err := g.persist(); err != nil {
		return account.View{}, err
	}
	g.reg.Apply(stored)
	g.trust.Warm(stored)
	g.log.Info("line saved", "line", stored.ID, "mode", stored.Mode)
	return stored.View(g.status(stored)), nil
}

// Delete removes a line (signing it out first).
func (g *Gateway) Delete(id string) bool {
	if _, ok := g.accounts.Delete(id); !ok {
		return false
	}
	g.reg.Remove(id)
	if err := g.persist(); err != nil {
		g.log.Error("saving accounts failed", "error", err)
	}
	g.log.Info("line removed", "line", id)
	return true
}

// Get returns one line's view.
func (g *Gateway) Get(id string) (account.View, bool) {
	a, ok := g.accounts.Get(id)
	if !ok {
		return account.View{}, false
	}
	return a.View(g.status(a)), true
}

// List returns every line's view.
func (g *Gateway) List() []account.View {
	all := g.accounts.All()
	out := make([]account.View, 0, len(all))
	for _, a := range all {
		out = append(out, a.View(g.status(a)))
	}
	return out
}

// Test tries one REGISTER for the line.
func (g *Gateway) Test(ctx context.Context, id string) (bool, string, bool) {
	a, ok := g.accounts.Get(id)
	if !ok {
		return false, "", false
	}
	okR, words := g.reg.Test(ctx, a)
	return okR, words, true
}

// WriteMetrics writes Prometheus text.
func (g *Gateway) WriteMetrics(w io.Writer) {
	g.metrics.Write(w, metrics.Gauges{Accounts: g.accounts.Len(), AccountsRegistered: g.reg.Registered()})
}

func (g *Gateway) status(a account.Account) account.Status {
	if a.Mode != account.ModeOn {
		return account.Status{State: account.StateOff}
	}
	return g.reg.Status(a.ID)
}

func (g *Gateway) persist() error {
	if g.store == nil {
		return nil
	}
	g.persistMu.Lock()
	defer g.persistMu.Unlock()
	return g.store.Save(g.accounts.All())
}

// --- for tests and main ---

// ProviderAddr is the bound provider listener for "udp", "tcp" or "tls".
func (g *Gateway) ProviderAddr(network string) string {
	switch network {
	case "udp":
		return addrOf(g.provUDP)
	case "tcp":
		return addrOf(g.provTCP)
	case "tls":
		return addrOf(g.provTLS)
	}
	return ""
}

// InternalAddr is the bound internal listener.
func (g *Gateway) InternalAddr() string { return g.intTCP.Addr().String() }

// ControlAddr is the bound control API listener.
func (g *Gateway) ControlAddr() string { return g.control.Addr().String() }

// Metrics exposes the counters.
func (g *Gateway) Metrics() *metrics.Metrics { return g.metrics }

// ActiveCalls is the number of calls in progress.
func (g *Gateway) ActiveCalls() int { return g.core.Active() }
