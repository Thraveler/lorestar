#!/usr/bin/env bash
# Usage: scripts/new-run.sh <path/to/Lorestar.lua SavedVariables> [label]
# Stores one in-game run under data/runs/<date>-<label>/ (git-ignored), checks it for private data,
# parses it to parsed.json and loads it into data/lorestar.db.
# A run never overwrites an earlier one: a second run with the same date and label gets a -2, -3... suffix.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?path to SavedVariables Lorestar.lua}"
LABEL="${2:-$(grep -m1 '^## Version:' Lorestar/Lorestar.toc | awk '{print "v"$3}')}"
BASE="data/runs/$(date +%Y-%m-%d)-${LABEL}"
DIR="$BASE"
n=2
while [ -e "$DIR" ]; do DIR="${BASE}-${n}"; n=$((n + 1)); done
mkdir -p "$DIR"
cp "$SRC" "$DIR/SavedVariables.lua"
if ! python3 -I tools/privacy_scan.py "$DIR/SavedVariables.lua"; then
  echo "Not ingested: the dump contains private data. Inspect $DIR/SavedVariables.lua, then run /lorestar clear in game and collect again." >&2
  exit 1
fi
python3 -I tools/analyze.py "$DIR/SavedVariables.lua" "$DIR/parsed.json"
python3 -I tools/ingest.py "$DIR"
echo "run stored in $DIR and loaded into data/lorestar.db"
