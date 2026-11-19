#!/bin/sh
# Run every check CI runs: syntax, static analysis, behaviour tests.
#
#   tests/run.sh            use `lua` / `luac` from PATH
#   LUA=lua5.2 tests/run.sh pick an interpreter (VLC 3 embeds Lua 5.2)
#
# luacheck is required in CI (REQUIRE_LUACHECK=1) and skipped with a warning
# locally when it is not installed.
set -eu

cd "$(dirname "$0")/.."

LUA="${LUA:-lua}"
LUAC="${LUAC:-$(echo "$LUA" | sed 's/lua/luac/')}"
SCRIPT=vlsubcom.lua

echo "==> Syntax ($LUAC -p)"
if command -v "$LUAC" >/dev/null 2>&1; then
  "$LUAC" -p "$SCRIPT"
else
  "$LUA" -e "assert(loadfile('$SCRIPT'))"
fi

echo "==> Static analysis (luacheck: undefined globals / functions)"
if command -v luacheck >/dev/null 2>&1; then
  luacheck "$SCRIPT"
elif [ "${REQUIRE_LUACHECK:-0}" = "1" ]; then
  echo "luacheck not found but REQUIRE_LUACHECK=1" >&2
  exit 1
else
  echo "WARNING: luacheck not installed - skipped (apt install lua-check / luarocks install luacheck)" >&2
fi

echo "==> Behaviour tests ($("$LUA" -v 2>&1 | head -1))"
"$LUA" tests/run_tests.lua
