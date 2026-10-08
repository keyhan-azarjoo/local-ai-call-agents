"""Copies the test-call results from this computer into docs/evaluations/runs/ (owner's personal
details replaced) and writes docs/evaluations/RUNS.md: every run, what it tested, how many passed.

  python3 test/scenarios/export_results.py
"""
import collections
import glob
import json
import os
import re
from pathlib import Path

SRC = os.path.expanduser('~/Library/Application Support/com.localailine.localailine/test-runs')
REPO = Path(__file__).resolve().parents[3]
OUT = REPO / 'docs' / 'evaluations' / 'runs'
OUT.mkdir(parents=True, exist_ok=True)

# The owner's own details (from early manual tests) never leave this computer.
PRIVATE = [
]


def clean(text: str) -> str:
    for rx, repl in PRIVATE:
        text = rx.sub(repl, text)
    return text


KIND = {'journey': 'Journeys (call-backs, teams, switching business)', 'challenge': 'Hard calls (long, tricky, other languages)',
        'security': 'Security (attackers trying to reach other people\'s data)'}

rows = []
for f in sorted(glob.glob(f'{SRC}/*.jsonl')):
    name = os.path.basename(f)
    lines = [l for l in open(f, encoding='utf-8') if l.strip()]
    if not lines:
        continue
    (OUT / name).write_text(clean(''.join(lines)), encoding='utf-8')
    results = []
    for l in lines:
        try:
            results.append(json.loads(l))
        except ValueError:
            pass
    kinds = collections.Counter(KIND.get(r['id'].split('-')[0], 'Single calls') for r in results)
    passed = sum(1 for r in results if r.get('pass'))
    turns = [t for r in results for c in r.get('calls', []) for t in c.get('times', []) if t.get('ms')]
    ms = sorted(t['ms'] for t in turns)
    med = f'{ms[len(ms) // 2] / 1000:.1f} s' if ms else '–'
    par = max((r.get('parallel') or 1) for r in results)
    when = re.search(r'(\d{4}-\d\d-\d\dT\d\d-\d\d)', name).group(1).replace('T', ' ').replace('-', ':', 4).replace(':', '-', 2)
    rows.append((name, when, ', '.join(k for k, _ in kinds.most_common()), len(results), passed, med, par))

md = ['# Test-call runs', '',
      'Every run of the spoken test calls (simulated callers speaking through text-to-speech, heard by the app\'s own speech recognition, '
      'answered by the AI, results checked against the business apps\' data). Raw results — every conversation, tool call, timing and '
      'failure — are in [runs/](runs/). Owner details from early manual tests are masked.', '',
      '| Run | Started | What | Calls | Passed | Median answer | Calls at once |', '|---|---|---|---:|---:|---:|---:|']
for name, when, kinds, n, p, med, par in rows:
    md.append(f'| [{name}](runs/{name}) | {when} | {kinds} | {n} | {p} ({100 * p // max(1, n)}%) | {med} | {par} |')
(REPO / 'docs' / 'evaluations' / 'RUNS.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
print(f'{len(rows)} runs exported to {OUT}')
