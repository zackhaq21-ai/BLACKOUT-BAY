#!/usr/bin/env bash
# Static checks + logic tests. Requires: luau-lsp, selene, luau, rojo on PATH
# and a Roblox API definitions file at $ROBLOX_DEFS (defaults to tools/globalTypes.d.luau).
set -uo pipefail
cd "$(dirname "$0")/.."
DEFS="${ROBLOX_DEFS:-tools/globalTypes.d.luau}"
if [ ! -f "$DEFS" ]; then
  echo "== fetching Roblox API definitions (luau-lsp 1.52.0)"
  curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.52.0/scripts/globalTypes.d.luau
fi
status=0
echo "== rojo sourcemap"
rojo sourcemap default.project.json -o sourcemap.json || status=1
echo "== luau-lsp analyze (type check against Roblox API)"
luau-lsp analyze --definitions "$DEFS" --sourcemap sourcemap.json --ignore "tests/**" --ignore "tools/**" src || status=1
echo "== selene lint"
selene src tests tools/run-tests.luau || status=1
echo "== logic tests (luau CLI)"
luau tools/run-tests.luau || status=1
if [ $status -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $status
