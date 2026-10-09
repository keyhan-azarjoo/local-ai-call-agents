"""LocalAILine voice engine: a LiveKit Agents worker that runs the live call.

Everything is local:
  hearing  — whisper.cpp `whisper-server` (Metal GPU), streamed: interim words while you speak
  thinking — the LocalAILine app (OpenAI-compatible endpoint), so documents, skills and tools apply;
             or Ollama directly when run on its own
  voice    — Kokoro (natural, human-sounding; spoken clause by clause so it starts fast) for
             English, Spanish, French, Italian, Portuguese, Chinese, Japanese, Hindi; Piper for the rest
  turns    — Silero VAD + LiveKit's multilingual end-of-turn model, preemptive generation,
             interruptions, a "thinking" sound and short spoken fillers

Configuration comes from environment variables (set by the app):
  LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
  LL_LLM_BASE (e.g. http://127.0.0.1:7420/v1), LL_LLM_KEY, LL_LLM_MODEL
  LL_WHISPER_URL (http://127.0.0.1:8910), LL_WHISPER_ACCURATE_URL (optional larger model),
  LL_LANGUAGE (auto | en | fa | …)
  LL_VOICES_DIR (folder with Piper .onnx voices), LL_KOKORO_DIR (kokoro-v1.0.onnx + voices-v1.0.bin),
  LL_GREETING, LL_INSTRUCTIONS
  LL_AGENT_NAME (optional: the name calls are dispatched to this worker by; empty: every new room)
  LL_PLUGIN (optional: a Python module that can change a few things per call; see "plugin" below)
"""
from __future__ import annotations

import asyncio
import io
import json
import logging
import importlib
import inspect
import os
import random
import sys
import threading
import time
import urllib.request
import wave
from dataclasses import dataclass
from pathlib import Path

import aiohttp
import httpx
import numpy as np
from livekit import api, rtc
from livekit.agents.voice import io as lk_io
from livekit.agents import (
    APIConnectOptions,
    Agent,
    AgentSession,
    JobContext,
    WorkerOptions,
    cli,
    room_io,
    stt,
    tts,
    utils,
)
from livekit.agents.types import DEFAULT_API_CONNECT_OPTIONS, NOT_GIVEN, NotGivenOr
from livekit.agents.voice.agent_session import SessionConnectOptions
from livekit.agents.voice.background_audio import AudioConfig, BackgroundAudioPlayer, BuiltinAudioClip
from livekit.plugins import openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

log = logging.getLogger("localailine.voice")

WHISPER_URL = os.environ.get("LL_WHISPER_URL", "http://127.0.0.1:8910")
# Hearing for several calls at once: a whisper server hears one request at a time, so the app
# runs a pool of them and each request goes to the next one (another if one is down).
HEARING = [u.strip().rstrip("/") for u in os.environ.get("LL_WHISPER_URLS", "").split(",") if u.strip()] or [WHISPER_URL.rstrip("/")]
_next_hearing = random.randrange(len(HEARING))
# Calls at the same time this computer is set up for (the app's setting).
LINES = max(1, int(os.environ.get("LL_LINES", "3") or 3))
# A larger hearing model for the final words in languages the fast one hears poorly (Persian, Arabic, …).
WHISPER_ACCURATE_URL = os.environ.get("LL_WHISPER_ACCURATE_URL", "")
EASY_LANGS = {"en", "es", "fr", "de", "it", "pt", "nl"}
LANGUAGE = os.environ.get("LL_LANGUAGE", "auto")
VOICES_DIR = Path(os.environ.get("LL_VOICES_DIR", Path.home() / "Library/Application Support/com.localailine.localailine/models/tts"))

# Sounds the app can choose for "thinking" and for the background.
SOUNDS = {
    "none": None,
    "keyboard": BuiltinAudioClip.KEYBOARD_TYPING,
    "keyboard2": BuiltinAudioClip.KEYBOARD_TYPING2,
    "office": BuiltinAudioClip.OFFICE_AMBIENCE,
    "hold": BuiltinAudioClip.HOLD_MUSIC,
    "city": BuiltinAudioClip.CITY_AMBIENCE,
    "forest": BuiltinAudioClip.FOREST_AMBIENCE,
    "room": BuiltinAudioClip.CROWDED_ROOM,
}

# Piper voices per language (downloaded on first use from the Piper voice library).
PIPER_VOICES = {
    "en": "en_GB-alba-medium",
    "fa": "fa_IR-gyro-medium",
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


KOKORO_DIR = Path(os.environ.get("LL_KOKORO_DIR", VOICES_DIR.parent / "kokoro"))
# Natural voices (Kokoro) per language: default voice and Kokoro's language code.
KOKORO_DEFAULT = {"en": "af_heart", "es": "ef_dora", "fr": "ff_siwis", "it": "if_sara", "pt": "pf_dora", "zh": "zf_xiaoxiao", "ja": "jf_alpha", "hi": "hf_alpha"}
KOKORO_LANG = {"a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr", "i": "it", "p": "pt-br", "z": "cmn", "j": "ja", "h": "hi"}
# Chosen in the app: language -> "kokoro:<voice>" or a Piper voice name.
VOICE_CHOICE: dict[str, str] = {}

# whisper.cpp reports languages by name; the rest of the engine uses codes.
WHISPER_LANGS = {
    "english": "en", "persian": "fa", "farsi": "fa", "arabic": "ar", "german": "de", "spanish": "es", "french": "fr",
    "italian": "it", "dutch": "nl", "portuguese": "pt", "russian": "ru", "turkish": "tr", "chinese": "zh", "japanese": "ja",
    "korean": "ko", "hindi": "hi", "urdu": "ur", "polish": "pl", "ukrainian": "uk", "swedish": "sv", "greek": "el",
    "hebrew": "he", "indonesian": "id", "vietnamese": "vi", "thai": "th", "romanian": "ro", "czech": "cs",
}

EMOJI = __import__("re").compile("[\U0001F000-\U0001FAFF\u2600-\u27BF\uFE0F]")

# ---------- the owner taking over a call (from the app's Calls page) ----------
# The app joins the call's room as "owner-\u2026", then sends {"takeover": true, "by": "<name>"} on this
# topic (and sets the attribute below): the AI stops at once, says nothing more and leaves; the
# caller stays on the line with the owner. "Hand back to AI" sends the agent back in with job
# metadata {"handback": true, "by": "<name>"}.
TAKEOVER_TOPIC = "localailine"
TAKEOVER_ATTRIBUTE = "localailine.takeover"
OWNER_PREFIX = "owner-"


def _owner_name(v: object) -> str:
    return v.strip()[:60] if isinstance(v, str) and v.strip() else "the owner"


def takeover_by(data: object, topic: str | None, identity: str | None = "") -> str | None:
    """Who is taking over, from a data message the owner's app sent; None if it isn't one."""
    if topic != TAKEOVER_TOPIC or not str(identity or "").startswith(OWNER_PREFIX):
        return None
    try:
        raw = bytes(data).decode("utf-8") if isinstance(data, (bytes, bytearray, memoryview)) else str(data)
        msg = json.loads(raw)
    except (ValueError, TypeError, UnicodeDecodeError):
        return None
    if not isinstance(msg, dict) or msg.get("takeover") is not True:
        return None
    return _owner_name(msg.get("by"))


def takeover_by_attributes(attributes: dict | None, identity: str | None = "") -> str | None:
    """Who is taking over, from the owner's participant attributes; None if nobody is."""
    if not str(identity or "").startswith(OWNER_PREFIX):
        return None
    v = (attributes or {}).get(TAKEOVER_ATTRIBUTE)
    if not isinstance(v, str) or v.strip().lower() in ("", "0", "false", "no"):
        return None
    return "the owner" if v.strip().lower() in ("1", "true", "yes") else _owner_name(v)


def handback_of(metadata: str | None) -> str | None:
    """The owner handing a call back to the AI (the job's metadata): who handed it back, or None."""
    try:
        m = json.loads(metadata or "")
    except (ValueError, TypeError):
        return None
    return _owner_name(m.get("by")) if isinstance(m, dict) and m.get("handback") is True else None


def is_app_listener(identity: str | None) -> bool:
    """The owner in the app (listening in or on the call): never the caller the AI talks to."""
    return str(identity or "").startswith((OWNER_PREFIX, "listen-"))


# ---------- who takes a call: the AI now, or the owner's devices ring first ----------
# The app's /api/voice-config can say, per phone call (the line's "who takes calls"):
#   "answer": {"off": true}                          not answered here: hang up without a word
#   "answer": {"wait": N, "then": "ai" | "message"}  the owner's devices ring first. The worker
#       stays silent (the caller hears ringing) until the app says who took the call
#       (/api/call-answer, held open until then), the owner takes over in the room, the caller
#       hangs up, or N seconds pass. Then the AI answers ("ai"), takes a message ("message"), or
#       leaves the call to the person who answered ("person", "owner").
# No "answer": the AI answers at once, as it always has.
ANSWER_GOES = ("ai", "message", "person", "owner", "gone")


def answer_plan(cfg: dict | None) -> dict | None:
    """The app's answer plan for this call, checked; None means answer now."""
    a = (cfg or {}).get("answer")
    if not isinstance(a, dict):
        return None
    if a.get("off") is True:
        return {"off": True}
    try:
        wait = float(a.get("wait") or 0)
    except (TypeError, ValueError):
        return None
    if wait <= 0:
        return None
    return {"wait": min(wait, 300.0), "then": a.get("then") if a.get("then") in ("ai", "message") else "ai"}


async def wait_to_answer(plan: dict, ask_app, taken: asyncio.Event, gone: asyncio.Event, who: dict | None = None,  # noqa: ANN001
                         grace: float = 10.0) -> dict:
    """Waits while the owner is rung: returns {"go": one of ANSWER_GOES, ...}.

    ask_app(): a coroutine asking the app (it answers once someone took the call or its time is up).
    taken: set when the owner takes the call over in the room (who["by"]: their name).
    gone: set when the caller hangs up. If the app can't be asked, the line's own time decides."""
    wait, then = plan["wait"], plan["then"]
    started = time.monotonic()

    async def from_app() -> dict:
        try:
            r = await ask_app()
        except Exception as e:  # noqa: BLE001
            log.warning("could not ask the app who takes the call: %s", e)
            r = None
        if isinstance(r, dict) and r.get("go") in ANSWER_GOES:
            return r
        await asyncio.sleep(max(0.0, wait - (time.monotonic() - started)))  # (the app couldn't say)
        return {"go": then}

    app = asyncio.ensure_future(from_app())
    t_taken = asyncio.ensure_future(taken.wait())
    t_gone = asyncio.ensure_future(gone.wait())
    try:
        await asyncio.wait({app, t_taken, t_gone}, timeout=wait + grace, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for t in (app, t_taken, t_gone):
            if not t.done():
                t.cancel()
    if gone.is_set():
        return {"go": "gone"}
    if taken.is_set():
        return {"go": "owner", "by": (who or {}).get("by") or "the owner"}
    if app.done() and not app.cancelled():
        return app.result()
    return {"go": then}


def ringback_cadence(number: str) -> tuple[tuple[float, ...], list[tuple[bool, float]]]:
    """The ringing tone a caller from [number] knows: its frequencies and (on, seconds) steps."""
    n = str(number or "")
    if n.startswith("+1"):
        return (440.0, 480.0), [(True, 2.0), (False, 4.0)]
    if n.startswith(("+44", "+353", "+61", "+64")):
        return (400.0, 450.0), [(True, 0.4), (False, 0.2), (True, 0.4), (False, 2.0)]
    return (425.0,), [(True, 1.0), (False, 4.0)]


# ---------- the app a call talks to, and a plugin ----------


@dataclass(frozen=True)
class Host:
    """The LocalAILine app a call talks to: its brain (an OpenAI-compatible endpoint), its voice
    settings and its call log. Here it comes from the environment the app sets."""

    url: str  # the app ("" when run on its own, straight on Ollama)
    token: str  # bearer token for the app
    llm_base: str  # the brain's OpenAI-compatible endpoint

    @classmethod
    def from_env(cls) -> Host:
        return cls(url=os.environ.get("LL_APP_URL", ""), token=os.environ.get("LL_LLM_KEY", ""),
                   llm_base=os.environ.get("LL_LLM_BASE", "http://127.0.0.1:11434/v1"))

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


# LL_PLUGIN=<module>: another package can change a few things per call without changing this
# file. Every function is optional; a missing one (or None returned) keeps what is here.
#   host_for_job(metadata: str) -> Host | None
#       the app this call talks to, from the job's metadata (a subclass of Host can carry more)
#   make_stt(host, language: str, vocabulary: str) -> stt.STT | None
#       the hearing for this call (else whisper.cpp)
#   make_tts(host, voice: str, language: str, stt) -> tts.TTS | None
#       the voice for this call (else Kokoro/Piper). voice = the app's voice for the agent ("" if
#       none); VOICE_CHOICE has the voices per language. The call sets `voice_override` on it when
#       passed to a teammate, and `_language`.
#   on_call_end(host, stats: dict) -> None (or a coroutine)
#       stats: room, phoneCall, answered, callSeconds, llmTurns, and this call's stt and tts
# The call also uses these on the hearing and voice when they have them: detected_language,
# recorder and record_agent_audio(pcm, sr) (recording), and played(frame) on the voice.
_plugin_module: object = None


def plugin():  # noqa: ANN201
    """The LL_PLUGIN module, or None."""
    global _plugin_module  # noqa: PLW0603
    name = os.environ.get("LL_PLUGIN", "").strip()
    if not name:
        return None
    if _plugin_module is None:
        # (Run as a script this file is __main__: the plugin's `import localailine_voice` gets this one.)
        sys.modules.setdefault("localailine_voice", sys.modules[__name__])
        _plugin_module = importlib.import_module(name)
    return _plugin_module


def plugin_call(fn: str, *args):  # noqa: ANN002, ANN201
    """The plugin's `fn(*args)`, or None when there is no plugin or it has no such function."""
    f = getattr(plugin(), fn, None)
    return f(*args) if callable(f) else None


def wav_bytes(pcm: np.ndarray, sr: int) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.astype(np.int16).tobytes())
    return buf.getvalue()


# ----------------------------------------------------------------------------- recording


class CallRecorder:
    """Both sides of a call on one timeline: the caller on the left, the assistant on the right
    (16 kHz stereo WAV). Kept as pieces and put together once, when the call ends."""

    SR = 16000

    def __init__(self) -> None:
        self.t0 = time.monotonic()
        self.pieces: dict[str, list[tuple[int, np.ndarray]]] = {"caller": [], "agent": []}

    def _at(self, t: float) -> int:
        return max(0, int((t - self.t0) * self.SR))

    def _resample(self, pcm: np.ndarray, sr: int) -> np.ndarray:
        if sr == self.SR or len(pcm) == 0:
            return pcm.astype(np.int16)
        x = np.arange(0, len(pcm), sr / self.SR)
        return np.interp(x, np.arange(len(pcm)), pcm.astype(np.float32)).astype(np.int16)

    def caller(self, pcm: np.ndarray, sr: int) -> None:
        self.pieces["caller"].append((self._at(time.monotonic() - len(pcm) / sr), self._resample(pcm, sr)))

    def agent(self, pcm: np.ndarray, sr: int, t: float) -> None:
        """The assistant's speech at the time it plays (it is made faster than it plays)."""
        self.pieces["agent"].append((self._at(t), self._resample(pcm, sr)))

    def cut_agent(self) -> None:
        """Interrupted: what was still queued was never heard."""
        now = self._at(time.monotonic())
        kept = []
        for at, pcm in self.pieces["agent"]:
            if at < now:
                kept.append((at, pcm[: now - at]))
        self.pieces["agent"] = kept

    def save(self, path: Path) -> Path | None:
        ends = [at + len(pcm) for side in self.pieces.values() for at, pcm in side]
        if not ends:
            return None
        n = max(ends)
        out = np.zeros((n, 2), np.int32)
        for ch, side in enumerate(("caller", "agent")):
            for at, pcm in self.pieces[side]:
                out[at : at + len(pcm), ch] += pcm[: max(0, n - at)]
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(self.SR)
            w.writeframes(np.clip(out, -32768, 32767).astype(np.int16).tobytes())
        return path


# ----------------------------------------------------------------------------- hearing

# Whisper's markers for non-speech ("[BLANK_AUDIO]", "[Music]", "(coughs)"): not words.
_NOT_SPEECH = __import__("re").compile(r"\[[^\]]*\]|\([^)]*\)|♪+")


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
        # Ava's own voice: what she is saying, whether she is speaking, and how loud the caller
        # usually is, so her voice leaking back into the microphone is not taken for the caller.
        self.agent_speaking = False
        self.agent_until = 0.0
        self.agent_said = ""
        self.user_level = 0.0
        # Loudness of what Ava plays, every 20 ms (time bin -> log energy), to recognise her echo.
        self.agent_env: dict[int, float] = {}
        # Names to expect (from the app), given to Whisper as a hint for English.
        self.vocabulary = ""
        # Recording this call (both sides), when the owner turned it on.
        self.recorder: CallRecorder | None = None
        # Recognise Ava's own voice coming back (speakers in the room); off on phone calls.
        self.echo_check = True
        self.play_end = 0.0

    def record_agent_audio(self, pcm: np.ndarray, sr: int) -> None:
        """Ava's own output, as it goes out."""
        n = max(1, int(sr * 0.02))
        # Speech is made faster than it plays: put it on a playback timeline (after what's queued).
        t0 = max(time.monotonic(), self.play_end)
        self.play_end = t0 + len(pcm) / sr
        if self.recorder:
            self.recorder.agent(pcm, sr, t0)
        b0 = int(t0 / 0.02)
        for i in range(0, len(pcm) - n + 1, n):
            seg = pcm[i : i + n].astype(np.float32)
            self.agent_env[b0 + i // n] = float(np.log10(np.sqrt(np.mean(seg * seg)) + 1.0))
        if len(self.agent_env) > 6000:
            for k in sorted(self.agent_env)[:2000]:
                del self.agent_env[k]

    def echo_likeness(self, pcm: np.ndarray, t_end: float) -> float:
        """How closely this sound follows Ava's own output (0..1), allowing for the delay
        between playing it and hearing it back (up to ~1.5 s)."""
        n = 320  # 20 ms at 16 kHz
        bins = len(pcm) // n
        if bins < 10 or not self.agent_env:
            return 0.0
        mic = np.array([np.log10(np.sqrt(np.mean(pcm[i * n : (i + 1) * n].astype(np.float32) ** 2)) + 1.0) for i in range(bins)])
        if mic.std() < 1e-3:
            return 0.0
        end_bin = int(t_end / 0.02)
        first = end_bin - bins + 1
        best = 0.0
        for lag in range(-30, 61):  # the segment end is only roughly known
            keys = [first + i - lag for i in range(bins)]
            # Only where Ava was actually playing for most of this sound.
            if sum(k in self.agent_env for k in keys) < bins * 0.7:
                continue
            ref = np.array([self.agent_env.get(k, 0.0) for k in keys])
            if ref.std() < 1e-3:
                continue
            c = float(np.corrcoef(mic, ref)[0, 1])
            best = max(best, c)
        return best

    def heard_agent(self, text: str) -> None:
        self.agent_said = (self.agent_said + " " + text)[-800:]

    def is_echo(self, pcm: np.ndarray, text: str, t_end: float | None = None) -> bool:
        """True when this sound is Ava's own voice coming back: it follows what she is playing,
        or (while she speaks) is much quieter than the caller usually is. Words aren't compared:
        echoes are mis-heard, and callers share common words with her."""
        if not self.echo_check:
            return False
        like = self.echo_likeness(pcm, t_end or time.monotonic())
        log.debug("own-voice check: like=%.2f text=%s", like, text[:40])
        # Follows what Ava just played (only possible if she played something then): her echo.
        if like >= 0.8:  # her echo scores ~0.9; two different voices ~0.6-0.7
            return True
        if not (self.agent_speaking or time.monotonic() < self.agent_until):
            return False
        if like >= 0.65:  # while she speaks, a looser match still means it's her
            return True
        rms = float(np.sqrt(np.mean(pcm.astype(np.float32) ** 2))) if len(pcm) else 0.0
        # Much quieter than the caller usually is, while she speaks: what's left of her echo.
        return bool(self.user_level) and rms < self.user_level * 0.35

    def learn_level(self, pcm: np.ndarray) -> None:
        if self.agent_speaking or time.monotonic() < self.agent_until or not len(pcm):
            return
        rms = float(np.sqrt(np.mean(pcm.astype(np.float32) ** 2)))
        self.user_level = rms if not self.user_level else 0.7 * self.user_level + 0.3 * rms

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

    def needs_accurate(self, pcm: np.ndarray, sr: int) -> bool:
        lang = self._language if self._language != "auto" else self.detected_language
        return bool(WHISPER_ACCURATE_URL) and lang not in EASY_LANGS and len(pcm) < sr * 14

    async def _accurate(self, pcm: np.ndarray, sr: int) -> str:
        """The larger model, told the language (no guessing). Empty if unavailable."""
        lang = self._language if self._language != "auto" else self.detected_language
        form = aiohttp.FormData()
        form.add_field("file", wav_bytes(pcm, sr), filename="a.wav", content_type="audio/wav")
        form.add_field("response_format", "json")
        form.add_field("language", lang)
        form.add_field("temperature", "0")
        try:
            async with self.http().post(WHISPER_ACCURATE_URL.rstrip("/") + "/inference", data=form, timeout=aiohttp.ClientTimeout(total=8)) as r:
                return _NOT_SPEECH.sub("", (await r.json(content_type=None)).get("text") or "").strip()
        except Exception as e:  # noqa: BLE001
            log.warning("accurate hearing failed, using the fast one: %s", e)
            return ""

    async def transcribe(self, pcm: np.ndarray, sr: int, *, final: bool = False) -> tuple[str, str]:
        # Final words in a harder language (Persian, Arabic, …) come from the larger model.
        tried = final and self.needs_accurate(pcm, sr)
        if tried and (text := await self._accurate(pcm, sr)):
            return text, self.detected_language if self._language == "auto" else self._language
        auto = self._language == "auto"
        j = await self._whisper(pcm, sr, "auto" if auto else self._language)
        text = _NOT_SPEECH.sub("", j.get("text") or "").strip()
        if auto:
            lang = str(j.get("language") or "").lower()
            lang = WHISPER_LANGS.get(lang, lang)
            prob = float(j.get("detected_language_probability") or 0)
            # Switch language only when Whisper is sure ("Hi there" can look Japanese).
            sure = prob >= 0.8 or (prob >= 0.5 and len(pcm) >= sr * 1.5)
            if lang and len(lang) <= 3 and sure:
                self.detected_language = lang
            elif lang != self.detected_language:
                # Not sure: hear it again in the language of the conversation.
                if final and self.needs_accurate(pcm, sr) and (better := await self._accurate(pcm, sr)):
                    return better, self.detected_language
                text = _NOT_SPEECH.sub("", (await self._whisper(pcm, sr, self.detected_language)).get("text") or "").strip()
            # Just found out it's a harder language: hear it again with the larger model.
            if final and not tried and self.needs_accurate(pcm, sr) and (better := await self._accurate(pcm, sr)):
                return better, self.detected_language
        return text, self.detected_language

    async def _whisper(self, pcm: np.ndarray, sr: int, language: str) -> dict:
        def form() -> aiohttp.FormData:  # a fresh one per try (a sent form can't be sent again)
            f = aiohttp.FormData()
            if self.vocabulary and language in ("en", "auto") and self.detected_language == "en":
                f.add_field("prompt", self.vocabulary)
            f.add_field("file", audio, filename="a.wav", content_type="audio/wav")
            f.add_field("response_format", "verbose_json")
            f.add_field("language", language)
            f.add_field("temperature", "0")
            return f

        global _next_hearing  # noqa: PLW0603
        audio = wav_bytes(pcm, sr)
        urls = HEARING if self._url == WHISPER_URL.rstrip("/") + "/inference" else [self._url[: -len("/inference")]]
        start, _next_hearing = _next_hearing, _next_hearing + 1
        for i in range(len(urls)):
            try:
                async with self.http().post(urls[(start + i) % len(urls)] + "/inference", data=form(), timeout=aiohttp.ClientTimeout(total=15)) as r:
                    return await r.json(content_type=None)
            except aiohttp.ClientConnectionError:
                if i == len(urls) - 1:
                    raise
        return {}

    async def _recognize_impl(self, buffer, *, language: NotGivenOr[str] = NOT_GIVEN, conn_options: APIConnectOptions):
        frame = rtc.combine_audio_frames(buffer)
        pcm = np.frombuffer(frame.data, dtype=np.int16)
        text, lang = await self.transcribe(pcm, frame.sample_rate, final=True)
        return stt.SpeechEvent(type=stt.SpeechEventType.FINAL_TRANSCRIPT, alternatives=[stt.SpeechData(language=lang, text=tidy_heard(text))])

    def stream(self, *, language: NotGivenOr[str] = NOT_GIVEN, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS):
        return _WhisperStream(stt_=self, conn_options=conn_options)

    async def aclose(self) -> None:
        if self._http:
            await self._http.close()


def _grams(t: str) -> set[str]:
    t = "".join(ch for ch in t.lower() if ch.isalnum() or ch == " ")
    t = " ".join(t.split())
    return {t[i : i + 3] for i in range(max(0, len(t) - 2))}


def _overlap(text: str, ref: str) -> float:
    """How much of `text` appears in `ref` (character 3-grams), 0..1."""
    a = _grams(text)
    return len(a & _grams(ref)) / len(a) if a else 0.0


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
                    if speaking and text and self._s.is_echo(pcm, text):
                        text = ""  # Ava hearing herself: not the caller
                    if speaking and text and text != last_text:
                        last_text = text
                        self._event_ch.send_nowait(stt.SpeechEvent(
                            type=stt.SpeechEventType.INTERIM_TRANSCRIPT,
                            alternatives=[stt.SpeechData(language=lang, text=tidy_heard(text))]))
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
                    if last_text and covered >= len(pcm) - 16000 * 0.35 and time.monotonic() - made < 0.8 and not self._s.needs_accurate(pcm, 16000):
                        text = last_text
                    elif len(pcm) > 16000 * 0.2:
                        try:
                            text, lang = await self._s.transcribe(pcm, 16000, final=True)
                        except Exception as e:  # noqa: BLE001
                            log.warning("final transcription failed: %s", e)
                    if text and self._s.is_echo(pcm, text):
                        log.info("ignored own voice (%.1f s, like %.2f, env %d..%d, now %d): %s", len(pcm) / 16000, self._s.echo_likeness(pcm, time.monotonic()),
                                 min(self._s.agent_env or [0]), max(self._s.agent_env or [0]), int(time.monotonic() / 0.02), text[:80])
                        text = ""
                    elif text:
                        self._s.learn_level(pcm)
                    self._event_ch.send_nowait(stt.SpeechEvent(
                        type=stt.SpeechEventType.FINAL_TRANSCRIPT,
                        alternatives=[stt.SpeechData(language=lang, text=tidy_heard(text))]))
                    self._event_ch.send_nowait(stt.SpeechEvent(type=stt.SpeechEventType.END_OF_SPEECH))

        vad_task = asyncio.create_task(read_vad())
        try:
            async for item in self._input_ch:
                if isinstance(item, self._FlushSentinel):
                    vad_stream.flush()
                    continue
                vad_stream.push_frame(item)
                if self._s.recorder:
                    self._s.recorder.caller(np.frombuffer(item.data, dtype=np.int16), item.sample_rate)
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
    if name == "fa_IR-mana-medium":  # a community Persian voice
        base = "https://huggingface.co/MahtaFetrat/Mana-Persian-Piper/resolve/main/fa_IR-mana-medium.onnx"
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
        lang = "en" if language == "auto" else language
        if not self.kokoro_voice(lang):
            self.voice_for(lang)

    @property
    def model(self) -> str:
        return "piper"

    @property
    def provider(self) -> str:
        return "local"

    # The voice of the agent on the call now (set when the call is passed to a teammate).
    voice_override: str | None = None

    def _override_for(self, lang: str) -> str | None:
        v = self.voice_override
        return v if v and voice_language(v) == lang else None

    def voice_for(self, lang: str):
        lang = lang if lang in PIPER_VOICES else "en"
        choice = self._override_for(lang) or VOICE_CHOICE.get(lang)
        name = choice if choice and not choice.startswith("kokoro:") else PIPER_VOICES[lang]
        if name not in self._voices:
            saved = PIPER_VOICES[lang]
            PIPER_VOICES[lang] = name
            path = ensure_piper_voice(lang) or ensure_piper_voice("en")
            PIPER_VOICES[lang] = saved
            self._voices[name] = self._PiperVoice.load(str(path))
        return self._voices[name]

    def current_language(self) -> str:
        if self._language != "auto":
            return self._language
        return self._stt.detected_language if self._stt else "en"

    def kokoro_voice(self, lang: str) -> str | None:
        """The natural (Kokoro) voice for this language, if there is one and it's chosen."""
        choice = self._override_for(lang) or VOICE_CHOICE.get(lang)
        if choice and not choice.startswith("kokoro:"):
            return None  # a Piper voice was chosen
        if not (KOKORO_DIR / "kokoro-v1.0.onnx").exists():
            return None
        return choice[7:] if choice else KOKORO_DEFAULT.get(lang)

    def kokoro(self):
        return load_kokoro()

    def synthesize(self, text: str, *, conn_options: APIConnectOptions = DEFAULT_API_CONNECT_OPTIONS):
        if self.kokoro_voice(self.current_language()):
            return _KokoroChunked(tts_=self, input_text=text, conn_options=conn_options)
        return _PiperChunked(tts_=self, input_text=text, conn_options=conn_options)


class _PiperChunked(tts.ChunkedStream):
    def __init__(self, *, tts_: PiperTTS, input_text: str, conn_options: APIConnectOptions):
        super().__init__(tts=tts_, input_text=input_text, conn_options=conn_options)
        self._p = tts_

    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        # Loading (or, the first time, downloading) a voice must not block the call.
        voice = await asyncio.get_running_loop().run_in_executor(None, self._p.voice_for, self._p.current_language())
        sr = voice.config.sample_rate
        output_emitter.initialize(request_id=utils.shortuuid(), sample_rate=sr, num_channels=1, mime_type="audio/pcm")
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[bytes | None] = asyncio.Queue()

        text = EMOJI.sub("", self._input_text).replace("*", "").strip()
        if self._p._stt:
            self._p._stt.heard_agent(text)
        text = persian_speakable(text) if self._p.current_language() == "fa" else speakable(text)

        def work():
            if not text:
                loop.call_soon_threadsafe(queue.put_nowait, None)
                return
            for chunk in voice.synthesize(text):
                loop.call_soon_threadsafe(queue.put_nowait, chunk.audio_int16_bytes)
            loop.call_soon_threadsafe(queue.put_nowait, None)

        fut = loop.run_in_executor(None, work)  # noqa: F841 (awaited below)
        while (b := await queue.get()) is not None:
            if self._p._stt:
                self._p._stt.record_agent_audio(np.frombuffer(b, dtype=np.int16), sr)
            output_emitter.push(b)
        await fut
        output_emitter.flush()


# Times as speech recognition writes them: "7, 30pm" / "7 30 p.m." / "7.30pm" -> "7:30 pm" (else the
# model takes "7, 30pm" for 7 pm).
_HEARD_TIME = __import__("re").compile(r"\b(1[0-2]|0?[1-9])(?:,\s*|\s+|\.)([0-5]\d)\s*([ap])\.?\s?m\b\.?", __import__("re").IGNORECASE)


# UK postcodes as heard: "BS 14 DJ" (said "B S one, four D J") -> "BS1 4DJ".
_HEARD_POSTCODE = __import__("re").compile(r"\b([A-Z]{1,2})\s?(\d{1,2}[A-Z]?)\s?(\d)\s?([A-Z]{2})\b")


def tidy_heard(text: str) -> str:
    if not text:
        return text
    text = _HEARD_TIME.sub(lambda m: f"{m[1]}:{m[2]} {m[3].lower()}m", text)
    return _HEARD_POSTCODE.sub(lambda m: f"{m[1]}{m[2]} {m[3]}{m[4]}", text)


_CLAUSE = __import__("re").compile(r"(?<=[,;:.!?…—])\s+")
_MONEY = __import__("re").compile(r"([£$€])(\d+)(?:\.(\d{2}))?")
_MONEY_NAMES = {"£": ("pounds", "p"), "$": ("dollars", "cents"), "€": ("euros", "cents")}


def speakable(text: str) -> str:
    """Prices and symbols the way a person says them ("£3.95" -> "3 pounds 95")."""
    def money(m):  # noqa: ANN001, ANN202
        unit, small = _MONEY_NAMES[m[1]]
        if m[3] and m[3] != "00":
            return f"{m[2]} {unit} {int(m[3])}" if m[1] == "£" else f"{m[2]} {unit} and {int(m[3])} {small}"
        return f"{m[2]} {unit}"
    text = _MONEY.sub(money, text).replace(" – ", ", ").replace(" — ", ", ")
    text = _SPOKEN_TIME.sub(spoken_time, text)
    text = _PHONE.sub(phone_digits, text)
    text = _SAY_AS_RE.sub(lambda m: _SAY_AS[m[0]], text)
    return __import__("re").sub(r"\s*&\s*", " and ", text)


# Times as people say them: "7:00pm" -> "7 pm" (was read "7, 0, 0 p m"), "19:30" -> "7:30 pm".
_SPOKEN_TIME = __import__("re").compile(r"(?<![\d£$€.:])\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:\s*([ap])\.?\s?m\b)?(?![\d:])", __import__("re").I)


def spoken_time(m) -> str:  # noqa: ANN001
    h, mins, half = int(m[1]), m[2], (m[3] or "").lower()
    if not half and h <= 12 and not m[1].startswith("0"):
        return m[0] if mins != "00" else f"{h} o'clock"
    if h > 12:
        h, half = h - 12, "p"
    elif h == 0:
        h, half = 12, "a"
    elif not half:
        half = "a" if h < 12 else "p"
    return f"{h}{'' if mins == '00' else ':' + mins} {half}m"


# Names the English voices say wrongly, spelled as they sound ("Giulia" came out as "Jellelia").
_SAY_AS = {"Giulia": "Julia"}  # (checked by voicing each and hearing it back: the others come out right)
_SAY_AS_RE = __import__("re").compile(r"\b(" + "|".join(_SAY_AS) + r")\b")


# A phone number (7+ digits, maybe spaced): said digit by digit in its groups ("07700 900123" ->
# "0 7 7 0 0, 9 0 0, 1 2 3"); as a number it comes out as "nine hundred thousand…" and is misheard.
_PHONE = __import__("re").compile(r"(?<![\d.,£$€])\+?\d(?:[\d -]{5,}\d)(?![\d.,]\d)")


def phone_digits(m) -> str:  # noqa: ANN001
    raw = m[0]
    if sum(c.isdigit() for c in raw) < 7:
        return raw
    groups = [g for g in __import__("re").split(r"[ -]+", raw.lstrip("+")) if g]
    if len(groups) == 1 and raw.startswith("+44") and len(groups[0]) == 12:  # +44 7700 900 258
        g = groups[0]
        groups = ["44", g[2:6], g[6:9], g[9:]]
    elif len(groups) == 1 and groups[0].startswith("0") and len(groups[0]) == 11:  # 07700 900 123
        g = groups[0]
        groups = [g[:5], g[5:8], g[8:]]
    # Long groups in threes ("900123" -> "900, 123"): easier to say and to hear.
    groups = [x for g in groups for x in ([g] if len(g) <= 5 or g.startswith("0") else [g[i:i + 3] for i in range(0, len(g), 3)])]
    return ("plus " if raw.startswith("+") else "") + ", ".join(" ".join(g) for g in groups if g)


_FA_ONES = ["صفر", "یک", "دو", "سه", "چهار", "پنج", "شش", "هفت", "هشت", "نه"]
_FA_TEENS = ["ده", "یازده", "دوازده", "سیزده", "چهارده", "پانزده", "شانزده", "هفده", "هجده", "نوزده"]
_FA_TENS = ["", "", "بیست", "سی", "چهل", "پنجاه", "شصت", "هفتاد", "هشتاد", "نود"]
_FA_HUNDREDS = ["", "صد", "دویست", "سیصد", "چهارصد", "پانصد", "ششصد", "هفتصد", "هشتصد", "نهصد"]
_FA_LETTERS = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "اِی بی سی دی ای اِف جی اِیچ آی جِی کِی اِل اِم اِن او پی کیو آر اِس تی یو وی دبلیو اِکس وای زِد".split()))
_FA_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_FA_MONEY = {"£": ("پوند", "پنس"), "$": ("دلار", "سنت"), "€": ("یورو", "سنت")}
_re = __import__("re")


def fa_number(n: int) -> str:
    """A number in Persian words (Persian voices garble digits)."""
    if n < 10:
        return _FA_ONES[n]
    parts: list[str] = []
    for size, name in ((10**9, "میلیارد"), (10**6, "میلیون"), (1000, "هزار")):
        if n >= size:
            parts.append(f"{fa_number(n // size)} {name}" if n // size > 1 or size > 1000 else name)
            n %= size
    if n >= 100:
        parts.append(_FA_HUNDREDS[n // 100])
        n %= 100
    if 10 <= n < 20:
        parts.append(_FA_TEENS[n - 10])
    else:
        if n >= 20:
            parts.append(_FA_TENS[n // 10])
        if n % 10:
            parts.append(_FA_ONES[n % 10])
    return " و ".join(parts)


def persian_speakable(text: str) -> str:
    """Persian text the voice can say: prices, numbers, times and Latin letters as Persian words."""
    text = text.translate(_FA_DIGITS)

    def money(m):  # noqa: ANN001, ANN202
        big, small = _FA_MONEY[m[1]]
        out = f"{fa_number(int(m[2]))} {big}"
        return out + (f" و {fa_number(int(m[3]))} {small}" if m[3] and int(m[3]) else "")

    text = _MONEY.sub(money, text)
    # Codes like "RV3": letters by their names, then the number.
    text = _re.sub(r"(?<![A-Za-z])([A-Z]{1,4})(?![a-z])", lambda m: " " + " ".join(_FA_LETTERS[c] for c in m[1]) + " ", text)
    text = _re.sub(r"\b(\d{1,2}):(\d{2})\b", lambda m: fa_number(int(m[1])) + ("" if m[2] == "00" else f" و {fa_number(int(m[2]))} دقیقه"), text)
    text = _re.sub(r"(\d+)\.(\d+)", lambda m: f"{fa_number(int(m[1]))} ممیز {fa_number(int(m[2]))}", text)
    text = _re.sub(r"\d+", lambda m: fa_number(int(m[0])) if len(m[0]) <= 12 else " ".join(_FA_ONES[int(d)] for d in m[0]), text)
    text = _re.sub(r"\s*&\s*", " و ", text).replace(" – ", "، ").replace(" — ", "، ")
    return _re.sub(r" {2,}", " ", text).strip()


def clauses(text: str) -> list[str]:
    """Short pieces to speak one after another: the first starts quickly ("Okay," alone),
    the rest flow on while it plays."""
    out: list[str] = []
    for part in _CLAUSE.split(text):
        if len(out) > 1 and (len(out[-1]) < 14 or len(part) < 6):
            out[-1] += " " + part
        else:
            out.append(part)
    # A long first piece: start with its first few words.
    if out and len(out[0].split()) > 7:
        w = out[0].split()
        out[:1] = [" ".join(w[:4]), " ".join(w[4:])]
    return [p for p in out if p.strip()]


# The app's own quick "let me check" lines: they don't count as the answer having started.
_FILLER = _re.compile(r"^(sure, let me sort that out|okay, on it|right, let me do that|hmm, let me see|let me check that for you|okay, one sec, let me look|one moment, let me check that)\.?$", _re.IGNORECASE)


def _early_piece(buf: str) -> int | None:
    """Where the answer's first words can be spoken already (the model is still writing the rest):
    at the first comma/colon after 3+ words, or after 6 words when 9 have come in. None = wait."""
    words = buf.split()
    if len(words) < 4:
        return None
    m = _re.search(r"[,;:—–]\s", buf)
    if m and len(buf[: m.end()].split()) >= 3 and not _FILLER.match(buf[: m.end()].strip().rstrip(",;:—–").strip() + "."):
        return m.end()
    if len(words) >= 9:
        six = _re.match(r"\s*(?:\S+\s+){6}", buf)
        return six.end() if six else None
    return None


def hold_music(stt_=None, seconds: float | None = None):  # noqa: ANN001, ANN201
    """A few seconds of soft hold music (a gentle arpeggio, made here: no files needed), as frames."""
    sr = 24000
    seconds = seconds or random.uniform(2.0, 4.0)
    notes = [261.63, 329.63, 392.00, 493.88, 523.25, 392.00, 329.63, 293.66]  # C E G B C G E D
    step = 0.32
    n = int(sr * seconds)
    t = np.arange(n) / sr
    out = np.zeros(n, np.float32)
    for i in range(int(seconds / step) + 1):
        f = notes[i % len(notes)]
        start = int(i * step * sr)
        if start >= n:
            break
        length = min(n - start, int(sr * 1.1))
        tt = t[:length]
        env = np.exp(-3.2 * tt) * np.minimum(1.0, tt / 0.01)  # soft pluck: quick rise, slow fade
        out[start : start + length] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)) * env * 0.12
    fade = int(sr * 0.25)
    out[-fade:] *= np.linspace(1.0, 0.0, fade)
    pcm = (np.clip(out, -1, 1) * 32767).astype(np.int16)
    if stt_ is not None:
        stt_.record_agent_audio(pcm, sr)
    for i in range(0, n, 2400):
        chunk = pcm[i : i + 2400]
        yield rtc.AudioFrame(data=chunk.tobytes(), sample_rate=sr, num_channels=1, samples_per_channel=len(chunk))


# Kokoro's speaking speed: a touch quicker than its default sounds more like someone on the phone.
SPEED = float(os.environ.get("LL_TTS_SPEED", "1.05"))


def sentences(text: str) -> list[str]:
    """Whole sentences, each spoken in one go (cutting at every comma resets the intonation and sounds
    robotic). Only the first may be shortened, so the answer starts quickly; very long ones are split
    at a comma."""
    out: list[str] = []
    for s in _re_sentence.split(text):
        s = s.strip()
        if not s:
            continue
        if len(s) > 220:  # one breath at most: split at a comma near the middle
            cut = s.rfind(", ", 0, len(s) // 2 + 60)
            if cut > 40:
                out += [s[: cut + 1], s[cut + 2 :]]
                continue
        out.append(s)
    # The first piece: a quick start ("Okay," / "Sure,") is said on its own, the rest flows on.
    if out:
        m = _re_opener.match(out[0])
        if m and len(out[0]) > len(m[0]) + 8:
            out[:1] = [m[0].strip(), out[0][m.end() :].strip()]
    return [p for p in out if p]


_re_sentence = __import__("re").compile(r"(?<=[.!?؟。…])\s+")
_re_opener = __import__("re").compile(r"^(okay|ok|sure|right|hmm|great|perfect|lovely|of course|no problem|thanks|thank you)[,!.]?\s+", __import__("re").IGNORECASE)


def smooth(pcm: np.ndarray, sr: int) -> np.ndarray:
    """Trims the silence Kokoro leaves around a piece (it adds up between pieces) and fades the
    edges in and out over 6 ms, so pieces join without clicks."""
    if len(pcm) == 0:
        return pcm
    loud = np.nonzero(np.abs(pcm) > 300)[0]
    if len(loud):
        start = max(0, loud[0] - int(sr * 0.03))
        end = min(len(pcm), loud[-1] + int(sr * 0.06))
        pcm = pcm[start:end]
    n = min(len(pcm) // 2, int(sr * 0.006))
    if n > 1:
        f = pcm.astype(np.float32)
        ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
        f[:n] *= ramp
        f[-n:] *= ramp[::-1]
        pcm = f.astype(np.int16)
    return pcm


# Speech already made, by (voice, text): fillers and greetings come back instantly.
_SPOKEN: dict[tuple[str, str], np.ndarray] = {}
COMMON_PHRASES = ["Hmm,", "Okay,", "Sure,", "Right,", "let me see.", "Let me check that for you.", "one sec, let me look.",
                  "let me sort that out.", "on it.", "let me do that.", "One moment,", "let me check that.", "Hmm, let me see."]


class _KokoroChunked(tts.ChunkedStream):
    """Kokoro: natural, human-sounding speech. Each clause is synthesised while the
    previous one plays (Kokoro runs ~4x faster than real time on Apple Silicon)."""

    def __init__(self, *, tts_: PiperTTS, input_text: str, conn_options: APIConnectOptions):
        super().__init__(tts=tts_, input_text=input_text, conn_options=conn_options)
        self._p = tts_

    async def _run(self, output_emitter: tts.AudioEmitter) -> None:
        lang = self._p.current_language()
        voice = self._p.kokoro_voice(lang) or "af_heart"
        output_emitter.initialize(request_id=utils.shortuuid(), sample_rate=24000, num_channels=1, mime_type="audio/pcm")
        text = speakable(EMOJI.sub("", self._input_text).replace("*", "")).strip()
        if self._p._stt:
            self._p._stt.heard_agent(self._input_text)
        if not text:
            output_emitter.flush()
            return
        loop = asyncio.get_running_loop()
        k = await loop.run_in_executor(None, self._p.kokoro)
        code = KOKORO_LANG.get(voice[0], "en-us")
        pieces = sentences(text)
        for i, piece in enumerate(pieces):
            pcm = _SPOKEN.get((voice, piece))
            if pcm is None:
                samples, _ = await loop.run_in_executor(None, lambda p=piece: k.create(p, voice=voice, speed=SPEED, lang=code))
                pcm = smooth((np.clip(samples, -1, 1) * 32767).astype(np.int16), 24000)
                if len(piece) < 40:
                    _SPOKEN[(voice, piece)] = pcm
            # A natural pause after it: longer after a sentence, short after a clause.
            gap = 0 if i == len(pieces) - 1 else int(24000 * (0.22 if piece.rstrip()[-1:] in ".!?؟。…" else 0.09))
            pcm = np.concatenate([pcm, np.zeros(gap, np.int16)]) if gap else pcm
            if self._p._stt:
                self._p._stt.record_agent_audio(pcm, 24000)
            output_emitter.push(pcm.tobytes())
        output_emitter.flush()


# ----------------------------------------------------------------------------- the call

def voice_language(v: str) -> str:
    """The language a voice speaks ("kokoro:bf_emma" → en, "fa_IR-gyro-medium" → fa)."""
    if v.startswith("kokoro:"):
        return {"a": "en", "b": "en", "e": "es", "f": "fr", "i": "it", "p": "pt", "z": "zh", "j": "ja", "h": "hi"}.get(v[7:8], "en")
    return v.split("_")[0]


class AppLLM(openai.LLM):
    """The LocalAILine app as the brain. The model name carries the call mode and the
    language the caller is speaking right now ("caller:fa"), so the app answers in it."""

    def __init__(self, *, mode: str, stt_: WhisperStreamingSTT, room: str = "", **kw):  # noqa: ANN003
        super().__init__(model=mode, **kw)
        self._mode, self._stt, self._room = mode, stt_, room

    def chat(self, **kw):  # noqa: ANN003, ANN201
        # mode:language:room — the room tells the app which call (and which agent is on it).
        self._opts.model = f"{self._mode}:{getattr(self._stt, 'detected_language', 'en')}:{self._room}"
        return super().chat(**kw)


_HANGUP = _re.compile(r"\s*\[hangup\]\s*", _re.IGNORECASE)
_FAREWELL = _re.compile(r"\b(bye|goodbye|good-bye|take care|have a (great|good|nice|lovely)|see you|thanks for calling|thank you for calling)\b|خداحافظ|با تشکر از تماس|وداعا|adiós|au revoir|tschüss|auf wiedersehen|ciao|arrivederci|ho[sş][cç]a kal|do widzenia|مع السلامة", _re.IGNORECASE)
_CONNECT = _re.compile(r"\s*\[connect:([^\]]*)\]\s*", _re.IGNORECASE)
_VOICE = _re.compile(r"\s*\[voice:([^\]]*)\]\s*", _re.IGNORECASE)
_SENTENCE_END = _re.compile(r"[.!?؟。…](?=\s)")


class Ava(Agent):
    """Speaks each sentence the moment it is complete. (LiveKit's sentence splitter waits for
    the next sentence to begin, so "Let me check." would wait for the whole answer.)"""

    # Set by the call: plays/stops the "thinking" sound while the rest of the answer is on its way.
    waiting = None
    # The model ends its last reply with [hangup] when the call is over.
    hangup_requested = False
    # Set when the call is being passed to a real person (agent id).
    connect_requested: str | None = None

    def _strip_hangup(self, t: str, switch_voice: bool = False) -> str:
        if "[hangup]" in t.lower():
            # Only a real goodbye ends the call (the model sometimes adds the marker too early): the
            # goodbye must be at the end ("Hi, thanks for calling! … Would you like to order?" is not one),
            # and never after a question.
            before = t[: t.lower().find("[hangup]")]
            self.hangup_requested = bool(_FAREWELL.search(before[-90:])) and not before.rstrip().endswith("?")
            t = _HANGUP.sub("", t)
        c = _CONNECT.search(t)
        if c:
            self.connect_requested = c.group(1)
            t = _CONNECT.sub(" ", t)
        m = _VOICE.search(t)
        if m:
            # The call was passed to a teammate: their voice from here on ("[voice:kokoro:am_michael|Sam]").
            if switch_voice:
                v = m.group(1).split("|")[0].strip()
                self.session.tts.voice_override = None if v in ("", "default", "null") else v
            t = _VOICE.sub(" ", t)
        return t

    async def transcription_node(self, text, model_settings):  # noqa: ANN001, ANN201
        async for t in text:
            yield self._strip_hangup(t) if "[" in t else t

    async def tts_node(self, text, model_settings):  # noqa: ANN001, ANN201
        tts_ = self.session.tts
        # (The local voices note what they play themselves; a plugin's voice is told frame by frame.)
        played = getattr(tts_, "played", None)
        spoke = False
        queue: asyncio.Queue[str | None] = asyncio.Queue()

        async def read() -> None:
            async for t in text:
                await queue.put(t)
            await queue.put(None)

        reader = asyncio.create_task(read())
        buf, ended = "", False
        said_enough = False
        try:
            while not ended or buf.strip():
                piece = None
                m = None
                for m in _SENTENCE_END.finditer(buf):
                    pass
                early = None if said_enough else _early_piece(buf)
                if early:  # the answer's first words: start speaking now, the rest follows in whole sentences
                    piece, buf = buf[:early], buf[early:]
                elif m is not None:  # one or more whole sentences: say them now
                    piece, buf = buf[: m.end()], buf[m.end() :]
                elif ended:
                    piece, buf = buf, ""
                else:
                    # A pause right after punctuation also ends what can be said now.
                    wait = 0.12 if buf.rstrip()[-1:] in ".!?؟。…,:;" else None
                    if wait is None and spoke and not buf.strip():
                        wait = 1.2  # said "let me check…": if the answer takes a while, sound busy
                    try:
                        t = await asyncio.wait_for(queue.get(), timeout=wait)
                    except asyncio.TimeoutError:
                        if buf.strip():
                            piece, buf = buf, ""
                        else:
                            if self.waiting:
                                self.waiting(True)
                            try:
                                t = await queue.get()
                            finally:
                                if self.waiting:
                                    self.waiting(False)
                            if t is None:
                                ended = True
                            else:
                                buf += t
                            continue
                    else:
                        if t is None:
                            ended = True
                        else:
                            buf += t
                        continue
                # Passed to a teammate: the words before it in this voice, a moment of hold music,
                # then the teammate picks up in their own voice.
                hand = _VOICE.search(piece) if piece else None
                if hand:
                    buf = piece[hand.end() :] + buf
                    before = self._strip_hangup(piece[: hand.start()])
                    if before.strip():
                        spoke = True
                        async with tts_.synthesize(before.strip()) as stream:
                            async for ev in stream:
                                if played:
                                    played(ev.frame)
                                yield ev.frame
                    for frame in hold_music(self.session.tts._stt if hasattr(self.session.tts, "_stt") else None):  # noqa: SLF001
                        yield frame
                    self._strip_hangup(piece[hand.start() : hand.end()], switch_voice=True)
                    continue
                piece = self._strip_hangup(piece) if piece else piece
                if piece and len(piece.split()) >= 5 and not _FILLER.match(piece.strip()):
                    said_enough = True  # past the first words: whole sentences from here
                if piece and piece.strip():
                    spoke = True
                    async with tts_.synthesize(piece.strip()) as stream:
                        async for ev in stream:
                            if played:
                                played(ev.frame)
                            yield ev.frame
        finally:
            reader.cancel()


class SpokenText(lk_io.TextOutput):
    """The AI's words as the caller hears them (timed to its voice, word by word), for the app's
    live view: the model writes faster than it speaks, so its text alone ran ahead of the voice."""

    def __init__(self, room: str, host: Host) -> None:
        super().__init__(label="LocalAILineSpoken", next_in_chain=None)
        self._room = room
        self._host = host
        self._q: asyncio.Queue = asyncio.Queue()
        self._task: asyncio.Task | None = None

    async def capture_text(self, text: str) -> None:
        self._put(text, False)

    def flush(self) -> None:
        self._put("", True)

    def _put(self, text: str, final: bool) -> None:
        self._q.put_nowait((text, final))
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._send())

    async def _send(self) -> None:
        base = self._host.url
        if not base:
            return
        async with aiohttp.ClientSession() as h:
            while True:
                text, final = await self._q.get()
                while not final and not self._q.empty():  # (what came meanwhile, in one go)
                    more, final = self._q.get_nowait()
                    text += more
                text = _re.sub(r"\[[^\]]*\]?", "", text)  # control tags ([hangup], [voice:…]) aren't heard
                if not text and not final:
                    continue
                try:
                    await h.post(f"{base}/api/call-text", json={"room": self._room, "who": "ai", "text": text, "final": final},
                                 headers=self._host.headers, timeout=aiohttp.ClientTimeout(total=3))
                except Exception:  # noqa: BLE001
                    pass


def build_session(stt_: stt.STT, vad, model: str, host: Host, phone_call: bool = False, room: str = "", tts_: tts.TTS | None = None) -> AgentSession:
    llm = (AppLLM if host.url else openai.LLM)(
        base_url=host.llm_base,
        api_key=host.token or "local",
        **({"mode": model, "stt_": stt_, "room": room} if host.url else {"model": model}),
        temperature=0.5,
        timeout=httpx.Timeout(120.0, connect=5.0),
        max_retries=0,
    )
    return AgentSession(
        # A retried turn would run its tools again: answer once, or say sorry.
        conn_options=SessionConnectOptions(llm_conn_options=APIConnectOptions(max_retry=0, timeout=120.0)),
        stt=stt_,
        vad=vad,
        llm=llm,
        tts=tts_ or PiperTTS(stt_=stt_),
        turn_handling={
            "turn_detection": MultilingualModel(),  # runs locally
            # Phone callers pause between sentences ("Only Marco. … No other barbers. … Can't do it
            # otherwise."): ending the turn 0.2 s into a pause split one answer into three, each
            # answered on its own (and the rest of what they said cut off). On calls, wait longer.
            "endpointing": {"mode": "dynamic", "min_delay": 0.7, "max_delay": 2.4} if phone_call else {"mode": "dynamic", "min_delay": 0.2, "max_delay": 1.5},
            # Think before the turn is confirmed (dropped if the caller continues), but don't start
            # speaking until it is: it said "One—", "Okay, once—" and was cut off as they went on.
            "preemptive_generation": {"enabled": True, "preemptive_tts": False},
            # "vad" keeps barge-in local ("adaptive" calls LiveKit Cloud).
            # Interrupt only on the caller's real words: Ava's own voice is filtered out by the hearing.
            # On the phone, "okay" / "yeah" / "mm" while she speaks is listening, not interrupting.
            # (Shorter than this is dropped, not just "not an interruption": at 3 words, a caller's
            # "Tom Reed." or "Only Marco." said over her was lost. One word is the listening noise.)
            "interruption": {"enabled": True, "mode": "vad", "min_duration": 0.6 if phone_call else 0.4, "min_words": 2 if phone_call else 1,
                             "resume_false_interruption": True},
        },
    )


async def app_config(host: Host, mode: str, lang: str = "auto", room: str = "") -> dict:
    """Greeting, name and default language from the LocalAILine app (if it runs us).
    Also tells the app a call is starting, so it loads the model while we greet."""
    base = host.url
    if not base:
        return {}
    # (The app can be slow to answer right after it starts, or while it loads the model: without
    # its answer the call would be greeted as nobody in particular. A few tries, then go on.)
    for attempt in range(3):
        try:
            async with aiohttp.ClientSession() as h:
                async with h.get(f"{base}/api/voice-config", params={"mode": mode, "lang": lang, "room": room}, headers=host.headers,
                                 timeout=aiohttp.ClientTimeout(total=4)) as r:
                    return await r.json(content_type=None)
        except Exception as e:  # noqa: BLE001
            log.warning("no app config (try %d): %s", attempt + 1, e)
            await asyncio.sleep(0.5)
    return {}


def is_phone_caller(p) -> bool:  # noqa: ANN001
    """The person who rang in (LiveKit SIP's participant), not the owner or the AI."""
    return getattr(p, "kind", None) == rtc.ParticipantKind.PARTICIPANT_KIND_SIP or str(getattr(p, "identity", "")).startswith("sip_")


async def play_ringback(room: rtc.Room, number: str, stop: asyncio.Event) -> None:
    """A ringing tone to the caller while the owner's devices ring (the call is already connected)."""
    sr, step = 16000, 320  # 20 ms frames
    freqs, cadence = ringback_cadence(number)
    source = rtc.AudioSource(sr, 1)
    track = rtc.LocalAudioTrack.create_audio_track("ringing", source)
    pub = await room.local_participant.publish_track(track, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE))
    t = 0
    try:
        while not stop.is_set():
            for on, secs in cadence:
                for _ in range(int(secs * sr / step)):
                    if stop.is_set():
                        return
                    if on:
                        x = (np.arange(step) + t) / sr
                        pcm = sum(np.sin(2 * np.pi * f * x) for f in freqs) * (0.25 / len(freqs)) * 32767
                    else:
                        pcm = np.zeros(step)
                    t += step
                    await source.capture_frame(rtc.AudioFrame(pcm.astype(np.int16).tobytes(), sr, 1, step))
    finally:
        try:
            await room.local_participant.unpublish_track(pub.sid)
        except Exception as e:  # noqa: BLE001
            log.warning("stopping the ringing tone: %s", e)


async def ring_first(ctx: JobContext, host: Host, plan: dict, number: str) -> dict:
    """The owner is rung before anyone answers (see answer_plan). The caller hears ringing."""
    # A plugin can ring people elsewhere too (it's told once, as the ringing starts).
    try:
        r = plugin_call("on_ring", host, ctx.room.name, number, plan)
        if asyncio.iscoroutine(r):
            await r
    except Exception as e:  # noqa: BLE001
        log.warning("plugin on_ring failed: %s", e)
    taken, gone, who = asyncio.Event(), asyncio.Event(), {"by": None}

    def owner_in(p) -> None:  # noqa: ANN001
        by = takeover_by_attributes(dict(p.attributes), p.identity)
        if by:
            who["by"] = by
            taken.set()

    def on_data(packet) -> None:  # noqa: ANN001
        p = getattr(packet, "participant", None)
        by = takeover_by(getattr(packet, "data", b""), getattr(packet, "topic", None), getattr(p, "identity", "") if p else "")
        if by:
            who["by"] = by
            taken.set()

    def on_left(p) -> None:  # noqa: ANN001
        if is_phone_caller(p) and not any(is_phone_caller(q) for q in ctx.room.remote_participants.values()):
            gone.set()

    handlers = {"participant_attributes_changed": lambda _c, p: owner_in(p), "participant_connected": owner_in,
                "data_received": on_data, "participant_disconnected": on_left, "disconnected": lambda *_: gone.set()}
    for ev, fn in handlers.items():
        ctx.room.on(ev, fn)
    for p in list(ctx.room.remote_participants.values()):
        owner_in(p)

    async def ask_app() -> dict:
        async with aiohttp.ClientSession() as h:
            async with h.get(f"{host.url}/api/call-answer", params={"room": ctx.room.name}, headers=host.headers,
                             timeout=aiohttp.ClientTimeout(total=plan["wait"] + 20)) as r:
                return await r.json(content_type=None)

    stop = asyncio.Event()
    ring = asyncio.create_task(play_ringback(ctx.room, number, stop))
    try:
        out = await wait_to_answer(plan, ask_app, taken, gone, who)
    finally:
        stop.set()
        try:
            await asyncio.wait_for(ring, timeout=2)
        except Exception as e:  # noqa: BLE001
            log.warning("ringing tone: %s", e)
        for ev, fn in handlers.items():
            ctx.room.off(ev, fn)
    log.info("who takes the call: %s", out.get("go"))
    return out


async def delete_room(name: str) -> None:
    """Ends a call: everyone leaves its room (a phone caller is hung up on)."""
    url = os.environ.get("LIVEKIT_URL", "").replace("ws://", "http://").replace("wss://", "https://")
    lk = api.LiveKitAPI(url, os.environ.get("LIVEKIT_API_KEY"), os.environ.get("LIVEKIT_API_SECRET"))
    try:
        await lk.room.delete_room(api.DeleteRoomRequest(room=name))
    finally:
        await lk.aclose()


async def report_not_taken(host: Host, room: str, number: str, started: float, out: dict) -> None:
    """Tells the app about a call the AI never took (answered by a person, or missed)."""
    go, by = out.get("go"), out.get("by") or "you"
    what = {"person": f"Answered on {by}", "owner": f"Answered by {by}"}.get(go, "Missed: hung up while it was ringing")
    body = {"room": room, "transcript": [{"role": "note", "text": what}], "answered": go in ("person", "owner"), "number": number,
            "started_at": int(started * 1000), "duration_s": int(time.time() - started), "outcome": what}
    if go == "owner":
        body["taken_over_by"] = by  # (the owner is on the call now: it stays on their live view)
    try:
        async with aiohttp.ClientSession() as h:
            await h.post(f"{host.url}/api/call-ended", json=body, headers=host.headers, timeout=aiohttp.ClientTimeout(total=10))
    except Exception as e:  # noqa: BLE001
        log.warning("could not report the call: %s", e)


async def entrypoint(ctx: JobContext) -> None:
    await ctx.connect()
    # Room names from the app: talk-<caller|owner>-<language>-<id>; phone calls: pstn-…
    parts = ctx.room.name.split("-")
    mode = parts[1] if len(parts) > 2 and parts[0] == "talk" and parts[1] in ("caller", "owner") else "caller"
    phone_call = parts[0] == "pstn"
    if ctx.room.name.startswith("pstn-out-"):  # a call Ava placed: pstn-out-<task id>
        mode = f"outbound#{ctx.room.name[9:]}"
    started = time.time()
    picked_up = {"yes": not ctx.room.name.startswith("pstn-out-")}
    # The app this call talks to (the environment's, unless a plugin says otherwise).
    host = plugin_call("host_for_job", getattr(ctx.job, "metadata", "") or "") or Host.from_env()
    cfg = await app_config(host, mode, parts[2] if len(parts) > 3 and parts[0] == "talk" else "auto", ctx.room.name)
    # Who takes this call (the line's "who takes calls"): nobody here, or ring the owner first.
    plan = answer_plan(cfg) if phone_call and mode == "caller" and host.url else None
    if plan and plan.get("off"):
        log.info("calls on this line aren't answered here: hanging up")
        try:
            await delete_room(ctx.room.name)
        except Exception as e:  # noqa: BLE001
            log.warning("hang up failed: %s", e)
        ctx.shutdown("line off")
        return
    if plan:
        m = _re.match(r"^pstn-in-\d+-_(\+?\d{6,15})_", ctx.room.name)
        out = await ring_first(ctx, host, plan, m[1] if m else "")
        if out["go"] in ("person", "owner", "gone"):
            # Someone else has the call (or the caller hung up): the AI never joins it.
            await report_not_taken(host, ctx.room.name, m[1] if m else "", started, out)
            try:
                await ctx.room.disconnect()
            except Exception as e:  # noqa: BLE001
                log.warning("leaving the room: %s", e)
            ctx.shutdown(f"call taken: {out['go']}")
            return
        if out["go"] == "message":
            cfg["greeting"] = out.get("greeting") or "Hi, sorry, nobody can come to the phone right now. I can take a message. What's your name, and what's it about?"
    # Voices chosen in the app, per language.
    VOICE_CHOICE.clear()
    VOICE_CHOICE.update({k: v for k, v in (cfg.get("voices") or {}).items() if isinstance(v, str)})
    language = parts[2] if len(parts) > 3 and parts[0] == "talk" else cfg.get("language", LANGUAGE)
    vad = silero.VAD.load(min_silence_duration=0.35)
    stt_ = plugin_call("make_stt", host, language, cfg.get("vocabulary") or "")
    if stt_ is None:
        stt_ = WhisperStreamingSTT(vad=silero.VAD.load(min_silence_duration=0.4), language=language)
        stt_.vocabulary = cfg.get("vocabulary") or ""
        # On a phone call the far end cancels its own echo; Ava's voice isn't in the room.
        stt_.echo_check = not phone_call
    # Recording, when the owner turned it on (phone calls only; the caller is told in the greeting).
    if cfg.get("record") and parts[0] == "pstn" and hasattr(stt_, "recorder"):
        stt_.recorder = CallRecorder()
    model = mode if host.url else os.environ.get("LL_LLM_MODEL", "qwen3:4b-instruct")
    session = build_session(stt_, vad, model, host, phone_call=ctx.room.name.startswith("pstn"), room=ctx.room.name,
                            tts_=plugin_call("make_tts", host, cfg.get("agentVoice") or "", language, stt_))
    if cfg.get("agentVoice"):
        session.tts.voice_override = cfg["agentVoice"]
    session.tts._language = language  # noqa: SLF001
    lang = language if language != "auto" else "en"
    llm_turns = {"n": 0}  # requests to the brain on this call (told to the plugin at the end)

    # Timing of each turn, for tuning (end-of-turn wait, first token, first audio).
    @session.on("metrics_collected")
    def _metrics(ev):  # noqa: ANN001
        m = ev.metrics
        kind = type(m).__name__
        if kind == "EOUMetrics":
            log.info("TIMING end_of_utterance_delay=%.0fms transcription_delay=%.0fms", m.end_of_utterance_delay * 1000, m.transcription_delay * 1000)
        elif kind == "LLMMetrics":
            llm_turns["n"] += 1
            log.info("TIMING llm_ttft=%.0fms", m.ttft * 1000)
        elif kind == "TTSMetrics":
            log.info("TIMING tts_ttfb=%.0fms", m.ttfb * 1000)

    ava = Ava(instructions=os.environ.get("LL_INSTRUCTIONS", "You are Ava, a warm, brief phone assistant.")
              + " This is a phone call: speak naturally in short sentences, no emojis, no lists or markdown.")
    # Sent back in by the owner ("Hand back to AI"): talk to the caller, not to the owner still in the room.
    handback = handback_of(getattr(ctx.job, "metadata", "") or "")
    caller_id = next((p.identity for p in ctx.room.remote_participants.values() if not is_app_listener(p.identity)), None) if handback else None
    spoken = room_io.TextOutputOptions(next_in_chain=SpokenText(ctx.room.name, host)) if phone_call else True
    if caller_id:
        await session.start(agent=ava, room=ctx.room, room_options=room_io.RoomOptions(participant_identity=caller_id, text_output=spoken))
    else:
        await session.start(agent=ava, room=ctx.room, room_options=room_io.RoomOptions(text_output=spoken))
    # The app's "Interrupt" button (its mic is off while Ava speaks, so she can't hear herself).
    async def _interrupt(_data) -> str:  # noqa: ANN001
        await session.interrupt(force=True)
        return "ok"

    ctx.room.local_participant.register_rpc_method("ll.interrupt", _interrupt)

    ambient = SOUNDS.get(cfg.get("ambient") or "none")
    background = BackgroundAudioPlayer(ambient_sound=AudioConfig(ambient, volume=0.25) if ambient else None)
    await background.start(room=ctx.room, agent_session=session)
    thinking_clip = SOUNDS.get(cfg.get("thinking") or "keyboard")
    sound = {"handle": None, "task": None}

    def stop_sound() -> None:
        if sound["task"]:
            sound["task"].cancel()
            sound["task"] = None
        if sound["handle"] and not sound["handle"].done():
            sound["handle"].stop()
        sound["handle"] = None

    async def start_sound_soon() -> None:
        # Only a real pause in the answer gets the sound (not quick replies, not while you talk).
        await asyncio.sleep(0.6)
        if session.agent_state == "thinking" and session.user_state != "speaking":
            sound["handle"] = background.play(AudioConfig(thinking_clip, volume=0.4), loop=True)

    def sync_sound(*_) -> None:  # noqa: ANN002
        thinking = session.agent_state == "thinking" and session.user_state != "speaking"
        if not thinking or not thinking_clip:
            stop_sound()
        elif sound["task"] is None and sound["handle"] is None:
            sound["task"] = asyncio.create_task(start_sound_soon())

    session.on("agent_state_changed", sync_sound)

    def track_own_voice(ev) -> None:  # noqa: ANN001
        if not hasattr(stt_, "play_end"):
            return  # (a plugin's hearing that doesn't follow Ava's own voice)
        stt_.agent_speaking = ev.new_state == "speaking"
        if ev.new_state != "speaking":
            stt_.play_end = min(stt_.play_end, time.monotonic())  # interrupted: nothing more queued
            if stt_.recorder and ev.old_state == "speaking":
                stt_.recorder.cut_agent()
        if ev.old_state == "speaking":
            stt_.agent_until = time.monotonic() + 0.8  # the last words are still in the room
    session.on("agent_state_changed", track_own_voice)

    def waiting_sound(on: bool) -> None:
        if on and thinking_clip and sound["handle"] is None:
            sound["handle"] = background.play(AudioConfig(thinking_clip, volume=0.4), loop=True)
        elif not on:
            stop_sound()
    ava.waiting = waiting_sound

    async def warm_phrases() -> None:
        await asyncio.sleep(4)  # after the greeting
        tts_ = session.tts
        voice = tts_.kokoro_voice(lang) if isinstance(tts_, PiperTTS) else None
        if not voice:
            return
        loop = asyncio.get_running_loop()
        k = await loop.run_in_executor(None, tts_.kokoro)
        code = KOKORO_LANG.get(voice[0], "en-us")
        for p in COMMON_PHRASES:
            if (voice, p) not in _SPOKEN:
                samples, _ = await loop.run_in_executor(None, lambda p=p: k.create(p, voice=voice, speed=SPEED, lang=code))
                _SPOKEN[(voice, p)] = smooth((np.clip(samples, -1, 1) * 32767).astype(np.int16), 24000)

    asyncio.create_task(warm_phrases())
    session.on("user_state_changed", sync_sound)
    # When the call ends: the conversation goes back to the app (Calls, and the call's result).
    known_number = {"n": ""}

    def caller_number() -> str:
        # (Kept once seen: when the call is reported the caller has usually left already. Else the
        # number the phone service put in the room's name, "pstn-in-<line>-_<number>_…".)
        for p in ctx.room.remote_participants.values():
            n = p.attributes.get("sip.phoneNumber")
            if n:
                known_number["n"] = n
                return n
        if not known_number["n"]:
            m = _re.match(r"^pstn-in-\d+-_(\+?\d{6,15})_", ctx.room.name)
            known_number["n"] = m[1] if m else ""
        return known_number["n"]

    async def report() -> None:
        base = host.url
        if not base or not phone_call:
            return
        recording = None
        if stt_.recorder:
            try:
                folder = Path(os.environ.get("LL_RECORDINGS_DIR") or (VOICES_DIR.parent.parent / "recordings"))
                # (The room name carries the caller's number as their phone network sent it: only safe characters in a file name.)
                safe = _re.sub(r"[^A-Za-z0-9_+-]", "", ctx.room.name)[-24:] or "call"
                recording = stt_.recorder.save(folder / f"{time.strftime('%Y-%m-%d_%H-%M-%S')}_{safe}.wav")
            except Exception as e:  # noqa: BLE001
                log.warning("could not save the recording: %s", e)
        transcript = [{"role": "note", "text": f"Handed back to the AI by {handback}"}] if handback else []
        for item in session.history.items:
            text = getattr(item, "text_content", None)
            role = getattr(item, "role", None)
            if text and role in ("user", "assistant"):
                transcript.append({"role": role, "text": text})
        if taken["by"]:
            transcript.append({"role": "note", "text": f"Taken over by {taken['by']}"})
        try:
            async with aiohttp.ClientSession() as h:
                await h.post(f"{base}/api/call-ended", json={"room": ctx.room.name, "transcript": transcript, "answered": picked_up["yes"], "number": caller_number(),
                                                              "started_at": int(started * 1000), "duration_s": int(time.time() - started),
                                                              "recording": str(recording) if recording else None,
                                                              **({"taken_over_by": taken["by"]} if taken["by"] else {})},
                             headers=host.headers, timeout=aiohttp.ClientTimeout(total=10))
        except Exception as e:  # noqa: BLE001
            log.warning("could not report the call: %s", e)

    ctx.add_shutdown_callback(report)

    async def tell_plugin() -> None:
        stats = {"room": ctx.room.name, "phoneCall": phone_call, "answered": picked_up["yes"], "callSeconds": round(time.time() - started, 1),
                 "llmTurns": llm_turns["n"], "stt": stt_, "tts": session.tts}
        try:
            res = plugin_call("on_call_end", host, stats)
            if inspect.isawaitable(res):
                await res
        except Exception as e:  # noqa: BLE001
            log.warning("plugin on_call_end failed: %s", e)

    if plugin():
        ctx.add_shutdown_callback(tell_plugin)

    # The owner takes over (the app's "Take over"): stop mid-word, say nothing more, and leave the
    # call to them. The caller stays connected; what was said so far is saved by report().
    taken = {"by": None}

    def step_out(by: str) -> None:
        if taken["by"]:
            return
        taken["by"] = by
        log.info("taken over by %s; leaving the call to them", by)
        ava.hangup_requested = False
        ava.connect_requested = None
        stop_sound()
        for quiet in (lambda: session.input.set_audio_enabled(False), lambda: session.output.set_audio_enabled(False), lambda: session.interrupt(force=True)):
            try:
                quiet()
            except Exception as e:  # noqa: BLE001
                log.warning("stepping out: %s", e)
        asyncio.create_task(leave_to_owner())

    async def leave_to_owner() -> None:
        await asyncio.sleep(0.3)
        # Leave the room properly first, so everyone sees the AI gone at once (a process that just
        # exits stays "in the call" for ~20 s); the room and the caller stay.
        try:
            await ctx.room.disconnect()
        except Exception as e:  # noqa: BLE001
            log.warning("leaving the room: %s", e)
        ctx.shutdown("taken over by the owner")

    def on_data(packet) -> None:  # noqa: ANN001
        p = getattr(packet, "participant", None)
        by = takeover_by(getattr(packet, "data", b""), getattr(packet, "topic", None), getattr(p, "identity", "") if p else "")
        if by:
            step_out(by)

    def on_attributes(_changed, participant) -> None:  # noqa: ANN001
        by = takeover_by_attributes(dict(participant.attributes), participant.identity)
        if by:
            step_out(by)

    def on_joined(participant) -> None:  # noqa: ANN001
        # The owner's app may join with the take-over already set (its first message can be lost
        # while its connection is still opening).
        by = takeover_by_attributes(dict(participant.attributes), participant.identity)
        if by:
            step_out(by)

    ctx.room.on("data_received", on_data)
    ctx.room.on("participant_attributes_changed", on_attributes)
    ctx.room.on("participant_connected", on_joined)

    async def watch_for_owner() -> None:
        # Events before the handlers above were set (the greeting, say) are missed: whoever is
        # already in the call, and once a second after, in case a change was lost.
        while not taken["by"]:
            for p in list(ctx.room.remote_participants.values()):
                by = takeover_by_attributes(dict(p.attributes), p.identity)
                if by:
                    step_out(by)
                    return
            await asyncio.sleep(1.0)

    asyncio.create_task(watch_for_owner())

    async def hang_up() -> None:
        await asyncio.sleep(1.0)  # let the goodbye finish on their side
        log.info("hanging up")
        try:
            url = os.environ.get("LIVEKIT_URL", "").replace("ws://", "http://").replace("wss://", "https://")
            lk = api.LiveKitAPI(url, os.environ.get("LIVEKIT_API_KEY"), os.environ.get("LIVEKIT_API_SECRET"))
            await lk.room.delete_room(api.DeleteRoomRequest(room=ctx.room.name))
            await lk.aclose()
        except Exception as e:  # noqa: BLE001
            log.warning("hang up failed: %s", e)
            ctx.shutdown("hang up")

    def maybe_hang_up(ev) -> None:  # noqa: ANN001
        if phone_call and ava.hangup_requested and ev.old_state == "speaking" and ev.new_state != "speaking":
            ava.hangup_requested = False
            asyncio.create_task(hang_up())

    session.on("agent_state_changed", maybe_hang_up)

    # Live state for the app (how many calls, who is speaking): sent when it changes.
    async def send_state() -> None:
        base = host.url
        if not base:
            return
        try:
            async with aiohttp.ClientSession() as h:
                await h.post(f"{base}/api/call-state", json={"room": ctx.room.name, "agent": str(session.agent_state), "caller": str(session.user_state), "number": caller_number()},
                             headers=host.headers, timeout=aiohttp.ClientTimeout(total=3))
        except Exception:  # noqa: BLE001
            pass

    session.on("agent_state_changed", lambda *_: asyncio.create_task(send_state()))
    session.on("user_state_changed", lambda *_: asyncio.create_task(send_state()))

    # The caller's words for the app's live view while they speak (interim), then as finally heard.
    last_words = {"text": "", "at": 0.0}

    async def send_words(text: str, final: bool) -> None:
        base = host.url
        if not base or not text.strip():
            return
        try:
            async with aiohttp.ClientSession() as h:
                await h.post(f"{base}/api/call-text", json={"room": ctx.room.name, "text": text, "final": final},
                             headers=host.headers, timeout=aiohttp.ClientTimeout(total=3))
        except Exception:  # noqa: BLE001
            pass

    def on_words(ev) -> None:  # noqa: ANN001
        text = getattr(ev, "transcript", "") or ""
        final = bool(getattr(ev, "is_final", False))
        # A plugin's hearing that reports the language: the answer follows it (whisper.cpp sets its own).
        if final and language == "auto" and not isinstance(stt_, WhisperStreamingSTT) and text.strip():
            heard = str(getattr(ev, "language", None) or "").lower().split("-")[0]
            if heard and len(heard) <= 3:
                stt_.detected_language = heard
        # Interim words change many times a second: send the new ones at most ~5 times a second.
        if not final and (text == last_words["text"] or time.time() - last_words["at"] < 0.2):
            return
        last_words.update(text=text, at=time.time())
        asyncio.create_task(send_words(text, final))

    session.on("user_input_transcribed", on_words)

    async def connect_person() -> None:
        """Hold music while a person is rung into this call; brief them, then step out."""
        hold = background.play(AudioConfig(BuiltinAudioClip.HOLD_MUSIC, volume=0.5), loop=True)
        try:
            async with aiohttp.ClientSession() as h:
                async with h.get(f"{host.url}/api/connect", params={"room": ctx.room.name},
                                 headers=host.headers, timeout=aiohttp.ClientTimeout(total=90)) as r:
                    res = await r.json(content_type=None)
        except Exception as e:  # noqa: BLE001
            res = {"ok": False}
            log.warning("connecting a person failed: %s", e)
        hold.stop()
        if res.get("ok"):
            await session.say(res.get("say") or "Connecting you now.", allow_interruptions=False)
            log.info("person connected; leaving the call to them")
            session.input.set_audio_enabled(False)
            await asyncio.sleep(0.5)
            ctx.shutdown("passed to a person")  # the caller and the person stay connected
        else:
            who = res.get("name")
            session.say(f"Sorry, {who + ' isn' if who else 'they aren'}'t available right now. Can I take a message, or help with anything else?", allow_interruptions=True)

    def maybe_connect(ev) -> None:  # noqa: ANN001
        if phone_call and ava.connect_requested and ev.old_state == "speaking" and ev.new_state != "speaking":
            ava.connect_requested = None
            asyncio.create_task(connect_person())

    session.on("agent_state_changed", maybe_connect)

    # Several calls at once, up to the limit set in the app; beyond it, callers hear "busy".
    if phone_call and host.url:
        try:
            async with aiohttp.ClientSession() as h:
                async with h.get(f"{host.url}/api/call-slot", params={"room": ctx.room.name},
                                 headers=host.headers, timeout=aiohttp.ClientTimeout(total=5)) as r:
                    slot = await r.json(content_type=None)
            if not slot.get("ok", True):
                await session.say("Sorry, all our lines are busy right now. Please call back in a few minutes. Goodbye.", allow_interruptions=False)
                await asyncio.sleep(0.5)
                await hang_up()
                return
        except Exception as e:  # noqa: BLE001
            log.warning("call slot check failed: %s", e)

    if mode.startswith("outbound#"):
        # Wait until they pick up (the phone is still ringing until then).
        answered = asyncio.Event()

        def check(*_):  # noqa: ANN002
            for p in ctx.room.remote_participants.values():
                if p.attributes.get("sip.callStatus") == "active":
                    answered.set()

        ctx.room.on("participant_attributes_changed", check)
        ctx.room.on("participant_connected", check)
        # The call failed before anyone answered (busy, refused…): stop waiting.
        ctx.room.on("participant_disconnected", lambda *_: None if answered.is_set() else ctx.shutdown("call failed"))
        check()
        try:
            await asyncio.wait_for(answered.wait(), timeout=75)
        except asyncio.TimeoutError:
            log.info("no answer")
            ctx.shutdown("no answer")
            return
        picked_up["yes"] = True
        await asyncio.sleep(0.6)  # let them say "hello?"

    greeting = cfg.get("greeting") if (mode == "caller" or mode.startswith("outbound#")) else f"Hi, it's {cfg.get('name', 'Ava')}. What can I do for you?"
    greeting = greeting or os.environ.get("LL_GREETING", "")
    if handback:  # back on a call the owner had taken over: no fresh hello, no "calling on behalf of"
        greeting = f"Hi, it's {cfg.get('name', 'Ava')} again. Is there anything else I can help you with?"
    if greeting and not taken["by"]:
        session.say(greeting, allow_interruptions=True)


_kokoro_model = None
_kokoro_lock = threading.Lock()


def load_kokoro():  # noqa: ANN201
    """The natural voice, once per process. Its voices are read into memory up front: they live in a
    zip file that can't be read from two threads at once (two sentences being spoken together)."""
    global _kokoro_model  # noqa: PLW0603
    with _kokoro_lock:
        if _kokoro_model is None:
            from kokoro_onnx import Kokoro  # noqa: PLC0415

            k = Kokoro(str(KOKORO_DIR / "kokoro-v1.0.onnx"), str(KOKORO_DIR / "voices-v1.0.bin"))
            k.voices = {name: k.voices[name] for name in k.voices.files} if hasattr(k.voices, "files") else k.voices
            _kokoro_model = k
        return _kokoro_model


def prewarm(proc) -> None:  # noqa: ANN001
    # Load models once per call process, before the call: each call has its own process, so calls
    # hear and speak at the same time, and the first words don't wait for a voice to load.
    proc.userdata["vad"] = silero.VAD.load(min_silence_duration=0.35)
    try:
        import piper  # noqa: F401, PLC0415
    except ImportError:  # (the local voices are optional when a plugin gives the voice)
        if not plugin():
            raise

    if KOKORO_DIR.joinpath("kokoro-v1.0.onnx").exists():
        load_kokoro()


def main() -> None:
    """Runs the worker (`start`, `dev`, `download-files`, … as LiveKit's command line takes them)."""
    logging.basicConfig(level=logging.INFO)
    plugin()  # (a missing or broken plugin stops the worker here, not on its first call)
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
            prewarm_fnc=prewarm,
            agent_name=os.environ.get("LL_AGENT_NAME", ""),
            # A ready process per line, so several callers are answered at once.
            num_idle_processes=LINES,
            # Never turn a caller away because the processor is busy (the app limits the lines).
            load_threshold=1.0,
        )
    )


if __name__ == "__main__":
    main()
