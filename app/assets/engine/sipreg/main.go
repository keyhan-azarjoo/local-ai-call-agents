// ll-sipreg: lets Twilio deliver calls to this computer without opening router ports.
//
// It signs in (SIP REGISTER) to your private Twilio SIP address over TLS — a connection this
// computer opens itself — and keeps it open. Twilio rings that sign-in when your number gets
// a call; the call is handed to LiveKit SIP on this computer (127.0.0.1), where Ava answers.
// Media goes directly between Twilio and LiveKit SIP, as for outgoing calls.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	"github.com/icholy/digest"
)

var log = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	domain := env("LL_REG_DOMAIN", "")        // e.g. localailine-ab12cd.sip.twilio.com
	user := env("LL_REG_USER", "localailine") // the sign-in name
	pass := env("LL_REG_PASS", "")
	number := env("LL_NUMBER", "")                      // your phone number (+44…): what LiveKit answers for
	local := env("LL_LOCAL_SIP", "127.0.0.1:5080")      // LiveKit SIP
	listen := env("LL_BRIDGE_LISTEN", "127.0.0.1:5090") // where LiveKit SIP talks back to us
	if domain == "" || pass == "" || number == "" {
		fmt.Fprintln(os.Stderr, "LL_REG_DOMAIN, LL_REG_PASS and LL_NUMBER are required")
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	ua, err := sipgo.NewUA(sipgo.WithUserAgent("LocalAILine"), sipgo.WithUserAgenTLSConfig(&tls.Config{ServerName: domain}))
	if err != nil {
		panic(err)
	}
	srv, _ := sipgo.NewServer(ua)
	cli, _ := sipgo.NewClient(ua)

	lhost, lportS, _ := splitHostPort(listen)
	lport, _ := strconv.Atoi(lportS)
	twilioContact := sip.ContactHeader{Address: sip.Uri{User: user, Host: domain, Port: 5061, UriParams: params("transport", "tls")}}
	localContact := sip.ContactHeader{Address: sip.Uri{User: "bridge", Host: lhost, Port: lport, UriParams: params("transport", "tcp")}}
	fromTwilio := sipgo.NewDialogServerCache(cli, twilioContact)
	toLocal := sipgo.NewDialogClientCache(cli, localContact)

	srv.OnInvite(func(req *sip.Request, tx sip.ServerTransaction) {
		in, err := fromTwilio.ReadInvite(req, tx)
		if err != nil {
			log.Warn("bad invite", "err", err)
			return
		}
		defer in.Close()
		caller := req.From().Address.User
		log.Info("incoming call", "from", caller)
		_ = in.Respond(100, "Trying", nil)

		callCtx, cancel := context.WithCancel(ctx)
		defer cancel()
		tx.OnCancel(func(*sip.Request) { cancel() }) // they hung up while it rang

		lp, _ := strconv.Atoi(portOf(local))
		target := sip.Uri{User: number, Host: hostOf(local), Port: lp, UriParams: params("transport", "tcp")}
		from := &sip.FromHeader{Address: sip.Uri{User: caller, Host: lhost}, Params: params("tag", sip.GenerateTagN(16))}
		out, err := toLocal.Invite(callCtx, target, req.Body(), sip.NewHeader("Content-Type", "application/sdp"), from)
		if err != nil {
			log.Warn("local invite failed", "err", err)
			_ = in.Respond(503, "Service Unavailable", nil)
			return
		}
		defer out.Close()
		err = out.WaitAnswer(callCtx, sipgo.AnswerOptions{OnResponse: func(res *sip.Response) error {
			if res.StatusCode == 180 || res.StatusCode == 183 {
				var hs []sip.Header
				if len(res.Body()) > 0 {
					hs = append(hs, sip.NewHeader("Content-Type", "application/sdp"))
				}
				_ = in.Respond(res.StatusCode, res.Reason, res.Body(), hs...)
			}
			return nil
		}})
		if err != nil {
			log.Info("not answered", "err", err)
			_ = in.Respond(486, "Busy Here", nil)
			return
		}
		// LiveKit SIP answers with its public address; we talk to it on this computer.
		if c := out.InviteResponse.Contact(); c != nil {
			c.Address.Host = hostOf(local)
			c.Address.Port = lp
			c.Address.UriParams = params("transport", "tcp")
		}
		if err := out.Ack(callCtx); err != nil {
			log.Warn("ack failed", "err", err)
		}
		if err := in.Respond(200, "OK", out.InviteResponse.Body(), sip.NewHeader("Content-Type", "application/sdp")); err != nil {
			log.Warn("answer to twilio failed", "err", err)
			_ = out.Bye(context.Background())
			return
		}
		log.Info("call connected", "from", caller)
		// Whoever hangs up first, the other side hears it.
		select {
		case <-in.Context().Done():
			bctx, c := context.WithTimeout(context.Background(), 5*time.Second)
			_ = out.Bye(bctx)
			c()
		case <-out.Context().Done():
			bctx, c := context.WithTimeout(context.Background(), 5*time.Second)
			_ = in.Bye(bctx)
			c()
		case <-ctx.Done():
		}
		log.Info("call ended", "from", caller)
	})
	srv.OnAck(func(req *sip.Request, tx sip.ServerTransaction) { _ = fromTwilio.ReadAck(req, tx) })
	srv.OnBye(func(req *sip.Request, tx sip.ServerTransaction) {
		if err := fromTwilio.ReadBye(req, tx); err == sipgo.ErrDialogDoesNotExists {
			_ = toLocal.ReadBye(req, tx)
		}
	})
	srv.OnOptions(func(req *sip.Request, tx sip.ServerTransaction) {
		_ = tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
	})

	go func() {
		if err := srv.ListenAndServe(ctx, "tcp", listen); err != nil && ctx.Err() == nil {
			log.Error("listen failed", "err", err)
			os.Exit(1)
		}
	}()

	// Stay signed in (and keep the connection busy, so routers don't close it).
	var once sync.Once
	for ctx.Err() == nil {
		if err := register(ctx, cli, domain, user, pass); err != nil {
			log.Warn("sign-in failed", "err", err)
			select {
			case <-time.After(15 * time.Second):
			case <-ctx.Done():
			}
			continue
		}
		once.Do(func() { log.Info("registered", "address", fmt.Sprintf("sip:%s@%s", user, domain)) })
		select {
		case <-time.After(120 * time.Second):
		case <-ctx.Done():
		}
	}
}

func register(ctx context.Context, cli *sipgo.Client, domain, user, pass string) error {
	recipient := sip.Uri{User: user, Host: domain, Port: 5061, UriParams: params("transport", "tls")}
	req := sip.NewRequest(sip.REGISTER, sip.Uri{Host: domain, Port: 5061, UriParams: params("transport", "tls")})
	req.AppendHeader(&sip.ToHeader{Address: recipient})
	req.AppendHeader(&sip.FromHeader{Address: recipient, Params: params("tag", sip.GenerateTagN(16))})
	req.AppendHeader(sip.NewHeader("Contact", fmt.Sprintf("<sip:%s@%s;transport=tls>;expires=3600", user, domain)))
	req.AppendHeader(sip.NewHeader("Expires", "3600"))
	req.SetTransport("TLS")
	req.SetDestination(fmt.Sprintf("%s:5061", domain))
	rctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	res, err := cli.Do(rctx, req)
	if err != nil {
		return err
	}
	if res.StatusCode == 401 || res.StatusCode == 407 {
		h := "WWW-Authenticate"
		if res.StatusCode == 407 {
			h = "Proxy-Authenticate"
		}
		chal, err := digest.ParseChallenge(res.GetHeader(h).Value())
		if err != nil {
			return err
		}
		cred, err := digest.Digest(chal, digest.Options{Method: "REGISTER", URI: req.Recipient.String(), Username: user, Password: pass})
		if err != nil {
			return err
		}
		auth := req.Clone()
		auth.RemoveHeader("Via")
		hn := "Authorization"
		if res.StatusCode == 407 {
			hn = "Proxy-Authorization"
		}
		auth.AppendHeader(sip.NewHeader(hn, cred.String()))
		res, err = cli.Do(rctx, auth, sipgo.ClientRequestIncreaseCSEQ, sipgo.ClientRequestAddVia)
		if err != nil {
			return err
		}
	}
	if res.StatusCode != 200 {
		return fmt.Errorf("twilio said %d %s", res.StatusCode, res.Reason)
	}
	return nil
}

func splitHostPort(hp string) (string, string, error) {
	for i := len(hp) - 1; i >= 0; i-- {
		if hp[i] == ':' {
			return hp[:i], hp[i+1:], nil
		}
	}
	return hp, "", fmt.Errorf("no port")
}
func params(k, v string) sip.HeaderParams {
	p := sip.NewParams()
	p.Add(k, v)
	return p
}

func hostOf(hp string) string { h, _, _ := splitHostPort(hp); return h }
func portOf(hp string) string { _, p, _ := splitHostPort(hp); return p }
