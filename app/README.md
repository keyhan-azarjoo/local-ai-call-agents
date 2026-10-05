# LocalAILine app (Flutter)

Desktop host app for Windows, macOS and Linux. The Android and iOS builds become the companion app.

## What works today
- First-run setup: owner account (Argon2id), hardware scan, AI engine check, model recommendation
- Sign-in, users and roles (Owner, Admin, Operator, Viewer), audit log
- Language models through Ollama: detect or start the engine, download (with progress), load, unload, delete, plus a "fits this computer" check
- Talk to Ava, two modes: *pretend I'm a caller* and *give instructions*. Asking Ava to call someone drafts a call task.
- Voice: microphone → whisper.cpp → model → Piper, or the OS voice as a fallback
- Make a call: just ask, or fill in the form → call queue
- Phone lines: Twilio, Telnyx, SIP, FXO landline. Twilio and Telnyx credentials are checked live with the provider.
- Agents, Automations & loops, Contacts & rules, Knowledge, Tools (MCP), Skills (saved locally)
- Cloud AI instead of local: OpenAI, Azure OpenAI, Google Gemini or Anthropic Claude. Pick the provider, paste the key, Test, Use.
- Chat page: text chat with the AI, chats saved per user
- MCP tools for real: URL (streamable HTTP or SSE) or local command; OAuth sign-in in the browser when the server asks (discovery, dynamic registration, PKCE, refresh), or an API key header. Ava uses the tools in Chat and Talk; anything not read-only asks first.
- Phones and other computers: install LocalAILine, choose **Connect to my LocalAILine computer**, enter the 6-digit code from *Phone line → Answer on your phone*. The phone rings first on calls (Answer here / Let Ava / Decline), can chat and talk to Ava, approve actions, and see calls. Direct connection on your network; no other server.
- The menu is always the same 8 items; **Show all features** adds tabs inside My assistant, Phone line and Settings

## Not yet (next milestones)
Real phone calls (phone gateway + LiveKit agent worker) — so “Answer here” on a phone doesn’t carry call audio yet, knowledge indexing, running MCP tools, automations, pairing the companion app, encrypting stored credentials and API keys (they are in the local database today).

## Run

```bash
# phone test (needs the computer app running with LOCALAILINE_DEV_PAIRCODE=246810 LOCALAILINE_DEV_RING=1)
flutter test integration_test/companion_test.dart -d <iphone-simulator-id>

flutter run -d macos      # or windows / linux
flutter test              # unit tests
flutter test integration_test/app_test.dart -d macos   # end-to-end, uses your local Ollama
```

Optional local tools: [Ollama](https://ollama.com), `whisper-cli` (whisper.cpp), `piper`.
