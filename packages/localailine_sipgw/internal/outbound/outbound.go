// Package outbound places calls for LiveKit SIP through a line's provider.
//
// LiveKit's outbound trunk points at the gateway's internal listener. Its INVITE carries the
// number to call in the Request-URI and the line in X-LL-Line, and must answer our digest
// challenge with the shared outbound credentials. The call then goes to that line's provider
// with the line's own number as caller ID — never anything the request asks for — signed in
// with the line's password, over the connection the line is registered on.
//
// Only the internal listener reaches this handler, and without valid credentials nothing is
// placed: the gateway is never an open relay.
package outbound

import (
	"context"
	"log/slog"
	"regexp"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/bridge"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/digest"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/ratelimit"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/registrar"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// Handler handles new INVITEs on the internal listener.
type Handler struct {
	Core     *bridge.Core
	Accounts *account.Registry
	Flows    func(id string) (registrar.Flow, bool)
	Trust    *bridge.ProviderTrust
	Metrics  *metrics.Metrics
	Log      *slog.Logger
	Ctx      context.Context

	// Shared credentials LiveKit's outbound trunk uses; empty Password = outbound calls off.
	User, Password string
	Challenger     *digest.Server
	// FailLimit counts failed sign-ins per source address; while it is empty, refuse.
	FailLimit *ratelimit.Limiter

	// ProviderSide is the leg towards line a's provider, sending to dest over transport.
	ProviderSide func(a account.Account, transport, dest string) *sipx.Side
	// InternalSide is the leg back to LiveKit, answering a request from dest over transport.
	InternalSide func(transport, dest string) *sipx.Side

	DefaultCountryCode string
}

var dialable = regexp.MustCompile(`^\+?[0-9]{2,20}$`)

// HandleInvite authenticates LiveKit, picks the line and bridges the call to its provider.
func (h *Handler) HandleInvite(req *sip.Request, tx sip.ServerTransaction) {
	reject := func(code int, why string, hdrs ...sip.Header) {
		if code != 407 {
			h.Metrics.CallsRejected.Add(1)
		}
		h.Log.Debug("outbound INVITE refused", "code", code, "why", why, "source", req.Source())
		bridge.Respond(tx, req, code, reason(code), hdrs...)
	}
	src, ok := sipx.SourceAddr(req.Source())
	if !ok {
		reject(403, "no source address")
		return
	}
	ip := src.Addr().String()
	if h.Password == "" {
		reject(403, "outbound calling is not configured (no outbound credentials)")
		return
	}
	if h.FailLimit.Blocked(ip) {
		reject(403, "too many failed sign-ins from this address")
		return
	}

	// 1. Who is asking? Digest with the shared outbound credentials.
	auth := sipx.Header(req, "Proxy-Authorization")
	if auth == "" {
		auth = sipx.Header(req, "Authorization")
	}
	if auth == "" {
		reject(407, "challenge", sip.NewHeader("Proxy-Authenticate", h.Challenger.Challenge(false)))
		return
	}
	ok, stale := h.Challenger.Verify(auth, string(sip.INVITE), h.User, h.Password)
	// The answer must be for this very number: a captured answer can't be replayed to call another.
	if c, err := digest.ParseCredentials(auth); err != nil || uriUser(c.URI) != req.Recipient.User {
		ok, stale = false, false
	}
	if stale {
		reject(407, "stale nonce", sip.NewHeader("Proxy-Authenticate", h.Challenger.Challenge(true)))
		return
	}
	if !ok {
		h.FailLimit.Allow(ip)
		reject(403, "wrong outbound credentials")
		return
	}

	// 2. Which line? X-LL-Line, or else the line whose number is the caller ID asked for.
	var acc account.Account
	if id := sipx.Header(req, "X-LL-Line"); id != "" {
		acc, ok = h.Accounts.Get(id)
	} else if f := req.From(); f != nil {
		if n, okN := account.NormalizeE164(f.Address.User, ""); okN {
			acc, ok = h.Accounts.ByNumber(n)
		}
	}
	if !ok {
		reject(404, "no such line")
		return
	}
	if acc.Mode != account.ModeOn {
		reject(403, "line is off")
		return
	}

	// 3. Whom to call.
	cc := acc.CountryCode
	if cc == "" {
		cc = h.DefaultCountryCode
	}
	target, okT := account.NormalizeE164(req.Recipient.User, cc)
	if !okT {
		target = req.Recipient.User
		if !dialable.MatchString(target) {
			reject(484, "number to call is not a phone number")
			return
		}
	}
	mf := 70
	if m := req.MaxForwards(); m != nil {
		if m.Val() <= 1 {
			bridge.Respond(tx, req, 483, "Too Many Hops")
			return
		}
		mf = int(m.Val()) - 1
	}

	// 4. The INVITE to the provider: the line's number as caller, nothing from the request.
	transport := acc.SIPTransport()
	dest := acc.RegistrarAddr()
	if f, ok := h.Flows(acc.ID); ok {
		dest = f.Addr // the connection the line is registered on (NAT-friendly, and what the provider expects)
	}
	ruri := sip.Uri{Scheme: "sip", User: target, Host: acc.Domain, UriParams: sipx.URIParams(transport)}
	if acc.Port != sip.DefaultPort(acc.Transport) {
		ruri.Port = acc.Port
	}
	me := sip.Uri{Scheme: "sip", User: acc.Number, Host: acc.Domain}
	bReq := sip.NewRequest(sip.INVITE, ruri)
	bReq.AppendHeader(&sip.FromHeader{Address: me, Params: sip.NewParams()})
	bReq.AppendHeader(&sip.ToHeader{Address: sip.Uri{Scheme: "sip", User: target, Host: acc.Domain}, Params: sip.NewParams()})
	bReq.AppendHeader(sip.NewHeader("P-Asserted-Identity", "<"+me.String()+">"))
	maxf := sip.MaxForwardsHeader(mf)
	bReq.AppendHeader(&maxf)
	if acc.OutboundProxy != "" {
		bReq.AppendHeader(&sip.RouteHeader{Address: sip.Uri{Scheme: "sip", Host: hostOf(acc.OutboundProxy), Port: portOf(acc.OutboundProxy), UriParams: sipx.Params("lr", "")}})
	}
	if len(req.Body()) > 0 {
		if ct := sipx.Header(req, "Content-Type"); ct != "" && sipx.SafeToken(ct) {
			bReq.AppendHeader(sip.NewHeader("Content-Type", ct))
		}
	}
	bReq.SetBody(req.Body())

	h.Metrics.CallsOut.Add(1)
	h.Log.Info("outgoing call", "line", acc.ID, "to", target)
	a := acc
	h.Core.Run(h.Ctx, bridge.Spec{
		Dir: "out", Line: acc.ID,
		AReq: req, ATx: tx,
		ASide: h.InternalSide(req.Transport(), req.Source()),
		BReq:  bReq,
		BSide: h.ProviderSide(acc, transport, dest),
		BTrust: func(r *sip.Request) bool {
			return h.Trust.Allowed(a, r)
		},
		BAuth: &bridge.Creds{Username: acc.AuthUser(), Password: acc.Password, Realm: acc.Realm},
	})
}

func reason(code int) string {
	switch code {
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 407:
		return "Proxy Authentication Required"
	case 484:
		return "Address Incomplete"
	}
	return "Error"
}
