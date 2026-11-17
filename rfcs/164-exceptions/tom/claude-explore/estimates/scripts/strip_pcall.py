# /// script
# requires-python = ">=3.11"
# ///
"""Rewrites generated Lua so each `x = f() orelse panic()` runs without
its closure and pcall, for timing what those cost. Edits in place; run
it on a copy of temper.out/lua.

Usage: uv run strip_pcall.py FILE.lua...
"""
import re
import sys

PATTERN = re.compile(
    r'if not temper\.pcall\(function\(\)\n\s*([^\n]*)\n\s*end\) then\n\s*error\("panic"\)\n\s*end'
)
for path in sys.argv[1:]:
    with open(path) as f:
        text = f.read()
    text, n = PATTERN.subn(lambda m: m.group(1), text)
    with open(path, "w") as f:
        f.write(text)
    print(f"{path}: {n} rewritten")
