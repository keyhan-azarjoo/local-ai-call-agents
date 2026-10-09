"""Unit tests for the voice worker's plugin hook (LL_PLUGIN) and its Host (no LiveKit, no servers).

  python3 -m unittest app/test/voice/test_voice_plugin.py      (needs the engine's venv: livekit-agents)
"""

from __future__ import annotations

import asyncio
import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

ENGINE = Path(__file__).resolve().parent.parent.parent / "assets/engine/localailine_voice.py"


def load_worker():  # noqa: ANN201
    spec = importlib.util.spec_from_file_location("localailine_voice_under_test", ENGINE)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


v = load_worker()


class FakeTTS(v.tts.TTS):
    def __init__(self) -> None:
        super().__init__(capabilities=v.tts.TTSCapabilities(streaming=False), sample_rate=24000, num_channels=1)

    def synthesize(self, text, *, conn_options=v.DEFAULT_API_CONNECT_OPTIONS):  # noqa: ANN001, ANN201
        raise NotImplementedError


class HostTests(unittest.TestCase):
    def test_from_env(self):
        env = {"LL_APP_URL": "http://127.0.0.1:7420", "LL_LLM_KEY": "k", "LL_LLM_BASE": "http://127.0.0.1:7420/v1"}
        with mock.patch.dict(os.environ, env):
            h = v.Host.from_env()
        self.assertEqual((h.url, h.token, h.llm_base), ("http://127.0.0.1:7420", "k", "http://127.0.0.1:7420/v1"))
        self.assertEqual(h.headers, {"Authorization": "Bearer k"})

    def test_from_env_defaults(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            h = v.Host.from_env()
        self.assertEqual((h.url, h.token, h.llm_base), ("", "", "http://127.0.0.1:11434/v1"))


class PluginTests(unittest.TestCase):
    def setUp(self):
        v._plugin_module = None
        self.addCleanup(setattr, v, "_plugin_module", None)
        self.addCleanup(sys.modules.pop, "fake_voice_plugin", None)

    def install(self, **fns) -> types.ModuleType:
        mod = types.ModuleType("fake_voice_plugin")
        for k, f in fns.items():
            setattr(mod, k, f)
        sys.modules["fake_voice_plugin"] = mod
        return mod

    def test_no_plugin(self):
        with mock.patch.dict(os.environ, {"LL_PLUGIN": ""}):
            self.assertIsNone(v.plugin())
            self.assertIsNone(v.plugin_call("host_for_job", "{}"))

    def test_functions_are_optional(self):
        self.install(make_stt=lambda host, lang, vocab: ("stt", host, lang, vocab))
        with mock.patch.dict(os.environ, {"LL_PLUGIN": "fake_voice_plugin"}):
            self.assertIsNone(v.plugin_call("host_for_job", "{}"))
            self.assertEqual(v.plugin_call("make_stt", "h", "en", "Marco"), ("stt", "h", "en", "Marco"))

    def test_host_for_job(self):
        host = v.Host(url="https://a.example", token="t", llm_base="https://a.example/v1")
        self.install(host_for_job=lambda metadata: host if metadata else None)
        with mock.patch.dict(os.environ, {"LL_PLUGIN": "fake_voice_plugin"}):
            self.assertIs(v.plugin_call("host_for_job", '{"x": 1}'), host)
            self.assertIsNone(v.plugin_call("host_for_job", ""))

    def test_plugin_sees_the_worker_by_its_package_name(self):
        self.install()
        saved = sys.modules.pop("localailine_voice", None)
        try:
            with mock.patch.dict(os.environ, {"LL_PLUGIN": "fake_voice_plugin"}):
                v.plugin()
            self.assertIs(sys.modules["localailine_voice"], v)
        finally:
            sys.modules.pop("localailine_voice", None)
            if saved is not None:
                sys.modules["localailine_voice"] = saved

    def test_missing_plugin_fails_loudly(self):
        with mock.patch.dict(os.environ, {"LL_PLUGIN": "no_such_voice_plugin_here"}):
            with self.assertRaises(ImportError):
                v.plugin()


class SessionTests(unittest.TestCase):
    def test_plugin_voice_and_host_are_used(self):
        async def run():
            host = v.Host(url="http://127.0.0.1:1", token="t", llm_base="http://127.0.0.1:1/v1")
            vad = v.silero.VAD.load(min_silence_duration=0.35)
            stt_ = v.WhisperStreamingSTT(vad=vad, language="en")
            voice = FakeTTS()
            with mock.patch.object(v, "MultilingualModel", lambda: "vad"):  # (needs a job to load)
                s = v.build_session(stt_, vad, "caller", host, phone_call=True, room="pstn-in-1-x", tts_=voice)
            return s, voice

        s, voice = asyncio.run(run())
        self.assertIs(s.tts, voice)
        self.assertIsInstance(s.llm, v.AppLLM)
        self.assertEqual(str(s.llm._client.base_url).rstrip("/"), "http://127.0.0.1:1/v1")


if __name__ == "__main__":
    unittest.main()
