package sipx

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"
)

func TestQuietHandlerRedactsAndDemotes(t *testing.T) {
	var buf bytes.Buffer
	base := slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo})
	l := slog.New(QuietHandler{H: base})
	l.Error("failed to parse", "data", "INVITE sip:x SIP/2.0\r\nAuthorization: Digest response=\"abc\"")
	if buf.Len() != 0 {
		t.Fatalf("sipgo error shown at info level: %s", buf.String())
	}

	buf.Reset()
	base = slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug})
	l = slog.New(QuietHandler{H: base}).With("hdr", `Proxy-Authorization: Digest username="u", response="deadbeef"`)
	l.Error("failed to parse", "data", "secret-dump", "msg2", "INVITE sip:x", "other", `Digest response="cafe"`)
	out := buf.String()
	for _, bad := range []string{"secret-dump", "deadbeef", "cafe"} {
		if strings.Contains(out, bad) {
			t.Fatalf("leaked %q: %s", bad, out)
		}
	}
	if !strings.Contains(out, "level=DEBUG") || !strings.Contains(out, "INVITE sip:x") {
		t.Fatalf("expected a demoted record with harmless attrs: %s", out)
	}
}
