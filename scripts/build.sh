#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SJASMPLUS="../tools/sjasmplus/build/sjasmplus"
mkdir -p build

python3 scripts/gen_sprites.py src/sprites.txt build/sprites.asm
"$SJASMPLUS" src/main.asm

echo "Built build/game.sna"
