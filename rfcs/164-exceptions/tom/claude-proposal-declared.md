Proposal sketch: **declared failures**, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17, as one of two competing sketches; the other
is [claude-proposal-values.md](claude-proposal-values.md), and what both
need is in [claude-common-ground.md](claude-common-ground.md). Evidence:
[claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), and the
[example translations](claude-translations/README.md); longer detail is
in [claude-proposal-declared-details.md](claude-proposal-declared-details.md).
All syntax marked **HYPOTHETICAL** is invented for comparison and doesn't
compile.

**How this maps to the RFC's
[two questions](claude-recommendation.md#two-questions).** On
**semantics**, this sketch's answer is that results are in flight only.
A failure object is an ordinary value once caught, but the result, the
success-or-failure union, exists only between `throw` and the handler
that catches it; Temper code can't hold, store, or return one. Typed as
`Result<T, E>`, as Kotlin types it internally, a fallible function given
to `map<T, R>(xs, f: fn (T): R)` instantiates `R` as `Result<U, E>`.
In flight only, that is safe only where generic code uses `R` linearly,
returning or propagating it at once; checking that is a hidden effect
system, which is where Kotlin's special cases come from
([review §4](claude-kotlin-result-review.md#4-toms-question-did-mike-deliberately-keep-results-out-of-temper-code)).
The [refinement](#refinement-generic-failure-parameters) below replaces
that check with an ordinary generic failure parameter: the middle
ground, which Tom chose on 2026-11-18 and
[claude-proposal.md](claude-proposal.md) drafts. On
**syntax**, it shows the most exception-looking sugar: `throws`, `throw`,
a propagation marker, `catch`, and `error case`.
**Representation** is still each backend's choice: Rust, Go, Zig, and C
implement it as values (below).

## Summary

Mike's semantics with Tom's surface. A function declares at most one
failure type, usually a sealed interface of variants with readable fields.
Tom's `error case X` declarations and `throws X, Y` are sugar that builds
that sealed type. Failures carry an optional message and cause for host
code, opaque to Temper. Propagation is explicit at each call. Only failures
declared in Temper are visible to Temper; host exceptions are panics. Each
backend presents failures in its own idiom: exception classes, `Result`,
error codes, or tagged tables.

## Semantics

1. **One failure type per function.** `throws E`, where `E` is a type
   declared as a failure: a non-generic class, or a sealed interface
   whose variants are such classes. No unions, so the type solver and
   backends see one type ([mike-thoughts.md](mike-thoughts.md)). Only
   declared failure types can be thrown, so each maps directly to one
   host exception class or error variant, and host code catches the
   library's own type with no wrapper; a `String` or a generic type must
   be put in a declared failure first.
2. **Sugar from #164.** `error case NotFound;` declares a failure class
   with no fields; `error case BadWord(public text: String);` one with
   fields. `throws X, Y` stands for a generated sealed interface with `X`
   and `Y` as its variants ([tom-thoughts.md](tom-thoughts.md)).
3. **Message and cause.** Every failure type's factory also takes an
   optional message and an optional cause (another failure), and doesn't
   fail itself. Temper code can pass them on but not read them; backends
   use them for host messages and chained causes. Fields the library
   declares are ordinary, readable fields.
4. **Raising and propagating.** `throw e` raises; `bubble()` stays as
   raising `Bubble`, the failure type with no fields. A call that can
   fail must be marked to propagate (spelled `f()!` below; the spelling
   is open, see [common ground](claude-common-ground.md#precedence)).
   Propagation passes a failure through when its type is the caller's
   type or one of its variants; anything else needs an explicit
   conversion, with the original as cause (Mike's `rethrowAs`).
5. **Handling.** `f() orelse x` handles any declared failure of `f()`;
   `catch (e) { … }` binds it, and `when (e)` over a sealed type checks
   that every variant is covered.
6. **What Temper sees.** Only failures declared in Temper. A host
   exception reaching Temper code (from a connected function or a host
   callback) is a panic, never caught by `orelse`.
7. **Host connection.** Each failure type keeps the library's name and
   extends a generated library base (`WherewithException`), and may
   carry a meaning category (such as invalid argument or not found)
   that a backend maps where it can; in Java
   failures are unchecked unless the library opts into checked ones
   ([common ground](claude-common-ground.md#host-facing-failure-types)).

## Worked example: Wherewith's parser rule

The `select` rule of the recursive-descent parser in
[claude-explore/wherewith-problems](claude-explore/wherewith-problems/README.md).
Today it bubbles, and stores its message in a field because the bubble
drops it; a `selectProblem` twin re-parses to read it.

```temper
// HYPOTHETICAL: `error case` with fields, `throws`, `throw`, postfix `!`,
// `catch`, and the factory's trailing optional message.
export error case SqlProblem(public text: String, public word: Int);

public select(): Select throws SqlProblem {
  keyword("SELECT")!;
  let columns = new ListBuilder<String>();
  columns.add(name("a column")!);
  while (peek() == ",") { pos += 1; columns.add(name("a column")!); }
  keyword("FROM")!;
  let table = name("a table")!;
  if (peek() != null) { throw problem("expected the end"); }
  new Select(columns.toList(), table)
}

private need(message: String): String throws SqlProblem {
  let w = peek();
  if (w == null) { throw problem(message); }
  w
}

private problem(text: String): SqlProblem {
  let word = pos + 1;
  new SqlProblem(text, word, "${text} at word ${word.toString()}") // message for hosts
}

// A Temper caller reading the fields:
let s = parseSelect(sql) catch (e) { log("${e.text}, word ${e.word.toString()}"); null };
```

Same 13-line shape as today, one marker per fallible call. The `problem`
field, `report`, and the `selectProblem` twin go. Python host code
catches `SqlProblem` with the message as text; Rust gets
`Result<Select, SqlProblem>`; each backend's code is in the
[translations](claude-translations/README.md).

## What each backend generates

| Backend | A failure type becomes | Propagation | Host code |
|---|---|---|---|
| C# | an exception class extending the library's `WherewithException : Exception` | exceptions | `catch (SqlProblem e)`, `e.Message`, `InnerException` |
| Java | the same, unchecked (`WherewithException extends RuntimeException`), or checked by a library setting | exceptions | `catch (SqlProblem e)`, `getMessage()`, `getCause()` |
| JS | a class extending `WherewithError extends Error` | exceptions | `instanceof SqlProblem`, `message`, `cause` |
| Python | an exception class with the category too: `class SqlProblem(WherewithError, ValueError)` | exceptions | `except SqlProblem as e`, `str(e)`, `__cause__` |
| C++ | a class deriving from `WherewithError : std::runtime_error`; or `std::expected<T, E>` by configuration | exceptions or values | `catch (SqlProblem const&)`, `what()` |
| Rust | an enum of variants (a struct for one type), implementing `std::error::Error`, convertible into a crate `wherewith::Error` | `Result<T, E>` and `?`, as today | `match` on `Err(…)` |
| Go | a struct implementing `error` and the library's `wherewith.Error` interface | `(T, error)` returns, as values | `errors.As(err, &problem)` |
| Lua | a table with a `kind` tag field and a shared metatable | `error(t)`; `orelse` checks the tag and re-raises anything else | `pcall`, then `e.kind` |
| Zig (future) | an error set, one code per variant; fields, message, and cause in an optional diagnostics out-parameter | error unions, `try` | `catch`, then the diagnostics |
| C (future) | a status code per variant; an error struct (kind, fields, message, cause) through an out-parameter | return codes | check the status, read and free the struct |

In Rust, Go, Zig, and C, declared failures are implemented as values,
with the same generated API as under
[failures as values](claude-proposal-values.md). Each of these names is
API, so a changed failure type is a compatibility change everywhere.

<a id="refinement-pass-through-and-capture"></a>

## Refinement: generic failure parameters

A middle ground between this sketch and
[first-class results](claude-proposal-values.md), and the third answer to
the [semantics question](claude-recommendation.md#two-questions).
Failure objects stay ordinary values throughout: a caught `SqlProblem`
with its fields, message, and cause can be bound, stored, passed, put in
lists, compared by its fields, and thrown again. What can't be held is
the result, the success-or-failure union. Inside the compiler,
`T throws E` is an ordinary generic `Result<T, E>`, so generic machinery
handles it uniformly, but Temper source can't name or hold one.

**Failure parameters.** A higher-order function is generic over its
callback's failure type, as with Swift 6's typed `throws(E)`, instead of
a special `rethrows` keyword. `E` is bounded by a root interface every
declared failure type extends (`Error`), and a function type
without `throws` means `throws Never<Error>`, a failure that can't
happen. Inference fills `E` at each call: a callback that can't fail
needs no `try` and propagates nothing. The body can only propagate or
handle the callback's failure, never hold it as a result. One rule
covers `map`, `forEach`, `filter`, and `sort`'s comparator.

**No capture in the first version.** Code that needs to keep an outcome
stores the failure object, and promises already hold async failures. An
earlier draft had `capture { … }` turning a failure into a held
`Result<T, E>`; it could be added later if real code shows the need.

```temper
// HYPOTHETICAL: failure parameter `E`, bounded by `Error`.
public map<T, R, E>(xs: List<T>, f: fn (T): R throws E): List<R> throws E {
  let out = new ListBuilder<R>();
  for (let x of xs) { out.add(f(x)!); }
  out.toList()
}

let doubled = map(xs, fn (x: Int): Int { x * 2 });   // E = Never<Error>: no marker
let ids = map(texts, fn (t: String): Int throws SqlProblem { parseId(t)! })!;
var problem: SqlProblem? = null;                      // keep the outcome
let node = parse(s) catch (e) { problem = e; null };
```

Exception-style syntax then tells the truth: no value is ever a result.
Kotlin's complexity came from having no failure polymorphism at all, not
from in-flight results as such. On exception backends, failure
parameters need nothing, since the failure propagates through the
generic function; value backends make `E` a generic error parameter
([details](claude-proposal-declared-details.md#generic-failure-parameters)).

## Migration from `throws Bubble`

`throws Bubble` stays valid as the failure type with no fields, so all
286 declarations compile unchanged at first; libraries move to declared
types where they want reasons (about 70 exported members), and explicit
propagation needs a marker at the
[630 calls](claude-common-ground.md#propagation-markers) that propagate
implicitly today ([details](claude-proposal-declared-details.md#migration-in-detail)).

## Cost

The success path is free on every backend but Lua (a closure and `pcall`
per `orelse`). Each failure costs an exception where it is one today, so
failure-heavy loops on C++, C#, Java, and JS take 2 to 107 times as long
as a nullable version; lowering local failures to branches, trace-free
throws, and value representations narrow that. On real libraries, valid input costs
about nothing, and one failure in an invalid Wherewith query adds an
estimated 15 to 300% to it on C++, C#, and Java
([details](claude-proposal-declared-details.md#cost-in-detail)).

## Open questions

- Naming the sealed type for `throws X, Y`, conversion between failure
  types, host messages, and categories
  ([details](claude-proposal-declared-details.md#other-open-questions)).
- How long `throws Bubble` may keep implicit propagation, and whether
  that warns.
- Whether to adopt the refinement (Tom chose it), and its open points
  ([details](claude-proposal-declared-details.md#generic-failure-parameters));
  whether an override may declare less failure (std's `asInt64Safe` twin).

## Pros and cons

| Pros | Cons |
|---|---|
| Close to today: `throws`, `orelse`, and `bubble()` keep their meaning | Failures stay exceptions inside Temper on C++, C#, Java, and JS, so failure-heavy loops stay slow unless the compiler lowers them (trace-free throws narrow this on Java and JS, not C#) |
| Host code in exception languages gets one idiomatic, typed, catchable exception with a message, and nothing else to learn | Three mechanisms for authors: `T?`, `throws E`, and `panic` |
| No allocation or boxing on the success path | New language surface: failure declarations, generated sealed types, `catch` with coverage, and conversion rules |
| Fields travel with the failure, so Wherewith's twins and std JSON's dropped messages go | Each backend needs its own failure machinery, including across `await` and generators |
| Rust, Go, Zig, and C map it to their native patterns | Those four implement it as values anyway, so it needs both machineries; accumulated errors (Hrefine's `UrlCheck`, Kelpto's lists) stay values too |
| Explicit propagation marks every call that can fail | Every implicitly propagating call needs a marker: about 630 in the surveyed code |
| With the refinement, generic helpers pass failures through with an ordinary generic failure parameter | Without it, generics, function types, `await`, and generators need special cases, as in Kotlin today; with it, one more rule to learn (failure parameters bounded by the root) |
