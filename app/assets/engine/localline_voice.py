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
import httpx
import numpy as np
from livekit import api, rtc
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
from livekit.agents.voice.agent_session import SessionConnectOptions
from livekit.agents.voice.background_audio import AudioConfig, BackgroundAudioPlayer, BuiltinAudioClip
from livekit.plugins import openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

log = logging.getLogger("localline.voice")

WHISPER_URL = os.environ.get("LL_WHISPER_URL", "http://127.0.0.1:8910")
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
        form = aiohttp.FormData()
        if self.vocabulary and language in ("en", "auto") and self.detected_language == "en":
            form.add_field("prompt", self.vocabulary)
        form.add_field("file", wav_bytes(pcm, sr), filename="a.wav", content_type="audio/wav")
        form.add_field("response_format", "verbose_json")
        form.add_field("language", language)
        form.add_field("temperature", "0")
        async with self.http().post(self._url, data=form, timeout=aiohttp.ClientTimeout(total=15)) as r:
            return await r.json(content_type=None)

    async def _recognize_impl(self, buffer, *, language: NotGivenOr[str] = NOT_GIVEN, conn_options: APIConnectOptions):
        frame = rtc.combine_audio_frames(buffer)
        pcm = np.frombuffer(frame.data, dtype=np.int16)
        text, lang = await self.transcribe(pcm, frame.sample_rate, final=True)
        return stt.SpeechEvent(type=stt.SpeechEventType.FINAL_TRANSCRIPT, alternatives=[stt.SpeechData(language=lang, text=text)])

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
                        alternatives=[stt.SpeechData(language=lang, text=text)]))
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
        if not hasattr(self, "_kokoro"):
            from kokoro_onnx import Kokoro  # noqa: PLC0415

            self._kokoro = Kokoro(str(KOKORO_DIR / "kokoro-v1.0.onnx"), str(KOKORO_DIR / "voices-v1.0.bin"))
        return self._kokoro

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
    return __import__("re").sub(r"\s*&\s*", " and ", text)


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
        self._opts.model = f"{self._mode}:{self._stt.detected_language}:{self._room}"
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
        spoke = False
        queue: asyncio.Queue[str | None] = asyncio.Queue()

        async def read() -> None:
            async for t in text:
                await queue.put(t)
            await queue.put(None)

        reader = asyncio.create_task(read())
        buf, ended = "", False
        try:
            while not ended or buf.strip():
                piece = None
                m = None
                for m in _SENTENCE_END.finditer(buf):
                    pass
                if m is not None:  # one or more whole sentences: say them now
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
                                yield ev.frame
                    for frame in hold_music(self.session.tts._stt if hasattr(self.session.tts, "_stt") else None):  # noqa: SLF001
                        yield frame
                    self._strip_hangup(piece[hand.start() : hand.end()], switch_voice=True)
                    continue
                piece = self._strip_hangup(piece) if piece else piece
                if piece and piece.strip():
                    spoke = True
                    async with tts_.synthesize(piece.strip()) as stream:
                        async for ev in stream:
                            yield ev.frame
        finally:
            reader.cancel()


def build_session(stt_: WhisperStreamingSTT, vad, model: str, phone_call: bool = False, room: str = "") -> AgentSession:
    llm = (AppLLM if os.environ.get("LL_APP_URL") else openai.LLM)(
        base_url=os.environ.get("LL_LLM_BASE", "http://127.0.0.1:11434/v1"),
        api_key=os.environ.get("LL_LLM_KEY", "local"),
        **({"mode": model, "stt_": stt_, "room": room} if os.environ.get("LL_APP_URL") else {"model": model}),
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
        tts=PiperTTS(stt_=stt_),
        turn_handling={
            "turn_detection": MultilingualModel(),  # runs locally
            "endpointing": {"mode": "dynamic", "min_delay": 0.2, "max_delay": 1.5},
            # Think (and start speaking) before the turn is confirmed; dropped if the caller continues.
            "preemptive_generation": {"enabled": True, "preemptive_tts": True},
            # "vad" keeps barge-in local ("adaptive" calls LiveKit Cloud).
            # Interrupt only on the caller's real words: Ava's own voice is filtered out by the hearing.
            # On the phone, "okay" / "yeah" / "mm" while she speaks is listening, not interrupting.
            "interruption": {"enabled": True, "mode": "vad", "min_duration": 0.6 if phone_call else 0.4, "min_words": 3 if phone_call else 1,
                             "resume_false_interruption": True},
        },
    )


async def app_config(mode: str, lang: str = "auto", room: str = "") -> dict:
    """Greeting, name and default language from the LocalAILine app (if it runs us).
    Also tells the app a call is starting, so it loads the model while we greet."""
    base = os.environ.get("LL_APP_URL")
    if not base:
        return {}
    try:
        async with aiohttp.ClientSession() as h:
            async with h.get(f"{base}/api/voice-config", params={"mode": mode, "lang": lang, "room": room}, headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"},
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
    phone_call = parts[0] == "pstn"
    if ctx.room.name.startswith("pstn-out-"):  # a call Ava placed: pstn-out-<task id>
        mode = f"outbound#{ctx.room.name[9:]}"
    started = time.time()
    picked_up = {"yes": not ctx.room.name.startswith("pstn-out-")}
    cfg = await app_config(mode, parts[2] if len(parts) > 3 and parts[0] == "talk" else "auto", ctx.room.name)
    # Voices chosen in the app, per language.
    VOICE_CHOICE.clear()
    VOICE_CHOICE.update({k: v for k, v in (cfg.get("voices") or {}).items() if isinstance(v, str)})
    language = parts[2] if len(parts) > 3 and parts[0] == "talk" else cfg.get("language", LANGUAGE)
    vad = silero.VAD.load(min_silence_duration=0.35)
    stt_ = WhisperStreamingSTT(vad=silero.VAD.load(min_silence_duration=0.4), language=language)
    stt_.vocabulary = cfg.get("vocabulary") or ""
    # Recording, when the owner turned it on (phone calls only; the caller is told in the greeting).
    if cfg.get("record") and parts[0] == "pstn":
        stt_.recorder = CallRecorder()
    # On a phone call the far end cancels its own echo; Ava's voice isn't in the room.
    stt_.echo_check = not phone_call
    model = mode if os.environ.get("LL_APP_URL") else os.environ.get("LL_LLM_MODEL", "qwen3:4b-instruct")
    session = build_session(stt_, vad, model, phone_call=ctx.room.name.startswith("pstn"), room=ctx.room.name)
    if cfg.get("agentVoice"):
        session.tts.voice_override = cfg["agentVoice"]
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

    ava = Ava(instructions=os.environ.get("LL_INSTRUCTIONS", "You are Ava, a warm, brief phone assistant.")
              + " This is a phone call: speak naturally in short sentences, no emojis, no lists or markdown.")
    await session.start(agent=ava, room=ctx.room)
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
    def caller_number() -> str:
        for p in ctx.room.remote_participants.values():
            n = p.attributes.get("sip.phoneNumber")
            if n:
                return n
        return ""

    async def report() -> None:
        base = os.environ.get("LL_APP_URL")
        if not base or not phone_call:
            return
        recording = None
        if stt_.recorder:
            try:
                folder = Path(os.environ.get("LL_RECORDINGS_DIR") or (VOICES_DIR.parent.parent / "recordings"))
                recording = stt_.recorder.save(folder / f"{time.strftime('%Y-%m-%d_%H-%M-%S')}_{ctx.room.name[-24:]}.wav")
            except Exception as e:  # noqa: BLE001
                log.warning("could not save the recording: %s", e)
        transcript = []
        for item in session.history.items:
            text = getattr(item, "text_content", None)
            role = getattr(item, "role", None)
            if text and role in ("user", "assistant"):
                transcript.append({"role": role, "text": text})
        try:
            async with aiohttp.ClientSession() as h:
                await h.post(f"{base}/api/call-ended", json={"room": ctx.room.name, "transcript": transcript, "answered": picked_up["yes"], "number": caller_number(),
                                                              "started_at": int(started * 1000), "duration_s": int(time.time() - started),
                                                              "recording": str(recording) if recording else None},
                             headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"}, timeout=aiohttp.ClientTimeout(total=10))
        except Exception as e:  # noqa: BLE001
            log.warning("could not report the call: %s", e)

    ctx.add_shutdown_callback(report)

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
        base = os.environ.get("LL_APP_URL")
        if not base:
            return
        try:
            async with aiohttp.ClientSession() as h:
                await h.post(f"{base}/api/call-state", json={"room": ctx.room.name, "agent": str(session.agent_state), "caller": str(session.user_state), "number": caller_number()},
                             headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"}, timeout=aiohttp.ClientTimeout(total=3))
        except Exception:  # noqa: BLE001
            pass

    session.on("agent_state_changed", lambda *_: asyncio.create_task(send_state()))
    session.on("user_state_changed", lambda *_: asyncio.create_task(send_state()))

    async def connect_person() -> None:
        """Hold music while a person is rung into this call; brief them, then step out."""
        hold = background.play(AudioConfig(BuiltinAudioClip.HOLD_MUSIC, volume=0.5), loop=True)
        try:
            async with aiohttp.ClientSession() as h:
                async with h.get(f"{os.environ['LL_APP_URL']}/api/connect", params={"room": ctx.room.name},
                                 headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"}, timeout=aiohttp.ClientTimeout(total=90)) as r:
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
            who = res.get("name") or "they"
            session.say(f"Sorry, {who} isn't available right now. Can I take a message, or help with anything else?", allow_interruptions=True)

    def maybe_connect(ev) -> None:  # noqa: ANN001
        if phone_call and ava.connect_requested and ev.old_state == "speaking" and ev.new_state != "speaking":
            ava.connect_requested = None
            asyncio.create_task(connect_person())

    session.on("agent_state_changed", maybe_connect)

    # Several calls at once, up to the limit set in the app; beyond it, callers hear "busy".
    if phone_call and os.environ.get("LL_APP_URL"):
        try:
            async with aiohttp.ClientSession() as h:
                async with h.get(f"{os.environ['LL_APP_URL']}/api/call-slot", params={"room": ctx.room.name},
                                 headers={"Authorization": f"Bearer {os.environ.get('LL_LLM_KEY', '')}"}, timeout=aiohttp.ClientTimeout(total=5)) as r:
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
    if greeting:
        session.say(greeting, allow_interruptions=True)


def prewarm(proc) -> None:  # noqa: ANN001
    # Load models and heavy imports once per worker process (not per call).
    proc.userdata["vad"] = silero.VAD.load(min_silence_duration=0.35)
    import piper  # noqa: F401, PLC0415
    import kokoro_onnx  # noqa: F401, PLC0415


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, prewarm_fnc=prewarm, agent_name=""))
