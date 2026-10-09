package account

import (
	"encoding/json"
	"regexp"
	"strings"
	"testing"
)

func TestNormalizeE164(t *testing.T) {
	cases := []struct {
		in, cc, want string
		ok           bool
	}{
		{"+44 7700 900123", "", "+447700900123", true},
		{"tel:+447700900123", "", "+447700900123", true},
		{"sip:+447700900123@sip.example.com;user=phone", "", "+447700900123", true},
		{"0044 7700 900123", "", "+447700900123", true},
		{"07700 900123", "44", "+447700900123", true},
		{"(555) 010-0123", "1", "+15550100123", true},
		{"15550100123", "1", "+15550100123", true},
		{"011 44 7700 900123", "1", "+447700900123", true},
		{"447700900123", "", "+447700900123", true}, // already has a country code
		{"07700900123", "", "07700900123", false},   // national, country unknown
		{"anonymous", "", "anonymous", false},
		{"*69", "44", "*69", false},
		{"+0123456789", "", "+0123456789", false},
		{"123", "44", "123", false},
		{"", "", "", false},
	}
	for _, c := range cases {
		got, ok := NormalizeE164(c.in, c.cc)
		if got != c.want || ok != c.ok {
			t.Errorf("NormalizeE164(%q,%q) = %q,%v; want %q,%v", c.in, c.cc, got, ok, c.want, c.ok)
		}
	}
}

func TestTokenShape(t *testing.T) {
	seen := map[string]bool{}
	re := regexp.MustCompile(`^[a-z2-7]{32}$`) // 160 bits of base32
	for range 1000 {
		tok := NewToken()
		if !re.MatchString(tok) {
			t.Fatalf("token %q is not 32 lower-case base32 characters", tok)
		}
		if seen[tok] {
			t.Fatal("duplicate token")
		}
		seen[tok] = true
	}
}

func TestRegistryTokenMatching(t *testing.T) {
	r := NewRegistry()
	a := r.Put(Account{ID: "line1", Number: "+447700900123", Password: "pw"})
	if a.Token == "" {
		t.Fatal("no token assigned")
	}
	if got, ok := r.ByToken(a.Token); !ok || got.ID != "line1" {
		t.Fatal("token lookup failed")
	}
	for _, bad := range []string{"", strings.ToUpper(a.Token), a.Token[:31], a.Token + "a", strings.Repeat("a", 200)} {
		if _, ok := r.ByToken(bad); ok {
			t.Fatalf("token %q matched", bad)
		}
	}
	// Update keeps the token and (if not given) the password.
	b := r.Put(Account{ID: "line1", Number: "+447700900999"})
	if b.Token != a.Token || b.Password != "pw" {
		t.Fatalf("update lost token or password: %+v", b)
	}
	if got, _ := r.ByToken(a.Token); got.Number != "+447700900999" {
		t.Fatal("token points at stale copy")
	}
	if _, ok := r.ByNumber("+447700900999"); !ok {
		t.Fatal("number lookup failed")
	}
	r.Delete("line1")
	if _, ok := r.ByToken(a.Token); ok {
		t.Fatal("deleted line still matches")
	}
}

func TestNormalizeAccount(t *testing.T) {
	a := Account{ID: "l1", Number: "07700 900123", CountryCode: "44", Domain: "SIP.Example.com", Username: "alice", Password: "x"}
	if err := a.Normalize(); err != nil {
		t.Fatal(err)
	}
	if a.Number != "+447700900123" || a.Transport != "tls" || a.Port != 5061 || a.Mode != "on" || a.Expires != 600 || a.Domain != "sip.example.com" {
		t.Fatalf("defaults wrong: %+v", a)
	}
	bad := []Account{
		{ID: "has space", Number: "+447700900123", Domain: "x.com", Username: "u", Password: "p"},
		{ID: "a", Number: "12", Domain: "x.com", Username: "u", Password: "p"},
		{ID: "a", Number: "+447700900123", Domain: "bad domain", Username: "u", Password: "p"},
		{ID: "a", Number: "+447700900123", Domain: "x.com", Username: "u", Password: "p", Transport: "ws"},
		{ID: "a", Number: "+447700900123", Domain: "x.com", Username: "u", Password: ""},
		{ID: "a", Number: "+447700900123", Domain: "x.com", Username: "u", Password: "p", Mode: "maybe"},
		{ID: "a", Number: "+447700900123", Domain: "x.com", Username: "u", Password: "p", AllowedSource: []string{"nope"}},
		{ID: "a", Number: "+447700900123", Domain: "x.com", Username: "u", Password: "p", Tenant: "a\r\nX-Evil: 1"},
	}
	for i, b := range bad {
		if err := b.Normalize(); err == nil {
			t.Errorf("case %d accepted: %+v", i, b)
		}
	}
}

func TestViewHasNoSecrets(t *testing.T) {
	a := Account{ID: "l1", Number: "+447700900123", Password: "hunter2", Token: "tok-secret"}
	js, _ := json.Marshal(a.View(Status{State: StateOff}))
	if strings.Contains(string(js), "hunter2") || strings.Contains(string(js), "tok-secret") {
		t.Fatalf("view leaks a secret: %s", js)
	}
	js, _ = json.Marshal(a)
	if strings.Contains(string(js), "tok-secret") {
		t.Fatalf("token serialised: %s", js)
	}
}
