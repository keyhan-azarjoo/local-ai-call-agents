package digest

import (
	"strings"
	"testing"
	"time"

	icholy "github.com/icholy/digest"
)

// RFC 2617 §3.5 example (MD5, qop=auth).
func TestResponseMD5RFC2617(t *testing.T) {
	got, err := Response("MD5", "Mufasa", "testrealm@host.com", "Circle Of Life", "GET", "/dir/index.html",
		"dcd98b7102dd2f0e8b11d0f600bfb0c093", 1, "0a4f113b", "auth")
	if err != nil {
		t.Fatal(err)
	}
	if got != "6629fae49393a05397450978507c4ef1" {
		t.Fatalf("md5 response = %s", got)
	}
}

// RFC 7616 §3.9.1 example (SHA-256 and MD5, qop=auth).
func TestResponseRFC7616(t *testing.T) {
	const nonce = "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
	const cnonce = "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
	sha, err := Response("SHA-256", "Mufasa", "http-auth@example.org", "Circle of Life", "GET", "/dir/index.html", nonce, 1, cnonce, "auth")
	if err != nil {
		t.Fatal(err)
	}
	if sha != "753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1" {
		t.Fatalf("sha-256 response = %s", sha)
	}
	md, _ := Response("MD5", "Mufasa", "http-auth@example.org", "Circle of Life", "GET", "/dir/index.html", nonce, 1, cnonce, "auth")
	if md != "8ca523f5e9506fed4657c9700eebdbec" {
		t.Fatalf("md5 response = %s", md)
	}
}

// Our answers must match an independent implementation, for every algorithm and with/without qop.
func TestAnswerMatchesIndependentImplementation(t *testing.T) {
	for _, alg := range []string{"MD5", "SHA-256", ""} {
		for _, qop := range []string{`, qop="auth"`, ""} {
			hdr := `Digest realm="sip.example.com", nonce="abc123", opaque="xyz", algorithm=` + alg + qop
			if alg == "" {
				hdr = `Digest realm="sip.example.com", nonce="abc123", opaque="xyz"` + qop
			}
			ch, err := ParseChallenge(hdr)
			if err != nil {
				t.Fatal(err)
			}
			cred, err := Answer(ch, "REGISTER", "sip:sip.example.com", "alice", "s3cret", 1, "c0ffee")
			if err != nil {
				t.Fatal(err)
			}
			ich, _ := icholy.ParseChallenge(hdr)
			want, err := icholy.Digest(ich, icholy.Options{Method: "REGISTER", URI: "sip:sip.example.com", Username: "alice", Password: "s3cret", Cnonce: "c0ffee", Count: 1})
			if err != nil {
				t.Fatal(err)
			}
			if cred.Response != want.Response {
				t.Fatalf("alg %q qop %q: got %s want %s", alg, qop, cred.Response, want.Response)
			}
			// Round trip through the header form.
			back, err := ParseCredentials(cred.String())
			if err != nil || back.Response != cred.Response || back.Opaque != "xyz" || back.Username != "alice" {
				t.Fatalf("round trip failed: %+v %v", back, err)
			}
		}
	}
}

func TestOnlyAuthIntIsUnsupported(t *testing.T) {
	ch, _ := ParseChallenge(`Digest realm="r", nonce="n", qop="auth-int"`)
	if _, err := Answer(ch, "INVITE", "sip:x", "u", "p", 1, ""); err == nil {
		t.Fatal("expected unsupported")
	}
	if _, err := ParseChallenge(`Basic realm="r"`); err == nil {
		t.Fatal("expected error for Basic")
	}
}

func TestServerVerify(t *testing.T) {
	for _, alg := range []string{"MD5", "SHA-256"} {
		s := NewServer("gw", alg)
		ch, err := ParseChallenge(s.Challenge(false))
		if err != nil {
			t.Fatal(err)
		}
		good, _ := Answer(ch, "INVITE", "sip:+15550001@gw", "livekit", "pw", 1, "")
		if ok, _ := s.Verify(good.String(), "INVITE", "livekit", "pw"); !ok {
			t.Fatalf("%s: good answer refused", alg)
		}
		bad, _ := Answer(ch, "INVITE", "sip:+15550001@gw", "livekit", "wrong", 1, "")
		if ok, _ := s.Verify(bad.String(), "INVITE", "livekit", "pw"); ok {
			t.Fatalf("%s: wrong password accepted", alg)
		}
		if ok, _ := s.Verify(good.String(), "BYE", "livekit", "pw"); ok {
			t.Fatalf("%s: answer for another method accepted", alg)
		}
		// A nonce we did not make.
		forged := strings.Replace(good.String(), ch.Nonce, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 1)
		if ok, _ := s.Verify(forged, "INVITE", "livekit", "pw"); ok {
			t.Fatalf("%s: forged nonce accepted", alg)
		}
		// Expired nonce: right password, but stale.
		s.now = func() time.Time { return time.Now().Add(time.Hour) }
		if ok, stale := s.Verify(good.String(), "INVITE", "livekit", "pw"); ok || !stale {
			t.Fatalf("%s: expected stale, got ok=%v stale=%v", alg, ok, stale)
		}
	}
}

func TestParseQuotedEscapes(t *testing.T) {
	ch, err := ParseChallenge(`Digest realm="a \"quoted\", realm", nonce="n1",stale=TRUE,algorithm=SHA-256`)
	if err != nil {
		t.Fatal(err)
	}
	if ch.Realm != `a "quoted", realm` || !ch.Stale || ch.Algorithm != "SHA-256" {
		t.Fatalf("bad parse: %+v", ch)
	}
}
