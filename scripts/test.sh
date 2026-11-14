#!/usr/bin/env bash
# Runs every test: Lua syntax, Lua tests (LuaJIT with a fake WoW API) and Python tests.
set -euo pipefail
cd "$(dirname "$0")/.."
for f in Lorestar/*.lua tests/*.lua; do luajit -bl "$f" >/dev/null; done
echo "lua syntax: ok"
fail=0
for t in tests/test_*.lua; do
  echo "== $t"
  luajit "$t" || fail=1
done
echo "== python"
python3 -I -m unittest discover -s tests -p 'test_*.py' || fail=1
exit $fail
