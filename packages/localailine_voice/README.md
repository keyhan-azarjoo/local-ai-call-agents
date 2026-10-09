# localailine-voice

The voice worker of [LocalAILine](https://github.com/keyhan-azarjoo/local-ai-call-agents), the AI phone
receptionist: a [LiveKit Agents](https://github.com/livekit/agents) worker that answers calls (phone
lines over SIP, or the app's own test calls), listens, thinks with the LocalAILine app, and speaks.

It is the same file the desktop app runs (`app/assets/engine/localailine_voice.py`); this package
only makes it installable.

```sh
pip install "localailine-voice[local]"   # with the local voices (Kokoro, Piper)
localailine-voice download-files         # LiveKit's end-of-turn and Silero models, once
localailine-voice start                  # (or `dev` while trying it out)
```

Hearing is whisper.cpp's server (`LL_WHISPER_URL`, or a pool in `LL_WHISPER_URLS`), the voice is
Kokoro (else Piper), and the brain is the LocalAILine app's OpenAI-compatible `/v1`, so its
documents, skills and tools apply.

## Environment

| Variable | Default | What it is |
|---|---|---|
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | | the LiveKit server |
| `LL_APP_URL` | | the LocalAILine app |
| `LL_LLM_KEY` | | bearer token for the app |
| `LL_LLM_BASE` | `http://127.0.0.1:11434/v1` | the brain's OpenAI-compatible endpoint (the app's is `<LL_APP_URL>/v1`) |
| `LL_LLM_MODEL` | `qwen3:4b-instruct` | model, only when run without the app |
| `LL_LANGUAGE` | `auto` | the caller's language, or `auto` to follow them |
| `LL_LINES` | `3` | calls ready to be answered at once |
| `LL_WHISPER_URL(S)`, `LL_WHISPER_ACCURATE_URL` | `http://127.0.0.1:8910` | the whisper.cpp server(s) |
| `LL_VOICES_DIR`, `LL_KOKORO_DIR`, `LL_TTS_SPEED` | | the local voices |
| `LL_RECORDINGS_DIR` | | where call recordings go |
| `LL_GREETING`, `LL_INSTRUCTIONS` | | used when the app doesn't give them |
| `LL_AGENT_NAME` | (empty) | name calls are dispatched to the worker by; empty: it joins every new room |
| `LL_PLUGIN` | (empty) | a Python module that can change a few things per call (below) |

## Plugin

`LL_PLUGIN=<importable module>` lets another package change a few things per call without changing
the worker. Every function is optional; a missing one, or `None` returned, keeps the worker's own.

| Function | Called | Returns |
|---|---|---|
| `host_for_job(metadata: str)` | at the start of each call, with the job's metadata | a `Host` (`url`, `token`, `llm_base`; a subclass can carry more), or `None` for the environment's |
| `make_stt(host, language, vocabulary)` | once per call | a LiveKit `stt.STT`, or `None` for whisper.cpp |
| `make_tts(host, voice, language, stt)` | once per call; `voice` is the app's voice for the agent (`""` if none) | a LiveKit `tts.TTS`, or `None` for Kokoro/Piper |
| `on_call_end(host, stats)` | when the call ends (may be a coroutine) | nothing. `stats`: `room`, `phoneCall`, `answered`, `callSeconds`, `llmTurns`, and the call's `stt` and `tts` |

The plugin can `import localailine_voice` for `Host`, `VOICE_CHOICE` (the app's voices per
language), `speakable` and the rest. The call sets `voice_override` on the voice when it is passed
to a teammate (and `_language`), and uses these when the hearing or voice has them:
`detected_language` (the language heard), `recorder` and `record_agent_audio(pcm, sr)` (call
recording), and `played(frame)` on the voice (each frame as it goes out).

## License

Apache-2.0
