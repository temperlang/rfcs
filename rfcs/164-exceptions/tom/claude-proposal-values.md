Proposal sketch: **failures as values**, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17, as one of two competing sketches; the other
is [claude-proposal-declared.md](claude-proposal-declared.md), and what
both need is in [claude-common-ground.md](claude-common-ground.md).
Evidence: [claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), and the
[example translations](claude-translations/README.md). All syntax marked
**HYPOTHETICAL** is invented for comparison and doesn't compile.

## Summary

Inside Temper, failure is an ordinary return value: `T?` for absence, a
minimal core result type for failure with a reason, and `panic` for bugs.
`return`, `break`, and `continue` become expressions, so `?? return null`
propagates in one line; a propagation operator may come later.
`throws Bubble` stays as the no-detail case. Temper callers always use
the value form; host callers in exception languages also get a generated
throwing form, named by each language's idiom.

## Semantics

1. **Absence:** `T?`, as today.
2. **Failure with a reason:** a core generic type, written here
   `Result<T, E>` with `Ok(value)` and `Failed(error)` (names open). `E`
   is any type, typically a class with readable fields or a sealed
   interface of variants. Core holds only the type and what the compiler
   must know; mapping, combining, and collecting failures live in std
   ([claude-thoughts.md](claude-thoughts.md#core-or-std)). Since `E` can
   be any type, an exported function's throwing form can't throw `E`
   itself: it throws a generated library exception holding it
   (`SqlProblemException`, with a `problem` field), or the library base
   with `E`'s text for a `String`. In Rust a foreign `E` can't implement
   `std::error::Error` (the orphan rule) and needs a newtype, and in Go a
   type with `Error()`. Restricting exported failures to classes declared
   as failures would remove the wrapper (an open question).
3. **Handling:** `r orelse x` gives the success value or `x`;
   `r orelse (e) …` binds the failure. `??` does the same for `T?`.
4. **Propagation:** `return`, `break`, and `continue` are expressions of
   type `Never`, so `f() ?? return null` and
   `f() orelse (e) return Failed(e)` propagate. A postfix operator meaning
   "return the failure, else unwrap" may follow once the spelling is
   settled ([common ground](claude-common-ground.md#precedence)).
5. **`throws Bubble`** keeps today's meaning and syntax: a failure with no
   detail. It's a value inside Temper on every backend, as it already is
   in Rust, so `orelse` compiles to a branch.
6. **Bugs:** `panic`, never caught by Temper code.
7. **At exported functions,** Temper callers in other libraries call the
   value form directly; nothing is thrown between Temper libraries. For
   host callers, each backend generates its idiomatic form (table below),
   with the library's names and base type, and in Java unchecked unless
   the library opts into checked
   ([common ground](claude-common-ground.md#host-facing-failure-types)).
   A host callback (a host implementation of a Temper interface) returns
   values too; a host exception thrown there is a panic.

## Worked example: Wherewith's parser rule

The `select` rule of the recursive-descent parser in
[claude-explore/wherewith-problems](claude-explore/wherewith-problems/README.md).
Today it bubbles, and stores its message in a field because the bubble
drops it; a `selectProblem` twin re-parses to read it. Written as runnable
code today, with a user-defined result type and no propagation, the rule
grows from 13 lines to 31.

```temper
// HYPOTHETICAL: core Result with inferred type arguments, `return` as an
// expression, `orelse (e)` binding a failure.
export class SqlProblem(public text: String, public word: Int) {}

public select(): Result<Select, SqlProblem> {
  keyword("SELECT") orelse (e) return Failed(e);
  let columns = new ListBuilder<String>();
  columns.add(name("a column") orelse (e) return Failed(e));
  while (peek() == ",") {
    pos += 1;
    columns.add(name("a column") orelse (e) return Failed(e));
  }
  keyword("FROM") orelse (e) return Failed(e);
  let table = name("a table") orelse (e) return Failed(e);
  if (peek() != null) { return problem("expected the end"); }
  Ok(new Select(columns.toList(), table))
}

private need(message: String): Result<String, SqlProblem> {
  Ok(peek() ?? return problem(message))
}

private problem<T>(text: String): Failed<T, SqlProblem> {
  Failed(new SqlProblem(text, pos + 1))
}

// With a later propagation operator (HYPOTHETICAL, spelling open):
//   keyword("SELECT")!;   columns.add(name("a column")!);
```

Today's shape and about its line count, with a longer marker per call
until an operator exists. The `problem` field, `report`, and the
`selectProblem` twin go. `keyword` returns `Result<Void, SqlProblem>`,
which needs a unit `Ok()`. Python host code calls the throwing
`parse_select`, which raises a `SqlProblemError` holding the
`SqlProblem`, or the hidden value form; Rust gets
`Result<Select, SqlProblem>`; each backend's code is in the
[translations](claude-translations/README.md).

## What each backend generates

For an exported function returning `Result<T, E>`. Functions returning
`T?` mean absence and stay `null`, `None`, or `nil` in every host, with
no throwing form.

| Backend | Value form (Temper callers, and hosts that want it) | Host-facing form |
|---|---|---|
| C# | `TryParseSelect(text, out Select? select, out SqlProblem? problem)`, a `readonly struct` inside | `ParseSelect(text)` throws `SqlProblemException`; both public, as .NET's `Parse` and `TryParse` |
| Java | a result object, in an `internal` package | `parseSelect(text)` throws `SqlProblemException` (unchecked by default) |
| JS | the value or a `Failed`, from the internal module | `parseSelect(text)` throws `SqlProblemError` |
| Python | the value or a `Failed`, in a `_temper` submodule | `parse_select(text)` raises `SqlProblemError` |
| C++ | `std::expected<T, E>` (C++23) or a core result struct | open: the value form only (`.value()` throws `std::bad_expected_access`), or a throwing form by configuration |
| Rust | `Result<T, E>`; `T?` is `Option<T>` | the same |
| Go | `(T, error)`, `E` implementing `error`; `T?` as a pointer or `(T, bool)` | the same; `errors.As` to match |
| Lua | `nil, failure` (Lua's own multiple-return idiom) | the same; `assert(f(…))` raises |
| Zig (future) | an error union, details in an optional diagnostics out-parameter | the same |
| C (future) | a status code, the value through an out-pointer, an error struct | the same |

The generated names and which form gets the plain name are API, so
they're recorded in `temper.keep`'s compatibility tracking; a library can
override the default per function (for example, to keep a hot exported
function exception-free). The throwing form is a few lines that call the
value form ([claude-thoughts.md](claude-thoughts.md#value-and-exception-forms-at-exported-functions)).

## Migration from `throws Bubble`

Nothing has to move: all 286 `throws Bubble` declarations (87 public, 199
internal) keep compiling, and the 87 public ones keep throwing for host
code through generated throwing forms. Where a library wants absence or
reasons instead, the rewrite to `T?` is mechanical for 155 declarations
(54 percent), mechanical for 50 more given one convention for `Void`
(17 percent), and needs a human decision for 81 (28 percent), such as
bug-like bubbles that should panic and interfaces hosts implement
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
With `return` as an expression, each rewrite stays local
(`f() ?? return null`) instead of hoisting calls into statements.

Each call that propagates implicitly today needs an explicit marker once
its callee moves to `T?` or a result: a propagation operator, or, until
one exists, `?? return null` or `orelse (e) return Failed(e)`, at the
[630 sites](claude-common-ground.md#propagation-markers) counted; 68 of
Wherewith's become `return`s of the problem.

## Cost

From [claude-explore](claude-explore/README.md#measurements) and
[findings §2](claude-findings.md#2-speed):

- **Nullables** cost about what today's success path costs, and nothing
  per failure, except through five calls when failures are rare (below
  0.1 to 1 percent): a JVM `Int?` (a boxed `Integer`) takes 3.5 to 4
  times as long as bubbling, and a .NET 6 `int?` 50 to 110 ns against 9
  to 22.
- **A result type the compiler knows** costs about what a nullable does,
  and about nothing per failure, in hand-written forms of what each
  backend could emit
  ([compiler-known result](claude-explore/README.md#a-compiler-known-result-type-likely-cost)):
  about a nullable on C++ and Rust; on C#, a `readonly struct` is
  cheaper than `int?` and 0.03 to 0.05 times today's bubbling at 1
  percent failures; on Java about a nullable, up to 2.6 times at depth 5
  with inlining limited; on JS, Python, and Lua 0.5 to 1.6 times.
- **Written as user code today,** a result type allocates per call: 1.0
  to 1.6 times a nullable on the JVM, JS, and Python, and 40 to 140 times
  on C++ and Rust, measuring today's translation of user types, not a
  core type.
- **Against today's exceptions:** bubbling costs 2 to 13 times at 1
  percent failures and 11 to 107 times at 10 percent on C++, C#, Java, and
  JS, which values avoid inside Temper. Most of that is the stack trace on
  Java and JS: thrown without one, it's 0.1 to 0.5 times today's. A host
  caller of a throwing form pays one shallow throw per failure.
- **Still unmeasured:** generated code, larger failure values copied by
  value in C++, C#, and Rust, and generated throwing forms.

## Open questions

- Names and location: `Result`, `Ok`, `Failed`; what core holds and what
  std holds.
- A unit success for `Result<Void, E>`, and `Result<T?, E>` in backends
  without nested optionals (Java, C#).
- Whether `orelse` and `??` merge into one default operator.
- Whether, and when, `throws Bubble` is deprecated in favor of `T?`.
- Constructors that fail (std's `Date`) become factories, which changes
  host code's `new Date(…)`.
- What the throwing form raises: a generated wrapper holding `E` (two
  host names per failure), or, when `E` is a class only used as a
  failure, `E` itself generated as an exception subclass (one name, but
  the JVM and V8 capture a stack trace at construction unless the
  generated code avoids it; .NET and Python capture it when thrown); and
  where its host message comes from (`E`'s `toString()`, or Mike's
  optional message).
- The default host form per backend for C++, and whether a library opts
  into throwing forms or out of them.

## Pros and cons

| Pros | Cons |
|---|---|
| One mechanism inside Temper (return values), the same on every backend | Two forms per exported function, with names to choose, document, and keep compatible |
| No exceptions between Temper functions, so failure-heavy loops stay cheap on C++, C#, Java, and JS | `Int?` on the JVM and `int?` on .NET 6 cost more than today when failures are rare, unless the compiler avoids them (a `long` sentinel, a struct) |
| `await`, generators, and what `orelse` catches need no special failure machinery | Cheap only once the compiler knows the result type; as user code today it allocates per call |
| Libraries' existing result values (Argmas's `ParseResult`, Hrefine's `UrlCheck`) become the normal style | Every fallible call needs a marker (about 630 in the surveyed code), and without an operator it's `orelse (e) return Failed(e)` |
| Rust, Go, Zig, C, and Lua get their native idioms directly | Host callbacks in Java, Python, and C# must return result values, which is unusual there |
| Any type can be a failure | In exception languages the throwing form wraps it, so host code sees two names (`SqlProblemException` holding `SqlProblem`) |
| `throws Bubble` code keeps working, and moves only where a library wants to | Two default operators (`??`, `orelse`) and two failure styles until `throws Bubble` is retired |
