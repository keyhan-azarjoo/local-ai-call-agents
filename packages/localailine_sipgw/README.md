# localailine-sipgw

A SIP gateway that connects people's **existing phone numbers** to [LocalAILine](https://github.com/keyhan-azarjoo/local-ai-call-agents) through their own phone provider. No hardware, no number porting.

For each line it signs in (SIP `REGISTER`) to the person's provider, just like a desk phone would, and keeps that sign-in alive. When the number rings, the provider sends the call to the gateway, and the gateway hands it to [LiveKit SIP](https://docs.livekit.io/sip/), where the LocalAILine agent answers. When the agent calls out, LiveKit hands the call to the gateway, which places it through the line's provider, showing the line's own number.

Only signalling passes through the gateway. The SDP is copied unchanged, so the audio flows directly between the provider and LiveKit.

```
 caller ──PSTN──> provider ──SIP (registered TLS/TCP/UDP flow)──> sipgw ──SIP──> LiveKit SIP ──> agent
                     ^                                              │
                     └──────────── RTP audio, direct ───────────────┼──────────> LiveKit SIP
```

One instance serves a desktop (one line or a few) or a server with a few thousand lines. It generalises the single-account bridge the desktop app ships for Twilio (`app/assets/engine/sipreg`): many lines, any provider, both directions.

## In the desktop app

The LocalAILine desktop app runs the gateway for the line type **My number, through my provider** (see [Phone lines](../../docs/guides/phone-lines.md)):

- **Built on first use.** The app carries this package's source as Flutter package assets (`pubspec.yaml` here lists the files; nothing is copied in git). The first time a line is tested or connected, the app writes the source to a temporary folder and runs `go build ./cmd/sipgw` into its data folder (`bin/ll-sipgw`), like the Twilio call bridge. It builds again when a new app version brings different source. Go is needed (`brew install go`).
- **Started on loopback.** The control API listens on `127.0.0.1` on a free port, with a new random token each start. Providers reach the gateway on port 5070 (UDP and TCP); TLS and TCP lines need no router change. The internal listener is `127.0.0.1:5092` (the Twilio bridge uses 5090).
- **Lines.** Each `sip` line is sent as account `line<id>` (signed out when its calls are set to **Off**). The encrypted store is `sipgw-lines.enc` in the app's data folder; its key and the LiveKit logins are in `sipgw.secret` next to it, readable only by the user.
- **LiveKit.** Per line, an inbound trunk for the line's number (only from `127.0.0.1`, with the gateway's login) and a dispatch rule into rooms `pstn-in-<line id>-…`, and an outbound trunk to the internal listener with `X-LL-Line: line<id>`.

## Run it

```sh
go build -o sipgw ./cmd/sipgw

export LL_SIPGW_CONTROL_TOKEN=$(openssl rand -hex 24)     # protects the control API
export LL_SIPGW_LIVEKIT_ADDR=127.0.0.1:5080               # LiveKit SIP
export LL_SIPGW_LIVEKIT_USER=sipgw LL_SIPGW_LIVEKIT_PASS=… # what LiveKit's inbound trunk expects
export LL_SIPGW_OUTBOUND_USER=livekit LL_SIPGW_OUTBOUND_PASS=… # what LiveKit's outbound trunk sends us
export LL_SIPGW_STORE_FILE=~/.localailine/sipgw.enc LL_SIPGW_STORE_KEY=$(openssl rand -base64 32)  # optional
./sipgw            # or: ./sipgw -config sipgw.yaml ; ./sipgw -env lists every variable
```

Then add a line:

```sh
curl -X PUT -H "Authorization: Bearer $LL_SIPGW_CONTROL_TOKEN" http://127.0.0.1:8090/v1/accounts/home \
  -d '{"number":"+447700900123","domain":"sip.example.com","transport":"tls",
       "username":"1234567","password":"…","mode":"on"}'
curl -H "Authorization: Bearer $LL_SIPGW_CONTROL_TOKEN" http://127.0.0.1:8090/v1/accounts/home
```

Docker (static binary on distroless, runs as uid 65532):

```sh
docker build -t localailine-sipgw packages/localailine_sipgw
docker run -d --name sipgw \
  -e LL_SIPGW_CONTROL_TOKEN=… -e LL_SIPGW_PUBLIC_HOST=sip.gw.example.com \
  -e LL_SIPGW_LIVEKIT_ADDR=livekit-sip:5060 -e LL_SIPGW_INTERNAL_HOST=sipgw \
  -e LL_SIPGW_STORE_FILE=/data/accounts.enc -e LL_SIPGW_STORE_KEY=… -v sipgw-data:/data \
  -p 5060:5060/udp -p 5060:5060/tcp -p 127.0.0.1:8090:8090 localailine-sipgw
```

Publish only the provider-facing ports (5060/5061) to the internet. Keep 5090 (internal) and 8090 (control) on a private network.

## Provider examples

Values as commonly documented. **Check with your provider**: domains, ports, TLS support and which username to use differ between products and change over time. The gateway needs the provider to offer **SIP registration** (a "SIP device", "SIP phone" or "credential" login), not only a trunk that sends calls to a fixed IP.

| Provider | Domain (registrar) | Port / transport | Username | Notes |
|---|---|---|---|---|
| BT Cloud Voice | from BT (per account) | 5060 UDP/TCP | SIP user from the BT portal | Only where BT gives out SIP credentials for a user/device ("third-party SIP device"). BT Digital Voice home lines usually do not expose SIP credentials (they are locked to the Smart Hub). Check with your provider. |
| Vonage Business | from Vonage (per account) | 5060 UDP/TCP, TLS on some plans | the SIP device's user | Use a "SIP device / BYOD" login from the admin portal. Vonage API (`sip.nexmo.com`) trunks do not register, so they don't fit. Check with your provider. |
| sipgate (UK) | `sipgate.co.uk` | 5060 UDP/TCP | SIP-ID (e.g. `1234567e0`) | sipgate.de: `sipgate.de`. TLS (5061) on some plans. Check with your provider. |
| Telnyx | `sip.telnyx.com` | 5060 UDP/TCP, 5061 TLS | the credential connection's username | Use a *credential* SIP connection. Check with your provider. |
| Zen Internet (UK) | from Zen's VoIP setup sheet | 5060 UDP | the VoIP account number | Check with your provider. |
| Twilio | `<name>.sip.twilio.com` (SIP Domain with registration on) | 5061 TLS | a SIP credential list user | What the desktop app's `sipreg` uses. Calls reach the registration through the domain's voice URL. |
| Any other | the provider's SIP server | 5061 TLS if offered, else 5060 TCP, else 5060 UDP | as given | `auth_username` if the digest login differs from the SIP user, `outbound_proxy` if the provider names one, `realm` to pin the digest realm. |

Prefer TLS, then TCP. Over TCP and TLS the provider sends calls back over the gateway's own connection, so nothing has to be opened on a home router.

## Lines (accounts)

| Field | Meaning |
|---|---|
| `number` | the line's own number, E.164 (`+447700900123`). National numbers work with `country_code`. |
| `domain`, `port`, `transport` | registrar; `transport` is `tls` (default), `tcp` or `udp`; `port` defaults to 5061 for TLS, else 5060 |
| `username`, `auth_username`, `password` | SIP user, digest user if different, digest password. The password is never returned by the API. On update, leave it out to keep the stored one. |
| `outbound_proxy` | `host[:port]` to send everything through |
| `realm` | only answer digest challenges for this realm |
| `expires` | registration time asked for (default 600 s; raised automatically on `423 Interval Too Brief`) |
| `mode` | `on`: registered, and calls go to the agent. `off`: signed out (`Expires: 0`), so the provider rings the person's other phones as before. |
| `tenant` | sent to LiveKit as `X-LL-Tenant` |
| `country_code` | e.g. `44`: turns `07700…` into `+447700…` (caller numbers, and the dialled number on outbound calls) |
| `allowed_sources` | extra IPs/CIDRs the provider may send calls from (some providers send INVITEs from addresses that aren't in their domain's DNS) |

Status per line: `registering`, `registered`, `failed` or `off`, with `last_error` in plain words ("wrong username or password", "the provider's address … could not be found", "… refused the connection: check the port and transport", "secure connection … failed: the certificate could not be verified …"), `last_registered`, `expires_at` and the registered `contact`.

## Control API

HTTP/JSON on `control_listen`. Every request except `/healthz` needs `Authorization: Bearer <control_token>`. The token is compared in constant time. After about 10 wrong tokens from one address, that address gets `429` for a while. Optional HTTPS (`control_tls_cert`/`control_tls_key`) and mTLS (`control_client_ca`).

| Request | Answer |
|---|---|
| `PUT /v1/accounts/{id}` | add or replace a line (body: the fields above). `200` with the line's view, or `400 {"error": "…"}` in plain words |
| `DELETE /v1/accounts/{id}` | sign the line out, then remove it. `204` or `404` |
| `GET /v1/accounts/{id}` | the line and its status (never the password or the token) |
| `GET /v1/accounts` | `{"accounts": [...]}`. Whatever manages the lines can compare this with its own list after a restart and send what's missing. |
| `POST /v1/accounts/{id}/test` | one REGISTER attempt now: `{"ok": false, "result": "wrong username or password …"}`. For a line that is `off`, a successful test binding is removed straight away. |
| `GET /healthz` | `{"status":"ok"}` (no token) |
| `GET /metrics` | Prometheus text: `sipgw_registrations_ok_total`, `sipgw_registrations_failed_total`, `sipgw_calls_in_total`, `sipgw_calls_out_total`, `sipgw_calls_rejected_total`, `sipgw_calls_answered_total`, `sipgw_active_calls`, `sipgw_accounts`, `sipgw_accounts_registered`, `sipgw_control_auth_failed_total` |

Lines live in memory. With `store_file` and `store_key` they are also saved, after every change, in one AES-256-GCM encrypted file (mode 0600, written atomically), so a desktop restart keeps them. The key comes from the environment, never from the file. Where another program keeps the lines, the store can stay off and that program sends the lines again on start.

## Configuration

A YAML (or JSON) file given with `-config` or `LL_SIPGW_CONFIG`, and/or environment variables. The environment wins. Unknown keys in the file are an error. Set a listener's address to empty to turn it off.

| Variable | File key | Default | Meaning |
|---|---|---|---|
| `LL_SIPGW_PUBLIC_HOST` | `public_host` | (learned) | host/IP put in Contact and Via. Empty: STUN result if `stun_server` is set, else what the provider reports (`received`/`rport`), else the local address |
| `LL_SIPGW_STUN_SERVER` | `stun_server` | | e.g. `stun.l.google.com:19302`, to learn the public IP behind NAT (checked every 5 min) |
| `LL_SIPGW_SIP_UDP` | `sip_udp` | `:5060` | provider-facing UDP listener (REGISTERs over UDP leave from it) |
| `LL_SIPGW_SIP_TCP` | `sip_tcp` | `:5060` | provider-facing TCP listener |
| `LL_SIPGW_SIP_TLS` | `sip_tls` | `:5061` | provider-facing TLS listener, only if `tls_cert`/`tls_key` are set |
| `LL_SIPGW_PUBLIC_UDP_PORT`, `…_TCP_PORT`, `…_TLS_PORT` | `public_udp_port`, … | listener's | port in Contact when a NAT/port-forward maps it differently |
| `LL_SIPGW_TLS_CERT`, `LL_SIPGW_TLS_KEY` | `tls_cert`, `tls_key` | | certificate for `public_host` (PEM) |
| `LL_SIPGW_PROVIDER_CA_FILE` | `provider_ca_file` | system roots | extra CAs for providers' TLS certificates |
| `LL_SIPGW_INTERNAL_LISTEN` | `internal_listen` | `127.0.0.1:5090` | where LiveKit SIP sends outbound calls and in-call requests (TCP and UDP) |
| `LL_SIPGW_INTERNAL_HOST` | `internal_host` | listen host (or 127.0.0.1) | how LiveKit reaches `internal_listen` (Contact/Via on the LiveKit side) |
| `LL_SIPGW_LIVEKIT_ADDR` | `livekit_addr` | `127.0.0.1:5080` | LiveKit SIP |
| `LL_SIPGW_LIVEKIT_TRANSPORT` | `livekit_transport` | `tcp` | `tcp` or `udp` |
| `LL_SIPGW_LIVEKIT_USER`, `LL_SIPGW_LIVEKIT_PASS` | `livekit_user`, `livekit_pass` | | digest credentials LiveKit's inbound trunk expects from the gateway |
| `LL_SIPGW_OUTBOUND_USER`, `LL_SIPGW_OUTBOUND_PASS` | `outbound_user`, `outbound_pass` | | digest credentials LiveKit's outbound trunk must use with the gateway (password ≥ 12 chars). Empty: outbound calls are refused |
| `LL_SIPGW_OUTBOUND_REALM` | `outbound_realm` | `localailine-sipgw` | realm of that challenge |
| `LL_SIPGW_CONTROL_LISTEN` | `control_listen` | `127.0.0.1:8090` | control API |
| `LL_SIPGW_CONTROL_TOKEN` | `control_token` | (required, ≥ 16 chars) | bearer token |
| `LL_SIPGW_CONTROL_TLS_CERT`, `…_KEY`, `…_CLIENT_CA` | `control_tls_cert`, … | | HTTPS, and mTLS with a client CA |
| `LL_SIPGW_STORE_FILE` | `store_file` | (memory only) | encrypted accounts file |
| `LL_SIPGW_STORE_KEY` | `store_key` | | 32 bytes, hex or base64 (`openssl rand -base64 32`) |
| `LL_SIPGW_LOG_LEVEL` | `log_level` | `info` | `debug`, `info`, `warn`, `error` |
| `LL_SIPGW_KEEPALIVE_INTERVAL` | `keepalive_interval` | `25s` | CRLF ping (TCP/TLS) or OPTIONS (UDP) on each registered flow |
| `LL_SIPGW_RING_TIMEOUT` | `ring_timeout` | `120s` | unanswered calls are given up |
| `LL_SIPGW_MAX_CALL_DURATION` | `max_call_duration` | `4h` | any call is hung up after this |
| `LL_SIPGW_CALL_PROBE_INTERVAL` | `call_probe_interval` | `60s` | in-call OPTIONS to each side (0 = off) |
| `LL_SIPGW_MAX_MESSAGE_BYTES` | `max_message_bytes` | `32768` | larger SIP messages are dropped |
| `LL_SIPGW_INBOUND_RATE`, `…_BURST` | `inbound_rate`, `inbound_burst` | `2`/s, `20` | new calls (and pings) per source IP |
| `LL_SIPGW_DEFAULT_COUNTRY_CODE` | `default_country_code` | | for lines without `country_code` |
| `LL_SIPGW_UNREGISTER_ON_SHUTDOWN` | `unregister_on_shutdown` | `true` | sign every line out on stop, so calls go to the person's other phones while the gateway is down |

### Desktop behind NAT, or a server

- **Desktop:** use TLS or TCP lines. The gateway opens the connection, keeps it busy (CRLF every 25 s) and the provider sends calls back over it, so no port forwarding is needed. Via carries `rport`, and the address the provider reports back (`received`/`rport`) is used in Contact when no public host is configured. For UDP lines, REGISTERs leave from the UDP listener, so the NAT mapping matches the Contact, and OPTIONS keep it open. Set `stun_server` to put the real public IP in Contact.
- **Server with a public IP:** set `public_host` (and a certificate for it, to accept TLS connections from providers that open their own).

## How calls work

**Inbound.** Each line registers `Contact: <sip:TOKEN@public-host:port;transport=…>`, where `TOKEN` is 160 random bits in base32, made by the gateway and kept with the line. An INVITE is accepted only when all of these hold:

1. its Request-URI user (or To user) is a known token, looked up by hash and checked in constant time;
2. it arrived over the very connection that line registered on, or from an IP that the provider's domain resolves to (A/AAAA plus the SIP SRV targets, cached), or from the line's `allowed_sources`;
3. its source IP is under the rate limit;
4. the line is `on`.

Otherwise the answer is `404` (unknown token, line off) or `403`, with no details, and it is logged at debug level only.

The gateway then calls LiveKit with a new INVITE:

- Request-URI user and To: the line's number;
- From: the caller, from P-Asserted-Identity or From, in E.164 when possible (`anonymous` when withheld);
- `X-LL-Line: <line id>` and `X-LL-Tenant: <tenant>`;
- the provider's SDP, unchanged.

It answers LiveKit's digest challenge with `livekit_user`/`livekit_pass`. Nothing else from the provider's INVITE is passed on.

Ringing (180/183 with early media), the answer, ACK, BYE from either side, CANCEL, re-INVITE and UPDATE (hold, codec change), and INFO (DTMF), NOTIFY, REFER and MESSAGE inside the call are relayed both ways. RFC 4028 session timers are passed end to end.

**Outbound.** LiveKit sends an INVITE to `internal_listen` with the number to call in the Request-URI and `X-LL-Line: <line id>`. It must answer the gateway's `407` digest challenge with `outbound_user`/`outbound_pass`. The answer must be for that very Request-URI, and the nonce expires after 5 minutes. Without `X-LL-Line`, the line whose number matches the From user is used.

The gateway calls the provider with:

- From and P-Asserted-Identity: the line's own number (never anything from LiveKit's request);
- the line's digest credentials on 401/407;
- the line's registered connection (or its outbound proxy) as the route.

Outbound requests are accepted only on the internal listener. The provider-facing listeners never place calls, so the gateway is not an open relay.

**No leaked calls.** These limits end calls whose other side is gone:

- unanswered calls give up after `ring_timeout`;
- answered calls end after `max_call_duration`;
- a call ends when a session timer runs out without a refresh;
- a call ends when an in-call OPTIONS probe gets no answer or `481`;
- a call ends when a forwarded in-call request gets `481`;
- a `2xx` the caller never ACKs ends the call.

On shutdown every call gets a BYE (or a CANCEL), and lines are signed out.

## Setting up LiveKit

**Inbound trunk** (calls from the gateway to LiveKit):

```json
{ "trunk": { "name": "sipgw", "numbers": ["+447700900123"],
  "auth_username": "<livekit_user>", "auth_password": "<livekit_pass>",
  "allowed_addresses": ["<gateway IP>"],
  "headers_to_attributes": { "X-LL-Line": "ll.line", "X-LL-Tenant": "ll.tenant" } } }
```

`numbers` are the called numbers, i.e. the lines' own numbers. Leave it empty to accept any number from this trunk (auth still applies).

**Dispatch rule:** dispatch by called number. Dispatch rules attach to inbound trunks (`trunk_ids`), so either give each number its own inbound trunk (`numbers: ["+44…"]`) with its own rule, or use one trunk for all numbers and one rule. In the second case the agent tells the lines apart by the called number (`sip.trunkPhoneNumber`) or the `ll.line`/`ll.tenant` attributes. An individual-room rule (each call in its own room, the agent named in `room_config`) fits both.

**Outbound trunk** (calls from LiveKit through the gateway):

```json
{ "trunk": { "name": "sipgw-home", "address": "<internal_host>:<internal port>", "transport": "SIP_TRANSPORT_TCP",
  "numbers": ["+447700900123"], "auth_username": "<outbound_user>", "auth_password": "<outbound_pass>",
  "headers": { "X-LL-Line": "home" } } }
```

Use one outbound trunk per line (with that line's `X-LL-Line`), or one shared trunk and pass `X-LL-Line` in each `CreateSIPParticipant` request's `headers`.

**Media:** LiveKit SIP's RTP ports must be reachable by the providers (a public IP, or `use_external_ip` and forwarded RTP ports), because audio does not go through the gateway.

## Security model

- **Two SIP stacks.** The provider-facing one (internet) only accepts inbound calls and in-call requests for its own legs. The internal one (LiveKit) is the only place outbound calls are accepted, and only with digest credentials. A request is matched to a call only on the side it belongs to.
- **Unguessable Contacts.** A per-line 160-bit token is the only way to reach a line. Tokens are looked up by hash and compared in constant time. Calls are also checked against the registered flow or the provider's addresses, and rate-limited per source.
- **Caller ID can't be spoofed outbound.** From/PAI to the provider always come from the line's record.
- **Secrets.** Passwords and tokens are never returned by the API and never logged. sipgo's own logs are demoted to debug, with raw messages and anything that looks like credentials removed. Digest responses aren't logged. Stored lines are AES-256-GCM encrypted with a key from the environment.
- **Constant-time checks** for the control token, line tokens, digest usernames and responses.
- **Input limits.** SIP messages over `max_message_bytes` and malformed messages are dropped. The control API caps bodies at 64 KB, rejects unknown fields, rate-limits wrong tokens per address, and supports TLS/mTLS.
- **Container** runs as a non-root user (65532) on a distroless image, with no shell.

## Development

```sh
go vet ./... && go test ./...          # add -race to check for races
SIPGW_TEST_LOG=1 SIPGW_SIP_DEBUG=1 go test ./internal/gateway -run TestOutboundCall -v   # with logs and SIP traces
```

Unit tests cover:

- digest: RFC 2617 and RFC 7616 MD5/SHA-256 vectors, a cross-check against an independent implementation, and server-side verify with wrong password, wrong method, forged nonce and stale nonce;
- tokens: their shape, and constant-time lookup that rejects near misses;
- the rate limiter, config parsing (file, environment, errors), and E.164 normalisation;
- store encryption: round trip, wrong key, tampering, file mode;
- the DNS/SRV cache, STUN, the provider source check, caller-number extraction;
- the control API: auth, rate limiting, validation, no password in answers;
- registrar behaviour: 423 Min-Expires, Retry-After, re-registering when the connection drops, backoff, and the plain-words errors;
- log redaction.

Integration tests run the whole gateway against in-process sipgo fakes: a provider registrar that challenges with 401 (SHA-256) and later rings the registered Contact over the registered connection, and a LiveKit UAS that challenges with 407 (MD5) and answers 200 with SDP. They cover:

- REGISTER with auth;
- an inbound call with the right headers, answered, then BYE from each side;
- CANCEL while ringing;
- wrong tokens getting 403/404;
- an outbound call through the internal listener with the line's number as From, and refused outbound attempts;
- mode `off` sending `Expires: 0`, and delete;
- the test endpoint;
- re-INVITE (hold) and INFO (DTMF) passthrough;
- a vanished side being hung up;
- TLS and UDP registration and calls;
- shutdown: BYE for answered calls, CANCEL and 503 for ringing ones, lines signed out.

## License

Apache-2.0, see [LICENSE](LICENSE).
