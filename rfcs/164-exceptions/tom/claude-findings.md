Claude's findings for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)),
2026-11-17, answering "Before deciding" in
[claude-thoughts.md](claude-thoughts.md). Evidence only, plus
suggestions marked as such at the end; neutral between the directions in
[tom-thoughts.md](tom-thoughts.md) and [mike-thoughts.md](mike-thoughts.md).

Everything was run with tempest's `temper` (0.7.0-alpha) on Linux
x86-64: g++ 13.3, .NET 6.0, OpenJDK 21, Node 24, Lua 5.4.6,
CPython 3.12, and Rust 1.99. "interp" is tempest's interpreter.

## 1. Behavior across backends

### How each backend represents failure today

| Backend | `bubble()` | `orelse` catches | `panic()` | Builtins fail with |
|---|---|---|---|---|
| interp | internal | bubbles only | "Panicked: panic()", exit 1 | bubbles |
| C++ | `throw temper::core::TemperBubble` (`std::exception`, `what()` "bubble") | `TemperBubble` only | `std::terminate()`, SIGABRT (134), no message | `TemperBubble` with a message ("division by zero", "invalid int") |
| C# | `throw new System.Exception()` | everything (bare `catch`) | `Environment.FailFast("panic")`: process killed, core dump, 134 | .NET exceptions (`FormatException` for parsing) or bare `Exception` |
| Java | `throw new RuntimeException()` (stack trace, no message) | `RuntimeException` | `AssertionError("panic")`, exit 1 | Java exceptions (`NumberFormatException`) or bare `RuntimeException` |
| JS | `throw Error()` (no message) | everything | **same as `bubble()`** (`panic = bubble`, a TODO in the runtime) | bare `Error` |
| Lua | `error(table)` whose `tostring` is "Bubble" | everything (`pcall`) | `error("panic")`, a string | Lua runtime errors as strings ("attempt to divide by zero", "attempt to compare number with nil") or the Bubble table |
| Python | `raise RuntimeError()` | `Exception` | `raise BaseException('panic')`, exit 1 | Python exceptions (`ValueError`, `ZeroDivisionError`, `OverflowError`) or bare `RuntimeError` |
| Rust | `Err(temper_core::Error(None))`, `Result` and `?` | `Err` | `panic!()`, exit 101 | `Error(None)`, or `Error(Some(cause))` carrying e.g. a `ParseIntError` |

So a "Bubble" is already not one thing per backend: where the
operation is a builtin, most backends let the host library's own
exception through (a `ValueError`, `NumberFormatException`,
`FormatException`, Lua string error), and Rust keeps it as a cause.
Only C++ and Rust have a type that host code can catch as "Temper failure" (Lua's own bubbles share a metatable, which isn't exported).

### Inside Temper: all agree

A probe library ran on every backend with identical output for bubble
and `orelse`:

| Case | Result on all 8 |
|---|---|
| bubble and `orelse` in one function; across 2 calls; across modules | fallback taken |
| through a named function, a `fn` literal, and a block lambda passed as a `@fun interface` | fallback taken |
| a constructor (`constructor(...): Void throws Bubble`) and a method | fallback taken |
| a module-level initializer (`let x = f() orelse 42`) | 42 |
| `await` of a broken promise, with `orelse`, alone and inside an expression | fallback taken |
| Int `/` and `%` by zero; `Int64.toInt32` out of range; `String.toInt32` on bad text | bubble |
| `Int.MIN / -1` | wraps to `Int.MIN`, no bubble (all backends) |

### Where they differ

| Case | interp | C++ | C# | Java | JS | Lua | Python | Rust |
|---|---|---|---|---|---|---|---|---|
| `1.0 / 0.0`, `0.0 / 0.0`, `1.0 % 0.0` (docs: bubble) | bubble | Infinity/NaN | Infinity/NaN | Infinity/NaN | Infinity/NaN | Infinity/NaN | bubble (by accident: Python's `ZeroDivisionError`) | bubble |
| `f() orelse x` where `f` panics | panic | panic | panic | panic | **fallback taken** | **fallback taken** | panic | panic |
| list `[i]` out of bounds, no `orelse` | panic | `TemperBubble` uncaught, abort | `ArgumentOutOfRangeException` | `IndexOutOfBoundsException` | `ReferenceError: bubble is not defined` | Lua error | `IndexError` | `unwrap()` on `None` |
| list `[i]` out of bounds inside an `orelse` whose body also bubbles | panic | **fallback taken** | **fallback taken** | **fallback taken** | **fallback taken** | **fallback taken** | **fallback taken** | panic |
| bubbling generator (`GeneratorFn` that bubbles, `Generator.next`) | propagates to caller | not supported yet: "core's Generator.next" | same | same | same | same | same | same |
| `await` that bubbles in an `async` block with no `orelse` | runs, then "Failed" | rejected at translation: "an await bubbles, but ~fn#30 can't" | same | same | same | same | same | same |

The list rows matter for the panic question: `Listed.get` is declared
without `throws` and documented to panic, but on six backends the
"panic" is an ordinary exception that any enclosing `orelse` swallows,
as long as something else in the `orelse` body can bubble.

`String.toInt32` also disagrees on which strings fail (all other cases
in the probe agree, including leading and trailing spaces, accepted
everywhere):

| Input | interp, C++, JS, Lua, Rust | C# | Java | Python |
|---|---|---|---|---|
| `"+5"` | 5 | **bubble** | 5 | 5 |
| `"-"` | bubble | **0** | bubble | bubble |
| `"1_0"` | bubble | bubble | bubble | **10** |
| `"٣"` (Arabic-Indic three) | bubble | bubble | **3** | **3** |

### What host code sees from an exported function

The same library called from a host program in each language
(`failIf(-1)` bubbles; `parseI("x")` is `s.toInt32()`; `panicIf(-1)`
panics):

| Language | `failIf(-1)` | `parseI("x")` | `panicIf(-1)` | Can host code catch the panic? |
|---|---|---|---|---|
| C++ | `TemperBubble`, `what()` "bubble" | `TemperBubble`, "invalid int" | `std::terminate` | no |
| C# | `System.Exception`, the default message | `System.FormatException` | `FailFast`: process killed | no |
| Java | `java.lang.RuntimeException`, null message, full trace | `NumberFormatException` | `java.lang.AssertionError: panic` | yes, as `Error`/`Throwable` |
| JS | `Error`, empty message | `Error`, empty message | `Error`, empty message | yes, but it is indistinguishable from a bubble |
| Lua | table, `tostring` "Bubble" | string "…init.lua:906: attempt to compare number with nil" | string "…: panic" | yes, with `pcall`; tells only by string matching |
| Python | `RuntimeError`, empty | `ValueError: invalid literal for int()…` | `BaseException('panic')` | yes, with `except BaseException`; `except Exception` lets it pass |
| Rust | `Err(Error(None))`, displays "bubble" | `Err(Error(Some(ParseIntError)))` | panic | with `catch_unwind` |

So host users can't catch "a Temper failure" selectively in C#, Java,
JS, Lua, or Python: the type is either the most general exception of the
language, or whichever exception the builtin happened to raise. The
libraries' own demos catch `RuntimeError` / `RuntimeException` /
`TemperBubble` (section 3), which also catch unrelated errors.

### Host exceptions inside callbacks

A Temper `export interface Callback { call(x: Int): Int throws Bubble }`,
a non-bubbling `PlainCallback`, and a `@fun interface`, each
implemented in host code that throws the host's ordinary exception:

| Language | Inside an `orelse` | Outside any `orelse` |
|---|---|---|
| C++ | passes through (only `TemperBubble` is caught); a host `throw TemperBubble(…)` is taken as a bubble | passes through |
| C# | **becomes a bubble**, even from the non-bubbling interface | passes through |
| Java | **becomes a bubble** if a `RuntimeException`; `Error`s (`StackOverflowError`) and sneaky-thrown checked exceptions pass through | passes through |
| JS | **becomes a bubble**, anything thrown, including a stack overflow `RangeError` and thrown strings | passes through |
| Lua | **becomes a bubble**, any `error(…)`, including stack overflow | passes through |
| Python | **becomes a bubble** if an `Exception`, including `RecursionError`; `KeyboardInterrupt` passes | passes through |
| Rust | host `Err(Error::with_source(e))` is a bubble, and `e` survives propagation to the caller; host `panic!` passes through | passes through |

So in five of seven languages, a host bug inside a callback is silently
turned into the fallback value if the call happens to sit in an
`orelse`. The non-bubbling `PlainCallback` row shows the type system
doesn't limit this: `orelse` catches more than the calls it covers.

### Panics in `temper test`

A test file with a passing test, a failing assertion, a test that
panics, one that bubbles, one with `orelse panic()`, and a passing test
after them:

| Backend | Result |
|---|---|
| interp | each reported on its own: "Panicked: panic()", "Bubble"; 2 of 6 pass |
| Java, Lua, Python, Rust | each reported on its own ("panic", "explicit panic", a traceback, `Error(None)`); 2 of 6 pass |
| C++ | the whole test binary aborts: "0 of 6 (6 not run)" |
| C# | the test host dies (`FailFast`): "0 of 6 (6 not run)", with no reason shown |
| JS | not run here (Mocha isn't installed in this environment); by the runtime, a panic would report like a bubble |

### Bugs found

Minimal repros, each a whole library module unless noted.

1. **JS and Lua: `orelse` catches `panic()`.** JS defines
   `panic = bubble`; Lua's `orelse` is a bare `pcall`.
   ```temper
   let mayPanic(n: Int): Int throws Bubble { if (n < 0) { panic() }; if (n == 0) { bubble() }; n }
   var k = -1; k = k;
   console.log("${ mayPanic(k) orelse -99 }"); // JS, Lua: -99; others: panic
   ```
2. **Float64 division and remainder by zero don't bubble on C++, C#,
   Java, JS, or Lua** (they give Infinity or NaN), while the docs, interp,
   and Rust bubble, and Python bubbles only because its native operator
   raises.
   ```temper
   var z = 0.0; z = z;
   console.log("${ (1.0 / z) orelse -1.0 } ${ (1.0 % z) orelse -1.0 }");
   ```
3. **Out-of-bounds list reads are caught by `orelse` on six backends**
   (all but interp and Rust), though `Listed.get` is documented to panic:
   ```temper
   let failIf(n: Int): Int throws Bubble { if (n < 0) { bubble() }; n }
   let xs = [1, 2]; var i = 5; i = i;
   console.log("${ (do { let a = xs[i]; failIf(a) }) orelse -1 }"); // -1 on 6 backends
   ```
   The first line of `Listed.get`'s doc comment (and so
   `docs/language/types.md`) still says it bubbles; the rest says it
   panics.
4. **JS runtime: `listed.js` calls `bubble()` without importing it**,
   so an out-of-bounds read throws `ReferenceError: bubble is not
   defined` (repro: `let xs = [1, 2]; var i = 5; i = i; xs[i];`).
5. **`String.toInt32` accepts different strings per backend**: C#
   rejects `"+5"` and returns 0 for `"-"`; Java and Python accept
   non-ASCII digits; Python accepts `"1_0"`. Repro: the table above,
   `c.toInt32() orelse …` over those strings.
6. **C++ loses console output on panic.** `console.log` writes to
   `std::cout` without flushing and `panic()` calls `std::terminate`,
   so with stdout on a pipe, lines logged before the panic are lost
   (`console.log("before"); panicIf(-1);` prints nothing). `panic()`
   without a message also prints no reason, only "terminate called
   without an active exception".
7. **C# and C++ test runs report nothing for a panicking test**: the
   whole run becomes "0 of N (N not run)" with no reason in C#'s case.
8. **An `await` that can bubble inside an `async` block without
   `orelse`** is accepted by the frontend and run by the interpreter
   (ending "Failed"), but every backend rejects it at translation with
   an internal message, "an await bubbles, but ~fn#30 can't":
   ```temper
   let b = new PromiseBuilder<Int>();
   async { (): GeneratorResult<Empty> extends GeneratorFn =>
     let x = await b.promise;
     console.log("${x}");
   }
   b.breakPromise();
   ```
9. **Bubbling generators aren't translated yet** ("not yet in tmpl:
   core's Generator.next") on any backend; only the interpreter runs
   them.
10. **Passing a non-bubbling function where a bubbling `@fun interface`
    is expected** works in the interpreter but Python reports "not yet in
    tmpl: a function as a value of another type":
    ```temper
    @fun interface IntFn(x: Int): Int throws Bubble;
    let applyIt(f: IntFn, x: Int): Int throws Bubble { f(x) }
    let plain(n: Int): Int { n }
    console.log("${ applyIt(plain, 1) orelse -1 }");
    ```
11. **JS: an exported interface's methods are emitted as class fields**
    (`call = undefined`), so a host class `extends Callback` with a
    `call()` method has it shadowed by the field: `new Thrower().call` is
    `undefined`. Host code has to assign the method in its constructor.
12. **Lua builtins fail through incidental Lua errors**:
    `String.toInt32("x")` fails with "attempt to compare number with nil"
    from inside the runtime, not `temper.bubble`, so host code can't tell
    a Temper failure from a runtime bug even by type.

Also of note: a library's design notes (Hrefine's) record Rust's
`Error(None)` overflowing the stack in `Display`; that's fixed, it now
shows "bubble".

## 2. Speed

Timing on this machine is noisy (other jobs shared it for part of the
runs), so read ratios measured back to back in one process, not
absolute numbers. All figures are nanoseconds per item.

### `orelse` in Temper, per backend

A Temper library parses a list of short strings, where F percent are
not numbers (`"x123"`), summing with 0 for each failure. Variants:

- **builtin:** `x.toInt32() orelse 0`.
- **bubble:** a hand-written digit loop that calls `bubble()`, with
  `orelse 0`.
- **null:** the same loop returning `null`, with `?? 0`. This is the
  "no exception" baseline, and roughly what lowering a bubble to a
  failure value would give.
- **bubble5 / null5:** the same, with the failure passing up five calls.

Host programs time the exported runners (warm-up, then 7 repeats;
median shown). N = 200,000 for C++, C#, Java, JS, and Rust (C++ `-O2`,
Rust `--release`, C# Release); 50,000 for Lua and Python.

| Backend | F = 0%: bubble / null | F = 1% | F = 10% | F = 90% | Cost per bubble | builtin `toInt32`, cost per failure |
|---|---|---|---|---|---|---|
| C++ | 25 / 25 | 42 / 27 (1.6x) | 170 / 38 (4.5x) | 1961 / 21 (90x) | ~2 µs | ~6.5 µs (throws twice: `std::stoi`'s exception, then `TemperBubble`) |
| C# | 145 / 148 | 345 / 151 (2.3x) | 2005 / 138 (15x) | 17575 / 134 (130x) | ~15-19 µs | ~14 µs |
| Java | 12 / 16 | 69 / 29 (2.4x) | 182 / 29 (6x) | 747 / 7 (100x) | ~0.8 µs | ~1.5 µs (`NumberFormatException` builds a message) |
| JS | 44 / 34 | 68 / 35 (1.9x) | 347 / 35 (10x) | 2918 / 20 (140x) | ~3 µs | ~3 µs |
| Lua | 2323 / 2158 | 2278 / 2156 (1.1x) | 2330 / 1928 (1.2x) | 795 / 485 (1.6x) | ~0.3 µs | ~0.4 µs |
| Python | 3104 / 3053 | 2860 / 3108 (0.9x) | 3009 / 2794 (1.1x) | 1050 / 762 (1.4x) | ~0.3 µs | ~1 µs |
| Rust | 50 / 47 | 44 / 47 (1.0x) | 44 / 44 (1.0x) | 42 / 37 (1.1x) | ~0 | ~0 |

Repeated runs moved Python and Lua cells by up to 2x and the others by
up to about 30 percent; the shape held. What it shows:

- **The success path is free everywhere** except Lua, where each
  `orelse` makes a closure and a `pcall` (about 5 to 10 percent here).
- **On C++, C#, Java, and JS, failures dominate at once:** 1 percent
  failures already double the loop's time (C#, Java, JS) and 10 percent
  make it 4.5 to 15 times slower. C# is an order of magnitude worse than
  the rest, at 15 µs or more per bubble.
- **On Python and Lua, the generated code is slow enough** (about 3 µs
  to parse a five-character string by hand in Python) that bubbling adds
  at most about 1.5 times, even at 90 percent failures.
- **Rust pays nothing,** since a bubble is already a `Result`.
- **Depth hardly matters here,** because the parse loop dominates; the
  host benchmarks below vary it properly.
- **Builtins can cost more than `bubble()`:** C++'s `toInt32` throws
  twice, and Java's throws a library exception with a formatted message,
  so they're 2 to 3 times dearer per failure than a bare bubble. A
  builtin that checks before converting (or uses `TryParse` and the like)
  would avoid most of that without any language change.

### Exceptions vs return values in host code

To estimate "failure values inside, exceptions only at exported
boundaries", hand-written programs in Java (OpenJDK 21), C# (.NET 6),
JS (Node 24), and Python (CPython 3.12) fail a cheap operation at rate F,
the failure passing up D calls before reaching the handler. Each cell is
the range of three runs' medians:

- **exception:** today's code, a new `RuntimeException`, `Exception`,
  `Error`, or `RuntimeError`.
- **no-trace:** throwing without capturing a stack trace: Java's
  `Throwable(msg, null, false, false)` (fresh instance, carrying a
  message, as a typed failure would); JS throwing a plain
  `{kind, message}` object; Python re-raising one preallocated instance
  (with its traceback cleared); C# a preallocated `Exception`.
- **retval:** a sentinel return value checked at each level.
- **boundary:** retval inside, plus one ordinary throw at the exported
  function, for failures that escape to host code.

| Lang | F, D | exception | no-trace | retval | boundary |
|---|---|---|---|---|---|
| Java | 0%, 20 | 24-31 | 21-33 | 20-37 | 23-39 |
| Java | 1%, 1 | 6.7-11 | 0.9-1.3 | 1.1-1.5 | 6.9-10 |
| Java | 10%, 1 | 73-94 | 2.7-3.8 | 1.0-1.4 | 75-89 |
| Java | 10%, 20 | 361-600 | 125-215 | 32-45 | 127-205 |
| Java | 100%, 20 | 2781-3811 | 949-1532 | 28-37 | 826-1208 |
| C# | 1%, 1 | 155-396 | 157-445 | 2.9-8.1 | 148-421 |
| C# | 10%, 20 | 2948-4853 | 2991-5771 | 59-101 | 1016-1770 |
| C# | 100%, 20 | 28268-49796 | 29731-49926 | 53-85 | 9358-17247 |
| JS | 1%, 1 | 36-52 | 8.3-14 | 7.2-11 | 34-60 |
| JS | 10%, 1 | 273-407 | 26-32 | 9.3-11 | 297-336 |
| JS | 10%, 20 | 548-1095 | 285-383 | 121-201 | 382-606 |
| JS | 100%, 20 | 6224-6938 | 1715-1911 | 159-190 | 3018-3646 |
| Python | 10%, 1 | 233-908 | 242-1140 | 218-851 | 296-1228 |
| Python | 0%, 20 | 2872-3027 | 2384-3182 | 3675-4087 | 3702-3940 |
| Python | 100%, 20 | 5936-9890 | 5670-7857 | 2409-3174 | 3388-4604 |

What it shows:

- **Per failure, an exception costs** about 0.5 to 1 µs at depth 1 and
  2.5 to 4 µs at depth 20 in Java (the stack trace grows with depth),
  2 to 5 µs in JS, 14 to 40 µs in C#, and 0.4 to 1.5 µs in Python.
- **Return values cost nothing measurable on the success path** in
  Java, C#, and JS. In Python, checking at every level costs about 25 to
  30 ns per level, so at depth 20 with no failures it is 15 to 30 percent
  slower than `try`, which is free until something raises.
- **Throwing without a trace is a large partial fix in Java and JS:**
  3 times cheaper at depth, 10 to 30 times at depth 1, where the JIT can
  turn a throw into a jump, while still able to carry a message or
  value. It remains 20 to 40 times dearer than a return value at depth,
  since unwinding still costs about 50 to 80 ns per frame. **C# has no
  cheap option:** .NET 6 collects the trace and unwinds in two passes on
  every throw, preallocated or not (.NET 9's new exception handling,
  reported 2 to 4 times faster, wasn't available here). Python gains
  nothing from reuse.
- **The boundary variant is roughly retval plus one shallow throw:** it
  saves most of the cost at depth (Java 3 times, C# 3 times, JS 2 times
  at depth 20) but nothing at depth 1, and nothing when the failure is
  handled inside the library, which is where retval alone already wins.

### When lowering would pay

- **`bubble` and `orelse` in the same function, or failures handled
  inside a library** (the parse-loop case): lowering to a branch or a
  failure value removes the whole cost on C++, C#, Java, and JS, from 2x
  at 1 percent failures to 100x at 90 percent. On Python it is about
  even, and Python's per-level checks cost something at depth; Lua's
  saving is the per-`orelse` closure and `pcall`. Rust has it already.
- **Failures that escape to host code:** a boundary throw keeps most of
  the exception's cost; it pays only when failures travel many frames
  inside the library first.
- **Cheaper throws** (no trace in Java and JS) close much of the gap
  without changing how code is generated, but not on .NET.

## 3. Real cases in public libraries

Libraries surveyed: Argmas, Chromarite, Hrefine, Kelpto, Ordable,
Wherewith, and tempest's core and std. Counts are lines matching in
`.temper` and `.temper.md` sources (prose examples included), non-test /
test.

| Library | `throws Bubble` | `bubble()` | `orelse` | `panic()` |
|---|---|---|---|---|
| Argmas | 6 / 2 | 9 / 2 | 22 / 67 | 19 / 61 |
| Chromarite | 52 / 0 | 28 / 0 | 74 / 0 | 79 / 0 |
| Hrefine | 24 / 1 | 46 / 0 | 123 / 8 | 92 / 5 |
| Kelpto | 49 / 1 | 48 / 0 | 315 / 14 | 291 / 15 |
| Ordable | 0 | 0 | 11 | 11 |
| Wherewith | 104 / 0 | 59 / 0 | 32 / 73 | 21 / 52 |
| tempest core + std | 56 | 8 | 22 | 13 |

### Patterns

- **`orelse panic()` is most `orelse`s** (roughly 85 to 95 percent): an
  assertion on operations the author knows can't fail, mostly `as`
  downcasts (Kelpto, Argmas), list indexing and `%` (Chromarite),
  `appendCodePoint` and `/` (Ordable):
  ```temper
  builder.appendCodePoint(0x100 + (past / 0x7F00 orelse panic())) orelse panic();  // Ordable
  if (((values.length % width) orelse panic()) != 0) { panic() }                     // Chromarite
  let text = (kids[i] as GreenToken orelse panic()).text;                            // Kelpto
  ```
- **Bubbles spread through internal code only because of arithmetic,
  then get turned into panics at the API.** Chromarite has 52
  `throws Bubble` but 5 public ones; the rest exist because of indexing
  or division inside, e.g. `public inGamut(space: Space): List<Boolean>
  { inGamutRows(this, space) orelse panic() }`.
- **Real recoverable failure is at a few parse and validate entry
  points:** Argmas `ValueType.parse`, Chromarite `Color.parse`, Hrefine
  `parseUrl`, Kelpto's builder and editor operations, Wherewith's
  `render`, `build`, `quoteName`, and parser. About 70 exported or
  public API members bubble across the five libraries that have any.
- **Bubbles converted to `null` or `Boolean`** right away:
  `public tryResolve(ref: String): Url? { resolve(ref) orelse null }`
  (Hrefine); `do { floats.parse(text); true } orelse false` (Argmas).

### Where libraries built their own error values, and why

| Library | What | Why (their docs) |
|---|---|---|
| Argmas | sealed `ParseResult` = `Args` \| `Output` \| `ArgError(kind, message)` | "Mistakes are values, not exceptions, with a suggestion when there's a near miss." |
| Hrefine | `UrlCheck { url?, errors: List<ValidationError> }`, `PolicyCheck`, nullable `Url.parse` | "**Failures say nothing,** in every language: a bare `RuntimeError` (Python), `Error` (JS), `RuntimeException` (Java), `System.Exception` (C#), `TemperBubble` (C++), the string "Bubble" (Lua) … Catching them catches unrelated errors too." |
| Wherewith | a `…Problem(): String?` twin for each bubbling operation, which re-runs the check | "none of the exceptions carries a message, so the tour prints `templateProblem` and `renderProblem`, which say why" |
| Kelpto | `HtmlParseError(code, offset)` lists; parsers "never fail" | parse errors are warnings next to a usable document |

Host demos catch the generic types (`except RuntimeError`,
`catch (RuntimeException e)`, `catch (TemperBubble const &)`); a C++
tour comments that `parseUrl`'s `what()` is only "bubble", "so
`checkUrl` says why". Wherewith's parser has `need(message)`, which
computes a message that the bubble then drops.

### Would those values fit a declared failure type?

Asked of each value: could it be a thrown, declared type (say a sealed
interface of variants with fields, caught by matching)?

| Value | Fits as a thrown type? |
|---|---|
| Argmas `ArgError(kind, message)` | Partly: one fatal error, and `ErrorKind` (ten kinds) could be variants. But it's a value by choice, sharing `exitStatus` with the non-error `Output` (help, version). |
| Argmas `ValueType.parse` | Needs nothing: Argmas turns any failure into its own `invalidValue`. |
| Hrefine `UrlCheck` / `ValidationError(name, position, length)` | No: errors accumulate next to a usable URL. Only `parseUrl`'s failure could carry the last `ValidationError`. |
| Hrefine `PolicyCheck` (rule, reason) | Shape fits, but rejection is the expected outcome; it "never bubbles". |
| Hrefine `withHosts` and similar | A message naming the bad entry would do. |
| Kelpto `HtmlParseError(code, offset)` | No: warnings next to a document. |
| Kelpto edits and builders | Could fit a small sealed set (out of range, foreign view, overlapping edits, would reparse differently); no type exists today. |
| Wherewith `…Problem()` strings, `need(message)` | A message alone would do, and would remove the twins. |
| std `parseJson`, `Date.fromIsoString`, `String.toInt32` | A message or position would do; most callers `orelse` them. |

Two notes: several of these are open sets of spec-named strings
(`ErrorKind`, `PolicyRule`, `ValidationError.name`,
`HtmlParseError.code`), not closed types, so sealed variants would be a
modelling change. And code that converts failures right away
(`orelse null`, `orelse panic()`) never inspects a cause, under any
design.

### What a host user would want to catch

From the exported bubbling APIs: which operation failed and a readable
reason (Wherewith's problems, Hrefine's validation error name and
position, Kelpto's rejected edit), and a type that is the library's own,
so `except` doesn't also swallow unrelated errors. None asks for a
hierarchy; Argmas's kinds are the only finer-grained dispatch, and it
already returns them as values.

## 4. What the evidence suggests (suggestions)

These are suggestions drawn from the evidence above, not decisions.

### Payloads or not

- **Suggestion: some failure information is wanted, and a message (or
  cause) is the part libraries miss most.** Four of six libraries built
  a second error channel: Hrefine and Wherewith cite the missing reason,
  Argmas prefers values anyway, and Kelpto's are warnings. What they'd
  put in it is mostly text or a name plus a position; only Kelpto's edits and Argmas's kinds
  would use a small set of variants with fields.
- **Suggestion: whatever is added, accumulated errors stay values.**
  Hrefine's `UrlCheck` and Kelpto's HTML errors sit next to a usable
  result and can't be thrown under any design, so a shared result or
  diagnostics type in std would help regardless.
- **Suggestion: declared kinds (#164) and a single declared failure
  type (sealed variants, convertible with a message and cause) both fit
  the surveyed cases;** the cases don't separate them. What does matter
  for both: Rust already carries an optional cause (`Error(Some(…))`),
  and several backends already surface builtin failures with host
  messages, so "opaque message plus cause" matches what partly exists.

### What host code should see

- **Suggestion: give each backend one Temper failure type** (a class or
  table host code can catch selectively, named in the API docs), and have
  `orelse` catch only that type. Today `orelse` catches far more than
  bubbles on five of seven backends (everything in C#, JS, and Lua; any
  `RuntimeException` in Java; any `Exception` in Python), so host bugs in callbacks, stack overflows, and
  out-of-bounds "panics" become fallback values (section 1). Both
  directions need this, since a declared kind can't be told apart from a
  host error otherwise.
- **Suggestion: builtins should raise that type too,** not
  `ValueError`, `NumberFormatException`, or Lua strings, and should check
  before converting where the host's own failure is dear.

### Which builtins should panic

- **Suggestion: list access already panics by contract; make it do so
  everywhere** (bugs 3 and 4), and treat that as the model for the
  #164 candidates. Usage supports moving the obvious assertions: most
  `orelse`s are `orelse panic()` on division, `%`, `as` downcasts that
  can't fail, and `appendCodePoint`. Those pushed `throws Bubble` through
  52 internal Chromarite functions.
- **Suggestion: decide Float64 division by zero first,** since backends
  already disagree (bug 2): either it bubbles everywhere, as documented,
  or it follows IEEE 754 (Infinity and NaN) and doesn't fail at all.
  Five backends already do the latter.
- **Suggestion: keep the parse-like ones recoverable** (`String.toInt32`,
  `toFloat64`, `parseJson`, `Date.fromIsoString`, `as` on untrusted
  data): these are where libraries actually recover, and they should
  also agree on which inputs fail (bug 5).
- **Suggestion: pin down `panic` per backend,** since it varies from
  uncatchable process death (C#, C++) to an ordinary exception host code
  can catch (Java, Python, Rust) to one `orelse` catches (JS, Lua; bug
  1), and test runners lose all results on two backends (bug 7).

### Boundary lowering

- **Suggestion: lowering a `bubble` to a branch where its `orelse` is in
  the same function, and to a failure value for non-exported functions,
  is worth doing for C++, C#, Java, and JS** where failures are expected
  (parsing loops): it is free on the success path there and saves 2 to
  100 times on the failure path. It is roughly neutral on Python and Lua
  and already the case in Rust. It can be done without language changes.
- **Suggestion: turning internal failure values back into exceptions
  at exported functions pays only when failures cross several internal
  frames;** the single host throw stays. For the escaping case,
  throwing without a stack trace (Java, JS) is the cheaper lever and
  keeps a message or payload possible, which matters if typed failures
  come. On .NET only fewer throws help.
- **Suggestion: decide the Lua and Python strategies separately,**
  since their costs come from the generated code around the failure,
  not from the exception.

### Before the RFC

- Fix or file bugs 1 to 12, then turn section 1's probes into a shared
  functional test so the RFC can state current semantics as tested
  facts. The probe sources, host harnesses, and benchmark programs are
  small and could be checked in with that test.
