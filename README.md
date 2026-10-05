# LocalLine

**Your computer answers your phone.** LocalLine is an open-source, self-hosted AI receptionist. It runs a local language model, local speech recognition and voices, and a built-in LiveKit voice server on your own computer. Connect a number from Twilio, Telnyx or any SIP provider, or plug in a landline, and your assistant answers calls using your knowledge, tools (MCP) and skills.

- No LocalLine cloud, no accounts, no telemetry
- Windows, macOS, Linux host · Android and iOS companion apps
- Ollama, llama.cpp, LM Studio, MLX, vLLM · Whisper, Parakeet · Kokoro, Piper
- Multi-user with roles, approvals for AI actions, encrypted local database

> **Status:** design phase. See the [architecture & plan](docs/PLAN.md) and the clickable [UI demo](demo/).

## Try the UI demo

```bash
cd demo && python3 -m http.server 4173
# open http://localhost:4173
```

## License

Apache-2.0
