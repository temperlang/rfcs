# /// script
# requires-python = ">=3.11"
# ///
"""Classify scan.py's output for the RFC 164 "no failure support" audit.

Classes: a = T? (or a nullable builtin) mechanically; b = panic (bug-like);
c = needs a library-defined result type (callers need the reason);
d = ambiguous, null is already a success value; f = other (Void needs a
convention, constructors, generators, test harness). Flag e = host-facing
(public or exported, or implemented by hosts).

Usage: uv run classify.py ROOT OUTDIR   (after scan.py ROOT OUTDIR)
"""
import re, sys, pathlib
from collections import Counter, defaultdict

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
def rows(name): return [l.rstrip("\n").split("\t") for l in open(out / f"{name}.tsv")]

def fname(text):
    m = re.search(r'(?:let|public|private|static|get)\s+(?:static\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*[<(]', text)
    if m: return m.group(1)
    m = re.search(r'constructor', text)
    if m: return "constructor"
    m = re.search(r'let\s+([A-Za-z_]\w*)\s*=', text)
    return m.group(1) if m else "?"

# (library, name) or (library, file-stem, line) overrides; default rules below.
B_CHROMARITE_FILES = {"adjust", "gamut", "hsv", "lab", "matrix", "mix", "helpers"}
PUBLIC = {
    "Argmas": {("values", 25)},
    "Chromarite": {("color", 101), ("color", 114), ("color", 278)},
    "Hrefine": {("host", 21), ("idna", 29), ("policy", 200), ("policy", 214), ("policy", 229),
                ("source", 35), ("url", 24), ("url", 41), ("url", 377), ("url", 395)},
    "Kelpto": {("tree", 491), ("tree", 511), ("build", 168), ("build", 241), ("build", 270),
               ("views", 587), ("views", 663), ("views", 670), ("views", 721), ("views", 832),
               ("views", 1164), ("views", 1507), ("views", 1533), ("views", 1746),
               ("walk", 238), ("walk", 250), ("walk", 261), ("walk", 267), ("walk", 274),
               ("walk", 292), ("walk", 305), ("walk", 309), ("walk", 315), ("walk", 322), ("walk", 333)},
    "Wherewith": {("core", 133), ("core", 178), ("core", 251), ("query", 98), ("query", 129),
                  ("query", 192), ("query", 561)},
}
STD_INTERNAL = {("json", 1285), ("json", 1299), ("json", 1313), ("json", 1327), ("json", 1341),
                ("json", 1361), ("testing", 54), ("testing", 110), ("regex", 453)}
CORE_INTERNAL = {("core", 257), ("core", 260), ("core", 264)}

def classify_decl(lib, path, line, text):
    stem = pathlib.Path(path).name.split(".")[0]
    name = fname(text); line = int(line)
    void = "): Void throws" in text
    key = (stem, line)
    if lib in ("std",):
        pub = key not in STD_INTERNAL
    elif lib == "core":
        pub = key not in CORE_INTERNAL
    else:
        pub = key in PUBLIC.get(lib, set())
    e = "e" if pub else ""
    if lib == "core":
        if name in ("toFloat64", "toInt32", "toInt64"): return "a", e, "number conversion: T?"
        if name in ("fromCodePoint", "fromCodePoints", "appendCodePoint"): return "b", e, "invalid code point is a bug (or String? for decoders)"
        if name in ("get", "remove"): return "d", e, "V is unbounded, so V? can't tell a missing key from a null value"
        return "f", e, "generator step: failure leaves next(); a generator yields its own result values"
    if lib == "std":
        if stem == "regex": return "a", e, "no match: Match?"
        if stem == "testing":
            if name in ("assertHard", "softFailToHard", "bail"): return "b", e, "a hard assertion becomes a panic"
            return "f", e, "test runner: tests can't fail, so runners must survive panics per test"
        if stem == "temporal":
            if name == "constructor": return "f", e, "constructor can't return null: a Date.of factory"
            return "a", e, "Date?"
        if name == "toJsonString": return "b", e, "producer used out of order: a bug"
        if name in ("parseJson", "toJsonSyntaxTree"): return "c", e, "callers want the message and offset (jsonError exists)"
        if line == 1275: return "d", e, "JsonAdapter<T>: T may itself be nullable"
        if line == 1390: return "d", e, "OrNullJsonAdapter: null is JSON null"
        return "a", e, "T?"
    if lib == "Argmas":
        return "a", e, "ValueType.parse: T? (hosts implement it)" if pub else "T?"
    if lib == "Chromarite":
        if stem in B_CHROMARITE_FILES or name in ("get", "alphaAt"):
            return "b", e, "fails only through indexing or division"
        return "a", e, "CSS parsing: Color?" if pub else "T?"
    if lib == "Hrefine":
        if name in ("withHosts", "withSubdomainsOf", "withPorts"):
            return "c", e, "configuration mistake: the bad entry is the reason (or a panic)"
        if name == "punycodeAdapt": return "b", e, "fails only through division"
        if void: return "f", e, "Void: return Boolean"
        return "a", e, "T?; reasons via checkUrl's log" if pub else "T?; reason noted in the ErrorLog"
    if lib == "Kelpto":
        if void: return "f", e, "Void: return Boolean"
        return "a", e, "T?"
    if lib == "Wherewith":
        if pub: return "c", e, "callers need the problem text (twins today)"
        if re.search(r'\):\s*\w+\?\s*throws', text):
            return "d", e, "null already means no such clause"
        if void: return "f", e, "Void: return Boolean; message in the problem field"
        return "a", e, "T?; message in the problem field"
    return "f", e, "?"

decls = rows("decls")
cls = []
for r in decls:
    lib, path, line, text, where = r
    c, e, note = classify_decl(lib, path, line, text)
    cls.append((lib, path, int(line), fname(text), c, e, note, text))

# Enclosing declaration for bubble() sites.
by_file = defaultdict(list)
for x in cls: by_file[x[1]].append(x)
def enclosing(path, line):
    best = None
    for x in by_file.get(path, []):
        if x[2] <= line and (best is None or x[2] > best[2]): best = x
    return best

bub = []
for lib, path, line, text, where in rows("bubbles"):
    enc = enclosing(path, int(line))
    c = enc[4] if enc else "?"
    if "orelse bubble()" in text: c = "a"   # `as … orelse bubble()`: an `is` check and return null
    bub.append((lib, path, int(line), c, enc[3] if enc else "?", text))

# orelse sites.
bclass_names = defaultdict(set)
for x in cls:
    if x[4] == "b": bclass_names[x[0]].add(x[3])
def operand(pre):
    """The expression `orelse` applies to: back to an unmatched bracket, `,`, `=`, `return`, or `;`."""
    depth = 0; i = len(pre)
    while i > 0:
        ch = pre[i-1]
        if ch in ")]}": depth += 1
        elif ch in "([{":
            if depth == 0: break
            depth -= 1
        elif depth == 0 and ch in ",;": break
        elif depth == 0 and ch == "=" and pre[i-2:i] not in ("==", "!=", "<=", ">=") and pre[i:i+1] != "=" and pre[i-2:i] != "=>":
            break
        i -= 1
    op = pre[i:].strip()
    op = re.sub(r'^(return|let\s+\w+(:\s*[\w<>?, ]+)?)\s*', '', op)
    return op

def toplevel(expr):
    out = []; depth = 0
    for ch in expr:
        if ch in "([{": depth += 1
        if depth == 0: out.append(ch)
        if ch in ")]}": depth -= 1
    return "".join(out)

def operation(op):
    top = toplevel(op)
    if re.search(r'\bas\s+[A-Z]', top): return "as"
    if re.search(r'\s[/%]\s', top): return "division"
    if op.endswith("]"): return "read"
    if op.endswith(")"):
        # find the matching "(" of the last ")"
        depth = 0
        for j in range(len(op)-1, -1, -1):
            if op[j] == ")": depth += 1
            elif op[j] == "(":
                depth -= 1
                if depth == 0: break
        head = op[:j].rstrip()
        m = re.search(r'([A-Za-z_]\w*)$', head)
        if not m:
            return operation(op[j+1:-1].strip()) if j < len(op) - 1 else "library call"
        name = m.group(1)
        if name in ("appendCodePoint",): return "appendCodePoint"
        if name in ("fromCodePoint", "fromCodePoints"): return "fromCodePoint"
        if name in ("toInt32", "toInt64", "toFloat64"): return "conversion"
        return "call:" + name
    if op.endswith("}"): return "block"
    return "other"

def orelse_class(lib, text, where):
    pre = text.split("orelse")[0] if text.count("orelse") == 1 else None
    return None

ors = []
src_cache = {}
def line_text(path, line):
    if path not in src_cache: src_cache[path] = (root / path).read_text().splitlines()
    return src_cache[path][line - 1]
seen = Counter()
for lib, path, line, kind, text, where in rows("orelse"):
    raw = line_text(path, int(line))
    k = seen[(path, line)]; seen[(path, line)] += 1
    idx = [m.start() for m in re.finditer(r'\borelse\b', raw)][k]
    pre = raw[:idx]; post = raw[idx + 6:].strip()
    opnd = operand(pre)
    op = operation(opnd) if opnd else "statement before"
    if not opnd:   # `} orelse …` closing a block on an earlier line
        op = "block"
    if op.startswith("call:"):
        name = op[5:]
        if name in bclass_names[lib] or (lib == "Chromarite" and name in ("get", "at", "alphaAt")):
            op = "bug-like library call"
        elif lib == "core":
            op = "Mapped.get"
        else:
            op = "library call"
    if op == "other" and opnd.startswith("this["): op = "Mapped.get"
    if re.search(r'\bas\s+[A-Z][\w<>, ?]*\s*$', pre): op = "as"
    if op == "block" and post.startswith("panic(") and lib in ("Chromarite", "std"):
        op = "bug-like block"   # a do block (or #203 whole-body wrapper) around reads, division, fromCodePoint
    if post.startswith("panic("):
        if op in ("as", "appendCodePoint", "fromCodePoint", "division", "read", "bug-like library call", "bug-like block"):
            c, note = "b", "the panic moves into the operation"
        else:
            c, note = "a", "?? panic()"
    elif op == "Mapped.get" or lib == "core":
        c, note = "d", "getOr/has built on get: needs a separate presence test"
    elif "hadBubble" in post or "test.assert" in post:
        c, note = "f", "test runner"
    elif op == "division":
        c, note = "b", "divisor already checked: the orelse goes"
    elif re.match(r'(true|false)\b', post):
        c, note = "f", "a Void call used as a check: needs a Boolean"
    elif post.startswith("null"):
        c, note = "a", "?? null, or nothing"
    elif op == "as":
        c, note = "a", "an `is` check, then return null"
    else:
        c, note = "a", "?? fallback"
    ors.append((lib, path, int(line), kind, op, c, where, note, text))

LIBS = ["Argmas", "Chromarite", "Hrefine", "Kelpto", "Ordable", "Wherewith", "std", "core"]
print("## Declarations (functions; std's TestFun alias and core's two function-typed slots included)")
print("lib\ttotal\ta\tb\tc\td\tf\te(host-facing)")
for lib in LIBS + ["All"]:
    xs = [x for x in cls if lib == "All" or x[0] == lib]
    c = Counter(x[4] for x in xs)
    print(f"{lib}\t{len(xs)}\t{c['a']}\t{c['b']}\t{c['c']}\t{c['d']}\t{c['f']}\t{sum(1 for x in xs if x[5])}")
print("\n## bubble() sites by enclosing class")
print("lib\ttotal\ta\tb\tc\td\tf")
for lib in LIBS + ["All"]:
    xs = [x for x in bub if lib == "All" or x[0] == lib]
    c = Counter(x[3] for x in xs)
    print(f"{lib}\t{len(xs)}\t{c['a']}\t{c['b']}\t{c['c']}\t{c['d']}\t{c['f']}")
print("\n## orelse sites")
print("lib\ttotal\ta\tb\tc\td\tf\tin-tests")
for lib in LIBS + ["All"]:
    xs = [x for x in ors if lib == "All" or x[0] == lib]
    c = Counter(x[5] for x in xs)
    print(f"{lib}\t{len(xs)}\t{c['a']}\t{c['b']}\t{c['c']}\t{c['d']}\t{c['f']}\t{sum(1 for x in xs if x[6]=='test')}")
print("\n## orelse panic() by operation")
print(Counter(x[4] for x in ors if x[3] == "panic"))

with open(out / "decls-classified.tsv", "w") as fh:
    fh.write("library\tfile\tline\tname\tclass\thost\tnote\n")
    for x in cls: fh.write("\t".join(map(str, x[:7])) + "\n")
with open(out / "bubbles-classified.tsv", "w") as fh:
    fh.write("library\tfile\tline\tclass\tin\ttext\n")
    for x in bub: fh.write("\t".join(map(str, x)) + "\n")
with open(out / "orelse-classified.tsv", "w") as fh:
    fh.write("library\tfile\tline\tfallback\toperation\tclass\twhere\tnote\ttext\n")
    for x in ors: fh.write("\t".join(map(str, x)) + "\n")
