#!/bin/zsh
# Compares assistant models on the same test calls: for each model, the app runs the "bench" set
# (one single call of each kind for every business, 45 calls) with the same simulated callers.
#   test/scenarios/bench_models.sh qwen3:4b-instruct llama3.2:3b phi4-mini qwen3:8b
# Results: <app data>/test-runs/bench-<model>-*.jsonl ; summary: python3 test/scenarios/bench_report.py
APP="$(cd "$(dirname "$0")/../.." && pwd)/build/macos/Build/Products/Debug/LocalAILine.app"
DATA="$HOME/Library/Application Support/com.localailine.localailine"
ORIG=$(sqlite3 "$DATA/localailine.db" "select value from settings where key='llm.model'")
for model in "$@"; do
  tag=${model//[:\/]/_}
  pkill -x LocalAILine; sleep 3
  sqlite3 "$DATA/localailine.db" "update settings set value='$model' where key='llm.model'"
  ollama run "$model" "" --keepalive 0 >/dev/null 2>&1  # make sure it's downloaded
  open -n --env LOCALAILINE_RUN_SCENARIOS=bench@2 --env LOCALAILINE_RUN_ALL=1 --env LOCALAILINE_RUN_TAG="$tag" "$APP"
  echo "$(date +%H:%M) started $model"
  start=$(date +%s); idle=0
  sleep 300
  while :; do
    f=$(ls -t "$DATA"/test-runs/bench-$tag-*.jsonl 2>/dev/null | head -1)
    if [ -n "$f" ] && ! ls "$DATA"/test-runs/live-*.json >/dev/null 2>&1; then idle=$((idle+1)); else idle=0; fi
    [ $idle -ge 3 ] && break
    [ $(( $(date +%s) - start )) -gt 7200 ] && { echo "$model: timed out"; break; }
    sleep 60
  done
  echo "$(date +%H:%M) finished $model: $(wc -l < "$f") results"
done
pkill -x LocalAILine; sleep 3
sqlite3 "$DATA/localailine.db" "update settings set value='$ORIG' where key='llm.model'"
echo "restored model $ORIG"
