package outbound

import (
	"net"
	"strconv"
	"strings"
)

func hostOf(hp string) string {
	if h, _, err := net.SplitHostPort(hp); err == nil {
		return h
	}
	return strings.Trim(hp, "[]")
}

func portOf(hp string) int {
	if _, p, err := net.SplitHostPort(hp); err == nil {
		n, _ := strconv.Atoi(p)
		return n
	}
	return 0
}

// uriUser is the user part of a SIP URI string ("sip:+1555@host;x" -> "+1555").
func uriUser(u string) string {
	if i := strings.IndexByte(u, ':'); i >= 0 {
		u = u[i+1:]
	}
	if i := strings.IndexAny(u, "@;?"); i >= 0 {
		u = u[:i]
	}
	return u
}
