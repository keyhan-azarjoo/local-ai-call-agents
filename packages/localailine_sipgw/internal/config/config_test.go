package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func env(m map[string]string) func(string) (string, bool) {
	return func(k string) (string, bool) { v, ok := m[k]; return v, ok }
}

const token = "0123456789abcdef0123" // gitleaks:allow (a fake token for tests)

func TestDefaultsAndEnv(t *testing.T) {
	c, err := Load("", env(map[string]string{
		"LL_SIPGW_CONTROL_TOKEN":          token,
		"LL_SIPGW_PUBLIC_HOST":            "gw.example.com",
		"LL_SIPGW_SIP_UDP":                "", // set but empty: UDP off
		"LL_SIPGW_RING_TIMEOUT":           "45",
		"LL_SIPGW_KEEPALIVE_INTERVAL":     "15s",
		"LL_SIPGW_INBOUND_RATE":           "0.5",
		"LL_SIPGW_LIVEKIT_TRANSPORT":      "UDP",
		"LL_SIPGW_UNREGISTER_ON_SHUTDOWN": "false",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.PublicHost != "gw.example.com" || c.SIPUDP != "" || c.SIPTCP != ":5060" || c.RingTimeout.Duration != 45*time.Second ||
		c.KeepaliveInterval.Duration != 15*time.Second || c.InboundRate != 0.5 || c.LiveKitTransport != "udp" || *c.UnregisterOnShutdown {
		t.Fatalf("unexpected: %+v", c)
	}
	h, p := c.InternalAdvertised()
	if h != "127.0.0.1" || p != 5090 {
		t.Fatalf("internal advertised %s:%d", h, p)
	}
}

func TestFileThenEnv(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sipgw.yaml")
	os.WriteFile(path, []byte(`
public_host: file.example.com
internal_listen: 0.0.0.0:5090
internal_host: sipgw.internal
livekit_addr: livekit:5060
livekit_user: lk
livekit_pass: lkpass
outbound_user: out
outbound_pass: outbound-secret-1
control_token: `+token+`
max_call_duration: 2h
call_probe_interval: 0
`), 0o600)
	c, err := Load(path, env(map[string]string{"LL_SIPGW_PUBLIC_HOST": "env.example.com"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.PublicHost != "env.example.com" {
		t.Fatal("env should override the file")
	}
	if c.LiveKitAddr != "livekit:5060" || c.MaxCallDuration.Duration != 2*time.Hour || c.CallProbeInterval.Duration != 0 || c.OutboundUser != "out" {
		t.Fatalf("file not applied: %+v", c)
	}
	if h, _ := c.InternalAdvertised(); h != "sipgw.internal" {
		t.Fatalf("internal host %s", h)
	}

	// JSON is YAML too.
	jpath := filepath.Join(dir, "sipgw.json")
	os.WriteFile(jpath, []byte(`{"control_token":"`+token+`","log_level":"debug"}`), 0o600)
	if c, err := Load(jpath, env(nil)); err != nil || c.LogLevel != "debug" {
		t.Fatalf("json: %v %+v", err, c)
	}
}

func TestErrors(t *testing.T) {
	dir := t.TempDir()
	typo := filepath.Join(dir, "typo.yaml")
	os.WriteFile(typo, []byte("control_tokn: x\n"), 0o600)
	if _, err := Load(typo, env(nil)); err == nil {
		t.Fatal("unknown key accepted")
	}
	cases := map[string]map[string]string{
		"no token":         {},
		"short token":      {"LL_SIPGW_CONTROL_TOKEN": "short"},
		"bad addr":         {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_SIP_TCP": "nope"},
		"half livekit":     {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_LIVEKIT_USER": "x"},
		"weak outbound":    {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_OUTBOUND_USER": "x", "LL_SIPGW_OUTBOUND_PASS": "short"},
		"store no key":     {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_STORE_FILE": "/tmp/x"},
		"bad duration":     {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_RING_TIMEOUT": "soon"},
		"bad level":        {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_LOG_LEVEL": "loud"},
		"mtls without tls": {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_CONTROL_CLIENT_CA": "/ca.pem"},
		"tiny messages":    {"LL_SIPGW_CONTROL_TOKEN": token, "LL_SIPGW_MAX_MESSAGE_BYTES": "100"},
	}
	for name, m := range cases {
		if _, err := Load("", env(m)); err == nil {
			t.Errorf("%s: accepted", name)
		} else if strings.Contains(err.Error(), token) {
			t.Errorf("%s: error echoes the token", name)
		}
	}
}
