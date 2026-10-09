// Package digest is SIP digest authentication (RFC 3261 §22, RFC 2617, RFC 7616/8760):
// answering a provider's 401/407 challenge, and challenging LiveKit's requests ourselves.
//
// Supported: MD5, MD5-sess, SHA-256 and SHA-256-sess, with qop "auth" or no qop.
// Nothing here ever logs; callers must not log Credentials.String() either (it holds the response).
package digest

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"strings"
	"time"
)

// Challenge is a parsed WWW-Authenticate / Proxy-Authenticate value.
type Challenge struct {
	Realm     string
	Nonce     string
	Opaque    string
	Algorithm string // as sent; "" means MD5
	QOP       []string
	Stale     bool
}

// Credentials is a parsed (or built) Authorization / Proxy-Authorization value.
type Credentials struct {
	Username  string
	Realm     string
	Nonce     string
	URI       string
	Response  string
	Algorithm string
	Cnonce    string
	Opaque    string
	QOP       string
	NC        uint32
}

// ErrUnsupported means the challenge asks for something we don't do (e.g. only qop=auth-int).
var ErrUnsupported = errors.New("digest: unsupported algorithm or qop")

// ParseChallenge reads `Digest realm="…", nonce="…", …`.
func ParseChallenge(v string) (*Challenge, error) {
	p, err := parseDigest(v)
	if err != nil {
		return nil, err
	}
	c := &Challenge{Realm: p["realm"], Nonce: p["nonce"], Opaque: p["opaque"], Algorithm: p["algorithm"]}
	if c.Nonce == "" {
		return nil, errors.New("digest: challenge without nonce")
	}
	for q := range strings.SplitSeq(p["qop"], ",") {
		if q = strings.TrimSpace(q); q != "" {
			c.QOP = append(c.QOP, q)
		}
	}
	c.Stale = strings.EqualFold(p["stale"], "true")
	return c, nil
}

// ParseCredentials reads `Digest username="…", response="…", …`.
func ParseCredentials(v string) (*Credentials, error) {
	p, err := parseDigest(v)
	if err != nil {
		return nil, err
	}
	c := &Credentials{
		Username: p["username"], Realm: p["realm"], Nonce: p["nonce"], URI: p["uri"],
		Response: p["response"], Algorithm: p["algorithm"], Cnonce: p["cnonce"],
		Opaque: p["opaque"], QOP: p["qop"],
	}
	if nc := p["nc"]; nc != "" {
		var n uint32
		if _, err := fmt.Sscanf(nc, "%x", &n); err != nil {
			return nil, errors.New("digest: bad nc")
		}
		c.NC = n
	}
	if c.Username == "" || c.Nonce == "" || c.Response == "" {
		return nil, errors.New("digest: incomplete credentials")
	}
	return c, nil
}

// String renders the header value. It contains the response: never log it.
func (c *Credentials) String() string {
	var b strings.Builder
	b.WriteString("Digest ")
	fmt.Fprintf(&b, `username="%s", realm="%s", nonce="%s", uri="%s", response="%s"`,
		quote(c.Username), quote(c.Realm), quote(c.Nonce), quote(c.URI), c.Response)
	if c.Algorithm != "" {
		fmt.Fprintf(&b, ", algorithm=%s", c.Algorithm)
	}
	if c.Opaque != "" {
		fmt.Fprintf(&b, `, opaque="%s"`, quote(c.Opaque))
	}
	if c.QOP != "" {
		fmt.Fprintf(&b, `, qop=%s, nc=%08x, cnonce="%s"`, c.QOP, c.NC, quote(c.Cnonce))
	}
	return b.String()
}

// Answer builds the credentials for a challenge. nc counts uses of the same nonce (start at 1).
// cnonce may be empty (a random one is made).
func Answer(ch *Challenge, method, uri, username, password string, nc uint32, cnonce string) (*Credentials, error) {
	qop := ""
	if len(ch.QOP) > 0 {
		for _, q := range ch.QOP {
			if strings.EqualFold(q, "auth") {
				qop = "auth"
			}
		}
		if qop == "" {
			return nil, ErrUnsupported // only auth-int (or unknown) offered
		}
		if cnonce == "" {
			cnonce = randomHex(16)
		}
		if nc == 0 {
			nc = 1
		}
	}
	resp, err := Response(ch.Algorithm, username, ch.Realm, password, method, uri, ch.Nonce, nc, cnonce, qop)
	if err != nil {
		return nil, err
	}
	c := &Credentials{
		Username: username, Realm: ch.Realm, Nonce: ch.Nonce, URI: uri, Response: resp,
		Algorithm: ch.Algorithm, Opaque: ch.Opaque, QOP: qop,
	}
	if qop != "" {
		c.NC, c.Cnonce = nc, cnonce
	}
	return c, nil
}

// Response computes the digest response value (lower-case hex).
func Response(algorithm, username, realm, password, method, uri, nonce string, nc uint32, cnonce, qop string) (string, error) {
	newHash, sess, err := algo(algorithm)
	if err != nil {
		return "", err
	}
	h := func(s string) string {
		x := newHash()
		x.Write([]byte(s))
		return hex.EncodeToString(x.Sum(nil))
	}
	ha1 := h(username + ":" + realm + ":" + password)
	if sess {
		ha1 = h(ha1 + ":" + nonce + ":" + cnonce)
	}
	ha2 := h(method + ":" + uri)
	if qop == "" {
		return h(ha1 + ":" + nonce + ":" + ha2), nil
	}
	return h(fmt.Sprintf("%s:%s:%08x:%s:%s:%s", ha1, nonce, nc, cnonce, qop, ha2)), nil
}

func algo(a string) (func() hash.Hash, bool, error) {
	switch strings.ToUpper(a) {
	case "", "MD5":
		return md5.New, false, nil
	case "MD5-SESS":
		return md5.New, true, nil
	case "SHA-256":
		return sha256.New, false, nil
	case "SHA-256-SESS":
		return sha256.New, true, nil
	}
	return nil, false, ErrUnsupported
}

// Server issues challenges and checks answers, for one realm and one username/password.
// Nonces are stateless: a timestamp signed with a per-process secret, so any old nonce
// is refused as "stale" after NonceTTL.
type Server struct {
	Realm     string
	Algorithm string // "MD5" (default) or "SHA-256"
	NonceTTL  time.Duration
	key       []byte
	now       func() time.Time
}

// NewServer makes a challenger with a fresh random nonce key.
func NewServer(realm, algorithm string) *Server {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		panic(err)
	}
	if algorithm == "" {
		algorithm = "MD5"
	}
	return &Server{Realm: realm, Algorithm: algorithm, NonceTTL: 5 * time.Minute, key: key, now: time.Now}
}

// Challenge returns a header value for WWW-Authenticate / Proxy-Authenticate.
func (s *Server) Challenge(stale bool) string {
	v := fmt.Sprintf(`Digest realm="%s", nonce="%s", algorithm=%s, qop="auth"`, quote(s.Realm), s.nonce(s.now()), s.Algorithm)
	if stale {
		v += ", stale=true"
	}
	return v
}

// Verify checks an Authorization value for method against username/password, in constant
// time for the secret parts. stale reports a correct answer to an expired nonce (re-challenge
// with stale=true).
func (s *Server) Verify(authValue, method, username, password string) (ok, stale bool) {
	c, err := ParseCredentials(authValue)
	if err != nil {
		return false, false
	}
	if c.Realm != s.Realm {
		return false, false
	}
	if c.Algorithm != "" && !strings.EqualFold(c.Algorithm, s.Algorithm) {
		return false, false
	}
	fresh, valid := s.checkNonce(c.Nonce)
	if !valid {
		return false, false
	}
	if c.QOP != "" && c.QOP != "auth" {
		return false, false
	}
	want, err := Response(s.Algorithm, username, s.Realm, password, method, c.URI, c.Nonce, c.NC, c.Cnonce, c.QOP)
	if err != nil {
		return false, false
	}
	userOK := subtle.ConstantTimeCompare([]byte(c.Username), []byte(username)) == 1
	respOK := subtle.ConstantTimeCompare([]byte(strings.ToLower(c.Response)), []byte(want)) == 1
	if !userOK || !respOK {
		return false, false
	}
	if !fresh {
		return false, true
	}
	return true, false
}

func (s *Server) nonce(t time.Time) string {
	var ts [8]byte
	binary.BigEndian.PutUint64(ts[:], uint64(t.Unix()))
	m := hmac.New(sha256.New, s.key)
	m.Write(ts[:])
	return base64.RawURLEncoding.EncodeToString(append(ts[:], m.Sum(nil)[:16]...))
}

// checkNonce: valid = we made it; fresh = not older than NonceTTL.
func (s *Server) checkNonce(n string) (fresh, valid bool) {
	raw, err := base64.RawURLEncoding.DecodeString(n)
	if err != nil || len(raw) != 24 {
		return false, false
	}
	m := hmac.New(sha256.New, s.key)
	m.Write(raw[:8])
	if !hmac.Equal(m.Sum(nil)[:16], raw[8:]) {
		return false, false
	}
	age := s.now().Sub(time.Unix(int64(binary.BigEndian.Uint64(raw[:8])), 0))
	return age >= -time.Minute && age <= s.NonceTTL, true
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

func quote(s string) string { return strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s) }

// parseDigest splits `Digest k=v, k="v", …` into a lower-case-keyed map.
func parseDigest(v string) (map[string]string, error) {
	v = strings.TrimSpace(v)
	if len(v) < 7 || !strings.EqualFold(v[:7], "digest ") {
		return nil, errors.New("digest: not a Digest header")
	}
	s := v[7:]
	out := map[string]string{}
	for {
		s = strings.TrimLeft(s, " \t,")
		if s == "" {
			return out, nil
		}
		eq := strings.IndexByte(s, '=')
		if eq <= 0 {
			return nil, errors.New("digest: malformed parameter")
		}
		key := strings.ToLower(strings.TrimSpace(s[:eq]))
		s = strings.TrimLeft(s[eq+1:], " \t")
		var val string
		if strings.HasPrefix(s, `"`) {
			var b strings.Builder
			i, closed := 1, false
			for ; i < len(s); i++ {
				if s[i] == '\\' && i+1 < len(s) {
					i++
					b.WriteByte(s[i])
					continue
				}
				if s[i] == '"' {
					closed = true
					break
				}
				b.WriteByte(s[i])
			}
			if !closed {
				return nil, errors.New("digest: unterminated quote")
			}
			val, s = b.String(), s[i+1:]
		} else {
			end := strings.IndexByte(s, ',')
			if end < 0 {
				end = len(s)
			}
			val, s = strings.TrimSpace(s[:end]), s[end:]
		}
		if len(out) > 32 {
			return nil, errors.New("digest: too many parameters")
		}
		out[key] = val
	}
}
