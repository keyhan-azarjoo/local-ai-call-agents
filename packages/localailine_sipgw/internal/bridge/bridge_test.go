package bridge

import (
	"context"
	"errors"
	"net"
	"testing"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/dnscache"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/registrar"
)

func invite(from string, hdrs ...sip.Header) *sip.Request {
	req := sip.NewRequest(sip.INVITE, sip.Uri{Scheme: "sip", User: "tok", Host: "gw"})
	var u sip.Uri
	if err := sip.ParseUri(from, &u); err != nil {
		panic(err)
	}
	req.AppendHeader(&sip.FromHeader{DisplayName: "Bob", Address: u, Params: sip.NewParams()})
	for _, h := range hdrs {
		req.AppendHeader(h)
	}
	return req
}

func TestCallerNumber(t *testing.T) {
	cases := []struct {
		req  *sip.Request
		cc   string
		want string
	}{
		{invite("sip:+447700900999@p"), "", "+447700900999"},
		{invite("sip:07700900999@p"), "44", "+447700900999"},
		{invite("sip:anonymous@anonymous.invalid", sip.NewHeader("P-Asserted-Identity", `"Bob" <sip:+15550100123@p;user=phone>`)), "", "+15550100123"},
		{invite("sip:trunk@p", sip.NewHeader("P-Asserted-Identity", "<tel:+15550100123>")), "", "+15550100123"},
		{invite("sip:+447700900999@p", sip.NewHeader("Privacy", "id")), "", "anonymous"},
		{invite("sip:+447700900999@p", sip.NewHeader("Privacy", "none")), "", "+447700900999"},
		{invite("sip:anonymous@p"), "", "anonymous"},
		{invite("sip:1234@p"), "", "1234"}, // an extension: passed as is
	}
	for i, c := range cases {
		if got := CallerNumber(c.req, c.cc); got != c.want {
			t.Errorf("case %d: got %q want %q", i, got, c.want)
		}
	}
}

type fakeResolver map[string][]string

func (f fakeResolver) LookupHost(_ context.Context, h string) ([]string, error) {
	if v, ok := f[h]; ok {
		return v, nil
	}
	return nil, errors.New("nx")
}
func (f fakeResolver) LookupSRV(context.Context, string, string, string) (string, []*net.SRV, error) {
	return "", nil, errors.New("nx")
}

func TestProviderTrust(t *testing.T) {
	tr := &ProviderTrust{
		DNS: dnscache.New(fakeResolver{"sip.example.com": {"192.0.2.1"}, "proxy.example.net": {"192.0.2.9"}}),
		Flows: func(id string) (registrar.Flow, bool) {
			return registrar.Flow{Transport: "TLS", Addr: "203.0.113.50:5061"}, id == "l1"
		},
	}
	acc := account.Account{ID: "l1", Domain: "sip.example.com", AllowedSource: []string{"198.51.100.0/24"}}
	req := func(transport, src string) *sip.Request {
		r := sip.NewRequest(sip.INVITE, sip.Uri{Host: "gw"})
		r.SetTransport(transport)
		r.SetSource(src)
		return r
	}
	allowed := []*sip.Request{
		req("TLS", "203.0.113.50:5061"),   // the registered connection
		req("UDP", "192.0.2.1:5060"),      // the provider's domain
		req("TCP", "198.51.100.77:40000"), // an allowed_sources range
	}
	for _, r := range allowed {
		if !tr.Allowed(acc, r) {
			t.Errorf("%s %s refused", r.Transport(), r.Source())
		}
	}
	refused := []*sip.Request{
		req("UDP", "203.0.113.50:5061"), // right address, wrong transport, and not a provider IP
		req("UDP", "203.0.113.99:5060"),
		req("UDP", "garbage"),
	}
	for _, r := range refused {
		if tr.Allowed(acc, r) {
			t.Errorf("%s %s allowed", r.Transport(), r.Source())
		}
	}
	// The outbound proxy's addresses count too.
	acc.OutboundProxy = "proxy.example.net:5060"
	if !tr.Allowed(acc, req("UDP", "192.0.2.9:5060")) {
		t.Error("outbound proxy address refused")
	}
}

func TestMapFinal(t *testing.T) {
	for in, want := range map[int]int{404: 404, 486: 486, 603: 603, 401: 503, 407: 503, 302: 503, 500: 500} {
		if got := mapFinal(in); got != want {
			t.Errorf("mapFinal(%d)=%d want %d", in, got, want)
		}
	}
}
