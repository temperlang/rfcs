(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: Declared failures for Temper

Author(s): draft by Claude Code (Claude Opus 5.5), for Tom P. and the team

Last updated: 2026-11-18

Discussion at https://github.com/temperlang/temper/issues/164.

**This is a draft written by Claude for Tom and the team to react to,** not
a decision. It turns
[Claude's recommendation](claude-recommendation.md) into one proposal,
following the direction Tom chose on 2026-11-18 (the middle ground,
callback polymorphism through an ordinary generic failure parameter, and
no `capture` in the first version), and links to the supporting files in
this folder rather than repeating them. All syntax marked **proposed** is
hypothetical and doesn't compile today.

## Abstract

A function declares at most one failure type, `T throws E`, where `E` is a
declared, sealed, non-generic failure type: a failure class, or a sealed
interface of them, which `error case` declarations can build. Failure
objects are ordinary values with readable fields, plus an optional
message and cause for host code. The compiler represents `T throws E`
internally as an ordinary generic result type, but Temper source can't
name or hold a result. A higher-order function is generic over its
callback's failure type, as with Swift 6's typed `throws(E)`; a callback
that can't fail instantiates it as `Never<Error>`. Code that needs to
keep an outcome stores the failure object itself. Propagation is
explicit with an expression-wide `try`; `orelse` gives defaults, `catch`
binds the failure in a block, and `return`, `break`, and `continue`
become expressions. Panics are separate, and Temper code never catches
them; builtins whose failure is a bug (division by zero, failed
downcasts, list access out of range) panic. Each backend presents
failures in its host's own idiom, under the library's names, and its
generated handlers catch only declared failures, never panics.
`throws Bubble` keeps working as the failure with no detail.

## Background

Temper has `throws Bubble`, `bubble()`, `orelse`, and `panic()`. A failure
carries nothing, propagates implicitly inside a `throws Bubble` function,
and reaches host code as whatever each backend throws. The evidence in
this folder ([findings](claude-findings.md),
[explorations](claude-explore/README.md), and the
[Kotlin `Result` review](claude-kotlin-result-review.md)) shows six
problems:

- **Failures carry no reason.** Wherewith keeps a `…Problem()` twin for
  each bubbling operation that re-runs the check to say why; its parser
  computes a message in `need(message)` that the bubble then drops; std's
  `parseJson` drops its message too; Hrefine's docs say "Failures say
  nothing, in every language"
  ([findings §3](claude-findings.md#where-libraries-built-their-own-error-values-and-why)).
- **Host code gets generic exceptions.** Java, C#, JS, and Python throw
  bare `RuntimeException`, `Exception`, `Error`, and `RuntimeError` with
  no message; the only catchable types, C++'s `TemperBubble` and Rust's
  `temper_core::Error`, are named after Temper, not the library
  ([findings §1](claude-findings.md#what-host-code-sees-from-an-exported-function)).
- **`orelse` catches too much.** It catches everything in C#, JS, and
  Lua, any `RuntimeException` in Java, and any `Exception` in Python, so a
  host bug inside a callback, or an out-of-bounds read on six backends,
  becomes the fallback value
  ([findings §1](claude-findings.md#host-exceptions-inside-callbacks)).
- **Panics are conflated with failures.** JS and Lua's `orelse` catches
  `panic()`. Of 596 `orelse`s in the surveyed libraries and std, 500 are
  `orelse panic()` on operations the author knows can't fail, and
  bubbling from indexing and division alone spreads `throws Bubble`
  through 31 of Chromarite's 52 declarations
  ([common ground](claude-common-ground.md#which-builtins-panic)).
- **Libraries build their own error channels.** Four of six built one:
  Argmas's `ParseResult`, Hrefine's `UrlCheck`, Wherewith's twins, and
  Kelpto's error lists. None works with `orelse`, so there are two
  failure worlds.
- **Kotlin Temper's second-class results cost special cases.** Mike's
  2026 work made `Result<T, Bubble>` the internal truth of failure, which
  removed whole passes, but generic code has no way to be polymorphic in
  failure, so every generic feature needs its own workaround: the
  `checkFun` TODO and `HACK`, core's `forEach` inlined so `bubble()`
  escapes it, std's `asInt64Safe` twin, two types per TmpL expression,
  broken bubbling `await` and generators, and a `Bubble` type parameter
  that can't be bounded
  ([review §4](claude-kotlin-result-review.md#4-toms-question-did-mike-deliberately-keep-results-out-of-temper-code)).

Tom's 2024 notes ([tom-thoughts.md](tom-thoughts.md)) and Mike's 2026
notes ([mike-thoughts.md](mike-thoughts.md)) agree on the direction:
declared failures distinct from panics, only declared failures catchable,
explicit propagation, and idiomatic host forms. Mike adds a single failure
type per function and opaque, convertible messages and causes. This
proposal combines them and answers the question the two sketches
([declared](claude-proposal-declared.md) and
[values](claude-proposal-values.md)) separate, whether Temper code can
hold a result: not in the first version.

## Proposal

### Semantics

1. **Failure objects are ordinary values.** A caught `SqlProblem` can be
   bound, stored, passed, put in lists, compared by its fields, and
   thrown again.
2. **One failure type per function.** `T throws E`, where `E` is declared
   as a failure type: a non-generic class, or a sealed interface whose
   variants are such classes, or a failure parameter (item 6). No unions,
   so the type solver and backends see one type. Sealed and non-generic
   because Zig, C, Rust, and Go need every variant known when the
   library compiles, and the JVM forbids generic `Throwable` subclasses
   ([common ground](claude-common-ground.md#host-facing-failure-types)).
   Only declared failure types can be thrown, so each maps to one host
   class or variant with no wrapper. Every declared failure type extends
   a root interface in core, named `Error`
   ([naming](#naming-the-root)).
3. **`error case` sugar** (proposed, from Tom's notes):
   `error case NotFound;` declares a failure class with no fields,
   `error case BadWord(public text: String);` one with fields, and
   `throws X, Y` stands for a generated sealed interface with `X` and `Y`
   as variants.
4. **Message and cause.** Every failure type's factory also takes an
   optional message and an optional cause (another failure), and can't
   fail. Temper code can pass them on but not read them; backends use them
   for host messages and chained causes (Mike's "highly convertible"
   throwables). Fields the library declares are ordinary and readable.
5. **Results can't be held,** the middle ground of the
   [two questions](claude-recommendation.md#two-questions). Internally,
   in the frontend's typing and in tmpl, `T throws E` is an ordinary
   generic type `Result<T, E>`, as in Kotlin Temper today, so
   substitution, inference, and lowering handle it like any other generic
   type. Temper source can't name `Result`, and no variable, field, list
   element, or ordinary type parameter can have a result type: `Result`
   isn't a subtype of `AnyValue`, Kotlin's existing rule. A failure exists
   only between `throw` and its handler.
6. **Callbacks are polymorphic through an ordinary generic failure
   parameter,** as with Swift 6's typed `throws(E)`, instead of a special
   `rethrows` keyword:
   `map<T, R, E>(xs: List<T>, f: fn (T): R throws E): List<R> throws E`.
   - `E` is bounded by the root: `E extends Error`, written or implied
     by its use after `throws`.
   - A function type without `throws` means `throws Never<Error>`.
     Under Temper's `Never<T>` rules, `Never<Error>` is a subtype of
     `Error` only and has no values, so it fits the bound and means "a
     failure that can't happen".
   - Inference fills `E` at each call, so users never write it: a
     callback that can't fail gives `Never<Error>`, and the call needs
     no `try`; one that throws `SqlProblem` needs `try` or a handler. A
     function that can't fail is also accepted where a failing one is
     expected.
   - The body can only `try f(x)` (propagate) or handle it, binding the
     failure object if it likes. It can't store a result, since item 5
     forbids holding one: no effect system beyond that.
   - Exported failure types stay sealed and non-generic. A generic `E` is
     instantiated with a concrete declared type or `Never<Error>` at
     each use, so every failure reaching a host has a concrete type.
7. **Keeping an outcome means keeping the failure object.** No `capture`
   in the first version: code that needs an outcome later stores the
   failure itself, and promises already hold the failures of async work,
   which `try await` rethrows. Capture, or holdable results, can be added
   later if real code shows the need.
8. **Propagation passes a failure through** when its type is the caller's
   failure type or one of its variants. Anything else needs an explicit
   conversion, with the original as cause (Mike's `rethrowAs`).
9. **Panics are separate.** `panic()` is never caught by Temper code. A
   host exception that reaches Temper code, from a connected function or a
   host callback, is a panic. Temper gives no guarantee that a panic is
   recoverable; it guarantees only that its message reaches the user
   ([common ground](claude-common-ground.md#panics-per-backend)).
10. **Handlers catch only Temper failures** declared by the expression
    they cover: never a panic, a host exception, a stack overflow, or an
    out-of-bounds read
    ([common ground](claude-common-ground.md#what-orelse-catches)).

```temper
// Proposed: `error case`, `throws`, prefix `try`, `catch`, and failure
// parameters (`E`, bounded by `Error` through its use after `throws`).
export error case SqlProblem(public text: String, public word: Int);

public select(): Select throws SqlProblem {
  try keyword("SELECT");
  let columns = new ListBuilder<String>();
  try columns.add(name("a column"));
  while (peek() == ",") { pos += 1; try columns.add(name("a column")); }
  try keyword("FROM");
  let table = try name("a table");
  if (peek() != null) { throw problem("expected the end"); }
  new Select(columns.toList(), table)
}

public map<T, R, E>(xs: List<T>, f: fn (T): R throws E): List<R> throws E {
  let out = new ListBuilder<R>();
  for (let x of xs) { try out.add(f(x)); }
  out.toList()
}

let doubled = map(xs, fn (x: Int): Int { x * 2 });  // E = Never<Error>: no `try`
let ids = try map(texts, fn (t: String): Int throws SqlProblem { try parseId(t) });

var problem: SqlProblem? = null;                     // keep the outcome
let node = parse(s) catch (e) { problem = e; null };
```

The parser rule keeps today's 13-line shape with one marker per
propagating expression; Wherewith's `problem` field, `report`, and
`selectProblem` twin go
([wherewith-problems](claude-explore/wherewith-problems/README.md)).

### Syntax

All proposed; the spellings of `try` and failure parameters are open
([options](claude-syntax-options.md)), and the root is named `Error`
([naming](#naming-the-root)).

- **`try` marks propagation for the whole expression to its right,** as
  in Swift: `let c = try lookup(s).column().type();`. A failure goes to
  the nearest enclosing `catch`, else out of the function. Written
  `try await f()`, so the awaited value's failure propagates. A call that
  can fail needs `try` unless it is directly the operand of a handler.
- **`orelse` is the expression default operator and never binds,** as
  today: `f() orelse 0`, `f() orelse (a + b) * c`.
- **`catch` is a keyword clause shaped like `else`:** it always takes a
  block, optionally after a binding, `f() catch (e) { … }` or
  `f() catch { … }`. So it follows Temper's brace rule, its block is never
  mistaken for a function literal, and `return`, `break`, and `continue`
  inside it refer to the enclosing function. `when (e)` over a sealed
  failure type checks that every variant is covered
  ([binding the failure](claude-syntax-options.md#binding-the-failure)).
- **`do { … } catch (e) { … }`** is the full block form, as Swift spells
  it, so `try` keeps one meaning; inside the block, `try` sends failures
  to the `catch`
  ([a full try/catch block](claude-syntax-options.md#a-full-trycatch-block)).
- **`??` stays for null,** and could later merge with `orelse`.
- **`return`, `break`, and `continue` become expressions** of type
  `Never`, as in Kotlin and Rust
  ([common ground](claude-common-ground.md#return-break-and-continue-as-expressions)).
- **Precedence:** `orelse`, `catch`, and `??` share one level above
  comparison and equality and below arithmetic, as Kotlin's `?:`,
  Swift's `??`, and Zig's `orelse` do, so `x orelse 0 == y` means
  `(x orelse 0) == y`, not today's `x orelse (0 == y)`. The type checker
  rejects a fallback whose type doesn't fit
  ([common ground](claude-common-ground.md#precedence)).
- **`throws Bubble`** stays as the failure type with no fields, and
  `bubble()` raises it.

```temper
// Proposed.
let n = s.toInt32() orelse 0;                       // default
let m = s.toInt32() orelse continue;                // skip this item
let x = findCached(k) ?? return null;               // null, propagated
let q = parseSelect(sql) catch (e) { log("${e.text}, word ${e.word.toString()}"); null };
let v = do { try a(); try b() } catch (e) {
  when (e) { is MissingValue -> fallback; is UnknownWord -> panic(); }
};
```

### Naming the root

The root is `Error`, the most common name across languages: JS, Python
(by PEP 8's suffix convention), Rust, Swift, and Go all use it, and
Temper favors common names. Tom would like `Exception` for its broader
meaning, but it's longer and less common across languages. Mike first
chose "bubble" so it wouldn't sound like failure, but nullables are the
clearest way to express a non-value that doesn't imply failure, so
`throws` and `Error` are for real errors. It also fits the names
programmers already bind, `e` and `err` (`catch (e) { … }`). Java's
`java.lang.Error` ("don't catch") doesn't matter: the root never
appears in host code. Considered: `Failure`, the earlier working name,
which breaks that habit (`f`), clashes with test-failure vocabulary in
std testing, and is a new word to learn;
`Exception`; `Fault`; and `Problem`, which core already has as a
builtin.

### Builtins: panic or fail

A builtin panics where failure is a bug that a cheap check avoids, and
stays a failure where libraries actually recover. Of the 500
`orelse panic()`s, 204 are on `as` downcasts, 56 on list or map reads,
40 on `appendCodePoint`, 14 on `/` and `%`, 6 on `String.fromCodePoint`,
and 1 on a conversion
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)).

| Panic | Stay failures |
|---|---|
| Int `/` and `%` by zero; list access out of bounds (already a panic by contract, but caught on six backends today); `as` downcasts | `String.toInt32`, `toInt64`, `toFloat64`; `parseJson`; `Date.fromIsoString`; type tests on untrusted data |

Float64 division by zero needs its own decision (bubble everywhere, as
documented, or IEEE 754 Infinity and NaN, as five backends already do),
and so do narrowing conversions, `appendCodePoint`, `Mapped.get`, and how
untrusted data is checked once `as` panics. Recoverable builtins must
agree on which inputs fail across backends (today `String.toInt32`
doesn't).

### Host mapping

Each backend presents failures in its host's idiom. The
[translations](claude-translations/README.md) show Wherewith's rule in
each language, and the [survey](claude-error-types-survey.md) has the
facts per language.

| Backend | A failure type becomes | Exported function (first pass) |
|---|---|---|
| C# | `SqlProblem : WherewithException : Exception` | `ParseSelect` throws; no `Try…` twin ([C#](claude-translations/csharp.md)) |
| Java | `SqlProblem extends WherewithException extends RuntimeException`; checked by a library-wide setting | throws, listed in the `throws` clause ([Java](claude-translations/java.md#checked-or-unchecked-meeting-point-3)) |
| JS | `SqlProblem extends WherewithError extends Error` | throws ([JS](claude-translations/js.md)) |
| Python | `class SqlProblem(WherewithError, ValueError)`, the category by multiple inheritance | raises ([Python](claude-translations/python.md)) |
| C++ | `SqlProblem : WherewithError : std::runtime_error`, held unthrown | returns `std::expected<T, SqlProblem>`, with a runtime shim of the same interface below C++23; `.value()` throws `std::bad_expected_access<SqlProblem>`; a throwing form by build option ([C++](claude-translations/cpp.md)) |
| Rust | a struct, or an enum for a sealed type, implementing `std::error::Error`, convertible into the crate's `wherewith::Error` | `Result<T, SqlProblem>`, like today's lowering ([Rust](claude-translations/rust.md)) |
| Go (as if a backend) | a struct implementing `error` and `wherewith.Error` | `(T, error)`, matched with `errors.As` ([Go](claude-translations/go.md)) |
| Lua | a tagged table with a shared metatable whose `__tostring` gives the message | `nil, failure`; `assert(f(…))` raises it ([Lua](claude-translations/lua.md)) |
| Zig, C (future) | an error set, or an enum of codes, with fields, message, and cause in a diagnostics out-parameter | error union, or status code ([C and Zig](claude-translations/c-and-zig.md)) |

Rules across backends
([common ground](claude-common-ground.md#host-facing-failure-types)):

- **No Temper names** in what users catch: each failure type keeps the
  library's name in its namespace, and each library gets one generated
  base (`WherewithException` in C# and Java, `WherewithError` elsewhere,
  an `Error` interface in Go, an `Error` enum in Rust, a metatable in
  Lua). A `throws Bubble` failure surfaces as that base. The root
  `Error` never appears in host code; in Java and C# the library base
  extends `RuntimeException` or `Exception`. `TemperBubble`
  and `temper_core::Error` leave the host API. A category such as
  `ValueError` joins the base only where the host allows it (Python, Go).
- **Host names follow the host (proposed).** Libraries name their own
  types in Temper: `export sealed interface WherewithError extends
  Error`, `class SqlProblem(…) extends WherewithError`. The Java, C#,
  and Kotlin backends own one rule: a type extending the root whose name
  ends in `Error` ends in `Exception` instead (`WherewithException`).
  Other names (`SqlProblem`) stay as written, with nothing appended.
  Clashes go through the existing clash handling, private names renamed
  first; per-backend overrides come from the planned naming RFC (say,
  `@name(java = "…")`), and host-facing names are recorded in
  `temper.keep`.

  | Hosts | `WherewithError` | `SqlProblem` |
  |---|---|---|
  | C#, Java, Kotlin | `WherewithException` | `SqlProblem` |
  | Go, JS, Python, Rust, Swift | `WherewithError` | `SqlProblem` |
- **No result types in host APIs.** Since Temper code can't hold a
  result, no exported function takes or returns one; hosts see only
  their own forms (a throw, `Result`, `(T, error)`, `nil, failure`).
- **Java is unchecked by default,** so failures work with lambdas and
  streams, as in Kotlin; a library-wide setting makes them checked.
- **C++ works without exceptions:** the `std::expected` default compiles
  under `-fno-exceptions`, and panics go through a configurable abort
  hook.
- **A message is always available,** from the author or generated from
  the fields (short and lowercase, as Rust's convention has it), and
  causes map to each host's slot (`getCause`, `InnerException`,
  `__cause__`, `cause`, `source()`, `Unwrap()`). Equality and hashing
  aren't required; no host uses them to pick a handler.
- **Stack traces only where a failure may escape.** With explicit
  propagation, the compiler knows where a failure may reach an exported
  function unhandled, and captures a trace only there.
- **Naming, first pass: the host's default form only**
  ([naming rule](claude-common-ground.md#naming-across-failure-styles)).
  In Temper source the plain name fails (`parseSelect`), `…OrNull` gives
  `T?`, and `…Or(fallback)` a fallback; no `…OrBubble`, `…Safe`, or
  panicking variants by name. Generated host APIs use each host's plain
  form and no `Try…` or `Must…` twins.
- **Representation is each backend's choice,** with identical behavior
  checked by shared tests
  ([values sketch](claude-proposal-values.md#semantics-and-representation-are-separate-choices)).
  Since no result is ever held, exception backends need no result class:
  the JVM keeps Kotlin's lightweight exceptions, C# keeps exceptions in a
  first pass and can move to value types if failure-heavy uses need
  them, and JS, Python, and Lua use plain values or exceptions. A failure
  parameter costs them nothing, since the failure propagates through the
  generic function. C++ and Rust use value types, generic over `E`
  (Rust's `fn map<T, R, E>(…) -> Result<Vec<R>, E>`, with an uninhabited
  error type for `Never<Error>`); Go, Zig, and C use error values. A
  `throw` handled in the same function, directly or after inlining,
  becomes a branch
  ([common ground](claude-common-ground.md#lowering-a-local-failure-to-a-branch)).

### Failures and panics on every backend

Generated handlers catch only the declared failure types of the
expression they cover, or, in hosts without typed catch, test for the
library base or a tag and rethrow anything else. So a panic can be any
idiomatic signal that isn't a failure, and it, like any host exception,
passes through every Temper handler
([common ground](claude-common-ground.md#panics-per-backend)):

| Backend | Failures | Panics |
|---|---|---|
| Java | library `RuntimeException` subclasses | an `Error` subclass or `IllegalStateException` |
| C# | library failure classes | `InvalidOperationException`, or `FailFast` |
| Python | library exception classes | `AssertionError` or another builtin |
| JS | library `Error` subclasses | a plain `Error` |
| Lua | tagged failure tables, or `nil, failure` | `error()` with a string |
| C++ | `std::expected` errors, or library exception types | the panic hook (`std::terminate` or `abort` by default) |
| Rust | `Result` errors | `panic!` |
| Go | `error` values | `panic` |
| Zig, C | error sets or codes | `@panic`, or an abort hook |

This fixes today's catch-alls, including JS and Lua's `orelse` catching
`panic()`.

## Rationale

### Why the middle ground, through generics

Typing `T throws E` as `Result<T, E>`, as Kotlin does internally, lets
the compiler's generic machinery carry failure. If a fallible `f` given
to `map<T, R>` instantiated `R` as a result, `map` could store it, and
results would be first-class. Instead, failure gets its own parameter:
`R` never binds a result, and `E` binds only a failure type or
`Never<Error>`, so generic code can propagate or handle `E` but never
hold it, with no rule beyond the bound
([why generics decide](claude-recommendation.md#why-generics-decide-the-semantics)).
Swift took the same path, from `rethrows` to typed `throws(E)`, where
`throws(Never)` means "can't fail".

It removes Kotlin's special cases
([review §4](claude-kotlin-result-review.md#4-toms-question-did-mike-deliberately-keep-results-out-of-temper-code)):

- **`Bubble` as a type parameter.** Kotlin already tried
  `<BUBBLE extends Bubble>` for callbacks, but *Typer* doesn't strip such
  a parameter from a call's type
  ([#108](https://github.com/temperlang/temper/issues/108)), and
  `Bubble` isn't a nominal type, so it can't be a bound
  ([#109](https://github.com/temperlang/temper/issues/109)). Here
  `Error` is a nominal interface, and stripping `E` is ordinary
  `Result<T, E>` handling.
- **Inlined `forEach`.** `forEach<T, E>(f: fn (T): Void throws E): Void
  throws E` propagates without inlining.
- **The `checkFun` TODO.** `fn <T>(f: fn (): T): T { f() }` accepts only
  callbacks that can't fail; the failing version declares `E`.
- **Bug 10 and `asInt64Safe`.** A function that can't fail fits where a
  failing one is expected, so passing one as a failing `@fun interface`
  works ([bug 10](claude-common-ground.md#bugs-to-fix-as-part-of-the-rfc-work));
  whether an override may narrow its failure type, retiring
  `asInt64Safe`, is open.
- **`await` and generators.** A promise holds its failure, typed by the
  async block, and `try await` rethrows it, with no hidden result.

Mike kept results second-class so that backends needn't represent
ad-hoc unions; this keeps result types out of host APIs entirely.
Exception-style syntax then tells the truth: no value is ever a result.

### Alternatives considered

- **First-class results** ([values sketch](claude-proposal-values.md)),
  the main alternative: Temper code can hold, store, return, collect,
  and map a `Result<T, E>`. No rule beyond the result type; generics,
  `await`, generators, and caches need nothing special; libraries'
  result values become the normal style. It is the better choice if the
  team expects many APIs to store outcomes (lazy values, caches, tasks).
  Not chosen because any value may then be a result, `map` collecting
  results needs a separate short-circuiting function, exception backends
  need held results wherever one may be held, and exported APIs that hold
  results need a host result type. Most of this proposal (failure types,
  host mapping, builtins, handling syntax) carries over if the team
  picks it.
- **Capture** (`capture { … }` turning a failure into a held result, in
  earlier drafts): a possible later addition. Left out of the first
  version because failure objects are already ordinary values and
  promises hold async failures, and when in doubt, leave it out.
- **A `rethrows`-style keyword** instead of a failure parameter: a second
  mechanism beside generics, which Swift 6's typed throws subsumes.
- **In flight without failure polymorphism** (Kotlin Temper today): no
  new rule, but every generic feature pays a special case.
- **Unions** (`throws A, B`, Java's checked exceptions): hard to
  translate and to solve, as Mike notes; `throws X, Y` is sugar for one
  sealed type instead.
- **Kinds without details** (Tom's 2024 `error case` without fields):
  keeps the side channels, since a kind can't carry Wherewith's text or
  Hrefine's position
  ([observations](claude-explore/README.md#observations)).
- **Any type as a failure** (the values sketch's default): exception
  hosts throw a wrapper, so host code sees two names
  ([details](claude-proposal-values-details.md#any-type-as-a-failure)).
- **A dedicated empty failure type** for "can't fail", like Rust's
  `std::convert::Infallible`, instead of `Never<Error>`: as good, but a
  second spelling of what `Never` already means. The root needs a name
  either way.
- **Syntax alternatives**
  ([options](claude-syntax-options.md)): per-call prefix `try` (Zig)
  nests in chains; postfix `?` collides with `?.`; postfix `!` reads as a
  non-null assertion to TypeScript, Kotlin, C#, and Swift users; postfix
  `.try` is unfamiliar; `orelse (e) …` binding is ambiguous with a
  parenthesized fallback; Java's `try { } catch` block clashes with a
  prefix `try`; methods on results fit first-class results only.

### Performance

Speed doesn't decide the semantics
([estimates](claude-explore/estimates/README.md)). The success path is
free on every backend but Lua, where each `orelse` costs a closure and a
`pcall` (1 to 6 percent of a Kelpto parse or a Wherewith query, gone once
bug-like builtins panic). Kelpto and Wherewith throw no failure on valid
input. Thrown failures cost 2 to 13 times a nullable at 1 percent
failures and 11 to 107 times at 10 percent on C++, C#, Java, and JS
([measurements](claude-explore/README.md#measurements)); one failure in
an invalid Wherewith query adds an estimated 15 to 300 percent. Local
lowering to a branch, trace-free throws (0.1 to 0.5 times today's cost
on Java and JS), and value representations narrow that
([compiler-known result](claude-explore/README.md#a-compiler-known-result-type-likely-cost)).

## Compatibility

**Nothing has to move at first.** `throws Bubble` stays valid as the
failure type with no fields, so all 286 declarations in the surveyed
libraries and std (87 public, 199 internal) compile, and host code keeps
catching an exception, now the library's base
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
`orelse` keeps its meaning; only its precedence changes, and only for
code that mixes it with comparison or logical operators unparenthesized.

**Explicit propagation needs a marker** at the 630 calls that propagate
implicitly today (65 public, 565 internal, about one per 60 lines;
Wherewith 365, Chromarite 140, Kelpto 52, Hrefine 36, std 32, Argmas 5)
([markers](claude-common-ground.md#propagation-markers)). The type
checker knows each site, so a **rewriting tool** adds `try`; some sites
go instead (68 of Wherewith's become `throw`s, and about half of
Chromarite's are matrix reads and division that stop failing once those
panic). `throws Bubble` functions keep implicit propagation, with a
warning, for a period the team sets.

**Where libraries move,** about 70 exported members across five
libraries want reasons, mostly parse and validate entry points
([findings §3](claude-findings.md#3-real-cases-in-public-libraries)).
Where absence is meant, rewriting `throws Bubble` to `T?` is mechanical
for 54 percent of declarations, 17 percent more given a convention for
`Void`, and needs a human for 28 percent.

**Failure changes are API changes.** Adding or changing the failure an
exported function can produce changes what host code catches or matches
in every backend; adding a variant breaks exhaustive matches (Rust,
Zig, `when`). The rule for which changes are compatible goes in the docs,
and host-visible names in `temper.keep`
([common ground](claude-common-ground.md#compatibility-of-failure-changes)).
Temper libraries are all beta, which leaves room for the move.

## Implementation

In tempest, which per [RFC 657](../../657-tempest/README.md) is Temper's
compiler from the switch on. Kotlin Temper gets no new development; its
2026 lesson, that typing failure through the return type removed whole
passes, carries over
([review §5](claude-kotlin-result-review.md#5-relation-to-the-proposals)).
The plan is to simplify internal processing to standard generic types as
far as possible.

1. **Common ground, settled first, independent of the semantics:**
   `return`, `break`, and `continue` as expressions; which builtins
   panic; precedence; what `orelse` catches; panics per backend, with
   their messages; test runners that report a panicking test and keep
   going; and per-library failure types with no Temper names.
2. **Semantics as generic types,** in the frontend and tmpl: core gains
   the `Error` root and a well-known generic `Result<T, E>`, outside
   `AnyValue`. Tmpl's `bubbles: bool` on signatures and function types,
   and the `MAY_BUBBLE` flag on calls, become that result type, so
   failure parameters are ordinary type parameters that the existing
   substitution and inference handle, and exception backends read the
   pass type `T` from the result type rather than from a second type per
   expression. Handlers bind the failure. A shared lowering pass, which
   each backend opts into through its profile's `Failure` choice,
   replaces per-translator handling, with local failures lowered to
   branches.
3. **Backends:** host-facing types, messages, causes, the stack-trace
   policy, handlers that catch only failures, panics per the table above,
   and failure parameters on value backends.
4. **Syntax,** as the team settles it.
5. **Migration:** the rewriting tool, then a deprecation schedule for
   implicit propagation.

Bugs fixed along the way: the twelve in the
[common ground](claude-common-ground.md#bugs-to-fix-as-part-of-the-rfc-work)
(among them `orelse` catching panics and out-of-bounds reads, Float64
division by zero disagreeing, bubbling `await` and generators failing at
translation, and C# and C++ test runs losing every result after a panic),
plus the precedence trap and the generic-sealed `when` gaps the
explorations found.

## Testing

- A shared functional test built from
  [findings §1](claude-findings.md#1-behavior-across-backends)'s probes,
  so behavior is a tested fact on every backend: what handlers catch,
  which builtins panic and which inputs fail, panics in callbacks and
  test runners.
- Failure parameters: higher-order helpers given callbacks that can and
  can't fail (no `try` needed for `Never<Error>`), handlers inside
  generic code, `await`, generators, and type-checker rejections (a
  fallible call without `try` or a handler, `E` bound to a non-failure
  type).
- Host harnesses per backend: the library's own types caught selectively,
  panics and host exceptions passing through every generated handler,
  messages and causes present, an escaping failure carrying its origin's
  trace and a handled one none.
- The libraries' own tests after the rewriting tool runs, and the
  benchmarks, rerun on generated code.

## Documentation

The language docs gain a failure-handling chapter (failure types,
propagation, handlers, failure parameters, keeping outcomes as failure
objects, and panics); std documents which builtins panic; each backend's
docs show what host code catches and what a panic is; and the naming
rule joins the style guide.

## Open issues

- Spellings of `try` and of failure parameters (whether
  `E extends Error` is written or implied); and `tryX` names, which
  read ambiguously beside a `try` keyword
  ([common ground](claude-common-ground.md#naming-across-failure-styles)).
- Whether real code later needs capture or holdable results: APIs that
  store a callback's outcome (lazy values, caches) are the cases to watch.
- Two callbacks with different failure types, such as a comparator and a
  key function: require one `E`, or a declared sealed type wrapping both.
- How a handler inside generic code recognizes `E` at run time on hosts
  without generic catch (a marker every library base carries, or a type
  witness), and how promise and generator types name their failure type.
- The name of the sealed type generated for `throws X, Y`, how another
  library's failure joins it, and whether conversion may ever be
  implicit.
- What std's recoverable builtins declare; Float64 division; how
  untrusted data is checked once `as` panics.
- Whether categories are worth keeping, given that only Python and Go can
  show one beside the library base.
- Whether a failure type derives its host message from its fields;
  whether an override may declare less failure (`asInt64Safe`).
- When `orelse` and `??` merge, and when implicit propagation in
  `throws Bubble` ends.
- C++'s default (`std::expected` or exceptions) and C#'s later `Try…`
  forms; which failure changes count as compatible.

## Evidence

All in this folder, drafted by Claude for the team:

- [claude-recommendation.md](claude-recommendation.md): the two questions
  and the recommended answers this proposal states.
- [claude-proposal-declared.md](claude-proposal-declared.md) and
  [details](claude-proposal-declared-details.md); and
  [claude-proposal-values.md](claude-proposal-values.md) and
  [details](claude-proposal-values-details.md): the two sketches.
- [claude-common-ground.md](claude-common-ground.md): decisions both need.
- [claude-syntax-options.md](claude-syntax-options.md): seven syntax
  options on the same six tasks.
- [claude-error-types-survey.md](claude-error-types-survey.md) and
  [claude-translations/](claude-translations/README.md): host languages,
  and the worked example in each.
- [claude-explore/](claude-explore/README.md) and its
  [estimates](claude-explore/estimates/README.md): five library cases,
  benchmarks, counts, and costs on real workloads.
- [claude-findings.md](claude-findings.md): behavior across backends,
  speed, and library patterns.
- [claude-kotlin-result-review.md](claude-kotlin-result-review.md): how
  Kotlin Temper represents failure.
- [claude-meeting-2026-11-17.md](claude-meeting-2026-11-17.md),
  [tom-thoughts.md](tom-thoughts.md), [mike-thoughts.md](mike-thoughts.md),
  and [team-function-naming.md](team-function-naming.md): the team's notes.
