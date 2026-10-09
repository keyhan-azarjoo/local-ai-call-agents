package gateway

import (
	"log/slog"
	"os"
	"testing"

	"github.com/emiago/sipgo/sip"
)

// TestMain sets sipgo's process-wide logger before any fake endpoint starts (setting it later
// would race with them). SIPGW_SIP_DEBUG=1 prints every SIP message.
func TestMain(m *testing.M) {
	h := slog.DiscardHandler
	if os.Getenv("SIPGW_TEST_LOG") != "" {
		h = slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug})
	}
	InitSIPLogging(h)
	if os.Getenv("SIPGW_SIP_DEBUG") != "" {
		sip.SIPDebug = true
	}
	os.Exit(m.Run())
}
