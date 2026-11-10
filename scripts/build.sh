#!/usr/bin/env bash
# Builds dist/Lorestar-v<version>.zip with a top-level Lorestar/ folder, ready to copy into Interface/AddOns/.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -m1 '^## Version:' Lorestar/Lorestar.toc | awk '{print $3}')
luajit -bl Lorestar/Lorestar.lua >/dev/null   # syntax check (LuaJIT ~ Lua 5.1)
mkdir -p dist
OUT="dist/Lorestar-v${VERSION}.zip"
rm -f "$OUT"
zip -qr "$OUT" Lorestar -x '*.DS_Store'
echo "built $OUT"
