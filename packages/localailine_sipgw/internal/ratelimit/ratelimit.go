// Package ratelimit is a token bucket per key (usually a source IP), with a cap on how many
// keys it remembers so a flood of new addresses can't grow memory without bound.
package ratelimit

import (
	"sync"
	"time"
)

// Limiter allows Rate events per second per key, with bursts up to Burst.
type Limiter struct {
	rate    float64
	burst   float64
	maxKeys int

	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
}

type bucket struct {
	tokens float64
	last   time.Time
}

// New makes a limiter. A rate <= 0 means "never limit".
func New(ratePerSecond float64, burst int) *Limiter {
	if burst < 1 {
		burst = 1
	}
	return &Limiter{rate: ratePerSecond, burst: float64(burst), maxKeys: 100_000, buckets: map[string]*bucket{}, now: time.Now}
}

// Allow takes one token for key; false means "too many, refuse this one".
func (l *Limiter) Allow(key string) bool {
	if l == nil || l.rate <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.refill(key)
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// Blocked reports whether key has no token left, without taking one. Used for failed logins:
// each failure calls Allow, and a request is refused while Blocked.
func (l *Limiter) Blocked(key string) bool {
	if l == nil || l.rate <= 0 {
		return false
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.refill(key).tokens < 1
}

// refill returns key's bucket, topped up for the time since it was last used. Caller holds mu.
func (l *Limiter) refill(key string) *bucket {
	now := l.now()
	b, ok := l.buckets[key]
	if !ok {
		if len(l.buckets) >= l.maxKeys {
			l.evict(now)
		}
		b = &bucket{tokens: l.burst, last: now}
		l.buckets[key] = b
		return b
	}
	b.tokens += now.Sub(b.last).Seconds() * l.rate
	if b.tokens > l.burst {
		b.tokens = l.burst
	}
	b.last = now
	return b
}

// evict drops keys whose bucket would be full again (they hold no information). If that frees
// nothing (a real flood), it drops everything: better to forget than to run out of memory.
func (l *Limiter) evict(now time.Time) {
	full := time.Duration(l.burst / l.rate * float64(time.Second))
	for k, b := range l.buckets {
		if now.Sub(b.last) >= full {
			delete(l.buckets, k)
		}
	}
	if len(l.buckets) >= l.maxKeys {
		clear(l.buckets)
	}
}

// Len is the number of keys remembered (for tests and metrics).
func (l *Limiter) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.buckets)
}
