#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SJASMPLUS="../tools/sjasmplus/build/sjasmplus"
mkdir -p build

"$SJASMPLUS" src/main.asm

echo "Built build/game.sna"
