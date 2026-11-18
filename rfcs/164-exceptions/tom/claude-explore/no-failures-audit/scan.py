# /// script
# requires-python = ">=3.11"
# ///
"""Scan Temper sources for `throws Bubble` declarations, `bubble()` calls, and
`orelse` sites, for the RFC 164 "no failure support" audit.

Usage: uv run scan.py ROOT OUTDIR
ROOT holds checkouts of argmas, chromarite, hrefine, kelpto, ordable,
wherewith, and tempest side by side.
Writes decls.tsv, bubbles.tsv, orelse.tsv into OUTDIR and prints a summary.
Code is indented lines in .temper.md, plus bare ``` fences (std/regex) or every line in .temper.
Files named *-tests.temper.md or wpt-*-tests.temper.md are skipped.
"""
import re, sys, pathlib

P = pathlib.Path(sys.argv[1])
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

def code_lines(path):
    text = path.read_text().splitlines()
    out = []
    if path.suffix == ".temper":
        for i, l in enumerate(text, 1):
            out.append((i, l))
        return out
    fence = None  # None outside; "code" inside a bare fence (compiled); "prose" otherwise
    for i, l in enumerate(text, 1):
        if l.startswith("```"):
            if fence is None:
                fence = "code" if l.strip() == "```" else "prose"
            else:
                fence = None
            continue
        if fence == "code":
            out.append((i, l)); continue
        if fence == "prose":
            continue
        if l.startswith("    ") or l.startswith("\t") or (out and l.strip() == "" ):
            out.append((i, l[4:] if l.startswith("    ") else l))
    return out

def strip_comments(l):
    # crude: drop // comments outside strings
    s = re.sub(r'"(\\.|[^"\\])*"', '""', l)
    k = s.find("//")
    return l[:k] if k >= 0 else l

def main():
    outdir = pathlib.Path(sys.argv[2]); outdir.mkdir(parents=True, exist_ok=True)
    decls, bubbles, orelses = [], [], []
    for lib, dirs in LIBS.items():
        for d in dirs:
            for f in sorted((P / d).rglob("*.temper*")):
                if f.name.endswith("-tests.temper.md") or f.name == "config.temper.md":
                    continue
                rel = f.relative_to(P)
                lines = code_lines(f)
                in_test = 0; depth = 0; test_depth = None
                in_doc = False
                for idx, (n, raw) in enumerate(lines):
                    st = raw.strip()
                    if st.startswith("/*"): in_doc = True
                    if in_doc:
                        if "*/" in st: in_doc = False
                        continue
                    l = strip_comments(raw)
                    if test_depth is None and re.match(r'\s*test\s*\(', l):
                        test_depth = depth
                    intest = test_depth is not None
                    if "throws Bubble" in l or "throws" in l and "Bubble" in l:
                        # join back to the declaration start
                        j = idx; buf = l
                        while j > 0 and not re.search(r'\b(let|fun|constructor|get|set|static|public|private|protected|export)\b|^\s*[A-Za-z_][A-Za-z0-9_]*\s*[<(]', lines[j][1]) :
                            j -= 1; buf = lines[j][1] + " " + buf
                        decls.append((lib, str(rel), n, " ".join(buf.split()), "test" if intest else "src"))
                    for m in re.finditer(r'\bbubble\s*\(\s*\)', l):
                        bubbles.append((lib, str(rel), n, st, "test" if intest else "src"))
                    for m in re.finditer(r'\borelse\b', l):
                        rest = l[m.end():].strip()
                        kind = "panic" if rest.startswith("panic(") else "null" if re.match(r'null\b', rest) else "other"
                        orelses.append((lib, str(rel), n, kind, st, "test" if intest else "src"))
                    depth += l.count("{") - l.count("}")
                    if test_depth is not None and depth <= test_depth and "}" in l:
                        test_depth = None
    for name, rows in (("decls", decls), ("bubbles", bubbles), ("orelse", orelses)):
        with open(outdir / f"{name}.tsv", "w") as fh:
            for r in rows:
                fh.write("\t".join(map(str, r)) + "\n")
    from collections import Counter
    print("lib\tdecls\tbubble()\torelse\tpanic\tnull\tother\t(in tests)")
    for lib in LIBS:
        d = sum(1 for r in decls if r[0] == lib)
        b = sum(1 for r in bubbles if r[0] == lib)
        o = [r for r in orelses if r[0] == lib]
        c = Counter(r[3] for r in o)
        t = sum(1 for r in o if r[5] == "test")
        print(f"{lib}\t{d}\t{b}\t{len(o)}\t{c['panic']}\t{c['null']}\t{c['other']}\t{t}")
    print("total", len(decls), len(bubbles), len(orelses), Counter(r[3] for r in orelses))

main()
