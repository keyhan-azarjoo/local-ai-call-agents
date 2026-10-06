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
