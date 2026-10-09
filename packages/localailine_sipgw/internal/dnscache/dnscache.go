// Package dnscache answers "is this IP one of the provider's?" by resolving the provider's
// domain (A/AAAA, and the SIP SRV records' targets) and remembering the answer for a while.
package dnscache

import (
	"context"
	"net"
	"net/netip"
	"sync"
	"time"
)

// Resolver is the part of *net.Resolver we use (swappable in tests).
type Resolver interface {
	LookupHost(ctx context.Context, host string) ([]string, error)
	LookupSRV(ctx context.Context, service, proto, name string) (string, []*net.SRV, error)
}

// Cache remembers each domain's addresses for TTL (failures for a shorter time).
type Cache struct {
	r      Resolver
	ttl    time.Duration
	negTTL time.Duration
	now    func() time.Time

	mu sync.Mutex
	m  map[string]*entry
}

type entry struct {
	ips     map[netip.Addr]bool
	expires time.Time
	ready   chan struct{} // closed once the lookup finished (one lookup per domain at a time)
}

// New makes a cache; r nil means the system resolver.
func New(r Resolver) *Cache {
	if r == nil {
		r = net.DefaultResolver
	}
	return &Cache{r: r, ttl: 5 * time.Minute, negTTL: 30 * time.Second, now: time.Now, m: map[string]*entry{}}
}

// Contains reports whether ip is one of domain's addresses. An IP-literal domain is compared
// directly.
func (c *Cache) Contains(ctx context.Context, domain string, ip netip.Addr) bool {
	ip = ip.Unmap()
	if lit, err := netip.ParseAddr(domain); err == nil {
		return lit.Unmap() == ip
	}
	return c.IPs(ctx, domain)[ip]
}

// IPs returns domain's addresses (cached).
func (c *Cache) IPs(ctx context.Context, domain string) map[netip.Addr]bool {
	c.mu.Lock()
	e, ok := c.m[domain]
	if ok {
		select {
		case <-e.ready:
			if c.now().Before(e.expires) {
				c.mu.Unlock()
				return e.ips
			}
		default:
			c.mu.Unlock()
			select { // someone else is looking it up: wait for them
			case <-e.ready:
				return e.ips
			case <-ctx.Done():
				return nil
			}
		}
	}
	e = &entry{ready: make(chan struct{})}
	c.m[domain] = e
	c.mu.Unlock()

	ips := c.resolve(ctx, domain)
	c.mu.Lock()
	e.ips = ips
	if len(ips) > 0 {
		e.expires = c.now().Add(c.ttl)
	} else {
		e.expires = c.now().Add(c.negTTL)
	}
	close(e.ready)
	c.mu.Unlock()
	return ips
}

func (c *Cache) resolve(ctx context.Context, domain string) map[netip.Addr]bool {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	hosts := []string{domain}
	for _, s := range []struct{ service, proto string }{{"sip", "udp"}, {"sip", "tcp"}, {"sips", "tcp"}} {
		if _, srvs, err := c.r.LookupSRV(ctx, s.service, s.proto, domain); err == nil {
			for _, srv := range srvs {
				hosts = append(hosts, srv.Target)
			}
		}
	}
	ips := map[netip.Addr]bool{}
	seen := map[string]bool{}
	for _, h := range hosts {
		if seen[h] || len(seen) > 32 {
			continue
		}
		seen[h] = true
		addrs, err := c.r.LookupHost(ctx, h)
		if err != nil {
			continue
		}
		for _, a := range addrs {
			if ip, err := netip.ParseAddr(a); err == nil {
				ips[ip.Unmap()] = true
			}
		}
	}
	return ips
}
