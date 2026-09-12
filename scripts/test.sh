#!/usr/bin/env bash
# Build the game, (re)load it into the running headless ZEsarUX, and grab a
# screenshot so a change can be verified without opening the emulator UI.
set -euo pipefail
cd "$(dirname "$0")/.."

PY="../.venv/bin/python"

./scripts/build.sh
$PY scripts/zx.py start
$PY scripts/zx.py load build/game.sna
sleep 0.5
$PY scripts/zx.py screenshot build/screenshot.png
