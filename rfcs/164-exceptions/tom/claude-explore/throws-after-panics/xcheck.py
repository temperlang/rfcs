# /// script
# requires-python = ">=3.11"
# ///
"""Cross-check analyze.py's call edges against the Rust-output propagation
sites from bench/markers (results/sites.tsv): for each function, the
names of the labeled things it calls without handling.

    uv run xcheck.py SITES_TSV FUNCTIONS_TSV EDGES_TSV
"""
import sys
from collections import defaultdict

sites = defaultdict(set)
for i, l in enumerate(open(sys.argv[1])):
    if i == 0:
        continue
    lib, fn, vis, kind, form, callee = l.rstrip("\n").split("\t")
    if kind in ("call", "builtin"):
        sites[(lib, fn.lstrip("."))].add(callee.split("::")[-1].split(".")[-1])
mine = defaultdict(set)
for i, l in enumerate(open(sys.argv[3])):
    if i == 0:
        continue
    lib, fn, callee = l.rstrip("\n").split("\t")
    mine[(lib, fn)].add(callee)
labeled = set()
for i, l in enumerate(open(sys.argv[2])):
    if i == 0:
        continue
    c = l.split("\t")
    labeled.add((c[0], c[3]))

def snake(s):
    return "".join("_" + ch.lower() if ch.isupper() else ch for ch in s)

agree = only_rust = only_mine = 0
diffs = []
fns_rust = {k for k in sites if k[0] != "Ordable"}
for k in sorted(fns_rust | {k for k in mine if k[0] not in ("core",)}):
    r = {snake(x) for x in sites.get(k, set())}
    m = {snake(x) for x in mine.get(k, set())}
    # Rust names builtins differently; compare by name only.
    a, b = r - m, m - r
    if not a and not b:
        agree += 1
    else:
        diffs.append((k, sorted(a), sorted(b)))
print(f"functions compared: {agree + len(diffs)}, same callee names: {agree}, differ: {len(diffs)}")
for k, a, b in diffs:
    print(f"  {k[0]} {k[1]}: only in Rust {a}; only here {b}")
