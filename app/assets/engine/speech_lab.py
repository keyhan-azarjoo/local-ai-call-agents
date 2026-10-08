"""Speech lab for test calls: speaks a line with the real voice (Kokoro, the way calls do: the
first words early, then whole sentences, trimmed and joined smoothly) and hears it back with the
real hearing (the Whisper server), timing both and saying how well it was understood.

  python speech_lab.py --port 8920
  POST /roundtrip {"text": "...", "voice": "af_heart", "lang": "en", "stt": true}
    -> {"first_ms", "tts_ms", "audio_s", "stt_ms", "heard", "match"}

Uses the voice engine's own code (localailine_voice.py), so tests hear what callers hear.
"""

from __future__ import annotations

import argparse
import asyncio
import difflib
import importlib.util
import io
import os
import re
import sys
import time
import wave
from pathlib import Path

import aiohttp
import numpy as np
from aiohttp import web

HERE = Path(__file__).resolve().parent
_ARGS = sys.argv[1:]
sys.argv = [sys.argv[0]]  # the engine module reads no arguments of ours
_spec = importlib.util.spec_from_file_location("localailine_voice", HERE / "localailine_voice.py")
v = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v)  # type: ignore[union-attr]

_turn = 0


def kokoro():  # noqa: ANN201
    return v.load_kokoro()


def pieces(text: str) -> list[str]:
    """As a call speaks it: the first words early (if the answer starts with a clause), then sentences."""
    out: list[str] = []
    rest = text
    early = v._early_piece(rest)  # noqa: SLF001
    if early:
        out.append(rest[:early])
        rest = rest[early:]
    return out + v.sentences(rest)


def norm(t: str) -> str:
    t = t.lower().replace("£", " pounds ").replace("%", " percent ")
    return " ".join(re.sub(r"[^a-z0-9À-ɏ؀-ۿ ]+", " ", t).split())


def wav16k(pcm: np.ndarray, sr: int) -> bytes:
    x = np.interp(np.arange(0, len(pcm), sr / 16000), np.arange(len(pcm)), pcm.astype(np.float32)).astype(np.int16) if sr != 16000 else pcm
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(x.tobytes())
    return buf.getvalue()


async def roundtrip(req: web.Request) -> web.Response:
    global _turn  # noqa: PLW0603
    j = await req.json()
    text = v.speakable(v.EMOJI.sub("", str(j.get("text", ""))).replace("*", "")).strip()
    voice = str(j.get("voice") or "af_heart").replace("kokoro:", "")
    lang = str(j.get("lang") or "en")
    if not text:
        return web.json_response({"error": "nothing to say"}, status=400)
    # No lock: several test calls speak and hear at the same time, as real calls do.
    started = time.time()
    loop = asyncio.get_running_loop()
    k = await loop.run_in_executor(None, kokoro)
    code = v.KOKORO_LANG.get(voice[0], "en-us")
    t0 = time.perf_counter()
    first_ms = None
    audio: list[np.ndarray] = []
    for p in pieces(text):
        samples, _ = await loop.run_in_executor(None, lambda p=p: k.create(p, voice=voice, speed=v.SPEED, lang=code))
        pcm = v.smooth((np.clip(samples, -1, 1) * 32767).astype(np.int16), 24000)
        if first_ms is None:
            first_ms = int((time.perf_counter() - t0) * 1000)  # the caller starts hearing it here
        audio.append(pcm)
    tts_ms = int((time.perf_counter() - t0) * 1000)
    pcm = np.concatenate(audio) if audio else np.zeros(0, np.int16)
    out = {"first_ms": first_ms, "tts_ms": tts_ms, "audio_s": round(len(pcm) / 24000, 2)}
    if j.get("stt", True) and len(pcm):
        t1 = time.perf_counter()
        form = aiohttp.FormData()
        form.add_field("file", wav16k(pcm, 24000), filename="a.wav", content_type="audio/wav")
        form.add_field("response_format", "json")
        form.add_field("language", lang if lang != "auto" else "auto")
        form.add_field("temperature", "0")
        _turn += 1  # several calls at once: each turn is heard by the next server in the pool
        url = v.HEARING[_turn % len(v.HEARING)] + "/inference"
        async with aiohttp.ClientSession() as h, h.post(url, data=form, timeout=aiohttp.ClientTimeout(total=30)) as r:
            heard = (await r.json(content_type=None)).get("text", "")
        heard = v._NOT_SPEECH.sub("", heard).strip()  # noqa: SLF001
        out.update(stt_ms=int((time.perf_counter() - t1) * 1000), heard=heard, match=round(difflib.SequenceMatcher(None, norm(text), norm(heard)).ratio(), 2))
    out.update(started=round(started, 3), ended=round(time.time(), 3))  # to see calls overlap
    return web.json_response(out)


async def health(_req: web.Request) -> web.Response:
    return web.json_response({"ok": True, "parallel": True, "hearing": v.HEARING})


def main() -> None:
    a = argparse.ArgumentParser()
    a.add_argument("--port", type=int, default=8920)
    args = a.parse_args(_ARGS)
    app = web.Application()
    app.router.add_post("/roundtrip", roundtrip)
    app.router.add_get("/health", health)
    web.run_app(app, host="127.0.0.1", port=args.port, print=None)


if __name__ == "__main__":
    main()
