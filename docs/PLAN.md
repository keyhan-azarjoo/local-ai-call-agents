# LocalLine — Architecture & Plan

> Your computer answers your phone. A private, self-hosted AI receptionist: local LLM, local speech-to-text and text-to-speech, a built-in LiveKit voice server, and phone lines from Twilio, Telnyx, any SIP provider, or a real landline. No LocalLine cloud, no accounts, no telemetry.

Status: **design / pre-implementation**. The clickable UI demo lives in [`/demo`](../demo).

---

## 1. Goals

| Goal | What it means in practice |
|---|---|
| Runs on the user's own computer | Windows, macOS, Linux host the whole system. |
| Mobile too | Android and iOS apps pair with the host: ring alerts, listen in, take over calls, approve actions, change settings. |
| Local AI | Pick or install an engine (Ollama, llama.cpp, LM Studio, MLX, vLLM). Download models sized to the hardware; load and unload them. Same for STT and TTS. |
| Real phone calls | Connect a number with provider credentials, or plug in a landline through an FXO box. The AI answers. |
| Acts, not just talks | MCP tools, RAG knowledge, skills, with per-tool permissions and human approval for anything that changes data. |
| Professional | Local encrypted database, multi-user with roles, audit log, backups, signed installers. |
| No server dependency | Everything ships in the installer or is downloaded from the original upstream (model hubs, engine vendors). |

## 2. Reality checks (decisions that shape the design)

1. **Phones can't be the host.** iOS can't run a background server or answer a cellular call with an app; Android only partly. Mobile apps are **companions** to a desktop host. (Optional later: an Android "lite host" for small models.)
2. **LiveKit SIP can't register to a provider.** It only accepts INVITEs at a reachable address, and needs Redis, cgo libs and host networking (weak on Windows/macOS Docker). Most home users have no public IP.
   → LocalLine ships its own small **Go phone gateway** (`llgw`) that *registers outward* to providers, accepts trunk/FXO INVITEs on the LAN, and publishes calls straight into LiveKit rooms via the LiveKit Go SDK. No Redis, no Docker, native on all three OSes. `livekit-sip` stays an optional "advanced trunk" mode on Linux.
3. **Raw SIP/RTP doesn't pass through Cloudflare Tunnel or Tailscale Funnel** (HTTP/TCP only). The fallback for providers without registration is **Media Streams over WebSocket** (Twilio `<Connect><Stream>`, Telnyx media streaming), which does tunnel fine.
4. **Licences.** LocalLine is Apache-2.0. Piper TTS is now GPL-3.0 → offered as an optional download, not bundled. Default voice is **Kokoro-82M** (Apache-2.0). Parakeet STT is CC-BY-4.0 (attribution in About). LiveKit turn-detector model has its own licence → downloaded on first run, user accepts terms.
5. **"Local" turn detection must really be local.** Pin the LiveKit local EOT model and never use `livekit.agents.inference` LLM/STT/TTS (those bill LiveKit Cloud).

## 3. Architecture

```
 ┌───────────────────────── Host computer (Win / macOS / Linux) ─────────────────────────┐
 │                                                                                        │
 │  LocalLine app (Flutter desktop)  ── UI, setup wizard, tray, supervisor                │
 │        │  local API (HTTP + WebSocket, random port + token)                             │
 │        ▼                                                                                │
 │  LocalLine Engine (Python, bundled runtime)                                            │
 │   ├─ Control API  — auth, users/roles, settings, calls, audit (SQLite + SQLCipher)     │
 │   ├─ Agent worker — LiveKit Agents: VAD → STT → LLM → TTS, barge-in, tools            │
 │   ├─ Speech servers — OpenAI-compatible /v1/audio/transcriptions & /v1/audio/speech   │
 │   │                   (faster-whisper / whisper.cpp / Parakeet · Kokoro / Piper)       │
 │   ├─ Knowledge     — ingest, chunk, embed (local), sqlite-vec search                  │
 │   ├─ Tools         — MCP client (stdio + HTTP), permissions, approval queue           │
 │   ├─ Skills        — folders of instructions + optional tools                         │
 │   └─ Model manager — hardware probe, catalog fit, download + SHA-256, load/unload      │
 │        │                                                                                │
 │  livekit-server (Go, native binary, single node, no Redis)  :7880                      │
 │        ▲                                                                                │
 │  llgw — LocalLine phone gateway (Go)                                                   │
 │   ├─ SIP REGISTER client  → Telnyx, Twilio SIP Domains, voip.ms, sipgate, any SIP     │
 │   ├─ SIP trunk listener   ← Twilio Elastic SIP, Telnyx, Vonage, Plivo (if reachable)  │
 │   ├─ FXO landline         ← Grandstream HT813 / Obihai on the LAN                      │
 │   ├─ Media Streams (WSS)  ← Twilio / Telnyx through a tunnel                           │
 │   └─ G.711/Opus ↔ LiveKit room audio, DTMF (RFC 4733), transfer                        │
 │                                                                                        │
 │  LLM engine (user's choice): Ollama · llama.cpp server · LM Studio · mlx_lm · vLLM     │
 └────────────────────────────────────────────────────────────────────────────────────────┘
          ▲  LAN / Tailscale (WebRTC + local API)
          │
   LocalLine mobile (Flutter, Android / iOS) — pair by QR, ring alerts, listen, take over
```

### Call flow (inbound)
1. Provider → `llgw` (registered line, trunk, FXO or media stream).
2. `llgw` checks caller rules (block list, VIP, quiet hours) via the Engine, then rings paired devices for N rings if configured.
3. `llgw` creates room `pstn-in-<id>` and joins the caller; Engine dispatches the agent.
4. Agent plays a pre-rendered greeting clip instantly (no TTS wait), then runs the turn loop.
5. Tool calls go through permissions; write actions wait for approval from any signed-in operator (desktop or phone) or are denied by policy.
6. Owner can **whisper**, **take over** (joins room from desktop or phone), or **transfer**.
7. On hang-up: transcript, recording, summary, actions → database; notification to paired devices.

### Latency budget (caller stops speaking → first audio)
| Stage | Target |
|---|---|
| Turn detection (VAD + EOT) | 200–300 ms |
| STT final | < 150 ms (streaming partials) |
| LLM first token | < 300 ms (model kept loaded, keep-alive pinned) |
| TTS first audio | < 150 ms (sentence-streamed) |
| **Total in-app** | **≤ 800 ms**, + PSTN 150–300 ms |

Measured on Apple Silicon in earlier prototypes: whisper.cpp base 322 ms + Ollama 0.5B 142 ms + Piper 107 ms ≈ 572 ms.

## 4. Technology choices

| Layer | Choice | Why |
|---|---|---|
| App UI | **Flutter 3.x** (desktop + mobile), Riverpod, go_router | One codebase for 5 OSes. |
| App ↔ Engine | Local HTTP + WebSocket, OpenAPI-generated Dart client | Same API serves mobile companions over LAN/Tailscale. |
| Engine | **Python 3.12**, FastAPI, LiveKit Agents 1.8+ | Best ecosystem for voice agents, STT/TTS, MCP, RAG. |
| Python packaging | python-build-standalone + `uv` lockfile, per OS/arch | Reproducible, no system Python required. |
| Voice server | **livekit-server** native binaries (Apache-2.0) | Pro-grade WebRTC SFU, runs single-node without Redis. |
| Phone gateway | **Go**: sipgo/diago + LiveKit server SDK | Registration behind NAT; native on Win/macOS/Linux. |
| LLM | Ollama default; llama.cpp built-in fallback; LM Studio, MLX (Mac), vLLM (Linux+NVIDIA) | All speak the OpenAI API → one adapter. |
| STT | faster-whisper / whisper.cpp (large-v3-turbo, small), **Parakeet TDT 0.6B v3** (ONNX), Vosk for tiny devices | Accuracy vs speed per tier; multilingual. |
| TTS | **Kokoro-82M** default; Piper (optional GPL download); Chatterbox Multilingual (GPU) | Licence-clean default, fast on CPU. |
| Turn-taking | Silero VAD + LiveKit local EOT model, backchannel filter, echo guard | Lessons from earlier call prototypes. |
| Database | **SQLite + SQLCipher**, sqlite-vec for embeddings | Single file, encrypted, easy backup. |
| Auth | Argon2id passwords, TOTP 2FA, short-lived JWT, roles: Owner/Admin/Operator/Viewer | Local multi-user with audit trail. |
| Secrets | OS keychain (Keychain, Credential Manager, libsecret) for provider credentials and DB key | Credentials never stored in plain text. |
| MCP | Official `mcp` Python SDK (pin `<2`), stdio + streamable HTTP | Per-caller-class tool sets, re-checked every call. |
| Installers | macOS DMG (signed + notarised), Windows MSIX/Inno Setup, Linux AppImage + .deb, Android APK/AAB, iOS TestFlight | GitHub Actions release pipeline. |

## 5. Hardware fit rules

- Q4_K_M weights ≈ 0.6 GB per billion params, + KV cache (0.5–1 GB at 8k ctx for 7–8B), + 1–2 GB overhead.
- Budget ≤ 85 % of VRAM (discrete GPU) or ≤ 70 % of unified memory (Apple Silicon); reserve 1–3 GB for STT + TTS.
- Refuse to load below 1 GB free RAM; abort a load below 256 MB; one model at a time under 16 GB.
- Tiers shown in the app:

| Tier | Machine | Thinking | Hearing | Voice |
|---|---|---|---|---|
| Light | 8 GB, any CPU | Qwen3 1.7B | Whisper small | Kokoro |
| Balanced | 16–32 GB or 8 GB GPU | Qwen3 8B | Whisper large-v3-turbo / Parakeet | Kokoro |
| Power | 24 GB+ NVIDIA | Mistral Small 24B / Qwen3 32B | Parakeet | Kokoro / Chatterbox |

Catalog is a versioned JSON in the repo (`catalog/models.json`): id, source URL, SHA-256, size, min RAM, tasks, languages, licence, platforms.

## 6. Security

- Gateway: allow-list provider IP ranges on trunk mode; reject unsolicited INVITEs (toll-fraud scanners hit open 5060 within minutes).
- Callers are strangers by default: screening mode exposes no tools and no private knowledge; knowledge sources and tools carry "who can hear/use it" scopes.
- Prompt-injection posture: no tool can both read private data and send it outward without approval.
- Every write action → approval queue (or denied by policy). Everything audited.
- Local API bound to 127.0.0.1; remote access only for paired devices with per-device keys (no shared owner password).
- Recording consent announcement on by default; retention policy configurable.

## 7. Repository layout (planned)

```
LocalLine/
├─ app/          Flutter app (desktop host UI + mobile companion)
├─ engine/       Python engine (API, agent, speech, knowledge, tools, models)
├─ gateway/      Go phone gateway (llgw)
├─ catalog/      Model + engine catalogs (JSON, checksums)
├─ packaging/    Installers, service units, bundled runtimes scripts
├─ docs/         Architecture, provider setup guides, FXO guide
└─ demo/         Static clickable UI demo (this phase)
```

## 8. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | Design demo | User approves look & page set. **← now** |
| M1 | Skeleton | Monorepo, CI, Flutter shell with all pages (mock data), Engine API stub, local DB + auth + users. |
| M2 | Local AI | Hardware probe, catalog, install/detect engines, download/verify, load/unload LLM + STT + TTS. |
| M3 | Talk to it | livekit-server bundled; "Talk to your assistant" from desktop browser/app; latency panel. |
| M4 | Phone lines | `llgw`: SIP registration (Telnyx, generic SIP, Twilio SIP Domain), FXO HT813, Twilio Elastic SIP trunk; test call wizard. |
| M5 | Acts | Persona & call flow, Knowledge (RAG), MCP tools with permissions/approvals, Skills. |
| M6 | Companion | Android/iOS pairing, ring alerts, listen/take over/approve. |
| M7 | Release | Signed installers for all OSes, docs, v0.1 public release. |

## 9. Open questions for the owner

- Name: **LocalLine** — OK?
- Default languages to ship voices for (English + Persian?).
- Should the first release also support **Twilio Media Streams** (tunnel) or only SIP registration + FXO?
- Licence: Apache-2.0 (recommended) vs GPL-3.0 (would allow bundling Piper).
