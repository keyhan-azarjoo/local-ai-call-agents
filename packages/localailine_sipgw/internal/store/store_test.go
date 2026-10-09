package store

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
)

func key(t *testing.T) []byte {
	k := make([]byte, 32)
	if _, err := rand.Read(k); err != nil {
		t.Fatal(err)
	}
	return k
}

func TestRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "accounts.enc")
	k := key(t)
	s, err := New(path, k)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := s.Load(); err != nil || len(got) != 0 {
		t.Fatalf("missing file should load empty, got %v %v", got, err)
	}
	in := []account.Account{
		{ID: "a", Number: "+447700900123", Domain: "sip.example.com", Username: "alice", Password: "hunter2", Token: "tok1", Mode: "on"},
		{ID: "b", Number: "+15550100123", Domain: "sip.example.org", Username: "bob", Password: "pa$$", Token: "tok2", Mode: "off", AllowedSource: []string{"10.0.0.0/8"}},
	}
	if err := s.Save(in); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(path)
	for _, secret := range []string{"hunter2", "alice", "tok1", "+447700900123"} {
		if bytes.Contains(raw, []byte(secret)) {
			t.Fatalf("file contains %q in clear", secret)
		}
	}
	if fi, _ := os.Stat(path); fi.Mode().Perm() != 0o600 {
		t.Fatalf("file mode %v, want 0600", fi.Mode().Perm())
	}
	out, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(out) != 2 || out[0].Password != "hunter2" || out[0].Token != "tok1" || out[1].AllowedSource[0] != "10.0.0.0/8" || out[1].Mode != "off" {
		t.Fatalf("round trip lost data: %+v", out)
	}

	// Another key can't read it.
	other, _ := New(path, key(t))
	if _, err := other.Load(); err != ErrWrongKey {
		t.Fatalf("wrong key: got %v", err)
	}
	// Any change to the file is detected.
	raw[len(raw)-1] ^= 1
	os.WriteFile(path, raw, 0o600)
	if _, err := s.Load(); err != ErrWrongKey {
		t.Fatalf("tampered file: got %v", err)
	}
}

func TestParseKey(t *testing.T) {
	k := key(t)
	for _, s := range []string{hex.EncodeToString(k), base64.StdEncoding.EncodeToString(k), base64.RawURLEncoding.EncodeToString(k)} {
		got, err := ParseKey(s)
		if err != nil || !bytes.Equal(got, k) {
			t.Fatalf("ParseKey(%q) failed: %v", s, err)
		}
	}
	if _, err := ParseKey("short"); err == nil {
		t.Fatal("short key accepted")
	}
	if _, err := New("x", []byte("too short")); err == nil {
		t.Fatal("short key accepted by New")
	}
}
