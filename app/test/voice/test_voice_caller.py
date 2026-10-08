"""Unit tests for the real-voice test caller's pure parts (no LiveKit, no servers).

  python3 -m unittest app/test/voice/test_voice_caller.py      (needs numpy; the engine's venv has it)
"""

from __future__ import annotations

import io
import json
import random
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "assets/engine"))
sys.path.insert(0, str(HERE))

import run_voice_tests as runner  # noqa: E402
import voice_caller as vc  # noqa: E402


def tone(seconds: float, sr: int = 16000, db: float = -20.0, hz: float = 220.0) -> np.ndarray:
    t = np.arange(int(sr * seconds)) / sr
    amp = 10 ** (db / 20) * 32767 * np.sqrt(2)
    return (np.sin(2 * np.pi * hz * t) * amp).astype(np.int16)


def silence(seconds: float, sr: int = 16000) -> np.ndarray:
    return np.zeros(int(sr * seconds), dtype=np.int16)


def run_detector(det: vc.SilenceDetector, pcm: np.ndarray, sr: int = 16000, frame_s: float = 0.02) -> list[tuple[str, float]]:
    n = int(sr * frame_s)
    events = []
    for i in range(0, len(pcm) - n + 1, n):
        events += det.feed(pcm[i:i + n], sr, i / sr)
    return events


class AudioTests(unittest.TestCase):
    def test_wav_roundtrip(self):
        pcm = tone(0.5)
        data = vc.wav_bytes(pcm, 16000)
        with wave.open(io.BytesIO(data)) as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (1, 2, 16000))
            back = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
        np.testing.assert_array_equal(back, pcm)

    def test_resample_length_and_shape(self):
        pcm = tone(1.0, 24000)
        out = vc.resample(pcm, 24000, 48000)
        self.assertEqual(len(out), 48000)
        self.assertEqual(out.dtype, np.int16)
        self.assertEqual(len(vc.resample(pcm, 24000, 16000)), 16000)
        self.assertIs(vc.resample(pcm, 16000, 16000).dtype, np.dtype(np.int16))

    def test_rms_db(self):
        self.assertEqual(vc.rms_db(silence(0.1)), -100.0)
        self.assertAlmostEqual(vc.rms_db(tone(0.5, db=-20)), -20, delta=0.5)

    def test_detector_finds_speech_and_silence(self):
        pcm = np.concatenate([silence(1.0), tone(1.5), silence(1.0), tone(0.5), silence(1.0)])
        events = run_detector(vc.SilenceDetector(hangover_s=0.5), pcm)
        kinds = [k for k, _ in events]
        self.assertEqual(kinds, ["start", "end", "start", "end"])
        self.assertAlmostEqual(events[0][1], 1.0, delta=0.03)
        self.assertAlmostEqual(events[1][1], 2.5, delta=0.03)
        self.assertAlmostEqual(events[2][1], 3.5, delta=0.03)

    def test_detector_bridges_short_pauses(self):
        pcm = np.concatenate([tone(0.8), silence(0.3), tone(0.8), silence(1.0)])
        kinds = [k for k, _ in run_detector(vc.SilenceDetector(hangover_s=0.5), pcm)]
        self.assertEqual(kinds, ["start", "end"])

    def test_detector_ignores_clicks_and_quiet_noise(self):
        rng = np.random.default_rng(0)
        noise = (rng.standard_normal(16000 * 2) * 30).astype(np.int16)  # about -60 dBFS
        pcm = np.concatenate([noise, tone(0.02), noise])
        self.assertEqual(run_detector(vc.SilenceDetector(min_speech_s=0.08), pcm), [])

    def test_detector_adapts_to_background(self):
        rng = np.random.default_rng(1)
        hum = (rng.standard_normal(16000 * 3) * 400).astype(np.int16)  # about -38 dBFS ambience
        det = vc.SilenceDetector(threshold_db=-45)
        run_detector(det, hum)
        self.assertGreater(det.threshold(), -38)
        events = run_detector(det, np.concatenate([tone(1.0, db=-12) + hum[:16000], hum[:16000]]))
        self.assertEqual([k for k, _ in events][:1], ["start"])

    def test_compress_silences(self):
        pcm = np.concatenate([tone(0.5), silence(3.0), tone(0.5)])
        out = vc.compress_silences(pcm, 16000, max_gap_s=0.5)
        self.assertLess(len(out), 16000 * 1.7)
        self.assertGreater(len(out), 16000 * 1.4)


class TextTests(unittest.TestCase):
    def test_clean_llm_line(self):
        self.assertEqual(vc.clean_llm_line('Caller: "Hi, table for two please." [END]'), ("Hi, table for two please.", True))
        self.assertEqual(vc.clean_llm_line("<think>hmm</think>(sighs) Yes, Friday."), ("Yes, Friday.", False))

    def test_goodbye(self):
        for t in ["Okay, goodbye!", "Thanks for calling, have a nice day.", "Adiós, gracias", "Merci, au revoir", "خداحافظ", "مع السلامة"]:
            self.assertTrue(vc.is_goodbye(t), t)
        self.assertFalse(vc.is_goodbye("Can I book a table?"))

    def test_filler(self):
        for t in ["One moment, let me check that.", "Right, let me do that.", "Okay, on it.", "Un momento.", "یک لحظه."]:
            self.assertTrue(vc.is_filler(t), t)
        for t in ["Yes, we have several vegetarian options.", "Sure, what time?", "", "[BLANK_AUDIO]"]:
            self.assertFalse(vc.is_filler(t), t)

    def test_script_lang(self):
        self.assertEqual(vc.script_lang("سلام، می‌خواستم یک میز رزرو کنم"), "fa")
        self.assertEqual(vc.script_lang("أريد حجز غرفة"), "ar")
        self.assertEqual(vc.script_lang("予約したいです"), "ja")
        self.assertEqual(vc.script_lang("我想预订"), "zh")
        self.assertIsNone(vc.script_lang("Hello there"))

    def test_whisper_tags_and_garbled(self):
        self.assertEqual(vc.strip_whisper_tags("[BLANK_AUDIO] Hello (music) there *typing*"), "Hello there")
        self.assertTrue(vc.garbled("[BLANK_AUDIO]"))
        self.assertTrue(vc.garbled("... - !"))
        self.assertFalse(vc.garbled("Sure, Friday at seven."))

    def test_mumble_cuts_and_fills(self):
        line = "I would like to book a haircut with Marco this Saturday at ten"
        m = vc.mumble(line, random.Random(3))
        self.assertTrue(m.endswith("..."))
        self.assertLess(len([w for w in m.split() if w not in ("uh,", "um,", "er,", "hmm,")]), len(line.split()))

    def test_schedule_tactics(self):
        self.assertEqual(vc.schedule_tactics(["change_mind", "silence", "bogus", "ramble"], 10), {1: "change_mind", 3: "silence", 5: "ramble"})
        self.assertEqual(vc.schedule_tactics({"2": "interrupt", "4": "nope"}, 10), {2: "interrupt"})
        self.assertEqual(vc.schedule_tactics(["a"], 10), {})
        # Not on the last turn (that one says goodbye).
        self.assertEqual(vc.schedule_tactics(["mumble", "silence", "ramble"], 4), {1: "mumble"})

    def test_caller_messages_roles(self):
        persona = {"name": "Sam", "goal": "Book", "facts": ["Party of 2"]}
        turns = [{"who": "agent", "text": "Hello, how can I help?"}, {"who": "caller", "text": "A table please."},
                 {"who": "agent", "text": "For how many?"}]
        msgs = vc.caller_messages(persona, turns, "Ask two things.", "en")
        self.assertEqual([m["role"] for m in msgs], ["system", "user", "assistant", "user"])
        self.assertIn("Party of 2", msgs[0]["content"])
        self.assertIn("Ask two things.", msgs[-1]["content"])
        first = vc.caller_messages(persona, [], None, "es")
        self.assertEqual(first[-1]["role"], "user")
        self.assertIn("Spanish", first[0]["content"])

    def test_fiction_numbers_only(self):
        self.assertTrue(vc.FICTION_NUMBER.match("+447700900123"))
        self.assertTrue(vc.FICTION_NUMBER.match("07700900123"))
        self.assertFalse(vc.FICTION_NUMBER.match("+447911123456"))

    def test_pick_voice(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            self.assertIsNone(vc.pick_voice("en", 0, piper_dir=d, kokoro_dir=d))
            (d / "kokoro-v1.0.onnx").write_bytes(b"x")
            self.assertTrue(vc.pick_voice("en", 0, piper_dir=d, kokoro_dir=d).startswith("kokoro:"))
            self.assertIsNone(vc.pick_voice("de", 0, piper_dir=d, kokoro_dir=d))
            (d / "de_DE-thorsten-medium.onnx").write_bytes(b"x")
            (d / "de_DE-thorsten-medium.onnx.json").write_bytes(b"{}")
            self.assertEqual(vc.pick_voice("de", 0, piper_dir=d, kokoro_dir=d), "de_DE-thorsten-medium")
            self.assertIsNone(vc.pick_voice("xx", 0, piper_dir=d, kokoro_dir=d))


def agent(text, first=1200, answer=3000, **kw):
    return {"who": "agent", "text": text, "first_audio_ms": first, "answer_ms": answer, "caller_language": kw.pop("lang", "en"), **kw}


def caller(text, **kw):
    return {"who": "caller", "text": text, **kw}


class AnalysisTests(unittest.TestCase):
    def test_good_call_passes(self):
        r = {"turns": [agent("Hi, thanks for calling. How can I help?", greeting=True), caller("A table for two tonight."),
                       agent("Sure, what time would you like?", 900, 2500), caller("Seven thirty, thanks. Bye!", ending=True),
                       agent("Booked for seven thirty. Goodbye!", 1100, 2600)], "end_reason": "caller_goodbye"}
        a = vc.analyze(r)
        self.assertTrue(a["pass"], a)
        self.assertEqual(a["latency"]["first_audio_avg_ms"], 1000)
        self.assertEqual(a["latency"]["first_audio_max_ms"], 1100)
        self.assertTrue(a["call_ended_properly"])

    def test_unanswered_and_notes_ignored(self):
        r = {"turns": [agent("Hello?", greeting=True), caller("Book a table."), {"who": "note", "text": "no answer"},
                       caller("Hello? Are you there?"), agent("Sorry, yes. How many?")]}
        a = vc.analyze(r)
        self.assertEqual(a["unanswered_caller_turns"], [1])
        self.assertFalse(a["pass"])

    def test_silence_turn_needs_no_answer(self):
        r = {"turns": [agent("Hello, how can I help?", greeting=True), caller("Hi, a table please."), agent("For how many people?"),
                       caller("", tactic="silence"), caller("Two people."), agent("Great, two people.")]}
        self.assertEqual(vc.analyze(r)["unanswered_caller_turns"], [])

    def test_repeats(self):
        same = "I can help you book a table, what day would you like to come in?"
        r = {"turns": [agent("Hello there, how can I help today?"), caller("a"), agent(same), caller("b"), agent(same), caller("c"), agent(same + " Thanks.")]}
        a = vc.analyze(r)
        self.assertEqual(len(a["repeats"]), 2)
        self.assertIn("repeated itself 2 times", " ".join(a["issues"]))

    def test_wrong_language(self):
        r = {"turns": [caller("Hola, quiero una mesa."), agent("Sure, for how many people would that be?", language="en", language_prob=0.97, lang="es"),
                       caller("Dos."), agent("Perfecto, dos personas.", language="es", language_prob=0.95, lang="es"),
                       caller("سلام"), agent("سلام، چطور می‌توانم کمک کنم؟", lang="fa")]}
        a = vc.analyze(r)
        self.assertEqual(len(a["wrong_language"]), 1)
        self.assertEqual(a["wrong_language"][0]["got"], "en")

    def test_markup_and_garbled(self):
        r = {"turns": [caller("I want to talk to Sam."), agent("Passing you to Sam.", published="Passing you to Sam. [transfer:Sam|wants Sam]"),
                       caller("Hello?"), agent("[BLANK_AUDIO]"), caller("Hello??"), agent("..."), caller("ok"), agent("Open bracket voice colon")]}
        a = vc.analyze(r)
        self.assertEqual(len(a["markup"]), 2)
        self.assertEqual(len(a["empty_or_garbled"]), 2)
        self.assertFalse(a["pass"])

    def test_filler_only_answer(self):
        r = {"turns": [agent("Hello, how can I help?", greeting=True), caller("Do you deliver to Elm Road?"), agent("Let me check that for you."),
                       caller("Hello?"), agent("Yes, we deliver there.")]}
        a = vc.analyze(r)
        self.assertEqual(a["filler_only"], [1])
        self.assertFalse(a["pass"])

    def test_slow_and_never_spoke(self):
        a = vc.analyze({"turns": [caller("Hi"), agent("Hello there, sorry for the wait.", 5000, 9000)]})
        self.assertIn("slow first audio", " ".join(a["issues"]))
        b = vc.analyze({"turns": [caller("Hi")]})
        self.assertIn("the agent never spoke", b["issues"])

    def test_interrupt_not_yielding_is_a_warning(self):
        r = {"turns": [agent("Hello, how can I help?", greeting=True), caller("A haircut please."), agent("Sure, we have", partial=True),
                       caller("Sorry, with Marco!", tactic="interrupt", agent_yielded=False), agent("With Marco, of course.")]}
        a = vc.analyze(r)
        self.assertIn("did not stop talking when interrupted", a["warnings"])
        self.assertEqual(a["unanswered_caller_turns"], [])


class RunnerTests(unittest.TestCase):
    def test_personas_file(self):
        personas = runner.load_personas(HERE / "personas.json")
        self.assertGreaterEqual(len(personas), 12)
        ids = [p["id"] for p in personas]
        self.assertEqual(len(ids), len(set(ids)))
        langs = {p["language"] for p in personas}
        self.assertTrue({"en", "es", "fr", "it", "de", "fa", "ar", "pt", "ja"} <= langs)
        used = set()
        for p in personas:
            t = p.get("tactics") or []
            used |= set(t.values() if isinstance(t, dict) else t)
            for k in ("name", "goal", "facts", "language"):
                self.assertIn(k, p, p["id"])
            for f in p["facts"]:
                for n in __import__("re").findall(r"\b0\d{4} ?\d{6}\b", f):
                    self.assertTrue(vc.FICTION_NUMBER.match(n.replace(" ", "")), n)
        self.assertEqual(used - set(vc.TACTICS), set())
        self.assertEqual(set(vc.TACTICS) - used, set(), "every tactic is used by some persona")

    def test_report(self):
        good = {"persona": "a", "language": "en", "room": "pstn-in-0-_+447700900111_vt1", "end_reason": "caller_goodbye", "tactics_plan": {},
                "turns": [agent("Hello"), caller("Hi")], "analysis": {"pass": True, "issues": [], "warnings": [], "latency": {"first_audio_avg_ms": 900}}}
        bad = {"persona": "b", "language": "es", "room": "r2", "end_reason": "max_turns", "tactics_plan": {"1": "silence"},
               "turns": [caller("Hola"), {"who": "note", "text": "no answer within 30 s"}],
               "analysis": {"pass": False, "issues": ["the agent never spoke"], "warnings": [], "latency": {}}}
        skip = {"persona": "c", "language": "tr", "end_reason": "skipped", "skipped": "no caller voice installed for language 'tr'", "turns": []}
        md = runner.build_report([good, bad, skip])
        self.assertIn("3 calls: **1 passed**, **1 failed**, 1 skipped.", md)
        self.assertIn("| b | es | silence | FAIL |", md)
        self.assertIn("the agent never spoke", md)
        self.assertIn("- caller: Hola", md)
        self.assertIn("skipped", md)
        json.dumps([good, bad, skip])


if __name__ == "__main__":
    unittest.main()
