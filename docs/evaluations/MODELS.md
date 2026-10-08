# Model comparison

The same quick set of spoken test calls (one of each kind of call for every business, about 70 calls), run with each assistant model in turn. The simulated callers always use the same model (Qwen3 4B), so only the assistant changes. Two calls run at a time on a MacBook Pro (M3 Pro, 18 GB) through Ollama.

- **Pass:** everything right, including speed.
- **Right:** the booking, order and answer were right (pass, or failed only for being slow).

| Model | Size | Calls | Pass | Right | Median answer | Slowest 10% | First words |
|---|---:|---:|---:|---:|---:|---:|---:|
| _results are added when the comparison run finishes_ | | | | | | | |

Run it yourself:

```bash
cd app
flutter build macos --debug
test/scenarios/bench_models.sh qwen3:4b-instruct llama3.2:3b phi4-mini gemma4:e2b qwen3:8b
python3 test/scenarios/bench_report.py
```

Not included:

- **Gemma 3 4B** doesn't support tool calling in Ollama.
- **Gemma 4 E4B** didn't fit on the test machine's disk.
