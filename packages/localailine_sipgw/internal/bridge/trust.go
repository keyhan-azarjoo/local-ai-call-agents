package bridge

import (
	"context"
	"net"
	"strings"
	"time"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/dnscache"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/registrar"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// ProviderTrust decides whether a request really comes from a line's provider: over the very
// connection the line registered on, or from an address the provider's domain (or outbound
// proxy) resolves to, or from one of the line's extra allowed_sources.
type ProviderTrust struct {
	DNS   *dnscache.Cache
	Flows func(id string) (registrar.Flow, bool)
}

// Allowed reports whether req may act for line a.
func (t *ProviderTrust) Allowed(a account.Account, req *sip.Request) bool {
	if t.Flows != nil {
		if f, ok := t.Flows(a.ID); ok && strings.EqualFold(f.Transport, req.Transport()) && f.Addr == req.Source() {
			return true
		}
	}
	ap, ok := sipx.SourceAddr(req.Source())
	if !ok {
		return false
	}
	ip := ap.Addr()
	for _, s := range a.AllowedSource {
		if p, err := account.ParseSource(s); err == nil && p.Contains(ip) {
			return true
		}
	}
	if t.DNS == nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if t.DNS.Contains(ctx, a.Domain, ip) {
		return true
	}
	if a.OutboundProxy != "" {
		h := a.OutboundProxy
		if hh, _, err := net.SplitHostPort(h); err == nil {
			h = hh
		}
		return t.DNS.Contains(ctx, strings.Trim(h, "[]"), ip)
	}
	return false
}

// Warm resolves a line's provider ahead of the first call.
func (t *ProviderTrust) Warm(a account.Account) {
	if t.DNS == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		t.DNS.IPs(ctx, a.Domain)
	}()
}
