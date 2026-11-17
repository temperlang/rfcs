# /// script
# requires-python = ">=3.11"
# ///
"""Summarizes count_markers.py's JSON output as Markdown tables.

    uv run summarize.py OUT.json [--sites SITES.tsv]

With --sites, also writes every counted site, one per line: library,
function (as Temper names it, roughly: snake_case turned back to camel
case), public or internal, the kind of call, and whether the Rust
output shows it as a `?` or as a call returned as it is (a tail call).
"""

import json
import sys
from collections import Counter, defaultdict

LIBS = {"argmas": "Argmas", "chromarite": "Chromarite", "hrefine": "Hrefine",
        "kelpto": "Kelpto", "kelpto-core": "Kelpto", "kelpto-md": "Kelpto", "kelpto-html": "Kelpto",
        "ordable": "Ordable", "wherewith": "Wherewith", "std": "std"}
ORDER = ["Argmas", "Chromarite", "Hrefine", "Kelpto", "Ordable", "Wherewith", "std"]
KINDS = {"call": "library calls", "builtin": "builtin calls", "operator": "`/` and `%`",
         "as": "`as`"}


def camel(name: str) -> str:
    name = name.removeprefix("r#")
    head, *rest = name.split("_")
    return head + "".join(w[:1].upper() + w[1:] for w in rest)


# Bubbling helpers defined in test files (`*-tests.temper.md`), found by
# grepping those files for `throws Bubble`: left out, like the tests.
TEST_HELPERS = {("argmas", "Even"), ("argmas", "Port"), ("hrefine", "set_part")}


def is_test_helper(x) -> bool:
    return (x["lib"], x["owner"].split(" as ")[0]) in TEST_HELPERS or (x["lib"], x["fn"]) in TEST_HELPERS


data = json.load(open(sys.argv[1]))
sites = [s for s in data["sites"] if s["where"] in ("fn", "closure", "tail") and not is_test_helper(s)]
fns = [f for f in data["fns"] if not is_test_helper(f)]

per = defaultdict(Counter)
for s in sites:
    lib = LIBS[s["lib"]]
    per[lib]["total"] += 1
    per[lib]["public" if s["public"] else "internal"] += 1
    per[lib][s["kind"]] += 1
    per[lib]["tail"] += s["where"] == "tail"
decls = Counter(LIBS[f["lib"]] for f in fns if " as " not in f["owner"])
with_sites = Counter(LIBS[f["lib"]] for f in fns if " as " not in f["owner"] and f["sites"])

print("| Library | Sites | Public | Internal | Library calls | Builtins | `/` `%` | `as` | Functions with a site / bubbling functions |")
print("|---|---|---|---|---|---|---|---|---|")
tot = Counter()
for lib in ORDER:
    c = per[lib]
    tot.update(c)
    print(f"| {lib} | {c['total']} | {c['public']} | {c['internal']} | {c['call']} | {c['builtin']} | {c['operator']} | {c['as']} | {with_sites[lib]} / {decls[lib]} |")
print(f"| **All** | **{tot['total']}** | **{tot['public']}** | **{tot['internal']}** | {tot['call']} | {tot['builtin']} | {tot['operator']} | {tot['as']} | {sum(with_sites.values())} / {sum(decls.values())} |")
print(f"\ntail calls (no `?` in Rust): {tot['tail']}")

# Concentration: sites per function.
by_fn = Counter()
for s in sites:
    owner = s["owner"].split(" as ")[0]
    by_fn[(LIBS[s["lib"]], owner, s["fn"], s["public"])] += 1
ranked = by_fn.most_common()
total = sum(by_fn.values())
print(f"\n{len(ranked)} functions with sites; total {total}")
for k in (1, 3, 5, 10, 20):
    share = sum(n for _, n in ranked[:k])
    print(f"top {k}: {share} ({100 * share / total:.0f}%)")
half = 0
acc = 0
for i, (_, n) in enumerate(ranked):
    acc += n
    if acc >= total / 2:
        half = i + 1
        break
print(f"functions holding half the sites: {half}")
print("distribution (sites per function: count):", sorted(Counter(n for _, n in ranked).items()))
print("\nTop 15:")
for (lib, owner, fn, pub), n in ranked[:15]:
    print(f"| {lib} | `{(owner + '.') if owner else ''}{camel(fn)}` | {'public' if pub else 'internal'} | {n} |")
for lib in ORDER:
    r = [(k, n) for k, n in ranked if k[0] == lib]
    if r:
        t = sum(n for _, n in r)
        top = sum(n for _, n in r[:5])
        print(f"{lib}: {len(r)} functions, top 5 hold {top}/{t} ({100 * top / t:.0f}%); max {r[0][1]} in {r[0][0][1]}.{camel(r[0][0][2])}")

if "--sites" in sys.argv:
    with open(sys.argv[sys.argv.index("--sites") + 1], "w") as f:
        f.write("library\tfunction\tvisibility\tkind\tform\tcallee\n")
        for s in sorted(sites, key=lambda s: (ORDER.index(LIBS[s["lib"]]), s["owner"], s["fn"], s["line"])):
            owner = s["owner"].split(" as ")[0]
            name = (owner + "." if owner else "") + camel(s["fn"])
            callee = s["callee"].split("::")[-1].split(".")[-1]
            form = "tail" if s["where"] == "tail" else "?"
            f.write(f"{LIBS[s['lib']]}\t{name}\t{'public' if s['public'] else 'internal'}\t{s['kind']}\t{form}\t{camel(callee)}\n")
