#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "Running convey.nvim tests..."
echo "========================================"

nvim --headless --noplugin -u "$REPO_DIR/tests/minimal_init.lua" \
    -c "PlenaryBustedDirectory $REPO_DIR/tests/unit/ { minimal_init = '$REPO_DIR/tests/minimal_init.lua' }"
