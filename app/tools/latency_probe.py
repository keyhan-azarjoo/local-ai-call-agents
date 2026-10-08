"""Latency probe: joins a LiveKit room as a caller, speaks WAV files like a person, and measures
how fast the agent answers (end of speech -> first audio).

  LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... python latency_probe.py question1.wav [question2.wav ...]

The key and secret are the voice engine's (see voice-engine.secret in the app's data folder).
"""
from __future__ import annotations

import asyncio
import os
import sys
import time
import wave

import numpy as np
from livekit import api, rtc

URL = os.environ.get("LIVEKIT_URL", "ws://127.0.0.1:7880")
KEY = os.environ["LIVEKIT_API_KEY"]
SECRET = os.environ["LIVEKIT_API_SECRET"]


def read_wav(path: str) -> tuple[np.ndarray, int]:
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16), w.getframerate()


async def main(files: list[str]) -> None:
    room = rtc.Room()
    token = (
        api.AccessToken(KEY, SECRET)
        .with_identity("test-caller")
        .with_grants(api.VideoGrants(room_join=True, room=os.environ.get("ROOM", f"test-{int(time.time())}")))
        .to_jwt()
    )
    first_audio = asyncio.Event()
    marks = {"spoke_end": 0.0}
    results = []

    echo_level = float(os.environ.get("ECHO", "0"))  # play the agent back into our mic, like speakers
    echo: list[np.ndarray] = []

    async def watch_agent_audio(track: rtc.Track) -> None:
        stream = rtc.AudioStream(track, sample_rate=16000, num_channels=1)
        async for ev in stream:
            pcm = np.frombuffer(ev.frame.data, dtype=np.int16)
            if echo_level:
                echo.append((time.monotonic(), (pcm.astype(np.float32) * echo_level).astype(np.int16)))
            if marks["spoke_end"] and not first_audio.is_set() and np.abs(pcm).mean() > 250:
                first_audio.set()

    @room.on("track_subscribed")
    def _sub(track, pub, participant):  # noqa: ANN001
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            asyncio.ensure_future(watch_agent_audio(track))

    transcripts: list[str] = []

    def on_text(reader: rtc.TextStreamReader, participant: str) -> None:
        async def read():
            text = await reader.read_all()
            final = reader.info.attributes.get("lk.transcription_final") == "true"
            who = "AGENT" if participant != "test-caller" else "YOU"
            if final and text.strip():
                transcripts.append(f"{who}: {text.strip()}")
        asyncio.ensure_future(read())

    room.register_text_stream_handler("lk.transcription", on_text)
    await room.connect(URL, token)
    source = rtc.AudioSource(16000, 1)
    track = rtc.LocalAudioTrack.create_audio_track("mic", source)
    await room.local_participant.publish_track(track, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE))

    clock = {"next": 0.0}

    async def pace() -> None:
        # Send like a real microphone: one 20 ms frame every 20 ms.
        now = time.monotonic()
        clock["next"] = max(clock["next"], now) + 0.02
        await asyncio.sleep(max(0.0, clock["next"] - now - 0.02))

    def take_echo(n: int) -> np.ndarray:
        # What the speakers played ~150 ms ago comes back into the mic (older sound is gone).
        out = np.zeros(n, np.int16)
        got = 0
        now = time.monotonic()
        while echo and echo[0][0] < now - 0.6:
            echo.pop(0)
        while echo and got < n and echo[0][0] <= now - 0.15:
            t, e = echo[0]
            k = min(n - got, len(e))
            out[got : got + k] = e[:k]
            got += k
            if k == len(e):
                echo.pop(0)
            else:
                echo[0] = (t, e[k:])
        return out

    async def silence(seconds: float) -> None:
        for _ in range(int(seconds * 50)):
            await pace()
            await source.capture_frame(rtc.AudioFrame(take_echo(320).tobytes(), 16000, 1, 320))

    async def speak(path: str) -> None:
        pcm, sr = read_wav(path)
        for i in range(0, len(pcm), 320):
            chunk = pcm[i : i + 320]
            if len(chunk) < 320:
                chunk = np.pad(chunk, (0, 320 - len(chunk)))
            await pace()
            mixed = np.clip(chunk.astype(np.int32) + take_echo(320), -32768, 32767).astype(np.int16)
            await source.capture_frame(rtc.AudioFrame(mixed.tobytes(), sr, 1, 320))

    await silence(6)  # agent joins, greets
    for f in files:
        pcm, sr = read_wav(f)
        first_audio.clear()
        marks["spoke_end"] = 0.0
        await speak(f)
        marks["spoke_end"] = time.monotonic()
        t0 = marks["spoke_end"]
        waiter = asyncio.create_task(first_audio.wait())
        while not waiter.done() and time.monotonic() - t0 < 25:
            await silence(0.1)
        latency = time.monotonic() - t0 if waiter.done() else None
        if os.environ.get("BARGE_IN") and waiter.done() and f == files[0]:
            # Talk over the agent, like a person cutting in.
            await silence(float(os.environ.get("BARGE_AFTER", "2")))
            print("BARGE-IN with", os.environ["BARGE_IN"])
            await speak(os.environ["BARGE_IN"])
        if os.environ.get("INTERRUPT_AFTER") and waiter.done():
            # Like the app's Interrupt button: stop the agent mid-answer.
            await silence(float(os.environ["INTERRUPT_AFTER"]))
            agent = next(p.identity for p in room.remote_participants.values() if p.identity.startswith("agent"))
            t_i = time.monotonic()
            print("INTERRUPT ->", await room.local_participant.perform_rpc(destination_identity=agent, method="ll.interrupt", payload=""), f"{(time.monotonic()-t_i)*1000:.0f} ms")
        results.append((os.path.basename(f), latency))
        await silence(float(os.environ.get("WAIT", "7")))  # let the agent finish speaking
    await room.disconnect()
    for line in transcripts:
        print("  " + line)
    for name, lat in results:
        print(f"RESULT {name}: first agent audio {'%.2f s' % lat if lat else 'NONE'} after end of speech")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
