package bridge

import (
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"sync"

	"github.com/emiago/sipgo/sip"
	"github.com/google/uuid"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/digest"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// Creds answer digest challenges from one side.
type Creds struct {
	Username string
	Password string
	Realm    string // if set, only answer challenges for this realm
}

// Leg is one half of a call: the dialog between the gateway and one side (the provider, or
// LiveKit). The gateway is the UAS on the leg that called it, and the UAC on the leg it called.
type Leg struct {
	Side  *sipx.Side
	Trust func(*sip.Request) bool // may an in-dialog request on this leg come from where it came from
	Auth  *Creds

	callID   string
	localTag string
	local    sip.Uri // our identity on this leg (From if we called, To if we were called)
	locName  string

	mu        sync.Mutex
	remoteTag string
	remote    sip.Uri
	remName   string
	target    sip.Uri   // the other side's Contact: Request-URI of our in-dialog requests
	routes    []sip.Uri // route set
	cseq      uint32
	chal      *digest.Challenge
	chalProxy bool
	nc        uint32
	lastAck   *sip.Request // to re-send if the 2xx is retransmitted
}

// newUASLeg is the leg that called us: its INVITE gives the dialog.
func newUASLeg(inv *sip.Request, side *sipx.Side, trust func(*sip.Request) bool) (*Leg, error) {
	from, to, ct := inv.From(), inv.To(), inv.Contact()
	if from == nil || to == nil || ct == nil || inv.CallID() == nil || inv.CSeq() == nil {
		return nil, errors.New("INVITE without From, To, Contact, Call-ID or CSeq")
	}
	l := &Leg{
		Side: side, Trust: trust,
		callID: inv.CallID().Value(), localTag: sip.GenerateTagN(16),
		local: to.Address, locName: to.DisplayName,
		remote: from.Address, remName: from.DisplayName, remoteTag: sipx.FromTag(inv),
		target: ct.Address, cseq: rand.Uint32N(1 << 20),
	}
	for _, h := range inv.GetHeaders("Record-Route") {
		if rr, ok := h.(*sip.RecordRouteHeader); ok {
			l.routes = append(l.routes, rr.Address)
		}
	}
	return l, nil
}

// newUACLeg is the leg we call; inv gives the From/To/Request-URI (tags, Call-ID and CSeq are
// added here).
func newUACLeg(inv *sip.Request, side *sipx.Side, trust func(*sip.Request) bool, auth *Creds) *Leg {
	l := &Leg{
		Side: side, Trust: trust, Auth: auth,
		callID: uuid.NewString(), localTag: sip.GenerateTagN(16),
		local: inv.From().Address, locName: inv.From().DisplayName,
		remote: inv.To().Address, remName: inv.To().DisplayName,
		target: inv.Recipient, cseq: 1,
	}
	inv.From().Params.Add("tag", l.localTag)
	cid := sip.CallIDHeader(l.callID)
	inv.AppendHeader(&cid)
	inv.AppendHeader(&sip.CSeqHeader{SeqNo: l.cseq, MethodName: sip.INVITE})
	return l
}

func (l *Leg) key() string { return l.callID + "|" + l.localTag }

func (l *Leg) nextCSeq() uint32 {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.cseq++
	return l.cseq
}

// request builds an in-dialog request with CSeq n.
func (l *Leg) request(method sip.RequestMethod, n uint32) *sip.Request {
	l.mu.Lock()
	target, remote, remName, rtag, routes := l.target, l.remote, l.remName, l.remoteTag, l.routes
	l.mu.Unlock()

	req := sip.NewRequest(method, *target.Clone())
	req.AppendHeader(&sip.FromHeader{DisplayName: l.locName, Address: l.local, Params: sipx.Params("tag", l.localTag)})
	to := &sip.ToHeader{DisplayName: remName, Address: remote, Params: sip.NewParams()}
	if rtag != "" {
		to.Params.Add("tag", rtag)
	}
	req.AppendHeader(to)
	cid := sip.CallIDHeader(l.callID)
	req.AppendHeader(&cid)
	req.AppendHeader(&sip.CSeqHeader{SeqNo: n, MethodName: method})
	mf := sip.MaxForwardsHeader(70)
	req.AppendHeader(&mf)
	for _, r := range routes {
		req.AppendHeader(&sip.RouteHeader{Address: r})
	}
	switch method {
	case sip.INVITE, sip.UPDATE, sip.SUBSCRIBE, sip.NOTIFY, sip.REFER:
		req.AppendHeader(l.Side.Contact.Clone())
	}
	return req
}

// send sends an in-dialog request (not ACK) and returns its final answer, answering one
// digest challenge if this side asks and we have credentials.
func (l *Leg) send(ctx context.Context, req *sip.Request) (*sip.Response, error) {
	l.Side.Prepare(req)
	l.authorize(req)
	res, err := sipx.Do(ctx, l.Side.Client, req)
	if err != nil || (res.StatusCode != 401 && res.StatusCode != 407) || l.Auth == nil {
		return res, err
	}
	if err := l.learnChallenge(res); err != nil {
		return res, nil
	}
	again := req.Clone()
	again.RemoveHeader("Authorization")
	again.RemoveHeader("Proxy-Authorization")
	again.CSeq().SeqNo = l.nextCSeq()
	l.Side.Prepare(again)
	l.authorize(again)
	return sipx.Do(ctx, l.Side.Client, again)
}

// learnChallenge stores a 401/407 challenge for later requests.
func (l *Leg) learnChallenge(res *sip.Response) error {
	name := "WWW-Authenticate"
	if res.StatusCode == 407 {
		name = "Proxy-Authenticate"
	}
	ch, err := digest.ParseChallenge(sipx.Header(res, name))
	if err != nil {
		return err
	}
	if l.Auth.Realm != "" && ch.Realm != l.Auth.Realm {
		return fmt.Errorf("challenge for unexpected realm")
	}
	l.mu.Lock()
	l.chal, l.chalProxy, l.nc = ch, res.StatusCode == 407, 0
	l.mu.Unlock()
	return nil
}

// authorize adds credentials for the last challenge seen on this leg, if any.
func (l *Leg) authorize(req *sip.Request) {
	if l.Auth == nil {
		return
	}
	l.mu.Lock()
	ch, proxy := l.chal, l.chalProxy
	if ch == nil {
		l.mu.Unlock()
		return
	}
	l.nc++
	nc := l.nc
	l.mu.Unlock()
	cred, err := digest.Answer(ch, string(req.Method), req.Recipient.String(), l.Auth.Username, l.Auth.Password, nc, "")
	if err != nil {
		return
	}
	name := "Authorization"
	if proxy {
		name = "Proxy-Authorization"
	}
	req.RemoveHeader(name)
	req.AppendHeader(sip.NewHeader(name, cred.String()))
}

// ack sends the ACK for our INVITE with CSeq n that got a 2xx (body: late-offer answer).
func (l *Leg) ack(n uint32, body []byte, contentType string) error {
	req := l.request(sip.ACK, n)
	if len(body) > 0 {
		req.AppendHeader(sip.NewHeader("Content-Type", contentType))
		req.SetBody(body)
	}
	l.Side.Prepare(req)
	l.mu.Lock()
	l.lastAck = req
	l.mu.Unlock()
	return l.Side.Client.WriteRequest(req, sipx.Prebuilt)
}

// reAck re-sends the last ACK (the other side didn't get it and repeated its 2xx).
func (l *Leg) reAck(n uint32) {
	l.mu.Lock()
	a := l.lastAck
	l.mu.Unlock()
	if a != nil && a.CSeq() != nil && a.CSeq().SeqNo == n {
		_ = l.Side.Client.WriteRequest(a, sipx.Prebuilt)
	}
}

// confirmed updates the dialog from a 2xx (or a 1xx that creates an early dialog).
func (l *Leg) confirmed(res *sip.Response, final bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if t := sipx.ToTag(res); t != "" {
		l.remoteTag = t
	}
	if c := res.Contact(); c != nil {
		l.target = c.Address
	}
	if final {
		// UAC route set: Record-Route in reverse order.
		var rs []sip.Uri
		for _, h := range res.GetHeaders("Record-Route") {
			if rr, ok := h.(*sip.RecordRouteHeader); ok {
				rs = append([]sip.Uri{rr.Address}, rs...)
			}
		}
		l.routes = rs
	}
}

func (l *Leg) hasRemoteTag() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.remoteTag != ""
}

func (l *Leg) setTarget(u sip.Uri) {
	l.mu.Lock()
	l.target = u
	l.mu.Unlock()
}
