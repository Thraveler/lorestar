#!/usr/bin/env bash
# Usage: scripts/new-run.sh <path/to/Lorestar.lua SavedVariables> [label]
# Stores one in-game run under data/runs/<date>-<label>/ (git-ignored) and parses it to parsed.json.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?path to SavedVariables Lorestar.lua}"
LABEL="${2:-$(grep -m1 '^## Version:' Lorestar/Lorestar.toc | awk '{print "v"$3}')}"
DIR="data/runs/$(date +%Y-%m-%d)-${LABEL}"
mkdir -p "$DIR"
cp "$SRC" "$DIR/SavedVariables.lua"
python3 -I tools/analyze.py "$DIR/SavedVariables.lua" "$DIR/parsed.json"
echo "run stored in $DIR"
