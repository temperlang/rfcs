Proposal sketch: **declared failures**, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17, as one of two competing sketches; the other
is [claude-proposal-values.md](claude-proposal-values.md), and what both
need is in [claude-common-ground.md](claude-common-ground.md). Evidence:
[claude-findings.md](claude-findings.md) and
[claude-explore/](claude-explore/README.md). All syntax marked
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
   declared as a failure: a class, or a sealed interface whose variants
   are classes. No unions, so the type solver and backends see one type
   ([mike-thoughts.md](mike-thoughts.md)).
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
7. **Host connection.** A failure type may carry a meaning category
   (invalid argument, not found, I/O, unsupported, invalid state); each
   backend maps a category to an idiomatic host base class or ignores it
   ([claude-thoughts.md](claude-thoughts.md#connecting-to-existing-host-exception-types)).

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
`Result<Select, SqlProblem>`.

## What each backend generates

| Backend | A failure type becomes | Propagation | Host code |
|---|---|---|---|
| C# | an exception class; variants subclass a generated base, which extends the category's base (`ArgumentException`) or a Temper base | exceptions | `catch (SqlProblem e)`, `e.Message`, `InnerException` |
| Java | an unchecked exception class, same shape (`IllegalArgumentException` for invalid argument) | exceptions | `catch (SqlProblem e)`, `getMessage()`, `getCause()` |
| JS | a class extending `Error` or the category's base (`TypeError`) | exceptions | `instanceof SqlProblem`, `message`, `cause` |
| Python | an exception class (`class SqlProblem(ValueError)`) | exceptions | `except SqlProblem as e`, `str(e)`, `__cause__` |
| C++ | a class deriving from a Temper base over `std::exception`; or `std::expected<T, E>` by configuration | exceptions or values | `catch (SqlProblem const&)`, `what()` |
| Rust | an enum of variants (a struct for one type), implementing `std::error::Error` | `Result<T, E>` and `?`, as today | `match` on `Err(…)` |
| Lua | a table with a `kind` tag field and a shared metatable | `error(t)`; `orelse` checks the tag and re-raises anything else | `pcall`, then `e.kind` |
| Zig (future) | an error set, one code per variant; fields, message, and cause in an optional diagnostics out-parameter | error unions, `try` | `catch`, then the diagnostics |
| C (future) | a status code per variant; an error struct (kind, fields, message, cause) through an out-parameter | return codes | check the status, read and free the struct |

Each of these names is API, and a changed failure type is a compatibility
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
Chromarite's 52. Explicit propagation means adding a marker at every call
that today propagates implicitly; that count isn't measured yet.

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
  throwing without a stack trace (3 times cheaper at depth 20, 10 to 30
  times at depth 1, in Java and JS; no help on .NET 6); and failure
  values inside a library with a throw only at exported functions, which
  pays only when failures cross many frames (about 3 times in Java and C#
  at depth 20, nothing at depth 1).

## Open questions

- The name of the sealed type generated for `throws X, Y`, and how a case
  from another library joins it (wrapped as a variant, or converted).
- Whether propagation may convert implicitly between unrelated failure
  types, or only by explicit `rethrowAs`.
- Whether a failure type can derive its host message from its fields,
  rather than taking a message argument.
- C# and Java have single inheritance: a category base and a common
  Temper base can't both be superclasses (a marker interface could stand
  in for one).
- How long `throws Bubble` may keep implicit propagation, and whether
  that warns.
- How typed failures cross `await` and leave generators on each backend.

## Pros and cons

| Pros | Cons |
|---|---|
| Close to today: `throws`, `orelse`, and `bubble()` keep their meaning | Failures stay exceptions inside Temper on C++, C#, Java, and JS, so failure-heavy loops stay slow unless the compiler lowers them |
| Host code in exception languages gets one idiomatic, typed, catchable exception with a message, and nothing else to learn | Three mechanisms for authors: `T?`, `throws E`, and `panic` |
| No allocation or boxing on the success path | New language surface: failure declarations, generated sealed types, `catch` with coverage, and conversion rules |
| Fields travel with the failure, so Wherewith's twins and std JSON's dropped messages go | Each backend needs its own failure machinery, including across `await` and generators |
| Rust, Zig, and C map it to their native patterns | Accumulated errors (Hrefine's `UrlCheck`, Kelpto's lists) stay values regardless |
| Explicit propagation marks every call that can fail | Every implicitly propagating call needs a marker, an unmeasured migration cost |
