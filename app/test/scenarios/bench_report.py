"""Model comparison: pass rate, how fast, and what goes wrong, per model (from bench-*.jsonl).

  python3 test/scenarios/bench_report.py
"""
import collections, glob, json, os, re

DATA = os.path.expanduser('~/Library/Application Support/com.localailine.localailine/test-runs')
rows = {}
for f in sorted(glob.glob(f'{DATA}/bench-*.jsonl')):
    tag = re.match(r'bench-(.+)-\d{4}-\d\d-\d\dT', os.path.basename(f)).group(1)
    for l in open(f):
        try:
            r = json.loads(l)
        except ValueError:
            continue
        rows.setdefault(tag, {})[r['id']] = r  # the latest result per scenario
def med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] / 1000 if xs else 0

# Only scenarios every model ran, so they're compared on the same calls (the "bench" set).
common = set.intersection(*[set(r) for r in rows.values()]) if rows else set()
rows = {tag: {i: r for i, r in rs.items() if i in common} for tag, rs in rows.items()}
print(f"Compared on the {len(common)} calls every model ran.")
print(f"{'model':<22}{'calls':>6}{'passed':>8}{'pass %':>8}{'right %':>9}{'answer s':>10}{'90% s':>8}{'first words s':>15}   most common problems")
for tag, rs in rows.items():
    rs = list(rs.values())
    ok = sum(1 for r in rs if r.get('pass'))
    # correctness without speed: passed, or only failed for being slow
    correct = sum(1 for r in rs if all('SLOW' in x for x in (r.get('failures') or [])))
    c = collections.Counter()
    for r in rs:
        for x in r.get('failures') or []:
            k = x.split(': ', 1)[1] if x.startswith('call ') else x
            c[re.sub(r'[\d"]+.*', '', k)[:40]] += 1
    turns = [t for r in rs for x in r.get('calls', []) for t in x.get('times', []) if t.get('ms')]
    ms = sorted(t['ms'] for t in turns)
    p90 = ms[int(len(ms) * .9)] / 1000 if ms else 0
    first = med([t['first_ms'] for t in turns if t.get('first_ms') is not None])
    print(f"{tag:<22}{len(rs):>6}{ok:>8}{100*ok/max(1,len(rs)):>7.0f}%{100*correct/max(1,len(rs)):>8.0f}%{med(ms):>10.1f}{p90:>8.1f}{first:>15.1f}   " + '; '.join(f'{k.strip()} ×{v}' for k, v in c.most_common(3)))
