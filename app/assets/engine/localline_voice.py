"""LocalAILine voice engine: a LiveKit Agents worker that runs the live call.

Everything is local:
  hearing  — whisper.cpp `whisper-server` (Metal GPU), streamed: interim words while you speak
  thinking — the LocalAILine app (OpenAI-compatible endpoint), so documents, skills and tools apply;
             or Ollama directly when run on its own
  voice    — Piper kept in memory (~80 ms per sentence), Kokoro optional
  turns    — Silero VAD + LiveKit's multilingual end-of-turn model, preemptive generation,
             interruptions, a "thinking" sound and short spoken fillers

Configuration comes from environment variables (set by the app):
  LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
  LL_LLM_BASE (e.g. http://127.0.0.1:7420/v1), LL_LLM_KEY, LL_LLM_MODEL
  LL_WHISPER_URL (http://127.0.0.1:8910), LL_LANGUAGE (auto | en | fa | …)
  LL_VOICES_DIR (folder with Piper .onnx voices), LL_GREETING, LL_INSTRUCTIONS
"""
from __future__ import annotations

import asyncio
import io
import json
import logging
import os
import random
import time
import urllib.request
import wave
from pathlib import Path

import aiohttp
import numpy as np
from livekit import rtc
from livekit.agents import (
    APIConnectOptions,
    Agent,
    AgentSession,
    JobContext,
    WorkerOptions,
    cli,
    stt,
    tts,
    utils,
)
from livekit.agents.types import DEFAULT_API_CONNECT_OPTIONS, NOT_GIVEN, NotGivenOr
from livekit.agents.voice.background_audio import AudioConfig, BackgroundAudioPlayer, BuiltinAudioClip
from livekit.plugins import openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

log = logging.getLogger("localline.voice")

WHISPER_URL = os.environ.get("LL_WHISPER_URL", "http://127.0.0.1:8910")
LANGUAGE = os.environ.get("LL_LANGUAGE", "auto")
VOICES_DIR = Path(os.environ.get("LL_VOICES_DIR", Path.home() / "Library/Application Support/com.localailine.localailine/models/tts"))

# Piper voices per language (downloaded on first use from the Piper voice library).
PIPER_VOICES = {
    "en": "en_GB-alba-medium",
    "fa": "fa_IR-amir-medium",
    "es": "es_ES-davefx-medium",
    "fr": "fr_FR-siwis-medium",
    "de": "de_DE-thorsten-medium",
    "it": "it_IT-riccardo-x_low",
    "ar": "ar_JO-kareem-medium",
    "tr": "tr_TR-dfki-medium",
    "pt": "pt_PT-tugão-medium",
    "nl": "nl_NL-mls-medium",
    "ru": "ru_RU-irina-medium",
    "zh": "zh_CN-huayan-medium",
}

# Short, natural fillers said while the answer is being prepared.
FILLERS = {
    "en": ["Mm, let me check.", "Sure, one moment.", "Okay, let me see.", "Right, just a sec."],
    "fa": ["یک لحظه.", "باشه، بذارید ببینم."],
    "es": ["Un momento.", "Vale, déjame ver."],
    "fr": ["Un instant.", "D'accord, je regarde."],
    "de": ["Einen Moment.", "Okay, ich schaue nach."],
}


EMOJI = __import__("re").compile("[\U0001F000-\U0001FAFF\u2600-\u27BF\uFE0F]")


def wav_bytes(pcm: np.ndarray, sr: int) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.astype(np.int16).tobytes())
    return buf.getvalue()


# ----------------------------------------------------------------------------- hearing

class WhisperStreamingSTT(stt.STT):
    """Streaming speech-to-text on whisper.cpp's server: interim words while the
    caller speaks (re-transcribed every ~0.4 s, ~150 ms each on Apple GPU) and a
    final transcript when they stop."""

    def __init__(self, *, url: str = WHISPER_URL, language: str = LANGUAGE, vad: silero.VAD | None = None):
        super().__init__(capabilities=stt.STTCapabilities(streaming=True, interim_results=True))
        self._url = url.rstrip("/") + "/inference"
        self._language = language
        self._vad = vad or silero.VAD.load(min_silence_duration=0.25)
        self._http: aiohttp.ClientSession | None = None
        self.detected_language = "en" if language == "auto" else language

    @property
    def model(self) -> str:
        return "whisper.cpp"

    @property
    def provider(self) -> str:
        return "local"

    def http(self) -> aiohttp.ClientSession:
        if self._http is None or self._http.closed:
            self._http = aiohttp.ClientSession()
        return self._http

    async def transcribe(self, pcm: np.ndarray, sr: int) -> tuple[str, str]:
        # Language detection on very short clips ("Hi there") is unreliable: reuse the last language.
        auto = self._language == "auto" and len(pcm) >= sr * 1.5
        form = aiohttp.FormData()
        form.add_field("file", wav_bytes(pcm, sr), filename="a.wav", content_type="audio/wav")
        form.add_field("response_format", "verbose_json")
        form.add_field("language", "auto" if auto else (self._language if self._language != "auto" else self.detected_language))
        form.add_field("temperature", "0")
        async with self.http().post(self._url, data=form, timeout=aiohttp.ClientTimeout(total=15)) as r:
            j = await r.json(content_type=None)
        text = (j.get("text") or "").strip()
        lang = j.get("language") or self.detected_language
        if auto and lang and len(lang) <= 3:
            self.detected_language = lang
        return text, self.detected_language

    async def _recognize_impl(self, buffer, *, language: NotGivenOr[str] = NOT_GIVEN, conn_options: APIConnectOptions):
        frame = rtc.combine_audio_frames(buffer)
        pcm = np.frombuffer(frame.data, dtype=np.int16)
        text, lang = await self.transcribe(pcm, frame.sample_rate)
        return stt.SpeechEvent(type=stt.SpeechEventType.FINAL_TRANSCRIPT, alternatives=[stt.SpeechData(language=lang, text=text)])

    def stream(self, *, language: NotGivenOr[str] = NOT_GIVEN, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS):
        return _WhisperStream(stt_=self, conn_options=conn_options)

    async def aclose(self) -> None:
        if self._http:
            await self._http.close()


class _WhisperStream(stt.RecognizeStream):
    def __init__(self, *, stt_: WhisperStreamingSTT, conn_options: APIConnectOptions):
        super().__init__(stt=stt_, conn_options=conn_options, sample_rate=16000)
        self._s = stt_

    async def _run(self) -> None:
        vad_stream = self._s._vad.stream()
        speaking = False
        chunks: list[np.ndarray] = []
        last_interim = 0.0
        busy = False
        last_text = ""
        last_cover = (0, 0.0)  # samples covered by last_text, when it was made

        async def interim():
            nonlocal busy, last_text, last_cover
            busy = True
            try:
                pcm = np.concatenate(chunks) if chunks else np.zeros(0, np.int16)
                if len(pcm) > 16000 * 0.3:
                    text, lang = await self._s.transcribe(pcm, 16000)
                    if text:
                        last_cover = (len(pcm), time.monotonic())
                    if speaking and text and text != last_text:
                        last_text = text
                        self._event_ch.send_nowait(stt.SpeechEvent(
                            type=stt.SpeechEventType.INTERIM_TRANSCRIPT,
                            alternatives=[stt.SpeechData(language=lang, text=text)]))
            except Exception as e:  # noqa: BLE001
                log.debug("interim failed: %s", e)
            finally:
                busy = False

        async def read_vad():
            nonlocal speaking, chunks, last_text, last_cover
            async for ev in vad_stream:
                name = ev.type.name if hasattr(ev.type, "name") else str(ev.type)
                if name == "INFERENCE_DONE":
                    # Silence just started: transcribe now so the final is ready when the pause is confirmed.
                    if speaking and not ev.speaking and 0.05 < ev.silence_duration < 0.2 and not busy:
                        asyncio.create_task(interim())
                    continue
                if name == "START_OF_SPEECH":
                    speaking = True
                    last_text = ""
                    last_cover = (0, 0.0)
                    chunks = [np.frombuffer(f.data, dtype=np.int16) for f in ev.frames]
                    self._event_ch.send_nowait(stt.SpeechEvent(type=stt.SpeechEventType.START_OF_SPEECH))
                elif name == "END_OF_SPEECH":
                    speaking = False
                    frames = ev.frames
                    pcm = np.concatenate([np.frombuffer(f.data, dtype=np.int16) for f in frames]) if frames else (np.concatenate(chunks) if chunks else np.zeros(0, np.int16))
                    chunks = []
                    text, lang = ("", self._s.detected_language)
                    # Fast final: a live transcript covering ~all of the speech, made a moment ago, is reused.
                    covered, made = last_cover
                    if last_text and covered >= len(pcm) - 16000 * 0.35 and time.monotonic() - made < 0.8:
                        text = last_text
                    elif len(pcm) > 16000 * 0.2:
                        try:
                            text, lang = await self._s.transcribe(pcm, 16000)
                        except Exception as e:  # noqa: BLE001
                            log.warning("final transcription failed: %s", e)
                    self._event_ch.send_nowait(stt.SpeechEvent(
                        type=stt.SpeechEventType.FINAL_TRANSCRIPT,
                        alternatives=[stt.SpeechData(language=lang, text=text)]))
                    self._event_ch.send_nowait(stt.SpeechEvent(type=stt.SpeechEventType.END_OF_SPEECH))

        vad_task = asyncio.create_task(read_vad())
        try:
            async for item in self._input_ch:
                if isinstance(item, self._FlushSentinel):
                    vad_stream.flush()
                    continue
                vad_stream.push_frame(item)
                if speaking:
                    chunks.append(np.frombuffer(item.data, dtype=np.int16))
                    now = time.monotonic()
                    if not busy and now - last_interim > 0.4:
                        last_interim = now
                        asyncio.create_task(interim())
            vad_stream.end_input()
            await vad_task
        finally:
            await utils.aio.cancel_and_wait(vad_task)
            await vad_stream.aclose()


# ----------------------------------------------------------------------------- voice

def ensure_piper_voice(lang: str) -> Path | None:
    name = PIPER_VOICES.get(lang)
    if not name:
        return None
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    onnx = VOICES_DIR / f"{name}.onnx"
    if onnx.exists() and (VOICES_DIR / f"{name}.onnx.json").exists():
        return onnx
    loc, rest = name.split("_", 1)[0], name
    parts = rest.split("-")
    region, speaker, quality = parts[0], parts[1], parts[2]
    base = f"https://huggingface.co/rhasspy/piper-voices/resolve/main/{loc}/{region}/{speaker}/{quality}/{name}.onnx"
    try:
        for url, path in [(base, onnx), (base + ".json", Path(str(onnx) + ".json"))]:
            urllib.request.urlretrieve(url, path)
        return onnx
    except Exception as e:  # noqa: BLE001
        log.warning("could not download voice %s: %s", name, e)
        return None


class PiperTTS(tts.TTS):
    """Piper kept in memory: ~80 ms per sentence on Apple Silicon. Picks the voice
    for the caller's language (auto-detected from what they said)."""

    def __init__(self, *, stt_: WhisperStreamingSTT | None = None, language: str = LANGUAGE):
        super().__init__(capabilities=tts.TTSCapabilities(streaming=False), sample_rate=22050, num_channels=1)
        from piper import PiperVoice  # noqa: PLC0415

        self._PiperVoice = PiperVoice
        self._stt = stt_
        self._language = language
        self._voices: dict[str, object] = {}
        self.voice_for("en" if language == "auto" else language)

    @property
    def model(self) -> str:
        return "piper"

    @property
    def provider(self) -> str:
        return "local"

    def voice_for(self, lang: str):
        lang = lang if lang in PIPER_VOICES else "en"
        if lang not in self._voices:
            path = ensure_piper_voice(lang) or ensure_piper_voice("en")
            self._voices[lang] = self._PiperVoice.load(str(path))
        return self._voices[lang]

    def current_language(self) -> str:
        if self._language != "auto":
            return self._language
        return self._stt.detected_language if self._stt else "en"

    def synthesize(self, text: str, *, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS):
        return _PiperChunked(tts_=self, input_text=text, conn_options=conn_options)


class _PiperChunked(tts.ChunkedStream):
    def __init__(self, *, tts_: PiperTTS, input_text: str, conn_options: APIConnectOptions):
        super().__init__(tts=tts_, input_text=input_text, conn_options=conn_options)
        self._p = tts_

    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        voice = self._p.voice_for(self._p.current_language())
        sr = voice.config.sample_rate
        output_emitter.initialize(request_id=utils.shortuuid(), sample_rate=sr, num_channels=1, mime_type="audio/pcm")
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[bytes | None] = asyncio.Queue()

        text = EMOJI.sub("", self._input_text).replace("*", "").strip()

        def work():
            if not text:
                loop.call_soon_threadsafe(queue.put_nowait, None)
                return
            for chunk in voice.synthesize(text):
                loop.call_soon_threadsafe(queue.put_nowait, chunk.audio_int16_bytes)
            loop.call_soon_threadsafe(queue.put_nowait, None)

        fut = loop.run_in_executor(None, work)  # noqa: F841 (awaited below)
        while (b := await queue.get()) is not None:
            output_emitter.push(b)
        await fut
        output_emitter.flush()


# ----------------------------------------------------------------------------- the call

def build_session(stt_: WhisperStreamingSTT, vad, model: str) -> AgentSession:
    llm = openai.LLM(
        base_url=os.environ.get("LL_LLM_BASE", "http://127.0.0.1:11434/v1"),
        api_key=os.environ.get("LL_LLM_KEY", "local"),
        model=model,
        temperature=0.5,
    )
    return AgentSession(
        stt=stt_,
        vad=vad,
        llm=llm,
        tts=PiperTTS(stt_=stt_),
        turn_handling={
            "turn_detection": MultilingualModel(),  # runs locally
            "endpointing": {"mode": "dynamic", "min_delay": 0.2, "max_delay": 1.5},
            # Think (and start speaking) before the turn is confirmed; dropped if the caller continues.
            "preemptive_generation": {"enabled": True, "preemptive_tts": True},
            # "vad" keeps barge-in local ("adaptive" calls LiveKit Cloud).
            "interruption": {"enabled": True, "mode": "vad", "min_duration": 0.4, "resume_false_interruption": True},
        },
    )


async def app_config(mode: str) -> dict:
    """Greeting, name and default language from the LocalAILine app (if it runs us).
    Also tells the app a call is starting, so it loads the model while we greet."""
    base = os.environ.get("LL_APP_URL")
    if not base:
        return {}
    try:
        async with aiohttp.ClientSession() as h:
            async with h.get(f"{base}/api/voice-config", params={"mode": mode}, headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"},
                             timeout=aiohttp.ClientTimeout(total=3)) as r:
                return await r.json(content_type=None)
    except Exception as e:  # noqa: BLE001
        log.warning("no app config: %s", e)
        return {}


async def entrypoint(ctx: JobContext) -> None:
    await ctx.connect()
    # Room names from the app: talk-<caller|owner>-<language>-<id>; phone calls: pstn-…
    parts = ctx.room.name.split("-")
    mode = parts[1] if len(parts) > 2 and parts[0] == "talk" and parts[1] in ("caller", "owner") else "caller"
    cfg = await app_config(mode)
    language = parts[2] if len(parts) > 3 and parts[0] == "talk" else cfg.get("language", LANGUAGE)
    vad = silero.VAD.load(min_silence_duration=0.35)
    stt_ = WhisperStreamingSTT(vad=silero.VAD.load(min_silence_duration=0.25), language=language)
    model = mode if os.environ.get("LL_APP_URL") else os.environ.get("LL_LLM_MODEL", "qwen3:4b-instruct")
    session = build_session(stt_, vad, model)
    session.tts._language = language  # noqa: SLF001
    lang = language if language != "auto" else "en"

    # Timing of each turn, for tuning (end-of-turn wait, first token, first audio).
    @session.on("metrics_collected")
    def _metrics(ev):  # noqa: ANN001
        m = ev.metrics
        kind = type(m).__name__
        if kind == "EOUMetrics":
            log.info("TIMING end_of_utterance_delay=%.0fms transcription_delay=%.0fms", m.end_of_utterance_delay * 1000, m.transcription_delay * 1000)
        elif kind == "LLMMetrics":
            log.info("TIMING llm_ttft=%.0fms", m.ttft * 1000)
        elif kind == "TTSMetrics":
            log.info("TIMING tts_ttfb=%.0fms", m.ttfb * 1000)

    await session.start(
        agent=Agent(instructions=os.environ.get("LL_INSTRUCTIONS", "You are Ava, a warm, brief phone assistant.")
                    + " This is a phone call: speak naturally in short sentences, no emojis, no lists or markdown."),
        room=ctx.room,
    )
    background = BackgroundAudioPlayer(thinking_sound=[AudioConfig(BuiltinAudioClip.KEYBOARD_TYPING, volume=0.45)])
    await background.start(room=ctx.room, agent_session=session)
    greeting = cfg.get("greeting") if mode == "caller" else f"Hi, it's {cfg.get('name', 'Ava')}. What can I do for you?"
    greeting = greeting or os.environ.get("LL_GREETING", "")
    if greeting:
        session.say(greeting, allow_interruptions=True)


def prewarm(proc) -> None:  # noqa: ANN001
    # Load models once per worker process (not per call).
    proc.userdata["vad"] = silero.VAD.load(min_silence_duration=0.35)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, prewarm_fnc=prewarm, agent_name=""))
