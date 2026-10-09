package sipx

import (
	"context"
	"log/slog"
	"strings"
)

// QuietHandler wraps the gateway's log handler for sipgo's own logs: every record is demoted
// to debug (so a flood of junk packets can't flood the log), raw message dumps are dropped,
// and any value that looks like credentials is replaced.
type QuietHandler struct{ H slog.Handler }

// Enabled: sipgo records only show at debug.
func (q QuietHandler) Enabled(ctx context.Context, _ slog.Level) bool {
	return q.H.Enabled(ctx, slog.LevelDebug)
}

// Handle rewrites the record and passes it on.
func (q QuietHandler) Handle(ctx context.Context, r slog.Record) error {
	out := slog.NewRecord(r.Time, slog.LevelDebug, "sipgo: "+r.Message, r.PC)
	r.Attrs(func(a slog.Attr) bool {
		if a = Redact(a); a.Key != "" {
			out.AddAttrs(a)
		}
		return true
	})
	return q.H.Handle(ctx, out)
}

// WithAttrs keeps the wrapping.
func (q QuietHandler) WithAttrs(as []slog.Attr) slog.Handler {
	kept := make([]slog.Attr, 0, len(as))
	for _, a := range as {
		if a = Redact(a); a.Key != "" {
			kept = append(kept, a)
		}
	}
	return QuietHandler{q.H.WithAttrs(kept)}
}

// WithGroup keeps the wrapping.
func (q QuietHandler) WithGroup(name string) slog.Handler { return QuietHandler{q.H.WithGroup(name)} }

// Redact drops raw SIP dumps and hides anything carrying credentials. A dropped attribute
// comes back with an empty key.
func Redact(a slog.Attr) slog.Attr {
	switch strings.ToLower(a.Key) {
	case "data", "msg_raw", "raw":
		return slog.Attr{}
	}
	v := a.Value.String()
	lv := strings.ToLower(v)
	if strings.Contains(lv, "authorization") || strings.Contains(lv, "response=") || strings.Contains(lv, "password") {
		return slog.String(a.Key, "[redacted]")
	}
	return a
}
