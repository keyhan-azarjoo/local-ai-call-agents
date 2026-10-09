// Package metrics counts what the gateway does and writes it in Prometheus text format.
package metrics

import (
	"fmt"
	"io"
	"sync/atomic"
)

// Metrics are plain atomic counters; the zero value is ready to use.
type Metrics struct {
	RegistrationsOK     atomic.Int64
	RegistrationsFailed atomic.Int64
	CallsIn             atomic.Int64 // inbound calls accepted and sent to LiveKit
	CallsOut            atomic.Int64 // outbound calls accepted and sent to a provider
	CallsRejected       atomic.Int64 // INVITEs refused (unknown token, wrong source, rate limit, auth)
	CallsAnswered       atomic.Int64
	ActiveCalls         atomic.Int64
	ControlAuthFailed   atomic.Int64
}

// Gauges the gateway knows at scrape time.
type Gauges struct {
	Accounts           int
	AccountsRegistered int
}

// Write prints every metric.
func (m *Metrics) Write(w io.Writer, g Gauges) {
	line := func(name, typ, help string, v int64) {
		fmt.Fprintf(w, "# HELP %s %s\n# TYPE %s %s\n%s %d\n", name, help, name, typ, name, v)
	}
	line("sipgw_registrations_ok_total", "counter", "Successful REGISTER exchanges.", m.RegistrationsOK.Load())
	line("sipgw_registrations_failed_total", "counter", "Failed REGISTER attempts.", m.RegistrationsFailed.Load())
	line("sipgw_calls_in_total", "counter", "Inbound calls relayed to LiveKit.", m.CallsIn.Load())
	line("sipgw_calls_out_total", "counter", "Outbound calls relayed to a provider.", m.CallsOut.Load())
	line("sipgw_calls_rejected_total", "counter", "INVITEs refused before relaying.", m.CallsRejected.Load())
	line("sipgw_calls_answered_total", "counter", "Relayed calls that were answered.", m.CallsAnswered.Load())
	line("sipgw_active_calls", "gauge", "Calls in progress (ringing or answered).", m.ActiveCalls.Load())
	line("sipgw_control_auth_failed_total", "counter", "Control API requests with a wrong token.", m.ControlAuthFailed.Load())
	line("sipgw_accounts", "gauge", "Lines configured.", int64(g.Accounts))
	line("sipgw_accounts_registered", "gauge", "Lines currently registered.", int64(g.AccountsRegistered))
}
