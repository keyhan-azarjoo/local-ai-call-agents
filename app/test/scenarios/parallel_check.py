"""Are calls really handled at the same time? Fires N requests at once at each stage of a call
(the AI model, hearing, the voice) and compares with one on its own.

  python parallel_check.py [N]

For each stage: the time for one alone, the time for N together, and "overlap" = the work done
divided by the time it took (N means all N ran side by side; 1 means they waited in a queue).
Needs Ollama, the whisper servers and the speech lab (port 8920) running; makes no calls.
"""

from __future__ import annotations

import concurrent.futures as cf
import io
import json
import sys
import time
import urllib.request
import wave

import numpy as np

N = int(sys.argv[1]) if len(sys.argv) > 1 else 3
LAB = "http://127.0.0.1:8920"
LINES = [
    "Hi, I'd like to book a table for four on Friday at seven, please.",
    "Could I get a skin fade with Mia tomorrow afternoon?",
    "What time do you close on Sundays, and do you have parking?",
    "I'd like to order two margheritas for delivery to 12 Park Road.",
    "Can I move my appointment from Tuesday to Thursday morning?",
    "Do you have a double room free for two nights next weekend?",
    "Is the gym open on bank holidays, and how much is a day pass?",
    "I need my car in for an MOT some time next week.",
    "Can you tell me the price of a cut and colour?",
    "I'd like to speak to someone about a group booking for twelve.",
]


def post(url: str, body: bytes, ctype: str = "application/json") -> bytes:
    rq = urllib.request.Request(url, body, {"Content-Type": ctype})
    return urllib.request.urlopen(rq, timeout=600).read()


def llm(i: int) -> None:
    body = {
        "model": "qwen3:4b-instruct", "stream": False, "keep_alive": -1,
        "options": {"num_ctx": 16384, "num_predict": 60, "temperature": 0.4},
        "messages": [{"role": "system", "content": "You are a friendly receptionist. Answer in one or two short sentences."},
                     {"role": "user", "content": LINES[i % len(LINES)]}],
    }
    post("http://127.0.0.1:11434/api/chat", json.dumps(body).encode())


def tts(i: int) -> None:
    post(f"{LAB}/roundtrip", json.dumps({"text": LINES[i % len(LINES)], "voice": "af_heart", "stt": False}).encode())


_speech: bytes | None = None


def speech() -> bytes:
    """A real spoken line (the lab's voice), as 16 kHz WAV for the hearing servers."""
    global _speech  # noqa: PLW0603
    if _speech is None:
        t = np.arange(16000 * 3) / 16000
        pcm = (np.sin(2 * np.pi * 200 * t) * 2500).astype(np.int16)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(pcm.tobytes())
        _speech = buf.getvalue()
    return _speech


HEARING: list[str] = []


def stt(i: int) -> None:
    b = "llcheck"
    body = (f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="a.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode() + speech() + f"\r\n--{b}--\r\n".encode()
    post(HEARING[i % len(HEARING)] + "/inference", body, f"multipart/form-data; boundary={b}")


def timed(fn, i: int) -> tuple[float, float, float]:  # noqa: ANN001
    t = time.perf_counter()
    fn(i)
    return t, time.perf_counter(), time.perf_counter() - t


def stage(name: str, fn, n: int) -> dict:  # noqa: ANN001
    fn(0)  # warm up (loads the model / voice)
    one = min(timed(fn, 0)[2] for _ in range(2))
    t0 = time.perf_counter()
    with cf.ThreadPoolExecutor(n) as ex:
        runs = list(ex.map(lambda i: timed(fn, i), range(n)))
    wall = time.perf_counter() - t0
    overlap = sum(r[2] for r in runs) / wall
    # Did they really run side by side: every request had started before the first one finished.
    together = max(r[0] for r in runs) < min(r[1] for r in runs)
    return {"stage": name, "one_s": round(one, 2), f"{n}_at_once_s": round(wall, 2), "overlap": round(overlap, 2), "all_started_together": together}


def main() -> None:
    global HEARING  # noqa: PLW0603
    try:
        HEARING = json.loads(urllib.request.urlopen(f"{LAB}/health", timeout=3).read()).get("hearing") or ["http://127.0.0.1:8910"]
    except Exception:  # noqa: BLE001
        HEARING = ["http://127.0.0.1:8910"]
    print(f"{N} at once · hearing servers: {len(HEARING)}")
    rows = [stage("AI model (answers)", llm, N), stage("hearing (STT)", stt, N), stage("voice (TTS)", tts, N)]
    for r in rows:
        verdict = "side by side" if r["overlap"] >= N * 0.6 else "partly queued" if r["overlap"] >= 1.3 else "QUEUED one after another"
        print(f"  {r['stage']:<20} one {r['one_s']:>5.2f} s   {N} together {r[f'{N}_at_once_s']:>5.2f} s   overlap {r['overlap']:.1f}/{N}  → {verdict}")
    print(json.dumps(rows))


if __name__ == "__main__":
    main()
