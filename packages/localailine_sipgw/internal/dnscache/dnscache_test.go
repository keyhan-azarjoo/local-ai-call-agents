package dnscache

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync/atomic"
	"testing"
	"time"
)

type fakeResolver struct {
	hosts map[string][]string
	srv   map[string][]*net.SRV
	calls atomic.Int32
}

func (f *fakeResolver) LookupHost(_ context.Context, h string) ([]string, error) {
	f.calls.Add(1)
	if v, ok := f.hosts[h]; ok {
		return v, nil
	}
	return nil, errors.New("no such host")
}

func (f *fakeResolver) LookupSRV(_ context.Context, service, proto, name string) (string, []*net.SRV, error) {
	if v, ok := f.srv["_"+service+"._"+proto+"."+name]; ok {
		return "", v, nil
	}
	return "", nil, errors.New("no srv")
}

func TestContainsWithSRVAndCache(t *testing.T) {
	f := &fakeResolver{
		hosts: map[string][]string{
			"sip.example.com":   {"192.0.2.1"},
			"edge1.example.net": {"198.51.100.7", "2001:db8::7"},
		},
		srv: map[string][]*net.SRV{"_sips._tcp.sip.example.com": {{Target: "edge1.example.net", Port: 5061}}},
	}
	c := New(f)
	now := time.Unix(0, 0)
	c.now = func() time.Time { return now }
	ctx := context.Background()
	for _, ip := range []string{"192.0.2.1", "198.51.100.7", "2001:db8::7", "::ffff:192.0.2.1"} {
		if !c.Contains(ctx, "sip.example.com", netip.MustParseAddr(ip)) {
			t.Fatalf("%s should belong to the provider", ip)
		}
	}
	if c.Contains(ctx, "sip.example.com", netip.MustParseAddr("203.0.113.9")) {
		t.Fatal("stranger accepted")
	}
	calls := f.calls.Load()
	c.Contains(ctx, "sip.example.com", netip.MustParseAddr("192.0.2.1"))
	if f.calls.Load() != calls {
		t.Fatal("cache not used")
	}
	now = now.Add(10 * time.Minute)
	c.Contains(ctx, "sip.example.com", netip.MustParseAddr("192.0.2.1"))
	if f.calls.Load() == calls {
		t.Fatal("expired entry not refreshed")
	}
	// IP literal domains need no DNS.
	if !c.Contains(ctx, "127.0.0.1", netip.MustParseAddr("127.0.0.1")) || c.Contains(ctx, "127.0.0.1", netip.MustParseAddr("127.0.0.2")) {
		t.Fatal("literal compare wrong")
	}
}
