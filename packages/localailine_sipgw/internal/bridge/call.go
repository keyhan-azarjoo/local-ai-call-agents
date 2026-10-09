// Package bridge relays calls between a SIP provider and LiveKit SIP, as a back-to-back user
// agent: each call is two dialogs (legs) and the gateway passes everything between them —
// ringing, the answer, ACK, hang-ups both ways, CANCEL, re-INVITE/UPDATE (hold, codec change),
// INFO (DTMF) and the like. Only signalling passes through here: the SDP is copied unchanged,
// so the audio flows directly between the provider and LiveKit.
//
// A call never outlives its sides: unanswered calls give up after the ring timeout, answered
// calls are hung up after the maximum call length, when a session timer runs out without a
// refresh, or when an in-call OPTIONS shows one side has gone.
package bridge

import (
	"context"
	"errors"
	"log/slog"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/metrics"
	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// Options for the Core.
type Options struct {
	Log           *slog.Logger
	Metrics       *metrics.Metrics
	RingTimeout   time.Duration
	MaxDuration   time.Duration
	ProbeInterval time.Duration // 0 = no in-call OPTIONS
	UserAgent     string
}

// Core tracks every call's dialogs so in-call requests find their call.
type Core struct {
	o Options

	mu      sync.Mutex
	dialogs map[string]*legRef // Call-ID|our tag -> leg
	calls   map[*Call]struct{}
	wg      sync.WaitGroup
}

type legRef struct {
	call *Call
	leg  *Leg
}

// NewCore makes a Core.
func NewCore(o Options) *Core {
	if o.Log == nil {
		o.Log = slog.Default()
	}
	if o.Metrics == nil {
		o.Metrics = &metrics.Metrics{}
	}
	if o.RingTimeout == 0 {
		o.RingTimeout = 2 * time.Minute
	}
	if o.MaxDuration == 0 {
		o.MaxDuration = 4 * time.Hour
	}
	return &Core{o: o, dialogs: map[string]*legRef{}, calls: map[*Call]struct{}{}}
}

// Active is the number of calls in progress.
func (c *Core) Active() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.calls)
}

// HangupAll ends every call (on shutdown) and waits for them to finish.
func (c *Core) HangupAll() {
	c.mu.Lock()
	calls := make([]*Call, 0, len(c.calls))
	for call := range c.calls {
		calls = append(calls, call)
	}
	c.mu.Unlock()
	for _, call := range calls {
		call.abort("gateway stopping")
	}
	c.wg.Wait()
}

// Spec describes a call to bridge: the INVITE we received (A) and the INVITE to send (B).
type Spec struct {
	Dir  string // "in" or "out", for logs
	Line string // account id

	AReq   *sip.Request
	ATx    sip.ServerTransaction
	ASide  *sipx.Side
	ATrust func(*sip.Request) bool

	// BReq has Request-URI, From (no tag), To, body and any extra headers; Call-ID, CSeq,
	// tags, Via, Contact are added.
	BReq   *sip.Request
	BSide  *sipx.Side
	BTrust func(*sip.Request) bool
	BAuth  *Creds

	OnAnswered func()
}

// Call is one bridged call.
type Call struct {
	core *Core
	log  *slog.Logger
	dir  string
	a, b *Leg
	aReq *sip.Request
	aTx  sip.ServerTransaction

	cancel     chan struct{} // stop before the answer: A's CANCEL, A's early BYE, or shutdown
	cancelCode int           // what A hears then (0 = A already has its answer: CANCEL got 487)
	ended      chan struct{} // closed when the call is over
	cancelOne  sync.Once

	mu          sync.Mutex
	established bool
	over        bool
	why         string
	ackWait     map[ackKey]chan struct{} // 2xx we sent, waiting for the ACK
	ackFwd      map[ackKey]ackFwd        // ACK to pass on (late offer: the ACK carries the answer)
	refreshed   time.Time                // last INVITE/UPDATE (session timer refresh)
	sessExpires time.Duration
	started     time.Time
}

type ackKey struct {
	leg  *Leg
	cseq uint32
}

type ackFwd struct {
	to   *Leg
	cseq uint32
}

// Run bridges the call described by s and returns when it is over.
func (c *Core) Run(ctx context.Context, s Spec) {
	a, err := newUASLeg(s.AReq, s.ASide, s.ATrust)
	if err != nil {
		respond(s.ATx, s.AReq, 400, "Bad Request", nil)
		return
	}
	b := newUACLeg(s.BReq, s.BSide, s.BTrust, s.BAuth)
	call := &Call{
		core: c, dir: s.Dir, a: a, b: b, aReq: s.AReq, aTx: s.ATx,
		log:    c.o.Log.With("call", a.callID[:min(len(a.callID), 12)], "dir", s.Dir, "line", s.Line),
		cancel: make(chan struct{}), ended: make(chan struct{}),
		ackWait: map[ackKey]chan struct{}{}, ackFwd: map[ackKey]ackFwd{}, started: time.Now(),
	}
	c.mu.Lock()
	c.dialogs[a.key()] = &legRef{call, a}
	c.dialogs[b.key()] = &legRef{call, b}
	c.calls[call] = struct{}{}
	c.wg.Add(1)
	c.mu.Unlock()
	c.o.Metrics.ActiveCalls.Add(1)
	defer func() {
		c.mu.Lock()
		delete(c.dialogs, a.key())
		delete(c.dialogs, b.key())
		delete(c.calls, call)
		c.mu.Unlock()
		c.o.Metrics.ActiveCalls.Add(-1)
		c.wg.Done()
	}()

	s.ATx.OnCancel(func(*sip.Request) { call.stopRinging(0) }) // the transaction layer answers 487
	_ = s.ATx.Respond(sip.NewResponseFromRequest(s.AReq, 100, "Trying", nil))

	if !call.dial(ctx, s.BReq) {
		call.finish("not answered")
		return
	}
	if s.OnAnswered != nil {
		s.OnAnswered()
	}
	call.log.Info("call connected")
	call.wait(ctx)
}

// dial sends the INVITE to B and relays its answers to A until the call is answered (true)
// or fails (false; A has had its final answer).
func (call *Call) dial(ctx context.Context, inv *sip.Request) bool {
	a, b := call.a, call.b
	core := call.core
	copySessionHeaders(call.aReq, inv)
	if supportsTimer(call.aReq) {
		inv.AppendHeader(sip.NewHeader("Supported", "timer"))
	}
	inv.AppendHeader(b.Side.Contact.Clone())
	inv.AppendHeader(sip.NewHeader("Allow", allowed))
	if core.o.UserAgent != "" {
		inv.AppendHeader(sip.NewHeader("User-Agent", core.o.UserAgent))
	}
	b.Side.Prepare(inv)

	tx, err := b.Side.Client.TransactionRequest(context.Background(), inv, sipx.Prebuilt)
	if err != nil {
		call.log.Warn("could not send the call on", "error", err)
		respondTagged(call.aTx, call.aReq, a, 503, "Service Unavailable", nil, nil)
		return false
	}
	ring := time.NewTimer(core.o.RingTimeout)
	defer ring.Stop()
	cancelCh, ctxDone := call.cancel, ctx.Done() // set to nil once handled: a closed channel is always ready

	var (
		provisional bool // B said something: CANCEL is allowed now
		giveUp      bool // we want to stop this attempt
		cancelSent  bool
		authTried   bool
		finalForA   int // what A hears if we give up (0 = A already has its answer, e.g. it cancelled)
		deadline    <-chan time.Time
	)
	stop := func(code int) {
		if giveUp {
			return
		}
		giveUp, finalForA = true, code
		deadline = time.After(32 * time.Second) // B must give a final answer to our CANCEL by then
	}
	answerA := func() {
		if finalForA != 0 {
			respondTagged(call.aTx, call.aReq, a, finalForA, sipReason(finalForA), nil, nil)
		}
	}

	for {
		if giveUp && provisional && !cancelSent {
			cancelSent = true
			go sendCancel(b, inv)
		}
		select {
		case res := <-tx.Responses():
			switch {
			case res.StatusCode == 100:
				provisional = true

			case res.IsProvisional():
				provisional = true
				if sipx.ToTag(res) != "" {
					b.confirmed(res, false)
				}
				if !giveUp {
					respondTagged(call.aTx, call.aReq, a, res.StatusCode, res.Reason, res.Body(), contentType(res))
				}

			case res.IsSuccess():
				b.confirmed(res, true)
				tx.OnRetransmission(func(r *sip.Response) { b.reAck(r.CSeq().SeqNo) })
				if giveUp {
					// Answered just as we gave up: take the call and hang it straight up.
					_ = b.ack(inv.CSeq().SeqNo, nil, "")
					go b.bye()
					answerA()
					return false
				}
				return call.answer(res, inv)

			case (res.StatusCode == 401 || res.StatusCode == 407) && b.Auth != nil && !authTried && !giveUp:
				authTried = true
				if err := b.learnChallenge(res); err != nil {
					call.log.Warn("could not sign in to the other side", "error", err)
					respondTagged(call.aTx, call.aReq, a, 503, "Service Unavailable", nil, nil)
					return false
				}
				inv = inv.Clone()
				inv.RemoveHeader("Authorization")
				inv.RemoveHeader("Proxy-Authorization")
				inv.CSeq().SeqNo = b.nextCSeq()
				b.Side.Prepare(inv)
				b.authorize(inv)
				tx, err = b.Side.Client.TransactionRequest(context.Background(), inv, sipx.Prebuilt)
				if err != nil {
					respondTagged(call.aTx, call.aReq, a, 503, "Service Unavailable", nil, nil)
					return false
				}
				provisional = false

			default:
				if giveUp {
					answerA()
					return false
				}
				code := mapFinal(res.StatusCode)
				reason := res.Reason
				if code != res.StatusCode {
					reason = sipReason(code)
				}
				call.log.Info("call refused by the other side", "code", res.StatusCode)
				respondTagged(call.aTx, call.aReq, a, code, reason, nil, nil)
				return false
			}

		case <-tx.Done():
			if !giveUp {
				call.log.Warn("other side did not answer the INVITE", "error", tx.Err())
				finalForA = 408
				if !errors.Is(tx.Err(), sip.ErrTransactionTimeout) {
					finalForA = 503
				}
			}
			answerA()
			return false

		case <-cancelCh:
			cancelCh = nil
			call.mu.Lock()
			code := call.cancelCode
			call.mu.Unlock()
			call.log.Info("call stopped while ringing", "answer_to_caller", code)
			stop(code)

		case <-ring.C:
			call.log.Info("no answer before the ring timeout")
			stop(480)

		case <-ctxDone:
			ctxDone = nil
			stop(503)

		case <-deadline:
			tx.Terminate()
			answerA()
			return false
		}
	}
}

// answer completes the call after B's 2xx: ACK B, answer A.
func (call *Call) answer(res *sip.Response, inv *sip.Request) bool {
	a, b := call.a, call.b
	aCSeq := call.aReq.CSeq().SeqNo
	if len(call.aReq.Body()) > 0 {
		if err := b.ack(inv.CSeq().SeqNo, nil, ""); err != nil {
			call.log.Warn("ack failed", "error", err)
		}
	} else {
		// Late offer: B's 2xx has the offer, A's ACK will carry the answer. Pass it on then.
		call.mu.Lock()
		call.ackFwd[ackKey{a, aCSeq}] = ackFwd{b, inv.CSeq().SeqNo}
		call.mu.Unlock()
	}
	call.noteSessionTimer(res)

	resp := newResponse(call.aReq, a, res.StatusCode, res.Reason, res.Body(), contentType(res))
	copySessionHeaders(res, resp)
	if requiresTimer(res) {
		resp.AppendHeader(sip.NewHeader("Require", "timer"))
	}
	call.mu.Lock()
	call.established = true
	call.refreshed = time.Now()
	call.mu.Unlock()
	if !call.respond2xx(a, aCSeq, call.aTx, resp) {
		call.log.Info("caller left as the call was answered")
		go b.bye()
		return false
	}
	call.core.o.Metrics.CallsAnswered.Add(1)
	return true
}

// respond2xx sends a 2xx on leg l's server transaction and, over UDP, repeats it until the
// ACK arrives (RFC 3261 §13.3.1.4). It returns false if the 2xx couldn't be sent at all.
func (call *Call) respond2xx(l *Leg, cseq uint32, tx sip.ServerTransaction, resp *sip.Response) bool {
	got := make(chan struct{})
	call.mu.Lock()
	call.ackWait[ackKey{l, cseq}] = got
	call.mu.Unlock()
	if err := tx.Respond(resp); err != nil {
		call.mu.Lock()
		delete(call.ackWait, ackKey{l, cseq})
		call.mu.Unlock()
		return false
	}
	go func() {
		defer func() {
			call.mu.Lock()
			delete(call.ackWait, ackKey{l, cseq})
			call.mu.Unlock()
		}()
		interval := sip.T1
		giveUp := time.After(64 * sip.T1)
		for {
			t := time.NewTimer(interval)
			select {
			case <-got:
				t.Stop()
				return
			case <-call.ended:
				t.Stop()
				return
			case <-giveUp:
				t.Stop()
				call.log.Info("no ACK for our answer; hanging up")
				call.hangup(nil, "no ACK")
				return
			case <-t.C:
				if l.Side.Transport == "UDP" {
					_ = tx.Respond(resp)
				}
				interval = min(interval*2, sip.T2)
			}
		}
	}()
	return true
}

// wait keeps an answered call until someone hangs up or a safety limit trips.
func (call *Call) wait(ctx context.Context) {
	o := call.core.o
	maxDur := time.NewTimer(o.MaxDuration)
	defer maxDur.Stop()
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	lastProbe := time.Now()
	ctxDone := ctx.Done()
	for {
		select {
		case <-call.ended:
			call.log.Info("call ended", "why", call.reason(), "seconds", int(time.Since(call.started).Seconds()))
			return
		case <-ctxDone:
			ctxDone = nil
			go call.hangup(nil, "gateway stopping")
		case <-maxDur.C:
			go call.hangup(nil, "maximum call length reached")
		case <-tick.C:
			call.mu.Lock()
			se, last := call.sessExpires, call.refreshed
			call.mu.Unlock()
			if se > 0 && time.Since(last) > se+32*time.Second {
				go call.hangup(nil, "session timer expired without a refresh")
				continue
			}
			if o.ProbeInterval > 0 && time.Since(lastProbe) >= o.ProbeInterval {
				lastProbe = time.Now()
				go call.probe()
			}
		}
	}
}

// probe asks both sides "are you still in this call?" (in-dialog OPTIONS). No answer, or
// "no such call" (481), means that side is gone: hang up the other.
func (call *Call) probe() {
	for _, l := range []*Leg{call.a, call.b} {
		ctx, cancel := context.WithTimeout(context.Background(), 32*time.Second)
		res, err := l.send(ctx, l.request(sip.OPTIONS, l.nextCSeq()))
		cancel()
		select {
		case <-call.ended:
			return
		default:
		}
		if err != nil || res.StatusCode == 481 || res.StatusCode == 408 {
			call.log.Info("a side of the call is gone", "side", l.Side.Name)
			call.hangup(l, l.Side.Name+" side gone")
			return
		}
	}
}

// hangup ends an answered call: BYE to every leg except from (which hung up, or is gone).
func (call *Call) hangup(from *Leg, why string) {
	call.mu.Lock()
	if call.over {
		call.mu.Unlock()
		return
	}
	call.over, call.why = true, why
	est := call.established
	call.mu.Unlock()
	if est {
		var wg sync.WaitGroup
		for _, l := range []*Leg{call.a, call.b} {
			if l != from {
				wg.Add(1)
				go func() { defer wg.Done(); l.bye() }()
			}
		}
		wg.Wait()
	}
	close(call.ended)
}

// abort ends a call in any state: an unanswered one is cancelled, an answered one hung up.
func (call *Call) abort(why string) {
	call.mu.Lock()
	est := call.established
	call.mu.Unlock()
	if est {
		call.hangup(nil, why)
		return
	}
	call.stopRinging(503)
}

// stopRinging gives up on an unanswered call; A hears code (0: it already has its answer).
func (call *Call) stopRinging(code int) {
	call.cancelOne.Do(func() {
		call.mu.Lock()
		call.cancelCode = code
		call.mu.Unlock()
		close(call.cancel)
	})
}

func (call *Call) finish(why string) {
	call.mu.Lock()
	if !call.over {
		call.over, call.why = true, why
		close(call.ended)
	}
	call.mu.Unlock()
}

func (call *Call) reason() string {
	call.mu.Lock()
	defer call.mu.Unlock()
	return call.why
}

func (call *Call) other(l *Leg) *Leg {
	if l == call.a {
		return call.b
	}
	return call.a
}

// bye sends BYE on the leg (best effort, a few seconds).
func (l *Leg) bye() {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	_, _ = l.send(ctx, l.request(sip.BYE, l.nextCSeq()))
}

// noteSessionTimer remembers the session interval from Session-Expires (RFC 4028).
func (call *Call) noteSessionTimer(m interface{ GetHeader(string) sip.Header }) {
	v := sipx.Header(m, "Session-Expires")
	if i := strings.IndexByte(v, ';'); i >= 0 {
		v = v[:i]
	}
	if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n >= 90 {
		call.mu.Lock()
		call.sessExpires = time.Duration(n) * time.Second
		call.mu.Unlock()
	}
}

func (call *Call) touch() {
	call.mu.Lock()
	call.refreshed = time.Now()
	call.mu.Unlock()
}

// sendCancel cancels our pending INVITE on leg b (same Via branch and CSeq number).
func sendCancel(b *Leg, inv *sip.Request) {
	req := sip.NewRequest(sip.CANCEL, inv.Recipient)
	req.AppendHeader(inv.Via().Clone())
	for _, h := range inv.GetHeaders("Route") {
		req.AppendHeader(sip.HeaderClone(h))
	}
	mf := sip.MaxForwardsHeader(70)
	req.AppendHeader(&mf)
	req.AppendHeader(sip.HeaderClone(inv.From()))
	req.AppendHeader(sip.HeaderClone(inv.To()))
	req.AppendHeader(sip.HeaderClone(inv.CallID()))
	req.AppendHeader(&sip.CSeqHeader{SeqNo: inv.CSeq().SeqNo, MethodName: sip.CANCEL})
	req.SetBody(nil)
	req.SetTransport(inv.Transport())
	req.SetDestination(inv.Destination())
	req.Laddr = inv.Laddr
	ctx, cancel := context.WithTimeout(context.Background(), 32*time.Second)
	defer cancel()
	_, _ = sipx.Do(ctx, b.Side.Client, req)
}

// The methods we pass through in a call.
const allowed = "INVITE, ACK, CANCEL, BYE, OPTIONS, INFO, UPDATE, NOTIFY, REFER, MESSAGE"

// mapFinal turns B's refusal into what A should hear. Auth challenges and redirects are
// about the gateway's own leg, so A just hears "unavailable".
func mapFinal(code int) int {
	switch {
	case code >= 300 && code < 400, code == 401, code == 407, code == 421, code == 494:
		return 503
	}
	return code
}

func sipReason(code int) string {
	switch code {
	case 400:
		return "Bad Request"
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 408:
		return "Request Timeout"
	case 480:
		return "Temporarily Unavailable"
	case 481:
		return "Call/Transaction Does Not Exist"
	case 484:
		return "Address Incomplete"
	case 486:
		return "Busy Here"
	case 487:
		return "Request Terminated"
	case 491:
		return "Request Pending"
	case 500:
		return "Server Internal Error"
	case 503:
		return "Service Unavailable"
	}
	return "Error"
}

func contentType(m interface{ GetHeader(string) sip.Header }) *string {
	if v := sipx.Header(m, "Content-Type"); v != "" {
		return &v
	}
	return nil
}

// newResponse answers req (received on leg l) with our tag in To.
func newResponse(req *sip.Request, l *Leg, code int, reason string, body []byte, ctype *string) *sip.Response {
	res := sip.NewResponseFromRequest(req, code, reason, nil)
	if code > 100 && l != nil {
		if to := res.To(); to != nil {
			to.Params.Add("tag", l.localTag)
		}
		if code < 300 && (req.Method == sip.INVITE || req.Method == sip.UPDATE || req.Method == sip.SUBSCRIBE || req.Method == sip.REFER) {
			res.AppendHeader(l.Side.Contact.Clone())
		}
	}
	if len(body) > 0 {
		if ctype != nil {
			res.AppendHeader(sip.NewHeader("Content-Type", *ctype))
		}
		res.SetBody(body)
	}
	return res
}

func respondTagged(tx sip.ServerTransaction, req *sip.Request, l *Leg, code int, reason string, body []byte, ctype *string) {
	_ = tx.Respond(newResponse(req, l, code, reason, body, ctype))
}

func respond(tx sip.ServerTransaction, req *sip.Request, code int, reason string, body []byte) {
	_ = tx.Respond(sip.NewResponseFromRequest(req, code, reason, body))
}

// Respond is respond for other packages (rejecting before a call exists).
func Respond(tx sip.ServerTransaction, req *sip.Request, code int, reason string, hdrs ...sip.Header) {
	res := sip.NewResponseFromRequest(req, code, reason, nil)
	for _, h := range hdrs {
		res.AppendHeader(h)
	}
	_ = tx.Respond(res)
}

// copySessionHeaders copies the RFC 4028 session timer headers (end to end, so both sides
// agree on who refreshes).
func copySessionHeaders(from interface{ GetHeader(string) sip.Header }, to interface{ AppendHeader(sip.Header) }) {
	for _, name := range []string{"Session-Expires", "Min-SE"} {
		if v := sipx.Header(from, name); v != "" && sipx.SafeToken(v) {
			to.AppendHeader(sip.NewHeader(name, v))
		}
	}
}

func hasOption(m interface{ GetHeaders(string) []sip.Header }, header, opt string) bool {
	for _, h := range m.GetHeaders(header) {
		for o := range strings.SplitSeq(h.Value(), ",") {
			if strings.EqualFold(strings.TrimSpace(o), opt) {
				return true
			}
		}
	}
	return false
}

func supportsTimer(r *sip.Request) bool {
	return hasOption(r, "Supported", "timer") || hasOption(r, "k", "timer")
}

func requiresTimer(r *sip.Response) bool { return hasOption(r, "Require", "timer") }
