"""Automated test caller: joins a LiveKit room, speaks WAV files like a person,
and measures how fast the agent answers (end of speech → first audio).

  python test_call.py question1.wav [question2.wav …]
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
KEY = os.environ.get("LIVEKIT_API_KEY", "devkey")
SECRET = os.environ.get("LIVEKIT_API_SECRET", "secret")


def read_wav(path: str) -> tuple[np.ndarray, int]:
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16), w.getframerate()


async def main(files: list[str]) -> None:
    room = rtc.Room()
    token = (
        api.AccessToken(KEY, SECRET)
        .with_identity("test-caller")
        .with_grants(api.VideoGrants(room_join=True, room=f"test-{int(time.time())}"))
        .to_jwt()
    )
    first_audio = asyncio.Event()
    marks = {"spoke_end": 0.0}
    results = []

    async def watch_agent_audio(track: rtc.Track) -> None:
        stream = rtc.AudioStream(track)
        async for ev in stream:
            pcm = np.frombuffer(ev.frame.data, dtype=np.int16)
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

    async def silence(seconds: float) -> None:
        frame = rtc.AudioFrame(b"\0" * 320 * 2, 16000, 1, 320)
        for _ in range(int(seconds * 50)):
            await source.capture_frame(frame)

    await silence(6)  # agent joins, greets
    for f in files:
        pcm, sr = read_wav(f)
        first_audio.clear()
        marks["spoke_end"] = 0.0
        for i in range(0, len(pcm), 320):
            chunk = pcm[i : i + 320]
            if len(chunk) < 320:
                chunk = np.pad(chunk, (0, 320 - len(chunk)))
            await source.capture_frame(rtc.AudioFrame(chunk.tobytes(), sr, 1, 320))
        marks["spoke_end"] = time.monotonic()
        t0 = marks["spoke_end"]
        waiter = asyncio.create_task(first_audio.wait())
        while not waiter.done() and time.monotonic() - t0 < 25:
            await silence(0.1)
        latency = time.monotonic() - t0 if waiter.done() else None
        results.append((os.path.basename(f), latency))
        await silence(7)  # let the agent finish speaking
    await room.disconnect()
    for line in transcripts:
        print("  " + line)
    for name, lat in results:
        print(f"RESULT {name}: first agent audio {'%.2f s' % lat if lat else 'NONE'} after end of speech")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
