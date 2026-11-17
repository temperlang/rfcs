# /// script
# requires-python = ">=3.11"
# ///
"""Counts implicit failure propagation sites, from tempest's Rust output.

    uv run count_markers.py RUST_OUT_DIR [--json OUT.json] [--list]

RUST_OUT_DIR is a `temper.out/rust` directory written by
`temper build -b rust`. tempest's Rust backend translates `throws
Bubble` to a `temper_core::Result` return, and each call that
propagates a bubble implicitly to a Rust `?`. An `orelse` becomes an
immediately called closure, `(|| Ok::<_, temper_core::Error>(...))()`,
or `.unwrap_or(...)` on a single call, so a `?` inside such a closure is
handled, not propagated. So, after type checking, the propagation
sites are the `?`s whose innermost enclosing function returns
`temper_core::Result`, outside those closures.

Skipped: the generated `init` functions (module initialization),
`#[cfg(test)]` modules, and each crate's `support/`, `lib.rs`, and
`main.rs` (generated glue).

Each site is attributed to its enclosing function: a Rust free
function, or a method in an `impl` block. Public means a `pub fn` at
module level, or a `pub fn` (or trait method) of a `pub struct` or
`pub trait`; everything else (`pub(crate)`, private) is internal.
"""

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lc>//[^\n]*)
  | (?P<bc>/\*.*?\*/)
  | (?P<raw>b?r(?P<h>\#*)"(?:.|\n)*?"(?P=h))
  | (?P<str>b?"(?:[^"\\]|\\.)*")
  | (?P<chr>b?'(?:[^'\\]|\\.[^']*)')
  | (?P<life>'[A-Za-z_][A-Za-z0-9_]*)
  | (?P<id>r\#[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*)
  | (?P<num>[0-9][0-9A-Za-z_]*(?:\.[0-9][0-9A-Za-z_]*)?)
  | (?P<p>::|->|=>|\|\||&&|==|!=|<=|>=|\.\.=?|[^\sA-Za-z0-9_])
""", re.X | re.S)


def tokens(text: str) -> list[tuple[str, int]]:
    out = []
    pos = 0
    line = 1
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"can't tokenize at {pos}: {text[pos:pos + 40]!r}")
        kind = m.lastgroup
        if kind == "h":
            kind = "raw"
        if kind not in ("ws", "lc", "bc"):
            out.append((m.group(0) if kind in ("id", "p") else f"<{kind}>", line))
        line += m.group(0).count("\n")
        pos = m.end()
    return out


OPEN = {"(": ")", "[": "]", "{": "}"}


def match_brackets(toks):
    pairs = {}
    stack = []
    for i, (t, _) in enumerate(toks):
        if t in OPEN:
            stack.append(i)
        elif t in (")", "]", "}"):
            j = stack.pop()
            pairs[j] = i
            pairs[i] = j
    return pairs


class Region:
    def __init__(self, kind, start, end, name="", ret="", public=False, owner=""):
        self.kind, self.start, self.end = kind, start, end
        self.name, self.ret, self.public, self.owner = name, ret, public, owner


def regions(toks, pairs):
    """Finds fn bodies, impl blocks, test modules, and closures."""
    out = []
    n = len(toks)
    pub_types = set()
    # First, which structs and traits are pub (not pub(crate)).
    for i in range(n - 2):
        if toks[i][0] == "pub" and toks[i + 1][0] in ("struct", "trait", "enum"):
            pub_types.add(toks[i + 2][0])
    impl_stack = []  # (end, type, trait)
    for i, (t, _) in enumerate(toks):
        while impl_stack and i > impl_stack[-1][0]:
            impl_stack.pop()
        if t == "#" and i + 5 < n and [x[0] for x in toks[i:i + 6]] == ["#", "[", "cfg", "(", "test", ")"]:
            # #[cfg(test)] mod tests { ... }
            j = pairs[i + 1] + 1
            if toks[j][0] == "mod":
                k = j
                while toks[k][0] != "{":
                    k += 1
                out.append(Region("test", k, pairs[k]))
        if t == "impl" and (i == 0 or toks[i - 1][0] in ("}", ";", "{", "]")):
            # impl<...>? Type { or impl Trait for Type {
            k = i + 1
            words = []
            depth = 0
            while not (toks[k][0] == "{" and depth == 0):
                if toks[k][0] == "<":
                    depth += 1
                elif toks[k][0] == ">":
                    depth -= 1
                elif depth == 0 and toks[k][0] not in ("::",):
                    words.append(toks[k][0])
                k += 1
            if "for" in words:
                f = words.index("for")
                trait, typ = words[f - 1], words[-1]
            else:
                trait, typ = "", words[-1]
            impl_stack.append((pairs[k], typ, trait))
        if t == "trait" and i + 1 < n and toks[i + 1][0].isidentifier():
            # A trait's default methods: interface methods with bodies.
            k = i + 2
            while toks[k][0] not in ("{", ";"):
                k += 1
            if toks[k][0] == "{":
                impl_stack.append((pairs[k], toks[i + 1][0], "<trait>"))
        if t == "fn" and i + 1 < n and toks[i + 1][0] not in ("(",):
            name = toks[i + 1][0]
            vis = []
            k = i - 1
            while k >= 0 and toks[k][0] in ("pub", "(", "crate", ")", "async", "const", "unsafe"):
                vis.insert(0, toks[k][0])
                k -= 1
            # Signature up to the body's "{" or a ";" (no body).
            k = i + 2
            ret = []
            in_ret = False
            while toks[k][0] not in ("{", ";"):
                if toks[k][0] in OPEN:
                    if in_ret:
                        ret.extend(x[0] for x in toks[k:pairs[k] + 1])
                    k = pairs[k] + 1
                    continue
                if toks[k][0] == "->":
                    in_ret = True
                elif toks[k][0] == "where":
                    in_ret = False
                elif in_ret:
                    ret.append(toks[k][0])
                k += 1
            if toks[k][0] == ";":
                continue
            owner_type, trait = (impl_stack[-1][1], impl_stack[-1][2]) if impl_stack else ("", "")
            if impl_stack:
                if trait == "<trait>":
                    public = owner_type in pub_types
                    trait = ""
                elif trait:
                    public = owner_type in pub_types and trait in pub_types
                else:
                    public = vis[:1] == ["pub"] and vis[1:2] != ["("] and owner_type in pub_types
                owner = f"{owner_type}" + (f" as {trait}" if trait else "")
            else:
                public = vis[:1] == ["pub"] and vis[1:2] != ["("]
                owner = ""
            out.append(Region("fn", k, pairs[k], name, "".join(ret), public, owner))
        if t in ("|", "||"):
            prev = toks[i - 1][0] if i else ""
            if prev in ("(", ",", "=", "move", "return", "{", ";", "=>", ":"):
                # A closure. Find the end of its parameters.
                if t == "||":
                    k = i + 1
                else:
                    k = i + 1
                    while toks[k][0] != "|":
                        if toks[k][0] in OPEN:
                            k = pairs[k]
                        k += 1
                    k += 1
                if toks[k][0] == "->":  # return type, then a block
                    while toks[k][0] != "{":
                        k += 1
                if toks[k][0] == "{":
                    end = pairs[k]
                else:
                    end = k
                    while toks[end][0] not in (",", ")", ";", "}", "]"):
                        if toks[end][0] in OPEN:
                            end = pairs[end]
                        elif toks[end][0] == "::" and toks[end + 1][0] == "<":
                            depth = 0
                            end += 1
                            while True:
                                if toks[end][0] == "<":
                                    depth += 1
                                elif toks[end][0] == ">":
                                    depth -= 1
                                    if depth == 0:
                                        break
                                end += 1
                        end += 1
                    end -= 1
                start = i
                # An immediately called closure, (|| ...)() or (move || ...)():
                # today's lowering of `orelse` around several calls.
                lp = i - 1 if prev == "(" else (i - 2 if prev == "move" and toks[i - 2][0] == "(" else None)
                iife = (lp is not None and pairs.get(lp) is not None
                        and toks[pairs[lp] + 1][0] == "(" and toks[pairs[lp] + 2][0] == ")")
                out.append(Region("orelse" if iife else "closure", start, end))
    return out


def callee(toks, pairs, q):
    """The name called just before the `?` at q (or the expression's kind)."""
    k = q - 1
    if toks[k][0] == ")":
        o = pairs[k]
        k = o - 1
        if toks[k][0] == ">":  # turbofish
            depth = 0
            while True:
                if toks[k][0] == ">":
                    depth += 1
                elif toks[k][0] == "<":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            k -= 2  # skip "::"
        name = [toks[k][0]]
        while k >= 2 and toks[k - 1][0] == "::":
            name.insert(0, toks[k - 2][0])
            k -= 2
        return "::".join(name)
    return f"({toks[k][0]})"


BUILTIN_OPS = {
    "temper_core::int_div": "/", "temper_core::int_rem": "%",
    "temper_core::int64_div": "/", "temper_core::int64_rem": "%",
    "temper_core::float64::div": "/", "temper_core::float64::rem": "%",
}


def kind_of(name: str) -> str:
    if name in BUILTIN_OPS or name.endswith("::div") or name.endswith("::rem") or name in ("div", "rem"):
        return "operator"
    last = name.split("::")[-1].split(".")[-1]
    if last == "ok_or_else" or name.startswith("temper_core::cast"):
        return "as"  # a failing `as` (or a null read as non-null)
    if name.startswith("temper_core::") or name.startswith("Temper"):
        return "builtin"
    if last not in DEFINED:
        return "builtin"  # a method no library here defines: core's
    return "call"


DEFINED: set = set()


STOP = {";", "{", "}", "=>", "else", "return", ",", "="}


def expr_start(toks, pairs, end):
    """Walks back from the last token of a postfix chain to its first."""
    k = end
    while True:
        t = toks[k][0]
        if t in (")", "]") :
            k = pairs[k] - 1
        elif t == ">" and toks[pairs.get(k, k)][0] != ">":
            depth = 0
            while True:
                if toks[k][0] == ">":
                    depth += 1
                elif toks[k][0] == "<":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            k -= 1
        elif t in (".", "::", "&", "*", "!") or toks[k][0].startswith("<") and toks[k][0].endswith(">") or t.isidentifier() or t.startswith("r#"):
            if t.isidentifier() and toks[k - 1][0] not in (".", "::", "&", "*", "!") and toks[k - 1][0] in STOP | {"(", "["}:
                return k
            if t.isidentifier() and toks[k - 1][0].isidentifier():
                return k
            k -= 1
        else:
            return k + 1


def tails(toks, pairs, open_brace):
    """The final call expressions of a block: (index of the call's "(", callee)."""
    close = pairs[open_brace]
    last = close - 1
    if last <= open_brace:
        return []
    t = toks[last][0]
    if t == ";":
        return []
    if t == "}":
        # if/else chain, match, or a plain block: recurse into each block.
        out = []
        k = last
        while True:
            o = pairs[k]
            before = toks[o - 1][0]
            # match arms: { pat => expr, ... }
            j = o - 1
            while toks[j][0] not in STOP and toks[j][0] != "match" and j > open_brace:
                j = pairs[j] - 1 if toks[j][0] in (")", "]") else j - 1
            if toks[j][0] == "match":
                out += arm_tails(toks, pairs, o)
            else:
                out += tails(toks, pairs, o)
            if before == "else":
                k = o - 2
                continue
            # Walk back over an `if cond` to see whether an else chain began.
            j = o - 1
            while toks[j][0] not in STOP and j > open_brace:
                j = pairs[j] - 1 if toks[j][0] in (")", "]", "}") else j - 1
            if toks[j][0] == "else" and toks[j - 1][0] == "}":
                k = j - 1
                continue
            return out
    if t == ")":
        start = expr_start(toks, pairs, last)
        return [(pairs[last], start)]
    return []


def arm_tails(toks, pairs, o):
    out = []
    k = o + 1
    close = pairs[o]
    while k < close:
        if toks[k][0] == "=>":
            k += 1
            if toks[k][0] == "{":
                out += tails(toks, pairs, k)
                k = pairs[k] + 1
            else:
                j = k
                while toks[j][0] not in (",",) and j < close:
                    if toks[j][0] in OPEN:
                        j = pairs[j]
                    j += 1
                if toks[j - 1][0] == ")":
                    out.append((pairs[j - 1], expr_start(toks, pairs, j - 1)))
                k = j
        elif toks[k][0] in OPEN:
            k = pairs[k] + 1
        else:
            k += 1
    return out


def scan(path: Path, lib: str, sites: list, fns: dict) -> None:
    text = path.read_text()
    toks = tokens(text)
    pairs = match_brackets(toks)
    regs = regions(toks, pairs)
    fn_regs = [r for r in regs if r.kind == "fn"]
    tests = [r for r in regs if r.kind == "test"]
    for r in fn_regs:
        if any(t.start <= r.start <= t.end for t in tests):
            continue
        if "temper_core::Result" in r.ret and r.name != "init":
            body = [t for t, _ in toks[r.start:r.end + 1]]
            fns[(lib, path.name, r.owner, r.name, r.start)] = {
                "lib": lib, "file": str(path), "owner": r.owner, "fn": r.name,
                "public": r.public, "line": toks[r.start][1], "sites": 0,
                "fails": "Err" in body, "tail": " ".join(body[-12:])}
    # Calls in tail position, or after `return`, whose Result is returned
    # as it is: propagation with no `?`.
    for r in fn_regs:
        key = (lib, path.name, r.owner, r.name, r.start)
        if key not in fns:
            continue
        found = tails(toks, pairs, r.start)
        closures = [c for c in regs if c.kind in ("closure", "orelse") and r.start < c.start < r.end]
        for k in range(r.start, r.end):
            if toks[k][0] == "return" and not any(c.start <= k <= c.end for c in closures):
                j = k + 1
                while toks[j][0] != ";":
                    if toks[j][0] in OPEN:
                        j = pairs[j]
                    j += 1
                if toks[j - 1][0] == ")":
                    found.append((pairs[j - 1], expr_start(toks, pairs, j - 1)))
        body_tokens = r.end - r.start
        for paren, start in found:
            text = " ".join(t for t, _ in toks[start:paren])
            first = toks[start][0]
            if first in ("Ok", "Err") or text.endswith("!") or text in ("Ok", "Err"):
                continue
            name = callee(toks, pairs, pairs[paren] + 1) if False else text
            # Generated forwarders in `impl Trait for Type` (one call on self).
            forward = " as " in r.owner and body_tokens < 40 and ("self" in text or "& * self" in " ".join(t for t, _ in toks[paren:pairs[paren]]))
            site = {"lib": lib, "file": str(path), "line": toks[paren][1], "callee": text.replace(" ", ""),
                    "kind": kind_of(text.replace(" ", "").split("(")[0]), "fn": r.name, "owner": r.owner,
                    "public": r.public, "where": "forwarder" if forward else "tail"}
            sites.append(site)
            if not forward:
                fns[key]["sites"] += 1
    for q, (t, line) in enumerate(toks):
        if t != "?":
            continue
        if toks[q + 1][0] == "Sized":
            continue
        enclosing = [r for r in regs if r.start <= q <= r.end]
        if any(r.kind == "test" for r in enclosing):
            continue
        inner = max(enclosing, key=lambda r: r.start)
        fn = max((r for r in enclosing if r.kind == "fn"), key=lambda r: r.start, default=None)
        if fn is None or fn.name == "init":
            continue
        name = callee(toks, pairs, q)
        site = {"lib": lib, "file": str(path), "line": line, "callee": name, "kind": kind_of(name),
                "fn": fn.name, "owner": fn.owner, "public": fn.public, "where": inner.kind}
        if inner.kind == "fn" and "temper_core::Result" not in fn.ret:
            site["where"] = "non-result fn"
        sites.append(site)
        if site["where"] in ("fn", "closure"):
            key = (lib, path.name, fn.owner, fn.name, fn.start)
            if key in fns:
                fns[key]["sites"] += 1


def main() -> None:
    root = Path(sys.argv[1])
    sites: list = []
    fns: dict = {}
    files = []
    for lib_dir in sorted(p for p in root.iterdir() if p.is_dir() and p.name != "temper-core"):
        for path in sorted((lib_dir / "src").rglob("*.rs")):
            if path.name in ("lib.rs", "main.rs", "support.rs") or "support" in path.parts:
                continue
            files.append((path, lib_dir.name))
            DEFINED.update(re.findall(r"\bfn\s+((?:r#)?[A-Za-z_][A-Za-z0-9_]*)", path.read_text()))
    for path, lib in files:
        scan(path, lib, sites, fns)
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        Path(out).write_text(json.dumps({"sites": sites, "fns": list(fns.values())}, indent=1))
    counted = [s for s in sites if s["where"] in ("fn", "closure", "tail")]
    print("sites by where:", dict(Counter(s["where"] for s in sites)))
    print("counted sites by kind:", dict(Counter(s["kind"] for s in counted)))
    by_lib = defaultdict(Counter)
    for s in counted:
        by_lib[s["lib"]]["total"] += 1
        by_lib[s["lib"]]["public" if s["public"] else "internal"] += 1
        by_lib[s["lib"]][s["kind"]] += 1
    for lib, c in sorted(by_lib.items()):
        print(lib, dict(c))
    if "--list" in sys.argv:
        for s in sites:
            print(f'{s["lib"]}:{Path(s["file"]).name}:{s["line"]} {s["where"]} {s["owner"]}.{s["fn"]} <- {s["callee"]} [{s["kind"]}]')


if __name__ == "__main__":
    main()
