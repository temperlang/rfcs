# Failure handling on real library code

Explorations for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)):
real failure paths from public Temper libraries and std, each written
today's way, as design A (runnable today), and as designs A with sugar,
B, and C (hypothetical syntax), plus a benchmark of what failing costs
on each backend. Background: [claude-thoughts.md](../claude-thoughts.md)
("Failures as values: a fuller sketch"),
[claude-findings.md](../claude-findings.md),
[tom-thoughts.md](../tom-thoughts.md), and
[mike-thoughts.md](../mike-thoughts.md).

Everything marked **hypothetical** is invented syntax for comparison
and does not compile. Everything else (`current/` and `values/` in each
case, and the benchmark) was built and tested with tempest's `temper`
(0.7.0-alpha) on all eight backends: interp, C++, C#, Java, JS, Lua,
Python, and Rust, except Argmas's design A on C#, which hits a C#
backend gap (a generic interface method returning `T?`; see that
case's notes).

## The designs

- **Today:** `throws Bubble`, `bubble()`, `orelse`, `panic()`. A
  failure carries nothing; propagation is implicit inside a
  `throws Bubble` function.
- **A, values:** absence is `T?`; failure with a reason is a small
  generic result type (written here as user code, a sealed interface
  with `Ok<T, E>` and `Failed<T, E>`, in each case's
  `values/result.temper.md`); bugs `panic()`. Propagation today is
  `if (x == null) { return null; }` or a `when`. **Runnable.** A *with a
  propagation operator* (postfix `?`) and backend-aware translation
  is **hypothetical**.
- **B, Mike's single declared failure type:** `throws E`, where `E` is
  one type, usually a sealed interface of variants; constructors take
  an optional message and cause, opaque to Temper; `catch` with
  `match`. **Hypothetical.**
- **C, Tom's declared error kinds:** `error case X;`, `throws X, Y`,
  explicit `try` or `!` to propagate, no details. **Hypothetical.**

## Cases

| Case | From | What fails | Folder |
|---|---|---|---|
| Value types and argument errors | Argmas | `ValueType.parse` (text to a value, implementable in host code); `ArgError` values | [argmas-values](argmas-values/) |
| URL parsing and validation errors | Hrefine | the URL parser's fatal errors, beside a log of non-fatal ones | [hrefine-url](hrefine-url/) |
| Problem strings | Wherewith | `quoteName` and its `nameProblem` twin; a recursive-descent parser's `need(message)` | [wherewith-problems](wherewith-problems/) |
| JSON parsing and decoding | tempest's `std` | `parseJson`'s dropped message; adapters failing on `as` and `toInt32` | [std-json](std-json/) |
| An internal `throws Bubble` chain | Chromarite | out-of-range reads and division bubbling through 31 internal declarations | [chromarite-matrix](chromarite-matrix/) |
| Benchmark | | a loop failing at 0, 0.1, 1, and 10 percent | [bench](bench/) |

Each case folder has a README (what the code does, each design side by
side, what host code sees, notes, and precedence), `current/` (today's
code, simplified but faithful, with tests), `values/` (design A, with
the same tests), and `hypothetical.md` (A with sugar, B, and C).

## Comparison

Code lines (indented Temper code, without tests; A's 3-line result type
not counted):

| Case | Today | A, runnable | A with `?` (hypothetical) | B (hypothetical) | C (hypothetical) |
|---|---|---|---|---|---|
| Argmas | 125 | 125 | about 122 | about today's | about today's, plus kinds; `ArgError` stays a value |
| Hrefine | 86 | 101 | about today's | about today's | today's plus a kind per error name (29 in the full parser); positions only via the log |
| Wherewith | 84 | 113 | today's less the twin and field | the same as A with `?` | today's plus kinds; twins stay |
| std JSON | 91 | 134 | about today's | about today's plus a sealed type | today's plus 2 kinds; offset and path lost |
| Chromarite | 78 | 81 | the same | the same | the same |

By design:

| | Today | A, runnable today | A as proposed (hypothetical) | B (hypothetical) | C (hypothetical) |
|---|---|---|---|---|---|
| A failure carries | nothing | any value the library declares | the same | a declared type's fields, plus an opaque message and cause | its kind only |
| Propagation | implicit | explicit: `if … return` or `when`, re-wrapping `Failed` when `T` changes | postfix operator per call | marker per call (`!`), `catch` with `match` | `try` or `!` per call |
| Python host sees | `RuntimeError()` with no message, or the host's own builtin exception | `None`, or `Ok`/`Failed` objects | a value form and, if asked for, a throwing form | a generated exception class per type | a generated class per kind (or one class with a tag) |
| Java host sees | `RuntimeException`, null message | `null`, or `Result<T, E>` with `instanceof` | as Python | as Python | as Python |
| Rust host sees | `Err(Error(None))` | `Option<T>`, or a generated `Result_<T, E>` (`Arc<dyn …>` with downcasts) | `Result<T, E>` | `Result<T, E>` with an enum | `Result<T, Kind>` |
| Accumulated errors (Hrefine's list) | a value | a value | a value | a value | a value |
| Status | runnable | runnable, tested on 8 backends (7 for Argmas) | hypothetical | hypothetical | hypothetical |

## Measurements

From [bench](bench/README.md) (run 1, a quiet machine): range of three
rounds' medians, depth 1 (the step fails, its caller handles it).
Ratios are to the nullable version in the same round.

| Backend | Success path: bubble / null | result / null | 10% failures: bubble / null | result / null |
|---|---|---|---|---|
| interp | 0.9-1.0x | 1.5-1.6x | 1.0x | 1.5-1.6x |
| C++ | 1.0-1.2x | 41-48x | 48-58x | 30-40x |
| C# | 0.5-0.8x | 2.2-3.4x | 81-107x | 2.5-3.2x |
| Java | 0.9-1.0x | 1.2-1.6x | 11-18x | 2.4-4.2x |
| JS | 0.8-1.0x | 1.0-1.4x | 13-18x | 0.9-1.4x |
| Lua | 0.6-1.3x | 0.9-2.1x | 1.1-1.3x | 2.0-2.3x |
| Python | 1.0-1.1x | 1.2-1.3x | 0.9-1.2x | 1.2-1.5x |
| Rust | 0.9-1.0x | 132-139x | 0.9-1.3x | 135-155x |

In short: a nullable return is as cheap as today's success path and
stays cheap when failing, except on the two managed runtimes. On the
JVM an `Int?` is a boxed `Integer`; the JIT removes the boxes only
while no null has occurred, so through five calls at 0.1 percent
failures `null` takes 3.5 to 4 times as long as today's bubbling (12-14
against 3.2-3.8 ns), and the crossover where bubbling becomes dearer is
between 0.1 and 1 percent. A hand-written `long` with a sentinel for
null (what lowering an internal `Int?` could give) costs 2.3 to 3.5 ns
at every rate. On .NET 6, `int?` through five calls costs 50 to 110 ns
against 9 to 22 for bubbling, with or without inlining, until failures
pass about 0.1 to 1 percent. Today's bubbles cost 2 to 13 times at 1
percent failures and 11 to 107 times at 10 percent on C++, C#, Java,
and JS, and about nothing elsewhere. The user-defined result type costs
an allocation per call: modest on the JVM, JS, and Python (1.0 to 1.6
times on the success path), more on interp and Lua (1.5 to 2.3 times),
and very large on C++ and Rust (40 to 140 times) because of how
user-defined sealed classes are translated there today; Rust's bubble,
already a native `Result`, costs 1.3 ns. At depth 5 the result type
pays an `Ok` per level (1.6 to 3.9 times on most backends; 400 to 900
ns per item on C++ and Rust).

## What dropping `throws Bubble` would take

If `throws Bubble` went away in favor of nullables (design A's first
tier), how much of today's code converts mechanically? Counted over the
public libraries (Argmas, Chromarite, Hrefine, Kelpto, Ordable,
Wherewith) and tempest's `lib/std` and `lib/core`, in non-test sources
(indented Temper code; tests in separate files excluded).

**Declarations.** 286 functions, methods, and constructors declare
`throws Bubble` (plus one function type alias, std's `TestFun`, and two
function-typed fields and parameters in core):

| Library | Total | Public | Internal |
|---|---|---|---|
| Argmas | 8 | 1 | 7 |
| Chromarite | 52 | 3 | 49 |
| Hrefine | 24 | 10 | 14 |
| Kelpto | 49 | 25 | 24 |
| Ordable | 0 | 0 | 0 |
| Wherewith | 104 | 7 | 97 |
| std | 34 | 27 | 7 |
| core (builtins) | 15 | 14 | 1 |
| **All** | **286** | **87** | **199** |

**Where null can't simply mean failure:**

- **Already nullable (5):** Wherewith's statement parser
  `sourceAlias(): CommonName?`, `joined(): CommonJoin?`,
  `joinedAt(t): CommonJoin?`, and `where(): CommonExpr?` (null means
  "no such clause", a bubble means a syntax error); std's
  `OrNullJsonAdapter.decodeFromJson(t): T?` (null is JSON `null`).
- **`Void` (69):** 15 public (Kelpto's `MarkdownEditor.setText`,
  `setContent`, `setLevel`, `setInfo`, `setDestination`, `setLabel`,
  `insertBefore`, `insertAfter`, `replace`, `remove`, and
  `MarkdownBuilder.heading` and `orderedList`; std's `Test.assertHard`,
  `softFailToHard`, and `runTest`) and 50 internal (44 in Wherewith's
  parser and checkers, 5 in Kelpto, 1 in Hrefine), plus 3 in Chromarite
  (counted below as bug-like) and core's `appendCodePoint` (counted
  with the builtins). There's no null to return; each needs a
  convention (return `Boolean`, or a result with a unit success).
- **`Never<Void>` (1):** std's `Test.bail`.

**Constructors that can bubble (1):** std's
`Date(year, month, day)`, which bubbles for a day that doesn't exist.
A constructor can't return null, so it would need a factory
(`Date.of(…): Date?`), and host code's `new Date(…)` changes. No library
constructor or initializer bubbles.

**Builtins and operators.** core declares 15 (`String.toInt32`,
`toInt64`, `toFloat64`, `fromCodePoint`, `fromCodePoints`,
`StringBuilder.appendCodePoint`, `Mapped.get`, `MapBuilder.remove`,
`Int64.toInt32`, `toFloat64`, `Float64.toInt32`, `toInt64`,
`Generator.next`, and two `next` implementations), and `/`, `%`, and
`as` bubble without a declaration. Of 596 `orelse`s in these sources,
500 are `orelse panic()`, 36 `orelse null`, and 60 other fallbacks. The
`orelse panic()`s are on `as` downcasts (204), list or map reads (56),
`appendCodePoint` (40), `/` and `%` (14), `String.fromCodePoint` (6),
and conversions (1); the other 179 are on the libraries' own bubbling
functions, mostly in tests inside source files and in public wrappers
like Chromarite's `inGamut`.

**How mechanical the rewrite is.** The rules: `throws Bubble` becomes
`T?`; `bubble()` becomes `return null`; `orelse x` becomes `?? x`; and
implicit propagation becomes a statement, since `?? return null`
doesn't parse today (`return` isn't an expression):

```temper
// Today: propagates implicitly.
adapter.decodeFromJson(parseJson(text))

// HYPOTHETICAL, doesn't parse today:
adapter.decodeFromJson(parseJson(text) ?? return null)

// What compiles today, after the rewrite:
let tree = parseJson(text);
if (tree == null) { return null; }
adapter.decodeFromJson(tree)
```

Hoisting a call out of an expression to check it must hoist everything
evaluated before it too (`a() + f(x)` becomes `let l = a(); let r =
f(x); if (r == null) …`), so the rewrite is mechanical but not local.

Sorted by what each declaration needs:

| | Count | Share |
|---|---|---|
| Mechanical: rules above suffice (104 internal, 51 public) | 155 | 54% |
| Mechanical given one convention for `Void` (internal) | 50 | 17% |
| A human decision | 81 | 28% |

The 81: 30 Chromarite functions that bubble only because of `/`, `%`,
indexing, and size checks (they should panic, not return null); 15
public `Void` methods; 15 builtins (their contract is std's and
core's); 14 interface methods hosts implement and their implementations
(Argmas's `ValueType.parse`, std's `JsonAdapter.decodeFromJson`); 5
already nullable; 1 constructor; 1 `Never`. Separately, every one of
the 87 public declarations changes what host code sees (a return value
instead of an exception) unless throwing forms are generated for hosts.

Three of the non-mechanical cases:

```temper
// Wherewith (common-statements.temper.md): null already means
// "no WHERE clause"; a bubble means a syntax error after WHERE.
private where(): CommonExpr? throws Bubble {
  if (!p.isKeyword(p.peek(), "where")) { return null; }
  p.advance();
  p.expression()
}

// std (temporal.temper.md): a constructor can't return null.
public constructor(year: Int, month: Int, day: Int): Void throws Bubble {
  if (1 <= month && month <= 12 && 1 <= day && ...) {
    this.year = year; this.month = month; this.day = day;
  } else {
    bubble();
  }
}

// Chromarite (hsv.temper.md): bubbles only because Float64 `/` does by
// the docs; a mechanical `Float64?` would spread nulls through color
// math. The decision is about the builtin (panic, or IEEE Infinity/NaN).
let wrap(x: Float64, modulus: Float64): Float64 throws Bubble {
  x - (x / modulus).floor() * modulus
}
```

Counts come from a scan of declarations (a declaration's line through
`throws Bubble`, joined across lines), classified by return type,
enclosing class, and `export`; the categories "bug-like" and
"interfaces hosts implement" were assigned by reading the code, and
are estimates.

## Added measurements

Two more measurements, for questions the designs raise: how many
explicit propagation markers they would add to today's code, and what a
result type the compiler knows might cost on each backend.

### Propagation markers

Today a call to a `throws Bubble` function inside another `throws
Bubble` function propagates silently. Under B and C each such call
needs a marker (`!`, `try`), and under A a postfix `?` or, without one,
a statement. How many such call sites are there?

**Method.** tempest's Rust backend shows the type checker's answer
directly: `throws Bubble` becomes a `temper_core::Result` return, each
implicitly propagating call becomes a Rust `?` (or, in tail position,
a call whose `Result` is returned as it is), and `orelse` becomes an
immediately called closure or `.unwrap_or(…)`. So
[bench/markers/count_markers.py](bench/markers/count_markers.py)
tokenizes the generated Rust for the same sources as above (the six
public libraries and `lib/std`; tests and the generated init, glue,
and `support/` files left out) and counts each `?` whose innermost
enclosing function returns `temper_core::Result`, outside the closures
that `orelse` makes, plus tail calls returning a `Result` that isn't an
`Ok(…)` or `Err(…)`. Generated forwarders (an interface's `impl Trait
for Type` calling the class's own method) aren't counted. A site is
public when its function is: a `pub fn` at module level, or a method
of a `pub` type or trait. Three bubbling helpers defined in test files
(Argmas's `Even` and `Port`, Hrefine's `setPart`) are left out, as the
tests are. Typed, so it sees through `/` with a non-constant divisor,
failing `as`, and methods reached through receivers; a parse of the
Temper source would have to guess those. Error sources: tail-call
detection is a backward walk over `if`/`else` and `match` arms, which
could miss a tail in some other block form; the public rule follows
Rust visibility, not Temper's (an internal class implementing a public
interface counts as internal); and core's two pure-Temper fallback
bodies (`Generator.next` calling its function, and `appendCodePoint`
calling `String.fromCodePoint`) aren't in the Rust output, so they're
counted by hand and left out of the table. Spot check by hand: six
functions across all six sources (Argmas's `IntType.parse`,
Chromarite's `parseCssColor`, Hrefine's `punycodeDecode`, Kelpto's
`editAll`, Wherewith's `StatementParser.insert`, and std's
`Date.fromIsoString`), 38 sites, matched the count exactly. Every site
is listed in
[bench/markers/results/sites.tsv](bench/markers/results/sites.tsv).

| Library | Sites | Public | Internal | Library calls | Builtins | `/` and `%` | `as` | Functions with a site / bubbling functions |
|---|---|---|---|---|---|---|---|---|
| Argmas | 5 | 0 | 5 | 2 | 3 | 0 | 0 | 3 / 7 |
| Chromarite | 140 | 2 | 138 | 119 | 2 | 19 | 0 | 38 / 52 |
| Hrefine | 36 | 10 | 26 | 26 | 0 | 10 | 0 | 19 / 24 |
| Kelpto | 52 | 30 | 22 | 52 | 0 | 0 | 0 | 35 / 49 |
| Ordable | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 / 0 |
| Wherewith | 365 | 1 | 364 | 365 | 0 | 0 | 0 | 89 / 104 |
| std | 32 | 22 | 10 | 12 | 13 | 0 | 7 | 22 / 32 |
| **All** | **630** | **65** | **565** | 576 | 18 | 29 | 7 | 206 / 268 |

Plus 2 in core's fallback bodies. 82 of the 630 are tail calls (the
call is the function's result), which a marker would still have to
cover. Beside them, 65 calls already sit under an `orelse` and need no
new marker.

**Concentration:** spread out, not concentrated. The 630 sites sit in
206 functions; the top 5 hold 93 (15 percent), the top 10 hold 149 (24
percent), and half the sites are in 37 functions (18 percent of those
with a site). 89 functions have exactly one site. The largest are
Wherewith's `CommonChecker.check` (28), `StatementChecker.select` (18),
Chromarite's `fitContrastRows` (17), Wherewith's
`StatementParser.select` (16), and `CommonChecker.call` (14). Per
library, the top 5 functions hold 24 percent of Wherewith's sites, 35
percent of Chromarite's and Kelpto's, 38 percent of std's, and 53
percent of Hrefine's.

What the sites are:

- **Wherewith (365, 58 percent of all):** a recursive-descent parser
  and checkers, where nearly every step can fail. 68 are calls to
  `CommonChecker.fail(message, at)`, a `Void` helper that records the
  problem and always bubbles: a raise in disguise, which under A or B
  would become a `return`/`throw` of the problem rather than a marker.
- **Chromarite (140):** 52 are reads through `Matrix.get`, `at`, and
  `alphaAt`, and 19 are Float64 `/`: the bug-like bubbles of
  observation 7. Once out-of-range reads panic and the division
  question is settled, about half of these go, and with them much of
  the rest (the callers that bubble only because of them).
- **Public (65):** mostly Kelpto's `MarkdownEditor` methods and its
  tree edits (30) and std's JSON adapters, `Date`, and regex (22). Of
  std's 32, 13 are builtin conversions (`toInt32`, `toFloat64`,
  `Int64.toInt32`, …) and 7 a failing `as`.

So each design with explicit markers would add about 630 markers to
these libraries (about one per 60 lines of their indented Temper code,
tests in separate files left out), most in
parsers and checkers, where a marker on nearly every line is the cost
of making propagation visible.

To reproduce: copy each library's source folder (Argmas's `src`,
Kelpto's four library folders, and so on) into one work root, run
`temper build -b rust` there, then `uv run
bench/markers/count_markers.py WORKROOT/temper.out/rust --json
counts.json` and `uv run bench/markers/summarize.py counts.json
--sites sites.tsv`.

### A compiler-known result type: likely cost

The first benchmark's `result` variant is a result type written as user
code, translated as any sealed interface is (an allocation per call;
`shared_ptr` and `dynamic_cast` in C++, `Arc<dyn …>` in Rust). A
result type the compiler knows could get each backend's cheapest
form. [bench/builtin-result/](bench/builtin-result/) hand-writes those
forms in each host language, beside the generated `bubble` and `null`
runners from [bench/src](bench/src/failbench.temper.md), with the same
loop, inputs, failure rates (0, 0.1, 1, and 10 percent), and depths (1,
and 5 with the failure passed up four more calls). The failure carries
a small `Bad` value (the input), so it isn't just a null.

| Backend | Hand-written forms |
|---|---|
| C++ | `variant`: `std::variant<int32_t, Bad>` by value; `tagged`: a struct with a flag, the value, and the failure; `expected`: C++23 `std::expected<int32_t, Bad>` |
| C# | `rstruct`: a `readonly struct Result<T, E>` by value, `E` a class allocated only on failure; `flag`: the plain value with the failure in an `out` parameter |
| Java | `rec`: a sealed interface with records `Ok(int)` and `Failed(Bad)`; `obj`: the plain value (as `Object`, so an `Integer`) or a `Failed`; `long`: a primitive with a sentinel (the failure's data lost) |
| JS, Python, Lua | `value`: the plain value, or a `Failed` object (checked with `instanceof`, `isinstance`, or the metatable) |
| Rust | `result`: `Result<i32, Bad>` by value, propagated with `?` |

Also, where quick, today's bubbling thrown without a stack trace
(`nothrow`): Java with a `RuntimeException` subclass constructed with
`writableStackTrace=false`, JS throwing a plain object instead of
`Error()`. The JS, Python, and Lua forms use the generated code's own
arithmetic helpers and loop shape, so only the failure handling
differs.

How it ran: the same toolchains as the first benchmark (g++ 13.3 at
`-O2 -std=c++23`, .NET 6, OpenJDK 21, Node 24, Lua 5.4, CPython 3.12,
Rust 1.99), a fresh process per backend, rate, and variant, warm-up
runs, then the median of 7 timed runs; three rounds back to back; n =
200,000 (50,000 for Lua and Python). Java and C# also ran with inlining
limited, as before. The machine was shared with other jobs during the
rounds, so absolute times spread widely (see the ranges); the ratios
divide by `null` (or `bubble`) within each round. Raw output and full
tables are in [bench/builtin-result/results/](bench/builtin-result/results/).

Ratios to `null`, ranges over the three rounds, depth 1:

| Backend | Form | ns per item, 0% / 10% | / null at 0% | 0.1% | 1% | 10% | / bubble at 1% | 10% |
|---|---|---|---|---|---|---|---|---|
| C++ | variant | 2.1-3.2 / 2.4-3.6 | 1.2-1.7x | 1.0-1.1x | 0.8-1.1x | 1.1-1.5x | 0.15-0.24x | 0.02-0.03x |
| | tagged | 2.6-3.2 / 2.8-3.3 | 1.2-1.7x | 0.7-1.1x | 0.7-1.1x | 1.2-1.5x | 0.15-0.16x | 0.02-0.03x |
| | expected | 2.3-3.1 / 2.4-3.5 | 1.2-1.7x | 0.7-1.2x | 0.7-1.5x | 1.0-1.5x | 0.15-0.21x | 0.02-0.03x |
| C# | rstruct | 3.7-8.7 / 6.5-10 | 0.5-0.8x | 0.5-0.7x | 0.5-0.9x | 0.7-1.0x | 0.03-0.05x | under 0.01x |
| | flag | 3.8-6.0 / 7.1-9.3 | 0.5x | 0.5x | 0.5-0.7x | 0.7-0.9x | 0.04x | under 0.01x |
| Java | rec | 2.9-7.9 / 4.6-16 | 1.0-1.1x | 0.6-0.8x | 0.8-1.0x | 1.1-2.0x | 0.2x | 0.07-0.08x |
| | obj | 2.8-9.3 / 5.3-11 | 0.7-1.2x | 0.8-1.0x | 0.7-1.8x | 1.3x | 0.2-0.4x | 0.06-0.08x |
| | long | 2.8-8.2 / 3.2-6.8 | 0.7-1.1x | 0.6-1.0x | 0.6-1.3x | 0.7-0.8x | 0.1-0.3x | 0.03-0.05x |
| JS | value | 10-19 / 18-36 | 0.6-0.9x | 0.7-1.0x | 0.9-1.3x | 1.3-1.6x | 0.3-0.5x | 0.07-0.09x |
| Lua | value | 843-1953 / 854-1752 | 0.8-1.0x | 0.6-1.0x | 0.8-1.1x | 0.9-1.1x | 0.6-0.8x | 0.6-1.0x |
| Python | value | 1426-2458 / 1797-1942 | 0.9-1.2x | 1.0-1.2x | 1.1-1.4x | 1.1x | 1.0-1.4x | 1.0-1.2x |
| Rust | result | 1.2-1.7 / 1.2-1.9 | 1.0x | 1.0x | 0.8-1.0x | 1.0-1.2x | 0.8-1.1x | 1.1x |

Depth 5 (the failure passes up four more calls):

| Backend | Form | ns per item, 0% / 10% | / null at 0% | 0.1% | 1% | 10% | / bubble at 1% | 10% |
|---|---|---|---|---|---|---|---|---|
| C++ | variant | 2.4-3.1 / 2.4-2.9 | 1.2-1.7x | 0.7-1.7x | 1.0-1.1x | 0.7-1.0x | 0.16-0.23x | 0.02x |
| | tagged | 2.3-3.4 / 2.6-3.3 | 1.1-1.7x | 1.1-1.2x | 0.7-1.1x | 0.7-1.2x | 0.16x | 0.02-0.03x |
| | expected | 2.1-2.4 / 2.3-3.6 | 1.1-1.2x | 1.1-1.2x | 0.7-1.7x | 0.7-1.0x | 0.15-0.23x | 0.02x |
| C# | rstruct | 4.9-6.5 / 7.1-8.4 | 0.1x | 0.1x | 0.1x | 0.1x | 0.04-0.05x | under 0.01x |
| | flag | 4.3-7.9 / 6.1-8.8 | 0.1x | 0.1x | 0.1x | 0.1x | 0.04x | under 0.01x |
| Java | rec | 2.9-5.3 / 12-26 | 1.0-1.2x | 0.6-0.8x | 0.6-1.0x | 0.5-1.6x | 0.5x | 0.07-0.19x |
| | obj | 2.8-5.2 / 11-30 | 1.0-1.1x | 0.7-0.9x | 0.5-1.3x | 0.7-1.7x | 0.4-0.7x | 0.1-0.2x |
| | long | 2.9-6.8 / 3.1-7.0 | 1.0-1.5x | 0.1-0.3x | 0.2-0.3x | 0.2-0.4x | 0.1-0.2x | 0.03-0.05x |
| JS | value | 11-34 / 19-42 | 0.5-0.8x | 0.8-0.9x | 0.9-1.0x | 1.0x | 0.3-0.5x | 0.05-0.07x |
| Lua | value | 1443-3171 / 1376-2743 | 0.8-1.0x | 0.7-0.9x | 1.0-1.2x | 0.5-1.0x | 1.0x | 0.8-1.0x |
| Python | value | 2935-3799 / 2660-2922 | 1.0-1.5x | 1.1-1.3x | 1.1-1.3x | 0.9-1.1x | 1.1-1.5x | 1.0-1.2x |
| Rust | result | 1.2-1.3 / 1.2-1.6 | 1.0x | 0.8-1.0x | 0.8-1.0x | 1.0-1.1x | 0.9-1.1x | 1.1-1.3x |

With inlining limited: C#'s `rstruct` stays at 0.4 to 0.7 times `null`
at depth 1 and 0.1 to 0.2 times at depth 5. On Java with the steps not
inlined, at depth 5, `rec` and `obj` cost 1.3 to 2.6 times `null` with
no failures (24 to 83 ns against 18 to 58) and 0.6 to 1.5 times once
failures occur; `long` stays at 0.3 to 1.2 times.

Throwing without a stack trace (ns per item at 1 / 10 percent
failures):

| Backend, depth | Today's bubble | `nothrow` | `nothrow` / bubble | `nothrow` / null at 10% |
|---|---|---|---|---|
| Java, 1 | 22-40 / 63-203 | 3.3-9.8 / 6.2-24 | 0.2-0.3x / 0.1x | 1.6-2.9x |
| Java, 5 | 24-44 / 68-169 | 5.4-8.7 / 7.5-18 | 0.2-0.4x / 0.1x | 0.5-1.0x |
| Java not inlined, 1 | 17-58 / 101-245 | 5.7-19 / 22-74 | 0.3-0.4x / 0.2-0.3x | 3.5-5.7x |
| Java not inlined, 5 | 37-124 / 170-348 | 18-47 / 62-186 | 0.3-0.5x / 0.3-0.5x | 2.6-3.3x |
| JS, 1 | 33-108 / 211-488 | 13-26 / 58-102 | 0.2-0.4x / 0.1-0.3x | 2.6-5.3x |
| JS, 5 | 51-89 / 295-871 | 12-25 / 27-65 | 0.2-0.3x / 0.1x | 1.5-1.6x |

**What it shows:**

- **A compiler-known result costs about what a nullable costs, on every
  backend measured,** and about nothing per failure: within 0.5 to 2.0
  times `null` on C++, Java, JS, Lua, Python, and Rust at every rate
  and depth (much of the spread is noise; the JVM's `long` is lower
  still), against 30 to 700 times for the user-defined result
  type on C++ and Rust in the first benchmark. In C++ the three forms
  (`std::variant`, a tagged struct, `std::expected`) cost the same,
  2 to 3.6 ns; in Rust a `Result<i32, Bad>` costs the same as today's
  bubble (already a `Result`) and `Option`, about 1.2 to 1.9 ns.
- **On .NET, a struct result is cheaper than `int?`:** 0.5 times `null`
  at depth 1 and 0.1 times at depth 5 (5 to 8 ns against 54 to 76),
  with or without inlining. So the depth-5 `int?` cost seen in the
  first benchmark looks specific to `Nullable<T>` returns across calls
  on .NET 6 (not investigated further); a plain struct with a flag, or
  an `out` parameter, doesn't pay it.
  Against today's bubbles, the struct costs 0.03 to 0.05 times at 1
  percent failures.
- **On the JVM, which form matters at depth:** with inlining, `rec` and
  `obj` cost about what `null` does (both box or allocate once failures
  occur), 12 to 30 ns at depth 5 with 10 percent failures; the `long`
  sentinel stays at 3 to 7 ns. Without inlining, `rec` and `obj` cost
  up to 2.6 times `null` with no failures. So for an `Int` success
  value, a primitive with a sentinel (failure data kept elsewhere, such
  as a field) is the form that never allocates; for a reference
  success value, `obj` (the plain value, or a `Failed`) allocates only
  on failure.
- **Most of an exception's cost on the JVM and JS is the stack trace.**
  Without one, throwing costs 0.1 to 0.5 times today's bubbling at 1
  and 10 percent failures, and 0.5 to 5.7 times `null` at 10 percent.
  So generated code could make today's `bubble()` much cheaper there
  without changing the language: a preallocated or trace-free
  exception class in Java, and a plain object instead of `Error()` in
  JS.

**Caveats:** hand-written, not generated, so these are what a backend
*could* emit, not what one does; the step is tiny, so the failure
mechanism dominates, as before; `Bad` is one integer, and a larger
failure value would cost more to copy in the by-value forms (C++, C#,
Rust); a shared machine spread the absolute times (up to about 3 times
between rounds on Java, JS, Lua, and Python), so read the ratios, and
the ranges of the ratios as the uncertainty; the Java `obj` form boxes
because the success value is an `int`.

To reproduce, from [bench/](bench/): `temper build` for the backends,
then `uv run builtin-result/run.py BACKEND` (also `java-noinline` and
`csharp-noinline`) once per round, and `uv run
builtin-result/summarize.py results/round-*.txt`.

## Operator precedence

Today's relevant precedences (tempest and Kotlin Temper share the same
table; higher binds tighter):

| Precedence | Operators |
|---|---|
| 24 | `.`, calls, `[]`, `?.` |
| 23 | postfix `!`, `?` (used in types today) |
| 22 | prefix `!`, `-`, `await` |
| 19, 20 | `+ -`, `* / %` |
| 13 | `< <= > >=`, `is`, `as` |
| 12 | `==`, `!=` |
| 11, 10 | `&&`, `\|\|` |
| 9 | `??` |
| 4 | `orelse` |
| 3 | `=`, `+=`, … |

**Pitfalls, checked with tempest:**

- `half(k) orelse 0 == 1` means `half(k) orelse (0 == 1)`. With
  `let a: Int = half(k) orelse 0 == 1;`, tempest's frontend reports
  nothing, the interpreter prints `false`, and the Python and Java
  backends stop with "not yet in tmpl: an expression of unknown type".
- `??` has the same trap: `let b: Int = maybe(m) ?? 0 == 1;` is
  accepted the same way, and `"${maybe(m) ?? 0 == 0}"` gives `true`.
  Likewise `x ?? 0 < 1`, `x ?? 5 > 3 && t`.
- Today's code avoids these with parentheses, e.g. Chromarite's
  `((values.length % ncols) orelse panic()) != 0`, and the tests in
  these cases write `(ints.parse("42") ?? -1) == 42`.

Where each design's operators sit (numbers as in the table above;
hypothetical operators at the level they'd get if added as today's
postfix and prefix operators):

| Design | Default | Propagation | Against calls and `.` | Against `==`, `&&`, `\|\|` | Against `??` |
|---|---|---|---|---|---|
| Today | `orelse` (4) | implicit, no operator | looser | looser: `x orelse 0 == y` is a trap | looser: `f() orelse a ?? b` groups `a ?? b` |
| A | `??` (9) | a statement today; hypothetical postfix `?` (23) | `?` just below calls, so `f()?` works but `f()?.g()` lexes as `?.` | `??` looser (the same trap); `?` tighter (safe) | `?` tighter |
| B | `catch { … }` (not specified) | hypothetical postfix `!` (23) | as `?`, without the `?.` collision | `!` tighter (safe); `catch` needs a rule | needs a rule |
| C | `catch { … }` or `orelse` (4) | hypothetical prefix `try` (22 if unary) | `try f().g()` covers `g`'s result only, if unary | `try a == b` is `(try a) == b`, if unary | needs a rule |

**Per design:**

- **Today and A:** the default operators, `orelse` (4) and `??` (9),
  sit below `==`, `&&`, and `||`, and at different levels from each
  other, so mixing them needs parentheses
  (`f() orelse null ?? 0` is `f() orelse (null ?? 0)`). Under A, where
  `orelse` and `??` become one idea, two precedences would be one more
  thing to remember.
- **A with a postfix `?` (hypothetical):** at today's postfix level
  (23), `f()?` binds tighter than every binary operator, so
  `parsePort(…)? + 1` and `need(…)? != word` work. Two traps: `?.`
  is already the null-safe call, so `parseJson(t)?.elements` lexes as
  `?.`, not as "propagate, then read" (the same for nullables, wrong
  for results); and prefix `await` (22) is looser, so `await f()?`
  would apply `?` to the promise, not to the awaited value (Rust writes
  `f().await?` for this reason).
- **B with postfix `!` (hypothetical):** binds like `?` without the
  `?.` collision, but readers from TypeScript, Kotlin (`!!`), C#, and
  Swift know postfix `!` as "assert not null, else crash", nearly the
  opposite of "propagate".
- **C with prefix `try` (hypothetical):** needs a rule for how far it
  reaches. Swift's `try` covers everything to its right in the
  expression; Zig's binds like a unary operator, so `try a + b` is
  `(try a) + b`, and `try f().g()` covers `g`'s result, not `f`'s.
- **`catch { … }` as an infix handler (B, C; hypothetical):** braces
  make the handler's extent visible, but its precedence relative to
  `==` and `&&` after the closing brace still needs a rule.

Elsewhere: Kotlin's `?:`, Swift's `??`, and Zig's `orelse` and `catch`
bind tighter than `==` and comparisons, so `a ?? 0 == 1` is
`(a ?? 0) == 1`; C#'s and JavaScript's `??` bind looser, like
Temper's, but C# rejects the resulting type mismatch, and JavaScript
forbids mixing `??` with `&&` or `||` without parentheses. Rust's `?`
is postfix at method-call level, and Rust has no `?.`.

**Suggestions** (labeled as such):

- **Suggestion:** have the type checker reject a fallback whose type
  doesn't fit (`Int orelse Boolean` where an `Int` is expected), so
  the trap becomes a compile error rather than a backend failure.
- **Suggestion:** move the default operators (`??`, and `orelse` while
  it exists) above comparison and equality and below arithmetic, as in
  Kotlin, Swift, and Zig, and give them one shared level; or, if
  changing precedence is too disruptive, require parentheses when they
  mix with comparison or logical operators, as JavaScript does for
  `??` with `&&` and `||`.
- **Suggestion:** if a postfix propagation operator is added, give it
  call-level precedence (left to right with `.` and calls, as in Rust),
  pick a spelling that doesn't collide with `?.`, and define how it
  combines with `await` (propagating the awaited value's failure).

## Observations

Neutral observations from the five cases and the benchmark; suggestions
are labeled.

1. **What failures need to carry:** absence alone (Argmas's value types,
   Chromarite's parser), a message (Wherewith), a name and a position
   (Hrefine), or a small set of variants with fields (JSON's syntax and
   shape errors; Argmas's argument errors). Only the last asks for
   matching on variants.
2. **Accumulated errors stay values in every design:** Hrefine's
   validation errors and Argmas's first-error-then-keep-parsing both
   need a list or a field regardless of A, B, or C.
3. **Propagation syntax decides A's readability.** Without an operator,
   A adds 17 to 47 percent more code where failures pass through
   several calls (Hrefine 86 to 101, Wherewith 84 to 113, JSON 91 to 134
   lines), most of it `when` blocks and re-wrapped `Failed`s; the
   Wherewith parser rule grows from 13 to 31 lines. With a `?`, A reads
   like today's code with one marker per fallible call, as B and C do.
   Today's implicit propagation has no marker at all.
4. **A and B remove the side channels** (Wherewith's `…Problem` twins
   and stored message, std JSON's dropped `jsonError`, and Hrefine's
   need for a log to learn why `parseUrl` failed); **C keeps them**,
   since a kind can't carry the text, the position, or the path.
5. **B and C need the failure type in every signature on the path,**
   including interfaces that hosts implement (`ValueType`,
   `JsonAdapter`); A does too (it's the return type), but for absence
   the contract is just `T?`, which every host language reads natively.
6. **Two failure types in one function** (JSON's `decodeJson`) worked
   under A with a sealed interface over both, as Mike proposes for B;
   it needs both types declared together, or a wrapper.
7. **Chromarite's chain is about panics, not failure values.** Once
   out-of-range reads panic, A, B, and C read the same and 31 of 52
   `throws Bubble` declarations go; the remaining `orelse panic()` are
   on builtins (`%`, `/`, Float64 `/`), #164's separate question.
8. **What hosts see under A depends on translation that doesn't exist
   yet.** Written as user code today, results reach Python and Java as
   `Ok`/`Failed` objects and Rust as a generated `Result_` rather than
   `Result`; an idiomatic host API (throwing forms, native `Result`)
   needs the compiler to know the type. B and C would generate an
   exception class (or enum) per declared type or kind.
9. **Cost:** nullables are free everywhere but on the managed
   runtimes: on the JVM, boxing once nulls occur makes `Int?` dearer
   than today's bubbling below about 0.1 to 1 percent failures (a
   primitive with a sentinel avoids it), and on .NET 6 `int?` across
   calls is dearer than bubbling below about the same rates. A
   user-defined result type is cheaper than today's bubbles on C#,
   Java, and JS once failures are frequent (1 to 10 percent), similar or
   dearer on Python, Lua, and interp, and much dearer on C++ and Rust as
   translated today.
10. **User-defined result types meet some gaps today** (tempest): a
    `when` over a generic sealed interface's classes isn't seen as
    exhaustive (each needs `else -> panic()`); after
    `if (r is Failed<…>) { return r; }`, the frontend accepts `r.value`
    but backends fail ("an expression of unknown type"); `Ok<Void, E>`
    can't be made (no `Void` value), so a check with nothing to return
    gives `Boolean`; and a `Failed` must be rebuilt to change its `T`.
    A type the compiler knows would avoid all four.
11. **Other tempest issues met on the way:** the precedence trap above
    (accepted by the frontend, rejected by backends); `Never<T>` as a
    helper's return type works on the interpreter but not on Python or
    JS; the C++ backend can't hold two modules of one library exporting
    the same name (so each case has two libraries); and Rust can't yet
    compare a nullable `Float64` that isn't a local
    (`c?.get(0, 2) == 1.0`). On C#, a generic interface method
    returning `T?` doesn't compile with implementations for `Int` or
    `String` (`Optional<T>` against `int?`), and a test asserting a
    `Float64` `==` calls a `FormatFloat64` helper that isn't generated.
    Also worth knowing when writing
    propagation by hand: semicolons are inserted only after a `}` that
    ends a line (as the syntax docs say), so a one-line body like
    `{ let v = f(); if (v == null) { return null; } v + 1 }` doesn't
    parse without a `;` after the `if`.
