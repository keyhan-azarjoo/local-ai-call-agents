// Package sipx holds the small SIP helpers the registrar and the call bridge share: building
// Via headers, sending a request "as built" and waiting for its final answer, reading peers'
// addresses, and a log handler that keeps secrets out of sipgo's own logs.
package sipx

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"strconv"
	"strings"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

// Side is one network side of the gateway, as seen by a call leg or a registration: which
// client sends, over what transport, to which address, and how we name ourselves there.
type Side struct {
	Name      string // "provider" or "internal" (for logs and for checking where requests come from)
	Client    *sipgo.Client
	Transport string    // "UDP", "TCP" or "TLS"
	Dest      string    // host:port every request goes to (the flow, the outbound proxy, LiveKit)
	Laddr     *sip.Addr // send from this local socket (our UDP listener), nil = any
	ViaHost   string    // sent-by host in Via ("" = the connection's local address)
	ViaPort   int       // sent-by port (0 = the connection's local port)
	Contact   sip.ContactHeader
}

// Prepare stamps a request built by hand with this side's routing: a fresh Via on top, the
// transport, destination and local socket, and a Content-Length.
func (s *Side) Prepare(req *sip.Request) {
	req.RemoveHeader("Via")
	req.PrependHeader(NewVia(s.Transport, s.ViaHost, s.ViaPort))
	req.SetTransport(s.Transport)
	req.SetDestination(s.Dest)
	if s.Laddr != nil {
		s.Laddr.Copy(&req.Laddr)
	}
	if req.ContentLength() == nil {
		req.SetBody(req.Body())
	}
}

// NewVia makes a Via with a new branch and an empty rport (RFC 3581: "tell me the port you
// saw", which is what keeps answers coming back through NAT).
func NewVia(transport, host string, port int) *sip.ViaHeader {
	v := &sip.ViaHeader{ProtocolName: "SIP", ProtocolVersion: "2.0", Transport: transport, Host: host, Port: port, Params: sip.NewParams()}
	v.Params.Add("branch", sip.GenerateBranchN(16))
	v.Params.Add("rport", "")
	return v
}

// Prebuilt is a client option meaning "send the request exactly as built".
func Prebuilt(*sipgo.Client, *sip.Request) error { return nil }

// Do sends a non-INVITE request (or an INVITE whose provisionals don't matter) and returns
// the final response.
func Do(ctx context.Context, c *sipgo.Client, req *sip.Request) (*sip.Response, error) {
	tx, err := c.TransactionRequest(ctx, req, Prebuilt)
	if err != nil {
		return nil, err
	}
	defer tx.Terminate()
	for {
		select {
		case res := <-tx.Responses():
			if res.IsProvisional() {
				continue
			}
			return res, nil
		case <-tx.Done():
			if err := tx.Err(); err != nil {
				return nil, err
			}
			return nil, errors.New("transaction ended without an answer")
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
}

// Params builds header/URI params from key, value pairs.
func Params(kv ...string) sip.HeaderParams {
	p := sip.NewParams()
	for i := 0; i+1 < len(kv); i += 2 {
		p.Add(kv[i], kv[i+1])
	}
	return p
}

// Header returns the first value of a header, or "".
func Header(m interface{ GetHeader(string) sip.Header }, name string) string {
	if h := m.GetHeader(name); h != nil {
		return h.Value()
	}
	return ""
}

// SourceAddr is where a message came from (the connection's remote address).
func SourceAddr(src string) (netip.AddrPort, bool) {
	ap, err := netip.ParseAddrPort(src)
	if err != nil {
		h, p, err := net.SplitHostPort(src)
		if err != nil {
			return netip.AddrPort{}, false
		}
		ip, err := netip.ParseAddr(h)
		n, err2 := strconv.Atoi(p)
		if err != nil || err2 != nil {
			return netip.AddrPort{}, false
		}
		ap = netip.AddrPortFrom(ip, uint16(n))
	}
	return netip.AddrPortFrom(ap.Addr().Unmap(), ap.Port()), true
}

// ToTag / FromTag read dialog tags.
func ToTag(m interface{ To() *sip.ToHeader }) string {
	if h := m.To(); h != nil {
		v, _ := h.Params.Get("tag")
		return v
	}
	return ""
}

// FromTag reads the From tag.
func FromTag(m interface{ From() *sip.FromHeader }) string {
	if h := m.From(); h != nil {
		v, _ := h.Params.Get("tag")
		return v
	}
	return ""
}

// CallID reads Call-ID.
func CallID(m interface{ CallID() *sip.CallIDHeader }) string {
	if h := m.CallID(); h != nil {
		return h.Value()
	}
	return ""
}

// TransportParam is the ;transport= value to put in a URI for transport ("" for UDP).
func TransportParam(transport string) string {
	switch strings.ToUpper(transport) {
	case "TCP":
		return "tcp"
	case "TLS":
		return "tls"
	}
	return ""
}

// URIParams returns ";transport=…" params for transport, or none for UDP.
func URIParams(transport string) sip.HeaderParams {
	if t := TransportParam(transport); t != "" {
		return Params("transport", t)
	}
	return sip.NewParams()
}

// SafeToken reports whether s can go in a header value as one line.
func SafeToken(s string) bool { return !strings.ContainsAny(s, "\r\n\x00") }
