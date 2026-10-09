package bridge

import (
	"context"
	"log/slog"
	"net"
	"regexp"
	"strconv"
	"strings"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/ratelimit"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// Inbound takes calls from providers and hands them to LiveKit SIP.
//
// An INVITE is accepted only if its Request-URI (or To) user is a line's token, it comes over
// that line's registered connection or from the provider's own addresses, and its source is
// not sending too many. Everything else gets 403/404 with no details, logged at debug.
type Inbound struct {
	Core     *Core
	Accounts *account.Registry
	Trust    *ProviderTrust
	Limit    *ratelimit.Limiter
	Metrics  *metrics.Metrics
	Log      *slog.Logger
	Ctx      context.Context // ends calls on shutdown

	// ProviderSide is the leg towards the provider for line a, answering a request that
	// arrived over transport from dest.
	ProviderSide func(a account.Account, transport, dest string) *sipx.Side
	// LiveKitSide is the leg towards LiveKit SIP.
	LiveKitSide func() *sipx.Side
	LiveKitAuth *Creds
	// InternalHost names the gateway towards LiveKit (From host).
	InternalHost string
	// DefaultCountryCode turns national caller numbers into E.164 when the line has none.
	DefaultCountryCode string
}

// HandleInvite is the provider listener's INVITE handler for new calls.
func (in *Inbound) HandleInvite(req *sip.Request, tx sip.ServerTransaction) {
	reject := func(code int, why string) {
		in.Metrics.CallsRejected.Add(1)
		in.Log.Debug("inbound INVITE refused", "code", code, "why", why, "source", req.Source())
		Respond(tx, req, code, sipReason(code))
	}
	src, ok := sipx.SourceAddr(req.Source())
	if !ok {
		reject(403, "no source address")
		return
	}
	if !in.Limit.Allow(src.Addr().String()) {
		reject(403, "rate limited")
		return
	}
	acc, ok := in.Accounts.ByToken(req.Recipient.User)
	if !ok && req.To() != nil {
		acc, ok = in.Accounts.ByToken(req.To().Address.User)
	}
	if !ok || acc.Mode != account.ModeOn {
		reject(404, "unknown token or line off")
		return
	}
	if !in.Trust.Allowed(acc, req) {
		reject(403, "not from the line's provider")
		return
	}
	mf := 70
	if h := req.MaxForwards(); h != nil {
		if h.Val() <= 1 {
			Respond(tx, req, 483, "Too Many Hops")
			return
		}
		mf = int(h.Val()) - 1
	}

	cc := acc.CountryCode
	if cc == "" {
		cc = in.DefaultCountryCode
	}
	caller := CallerNumber(req, cc)
	lk := in.LiveKitSide()
	lkHost, lkPortS, _ := net.SplitHostPort(lk.Dest)
	lkPort, _ := strconv.Atoi(lkPortS)

	// The INVITE to LiveKit: called number = the line's own number, caller = who rang.
	bReq := sip.NewRequest(sip.INVITE, sip.Uri{Scheme: "sip", User: acc.Number, Host: lkHost, Port: lkPort, UriParams: sipx.URIParams(lk.Transport)})
	bReq.AppendHeader(&sip.FromHeader{DisplayName: displayName(req), Address: sip.Uri{Scheme: "sip", User: caller, Host: in.InternalHost}, Params: sip.NewParams()})
	bReq.AppendHeader(&sip.ToHeader{Address: sip.Uri{Scheme: "sip", User: acc.Number, Host: lkHost}, Params: sip.NewParams()})
	maxf := sip.MaxForwardsHeader(mf)
	bReq.AppendHeader(&maxf)
	bReq.AppendHeader(sip.NewHeader("X-LL-Line", acc.ID))
	if acc.Tenant != "" {
		bReq.AppendHeader(sip.NewHeader("X-LL-Tenant", acc.Tenant))
	}
	if len(req.Body()) > 0 {
		if ct := contentType(req); ct != nil {
			bReq.AppendHeader(sip.NewHeader("Content-Type", *ct))
		}
	}
	bReq.SetBody(req.Body())

	in.Metrics.CallsIn.Add(1)
	in.Log.Info("incoming call", "line", acc.ID, "from", caller)
	a := acc
	in.Core.Run(in.Ctx, Spec{
		Dir: "in", Line: acc.ID,
		AReq: req, ATx: tx,
		ASide:  in.ProviderSide(acc, req.Transport(), req.Source()),
		ATrust: func(r *sip.Request) bool { return in.Trust.Allowed(a, r) },
		BReq:   bReq, BSide: lk, BAuth: in.LiveKitAuth,
	})
}

var safeUser = regexp.MustCompile(`^[A-Za-z0-9+._-]{1,64}$`)

// CallerNumber is who is calling, from P-Asserted-Identity (the provider's verified identity)
// or else From, as E.164 when possible. Withheld numbers (Privacy: id/user, or "anonymous")
// stay "anonymous".
func CallerNumber(req *sip.Request, countryCode string) string {
	for p := range strings.FieldsFuncSeq(strings.ToLower(sipx.Header(req, "Privacy")), func(r rune) bool { return r == ';' || r == ',' || r == ' ' }) {
		if p == "id" || p == "user" {
			return "anonymous"
		}
	}
	var cands []string
	for _, h := range req.GetHeaders("P-Asserted-Identity") {
		for v := range strings.SplitSeq(h.Value(), ",") {
			cands = append(cands, uriUser(v))
		}
	}
	if f := req.From(); f != nil {
		cands = append(cands, f.Address.User)
	}
	for _, c := range cands {
		if n, ok := account.NormalizeE164(c, countryCode); ok {
			return n
		}
	}
	for _, c := range cands {
		if c != "" && safeUser.MatchString(c) && !strings.EqualFold(c, "anonymous") {
			return c
		}
	}
	return "anonymous"
}

// uriUser pulls the user part out of `"Name" <sip:user@host;x>` or `<tel:+44…>`.
func uriUser(v string) string {
	if i := strings.IndexByte(v, '<'); i >= 0 {
		v = v[i+1:]
		if j := strings.IndexByte(v, '>'); j >= 0 {
			v = v[:j]
		}
	}
	v = strings.TrimSpace(v)
	low := strings.ToLower(v)
	for _, p := range []string{"sip:", "sips:", "tel:"} {
		if strings.HasPrefix(low, p) {
			v = v[len(p):]
			break
		}
	}
	if i := strings.IndexAny(v, "@;?"); i >= 0 {
		v = v[:i]
	}
	return v
}

// displayName is the caller's name, cleaned so it can't break the header.
func displayName(req *sip.Request) string {
	f := req.From()
	if f == nil {
		return ""
	}
	n := strings.Map(func(r rune) rune {
		if r == '"' || r == '\\' || r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, f.DisplayName)
	if r := []rune(n); len(r) > 64 {
		n = string(r[:64])
	}
	return strings.TrimSpace(n)
}
