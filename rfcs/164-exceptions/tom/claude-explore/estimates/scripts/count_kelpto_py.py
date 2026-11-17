# /// script
# requires-python = ">=3.12"
# ///
"""Counts, per Kelpto benchmark task, calls of functions declared
`throws Bubble`, all calls in kelpto-md and kelpto-core, and exceptions
raised and caught, using sys.monitoring on the generated Python.

Usage: uv run count_kelpto_py.py KELPTO_MD_SRC,KELPTO_CORE_SRC PY_OUT_DIR FILE.md...
"""
import re
import sys
import time
from collections import Counter
from pathlib import Path

srcs, out = [Path(p) for p in sys.argv[1].split(",")], Path(sys.argv[2])


def snake(name: str) -> str:
    return re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()


# (class or "", snake name) of each `throws Bubble` declaration.
bubbling: set[tuple[str, str]] = set()
for path in sorted(p for src in srcs for p in src.glob("*.temper.md")):
    if path.name.endswith("-tests.temper.md"):
        continue
    cls = ""
    text = path.read_text()
    # Join declarations split across lines up to the `{`.
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = re.match(r"^    (?:export )?(?:sealed )?(?:class|interface) (\w+)", line)
        if m:
            cls = m.group(1)
        elif re.match(r"^    (?:export )?let ", line):
            cls = ""
        joined = line
        j = i
        while "{" not in joined and j + 1 < len(lines) and j - i < 8:
            j += 1
            joined += lines[j]
        if "throws Bubble" not in joined.split("{")[0]:
            continue
        m = re.match(r"^\s*(?:export |public |private |protected |static |override |let )+(\w+)\s*\(", line)
        if not m or m.group(1) in ("if", "while", "for", "when"):
            continue
        indent = len(line) - len(line.lstrip())
        bubbling.add((cls if indent > 4 else "", snake(m.group(1))))


for lib in ("kelpto-md", "kelpto-core", "temper-core", "std"):
    sys.path.insert(0, str(out / lib))
import kelpto_md, kelpto_core  # noqa: E402
from kelpto_md import Heading, MarkdownParser, MarkdownRenderer  # noqa: E402
libfiles = {str(Path(m.__file__).parent / (m.__name__ + ".py")) for m in (kelpto_md, kelpto_core)}
mon = sys.monitoring
TOOL = 3
mon.use_tool_id(TOOL, "count")
calls = Counter(); bcalls = Counter(); ev = Counter()
def key(code):
    parts = code.co_qualname.split(".")
    return (parts[-2].lstrip("_") if len(parts) > 1 else ""), parts[-1].lstrip("_")
def on_start(code, offset):
    if code.co_filename not in libfiles:
        return mon.DISABLE
    calls["all"] += 1
    k = key(code)
    if k in bubbling or ("", k[1]) in bubbling:
        bcalls[code.co_qualname] += 1; calls["bubbling"] += 1
def on_raise(code, offset, exc):
    if code.co_filename in libfiles: ev["raise " + type(exc).__name__] += 1
def on_handled(code, offset, exc):
    if code.co_filename in libfiles: ev["handled " + type(exc).__name__] += 1
mon.register_callback(TOOL, mon.events.PY_START, on_start)
mon.register_callback(TOOL, mon.events.RAISE, on_raise)
mon.register_callback(TOOL, mon.events.EXCEPTION_HANDLED, on_handled)
parser = MarkdownParser.common_mark
renderer = MarkdownRenderer().with_raw_html_trusted()
def transform(text):
    doc = parser.parse(text); editor = doc.editor()
    for h in doc.headings:
        if h.level < 6 and not (h.level == 2 and h.style == "setext"):
            editor.set_level(h, h.level + 1)
    return len(editor.to_document().as_written)
tasks = {"parse": lambda t: parser.parse(t).span.end, "render": lambda t: len(renderer.render(parser.parse(t))), "transform": transform}
for f in sys.argv[3:]:
    text = Path(f).read_text()
    for name, fn in tasks.items():
        calls.clear(); bcalls.clear(); ev.clear()
        mon.set_events(TOOL, mon.events.PY_START | mon.events.RAISE | mon.events.EXCEPTION_HANDLED)
        fn(text)
        mon.set_events(TOOL, 0); mon.restart_events()
        t0 = time.perf_counter(); fn(text); t = time.perf_counter() - t0
        print(f"{Path(f).name} {name}: {t*1e3:.0f} ms; calls {calls['all']}, bubbling-function calls {calls['bubbling']}; {dict(ev)}")
        if name == "transform":
            for k, v in bcalls.most_common(10): print(f"    {v:5d} {k}")
print(f"({len(bubbling)} bubbling declarations matched by name)")
