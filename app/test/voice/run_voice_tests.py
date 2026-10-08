"""Runs real-voice test calls (app/assets/engine/voice_caller.py) for a list of personas.

Each call is a real LiveKit room on the test line, answered by the running voice engine, so the
LocalAILine app must be running. Writes app/test/voice/out/<timestamp>.jsonl (one call per line)
and <timestamp>.md (a short report).

  python3 app/test/voice/run_voice_tests.py                    # all personas, one call at a time
  python3 app/test/voice/run_voice_tests.py --only en_clinic_injection,es_restaurant_delivery --parallel 2
"""

from __future__ import annotations

import argparse
import json
import queue
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
CALLER = HERE.parent.parent / "assets/engine/voice_caller.py"
ENGINE_PY = Path.home() / "Library/Application Support/com.localailine.localailine/engine/.venv/bin/python"


def load_personas(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    return data.get("personas", []) if isinstance(data, dict) else data


def short(text: str | None, n: int = 160) -> str:
    t = " ".join((text or "").split())
    return t if len(t) <= n else t[: n - 1] + "…"


def build_report(results: list[dict], title: str = "Voice test calls") -> str:
    """A short markdown report: totals, one row per call, then the failures with their turns."""
    passed = [r for r in results if r.get("end_reason") != "skipped" and (r.get("analysis") or {}).get("pass")]
    skipped = [r for r in results if r.get("end_reason") == "skipped" or r.get("error")]
    failed = [r for r in results if r not in passed and r not in skipped]
    lines = [f"# {title}", "", f"{len(results)} calls: **{len(passed)} passed**, **{len(failed)} failed**, {len(skipped)} skipped.", ""]
    firsts = [(r.get("analysis") or {}).get("latency", {}).get("first_audio_avg_ms") for r in results]
    firsts = [x for x in firsts if x]
    if firsts:
        lines += [f"Average first audio across calls: {int(sum(firsts) / len(firsts))} ms (worst call average {max(firsts)} ms).", ""]
    lines += ["| persona | lang | tactics | result | turns (caller/agent) | first audio avg / max ms | whole answer avg ms | ended | issues |",
              "|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        a = r.get("analysis") or {}
        lat = a.get("latency") or {}
        tactics = r.get("tactics_plan") or {}
        tac = ", ".join(tactics.values()) if isinstance(tactics, dict) else ""
        if r.get("end_reason") == "skipped" or r.get("error"):
            res = "skipped" if r.get("end_reason") == "skipped" else "error"
            lines.append(f"| {r.get('persona')} | {r.get('language', '')} | {tac} | {res} | | | | | {short(r.get('skipped') or r.get('error'), 120)} |")
            continue
        res = "PASS" if a.get("pass") else "FAIL"
        lines.append(f"| {r.get('persona')} | {r.get('language', '')} | {tac} | {res} | {a.get('caller_turns', 0)}/{a.get('agent_turns', 0)} | "
                     f"{lat.get('first_audio_avg_ms') or '-'} / {lat.get('first_audio_max_ms') or '-'} | {lat.get('answer_avg_ms') or '-'} | "
                     f"{r.get('end_reason')}{' (agent hung up)' if r.get('agent_ended_call') else ''} | {short('; '.join(a.get('issues') or []), 160)} |")
    notable = [r for r in failed] + [r for r in passed if (r.get("analysis") or {}).get("warnings")]
    if notable:
        lines += ["", "## Notable", ""]
    for r in notable:
        a = r.get("analysis") or {}
        lines += [f"### {r.get('persona')} ({r.get('language')}) — {'FAIL' if r in failed else 'warnings'}", "",
                  f"Room `{r.get('room')}`. Issues: {'; '.join(a.get('issues') or []) or 'none'}. Warnings: {'; '.join(a.get('warnings') or []) or 'none'}.", ""]
        for t in r.get("turns") or []:
            if t.get("who") == "note":
                lines.append(f"- _note: {t.get('text')}_")
            elif t.get("who") == "agent":
                lat = f" ({t.get('first_audio_ms')} ms)" if t.get("first_audio_ms") is not None else ""
                lines.append(f"- **agent**{lat}: {short(t.get('text'), 240) or '(nothing heard)'}")
            else:
                tag = f" [{t.get('tactic')}]" if t.get("tactic") else ""
                who = "owner" if t.get("owner") else "caller"
                lines.append(f"- {who}{tag}: {short(t.get('text'), 240) or '(silence)'}")
        for w in a.get("wrong_language") or []:
            lines.append(f"- wrong language: wanted {w['want']}, heard {w['got']}: {short(w['text'], 100)}")
        lines.append("")
    return "\n".join(lines) + "\n"


# The ready-made businesses the test runs set up (Calls → Tests), by the personas' "business".
BUSINESSES = {"restaurant": "Trattoria Bella", "barber": "Kings Cut Barbers", "salon": "Studio Lumière", "clinic": "Riverside Dental",
              "hotel": "The Harbour House", "garage": "Precision Motors", "gym": "Forge Fitness", "shop": "Corner Store"}


def receptionist(business: str) -> int | None:
    """The receptionist of that business in the app's data, if it has been set up."""
    name = BUSINESSES.get(business)
    db = Path.home() / "Library/Application Support/com.localailine.localailine/localailine.db"
    if not name or not db.exists():
        return None
    import sqlite3
    with sqlite3.connect(f"file:{db}?mode=ro", uri=True) as c:
        row = c.execute("SELECT id FROM agents WHERE role = ? ORDER BY id DESC", (f"Receptionist · {name}",)).fetchone()
    return row[0] if row else None


def run_one(persona_file: Path, persona: dict, args, slot: int, log_lock: threading.Lock) -> dict:  # noqa: ANN001
    out = Path(tempfile.mkstemp(prefix="voicecall-", suffix=".json")[1])
    cmd = [str(args.python), str(CALLER), "--persona-file", str(persona_file), "--persona", persona["id"], "--out", str(out),
           "--max-turns", str(persona.get("max_turns", args.max_turns)), "--control-port", str(args.control_port + slot),
           "--max-seconds", str(args.max_seconds)]
    if args.caller_model:
        cmd += ["--caller-model", args.caller_model]
    agent = receptionist(persona.get("business", "")) if args.business_line else None
    if agent:
        cmd += ["--room-tag", f"ag{agent}"]  # the business's own receptionist answers, as on its own line
    started = time.time()
    with log_lock:
        print(f"[{persona['id']}] calling…", flush=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:  # type: ignore[union-attr]
        line = line.rstrip()
        # (The LiveKit SDK prints harmless tracebacks while shutting down.)
        if line.startswith(("ROOM", "  caller", "  agent", "  owner", "  >>>", "RESULT", "SKIPPED")):
            with log_lock:
                print(f"[{persona['id']}] {line}", flush=True)
    code = proc.wait()
    try:
        result = json.loads(out.read_text()) if out.stat().st_size else {}
    except (OSError, json.JSONDecodeError):
        result = {}
    out.unlink(missing_ok=True)
    if not result:
        result = {"persona": persona["id"], "language": persona.get("language"), "error": f"voice_caller exited with {code}", "turns": []}
    result["persona"] = persona["id"]
    result["business"] = persona.get("business")
    result["wall_s"] = round(time.time() - started, 1)
    return result


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--personas", default=str(HERE.parent.parent / "assets/engine/voice_personas.json"))
    p.add_argument("--only", help="comma-separated persona ids")
    p.add_argument("--languages", help="comma-separated languages to run (e.g. en,es)")
    p.add_argument("--parallel", type=int, choices=(1, 2), default=1, help="calls at the same time (keep it light: 1 or 2)")
    p.add_argument("--max-turns", type=int, default=8)
    p.add_argument("--max-seconds", type=float, default=300)
    p.add_argument("--caller-model")
    p.add_argument("--main-line", dest="business_line", action="store_false",
                   help="call the main assistant (by default each persona calls its business's receptionist)")
    p.add_argument("--control-port", type=int, default=8925, help="first call's control port (the second uses +1)")
    p.add_argument("--python", default=str(ENGINE_PY if ENGINE_PY.exists() else sys.executable))
    p.add_argument("--out-dir", default=str(HERE / "out"))
    args = p.parse_args(argv)

    persona_file = Path(args.personas)
    personas = load_personas(persona_file)
    if args.only:
        want = {x.strip() for x in args.only.split(",") if x.strip()}
        personas = [x for x in personas if x["id"] in want]
    if args.languages:
        langs = {x.strip() for x in args.languages.split(",") if x.strip()}
        personas = [x for x in personas if x.get("language") in langs]
    if not personas:
        print("no personas to run")
        return 2
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    jsonl, md = out_dir / f"{stamp}.jsonl", out_dir / f"{stamp}.md"
    lock = threading.Lock()
    results: list[dict] = []

    slots: queue.Queue[int] = queue.Queue()
    for s in range(args.parallel):
        slots.put(s)  # each running call gets its own control port

    def job(persona):  # noqa: ANN001, ANN202
        slot = slots.get()
        try:
            r = run_one(persona_file, persona, args, slot, lock)
        finally:
            slots.put(slot)
        with lock:
            results.append(r)
            with jsonl.open("a") as f:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        return r

    with ThreadPoolExecutor(max_workers=args.parallel) as ex:
        list(ex.map(job, personas))
    order = {x["id"]: i for i, x in enumerate(personas)}
    results.sort(key=lambda r: order.get(r.get("persona"), 99))
    md.write_text(build_report(results, f"Voice test calls {stamp}"))
    print(f"\nwrote {jsonl}\nwrote {md}")
    failed = [r for r in results if r.get("end_reason") != "skipped" and not (r.get("analysis") or {}).get("pass")]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
