"""What the voice agent says and hears: phone numbers said digit by digit, prices in words, and
times as speech recognition writes them ("7, 30pm") read as 7:30 pm. Found on voice test calls.

Read straight from assets/engine/localailine_voice.py, so this runs with any Python 3:
    python3 -m unittest discover -s app/test/engine
"""
from __future__ import annotations

import ast
import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2] / "assets" / "engine" / "localailine_voice.py"
WANTED = {"_MONEY", "_MONEY_NAMES", "_PHONE", "_HEARD_TIME", "speakable", "phone_digits", "tidy_heard"}


def _load() -> dict:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    body = [n for n in tree.body if (isinstance(n, ast.FunctionDef) and n.name in WANTED)
            or (isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in WANTED for t in n.targets))]
    ns: dict = {"re": re}
    exec(compile(ast.Module(body=body, type_ignores=[]), str(SOURCE), "exec"), ns)  # noqa: S102
    missing = WANTED - ns.keys()
    assert not missing, f"not found in localailine_voice.py: {missing}"
    return ns


V = _load()


class Speakable(unittest.TestCase):
    def test_phone_numbers_digit_by_digit(self) -> None:
        # (As one number, "900123" was heard back as "900 1123".)
        self.assertEqual(V["speakable"]("Phone number is 07700 900123."), "Phone number is 0 7 7 0 0, 9 0 0, 1 2 3.")
        self.assertEqual(V["speakable"]("07700900123"), "0 7 7 0 0, 9 0 0, 1 2 3")
        self.assertEqual(V["speakable"]("Call +447700900258"), "Call plus 4 4, 7 7 0 0, 9 0 0, 2 5 8")

    def test_other_numbers_stay(self) -> None:
        self.assertEqual(V["speakable"]("It is £21.50 for 2 people"), "It is 21 pounds 50 for 2 people")
        self.assertEqual(V["speakable"]("Room 101 in 2026, at 7:30 pm"), "Room 101 in 2026, at 7:30 pm")


class Heard(unittest.TestCase):
    def test_times_as_recognised(self) -> None:
        self.assertEqual(V["tidy_heard"]("it's 7, 30pm, not 7pm"), "it's 7:30 pm, not 7pm")
        self.assertEqual(V["tidy_heard"]("at 7 30 p.m. tonight"), "at 7:30 pm tonight")
        self.assertEqual(V["tidy_heard"]("7.30pm please"), "7:30 pm please")

    def test_not_times(self) -> None:
        self.assertEqual(V["tidy_heard"]("table for 2, 30 people"), "table for 2, 30 people")
        self.assertEqual(V["tidy_heard"]("£7.30 each"), "£7.30 each")


if __name__ == "__main__":
    unittest.main()
