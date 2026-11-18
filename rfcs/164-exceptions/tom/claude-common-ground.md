Common ground for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)):
decisions that both [declared failures](claude-proposal-declared.md) and
[failures as values](claude-proposal-values.md) need, and that can be
made before choosing between them. Drafted by Claude, 2026-11-17.
Evidence: [claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), and the
[example translations](claude-translations/README.md). Syntax marked
**HYPOTHETICAL** doesn't compile today.

**How this maps to the RFC's
[two questions](claude-recommendation.md#two-questions).** Nothing here
depends on the **semantics** question (whether results, the
success-or-failure union, are first-class, in flight only, or in the
middle ground between), so all of it can be settled first. Several
sections are parts of the **syntax** question that either answer needs:
[`return` as an expression](#return-break-and-continue-as-expressions),
[propagation markers](#propagation-markers),
[precedence](#precedence), and
[naming](#naming-across-failure-styles). The rest is behavior both share
([which builtins panic](#which-builtins-panic),
[what `orelse` catches](#what-orelse-catches), panics) or the host
boundary that each backend's **representation** must present
([host-facing failure types](#host-facing-failure-types),
[compatibility](#compatibility-of-failure-changes)).

Much of it also holds for
[option 0, no failure support](claude-option-no-failures.md), where
Temper keeps only nullables and panics:
[which builtins panic](#which-builtins-panic),
[`return` as an expression](#return-break-and-continue-as-expressions)
(there, the only propagation), [precedence](#precedence) (for `??`),
[panics per backend](#panics-per-backend), and
[panics in test runners](#panics-in-test-runners). Propagation markers,
what `orelse` catches, host-facing failure types, and lowering apply
only if Temper keeps failures.

## `return`, `break`, and `continue` as expressions

Today `f() ?? return null` and `f() orelse return null` don't parse, so
propagating absence takes a hoisted `let` and an `if`, and hoisting one
call means hoisting everything evaluated before it
([explore](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
Making all three expressions of type `Never` (as in Kotlin and Rust) is
useful under either proposal:

```temper
// HYPOTHETICAL
let tree = parseJson(text) ?? return null;
let n = s.toInt32() orelse continue;
```

## Propagation markers

Both proposals want a marker at each call that propagates a failure,
where today's `throws Bubble` propagates implicitly: 630 sites (65
public, 565 internal), in 206 of the 268 bubbling functions, about one
per 60 lines, spread out rather than concentrated. By library: Wherewith
365, Chromarite 140, Kelpto 52, Hrefine 36, std 32, Argmas 5, and
Ordable 0 ([markers](claude-explore/README.md#propagation-markers),
counted from the type checker's own propagation in generated Rust). Some
go rather than gaining a marker: 68 of Wherewith's call a helper that
always bubbles, and about half of Chromarite's are matrix reads (52) and
Float64 division (19) that stop bubbling once out-of-range reads panic
and division is settled. The type checker already knows each site, so a
rewriting tool can add them.

## Which builtins panic

Of 596 `orelse`s in the surveyed libraries and std, 500 are
`orelse panic()`: on `as` downcasts (204), list or map reads (56),
`appendCodePoint` (40), `/` and `%` (14), `String.fromCodePoint` (6), and
conversions (1). Bubbles from indexing and division also spread
`throws Bubble` through 31 of Chromarite's 52 declarations
([findings §3](claude-findings.md#3-real-cases-in-public-libraries)).
Suggested split:

| Panic (bugs, avoidable by a cheap check) | Stay recoverable (where libraries recover) |
|---|---|
| Int `/` and `%` by zero; list access out of bounds (already panics by contract); `as` downcasts the author knows can't fail | `String.toInt32`, `toInt64`, `toFloat64`; `parseJson`; `Date.fromIsoString`; `as` on untrusted data |

Float64 division by zero needs its own decision: bubble everywhere, as
documented, or follow IEEE 754 (Infinity and NaN), as C++, C#, Java, JS,
and Lua already do. Narrowing conversions (`Int64.toInt32`), `appendCodePoint`, `Mapped.get`,
and how `as` tells a known-safe downcast from a check on untrusted data
are judgment calls, best settled one by one.

## What `orelse` catches

`orelse` (and `catch`, if added) handles only Temper failures declared by
the expression it covers. It never catches a panic, a host exception, a
stack overflow, or an out-of-bounds read. Today it catches far more on
five of seven backends: everything in C#, JS, and Lua, any
`RuntimeException` in Java, and any `Exception` in Python, so a host bug
inside a callback becomes the fallback value
([findings §1](claude-findings.md#host-exceptions-inside-callbacks)).
That needs declared failure types that host code can also catch
selectively, builtins raising them rather than `ValueError`,
`NumberFormatException`, or Lua strings, and generated handlers that
catch only those types ([below](#panics-per-backend)).

## Host-facing failure types

What host code catches or checks, under either proposal. The
[survey](claude-error-types-survey.md) has the facts per language, and
the [translations](claude-translations/README.md) show each one.

- **Library names, never Temper's.** Each failure type a library declares
  is generated under its own name in the library's namespace, and each
  library gets one generated base: a class in C++, C#, Java, JavaScript,
  and Python (`WherewithException` in C# and Java, by their naming rules;
  `WherewithError` elsewhere), an `Error` interface in Go, an `Error` enum
  in Rust, a metatable in Lua. Host code catches everything from one
  library with it, as Python code catches `requests.RequestException`.
  A `throws Bubble` failure, which has no detail, surfaces as that base
  itself. Today the only catchable failure types, C++'s
  `temper::core::TemperBubble` and Rust's `temper_core::Error`, are named
  after Temper, and the other backends throw bare `RuntimeException`,
  `RuntimeError`, `Error`, or `Exception`; both change. (Temper names
  elsewhere in host APIs, such as C++'s `temper::core::Str`, are a
  separate question.)
- **A category alongside the base.** Java, C#, JavaScript, and C++ allow
  one superclass chain, and Java and C# can't catch interfaces, so a
  failure can't extend both `WherewithException` and
  `IllegalArgumentException`. Proposed: the library base is always the
  superclass, as the JDK's `DateTimeException` and .NET's
  `JsonException` are; Python adds the category by multiple inheritance
  (`class SqlProblem(WherewithError, ValueError)`), and Go by an `Is`
  method; where a library's failures all share one category, its base
  can extend that category's class. Otherwise the category is dropped.
  Open: whether categories are worth having with this little reach.
- **Java: unchecked by default.** The base extends `RuntimeException`, so
  failures work with lambdas and streams, as in Kotlin, where nothing is
  checked; generated signatures still list them in `throws` clauses,
  which Java allows for unchecked exceptions. A library-wide setting
  makes the base extend `Exception`, so every failure is checked. It's
  per library, not per function, since one base serves all.
- **A message always; equality never required.** Every host has a
  message slot and Go and Rust require one, so each failure gets a
  message, from the author or generated from its fields. No host language
  requires or uses equality or hashing on thrown types, so failure types
  don't need them. Causes map to each host's slot (`getCause`,
  `InnerException`, `__cause__`, `cause`, `source()`, `Unwrap()`).
- **Generic failure types** can't become JVM exceptions (Java and Kotlin
  forbid generic `Throwable` subclasses), so a failure type that
  becomes an exception class must be non-generic. A function that is
  generic over its callback's failure type (`throws E`, as in Swift 6)
  is a different matter: each use instantiates `E` with a concrete
  declared failure type or a "can't fail" type, so every failure a host
  sees is still of a concrete, non-generic type.
- **Failure types are sealed (closed).** Languages without exceptions need
  every variant known when the library is compiled: Zig turns the kinds
  into an error set and the fields into a tagged union carried in a
  diagnostics parameter; C uses an enum plus a struct with a union; Rust
  an enum; Go one concrete type per variant matched with `errors.As`;
  Elixir one struct per variant (with its own `parse`/`parse!` pair of
  forms); Lua a tag field. An open failure interface, which other
  libraries could extend later, has no representation in Zig or C, so
  failure types must be sealed as well as non-generic. Across the 30 or
  so most used languages, sealed variants with fields map onto
  exceptions (one class per variant), sum or result types, or codes plus
  data; only environments with no structured error data, such as shell
  exit codes, can't carry them, and those aren't library hosts.
- **C++ without exceptions.** Many C++ codebases build with
  `-fno-exceptions`, where generated code that throws doesn't compile.
  C++ output should offer an exception-free style: failures as
  `std::expected<T, E>`, with a small shim of the same interface in the
  runtime below C++23, and panics through a configurable abort hook. Since
  the two styles have different signatures, this fits a per-build option
  better than preprocessor switches in one output. Under failures as
  values it's the natural C++ form; under declared failures, C++ needs
  both mechanisms.

## Precedence

Today `orelse` (4) and `??` (9) bind looser than `==`, so
`half(k) orelse 0 == 1` means `half(k) orelse (0 == 1)`, and the frontend
accepts the type mismatch
([explore](claude-explore/README.md#operator-precedence)). Either:

- move the default operators above comparison and equality and below
  arithmetic, at one shared level, as Kotlin's `?:`, Swift's `??`, and
  Zig's `orelse` are; or
- require parentheses where they mix with comparison or logical
  operators, as JavaScript does for `??` with `&&` and `||`.

Either way, the type checker should reject a fallback whose type doesn't
fit. A propagation operator, in either proposal, should bind at call
level (left to right with `.` and calls), not collide with `?.` (so not
postfix `?`), and say how it combines with `await`: Rust writes
`f().await?` so the awaited value's failure propagates. Postfix `!` reads
as "assert not null" to TypeScript, Kotlin, C#, and Swift users, which is
worth weighing.

## Naming across failure styles

The same operation may come in variants that fail, give null, take a
fallback, or panic. Temper's std already mixes names for them:
`propertyValueOrNull` beside `propertyValueOrBubble`; `JsonInt32.asInt64`,
which bubbles, beside `asInt64Safe`, which can't fail; `getOr(key,
fallback)`; and `toInt32Unsafe`, which gives a backend-dependent value
out of range. Precedents:

| Language | Fails | Absent or fallback | Panics |
|---|---|---|---|
| Kotlin | `toInt()` throws | `toIntOrNull()`, `getOrNull(i)`, `getOrElse(i) { … }` | `!!`, `error()` |
| C# | `int.Parse` throws | `int.TryParse(s, out v)` | |
| Swift | a `throws` function | `try?` at the call | `try!` at the call |
| Rust | `parse()` returns `Result` | `get(i)` returns `Option`; `.ok()` at the call | `v[i]`; `unwrap()`, `expect()` at the call |
| Go | `(v, err)` | | `regexp.MustCompile` |
| Java, JS | `Integer.parseInt`, `JSON.parse` throw | Guava's `Ints.tryParse`; zod's `safeParse` | |

Proposed rule:

1. **In Temper source and std, the plain name fails** with the
   operation's failure (thrown under declared failures, returned under
   values): `parseSelect`, `toInt32`.
2. **Variants take a suffix with one meaning each:** `…OrNull` returns
   `T?` and drops the reason; `…Or(fallback)` returns the fallback, as
   `getOr` does. No `…OrBubble` or `…Safe`. (`asInt64Safe` exists
   because an override can't drop `throws Bubble`; whether an override
   may declare less failure is a question for either proposal.)
3. **No panicking variants by name;** callers write `orelse panic()`.
   The exception is syntax that panics by contract (`list[i]`), whose
   checked forms are the named ones (`getOrNull`, `getOr`).
   `toInt32Unsafe` describes out-of-range behavior, not a failure style,
   and is better named for that behavior once it's settled (Rust's
   `wrapping_`, `saturating_`).
4. **Generated host forms follow the host, never Temper's suffixes:** the
   plain name is each host's default (throwing in C#, Java, JavaScript,
   and Python; `Result` in Rust; `(v, err)` in Go; `nil, failure` in
   Lua). In a first pass, that's the only generated form: no `Try…` or
   `Must…` twins. Most .NET methods have no `Try` form either; .NET
   reserves the Try pattern for operations where failure is a common,
   normal outcome. Later, a library could ask for one where that's true,
   for example by presenting an author-written `…OrNull` variant as C#'s
   `TryParseSelect(…, out …)`. Variants an author writes in Temper keep
   their Temper names, case converted. Generated names are recorded in
   `temper.keep`.

How this fits the team's earlier naming discussion
([team-function-naming.md](team-function-naming.md), 2026-10-06):

- **Its affix rules agree with the rule above:** add an affix when it
  disambiguates (`…OrNull` against `…OrEmpty`); leave the API people
  should use unaffixed; and when a safe alternative is preferred, put a
  negative affix on the unsafe, occasional one.
- **Its kinds of unsafety are a useful vocabulary for docs and affixes**,
  beyond failure styles: can bubble, can panic, semantic ambiguity across
  backends, a security issue if misused, and a contract the caller must
  uphold. The last three are where negative affixes belong (for example
  an API taking raw HTML beside one taking `SafeHtml`), while failure
  styles follow the suffixes above.
- **`tryX`** (Tom's idea, not in that discussion) is an alternative to
  `…OrNull` for the variant that returns `T?`: familiar from C#'s
  `TryParse` and Guava's `tryParse`, shorter at call sites, but it reads
  like propagation syntax if Temper adopts a `try` keyword, and in C# it
  conventionally means a `bool` result with an `out` parameter. Worth
  deciding together with the propagation syntax.

## Lowering a local failure to a branch

Where a failure is raised and handled in one function, directly or after
inlining, the compiler can emit a plain branch instead of an exception.
No language change is needed. On C++, C#, Java, and JS it removes the
whole failure cost in parsing loops, from 2 times at 1 percent failures to
about 100 times at 90 percent; it's roughly neutral on Python and Lua
(Lua saves the closure and `pcall`), and Rust has it already
([findings §2](claude-findings.md#when-lowering-would-pay)). Under the
values proposal this is the normal case; under declared failures it's an
optimization.

## Panics per backend

A panic follows each backend's idiom (process exit in some, an exception
that's uncatchable by convention in others), and Temper gives no
guarantee that one is recoverable, so library code must not rely on
catching one. What the RFC pins down: `orelse` never catches a panic
(today it does on JS and Lua), and a panic's message reaches the user
(C++ prints none today and can lose earlier output).

**The key rule: generated handlers catch only declared failure types.**
A handler (`orelse`, `catch`) catches the failure types declared by the
expression it covers, which are the library's own types; in a host
without typed catch, it tests for the library base or a tag and rethrows
anything else. So a panic can be any idiomatic signal that isn't a
failure, and it passes every Temper handler untouched, as does any host
exception:

| Backend | Failures | Panics | How handlers tell them apart |
|---|---|---|---|
| Java | library `RuntimeException` subclasses (`Exception` subclasses if the library opts into checked) | an `Error` subclass or `IllegalStateException` | typed `catch` of the declared type; never caught |
| C# | library failure classes | `InvalidOperationException`, or `Environment.FailFast` if preferred | typed `catch` |
| Python | library exception classes | `AssertionError` or another builtin | typed `except` |
| JS | library `Error` subclasses | a plain `Error` | `instanceof` the declared type or library base; rethrow anything else |
| Lua | tagged failure tables, or `nil, failure` returns | `error()` with a string | check the tag; rethrow anything else |
| C++ | `std::expected` errors, or library exception types in a throwing build | the panic hook, `std::terminate` or `abort` by default | values are checked; typed `catch` in a throwing build |
| Rust | `Result` errors | `panic!` | values are checked; panics unwind past |
| Go | `error` values | `panic` | values are checked; no `recover` |
| Zig, C | error sets or status codes | `@panic`, or an abort hook | values are checked |

This fixes today's catch-alls: everything in C#, JS, and Lua, any
`RuntimeException` in Java, and any `Exception` in Python, including JS
and Lua's `orelse` catching `panic()` (bugs 1, 3, and 12
[below](#bugs-to-fix-as-part-of-the-rfc-work)). A handler inside code
that is generic over a callback's failure type can't name one library's
type; how it recognizes a Temper failure there (a marker every library
base carries, or a type witness) is open.

## Panics in test runners

A test that panics is reported as a failed test with its message, and the
other tests still run. Today C# and C++ lose the whole run ("0 of N, N
not run"); interp, Java, Lua, Python, and Rust already report each test
on its own ([findings §1](claude-findings.md#panics-in-temper-test)).

## Compatibility of failure changes

Under either proposal, adding or changing the failure an exported
function can produce changes what host code catches or checks, in every
backend. The RFC should say which changes are compatible (probably adding
a variant is not, in languages with exhaustive matching) and record
host-visible names in `temper.keep`.

## Bugs to fix as part of the RFC work

From [findings §1](claude-findings.md#bugs-found), most touch what
`orelse` catches or how builtins fail, so they fit this work; any that
proves urgent can go first.

| # | Bug | Settled by |
|---|---|---|
| 1 | JS and Lua: `orelse` catches `panic()` | what `orelse` catches |
| 2 | Float64 `/` and `%` by zero don't bubble on five backends | which builtins panic |
| 3 | out-of-bounds list reads caught by `orelse` on six backends | what `orelse` catches |
| 4 | JS runtime: `listed.js` calls `bubble()` without importing it | which builtins panic (list access) |
| 5 | `String.toInt32` accepts different strings per backend | which builtins panic (recoverable ones must agree) |
| 6 | C++ loses console output on panic, and prints no reason | panics per backend |
| 7 | C# and C++ test runs report nothing for a panicking test | test runners |
| 8 | a bubbling `await` in an `async` block fails at translation | either proposal's async rules |
| 9 | bubbling generators aren't translated | either proposal's generator rules |
| 10 | a non-bubbling function passed as a bubbling `@fun interface` fails on Python | either proposal |
| 11 | JS: exported interface methods emitted as class fields | either proposal (host callbacks) |
| 12 | Lua builtins fail through incidental Lua errors | what `orelse` catches |

The explorations add a few more: the precedence trap above, a `when` over
a generic sealed interface not seen as exhaustive, and narrowing after
`if (r is Failed<…>) { return r; }` failing in backends
([explore, observations 10 and 11](claude-explore/README.md#observations)).
Turning the probes in findings §1 into a shared functional test would let
the RFC state current behavior as tested facts.
