#!/usr/bin/env python3
"""Summarises scenario results: pass rates by app, intent, agent set-up and caller style,
the most common failures, and a few failed calls in full.

python3 test/scenarios/report.py [results.jsonl] > report.md
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).with_name('out') / 'results.jsonl')
rows = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
if not rows:
    sys.exit('no results yet')


def kind(f):
    """A failure message without its particular names and numbers."""
    f = re.sub(r'^call \d+: ', '', f)
    f = re.sub(r'"[^"]*"', '"…"', f)
    f = re.sub(r'\d+', 'N', f)
    f = re.sub(r': .*', '', f) if f.startswith(('expected N new', 'caller', 'seeded record', 'FALSE CONFIRMATION', 'harness error')) else f
    return f[:110]


def table(title, key):
    g = defaultdict(lambda: [0, 0])
    for r in rows:
        g[r.get(key) or '-'][0] += 1
        g[r.get(key) or '-'][1] += bool(r['pass'])
    print(f'\n### By {title}\n\n| {title} | runs | passed | rate |\n|---|---:|---:|---:|')
    for k, (n, p) in sorted(g.items(), key=lambda e: e[1][1] / e[1][0]):
        print(f'| {k} | {n} | {p} | {100 * p / n:.0f}% |')


passed = sum(bool(r['pass']) for r in rows)
calls = sum(len([c for c in r.get('calls', []) if 'turns' in c]) for r in rows)
secs = sum(r.get('seconds', 0) for r in rows)
print(f'# Phone-call scenario results\n\n**{passed} of {len(rows)} scenarios passed ({100 * passed / len(rows):.0f}%)** — {calls} phone calls, '
      f'{secs / 3600:.1f} hours of calls.\n')
# How fast the AI answered (each AI reply: first words, and the whole answer).
first, total = [], []
for r in rows:
    for c in r.get('calls', []):
        for t in c.get('times', []) or []:
            if t.get('ms') is not None:
                total.append(t['ms'])
                first.append(t.get('first_ms', t['ms']))
if total:
    def pct(xs, p):
        xs = sorted(xs)
        return xs[min(len(xs) - 1, int(len(xs) * p))] / 1000
    slow = sum(1 for r in rows if any('SLOW' in f for f in r.get('failures', [])))
    print('### How fast the AI answers\n\n| | median | 90% under | slowest |\n|---|---:|---:|---:|')
    print(f'| first words heard | {pct(first, .5):.1f} s | {pct(first, .9):.1f} s | {max(first) / 1000:.1f} s |')
    print(f'| whole answer | {pct(total, .5):.1f} s | {pct(total, .9):.1f} s | {max(total) / 1000:.1f} s |')
    print(f'\n{len(total)} AI replies timed; {slow} scenarios had a reply slower than 5 s to first words or 25 s in all.\n')

# Calls at the same time vs one at a time: are the lines still fast together?
def speed(rs):
    ms = sorted(t['ms'] for r in rs for c in r.get('calls', []) for t in (c.get('times') or []) if t.get('ms') is not None)
    return (ms[len(ms) // 2] / 1000, ms[int(len(ms) * .9)] / 1000, len(ms)) if ms else None
par = [r for r in rows if r.get('parallel')]
if par:
    print('### Calls at the same time\n\n| | runs | passed | median answer | 90% under |\n|---|---:|---:|---:|---:|')
    for label, rs in [('one at a time', [r for r in rows if not r.get('parallel')])] + [(f'{n} at once', [r for r in par if r['parallel'] == n]) for n in sorted({r['parallel'] for r in par})]:
        sp = speed(rs)
        if rs and sp:
            print(f'| {label} | {len(rs)} | {sum(bool(r["pass"]) for r in rs)} | {sp[0]:.1f} s | {sp[1]:.1f} s |')
    print()

table('app', 'app')
table('intent', 'intent')
table('agent set-up', 'setup')
table('caller style', 'style')

fails = Counter(kind(f) for r in rows for f in r.get('failures', []))
print('\n### Most common failures\n\n| failure | count |\n|---|---:|')
for f, n in fails.most_common(25):
    print(f'| {f.replace("|", "/")} | {n} |')

print('\n### Examples of failed calls\n')
seen = set()
for r in rows:
    if r['pass'] or not r.get('failures'):
        continue
    k = kind(r['failures'][0])
    if k in seen:
        continue
    seen.add(k)
    print(f'**{r["id"]}** ({r["intent"]}, {r.get("setup")}/{r.get("style")}): {"; ".join(r["failures"])}\n')
    for c in r.get('calls', []):
        if 'turns' not in c:
            continue
        print('```')
        print('\n'.join(c['turns']))
        for t in c.get('tools', []):
            print('  tool: ' + t[:300])
        print('```')
    if len(seen) >= 12:
        break
