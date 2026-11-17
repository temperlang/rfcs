# /// script
# requires-python = ">=3.11"
# ///
"""Turns run.py's output from several rounds into Markdown tables.

    uv run hosts/summarize.py results/run-1.txt results/run-2.txt ...

Each cell is the range of the per-round medians, in ns per item; the
ratio columns divide by `null` within each round, so noise shared by a
round cancels. Failure rates are given in per mille by run.py and shown
here in percent.
"""

import sys
from collections import defaultdict

BACKENDS = ["interp", "cpp", "csharp", "csharp-noinline", "java", "java-noinline",
            "js", "lua", "py", "rust"]
NAMES = {"interp": "interp", "cpp": "C++", "csharp": "C#", "csharp-noinline": "C#, no inlining",
         "java": "Java", "java-noinline": "Java, steps not inlined", "js": "JS", "lua": "Lua",
         "py": "Python", "rust": "Rust"}
RATE = {0: "0%", 1: "0.1%", 10: "1%", 100: "10%"}

med = defaultdict(list)
rounds = []
for path in sys.argv[1:]:
    one = {}
    for line in open(path):
        parts = line.split()
        if len(parts) == 5 and parts[0] in NAMES:
            b, rate, v, _lo, m = parts
            one[(b, int(rate), v)] = float(m)
    rounds.append(one)
    for k, m in one.items():
        med[k].append(m)


def fmt(x: float) -> str:
    return f"{x:.0f}" if x >= 10 else f"{x:.1f}"


def rng(xs: list[float]) -> str:
    lo, hi = fmt(min(xs)), fmt(max(xs))
    return lo if lo == hi else f"{lo}-{hi}"


def ratio(b: str, rate: int, v: str, base: str) -> str:
    rs = [r[(b, rate, v)] / r[(b, rate, base)] for r in rounds
          if (b, rate, v) in r and (b, rate, base) in r]
    if not rs:
        return ""
    f = (lambda x: f"{x:.1f}") if max(rs) < 10 else (lambda x: f"{x:.0f}")
    lo, hi = f(min(rs)), f(max(rs))
    return f"{lo}x" if lo == hi else f"{lo}-{hi}x"


def table(backends: list[str], variants: list[str], suffix: str) -> None:
    head = " | ".join(variants)
    ratios = " | ".join(f"{v} / null" for v in variants if v != "null")
    print(f"| Backend | F | {head} | {ratios} |")
    print("|---|---|" + "---|" * (2 * len(variants) - 1))
    for b in backends:
        first = True
        for rate in RATE:
            ks = [(b, rate, v + suffix) for v in variants]
            if not any(k in med for k in ks):
                continue
            cells = [rng(med[k]) if k in med else "" for k in ks]
            rs = [ratio(b, rate, v + suffix, "null" + suffix) for v in variants if v != "null"]
            print(f"| {NAMES[b] if first else ''} | {RATE[rate]} | {' | '.join(cells)} | {' | '.join(rs)} |")
            first = False


for depth, suffix in (("1 (fails and is handled in the caller)", ""),
                      ("5 (fails, then passes up 4 more calls)", "5")):
    print(f"\n### Depth {depth}\n")
    table([b for b in BACKENDS if not b.startswith("java")], ["bubble", "null", "result"], suffix)
    print(f"\nJava, with a hand-written `long` variant (a sentinel for null, nothing boxed):\n")
    table(["java", "java-noinline"], ["bubble", "null", "result", "long"], suffix)
