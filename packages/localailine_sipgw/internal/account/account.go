// Package account is one phone line: the person's number and how to sign in to their SIP
// provider. It also makes the secret per-line token the provider rings, and keeps all lines
// in a Registry that can be searched by id or by token.
package account

import (
	"crypto/rand"
	"encoding/base32"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/netip"
	"regexp"
	"strings"
	"time"
)

// Account is one line. Password and Token are secrets: they go to the encrypted store, never
// to logs or the control API's answers.
type Account struct {
	ID            string   `json:"id" yaml:"id"`
	Number        string   `json:"number" yaml:"number"`                             // the line's own number, E.164 (+447700900123)
	Domain        string   `json:"domain" yaml:"domain"`                             // registrar domain, e.g. sip.example.com
	Port          int      `json:"port,omitempty" yaml:"port"`                       // 0 = 5061 for tls, else 5060
	Transport     string   `json:"transport,omitempty" yaml:"transport"`             // tls | tcp | udp (default tls)
	Username      string   `json:"username" yaml:"username"`                         // the SIP user (To/From of REGISTER)
	AuthUsername  string   `json:"auth_username,omitempty" yaml:"auth_username"`     // digest user, if different
	Password      string   `json:"password,omitempty" yaml:"password"`               // digest password
	OutboundProxy string   `json:"outbound_proxy,omitempty" yaml:"outbound_proxy"`   // host[:port] to send everything through
	Realm         string   `json:"realm,omitempty" yaml:"realm"`                     // only answer challenges for this realm
	Expires       int      `json:"expires,omitempty" yaml:"expires"`                 // seconds asked for in REGISTER (default 600)
	Mode          string   `json:"mode,omitempty" yaml:"mode"`                       // on | off
	Tenant        string   `json:"tenant,omitempty" yaml:"tenant"`                   // sent to LiveKit as X-LL-Tenant
	CountryCode   string   `json:"country_code,omitempty" yaml:"country_code"`       // e.g. "44": turns 07700… into +447700…
	AllowedSource []string `json:"allowed_sources,omitempty" yaml:"allowed_sources"` // extra CIDRs the provider may call from
	Token         string   `json:"-" yaml:"-"`                                       // Contact user part; set by the gateway
}

// Mode values.
const (
	ModeOn  = "on"
	ModeOff = "off"
)

var (
	idRe     = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
	numberRe = regexp.MustCompile(`^\+[1-9][0-9]{6,14}$`)
	userRe   = regexp.MustCompile(`^[A-Za-z0-9!$&'()*+,;=?/._~%-]{1,128}$`) // SIP "user" characters, unescaped
	hostRe   = regexp.MustCompile(`^[A-Za-z0-9.-]{1,253}$`)
)

// Normalize fills defaults and checks every field; the error says what is wrong in plain words.
func (a *Account) Normalize() error {
	a.ID = strings.TrimSpace(a.ID)
	if !idRe.MatchString(a.ID) {
		return errors.New("id must be 1-64 letters, digits, dot, dash or underscore")
	}
	if n, ok := NormalizeE164(a.Number, a.CountryCode); ok {
		a.Number = n
	}
	if !numberRe.MatchString(a.Number) {
		return errors.New("number must be in international format, e.g. +447700900123")
	}
	a.Domain = strings.ToLower(strings.TrimSpace(a.Domain))
	if !validHost(a.Domain) {
		return errors.New("domain must be a host name or IP address, e.g. sip.example.com")
	}
	a.Transport = strings.ToLower(strings.TrimSpace(a.Transport))
	switch a.Transport {
	case "":
		a.Transport = "tls"
	case "tls", "tcp", "udp":
	default:
		return errors.New("transport must be tls, tcp or udp")
	}
	if a.Port == 0 {
		a.Port = 5060
		if a.Transport == "tls" {
			a.Port = 5061
		}
	}
	if a.Port < 1 || a.Port > 65535 {
		return errors.New("port must be between 1 and 65535")
	}
	if !userRe.MatchString(a.Username) {
		return errors.New("username is required (letters, digits and the usual SIP characters)")
	}
	if a.AuthUsername != "" && !userRe.MatchString(a.AuthUsername) {
		return errors.New("auth_username has characters that are not allowed")
	}
	if a.Password == "" {
		return errors.New("password is required")
	}
	if len(a.Password) > 256 {
		return errors.New("password is too long")
	}
	if a.OutboundProxy != "" {
		h, p := splitHostPortDefault(a.OutboundProxy, 0)
		if !validHost(h) || p < 0 || p > 65535 {
			return errors.New("outbound_proxy must be host or host:port")
		}
	}
	if a.Expires == 0 {
		a.Expires = 600
	}
	if a.Expires < 60 || a.Expires > 86400 {
		return errors.New("expires must be between 60 and 86400 seconds")
	}
	a.Mode = strings.ToLower(strings.TrimSpace(a.Mode))
	switch a.Mode {
	case "":
		a.Mode = ModeOn
	case ModeOn, ModeOff:
	default:
		return errors.New("mode must be on or off")
	}
	if len(a.Tenant) > 128 || strings.ContainsAny(a.Tenant, "\r\n") {
		return errors.New("tenant must be one line of at most 128 characters")
	}
	if a.CountryCode != "" && !regexp.MustCompile(`^[1-9][0-9]{0,2}$`).MatchString(a.CountryCode) {
		return errors.New("country_code must be digits only, e.g. 44")
	}
	for _, c := range a.AllowedSource {
		if _, err := ParseSource(c); err != nil {
			return fmt.Errorf("allowed_sources: %q is not an IP address or CIDR", c)
		}
	}
	if len(a.Realm) > 256 || strings.ContainsAny(a.Realm, "\r\n\"") {
		return errors.New("realm has characters that are not allowed")
	}
	return nil
}

// AuthUser is the digest username (auth_username, else username).
func (a *Account) AuthUser() string {
	if a.AuthUsername != "" {
		return a.AuthUsername
	}
	return a.Username
}

// RegistrarAddr is where REGISTER (and everything else) is sent: the outbound proxy if set,
// else domain:port.
func (a *Account) RegistrarAddr() string {
	if a.OutboundProxy != "" {
		h, p := splitHostPortDefault(a.OutboundProxy, a.Port)
		return net.JoinHostPort(h, fmt.Sprint(p))
	}
	return net.JoinHostPort(a.Domain, fmt.Sprint(a.Port))
}

// SIPTransport is the transport in sipgo's spelling (UDP/TCP/TLS).
func (a *Account) SIPTransport() string { return strings.ToUpper(a.Transport) }

// LogValue keeps secrets out of logs whatever a caller passes to slog.
func (a Account) LogValue() slog.Value {
	return slog.GroupValue(slog.String("id", a.ID), slog.String("number", a.Number), slog.String("domain", a.Domain), slog.String("transport", a.Transport))
}

// View is what the control API shows: no password, no token.
type View struct {
	ID             string   `json:"id"`
	Number         string   `json:"number"`
	Domain         string   `json:"domain"`
	Port           int      `json:"port"`
	Transport      string   `json:"transport"`
	Username       string   `json:"username"`
	AuthUsername   string   `json:"auth_username,omitempty"`
	HasPassword    bool     `json:"has_password"`
	OutboundProxy  string   `json:"outbound_proxy,omitempty"`
	Realm          string   `json:"realm,omitempty"`
	Expires        int      `json:"expires"`
	Mode           string   `json:"mode"`
	Tenant         string   `json:"tenant,omitempty"`
	CountryCode    string   `json:"country_code,omitempty"`
	AllowedSources []string `json:"allowed_sources,omitempty"`
	Status         Status   `json:"status"`
}

// View returns the safe view of a with status st.
func (a *Account) View(st Status) View {
	return View{
		ID: a.ID, Number: a.Number, Domain: a.Domain, Port: a.Port, Transport: a.Transport,
		Username: a.Username, AuthUsername: a.AuthUsername, HasPassword: a.Password != "",
		OutboundProxy: a.OutboundProxy, Realm: a.Realm, Expires: a.Expires, Mode: a.Mode,
		Tenant: a.Tenant, CountryCode: a.CountryCode, AllowedSources: a.AllowedSource, Status: st,
	}
}

// Status is how a line's sign-in is going.
type Status struct {
	State          string    `json:"state"` // registering | registered | failed | off
	LastError      string    `json:"last_error,omitempty"`
	LastRegistered time.Time `json:"last_registered,omitzero"`
	ExpiresAt      time.Time `json:"expires_at,omitzero"`
	Contact        string    `json:"contact,omitempty"`
}

// States.
const (
	StateRegistering = "registering"
	StateRegistered  = "registered"
	StateFailed      = "failed"
	StateOff         = "off"
)

// NewToken returns 160 random bits as lower-case base32 (32 characters): unguessable, and
// safe as a SIP URI user part.
func NewToken() string {
	b := make([]byte, 20)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return strings.ToLower(base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b))
}

// ParseSource reads an IP or CIDR into a prefix.
func ParseSource(s string) (netip.Prefix, error) {
	s = strings.TrimSpace(s)
	if strings.Contains(s, "/") {
		p, err := netip.ParsePrefix(s)
		return p.Masked(), err
	}
	ip, err := netip.ParseAddr(s)
	if err != nil {
		return netip.Prefix{}, err
	}
	return netip.PrefixFrom(ip.Unmap(), ip.Unmap().BitLen()), nil
}

func validHost(h string) bool {
	if h == "" {
		return false
	}
	if _, err := netip.ParseAddr(strings.Trim(h, "[]")); err == nil {
		return true
	}
	return hostRe.MatchString(h) && !strings.HasPrefix(h, "-") && !strings.Contains(h, "..")
}

func splitHostPortDefault(hp string, def int) (string, int) {
	if h, p, err := net.SplitHostPort(hp); err == nil {
		var n int
		if _, err := fmt.Sscanf(p, "%d", &n); err != nil {
			return h, -1
		}
		return h, n
	}
	return strings.Trim(hp, "[]"), def
}
