Proposal sketch: **declared failures**, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17, as one of two competing sketches; the other
is [claude-proposal-values.md](claude-proposal-values.md), and what both
need is in [claude-common-ground.md](claude-common-ground.md). Evidence:
[claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), and the
[example translations](claude-translations/README.md). All syntax marked
**HYPOTHETICAL** is invented for comparison and doesn't compile.

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
   be put in a declared failure first (Java and Kotlin can't make a
   generic exception class).
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
   carry a meaning category (invalid argument, not found, I/O,
   unsupported, invalid state) that a backend maps where it can; in Java
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
and the generated API is the same as under
[failures as values](claude-proposal-values.md). Each of these names is API, and a changed failure type is a compatibility
change in every backend.

## Migration from `throws Bubble`

`throws Bubble` stays valid: it's the failure type with no fields, so the
286 declarations (87 public, 199 internal) in the surveyed libraries and
std compile unchanged at first, and host code keeps catching an exception
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
Libraries then move to declared types where they want reasons: about 70
exported members across five libraries, mostly parse and validate entry
points ([findings §3](claude-findings.md#3-real-cases-in-public-libraries)).
Moving builtins to panic removes most of the rest, for example 31 of
Chromarite's 52.

Explicit propagation, which Tom's and Mike's notes both lean toward,
needs a marker at the [630 calls](claude-common-ground.md#propagation-markers)
that propagate implicitly today; 68 of Wherewith's become `throw`s.

## Cost

- **Success path:** free on every backend but Lua, where each `orelse`
  builds a closure and `pcall` (5 to 10 percent)
  ([findings §2](claude-findings.md#2-speed)).
- **Each failure:** an exception where it is one today: about 2 µs in C++,
  15 to 19 µs in C#, 0.8 µs in Java, 3 µs in JS, and 0.3 µs in Lua and
  Python; nothing in Rust. At 1 percent failures, C#, Java, and JS loops
  take about twice as long as a nullable version, and at 10 percent 11 to
  107 times on C++, C#, Java, and JS
  ([bench](claude-explore/bench/README.md)). Building a message adds to
  this: Java's `toInt32`, which formats one, costs about twice a bare
  bubble.
- **Mitigations:** lowering a `throw` and its handler in one function to a
  branch ([common ground](claude-common-ground.md#lowering-a-local-failure-to-a-branch));
  throwing without a stack trace (Java's `writableStackTrace=false`, a
  plain object in JS), at 0.1 to 0.5 times today's bubbling cost (no help
  on .NET 6); and failure values inside a library with a throw only at
  exported functions, where a compiler-known result costs about what a
  nullable does ([hand-written forms](claude-explore/README.md#a-compiler-known-result-type-likely-cost)).

## Open questions

- The name of the sealed type generated for `throws X, Y`, and how a case
  from another library joins it (wrapped as a variant, or converted).
- Whether propagation may convert implicitly between unrelated failure
  types, or only by explicit `rethrowAs`.
- Whether a failure type can derive its host message from its fields,
  rather than taking a message argument.
- Whether categories are worth keeping, given that only Python and Go
  can show one beside the library base
  ([common ground](claude-common-ground.md#host-facing-failure-types)).
- How long `throws Bubble` may keep implicit propagation, and whether
  that warns.
- How typed failures cross `await` and leave generators on each backend.

## Pros and cons

| Pros | Cons |
|---|---|
| Close to today: `throws`, `orelse`, and `bubble()` keep their meaning | Failures stay exceptions inside Temper on C++, C#, Java, and JS, so failure-heavy loops stay slow unless the compiler lowers them (trace-free throws narrow this on Java and JS, not C#) |
| Host code in exception languages gets one idiomatic, typed, catchable exception with a message, and nothing else to learn | Three mechanisms for authors: `T?`, `throws E`, and `panic` |
| No allocation or boxing on the success path | New language surface: failure declarations, generated sealed types, `catch` with coverage, and conversion rules |
| Fields travel with the failure, so Wherewith's twins and std JSON's dropped messages go | Each backend needs its own failure machinery, including across `await` and generators |
| Rust, Go, Zig, and C map it to their native patterns | Those four implement it as values anyway, so it needs both machineries; accumulated errors (Hrefine's `UrlCheck`, Kelpto's lists) stay values too |
| Explicit propagation marks every call that can fail | Every implicitly propagating call needs a marker: about 630 in the surveyed code |
