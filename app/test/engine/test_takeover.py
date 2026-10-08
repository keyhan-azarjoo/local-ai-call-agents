"""The voice agent's "owner takes over" messages, without LiveKit or a network.

The functions are read straight from assets/engine/localailine_voice.py (its imports need the
voice engine's packages), so this runs with any Python 3:
    python3 -m unittest discover -s app/test/engine
"""
from __future__ import annotations

import ast
import json
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2] / "assets" / "engine" / "localailine_voice.py"
WANTED = {"TAKEOVER_TOPIC", "TAKEOVER_ATTRIBUTE", "OWNER_PREFIX", "_owner_name", "takeover_by", "takeover_by_attributes", "handback_of", "is_app_listener"}


def _load() -> dict:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    body = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in WANTED:
            body.append(node)
        elif isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in WANTED for t in node.targets):
            body.append(node)
    module = ast.Module(body=[ast.parse("from __future__ import annotations").body[0], *body], type_ignores=[])
    ns: dict = {"json": json}
    exec(compile(module, str(SOURCE), "exec"), ns)  # noqa: S102
    missing = WANTED - ns.keys()
    assert not missing, f"not found in localailine_voice.py: {missing}"
    return ns


V = _load()


class TakeoverMessage(unittest.TestCase):
    def test_the_apps_message_names_the_owner(self) -> None:
        msg = json.dumps({"takeover": True, "by": "Keyhan"}).encode()
        self.assertEqual(V["takeover_by"](msg, "localailine", "owner-abc"), "Keyhan")
        self.assertEqual(V["takeover_by"](bytearray(msg), "localailine", "owner-abc"), "Keyhan")
        self.assertEqual(V["takeover_by"](memoryview(msg), "localailine", "owner-abc"), "Keyhan")
        self.assertEqual(V["takeover_by"](msg.decode(), "localailine", "owner-abc"), "Keyhan")

    def test_without_a_name_it_is_the_owner(self) -> None:
        for by in (None, "", "   ", 42):
            msg = json.dumps({"takeover": True, **({"by": by} if by is not None else {})}).encode()
            self.assertEqual(V["takeover_by"](msg, "localailine", "owner-1"), "the owner")
        self.assertEqual(len(V["takeover_by"](json.dumps({"takeover": True, "by": "x" * 500}).encode(), "localailine", "owner-1")), 60)

    def test_anything_else_is_ignored(self) -> None:
        good = json.dumps({"takeover": True, "by": "Keyhan"}).encode()
        self.assertIsNone(V["takeover_by"](good, "other-topic", "owner-1"))
        self.assertIsNone(V["takeover_by"](good, None, "owner-1"))
        # Only the owner's own app: not the caller, a listener or a person the call was passed to.
        for who in ("sip_+447700900123", "listen-1", "person-3-1", "", None):
            self.assertIsNone(V["takeover_by"](good, "localailine", who))
        for bad in (b"", b"not json", b"\xff\xfe", b"[]", b'"takeover"', b'{"takeover": "yes"}', b'{"takeover": 1}', b'{"takeover": false}', b'{"handback": true}'):
            self.assertIsNone(V["takeover_by"](bad, "localailine", "owner-1"), bad)


class TakeoverAttribute(unittest.TestCase):
    def test_attribute_set_by_the_owner(self) -> None:
        f = V["takeover_by_attributes"]
        self.assertEqual(f({"localailine.takeover": "Keyhan"}, "owner-1"), "Keyhan")
        self.assertEqual(f({"localailine.takeover": "1"}, "owner-1"), "the owner")
        self.assertEqual(f({"localailine.takeover": "true"}, "owner-1"), "the owner")

    def test_cleared_or_missing_or_not_the_owner(self) -> None:
        f = V["takeover_by_attributes"]
        for v in ("", " ", "0", "false", "no"):
            self.assertIsNone(f({"localailine.takeover": v}, "owner-1"))
        self.assertIsNone(f({}, "owner-1"))
        self.assertIsNone(f(None, "owner-1"))
        self.assertIsNone(f({"lk.agent.state": "speaking"}, "owner-1"))
        self.assertIsNone(f({"localailine.takeover": "Keyhan"}, "sip_+447700900123"))


class HandBack(unittest.TestCase):
    def test_job_metadata(self) -> None:
        f = V["handback_of"]
        self.assertEqual(f(json.dumps({"handback": True, "by": "Keyhan"})), "Keyhan")
        self.assertEqual(f(json.dumps({"handback": True})), "the owner")
        for m in ("", None, "{}", "nope", '{"handback": "yes"}', '{"takeover": true}', "[1]"):
            self.assertIsNone(f(m), m)

    def test_the_ai_talks_to_the_caller_not_the_owner(self) -> None:
        f = V["is_app_listener"]
        self.assertTrue(f("owner-abc"))
        self.assertTrue(f("listen-abc"))
        self.assertFalse(f("sip_+447700900123"))
        self.assertFalse(f("caller-vt"))
        self.assertFalse(f(None))


if __name__ == "__main__":
    unittest.main()
