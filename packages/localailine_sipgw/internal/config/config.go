// Package config reads the gateway's settings from a YAML (or JSON) file and/or LL_SIPGW_*
// environment variables. The environment wins, so secrets can stay out of the file.
package config

import (
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Config is everything the gateway needs. Empty listen addresses switch that listener off.
type Config struct {
	// Provider side (the internet).
	PublicHost     string `yaml:"public_host"`      // host/IP put in Contact and Via; "" = learn it (STUN, then what the provider sees)
	STUNServer     string `yaml:"stun_server"`      // e.g. stun.l.google.com:19302, to learn the public IP behind NAT
	SIPUDP         string `yaml:"sip_udp"`          // provider-facing UDP listener
	SIPTCP         string `yaml:"sip_tcp"`          // provider-facing TCP listener
	SIPTLS         string `yaml:"sip_tls"`          // provider-facing TLS listener (needs tls_cert/tls_key)
	PublicUDPPort  int    `yaml:"public_udp_port"`  // port in Contact if NAT maps it differently (0 = listener's)
	PublicTCPPort  int    `yaml:"public_tcp_port"`  //
	PublicTLSPort  int    `yaml:"public_tls_port"`  //
	TLSCert        string `yaml:"tls_cert"`         // certificate for public_host (PEM file)
	TLSKey         string `yaml:"tls_key"`          //
	ProviderCAFile string `yaml:"provider_ca_file"` // extra CA bundle for providers' TLS certificates (default: system roots)

	// LiveKit side (private).
	InternalListen   string `yaml:"internal_listen"`   // where LiveKit SIP sends outbound calls and in-call requests (TCP and UDP)
	InternalHost     string `yaml:"internal_host"`     // how LiveKit reaches internal_listen (default: its host)
	LiveKitAddr      string `yaml:"livekit_addr"`      // LiveKit SIP host:port
	LiveKitTransport string `yaml:"livekit_transport"` // tcp | udp
	LiveKitUser      string `yaml:"livekit_user"`      // digest credentials LiveKit's inbound trunk expects
	LiveKitPass      string `yaml:"livekit_pass"`      //
	OutboundUser     string `yaml:"outbound_user"`     // digest credentials LiveKit's outbound trunk uses with us
	OutboundPass     string `yaml:"outbound_pass"`     //
	OutboundRealm    string `yaml:"outbound_realm"`    //

	// Control API.
	ControlListen   string `yaml:"control_listen"`
	ControlToken    string `yaml:"control_token"`
	ControlTLSCert  string `yaml:"control_tls_cert"`  // serve HTTPS
	ControlTLSKey   string `yaml:"control_tls_key"`   //
	ControlClientCA string `yaml:"control_client_ca"` // require client certificates from this CA (mTLS)

	// Persistence.
	StoreFile string `yaml:"store_file"` // encrypted accounts file ("" = memory only)
	StoreKey  string `yaml:"store_key"`  // 32 bytes, hex or base64; better given as LL_SIPGW_STORE_KEY

	// Behaviour.
	LogLevel             string   `yaml:"log_level"`              // debug | info | warn | error
	KeepaliveInterval    Duration `yaml:"keepalive_interval"`     // CRLF (TCP/TLS) or OPTIONS (UDP) to hold NAT open
	RingTimeout          Duration `yaml:"ring_timeout"`           // give up on an unanswered call
	MaxCallDuration      Duration `yaml:"max_call_duration"`      // hang up any call older than this
	CallProbeInterval    Duration `yaml:"call_probe_interval"`    // in-call OPTIONS to find vanished sides (0 = off)
	MaxMessageBytes      int      `yaml:"max_message_bytes"`      // larger SIP messages are dropped
	InboundRate          float64  `yaml:"inbound_rate"`           // new calls per second per source IP
	InboundBurst         int      `yaml:"inbound_burst"`          //
	DefaultCountryCode   string   `yaml:"default_country_code"`   // for national caller numbers when the line has none
	UnregisterOnShutdown *bool    `yaml:"unregister_on_shutdown"` // sign lines out on stop, so calls go to the person's other phones
}

// Duration is a time.Duration written as "25s", "2m", or a number of seconds.
type Duration struct{ time.Duration }

// UnmarshalYAML accepts "90s" or 90.
func (d *Duration) UnmarshalYAML(n *yaml.Node) error {
	v, err := parseDuration(n.Value)
	if err != nil {
		return err
	}
	d.Duration = v
	return nil
}

func parseDuration(s string) (time.Duration, error) {
	s = strings.TrimSpace(s)
	if n, err := strconv.Atoi(s); err == nil {
		return time.Duration(n) * time.Second, nil
	}
	v, err := time.ParseDuration(s)
	if err != nil {
		return 0, fmt.Errorf("%q is not a duration (e.g. 30s, 5m)", s)
	}
	return v, nil
}

// Default is the configuration before the file and environment are applied.
func Default() Config {
	t := true
	return Config{
		SIPUDP:               ":5060",
		SIPTCP:               ":5060",
		SIPTLS:               ":5061",
		InternalListen:       "127.0.0.1:5090",
		LiveKitAddr:          "127.0.0.1:5080",
		LiveKitTransport:     "tcp",
		OutboundRealm:        "localailine-sipgw",
		ControlListen:        "127.0.0.1:8090",
		LogLevel:             "info",
		KeepaliveInterval:    Duration{25 * time.Second},
		RingTimeout:          Duration{120 * time.Second},
		MaxCallDuration:      Duration{4 * time.Hour},
		CallProbeInterval:    Duration{60 * time.Second},
		MaxMessageBytes:      32 * 1024,
		InboundRate:          2,
		InboundBurst:         20,
		UnregisterOnShutdown: &t,
	}
}

// Load reads path (if not empty) over the defaults, then the environment over that, and checks
// the result. lookupEnv is os.LookupEnv outside tests (nil means os.LookupEnv).
func Load(path string, lookupEnv func(string) (string, bool)) (*Config, error) {
	c := Default()
	if path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		dec := yaml.NewDecoder(strings.NewReader(string(data)))
		dec.KnownFields(true) // a typo in a key is an error, not a silently ignored setting
		if err := dec.Decode(&c); err != nil {
			return nil, fmt.Errorf("config %s: %w", path, err)
		}
	}
	if err := c.applyEnv(lookupEnv); err != nil {
		return nil, err
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

// EnvVars lists every variable read, with the file key it overrides (for the README and -help).
var EnvVars = []struct{ Env, Key string }{
	{"LL_SIPGW_PUBLIC_HOST", "public_host"},
	{"LL_SIPGW_STUN_SERVER", "stun_server"},
	{"LL_SIPGW_SIP_UDP", "sip_udp"},
	{"LL_SIPGW_SIP_TCP", "sip_tcp"},
	{"LL_SIPGW_SIP_TLS", "sip_tls"},
	{"LL_SIPGW_PUBLIC_UDP_PORT", "public_udp_port"},
	{"LL_SIPGW_PUBLIC_TCP_PORT", "public_tcp_port"},
	{"LL_SIPGW_PUBLIC_TLS_PORT", "public_tls_port"},
	{"LL_SIPGW_TLS_CERT", "tls_cert"},
	{"LL_SIPGW_TLS_KEY", "tls_key"},
	{"LL_SIPGW_PROVIDER_CA_FILE", "provider_ca_file"},
	{"LL_SIPGW_INTERNAL_LISTEN", "internal_listen"},
	{"LL_SIPGW_INTERNAL_HOST", "internal_host"},
	{"LL_SIPGW_LIVEKIT_ADDR", "livekit_addr"},
	{"LL_SIPGW_LIVEKIT_TRANSPORT", "livekit_transport"},
	{"LL_SIPGW_LIVEKIT_USER", "livekit_user"},
	{"LL_SIPGW_LIVEKIT_PASS", "livekit_pass"},
	{"LL_SIPGW_OUTBOUND_USER", "outbound_user"},
	{"LL_SIPGW_OUTBOUND_PASS", "outbound_pass"},
	{"LL_SIPGW_OUTBOUND_REALM", "outbound_realm"},
	{"LL_SIPGW_CONTROL_LISTEN", "control_listen"},
	{"LL_SIPGW_CONTROL_TOKEN", "control_token"},
	{"LL_SIPGW_CONTROL_TLS_CERT", "control_tls_cert"},
	{"LL_SIPGW_CONTROL_TLS_KEY", "control_tls_key"},
	{"LL_SIPGW_CONTROL_CLIENT_CA", "control_client_ca"},
	{"LL_SIPGW_STORE_FILE", "store_file"},
	{"LL_SIPGW_STORE_KEY", "store_key"},
	{"LL_SIPGW_LOG_LEVEL", "log_level"},
	{"LL_SIPGW_KEEPALIVE_INTERVAL", "keepalive_interval"},
	{"LL_SIPGW_RING_TIMEOUT", "ring_timeout"},
	{"LL_SIPGW_MAX_CALL_DURATION", "max_call_duration"},
	{"LL_SIPGW_CALL_PROBE_INTERVAL", "call_probe_interval"},
	{"LL_SIPGW_MAX_MESSAGE_BYTES", "max_message_bytes"},
	{"LL_SIPGW_INBOUND_RATE", "inbound_rate"},
	{"LL_SIPGW_INBOUND_BURST", "inbound_burst"},
	{"LL_SIPGW_DEFAULT_COUNTRY_CODE", "default_country_code"},
	{"LL_SIPGW_UNREGISTER_ON_SHUTDOWN", "unregister_on_shutdown"},
}

// applyEnv sets every field whose variable is present (even if empty: "" turns a listener off).
func (c *Config) applyEnv(lookupEnv func(string) (string, bool)) error {
	if lookupEnv == nil {
		lookupEnv = os.LookupEnv
	}
	str := map[string]*string{
		"public_host": &c.PublicHost, "stun_server": &c.STUNServer, "sip_udp": &c.SIPUDP, "sip_tcp": &c.SIPTCP,
		"sip_tls": &c.SIPTLS, "tls_cert": &c.TLSCert, "tls_key": &c.TLSKey, "provider_ca_file": &c.ProviderCAFile,
		"internal_listen": &c.InternalListen, "internal_host": &c.InternalHost, "livekit_addr": &c.LiveKitAddr,
		"livekit_transport": &c.LiveKitTransport, "livekit_user": &c.LiveKitUser, "livekit_pass": &c.LiveKitPass,
		"outbound_user": &c.OutboundUser, "outbound_pass": &c.OutboundPass, "outbound_realm": &c.OutboundRealm,
		"control_listen": &c.ControlListen, "control_token": &c.ControlToken, "control_tls_cert": &c.ControlTLSCert,
		"control_tls_key": &c.ControlTLSKey, "control_client_ca": &c.ControlClientCA, "store_file": &c.StoreFile,
		"store_key": &c.StoreKey, "log_level": &c.LogLevel, "default_country_code": &c.DefaultCountryCode,
	}
	ints := map[string]*int{
		"public_udp_port": &c.PublicUDPPort, "public_tcp_port": &c.PublicTCPPort, "public_tls_port": &c.PublicTLSPort,
		"max_message_bytes": &c.MaxMessageBytes, "inbound_burst": &c.InboundBurst,
	}
	durs := map[string]*Duration{
		"keepalive_interval": &c.KeepaliveInterval, "ring_timeout": &c.RingTimeout,
		"max_call_duration": &c.MaxCallDuration, "call_probe_interval": &c.CallProbeInterval,
	}
	for _, ev := range EnvVars {
		v, set := lookupEnv(ev.Env)
		if !set {
			continue
		}
		switch {
		case str[ev.Key] != nil:
			*str[ev.Key] = v
		case ints[ev.Key] != nil:
			n, err := strconv.Atoi(strings.TrimSpace(v))
			if err != nil {
				return fmt.Errorf("%s: %q is not a whole number", ev.Env, v)
			}
			*ints[ev.Key] = n
		case durs[ev.Key] != nil:
			d, err := parseDuration(v)
			if err != nil {
				return fmt.Errorf("%s: %w", ev.Env, err)
			}
			durs[ev.Key].Duration = d
		case ev.Key == "inbound_rate":
			f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
			if err != nil {
				return fmt.Errorf("%s: %q is not a number", ev.Env, v)
			}
			c.InboundRate = f
		case ev.Key == "unregister_on_shutdown":
			b, err := strconv.ParseBool(strings.TrimSpace(v))
			if err != nil {
				return fmt.Errorf("%s: %q is not true/false", ev.Env, v)
			}
			c.UnregisterOnShutdown = &b
		}
	}
	return nil
}

// Validate checks the settings and says what is wrong in plain words.
func (c *Config) Validate() error {
	var errs []error
	addr := func(name, v string, required bool) {
		if v == "" {
			if required {
				errs = append(errs, fmt.Errorf("%s is required", name))
			}
			return
		}
		if _, _, err := net.SplitHostPort(v); err != nil {
			errs = append(errs, fmt.Errorf("%s must be host:port (got %q)", name, v))
		}
	}
	addr("sip_udp", c.SIPUDP, false)
	addr("sip_tcp", c.SIPTCP, false)
	addr("sip_tls", c.SIPTLS, false)
	addr("internal_listen", c.InternalListen, true)
	addr("livekit_addr", c.LiveKitAddr, true)
	addr("control_listen", c.ControlListen, true)
	if c.STUNServer != "" {
		addr("stun_server", c.STUNServer, false)
	}
	if (c.TLSCert == "") != (c.TLSKey == "") {
		errs = append(errs, errors.New("tls_cert and tls_key go together"))
	}
	if (c.ControlTLSCert == "") != (c.ControlTLSKey == "") {
		errs = append(errs, errors.New("control_tls_cert and control_tls_key go together"))
	}
	if c.ControlClientCA != "" && c.ControlTLSCert == "" {
		errs = append(errs, errors.New("control_client_ca (mTLS) needs control_tls_cert and control_tls_key"))
	}
	c.LiveKitTransport = strings.ToLower(c.LiveKitTransport)
	if c.LiveKitTransport != "tcp" && c.LiveKitTransport != "udp" {
		errs = append(errs, errors.New("livekit_transport must be tcp or udp"))
	}
	if (c.LiveKitUser == "") != (c.LiveKitPass == "") {
		errs = append(errs, errors.New("livekit_user and livekit_pass go together"))
	}
	if (c.OutboundUser == "") != (c.OutboundPass == "") {
		errs = append(errs, errors.New("outbound_user and outbound_pass go together"))
	}
	if c.OutboundPass != "" && len(c.OutboundPass) < 12 {
		errs = append(errs, errors.New("outbound_pass must be at least 12 characters"))
	}
	if len(c.ControlToken) < 16 {
		errs = append(errs, errors.New("control_token is required and must be at least 16 characters (e.g. `openssl rand -hex 24`)"))
	}
	if c.StoreFile != "" && c.StoreKey == "" {
		errs = append(errs, errors.New("store_file needs store_key (LL_SIPGW_STORE_KEY)"))
	}
	switch strings.ToLower(c.LogLevel) {
	case "debug", "info", "warn", "error":
	default:
		errs = append(errs, errors.New("log_level must be debug, info, warn or error"))
	}
	if c.KeepaliveInterval.Duration < 5*time.Second {
		errs = append(errs, errors.New("keepalive_interval must be at least 5s"))
	}
	if c.RingTimeout.Duration < 5*time.Second {
		errs = append(errs, errors.New("ring_timeout must be at least 5s"))
	}
	if c.MaxCallDuration.Duration < time.Minute {
		errs = append(errs, errors.New("max_call_duration must be at least 1m"))
	}
	if c.CallProbeInterval.Duration != 0 && c.CallProbeInterval.Duration < 5*time.Second {
		errs = append(errs, errors.New("call_probe_interval must be 0 (off) or at least 5s"))
	}
	if c.MaxMessageBytes < 2048 || c.MaxMessageBytes > 65535 {
		errs = append(errs, errors.New("max_message_bytes must be between 2048 and 65535"))
	}
	if c.InboundBurst < 1 {
		errs = append(errs, errors.New("inbound_burst must be at least 1"))
	}
	if c.UnregisterOnShutdown == nil {
		t := true
		c.UnregisterOnShutdown = &t
	}
	return errors.Join(errs...)
}

// InternalAdvertised is how LiveKit reaches us: internal_host, else internal_listen's host
// (with 0.0.0.0/:: replaced by 127.0.0.1), plus the listen port.
func (c *Config) InternalAdvertised() (string, int) {
	h, p, _ := net.SplitHostPort(c.InternalListen)
	port, _ := strconv.Atoi(p)
	if c.InternalHost != "" {
		h = c.InternalHost
	}
	if h == "" || h == "0.0.0.0" || h == "::" {
		h = "127.0.0.1"
	}
	return h, port
}
