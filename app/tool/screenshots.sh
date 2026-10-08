#!/bin/sh
# Makes the README pictures in docs/screenshots: the desktop app (drawn by Flutter with the app's
# own fonts) and the business websites and manager pages (photographed with headless Chrome).
# Demo data only, in temporary databases: nothing is called, your LocalAILine data and Ollama are
# not touched. Needs Flutter, Google Chrome, Node 22+, Python 3 with Pillow (or pngquant), internet.
#   app/tool/screenshots.sh [output folder]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-../docs/screenshots}"
if [ -z "$FLUTTER_ROOT" ]; then
  FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
  export FLUTTER_ROOT
fi
mkdir -p "$OUT"
# (OLLAMA_MODELS: no Ollama models on this computer are listed in the pictures.)
OLLAMA_MODELS=/nonexistent SHOTS="$OUT" flutter test test/screenshots_test.dart
SHOTS="$OUT" flutter test test/screenshots_sites_test.dart
python3 tool/shrink_png.py "$OUT"
ls -l "$OUT"
