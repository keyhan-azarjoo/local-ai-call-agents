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
- The menu is always the same 8 items; **Show all features** adds tabs inside My assistant, Phone line and Settings

## Not yet (next milestones)
Real phone calls (phone gateway + LiveKit agent worker), knowledge indexing, running MCP tools, automations, pairing the companion app, encrypting stored credentials and API keys (they are in the local database today).

## Run

```bash
flutter run -d macos      # or windows / linux
flutter test              # unit tests
flutter test integration_test/app_test.dart -d macos   # end-to-end, uses your local Ollama
```

Optional local tools: [Ollama](https://ollama.com), `whisper-cli` (whisper.cpp), `piper`.
