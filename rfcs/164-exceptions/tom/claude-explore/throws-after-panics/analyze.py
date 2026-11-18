# /// script
# requires-python = ">=3.11"
# ///
"""Which functions would still need a failure label (`throws Bubble`) if
bug-like builtins panicked instead of bubbling? For RFC 164.

    uv run analyze.py ROOT OUTDIR [--sample N]

ROOT holds checkouts of argmas, chromarite, hrefine, kelpto, ordable,
wherewith, and tempest side by side (tempest's lib/core and lib/std are
read). Writes functions.tsv, orelse.tsv, edges.tsv, and summary.md into
OUTDIR.

The scan is lexical, without types: it tokenizes the Temper code in each
file, finds function declarations and their bodies, and in each body the
failure sources that no `orelse` handles: `bubble()`, calls, `as`, `/`,
`%`, and index reads. A call is resolved by name to the labeled functions
of the same library, std, and core. Where a name has more than one
candidate, two figures bound the answer: pessimistic (the call fails if
any labeled candidate still fails) and optimistic (it fails only if
every same-named function, labeled or not, still fails). A third, "best"
figure applies the hand resolutions in RESOLVE below, which were checked
by reading the code, and is otherwise pessimistic. A fourth, "authors",
is "best" with the bug-like `bubble()` calls in BUGLIKE_BUBBLES made
panics too.

A labeled function still needs its label if, after the change, an
unhandled source can still fail: `bubble()`, a builtin the model keeps
fallible, or a call to a function that still needs its label (a least
fixpoint over the call graph). An abstract interface method needs one if
an implementation does, or if hosts may implement it (an exported,
unsealed interface). Only functions labeled today are candidates, since
the change only removes failures.
"""
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

LIBS = {
    "Argmas": ["argmas/src"],
    "Chromarite": ["chromarite/src"],
    "Hrefine": ["hrefine/src"],
    "Kelpto": ["kelpto/kelpto", "kelpto/kelpto-core", "kelpto/kelpto-html", "kelpto/kelpto-md"],
    "Ordable": ["ordable/src"],
    "Wherewith": ["wherewith/src"],
    "std": ["tempest/lib/std"],
    "core": ["tempest/lib/core"],
}
ORDER = list(LIBS)

# The model. Core's labeled builtins, by owner and name: True if they still
# fail after the change, False if they panic instead.
CORE_AFTER = {
    ("String", "fromCodePoint"): False,
    ("String", "fromCodePoints"): False,
    ("StringBuilder", "appendCodePoint"): False,
    ("String", "toFloat64"): True,   # number parsing from strings
    ("String", "toInt32"): True,
    ("String", "toInt64"): True,
    ("Int64", "toFloat64"): False,   # narrowing: a cheap range check
    ("Int64", "toInt32"): False,
    ("Float64", "toInt32"): False,
    ("Float64", "toInt64"): False,
    ("Mapped", "get"): False,        # map read
    ("MapBuilder", "remove"): False, # map removal of a missing key, like a read
    ("Generator", "next"): True,     # a generator's body may still fail
    ("SafeGenerator", "next"): True,
    ("GeneratorFnWrapper", "next"): True,
}
# Abstract or connected declarations outside core whose status the model sets.
FIXED = {
    ("std", "Regex", "compiledFind"): True,   # regex stays as today
}

# Hand resolutions of ambiguous calls, checked by reading the code:
# (library, enclosing function, callee name) -> owner of the target, or
# "-" for a function that isn't labeled (a non-failing overload or a
# different method of the same name).
RESOLVE: dict[tuple, str] = {
    ("Argmas", "FloatType.parse", "toFloat64"): "String",
    ("Argmas", "Int64Type.parse", "toInt64"): "String",
    ("Argmas", "IntType.parse", "toInt32"): "String",
    ("Chromarite", "gradientColors", "toFloat64"): "-",   # Int.toFloat64
    ("Chromarite", "parseHex", "toFloat64"): "-",         # Int.toFloat64
    ("Chromarite", "toNumber", "toFloat64"): "String",
    ("Chromarite", "parseNamed", "get"): "Mapped",
    ("Wherewith", "StatementChecker.count", "toInt64"): "-",   # 0.toInt64()
    ("Wherewith", "StatementChecker.statement", "statement"): "NameCases",
    ("std", "Float64JsonAdapter.decodeFromJson", "asFloat64"): "JsonNumeric",
    ("std", "Int32JsonAdapter.decodeFromJson", "asInt32"): "JsonNumeric",
    ("std", "Int64JsonAdapter.decodeFromJson", "asInt64"): "JsonNumeric",
    ("std", "JsonFloat64.asInt32", "toInt32"): "Float64",
    ("std", "JsonFloat64.asInt64", "toInt64"): "Float64",
    ("std", "JsonInt64.asFloat64", "toFloat64"): "Int64",
    ("std", "JsonInt64.asInt32", "toInt32"): "Int64",
    ("std", "JsonNumericToken.asFloat64", "toFloat64"): "String",
    ("std", "JsonNumericToken.asInt32", "toFloat64"): "String",
    ("std", "JsonNumericToken.asInt32", "toInt32"): "Float64",
    ("std", "JsonNumericToken.asInt64", "toFloat64"): "String",
    ("std", "JsonNumericToken.asInt64", "toInt64"): "Float64",
    ("std", "ListJsonAdapter.decodeFromJson", "decodeFromJson"): "JsonAdapter",
    ("std", "OrNullJsonAdapter.decodeFromJson", "decodeFromJson"): "JsonAdapter",
    ("std", "RegexNode.find", "find"): "Regex",
    # Calls in orelse operands, which matter for which orelse sites go.
    ("std", "JsonNumericToken.asInt32", "toInt32", "content"): "String",
    ("std", "JsonNumericToken.asInt64", "toInt64", "content"): "String",
    ("std", "parseJsonNumber", "toFloat64"): "-",     # Int digits
    ("std", "parseJsonNumber", "toInt64"): "-",
    ("Chromarite", "intToUnit", "toFloat64"): "-",
    ("Hrefine", "parseSpecialHosts", "toInt32"): "String",
    ("Wherewith", "commonCheck", "statement"): "StatementChecker",
    ("Kelpto", "<top>", "remove"): "MarkdownEditor",  # in-file tests
    ("Kelpto", "<top>", "replace"): "MarkdownEditor",
    ("Kelpto", "<top>", "toDocument"): "MarkdownEditor",
    ("Kelpto", "<top>", "withContent"): "Paragraph",
    ("Kelpto", "<top>", "withText"): "Paragraph",
    ("Kelpto", "editedWith", "toDocument"): "MarkdownEditor",
    # type.parse(text) on Argmas's ValueType, which hosts implement.
    **{("Argmas", f, "parse"): "ValueType" for f in (
        "Counter.read", "MaybeValue.read", "Parser.readEnvironment", "TypeChecker.accepts",
        "Value.read", "Values.read", "completionRequest", "looksLikeNumber")},
}

# The variant "authors follow suit": the bubble() calls the no-failures audit
# found bug-like (a bad index, mismatched sizes, a misused producer, a test
# bailing out) become panics too.
BUGLIKE_BUBBLES = {
    ("chromarite/src/color.temper.md", 117), ("chromarite/src/matrix.temper.md", 51),
    ("chromarite/src/matrix.temper.md", 91), ("chromarite/src/matrix.temper.md", 147),
    ("tempest/lib/std/json/json.temper.md", 497), ("tempest/lib/std/testing/testing.temper.md", 55),
}

KEYWORDS = {
    "if", "else", "while", "for", "do", "when", "return", "let", "var", "fn",
    "new", "class", "interface", "export", "public", "private", "protected",
    "static", "get", "set", "constructor", "throws", "orelse", "as", "is",
    "in", "of", "break", "continue", "yield", "await", "this", "null",
    "true", "false", "sealed", "extends", "import", "test", "assert", "panic",
    "bubble", "super", "async", "type", "void", "Void", "case",
}

TOKEN = re.compile(r"""
    (?P<ws>[ \t\r\n]+)
  | (?P<lc>//[^\n]*)
  | (?P<bc>/\*.*?\*/)
  | (?P<num>0[xXbBoO][0-9A-Fa-f_]+[A-Za-z0-9_]*|[0-9][0-9_]*(?:\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9_]+)?[A-Za-z0-9_]*)
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<p>\.\.\.|\?\?|\?\.|=>|->|===|==|!=|<=|>=|&&|\|\||\+=|-=|\*=|/=|%=|\+\+|--|::|[^\sA-Za-z0-9_])
""", re.X | re.S)


class Lexer:
    """Temper tokens: (text, line). Strings become one <str> token; their
    `${...}` interpolations are emitted inside ( ) so calls in them count."""

    def __init__(self, text):
        self.text = text
        self.toks = []

    def line(self, pos):
        return self.text.count("\n", 0, pos) + 1

    def run(self):
        self.lex(0, False)
        return self.toks

    def lex(self, pos, in_interp):
        text, toks = self.text, self.toks
        depth = 0
        while pos < len(text):
            c = text[pos]
            if c == '"':
                if text.startswith('"""', pos):
                    pos = self.multiline(pos)
                else:
                    pos = self.string(pos + 1, '"')
                continue
            if c == "'":
                pos = self.string(pos + 1, "'")
                continue
            if in_interp:
                if c == "{":
                    depth += 1
                elif c == "}":
                    if depth == 0:
                        return pos + 1
                    depth -= 1
            m = TOKEN.match(text, pos)
            if not m:
                raise ValueError(f"can't tokenize at line {self.line(pos)}: {text[pos:pos + 30]!r}")
            kind = m.lastgroup
            if kind in ("id", "p", "num"):
                toks.append((m.group(0) if kind != "num" else "<num>", self.line(pos)))
            pos = m.end()
        return pos

    def string(self, pos, q):
        line = self.line(pos)
        self.toks.append(("<str>", line))
        text = self.text
        while pos < len(text):
            c = text[pos]
            if c == "\\":
                pos += 2
                continue
            if c == q:
                return pos + 1
            if c == "$" and text.startswith("${", pos):
                self.toks.append(("(", self.line(pos)))
                pos = self.lex(pos + 2, True)
                self.toks.append((")", self.line(pos)))
                continue
            if c == "\n":
                return pos  # an unterminated line; don't run away
            pos += 1
        return pos

    def multiline(self, pos):
        """\"\"\" then lines that start with a quote, each running to its end."""
        text = self.text
        self.toks.append(("<str>", self.line(pos)))
        pos = text.find("\n", pos)
        while pos >= 0 and pos < len(text):
            nxt = pos + 1
            m = re.compile(r'[ \t]*"').match(text, nxt)
            if not m:
                return nxt
            p = m.end()
            end = text.find("\n", p)
            end = len(text) if end < 0 else end
            while p < end:
                if text[p] == "\\":
                    p += 2
                    continue
                if text.startswith("${", p):
                    self.toks.append(("(", self.line(p)))
                    p = self.lex(p + 2, True)
                    self.toks.append((")", self.line(p)))
                    continue
                p += 1
            pos = end
        return len(text)


def code_text(path: Path) -> str:
    """The file's Temper code, with prose blanked so line numbers stay."""
    lines = path.read_text().split("\n")
    if path.suffix == ".temper":
        return "\n".join(lines)
    out = []
    fence = None
    prev_code_or_blank = True
    for l in lines:
        if l.startswith("```"):
            fence = (None if fence else ("code" if l.strip() == "```" else "prose"))
            out.append("")
            prev_code_or_blank = False
            continue
        if fence == "code":
            out.append(l)
            continue
        if fence == "prose":
            out.append("")
            continue
        if l.strip() == "":
            out.append("")
            prev_code_or_blank = True
            continue
        if (l.startswith("    ") or l.startswith("\t")) and prev_code_or_blank:
            out.append(l)
            continue
        out.append("")
        prev_code_or_blank = False
    return "\n".join(out)


OPEN = {"(": ")", "[": "]", "{": "}"}


def match_brackets(toks, where):
    pairs, stack = {}, []
    for i, (t, line) in enumerate(toks):
        if t in OPEN:
            stack.append(i)
        elif t in (")", "]", "}"):
            if not stack or OPEN[toks[stack[-1]][0]] != t:
                raise ValueError(f"{where}:{line}: unbalanced {t}")
            j = stack.pop()
            pairs[i], pairs[j] = j, i
    if stack:
        raise ValueError(f"{where}:{toks[stack[-1]][1]}: unclosed {toks[stack[-1]][0]}")
    return pairs


class Fn:
    def __init__(self, **kw):
        self.__dict__.update(kw)
        self.sources = []   # (kind, name, token index, line, receiver)

    @property
    def qual(self):
        return f"{self.owner}.{self.name}" if self.owner else self.name


class Klass:
    def __init__(self, name, exported, sealed, interface, extends, start, end):
        self.name, self.exported, self.sealed = name, exported, sealed
        self.interface, self.extends, self.start, self.end = interface, extends, start, end


def skip_generic(toks, k):
    """At a `<`, returns the index after its matching `>`."""
    depth = 0
    while k < len(toks):
        t = toks[k][0]
        if t == "<":
            depth += 1
        elif t == ">":
            depth -= 1
            if depth == 0:
                return k + 1
        elif t in (";", "{", "}"):
            return k
        k += 1
    return k


MODS = {"public", "private", "protected", "static", "get", "set", "override", "export", "sealed"}


def scan_file(lib, path, rel):
    toks = Lexer(code_text(path)).run()
    pairs = match_brackets(toks, rel)
    n = len(toks)
    classes, fns, tests = [], [], []
    # Classes and interfaces.
    for i, (t, _) in enumerate(toks):
        if t in ("class", "interface") and i + 1 < n and re.match(r"[A-Z]", toks[i + 1][0]):
            k = i - 1
            mods = set()
            while k >= 0 and (toks[k][0] in MODS or toks[k][0].startswith("@")):
                mods.add(toks[k][0])
                k -= 1
            j = i + 2
            ext, after_ext, depth = [], False, 0
            while j < n and toks[j][0] not in ("{", ";"):
                tt = toks[j][0]
                if tt in OPEN:
                    j = pairs[j] + 1
                    continue
                if tt == "<":
                    depth += 1
                elif tt == ">":
                    depth -= 1
                elif tt == "extends" and depth == 0:
                    after_ext = True
                elif after_ext and depth == 0 and re.match(r"[A-Z]\w*$", tt):
                    ext.append(tt)
                j += 1
            if j < n and toks[j][0] == "{":
                classes.append(Klass(toks[i + 1][0], "export" in mods, "sealed" in mods,
                                     t == "interface", ext, j, pairs[j]))
    # Tests: test("...") { ... } blocks.
    for i, (t, _) in enumerate(toks):
        if t == "test" and i + 1 < n and toks[i + 1][0] == "(":
            j = pairs[i + 1] + 1
            if j < n and toks[j][0] == "{":
                tests.append((i, pairs[j]))
    # The innermost open brace around each token, and which braces are class bodies.
    enclosing, stack = {}, []
    for i, (t, _) in enumerate(toks):
        if stack:
            enclosing[i] = stack[-1]
        if t == "{":
            stack.append(i)
        elif t == "}":
            stack.pop()
    class_bodies = {c.start for c in classes}
    # Functions.
    for i, (t, line) in enumerate(toks):
        name = None
        if t == "let" and i + 2 < n and re.match(r"[A-Za-z_]\w*$", toks[i + 1][0]) and toks[i + 2][0] in ("(", "<"):
            name, k = toks[i + 1][0], i + 2
            kind = "let"
        elif t == "constructor" and i + 1 < n and toks[i + 1][0] == "(":
            name, k, kind = "constructor", i + 1, "constructor"
        elif (re.match(r"[A-Za-z_]\w*$", t) and (t not in KEYWORDS | MODS or t in ("get", "set"))
              and i + 1 < n and toks[i + 1][0] in ("(", "<") and i > 0
              and enclosing.get(i) in class_bodies
              and (toks[i - 1][0] in MODS or toks[i - 1][0] in (";", "{", "}"))):
            name, k = t, i + 1
            kind = toks[i - 1][0] if toks[i - 1][0] in ("get", "set") else "method"
        if name is None:
            continue
        if toks[k][0] == "<":
            k = skip_generic(toks, k)
        if k >= n or toks[k][0] != "(":
            continue
        params_end = pairs[k]
        j = params_end + 1
        sig = []
        while j < n and toks[j][0] not in ("{", ";", "}", "="):
            if toks[j][0] in ("(", "["):
                sig.extend(x[0] for x in toks[j:pairs[j] + 1])
                j = pairs[j] + 1
                continue
            sig.append(toks[j][0])
            j += 1
        if j >= n:
            continue
        # A method needs a ':' return type or a body; skip plain calls like `foo(x);`.
        body = toks[j][0] == "{"
        if kind == "method" and not body and ":" not in sig:
            continue
        if kind == "let" and not body and ":" not in sig:
            continue
        mods = set()
        m = i - 1
        while m >= 0 and (toks[m][0] in MODS or toks[m][0] in ("let",)):
            mods.add(toks[m][0])
            m -= 1
        labeled = "throws" in sig
        params = split_top(toks, pairs, k, params_end)
        nparams = len(params)
        nrequired = sum(1 for p in params if "=" not in p)
        start, end = (j, pairs[j]) if body else (None, None)
        fns.append(Fn(lib=lib, file=rel, line=line, name=name, kind=kind, mods=mods,
                      labeled=labeled, body=body, nparams=nparams, nrequired=nrequired, start=start, end=end, decl=i, sig=sig,
                      sig_text=" ".join(sig)))
    # Owners: innermost class whose body holds the declaration; parent fn.
    for f in fns:
        cls = [c for c in classes if c.start < f.decl < c.end]
        c = max(cls, key=lambda c: c.start) if cls else None
        parents = [g for g in fns if g.body and g is not f and g.start < f.decl < g.end]
        p = max(parents, key=lambda g: g.start) if parents else None
        f.klass = c if (c and (p is None or c.start > p.start)) else None
        f.parent = p if (p and (c is None or p.start > c.start)) else None
        f.owner = f.klass.name if f.klass else (f"{p.qual}/" if p else "")
        if f.parent:
            f.exported = False
        elif f.klass:
            f.exported = f.klass.exported and not (f.mods & {"private", "protected"})
        else:
            f.exported = "export" in f.mods or lib == "core" and "export" in f.mods
        f.in_test = any(a < f.decl < b for a, b in tests)
    # Labeled function types (`let TestFun = fn (Test): Void throws Bubble`)
    # are counted apart.
    ftypes = []
    for i, (t, line) in enumerate(toks):
        if t == "fn" and i + 1 < n and toks[i + 1][0] == "(":
            j = pairs[i + 1] + 1
            sig = []
            while j < n and toks[j][0] not in (";", "{", ",", ")", "}", "="):
                sig.append(toks[j][0])
                j += 1
            if "throws" in sig and (j >= n or toks[j][0] != "{"):
                ftypes.append((lib, rel, line))
    return toks, pairs, classes, fns, tests, ftypes


def split_top(toks, pairs, a, b):
    """The comma-separated parts between brackets a and b, as token lists."""
    parts, cur, k = [], [], a + 1
    while k < b:
        t = toks[k][0]
        if t in OPEN:
            cur.extend(x[0] for x in toks[k:pairs[k] + 1])
            k = pairs[k] + 1
            continue
        if t == ",":
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
        k += 1
    if cur:
        parts.append(cur)
    return parts


STOP_BACK = {",", ";", "=", "+=", "-=", "*=", "/=", "%=", "=>", "->", "return", "let", "var",
             "else", ":", "yield"}


def generic_closers(toks):
    """Type arguments' closing `>`s, mapped to their `<`: `as Map<K, V>`."""
    out = {}
    ok = {",", "?", ".", "<", ">", "fn", "(", ")", ":", "in", "out"}
    for i, (t, _) in enumerate(toks):
        if t != "<" or i == 0 or not re.match(r"[A-Z]\w*$", toks[i - 1][0]):
            continue
        depth, j = 0, i
        while j < len(toks):
            tt = toks[j][0]
            if tt == "<":
                depth += 1
            elif tt == ">":
                depth -= 1
                if depth == 0:
                    out[j] = i
                    break
            elif not (tt in ok or re.match(r"[A-Za-z_]\w*$", tt)):
                break
            j += 1
    return out


def orelse_operands(toks, pairs):
    """For each `orelse`, the token range of its left operand."""
    out = []
    gclose = generic_closers(toks)
    for k, (t, line) in enumerate(toks):
        if t != "orelse":
            continue
        i = k - 1
        while i >= 0:
            tt = toks[i][0]
            if tt in (")", "]"):
                i = pairs[i] - 1
                continue
            if tt == ">" and i in gclose:
                i = gclose[i] - 1
                continue
            if tt == "}":
                if i == k - 1 or (i + 1 < len(toks) and toks[i + 1][0] in (".", "?.")):
                    i = pairs[i] - 1
                    continue
                break
            if tt in OPEN or tt in STOP_BACK:
                break
            i -= 1
        rhs = toks[k + 1][0] if k + 1 < len(toks) else ""
        out.append((k, i + 1, k - 1, line, rhs))
    return out


def body_sources(f, toks, pairs, nested):
    """Failure sources in f's body, outside nested function bodies:
    (kind, name, token index, line, receiver, argument count)."""
    srcs = []
    k = f.start + 1
    n = len(toks)
    while k < f.end:
        skip = next((g for g in nested if g.start is not None and g.decl <= k <= g.end and g is not f), None)
        if skip:
            k = skip.end + 1
            continue
        t, line = toks[k]
        prev = toks[k - 1][0]
        nxt = toks[k + 1][0] if k + 1 < n else ""
        if t == "bubble" and nxt == "(":
            srcs.append(("bubble", "bubble", k, line, "", 0))
        elif t == "new" and re.match(r"[A-Z]\w*$", nxt):
            j = k + 2
            if j < n and toks[j][0] == "<":
                j = skip_generic(toks, j)
            nargs = len(split_top(toks, pairs, j, pairs[j])) if j < n and toks[j][0] == "(" else 0
            srcs.append(("ctor", nxt, k, line, nxt, nargs))
        elif re.match(r"[A-Za-z_]\w*$", t) and (t not in KEYWORDS or t in ("get", "set")) and prev != "new":
            j = k + 1
            if j < n and toks[j][0] == "<" and prev in (".", "?."):
                j2 = skip_generic(toks, j)
                if j2 < n and toks[j2][0] == "(":
                    j = j2
            recv = ""
            if prev in (".", "?."):
                pp = toks[k - 2][0]
                recv = pp if re.match(r"[A-Za-z_]\w*$", pp) else ("(" if pp in (")", "]") else pp)
            if j < n and toks[j][0] == "(":
                nargs = len(split_top(toks, pairs, j, pairs[j]))
                after = pairs[j] + 1
                if after < n and toks[after][0] == "{" and after < f.end:
                    nargs += 1   # a trailing block
                srcs.append(("call", t, k, line, recv, nargs))
            elif j < n and toks[j][0] == "{" and prev in (".", "?."):
                srcs.append(("call", t, k, line, recv, 1))   # xs.map { ... }
        elif t == "as" and re.match(r"[A-Z]", nxt):
            srcs.append(("as", "as", k, line, "", 0))
        elif t in ("/", "%", "/=", "%="):
            srcs.append(("div", t, k, line, "", 0))
        elif t == "[" and (prev in (")", "]") or (re.match(r"[A-Za-z_]\w*$", prev) and prev not in KEYWORDS) or prev == "this"):
            # x[i] reads x.get(i): a list or map read, or a library's own get.
            srcs.append(("index", "get", k, line, "(", len(split_top(toks, pairs, k, pairs[k]))))
        k += 1
    return srcs


def main():
    root = Path(sys.argv[1])
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    sample_n = int(sys.argv[sys.argv.index("--sample") + 1]) if "--sample" in sys.argv else 20
    all_fns, all_classes, all_orelse, ftypes = [], {}, [], []
    file_data = {}
    for lib, dirs in LIBS.items():
        for d in dirs:
            for path in sorted((root / d).rglob("*.temper*")):
                if path.name.endswith("-tests.temper.md") or path.name == "config.temper.md":
                    continue
                rel = str(path.relative_to(root))
                toks, pairs, classes, fns, tests, ft = scan_file(lib, path, rel)
                ftypes += ft
                file_data[rel] = (toks, pairs, tests)
                for c in classes:
                    all_classes.setdefault((lib, c.name), c)
                for f in fns:
                    f.sources = body_sources(f, toks, pairs, [g for g in fns if g.parent is f]) if f.body else []
                all_fns += fns
                for (k, a, b, line, rhs) in orelse_operands(toks, pairs):
                    all_orelse.append(dict(lib=lib, file=rel, k=k, a=a, b=b, line=line, rhs=rhs,
                                           in_test=any(x < k < y for x, y in tests)))
    # Handled sources: those inside an orelse's left operand.
    by_file_or = defaultdict(list)
    for o in all_orelse:
        by_file_or[o["file"]].append(o)
    for f in all_fns:
        if not f.body:
            continue
        kept = []
        for s in f.sources:
            if not any(o["a"] <= s[2] <= o["b"] for o in by_file_or[f.file]):
                kept.append(s)
        f.handled = len(f.sources) - len(kept)
        f.unhandled = kept

    # Node set: labeled functions (outside tests).
    labeled = [f for f in all_fns if f.labeled and not f.in_test]
    by_name = defaultdict(list)       # every function by name, labeled or not
    for f in all_fns:
        if not f.in_test:
            by_name[f.name].append(f)

    def visible(lib):
        return {lib, "std", "core"}

    # Interfaces: implementations of an abstract method.
    def subclasses(lib, iface):
        out = set()
        frontier = {iface}
        while frontier:
            nxt = set()
            for (l, cname), c in all_classes.items():
                if l in visible(lib) | {lib} and cname not in out and set(c.extends) & frontier:
                    out.add(cname)
                    nxt.add(cname)
            frontier = nxt
        return out

    for f in labeled:
        f.impls = []
        f.override_of = None
        if f.klass and f.klass.interface and not f.body:
            subs = subclasses(f.lib, f.klass.name)
            f.impls = [g for g in by_name[f.name] if g.klass and g.klass.name in subs and g.body]
    for f in labeled:
        if f.klass and f.body:
            for g in labeled:
                if g is not f and not g.body and g.name == f.name and g.klass and g.klass.interface and f in g.impls:
                    f.override_of = g
    labeled_set = set(map(id, labeled))

    def candidates(f, s):
        kind, name, k, line, recv, nargs = s
        libs = visible(f.lib)
        if kind == "ctor":
            alls = [g for g in by_name["constructor"] if g.lib in libs and g.klass and g.klass.name == name]
            return [g for g in alls if id(g) in labeled_set], alls
        alls = [g for g in by_name[name] if g.lib in libs and g.kind not in ("constructor", "get", "set")]
        # Arity, allowing for defaults; kept only if it leaves a candidate.
        fit = [g for g in alls if g.nrequired <= nargs <= g.nparams]
        if fit:
            alls = fit
        # A bare call or this.x() in a class: that class's own method if it has one.
        if recv in ("", "this") and f.klass:
            own = [g for g in alls if g.klass is f.klass]
            if own:
                alls = own
        if recv == "" and not f.klass:
            top = [g for g in alls if g.klass is None and g.file == f.file]
            if top:
                alls = top
        # A receiver that names a class: that class's static methods.
        if re.match(r"[A-Z]", recv or ""):
            own = [g for g in alls if g.klass and g.klass.name == recv]
            if own:
                alls = own
        lab = [g for g in alls if id(g) in labeled_set]
        return lab, alls

    def core_after(g):
        return CORE_AFTER.get((g.klass.name if g.klass else "", g.name))

    def resolve(f, s, after, mode):
        kind, name, k, line, recv, nargs = s
        if kind == "bubble":
            if mode == "authors" and (f.file, line) in BUGLIKE_BUBBLES:
                return False, "bubble() made a panic"
            return True, "bubble()"
        if kind in ("as", "div"):
            return False, kind
        lab, alls = candidates(f, s)
        if not lab:
            return False, ""
        key = (f.lib, f.qual, name, recv)
        if key not in RESOLVE:
            key = key[:3]
        if mode in ("best", "authors") and key in RESOLVE:
            tgt = RESOLVE[key]
            if tgt == "-":
                return False, f"{name} (resolved: not labeled)"
            hit = [g for g in lab if (g.klass.name if g.klass else "") == tgt]
            return any(after[id(g)] for g in hit), f"{tgt}.{name}"
        fails = [after[id(g)] for g in lab]
        if mode == "optimistic":
            ok = all(after.get(id(g), False) for g in alls)
        else:
            ok = any(fails)
        return ok, (lab[0].qual if len(lab) == 1 else f"{name}?{len(lab)}/{len(alls)}")

    def host_impl(g):
        """An exported, unsealed interface's method: hosts may implement it."""
        return bool(g.klass and g.klass.interface and g.klass.exported and not g.klass.sealed)

    results = {}
    for mode in ("pessimistic", "optimistic", "best", "authors"):
        after = {id(g): False for g in all_fns}
        for g in labeled:
            if g.lib == "core":
                v = core_after(g)
                if v is None:
                    raise SystemExit(f"core function without a model entry: {g.qual}")
                after[id(g)] = v
            elif (g.lib, g.klass.name if g.klass else "", g.name) in FIXED:
                after[id(g)] = FIXED[(g.lib, g.klass.name if g.klass else "", g.name)]
        changed = True
        while changed:
            changed = False
            for g in labeled:
                if g.lib == "core" or (g.lib, g.klass.name if g.klass else "", g.name) in FIXED:
                    continue
                if g.body:
                    v = any(resolve(g, s, after, mode)[0] for s in g.unhandled)
                else:
                    v = any(after[id(h)] for h in g.impls) or host_impl(g)
                if v and not after[id(g)]:
                    after[id(g)] = True
                    changed = True
        results[mode] = after

    best = results["best"]

    # Why each labeled function stays (best figure): direct or via calls.
    rows = []
    for g in labeled:
        direct = False
        via = []
        if g.lib == "core" or (g.lib, g.klass.name if g.klass else "", g.name) in FIXED:
            direct = best[id(g)]
        elif g.body:
            for s in g.unhandled:
                ok, why = resolve(g, s, best, "best")
                if ok:
                    if s[0] == "bubble":
                        direct = True
                    else:
                        lab, _ = candidates(g, s)
                        if lab and all(h.lib == "core" or not h.body and (h.lib, h.klass.name if h.klass else "", h.name) in FIXED for h in lab):
                            direct = True
                        via.append(why)
        else:
            if host_impl(g):
                direct = True
            via += [h.qual for h in g.impls if best[id(h)]]
        g.direct, g.via = direct, via
        rows.append(g)

    # orelse sites: does the operand still fail?
    fn_at = defaultdict(list)
    for f in all_fns:
        if f.body:
            fn_at[f.file].append(f)
    or_rows = []
    or_amb = Counter()
    for o in all_orelse:
        toks, pairs, tests = file_data[o["file"]]
        encl = [f for f in fn_at[o["file"]] if f.start < o["k"] < f.end]
        f = max(encl, key=lambda f: f.start) if encl else None
        # Sources in the operand, minus those an inner orelse handles.
        inner = [p for p in all_orelse if p["file"] == o["file"] and p is not o and o["a"] <= p["k"] <= o["b"]]
        fake = Fn(lib=o["lib"], file=o["file"], line=o["line"], name=f.name if f else "<top>", kind="x", mods=set(),
                  labeled=False, body=True, start=o["a"] - 1, end=o["b"] + 1, decl=o["a"] - 1, sig=[], sig_text="")
        fake.klass = f.klass if f else None
        fake.owner = f.owner if f else ""
        fake.parent = None
        nested = [g for g in all_fns if g.file == o["file"] and g.body and o["a"] <= g.decl <= o["b"]]
        srcs = [s for s in body_sources(fake, toks, pairs, nested) if not any(p["a"] <= s[2] <= p["b"] for p in inner)]
        if fake.start < 0:
            srcs = []
        today = []
        afters = {}
        for s in srcs:
            if s[0] in ("as", "div"):
                today.append(s[0])
            elif s[0] == "bubble":
                today.append("bubble")
            else:
                lab, _ = candidates(fake, s)
                if lab:
                    today.append(s[1])
        for mode in ("pessimistic", "optimistic", "best", "authors"):
            afters[mode] = any(resolve(fake, s, results[mode], mode)[0] for s in srcs)
        for s in srcs:
            if s[0] in ("call", "ctor", "index"):
                lab, _ = candidates(fake, s)
                if lab and resolve(fake, s, results["best"], "pessimistic")[0] != resolve(fake, s, results["best"], "optimistic")[0]:
                    or_amb[(fake.lib, fake.qual, s[1], ",".join(sorted({h.klass.name if h.klass else "" for h in lab})))] += 1
        or_rows.append((o, f, today, afters))

    write_outputs(outdir, rows, results, or_rows, ftypes, sample_n, resolve, candidates, or_amb)


def write_outputs(outdir, rows, results, or_rows, ftypes, sample_n, resolve, candidates, or_amb):
    P, O, B, A = results["pessimistic"], results["optimistic"], results["best"], results["authors"]
    with open(outdir / "functions.tsv", "w") as fh:
        fh.write("library\tfile\tline\tfunction\tvisibility\tabstract\toverride\tafter_best\tafter_optimistic\t"
                 "after_pessimistic\tafter_authors\tstays_because\tunhandled_today\tstill_failing_via\n")
        for g in rows:
            unh = Counter(s[0] for s in g.unhandled) if g.body else Counter()
            stays = "" if not B[id(g)] else ("direct" if g.direct else "calls only")
            fh.write("\t".join(map(str, [
                g.lib, g.file, g.line, g.qual, "exported" if g.exported else "private",
                "" if g.body else "abstract", g.override_of.qual if g.override_of else "",
                int(B[id(g)]), int(O[id(g)]), int(P[id(g)]), int(A[id(g)]), stays,
                " ".join(f"{k}:{v}" for k, v in sorted(unh.items())),
                " ".join(sorted(set(g.via))),
            ])) + "\n")
    with open(outdir / "edges.tsv", "w") as fh:
        fh.write("library\tfunction\tcallee\n")
        seen = set()
        for g in rows:
            for src in (g.unhandled if g.body else []):
                lab = candidates(g, src)[0] if src[0] in ("call", "ctor", "index") else []
                # Reads that can only be core's Mapped.get: Rust shows list reads as no site.
                if lab and not all(h.lib == "core" and h.name == "get" for h in lab):
                    e = (g.lib, g.qual, "new" if src[0] == "ctor" else src[1])
                    if e not in seen:
                        seen.add(e)
                        fh.write("\t".join(e) + "\n")
    with open(outdir / "orelse.tsv", "w") as fh:
        fh.write("library\tfile\tline\tfallback\tin_test\tfunction\toperand_sources\tstill_fails_best\t"
                 "still_fails_optimistic\tstill_fails_pessimistic\tstill_fails_authors\n")
        for o, f, today, afters in or_rows:
            fh.write("\t".join(map(str, [
                o["lib"], o["file"], o["line"], o["rhs"], int(o["in_test"]), f.qual if f else "",
                " ".join(today), int(afters["best"]), int(afters["optimistic"]), int(afters["pessimistic"]), int(afters["authors"]),
            ])) + "\n")

    # Summary table.
    lines = []
    lines.append("| Library | Labeled today (exported / private) | Labeled after (exported / private) | "
                 "Private after, via calls only | After, bounds | After, if bug-like `bubble()`s panic too | `orelse panic()` gone / total |")
    lines.append("|---|---|---|---|---|---|---|")
    tot = Counter()
    for lib in ORDER + ["All"]:
        gs = [g for g in rows if lib == "All" or g.lib == lib]
        te = sum(g.exported for g in gs)
        ae = sum(1 for g in gs if B[id(g)] and g.exported)
        ap = sum(1 for g in gs if B[id(g)] and not g.exported)
        via = sum(1 for g in gs if B[id(g)] and not g.exported and not g.direct)
        ao = sum(1 for g in gs if O[id(g)])
        apz = sum(1 for g in gs if P[id(g)])
        aa = sum(1 for g in gs if A[id(g)])
        aae = sum(1 for g in gs if A[id(g)] and g.exported)
        ors = [r for r in or_rows if (lib == "All" or r[0]["lib"] == lib) and r[0]["rhs"] == "panic"]
        gone = sum(1 for r in ors if not r[3]["best"])
        lines.append(f"| {lib} | {len(gs)} ({te} / {len(gs) - te}) | {ae + ap} ({ae} / {ap}) | {via} | "
                     f"{ao} to {apz} | {aa} ({aae} / {aa - aae}) | {gone} / {len(ors)} |")
    summ = "\n".join(lines)
    extra = []
    ors = [r for r in or_rows if r[0]["rhs"] == "panic"]
    gone_src = sum(1 for r in ors if not r[3]["best"] and not r[0]["in_test"])
    extra.append(f"orelse panic() outside tests: {sum(1 for r in ors if not r[0]['in_test'])}, gone {gone_src}")
    extra.append(f"orelse panic() gone if bug-like bubble()s panic too: {sum(1 for r in ors if not r[3]['authors'])}")
    gone_bounds = (sum(1 for r in ors if not r[3]["pessimistic"]), sum(1 for r in ors if not r[3]["optimistic"]))
    extra.append(f"orelse panic() gone, pessimistic to optimistic: {gone_bounds[0]} to {gone_bounds[1]}")
    others = [r for r in or_rows if r[0]["rhs"] != "panic"]
    extra.append(f"other orelse: {len(others)}, operand no longer fails (best): {sum(1 for r in others if not r[3]['best'])}")
    nosrc = [r for r in or_rows if not r[2]]
    extra.append(f"orelse with no failure source found in the operand: {len(nosrc)}")
    no_today = [g for g in rows if g.body and g.lib != "core" and not any(
        s[0] in ("bubble", "as", "div") or candidates(g, s)[0] for s in g.unhandled)]
    extra.append(f"labeled functions with a body but no unhandled source found: {len(no_today)}: "
                 + ", ".join(f"{g.lib}:{g.qual}" + (" (override)" if g.override_of else "") for g in no_today))
    extra.append(f"labeled function types (not counted): {len(ftypes)}: " + ", ".join(f"{a}:{Path(b).name}:{c}" for a, b, c in ftypes))
    ov = [g for g in rows if g.override_of and not B[id(g)] and B[id(g.override_of)]]
    extra.append(f"overrides that can't fail of still-labeled interface methods: {len(ov)}: " + ", ".join(f"{g.lib}:{g.qual}" for g in ov))
    amb = Counter()
    for g in rows:
        for s in (g.unhandled if g.body else []):
            if s[0] in ("call", "ctor", "index"):
                lab, alls = candidates(g, s)
                if lab and resolve(g, s, B, "pessimistic")[0] != resolve(g, s, B, "optimistic")[0]:
                    amb[(g.lib, g.qual, s[1], ",".join(sorted({(h.klass.name if h.klass else h.file.split('/')[-1]) for h in lab})),
                         len(alls) - len(lab))] += 1
    extra.append(f"unhandled calls in labeled functions whose outcome depends on the target: {sum(amb.values())} at {len(amb)} (function, name) pairs")
    rng = random.Random(164)
    sample = rng.sample(rows, min(sample_n, len(rows)))
    with open(outdir / "summary.md", "w") as fh:
        fh.write("# Labels after panics: generated summary\n\nWritten by analyze.py; see ../README.md.\n\n"
                 + summ + "\n\n" + "\n".join(f"- {e}" for e in extra)
                 + "\n\n## Ambiguous calls in labeled functions, by target\n\n")
        for (lib, q, name, labs, unl), c in sorted(amb.items()):
            res = RESOLVE.get((lib, q, name), "pessimistic")
            fh.write(f"- {lib} {q} -> {name} x{c}: labeled in [{labs}], plus {unl} unlabeled; best: {res}\n")
        fh.write("\n## Ambiguous calls in orelse operands (outside labeled functions too)\n\n")
        for (lib, q, name, labs), c in sorted(or_amb.items()):
            res = RESOLVE.get((lib, q, name), "pessimistic")
            fh.write(f"- {lib} {q} -> {name} x{c}: labeled in [{labs}]; best: {res}\n")
        fh.write("\n## Sample (seed 164)\n\n")
        for g in sample:
            fh.write(f"- {g.lib} {g.file}:{g.line} {g.qual} [{'exported' if g.exported else 'private'}] "
                     f"after={int(B[id(g)])} ({'direct' if g.direct else 'calls'}) via={sorted(set(g.via))}\n")
    print(summ)
    print("\n".join(extra))


if __name__ == "__main__":
    main()
