#!/bin/bash
# Runs the Lua unit tests (policy.lua via lupa = real Lua 5.4) and the syntax check of all mod scripts.
set -e
cd "$(dirname "$0")/.."
V=tests/.venv
if [ ! -x "$V/bin/python" ]; then
  python3 -m venv "$V"
  "$V/bin/pip" install -q -r tests/requirements.txt
fi
exec "$V/bin/python" -m unittest discover -s tests -t . "$@"
