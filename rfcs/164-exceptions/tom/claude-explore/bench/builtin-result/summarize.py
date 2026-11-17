# /// script
# requires-python = ">=3.11"
# ///
"""Turns builtin-result/run.py's output from several rounds into tables.

    uv run builtin-result/summarize.py results/round-1.txt results/round-2.txt ...

Each cell is the range of the per-round medians in ns per item; ratio
columns divide by `null` in the same round, so noise shared by a round
cancels. Failure rates are per mille in the input, percent here.
"""

import sys
from collections import defaultdict

NAMES = {"cpp": "C++", "csharp": "C#", "csharp-noinline": "C#, no inlining",
         "java": "Java", "java-noinline": "Java, steps not inlined", "js": "JS",
         "lua": "Lua", "py": "Python", "rust": "Rust"}
RATE = {0: "0%", 1: "0.1%", 10: "1%", 100: "10%"}

rounds = []
variants = defaultdict(list)
for path in sys.argv[1:]:
    one = {}
    for line in open(path):
        parts = line.split()
        if len(parts) == 5 and parts[0] in NAMES:
            b, rate, v, _lo, med = parts
            one[(b, int(rate), v)] = float(med)
            base = v.removesuffix("5")
            if base not in variants[b]:
                variants[b].append(base)
    rounds.append(one)


def fmt(x: float) -> str:
    return f"{x:.0f}" if x >= 10 else f"{x:.1f}"


def cell(k) -> str:
    xs = [r[k] for r in rounds if k in r]
    if not xs:
        return ""
    lo, hi = fmt(min(xs)), fmt(max(xs))
    return lo if lo == hi else f"{lo}-{hi}"


def ratio(k, base) -> str:
    rs = [r[k] / r[base] for r in rounds if k in r and base in r]
    if not rs:
        return ""
    f = (lambda x: f"{x:.1f}") if max(rs) < 10 else (lambda x: f"{x:.0f}")
    lo, hi = f(min(rs)), f(max(rs))
    return f"{lo}x" if lo == hi else f"{lo}-{hi}x"


for depth, suffix in (("1 (fails and is handled in the caller)", ""),
                      ("5 (fails, then passes up 4 more calls)", "5")):
    print(f"\n### Depth {depth}\n")
    for b in NAMES:
        if b not in variants:
            continue
        vs = variants[b]
        others = [v for v in vs if v != "null"]
        print(f"| {NAMES[b]} | F | " + " | ".join(vs) + " | "
              + " | ".join(f"{v} / null" for v in others) + " |")
        print("|---|---|" + "---|" * (len(vs) + len(others)))
        for rate, label in RATE.items():
            ks = [(b, rate, v + suffix) for v in vs]
            if not any(k in r for r in rounds for k in ks):
                continue
            cells = [cell(k) for k in ks]
            rs = [ratio((b, rate, v + suffix), (b, rate, "null" + suffix)) for v in others]
            print(f"| | {label} | " + " | ".join(cells) + " | " + " | ".join(rs) + " |")
        print()
