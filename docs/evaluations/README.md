# Evaluations

- **[RUNS.md](RUNS.md)**: every spoken test-call run, with what it tested, how many passed and the median answer time. Each run links to its raw results in [runs/](runs/): one JSON line per scenario with every turn, tool call, timing, speech measurement and failure.
- **[MODELS.md](MODELS.md)**: the same test calls with different AI models.

To regenerate these from the app's data on your own computer:

```bash
cd app
python3 test/scenarios/export_results.py   # runs → docs/evaluations
python3 test/scenarios/bench_report.py     # model comparison table
python3 test/scenarios/report.py <run.jsonl>   # details of one run
```

## Reading a result line

```json
{"id": "restaurant-0042", "app": "restaurant", "intent": "book_table", "pass": false,
 "failures": ["time: expected \"19:00\", website has \"20:00\""],
 "calls": [{"turns": ["AI: Ciao, thanks for calling…", "CALLER: A table for four…"],
            "times": [{"ms": 4210, "first_ms": 650, "stages": {"reply": 3100, "save_on_yes": 900}}],
            "tools": ["check_reservations({…}) → Free tables at 19:00: …", "add_reservations({…}) → Done…"]}]}
```
