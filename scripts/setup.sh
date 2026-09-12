#!/usr/bin/env bash
# One-time setup: builds sjasmplus from source and creates a venv for the
# ZRCP test scripts. Requires: git, cmake, a C++ toolchain (Xcode CLT),
# python3. ZEsarUX itself is NOT installed by this script - see README.md,
# since Homebrew's cask is currently disabled by Gatekeeper.
#
# Both live one directory above this repo (../tools, ../.venv) rather than
# inside it, so they don't end up nested inside the project's git repo
# (tools/sjasmplus is itself a git checkout, which git would otherwise see
# as an embedded repository).
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS_DIR="../tools"
VENV_DIR="../.venv"

if [ ! -x "$TOOLS_DIR/sjasmplus/build/sjasmplus" ]; then
  mkdir -p "$TOOLS_DIR"
  if [ ! -d "$TOOLS_DIR/sjasmplus" ]; then
    git clone --depth 1 --branch v1.24.0 https://github.com/z00m128/sjasmplus.git "$TOOLS_DIR/sjasmplus"
  fi
  (cd "$TOOLS_DIR/sjasmplus" && git submodule update --init --recursive)
  mkdir -p "$TOOLS_DIR/sjasmplus/build"
  (
    cd "$TOOLS_DIR/sjasmplus/build"
    # Workaround: this machine's CommandLineTools clang doesn't pick up
    # libc++ headers from the active SDK on its own (missing <cassert>
    # etc.), so point it at the SDK's c++/v1 directory explicitly.
    SDK="$(xcrun --show-sdk-path)"
    cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-isystem ${SDK}/usr/include/c++/v1"
    make -j"$(sysctl -n hw.ncpu)"
  )
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet Pillow
fi

echo "Setup complete."
echo "sjasmplus: $TOOLS_DIR/sjasmplus/build/sjasmplus"
echo "python venv: $VENV_DIR/bin/python"
