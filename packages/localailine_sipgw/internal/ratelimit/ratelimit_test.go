package ratelimit

import (
	"testing"
	"time"
)

func TestBurstThenRefill(t *testing.T) {
	now := time.Unix(1000, 0)
	l := New(2, 3) // 2 per second, burst 3
	l.now = func() time.Time { return now }

	for i := range 3 {
		if !l.Allow("1.2.3.4") {
			t.Fatalf("request %d refused inside the burst", i)
		}
	}
	if l.Allow("1.2.3.4") {
		t.Fatal("4th request allowed, burst is 3")
	}
	if !l.Blocked("1.2.3.4") {
		t.Fatal("expected blocked")
	}
	// Another key is independent.
	if !l.Allow("5.6.7.8") {
		t.Fatal("other key refused")
	}
	// Half a second later one token is back (2/s).
	now = now.Add(500 * time.Millisecond)
	if !l.Allow("1.2.3.4") {
		t.Fatal("token not refilled")
	}
	if l.Allow("1.2.3.4") {
		t.Fatal("only one token should have come back")
	}
	// Long idle: refills to burst, not beyond.
	now = now.Add(time.Hour)
	for range 3 {
		if !l.Allow("1.2.3.4") {
			t.Fatal("refused after idle")
		}
	}
	if l.Allow("1.2.3.4") {
		t.Fatal("bucket grew past burst")
	}
}

func TestZeroRateNeverLimits(t *testing.T) {
	l := New(0, 1)
	for range 100 {
		if !l.Allow("x") {
			t.Fatal("limited with rate 0")
		}
	}
	var nilL *Limiter
	if !nilL.Allow("x") || nilL.Blocked("x") {
		t.Fatal("nil limiter must allow")
	}
}

func TestKeyCapEvicts(t *testing.T) {
	now := time.Unix(0, 0)
	l := New(1, 1)
	l.maxKeys = 10
	l.now = func() time.Time { return now }
	for i := range 50 {
		l.Allow(string(rune('a' + i)))
		now = now.Add(2 * time.Second) // older buckets are full again, so evictable
	}
	if n := l.Len(); n > 10 {
		t.Fatalf("remembers %d keys, cap is 10", n)
	}
}
