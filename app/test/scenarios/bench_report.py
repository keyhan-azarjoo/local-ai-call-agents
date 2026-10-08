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
print(f"{'model':<22}{'calls':>6}{'passed':>8}{'pass %':>8}{'not slow %':>11}   most common problems")
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
    print(f"{tag:<22}{len(rs):>6}{ok:>8}{100*ok/max(1,len(rs)):>7.0f}%{100*correct/max(1,len(rs)):>10.0f}%   " + '; '.join(f'{k.strip()} ×{v}' for k, v in c.most_common(3)))
