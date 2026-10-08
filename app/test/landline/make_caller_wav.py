"""Makes test/landline/caller.wav: a caller's words in the app's own voice, as a phone line carries
them (8 kHz G.711 mu-law). Run with the voice engine's Python:
  "$HOME/Library/Application Support/com.localailine.localailine/engine/.venv/bin/python" test/landline/make_caller_wav.py
"""
import importlib.util
import struct
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.argv = [sys.argv[0]]
spec = importlib.util.spec_from_file_location("v", HERE.parents[1] / "assets" / "engine" / "localailine_voice.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

samples, sr = v.load_kokoro().create("Hello, I would like to book a table for two tonight at seven, please.", voice="bf_emma", speed=1.0, lang="en-gb")
x = np.interp(np.arange(0, len(samples), sr / 8000), np.arange(len(samples)), samples)
x = np.concatenate([np.zeros(4000), x, np.zeros(48000)])  # a moment of quiet, the words, then quiet for the answer
pcm = np.clip(x * 32767, -32768, 32767).astype(np.int32)


def ulaw(s: int) -> int:
    sign = 0x80 if s < 0 else 0
    s = min(abs(s), 32635) + 0x84
    exp, mask = 7, 0x4000
    while exp > 0 and not (s & mask):
        exp -= 1
        mask >>= 1
    return ~(sign | (exp << 4) | ((s >> (exp + 3)) & 0x0F)) & 0xFF


data = bytes(ulaw(int(s)) for s in pcm)
with open(HERE / "caller.wav", "wb") as f:
    fmt = struct.pack("<HHIIHH", 7, 1, 8000, 8000, 1, 8)
    f.write(b"RIFF" + struct.pack("<I", 4 + 8 + 18 + 8 + len(data) + 12) + b"WAVE" + b"fmt " + struct.pack("<I", 18) + fmt + b"\x00\x00"
            + b"fact" + struct.pack("<II", 4, len(data)) + b"data" + struct.pack("<I", len(data)) + data)
print(f"wrote {HERE / 'caller.wav'} ({len(data) / 8000:.1f} s)")
