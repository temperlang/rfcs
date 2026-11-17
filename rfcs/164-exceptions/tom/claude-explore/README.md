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
