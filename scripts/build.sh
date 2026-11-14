#!/usr/bin/env bash
# Builds dist/Lorestar-v<version>.zip with a top-level Lorestar/ folder, ready to copy into Interface/AddOns/.
# Needs bash and zip. LuaJIT is optional: when present it syntax-checks the Lua files first.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "build.sh needs 'zip' (not found). Install it, or download the zip from the GitHub release instead." >&2; exit 1; }

if command -v luajit >/dev/null 2>&1; then
  for f in Lorestar/*.lua; do luajit -bl "$f" >/dev/null; done   # syntax check (LuaJIT ~ Lua 5.1)
else
  echo "warning: luajit not found, skipping the Lua syntax check (CI runs it on every push)" >&2
fi

VERSION=$(grep -m1 '^## Version:' Lorestar/Lorestar.toc | awk '{print $3}')
mkdir -p dist
OUT="dist/Lorestar-v${VERSION}.zip"
rm -f "$OUT"
zip -qr "$OUT" Lorestar -x '*.DS_Store'
echo "built $OUT"
