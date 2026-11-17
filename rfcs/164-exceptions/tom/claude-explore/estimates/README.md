# Estimates: failure handling's cost on real library workloads

How would today's bubbling compare with failures as values on Kelpto
(Markdown) and Wherewith (SQL), per backend, on their own workloads?
Mostly code review, backed by call counts on the generated code. Back to
[the overview](../README.md); per-failure and per-call costs come from
[bench](../bench/README.md),
[the compiler-known result forms](../README.md#a-compiler-known-result-type-likely-cost),
and [findings §2](../../claude-findings.md#2-speed).

Everything below is an **estimate**, labeled with its confidence. Counts
are exact for the inputs named; costs per call or per failure are
borrowed from the microbenchmarks; times per document or query are from
Kelpto's published benchmarks, or measured here on a busy machine (load
average 3 to 7), so read them as ranges.

**In short:**

- **Neither library throws on its benchmark workloads.** Kelpto's
  parser, renderer, and tree walk have no `throws Bubble` function at
  all, and no failure occurs on valid queries in Wherewith. Today's
  bubbling costs nothing there, except **Lua**, where each executed
  `orelse` (here all `orelse panic()` on builtins) makes a closure and a
  `pcall`: about 1 to 3 percent of a Kelpto parse and 3 to 6 percent of
  building a Wherewith query.
- **Under values, the per-call cost is small where fallible calls are
  dense.** Kelpto's parse makes no fallible call; Wherewith's query
  building makes 155 to 600 (about 7 percent of its calls): about 0 to 2
  percent on C++, C#, Java, JS, and Rust with a compiler-known result,
  and 0.5 to 3 percent on Python and Lua. A result type written as user
  code, as translated today, would cost far more there: 20 to 300
  percent on C++ and Rust, and 5 to 15 percent on Python and Lua.
- **Where today's bubbling does cost:** invalid SQL. Each one throws
  once through about 25 frames, which on C# may cost more than checking
  the whole query (an estimated 40 to 300 percent of it), on C++ 15 to
  100 percent, on Java and JS up to about 30 percent, and nothing to
  speak of on Python, Lua, and Rust. Values remove it.

## Method

1. **Workloads.** Kelpto: its benchmark (Kelpto's `bench/README.md`) parses, renders,
   walks, and transforms (every heading down a level in one `editor()`)
   the CommonMark spec (205 KB, 9,756 lines) and four READMEs, plus
   cmark's pathological inputs (parse only). Wherewith has no benchmark,
   so its demo's query stands in (`example`: a `SELECT` with `LIKE`,
   `ORDER BY … NULLS LAST`, `LIMIT`, `OFFSET`), with a larger one
   (`bigger`: a join, a subquery, `GROUP BY`, `HAVING`, three values), each
   built (lexed, parsed, and checked for five targets) and rendered for
   four dialects, and an invalid one (`SELECT a, b FROM t WHERE a = (b +`).
2. **Static review** of the hot paths: every `throws Bubble`
   declaration, `bubble()`, and `orelse` in the libraries' non-test
   sources.
3. **Dynamic counts** on the generated code in each repo's `temper.out`
   (temper-core 0.7.0-alpha.0.243, 2026-11-17), copied to a scratch
   folder:
   - **Python**, with `sys.monitoring`: calls of the functions declared
     `throws Bubble` (matched by class and name, all 49 of Kelpto's and
     104 of Wherewith's found), all calls into the library, and every
     exception raised, unwound, and caught
     ([count_kelpto_py.py](scripts/count_kelpto_py.py),
     [count_wherewith_py.py](scripts/count_wherewith_py.py)).
   - **Lua**, by wrapping `temper.pcall` (each executed `orelse`) and
     `temper.bubble`, with call sites
     ([count_kelpto_lua.lua](scripts/count_kelpto_lua.lua),
     [count_wherewith_lua.lua](scripts/count_wherewith_lua.lua)).
4. **Costs per backend:** today, failures times the measured cost of a
   failure, plus Lua's `pcall`s; under values, fallible calls times the
   measured per-call cost of the representation, plus failures times a
   failure value's cost. Small microbenchmarks for Lua's `pcall` and
   for a result check in Python and Lua
   ([pcall_cost.lua](scripts/pcall_cost.lua),
   [check_cost.py](scripts/check_cost.py),
   [check_cost.lua](scripts/check_cost.lua)), and JS timings of
   Wherewith's workloads ([time_wherewith_js.mjs](scripts/time_wherewith_js.mjs)).

## Kelpto

### Hot paths and sites

| Path | Files | `throws Bubble` | `orelse` outside tests |
|---|---|---|---|
| Block parser | `blocks.temper.md`, `parse.temper.md` | none | `orelse panic()` on builtins only |
| Inline parser | `inlines.temper.md` | none | `orelse panic()` on builtins only |
| Renderer | `render.temper.md` | none | `orelse panic()` on builtins only |
| Walk (`descendants`, `asWritten`) | `views.temper.md`, `kelpto-core/tree.temper.md` | none on this path | `orelse panic()` only |
| Transform (`editor()`, `setLevel`, `toDocument`) | `walk.temper.md`, `edit.temper.md`, `views.temper.md`, `kelpto-core/tree.temper.md` | 49 in all, a few per edit | none outside tests |

Every `orelse` in Kelpto's non-test code is `orelse panic()`, on `as`
(mostly a nullable made non-null), list reads, `appendCodePoint`, and
`String.fromCodePoint`: none can fail on any input, by construction.
Every non-panic `orelse` (`orelse "bubbled"`) is in a test. The busiest
site, from the block parser, runs once per open block per line:

```temper
let clearLastLineBlank(block: BlockData?): Void {
  var at = block;
  while (at != null) {
    let b = at as BlockData orelse panic();
    b.lastLineBlank = false;
    at = b.parent;
  }
}
```

The bubbling functions are the editing API's checks: a heading level
outside 1 to 6, a setext heading deeper than 2, a tab inside a list
item's prefix, a removed link definition still referenced, and so on.
The benchmark's transform never asks for one (it skips level 6 and
setext level 2), so none fails:

```temper
let headingLevelEdit(node: RedNode, level: Int): Replacement throws Bubble {
  if (level < 1 || level > 6) { bubble(); }
  ...
```

### Counts per document (exact)

| Document | Task | Library calls (Python) | Fallible calls (`throws Bubble`) | Failures | Executed `orelse` (Lua `pcall`s) |
|---|---|---|---|---|---|
| CommonMark spec, 205 KB | parse | 1,153,730 | 0 | 0 | 29,097 (about 3 per line) |
| | render | 1,818,372 | 0 | 0 | 29,988 |
| | walk | | 0 | 0 | 29,097 |
| | transform (45 edits) | 1,331,262 | 185 | 0 | 29,322 |
| Hrefine README, 32 KB | parse | 144,477 | 0 | 0 | 3,040 |
| | transform (13 edits) | 155,913 | 57 | 0 | 3,105 |
| Kelpto README, 6 KB | parse | | 0 | 0 | 374 |

The 185 in the transform are `setLevel`, `headingLevelEdit`, `pathTo`,
and `rebuild` once per edit, plus one `toDocument` chain. Lua's `pcall`s
come from 10 sites; two in the block parser (`reach` and
`clearLastLineBlank`, as above) make 98 percent of them. In Python, JS,
Java, C#, and C++, the same `orelse panic()` is a `try` block, which
costs nothing until something throws (C#: a method with `try` isn't
inlined on .NET 6, unmeasured here). Pathological inputs are parsed
only, through the same code, so they make no fallible call either.

### Per backend (estimates, percent of the benchmark's time)

Benchmark times per spec parse, from Kelpto's
`docs/benchmarks.md` (2026-11-02 and later tuning): C++ about 25 ms, C#, Java, JS, and Rust about 60 to
100 ms, Python about 640 ms, and Lua about 870 ms.

| Backend | Today: parse, render, walk | Today: transform | Values: parse, render, walk | Values: transform |
|---|---|---|---|---|
| C++ | 0 (no failures; `try` free) | 0 | 0 (no fallible calls) | under 0.01% |
| C# | about 0 (no failures; possible inlining loss from `try`, unmeasured) | about 0 | 0 | under 0.01% |
| Java | 0 | 0 | 0 | under 0.01% |
| JS | 0 | 0 | 0 | under 0.01% |
| Lua | **1 to 3%** (29,000 `pcall`s at 0.3 to 0.6 µs) | 1 to 3% | 0, and the `pcall`s go if those builtins panic or return nullables | under 0.01% |
| Python | 0 (`try` is free in 3.11 and later) | 0 | 0 | under 0.01% (185 checks, about 10 to 40 µs in 640 ms or more) |
| Rust | 0 | 0 | 0 | 0 (already a `Result`) |

**Confidence:** high that neither design costs anything measurable on
Kelpto's parse, render, and walk, and that the transform's difference is
negligible: no bubbling declaration on those paths, and counted zero
failures and zero fallible calls on three documents in two backends.
Medium on Lua's 1 to 3 percent: the count is exact, but the `pcall`
cost comes from a microbenchmark on a busy machine (0.4 to 0.6 µs over
a direct call, against a parse taking 0.65 to 1.25 s on the same
machine), and an A/B timing of the whole parse with the `pcall`s
removed was inconclusive under that load (runs varied by 30 to 50
percent). Lua's saving belongs to [which builtins
panic](../../claude-common-ground.md#which-builtins-panic) as much as to
values: a panicking `as` or `appendCodePoint` needs no `pcall` under any
design.

**Cheapest confirmation:** on a quiet machine, copy `temper.out/lua`,
run [strip_pcall.py](scripts/strip_pcall.py) on the copy's
`kelpto-md/init.lua` and `kelpto-core/init.lua` (64 sites rewritten
without the closure and `pcall`), and time both copies back to back with
[time_kelpto_lua.lua](scripts/time_kelpto_lua.lua) (minutes).

## Wherewith

### Hot paths and sites

| Path | Where | What can fail |
|---|---|---|
| Lexing (`appendSafe`, holes) | `CommonLexer` | nothing bubbles; problems (a bare mixed-case name, an unterminated string) are stored as values |
| Parsing | `CommonParser` (41 bubbling), `StatementParser` (56 in the file) | `need(message)` when tokens run out, wrong tokens; every grammar rule is `throws Bubble` |
| Checking | `CommonChecker.check`, `StatementChecker`, `NameCases` | `fail(message, at)` (68 sites) for what databases read differently |
| Rendering | `Query.render`, `Dialect.quoteName`, `quoteString` | a name or string the dialect can't write (NUL, too long) |
| `folded`, `quoteName` | per character, per name | `appendCodePoint` and `String.fromCodePoint` with `orelse panic()` |

The parser is recursive descent with one function per precedence level,
so every operand passes through about ten bubbling calls
(`expression`, `disjunction`, `conjunction`, `negation`, `predicate`,
`concatenation`, `sum`, `product`, `unary`, `primary`):

```temper
private product(): CommonExpr throws Bubble {
  var e = unary();
  ...
    let right = unary();
```

None of these fail on a valid query. One failure, on invalid SQL, is
caught once, in `commonCheck` and `QueryBuilder`'s template check:

```temper
let tree: CommonStatement? = parser.parseStatement() orelse null;
```

The only other non-panic `orelse`s are constant folding's division
(`(a / b) orelse null`, after a zero check), and the renderer's
`quoteString(value) orelse ""` and `quoteName(value) orelse ""` beside
their `…Problem` twins; none fails on valid input. No `orelse` is a
parse attempt that fails and falls back, so failures don't scale with
input size.

### Counts per query (exact, for these queries)

| Workload | Library calls (Python) | Fallible calls | Failures (frames unwound) | Executed `orelse` (Lua `pcall`s) |
|---|---|---|---|---|
| example: build (lex, parse, check) | 2,064 | 155 | 0 | 136 |
| example: render for 4 dialects | 2,325 | 33 | 0 | 50 |
| bigger: build | 8,640 | 602 | 0 | 1,046 |
| bigger: render for 4 dialects | 6,763 | 148 | 0 | 284 |
| bare mixed-case name (refused by the lexer) | 125 | 0 | 0 | |
| syntax error | 888 | 88 | 1 (25) | 16 (1 failed) |
| `quoteName` and `quoteString`, 4 dialects | 53 | 8 | 0 | |

Fallible calls are about 7 percent of the library's calls when building
and about 1.5 to 2 percent when rendering; the busiest are `need` (17 and 69
per build), the precedence chain (5 to 6 and 23 per level), and
`CommonChecker.check` (8 and 31). Lua's `pcall`s are mostly `folded`,
which lowercases a name with `appendCodePoint(…) orelse panic()` per
character (339 of 386 in one build and render of a mid-sized query).

Times per query, measured here (busy machine; ranges over rounds):

| Backend | example: build | example: render ×4 | bigger: build | bigger: render ×4 | syntax error / valid twin |
|---|---|---|---|---|---|
| JS | 40 to 57 µs | 67 to 97 µs | 127 to 236 µs | 176 to 212 µs | 15 to 18 / 13 to 23 µs |
| Lua | 1.7 ms | 3.8 ms | 11.4 ms | 24 ms | 1.6 ms |
| Python | 0.9 to 3.5 ms | 2.3 to 4.6 ms | 3.7 to 7.3 ms | 5.5 to 10 ms | 0.36 to 0.58 ms |

For C++, C#, Java, and Rust, not run: assumed within a few times of
JS (they are within 10 percent of each other on Kelpto, C++ faster),
about 10 to 60 µs per `example` build.

### Per backend (estimates, percent of the workload's time)

Per-call cost under values: a compiler-known result in each backend's
cheapest form ([hand-written measurements](../README.md#a-compiler-known-result-type-likely-cost)).
Nearly all of Wherewith's fallible functions return references
(`CommonExpr`, `CommonToken`, `String`, `Query`) or `Void`; the one
`Int`, `check`'s kind, is a small constant (inside the JVM's `Integer`
cache). Per-failure cost today: from [findings
§2](../../claude-findings.md#2-speed), scaled to about 25 frames.

| Backend | Today: valid query | Values: valid query (build; render about a quarter of this) | Today: invalid query (1 failure) | Values: invalid query |
|---|---|---|---|---|
| C++ | 0 | 0 to 2% (`std::expected`, about 0.3 to 1 ns per call) | +15 to 100% (2 to 5 µs) | about 0 |
| C# | 0 | 0 to 1% (`readonly struct`, as cheap as today's success path) | **+40 to 300%** (15 to 50 µs on .NET 6) | about 0 |
| Java | 0 | 0 to 1% (plain reference or `Failed`, nothing boxed) | +5 to 25% (1 to 4 µs with a stack trace) | about 0 |
| JS | 0 | 0 to 0.5% (plain value or `Failed`) | 0 to 30% (3 to 5 µs; measured within noise of the valid twin) | about 0 |
| Lua | **3 to 6%** of a build, under 1% of rendering (`pcall`s) | +0.5 to 1.5% (a tag check per call), or **2 to 5% faster** if the `orelse panic()` builtins lose their `pcall`s too | under 0.1% | about 0 |
| Python | 0 | +0.5 to 3% (an `isinstance` or `is` check per call, 25 to 60 ns on a quiet machine) | under 1% (1 to 3 µs) | about 0 |
| Rust | 0 | 0 (already a `Result`) | 0 | 0 |
| Any, result written as user code (today's translation) | | Java, JS: +0.5 to 2%; Python, Lua: +5 to 15%; **C++, Rust: +20 to 300%** (an allocation and casts per call, 85 to 175 ns) | | as the row above |

For an application, these are percentages of building or rendering a
query, which is usually done once per statement, or cached, and is
small beside a database round trip. The invalid-query column matters
where invalid SQL is common: an admin tool or editor checking SQL as it
is typed, where most inputs are incomplete. There, on C#, one exception
can cost more than checking the rest of the query, though still well
under a millisecond.

**Confidence:**

- **Counts:** high for these queries (exact); medium that they
  represent real use, since Wherewith has no benchmark. Larger queries
  scale the counts with operands (about ten fallible calls each) and
  names (one `pcall` per character in Lua), but not the failures, which
  stay at most one per query.
- **Values on C++, C#, Java, JS, and Rust:** medium. The per-call costs
  are from hand-written forms in a tiny loop; real generated code could
  differ (the JVM without inlining measured up to 2.6 times a nullable
  at depth 5, but that was for a boxed `Int`; references don't box).
- **Python and Lua:** medium; their per-check and per-`pcall` costs come
  from microbenchmarks on a busy machine, as ratios to the workload
  timed on the same machine.
- **Invalid queries:** low to medium; the per-failure costs are from
  other benchmarks at depths 1 and 20, and the C++, C#, and Java query
  times are assumed, not measured.

**Cheapest confirmation**, in order:

1. Time valid and invalid queries in C# and Java with the demo projects'
   setup (as [time_wherewith_js.mjs](scripts/time_wherewith_js.mjs) does
   for JS): the C# failure cost is the largest and least certain number
   here.
2. A Lua A/B with [strip_pcall.py](scripts/strip_pcall.py) on a copy of
   `temper.out/lua/wherewith/init.lua`, timed with
   [count_wherewith_lua.lua](scripts/count_wherewith_lua.lua).
3. For the values side, lower `CommonParser` by hand in a copy of the
   generated Python or JS (`raise` becomes returning a `Failed`, and a
   check follows each of the bubbling calls), and time `example` and
   `bigger` against the original.

## Notes

- The generated code measured is what each repo's `temper.out` held on
  2026-11-17 (temper-core 0.7.0-alpha.0.243). Another translation of
  `orelse panic()` (no `pcall` in Lua, say) changes the Lua rows, not
  the others.
- The counts treat a call as fallible when its callee is declared
  `throws Bubble`. Builtins under `orelse panic()` (`as`, list reads,
  `appendCodePoint`) are counted only through Lua's `pcall`s; elsewhere
  they cost a `try` block today and a null check, or nothing if they
  panic, under values.
- Reproducing: copy `temper.out/py`, `temper.out/lua`, or `temper.out/js`
  from a built checkout to a scratch folder, then run the scripts in
  [scripts/](scripts/) with the paths they name in their headers
  (`uv run` for the Python ones, which need Python 3.12 for
  `sys.monitoring`; `lua` 5.4; Node).
