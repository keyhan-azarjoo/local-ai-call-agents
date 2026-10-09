"""The voice worker's "who takes the call" logic, without LiveKit or a network.

A line can ring the owner first (or be off): the app says so in /api/voice-config, and the worker
waits, silent, until the app says who took the call, the owner takes over in the room, the caller
hangs up, or the line's ring time is up. The functions are read straight from
assets/engine/localailine_voice.py (its imports need the voice engine's packages), so this runs
with any Python 3:

    python3 -m unittest app/test/voice/test_answer_wait.py
"""
from __future__ import annotations

import ast
import asyncio
import json
import logging
import time
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2] / "assets" / "engine" / "localailine_voice.py"
WANTED = {"ANSWER_GOES", "answer_plan", "wait_to_answer", "ringback_cadence",
          "TAKEOVER_TOPIC", "TAKEOVER_ATTRIBUTE", "OWNER_PREFIX", "_owner_name", "takeover_by", "takeover_by_attributes"}


def _load() -> dict:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    body = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in WANTED:
            body.append(node)
        elif isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in WANTED for t in node.targets):
            body.append(node)
    module = ast.Module(body=[ast.parse("from __future__ import annotations").body[0], *body], type_ignores=[])
    ns: dict = {"asyncio": asyncio, "json": json, "time": time, "log": logging.getLogger("test")}
    exec(compile(module, str(SOURCE), "exec"), ns)  # noqa: S102
    missing = WANTED - ns.keys()
    assert not missing, f"not found in localailine_voice.py: {missing}"
    return ns


V = _load()


class AnswerPlan(unittest.TestCase):
    def test_no_plan_means_answer_now(self) -> None:
        # (What every call got before lines had modes: the AI answers at once.)
        for cfg in [{}, None, {"answer": None}, {"answer": {}}, {"answer": {"wait": 0}}, {"answer": "soon"}, {"answer": {"wait": "x"}}]:
            self.assertIsNone(V["answer_plan"](cfg), cfg)

    def test_off(self) -> None:
        self.assertEqual(V["answer_plan"]({"answer": {"off": True}}), {"off": True})

    def test_ring_first(self) -> None:
        self.assertEqual(V["answer_plan"]({"answer": {"wait": 20, "then": "message"}}), {"wait": 20.0, "then": "message"})
        self.assertEqual(V["answer_plan"]({"answer": {"wait": 15, "then": "ai"}}), {"wait": 15.0, "then": "ai"})
        # Unknown "then": the AI answers. A silly wait is capped.
        self.assertEqual(V["answer_plan"]({"answer": {"wait": 9999, "then": "dance"}}), {"wait": 300.0, "then": "ai"})


def run(coro):  # noqa: ANN001, ANN201
    return asyncio.run(coro)


class Waiting(unittest.TestCase):
    def wait(self, plan: dict, ask_app, *, taken_after: float | None = None, gone_after: float | None = None, who: dict | None = None):  # noqa: ANN001, ANN201
        async def go():  # noqa: ANN202
            taken, gone = asyncio.Event(), asyncio.Event()
            loop = asyncio.get_running_loop()
            if taken_after is not None:
                loop.call_later(taken_after, taken.set)
            if gone_after is not None:
                loop.call_later(gone_after, gone.set)
            t0 = time.monotonic()
            out = await V["wait_to_answer"](plan, ask_app, taken, gone, who, grace=0.5)
            return out, time.monotonic() - t0
        return run(go())

    def test_released_early_by_the_app(self) -> None:
        # "Let the AI answer" on the computer, or "AI" chosen on a paired phone.
        async def app():  # noqa: ANN202
            await asyncio.sleep(0.05)
            return {"go": "ai"}
        out, took = self.wait({"wait": 5.0, "then": "message"}, app)
        self.assertEqual(out, {"go": "ai"})
        self.assertLess(took, 1.0)

    def test_answered_on_a_paired_phone(self) -> None:
        async def app():  # noqa: ANN202
            return {"go": "person", "by": "Sam's iPhone"}
        out, _ = self.wait({"wait": 5.0, "then": "ai"}, app)
        self.assertEqual(out["go"], "person")
        self.assertEqual(out["by"], "Sam's iPhone")

    def test_nobody_answers_then_a_message(self) -> None:
        # The app says so when the line's ring time is up.
        async def app():  # noqa: ANN202
            await asyncio.sleep(0.2)
            return {"go": "message", "greeting": "Sorry, nobody can come to the phone."}
        out, _ = self.wait({"wait": 0.2, "then": "message"}, app)
        self.assertEqual(out["go"], "message")
        self.assertIn("nobody", out["greeting"])

    def test_the_app_cannot_be_reached(self) -> None:
        # Its time still counts: then what the line says ("then").
        async def app():  # noqa: ANN202
            raise ConnectionError("refused")
        out, took = self.wait({"wait": 0.3, "then": "ai"}, app)
        self.assertEqual(out, {"go": "ai"})
        self.assertGreaterEqual(took, 0.25)
        self.assertLess(took, 0.8)

    def test_the_app_never_answers(self) -> None:
        # A hung request: the worker's own clock (ring time + grace) decides.
        async def app():  # noqa: ANN202
            await asyncio.sleep(60)
        out, took = self.wait({"wait": 0.2, "then": "message"}, app)
        self.assertEqual(out, {"go": "message"})
        self.assertLess(took, 1.5)

    def test_a_strange_answer_is_not_trusted(self) -> None:
        async def app():  # noqa: ANN202
            return {"go": "launch"}
        out, _ = self.wait({"wait": 0.2, "then": "ai"}, app)
        self.assertEqual(out, {"go": "ai"})

    def test_owner_takes_over_in_the_room(self) -> None:
        async def app():  # noqa: ANN202
            await asyncio.sleep(60)
        out, took = self.wait({"wait": 5.0, "then": "ai"}, app, taken_after=0.05, who={"by": "Keyhan"})
        self.assertEqual(out, {"go": "owner", "by": "Keyhan"})
        self.assertLess(took, 1.0)

    def test_caller_hangs_up_while_ringing(self) -> None:
        async def app():  # noqa: ANN202
            await asyncio.sleep(60)
        out, took = self.wait({"wait": 5.0, "then": "message"}, app, gone_after=0.05)
        self.assertEqual(out, {"go": "gone"})
        self.assertLess(took, 1.0)

    def test_hanging_up_wins_over_everything(self) -> None:
        async def app():  # noqa: ANN202
            await asyncio.sleep(0.1)
            return {"go": "ai"}
        out, _ = self.wait({"wait": 5.0, "then": "ai"}, app, taken_after=0.1, gone_after=0.1)
        self.assertEqual(out["go"], "gone")

    def test_the_owners_takeover_message_is_recognised_while_ringing(self) -> None:
        # (The same message as taking over from the AI: so "Answer" on the computer is a take-over.)
        msg = json.dumps({"takeover": True, "by": "Keyhan"}).encode()
        self.assertEqual(V["takeover_by"](msg, "localailine", "owner-abc"), "Keyhan")
        self.assertIsNone(V["takeover_by"](msg, "localailine", "sip_+447700900123"))


class RingingTone(unittest.TestCase):
    def test_tones_by_the_callers_country(self) -> None:
        freqs, steps = V["ringback_cadence"]("+14155550100")
        self.assertEqual(freqs, (440.0, 480.0))
        self.assertEqual(steps, [(True, 2.0), (False, 4.0)])
        freqs, steps = V["ringback_cadence"]("+447700900123")
        self.assertEqual(freqs, (400.0, 450.0))
        self.assertEqual([on for on, _ in steps], [True, False, True, False])
        freqs, _ = V["ringback_cadence"]("+4930123456")
        self.assertEqual(freqs, (425.0,))
        # Withheld number: the common European tone.
        self.assertEqual(V["ringback_cadence"]("")[0], (425.0,))

    def test_every_cadence_rings_and_pauses(self) -> None:
        for n in ["+1", "+44", "+353", "+49", ""]:
            _, steps = V["ringback_cadence"](n)
            self.assertTrue(any(on for on, _ in steps) and any(not on for on, _ in steps))
            self.assertTrue(all(secs > 0 for _, secs in steps))


if __name__ == "__main__":
    unittest.main()
