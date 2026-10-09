package bridge

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/emiago/sipgo/sip"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/sipx"
)

// InDialog handles a request that belongs to a call (it has a To tag): ACK, BYE, re-INVITE,
// UPDATE, INFO, OPTIONS, NOTIFY, REFER, MESSAGE. side is the listener it arrived on
// ("provider" or "internal"): a request is only accepted for a leg on that same side.
func (c *Core) InDialog(side string, req *sip.Request, tx sip.ServerTransaction) {
	c.mu.Lock()
	ref := c.dialogs[sipx.CallID(req)+"|"+sipx.ToTag(req)]
	c.mu.Unlock()
	if ref == nil || ref.leg.Side.Name != side {
		if !req.IsAck() {
			respond(tx, req, 481, "Call/Transaction Does Not Exist", nil)
		}
		return
	}
	call, from := ref.call, ref.leg
	if from.Trust != nil && !from.Trust(req) {
		call.log.Debug("in-call request from an unexpected address refused", "method", req.Method)
		if !req.IsAck() {
			respond(tx, req, 403, "Forbidden", nil)
		}
		return
	}
	switch req.Method {
	case sip.ACK:
		call.onAck(from, req)
	case sip.BYE:
		respond(tx, req, 200, "OK", nil)
		call.mu.Lock()
		est := call.established
		call.mu.Unlock()
		if !est {
			call.stopRinging(487) // hung up before the answer: end the pending INVITE too
			return
		}
		call.log.Info("hang-up", "from", from.Side.Name)
		call.hangup(from, from.Side.Name+" hung up")
	case sip.CANCEL:
		respond(tx, req, 481, "Call/Transaction Does Not Exist", nil)
	default:
		call.forward(from, req, tx)
	}
}

// StrayResponse handles a response no transaction wanted: a repeated 2xx to an INVITE whose
// transaction is gone means our ACK was lost, so send it again.
func (c *Core) StrayResponse(res *sip.Response) {
	if !res.IsSuccess() || res.CSeq() == nil || res.CSeq().MethodName != sip.INVITE {
		return
	}
	c.mu.Lock()
	ref := c.dialogs[sipx.CallID(res)+"|"+sipx.FromTag(res)]
	c.mu.Unlock()
	if ref != nil {
		ref.leg.reAck(res.CSeq().SeqNo)
	}
}

// onAck: an ACK for a 2xx we sent. Stop repeating that 2xx, and pass the ACK on if the
// other side is waiting for it (late offer: it carries the SDP answer).
func (call *Call) onAck(from *Leg, ack *sip.Request) {
	if ack.CSeq() == nil {
		return
	}
	k := ackKey{from, ack.CSeq().SeqNo}
	call.mu.Lock()
	got := call.ackWait[k]
	delete(call.ackWait, k)
	fwd, ok := call.ackFwd[k]
	delete(call.ackFwd, k)
	call.mu.Unlock()
	if got != nil {
		close(got)
	}
	if ok {
		ct := ""
		if v := contentType(ack); v != nil {
			ct = *v
		}
		_ = fwd.to.ack(fwd.cseq, ack.Body(), ct)
	}
}

// Headers passed on with in-call requests and their answers (besides the body).
var passHeaders = []string{"Content-Disposition", "Info-Package", "Recv-Info", "Event", "Subscription-State", "Refer-To", "Referred-By", "Reason", "Allow-Events"}

// forward passes an in-call request to the other leg and its answer back.
func (call *Call) forward(from *Leg, req *sip.Request, tx sip.ServerTransaction) {
	call.mu.Lock()
	est := call.established
	call.mu.Unlock()
	to := call.other(from)
	if req.Method == sip.INVITE && !est {
		respond(tx, req, 491, "Request Pending", nil)
		return
	}
	if !to.hasRemoteTag() {
		respond(tx, req, 481, "Call/Transaction Does Not Exist", nil)
		return
	}

	out := to.request(req.Method, to.nextCSeq())
	if len(req.Body()) > 0 {
		if ct := contentType(req); ct != nil {
			out.AppendHeader(sip.NewHeader("Content-Type", *ct))
		}
		out.SetBody(req.Body())
	}
	for _, name := range passHeaders {
		for _, h := range req.GetHeaders(name) {
			if sipx.SafeToken(h.Value()) {
				out.AppendHeader(sip.NewHeader(name, h.Value()))
			}
		}
	}
	if req.Method == sip.INVITE || req.Method == sip.UPDATE {
		copySessionHeaders(req, out)
		if supportsTimer(req) {
			out.AppendHeader(sip.NewHeader("Supported", "timer"))
		}
		call.touch() // a session refresh, whatever the answer
		call.noteSessionTimer(req)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	res, err := to.send(ctx, out)
	if err != nil {
		code := 503
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, sip.ErrTransactionTimeout) {
			code = 408
		}
		respond(tx, req, code, sipReason(code), nil)
		return
	}

	code, reason := res.StatusCode, res.Reason
	if code == 401 || code == 407 {
		code, reason = 500, "Server Internal Error"
	}
	resp := newResponse(req, nil, code, reason, res.Body(), contentType(res))
	if code >= 200 && code < 300 && (req.Method == sip.INVITE || req.Method == sip.UPDATE) {
		resp.AppendHeader(from.Side.Contact.Clone())
		copySessionHeaders(res, resp)
		if requiresTimer(res) {
			resp.AppendHeader(sip.NewHeader("Require", "timer"))
		}
		call.noteSessionTimer(res)
	}
	for _, name := range passHeaders {
		for _, h := range res.GetHeaders(name) {
			if sipx.SafeToken(h.Value()) {
				resp.AppendHeader(sip.NewHeader(name, h.Value()))
			}
		}
	}
	if v := sipx.Header(res, "Retry-After"); v != "" && sipx.SafeToken(v) {
		resp.AppendHeader(sip.NewHeader("Retry-After", v))
	}

	if req.Method == sip.INVITE && res.IsSuccess() {
		if c := res.Contact(); c != nil {
			to.setTarget(c.Address)
		}
		if len(out.Body()) > 0 {
			_ = to.ack(out.CSeq().SeqNo, nil, "")
		} else {
			call.mu.Lock()
			call.ackFwd[ackKey{from, req.CSeq().SeqNo}] = ackFwd{to, out.CSeq().SeqNo}
			call.mu.Unlock()
		}
		call.respond2xx(from, req.CSeq().SeqNo, tx, resp)
	} else {
		_ = tx.Respond(resp)
	}

	// The other side has no such call any more: end ours too.
	if code == 481 {
		call.log.Info("the other side no longer knows this call", "side", to.Side.Name)
		call.hangup(to, to.Side.Name+" side lost the call")
	}
}

// IsInDialog reports whether req carries a To tag (belongs to an existing dialog).
func IsInDialog(req *sip.Request) bool { return strings.TrimSpace(sipx.ToTag(req)) != "" }
