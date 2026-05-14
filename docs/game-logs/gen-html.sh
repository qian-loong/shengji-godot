#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

python "$REPO_ROOT/tools/export_game_log_html.py" \
  "$SCRIPT_DIR/game_log_latest.json" \
  -o "$SCRIPT_DIR/replay_latest.html"