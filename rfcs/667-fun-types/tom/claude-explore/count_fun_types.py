# /// script
# requires-python = ">=3.11"
# ///
"""Count function types and fun interfaces in Temper sources, for RFC 667.

Usage: uv run count_fun_types.py NAME=DIR [NAME=DIR ...] > results.md

Each NAME=DIR is a library label and a directory to scan. Files named
*.temper and *.temper.md are read; in Markdown, only Temper code blocks
(unlabeled or `temper` fences, and indented blocks) count. Directories
named temper.out, build, site, and node_modules are skipped.

Found:
- function *types*: `fn (A, B): R`, maybe generic or with `throws`, in a
  type position, that is, not followed by a body `{`;
- function *literals*: `fn (a: A): R { ... }`;
- block lambdas, roughly: `=>` tokens outside strings and comments;
- `@fun interface` declarations and how often each name is used.

The role column is a heuristic from the shape and the slot's name; the
study reviews it by hand.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

SKIP_DIRS = {"temper.out", "build", "site", "node_modules", ".git"}


def code_only(path: Path, text: str) -> str:
    """Blank out Markdown prose, keeping line numbers."""
    if not path.name.endswith(".temper.md"):
        return text
    out, fence = [], None  # fence: None outside, else (marker, is_code)
    for line in text.split("\n"):
        m = re.match(r"^\s*(```+|~~~+)\s*([\w-]*)", line)
        if fence is None and m:
            fence = (m.group(1), m.group(2) in ("", "temper"))
            out.append("")
        elif fence is not None and m and m.group(1).startswith(fence[0]) and not m.group(2):
            fence = None
            out.append("")
        elif fence is not None:
            out.append(line if fence[1] else "")
        else:
            out.append(line if re.match(r"^(    |\t)", line) else "")
    return "\n".join(out)


def strip_strings_and_comments(s: str) -> str:
    """Replace comment and string text with spaces; keep `${...}` code."""
    out = list(s)
    i, n = 0, len(s)
    stack = []  # 'str' or 'interp' (brace depth tracked separately)
    depth = []
    while i < n:
        c = s[i]
        in_str = stack and stack[-1] == "str"
        if in_str:
            if c == "\\":
                out[i] = " "
                if i + 1 < n and s[i + 1] != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if c == '"':
                stack.pop()
                i += 1
                continue
            if c == "$" and i + 1 < n and s[i + 1] == "{":
                stack.append("interp")
                depth.append(0)
                i += 2
                continue
            if c != "\n":
                out[i] = " "
            i += 1
            continue
        if s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if s.startswith("/*", i):
            j = s.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if s[k] != "\n":
                    out[k] = " "
            i = j
            continue
        if c == '"':
            stack.append("str")
        elif stack and stack[-1] == "interp":
            if c == "{":
                depth[-1] += 1
            elif c == "}":
                if depth[-1] == 0:
                    stack.pop()
                    depth.pop()
                else:
                    depth[-1] -= 1
        i += 1
    return "".join(out)


def skip_ws(s, i):
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def balanced(s, i, open_c, close_c):
    """s[i] == open_c; return index just past the matching close."""
    d = 0
    while i < len(s):
        if s[i] == open_c:
            d += 1
        elif s[i] == close_c:
            d -= 1
            if d == 0:
                return i + 1
        i += 1
    return len(s)


def parse_type(s, i):
    """Return the end of a type expression starting at or after i."""
    i = skip_ws(s, i)
    if re.match(r"fn\b", s[i:]):
        return parse_sig(s, i)[-1]
    if i < len(s) and s[i] == "(":
        i = balanced(s, i, "(", ")")
    else:
        m = re.match(r"[A-Za-z_][\w.]*", s[i:])
        if not m:
            return i
        i += m.end()
        j = skip_ws(s, i)
        if j < len(s) and s[j] == "<":
            i = balanced(s, j, "<", ">")
    j = skip_ws(s, i)
    if j < len(s) and s[j] == "?":
        i = j + 1
    j = skip_ws(s, i)
    if j < len(s) and s[j] in "|&":
        return parse_type(s, j + 1)
    return i


def parse_sig(s, i):
    """s[i:] starts with `fn`. Return (tparams, params, ret, throws, end)."""
    i = skip_ws(s, i + 2)
    tparams = ""
    if i < len(s) and s[i] == "<":
        j = balanced(s, i, "<", ">")
        tparams, i = s[i + 1 : j - 1].strip(), skip_ws(s, j)
    if i >= len(s) or s[i] != "(":
        return tparams, None, None, None, i
    j = balanced(s, i, "(", ")")
    params, i = s[i + 1 : j - 1], j
    ret = throws = None
    k = skip_ws(s, i)
    if k < len(s) and s[k] == ":":
        e = parse_type(s, k + 1)
        ret, i = s[k + 1 : e].strip(), e
    k = skip_ws(s, i)
    if re.match(r"throws\b", s[k:]):
        e = parse_type(s, k + 6)
        throws, i = s[k + 6 : e].strip(), e
    return tparams, params, ret, throws, i


def split_top(s):
    parts, d, cur = [], 0, ""
    for c in s:
        if c in "<([{":
            d += 1
        elif c in ">)]}":
            d -= 1
        if c == "," and d == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def norm(t):
    return re.sub(r"\s+", " ", re.sub(r"\bbuiltins\.", "", t or "")).strip()


def param_types(params):
    out = []
    for p in split_top(params):
        p = re.sub(r"^(@\w+\s+)*(let\s+|var\s+)?", "", p)
        m = re.match(r"^(\.\.\.)?\s*([a-z_]\w*)\s*:\s*(.*)$", p, re.S)
        out.append(norm((m.group(1) or "") + m.group(3)) if m else norm(p))
    return out


def role(ptypes, ret, slot):
    n, r = len(ptypes), ret or "Void"
    if n == 0:
        return "thunk"
    if r == "Boolean" and n == 1:
        return "predicate"
    if n == 2 and r == "Int" and ptypes[0] == ptypes[1]:
        return "comparator"
    if r == "Void":
        return "consumer"
    if n == 2 and ptypes[0] == r:
        return "reducer"
    if n == 1:
        return "mapper"
    return "other"


# Slot names whose meaning is generic: map, filter, sort, reduce, iterate.
GENERIC_SLOTS = {"transform", "predicate", "compare", "accumulate", "key",
                 "stringify", "func", "body", "message"}


def visibility(lines, lineno):
    for k in range(lineno - 1, max(-1, lineno - 7), -1):
        line = lines[k]
        if re.search(r"\b(export|public)\b", line):
            return "api"
        if re.search(r"\b(let|private|var|constructor)\b", line):
            return "internal"
    return "internal"


def scan(label, root: Path, rows, literals, lambdas, funs, texts):
    for path in sorted(root.rglob("*")):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if not (path.name.endswith(".temper") or path.name.endswith(".temper.md")):
            continue
        rel = path.relative_to(root).as_posix()
        is_test = bool(re.search(r"(^|/)tests?/|[-_.]tests?\.", rel.lower()))
        raw = path.read_text(encoding="utf-8")
        code = strip_strings_and_comments(code_only(path, raw))
        texts.append((label, rel, code))
        lines = code.split("\n")
        lambdas[label] += code.count("=>")
        for m in re.finditer(r"@fun\s+interface\s+([A-Z]\w*)\s*(<[^>]*>)?\s*\(", code):
            j = balanced(code, m.end() - 1, "(", ")")
            k = skip_ws(code, j)
            ret = norm(code[k + 1 : parse_type(code, k + 1)]) if code[k] == ":" else "Void"
            lineno = code.count("\n", 0, m.start()) + 1
            funs.append(dict(lib=label, file=rel, line=lineno, name=m.group(1),
                             ptypes=param_types(code[m.end() : j - 1]), ret=ret,
                             tparams=(m.group(2) or "").strip("<>")))
        for m in re.finditer(r"(?<![\w.])fn\b(?=\s*[<(])", code):
            tparams, params, ret, throws, end = parse_sig(code, m.start())
            if params is None:
                continue
            k = skip_ws(code, end)
            lineno = code.count("\n", 0, m.start()) + 1
            if k < len(code) and code[k] == "{":
                literals[label] += 1
                continue
            before = code[: m.start()].rstrip()
            slot, ctx = "", "other"
            if before.endswith(":"):
                ctx = "annotation"
                sm = re.search(r"([A-Za-z_]\w*)\s*$", before[:-1])
                slot = sm.group(1) if sm else ""
            elif before.endswith("="):
                ctx = "alias"
                sm = re.search(r"([A-Za-z_]\w*)\s*(<[^>]*>)?\s*$", before[:-1])
                slot = sm.group(1) if sm else ""
            pts = param_types(params)
            r = norm(ret) or "Void"
            rows.append(dict(lib=label, file=rel, line=lineno, slot=slot, ctx=ctx,
                             test=is_test, vis="test" if is_test else visibility(lines, lineno),
                             tparams=tparams, ptypes=pts, ret=r, throws=norm(throws),
                             role=role(pts, r, slot)))


def shape(row):
    s = f"({', '.join(row['ptypes'])}): {row['ret']}"
    if row.get("throws"):
        s += f" throws {row['throws']}"
    return s


def main(args):
    roots = []
    for a in args:
        label, _, d = a.partition("=")
        roots.append((label, Path(d).expanduser()))
    labels = [label for label, _ in roots]
    rows, funs, texts = [], [], []
    literals, lambdas = Counter(), Counter()
    for label, d in roots:
        scan(label, d, rows, literals, lambdas, funs, texts)
    for f in funs:
        pat = re.compile(rf"\b{re.escape(f['name'])}\b")
        f["uses"] = sum(len(pat.findall(c)) for _, _, c in texts) - 1

    print("# Function types and fun interfaces: counts\n")
    print("Generated by `count_fun_types.py`. Roles and the generic/domain")
    print("column are heuristics, reviewed in the study.\n")
    print("Scanned: " + ", ".join(labels) + ". Test files are those under a")
    print("`tests/` directory or named `*-tests.temper.md` and the like.\n")
    print("## Per library\n")
    print("| Library | Fn types | in API | internal | in tests | Distinct shapes | Arity 0/1/2/3+ | @fun decls | fn literals | `=>` lambdas |")
    print("|---|---:|---:|---:|---:|---:|---|---:|---:|---:|")
    tot = Counter()
    for label in labels:
        rs = [r for r in rows if r["lib"] == label]
        ar = Counter(min(len(r["ptypes"]), 3) for r in rs)
        vis = Counter(r["vis"] for r in rs)
        nf = sum(1 for f in funs if f["lib"] == label)
        shapes = len({shape(r) for r in rs})
        print(f"| {label} | {len(rs)} | {vis['api']} | {vis['internal']} | {vis['test']} | {shapes} | "
              f"{ar[0]}/{ar[1]}/{ar[2]}/{ar[3]} | {nf} | {literals[label]} | {lambdas[label]} |")
        tot.update(dict(n=len(rs), api=vis["api"], internal=vis["internal"], test=vis["test"],
                        a0=ar[0], a1=ar[1], a2=ar[2], a3=ar[3], f=nf, lit=literals[label],
                        lam=lambdas[label]))
    allshapes = len({shape(r) for r in rows})
    print(f"| **All** | {tot['n']} | {tot['api']} | {tot['internal']} | {tot['test']} | {allshapes} | "
          f"{tot['a0']}/{tot['a1']}/{tot['a2']}/{tot['a3']} | {tot['f']} | {tot['lit']} | {tot['lam']} |\n")

    print("## Shapes\n")
    print("Type parameters are kept as written, so `(T): O` and `(T): String` differ.\n")
    by_shape = defaultdict(list)
    for r in rows:
        by_shape[shape(r)].append(r)
    once = sum(1 for v in by_shape.values() if len(v) == 1)
    multi_lib = sum(1 for v in by_shape.values() if len({r["lib"] for r in v}) > 1)
    print(f"{len(by_shape)} distinct shapes; {once} used once; "
          f"{multi_lib} used in more than one library.\n")
    print("| Shape | Uses | Libraries | Roles | Slots |")
    print("|---|---:|---|---|---|")
    for s, v in sorted(by_shape.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        libs = ", ".join(sorted({r["lib"] for r in v}))
        roles = ", ".join(sorted({r["role"] for r in v}))
        slots = ", ".join(sorted({r["slot"] or "?" for r in v}))
        print(f"| `{s}` | {len(v)} | {libs} | {roles} | {slots} |")

    print("\n## Every function type\n")
    print("Generic slot: the slot's name is a generic verb (transform, compare, key, ...),")
    print("so a common core name (`Fn1`, or `Predicate`/`Comparator`) would say as much.\n")
    print("| Where | Slot | Visibility | Shape | Role | Generic slot |")
    print("|---|---|---|---|---|---|")
    gen = Counter()
    for r in rows:
        g = "yes" if r["slot"] in GENERIC_SLOTS else "no"
        gen[(r["vis"], g)] += 1
        tp = f"<{r['tparams']}> " if r["tparams"] else ""
        print(f"| {r['lib']}: {r['file']}:{r['line']} | {r['slot'] or '?'} ({r['ctx']}) | {r['vis']} | "
              f"`{tp}{shape(r)}` | {r['role']} | {g} |")
    print("\nGeneric slot by visibility: " + ", ".join(
        f"{v} {g}: {gen[(v, g)]}" for v in ("api", "internal", "test") for g in ("yes", "no")) + "\n")

    print("## `@fun interface` declarations\n")
    print("| Where | Name | Shape | Uses of the name |")
    print("|---|---|---|---|")
    for f in funs:
        tp = f"<{f['tparams']}>" if f["tparams"] else ""
        print(f"| {f['lib']}: {f['file']}:{f['line']} | `{f['name']}{tp}` | "
              f"`({', '.join(f['ptypes'])}): {f['ret']}` | {f['uses']} |")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
