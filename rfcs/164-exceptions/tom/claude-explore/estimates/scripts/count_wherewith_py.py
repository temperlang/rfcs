# /// script
# requires-python = ">=3.12"
# ///
"""Counts, per Wherewith workload, calls of functions declared
`throws Bubble`, all calls in the library, and exceptions raised and
caught, using sys.monitoring on the generated Python.

Usage: uv run count_wherewith_py.py SRC_DIR PY_OUT_DIR [-v]
"""
import re
import sys
import time
from collections import Counter
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])


def snake(name: str) -> str:
    return re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()


# (class or "", snake name) of each `throws Bubble` declaration.
bubbling: set[tuple[str, str]] = set()
for path in sorted(src.glob("*.temper.md")):
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

sys.path[:0] = [str(out / "wherewith"), str(out / "temper-core"), str(out / "std")]
import wherewith  # noqa: E402
from wherewith import Dialect, PlaceholderStyle, QueryBuilder  # noqa: E402

libfile = str(Path(wherewith.__file__).parent / "wherewith.py")
mon = sys.monitoring
TOOL = 3
mon.use_tool_id(TOOL, "count")
calls: Counter = Counter()
bcalls: Counter = Counter()
ev = Counter()


def key(code):
    q = code.co_qualname
    parts = q.split(".")
    name = parts[-1].lstrip("_")
    cls = parts[-2].lstrip("_") if len(parts) > 1 else ""
    return cls, name


def on_start(code, offset):
    if code.co_filename != libfile:
        return mon.DISABLE
    calls["all"] += 1
    k = key(code)
    if k in bubbling or ("", k[1]) in bubbling:
        bcalls[code.co_qualname] += 1
        calls["bubbling"] += 1


def on_raise(code, offset, exc):
    if code.co_filename == libfile:
        ev["raise " + type(exc).__name__] += 1


def on_handled(code, offset, exc):
    if code.co_filename == libfile:
        ev["handled " + type(exc).__name__] += 1


def on_unwind(code, offset, exc):
    if code.co_filename == libfile:
        ev["unwind"] += 1


mon.register_callback(TOOL, mon.events.PY_START, on_start)
mon.register_callback(TOOL, mon.events.RAISE, on_raise)
mon.register_callback(TOOL, mon.events.EXCEPTION_HANDLED, on_handled)
mon.register_callback(TOOL, mon.events.PY_UNWIND, on_unwind)


def example():
    b = QueryBuilder(Dialect.common)
    b.append_safe('SELECT title, "dueDate" FROM tasks WHERE title LIKE ')
    b.append_string("Launch")
    b.append_safe(" || '%' ESCAPE '!' ORDER BY \"dueDate\" NULLS LAST LIMIT ")
    b.append_int(20)
    b.append_safe(" OFFSET ")
    b.append_int(40)
    return b.build()


def build_only():
    return example()


def render4(q):
    q.render(Dialect.sqlite, PlaceholderStyle.question)
    q.render(Dialect.postgres, PlaceholderStyle.dollar_numbered)
    q.render(Dialect.mysql, PlaceholderStyle.percent_s)
    q.render(Dialect.duckdb, PlaceholderStyle.dollar_numbered)


def bigger():
    b = QueryBuilder(Dialect.common)
    b.append_safe(
        "SELECT u.id, u.name, count(o.id) AS orders, sum(o.total) AS spent "
        "FROM users AS u LEFT JOIN orders AS o ON o.user_id = u.id "
        "WHERE u.created_at >= "
    )
    b.append_string("2026-01-01")
    b.append_safe(" AND (u.status = ")
    b.append_string("active")
    b.append_safe(" OR u.status = ")
    b.append_string("trial")
    b.append_safe(") AND u.id NOT IN (SELECT user_id FROM bans) "
                  "GROUP BY u.id, u.name HAVING count(o.id) > ")
    b.append_int(2)
    b.append_safe(" ORDER BY spent DESC NULLS LAST LIMIT ")
    b.append_int(50)
    return b.build()


def refused():
    bad = QueryBuilder(Dialect.common)
    bad.append_safe("SELECT title, dueDate FROM tasks")
    return bad.template_problem


def syntax_error():
    bad = QueryBuilder(Dialect.common)
    bad.append_safe("SELECT a, b FROM t WHERE a = (b + ")
    return bad.template_problem


def quote():
    for d in (Dialect.sqlite, Dialect.postgres, Dialect.mysql, Dialect.duckdb):
        d.quote_name("my table")
        d.quote_string("it's fine")


q = example()
qb = bigger()
for name, fn in [
    ("example: build (lex, parse, check)", build_only),
    ("example: render for 4 dialects", lambda: render4(q)),
    ("bigger: build", bigger),
    ("bigger: render for 4 dialects", lambda: render4(qb)),
    ("refused (bare mixed-case name)", refused),
    ("syntax error", syntax_error),
    ("quoteName+quoteString x4", quote),
]:
    fn()  # warm, and check it runs
    calls.clear(); bcalls.clear(); ev.clear()
    mon.set_events(TOOL, mon.events.PY_START | mon.events.RAISE | mon.events.EXCEPTION_HANDLED | mon.events.PY_UNWIND)
    fn()
    mon.set_events(TOOL, 0)
    mon.restart_events()
    # Untraced time per op.
    n = 0
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < 0.5:
        fn(); n += 1
    per = (time.perf_counter() - t0) / n
    print(f"{name}: {per * 1e6:.0f} us/op; calls {calls['all']}, bubbling-function calls {calls['bubbling']}; {dict(ev)}")
    if "-v" in sys.argv:
        for k, v in bcalls.most_common(12):
            print(f"    {v:5d} {k}")
print(f"({len(bubbling)} bubbling declarations matched by name)")
