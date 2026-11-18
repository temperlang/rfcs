Proposal sketch: **failures as values**, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17, as one of two sketches; the other is
[claude-proposal-declared.md](claude-proposal-declared.md), and what both
need is in [claude-common-ground.md](claude-common-ground.md). Evidence:
[claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), the
[example translations](claude-translations/README.md), and the
[Kotlin `Result` review](claude-kotlin-result-review.md); longer detail is
in [claude-proposal-values-details.md](claude-proposal-values-details.md).
All syntax marked **HYPOTHETICAL** is invented for comparison and doesn't
compile.

**How this maps to the RFC's
[two questions](claude-recommendation.md#two-questions).** On
**semantics**, this sketch's answer is first-class results: a result type
(the success-or-failure union) that Temper code can hold, store, return,
collect, and map. Failure objects are ordinary values under every answer;
what this sketch adds is holding the union. Typing a fallible call as
returning `Result<T, E>`, as Kotlin already does internally, lets failure
polymorphism fall out of ordinary generics: `map<T, R>(xs, f: fn (T): R)`
given a fallible `f` instantiates `R` as `Result<U, E>`, and `map` may
collect its `R`s into a `List<R>`, unchanged. The middle ground, which
[the proposal](claude-proposal.md) adopts, keeps results in flight and
makes a higher-order function generic over its callback's failure type
(`fn (T): R throws E`); code that needs to keep an outcome stores the
failure object, and capture is deferred
([declared sketch](claude-proposal-declared.md#refinement-generic-failure-parameters)).
On **syntax**, it
shows the least sugar (`orelse`, `??`, and `return` as an expression, with
a propagation operator later); exception-looking sugar such as `T throws E`
for returning a result, or the declared sketch's `error case`, can sit on
top without changing the semantics. **Representation** is each backend's
choice ([below](#semantics-and-representation-are-separate-choices)).
Kotlin Temper already uses `Result` as its internal model of failure, but
keeps it second-class ([review](claude-kotlin-result-review.md)).

## Summary

Inside Temper, failure is an ordinary return value: `T?` for absence, a
minimal core result type for failure with a reason, and `panic` for bugs.
`return`, `break`, and `continue` become expressions, so `?? return null`
propagates in one line. `throws Bubble` stays as the no-detail case.
Temper callers always use the value form; host callers in exception
languages also get a generated throwing form, named by each language's
idiom.

## Semantics

1. **Absence:** `T?`, as today.
2. **Failure with a reason:** a core generic type, written here
   `Result<T, E>` with `Ok(value)` and `Failed(error)` (names open). `E`
   is any type, typically a class with readable fields or a sealed
   interface of variants. Core holds only the type and what the compiler
   must know; mapping, combining, and collecting live in std
   ([claude-thoughts.md](claude-thoughts.md#core-or-std)). An exported
   `E` that isn't a declared failure class needs a wrapper in some hosts
   ([details](claude-proposal-values-details.md#any-type-as-a-failure)).
3. **Handling:** `r orelse x` gives the success value or `x`;
   `r orelse (e) …` binds the failure. `??` does the same for `T?`.
4. **Propagation:** `return`, `break`, and `continue` are expressions of
   type `Never`, so `f() ?? return null` and
   `f() orelse (e) return Failed(e)` propagate. A postfix operator may
   follow once the spelling is settled
   ([common ground](claude-common-ground.md#precedence)).
5. **`throws Bubble`** keeps today's meaning and syntax: a failure with no
   detail, a value inside Temper on every backend, as it already is in
   Rust.
6. **Bugs:** `panic`, never caught by Temper code.
7. **At exported functions,** Temper callers in other libraries call the
   value form; nothing is thrown between Temper libraries. For host
   callers, each backend generates its idiomatic form (below), with the
   library's names and base type
   ([common ground](claude-common-ground.md#host-facing-failure-types)).
   A host callback returns values too; a host exception thrown there is
   a panic.

## Worked example: Wherewith's parser rule

The `select` rule of the recursive-descent parser in
[claude-explore/wherewith-problems](claude-explore/wherewith-problems/README.md).
Today it bubbles, and stores its message in a field because the bubble
drops it; a `selectProblem` twin re-parses to read it.

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
`selectProblem` twin go. Each backend's code is in the
[translations](claude-translations/README.md).

## What each backend generates

For an exported function returning `Result<T, E>`. Functions returning
`T?` stay `null`, `None`, or `nil` in every host, with no throwing form.

| Backend | Value form (Temper callers, and hosts that want it) | Host-facing form |
|---|---|---|
| C# | a hidden value form for Temper callers (exceptions internally in a first pass; a `readonly struct` result later if measurements warrant) | `ParseSelect(text)` throws `SqlProblemException`; a `TryParseSelect` twin only later, where failure is a common outcome |
| Java | a result object, in an `internal` package | `parseSelect(text)` throws `SqlProblemException` (unchecked by default) |
| JS | the value or a `Failed`, from the internal module | `parseSelect(text)` throws `SqlProblemError` |
| Python | the value or a `Failed`, in a `_temper` submodule | `parse_select(text)` raises `SqlProblemError` |
| C++ | `std::expected<T, E>` (C++23) or a core result struct | open: the value form only, or a throwing form by configuration |
| Rust | `Result<T, E>`; `T?` is `Option<T>` | the same |
| Go | `(T, error)`, `E` implementing `error`; `T?` as a pointer or `(T, bool)` | the same; `errors.As` to match |
| Lua | `nil, failure` (Lua's own multiple-return idiom) | the same; `assert(f(…))` raises |
| Zig (future) | an error union, details in an optional diagnostics out-parameter | the same |
| C (future) | a status code, the value through an out-pointer, an error struct | the same |

Generated names, and which form gets the plain name, are API recorded in
`temper.keep`; a library can override the default per function. The
throwing form is a few lines over the value form
([claude-thoughts.md](claude-thoughts.md#value-and-exception-forms-at-exported-functions)).

### Semantics and representation are separate choices

Results are first-class values in Temper's semantics; each backend picks the
representation that is readable and cheapest there, with identical
behavior. On the JVM that can be lightweight exceptions internally, with
real return types and the same exception classes the public API shows;
stack traces are captured only where the compiler sees a failure may
reach an exported function unhandled. Where Temper code holds a result,
the JVM materializes `Ok(value)` or `Failed(failure)` around the same
failure object, rethrown as that object if later propagated. C# can keep
exceptions in a first pass (real libraries rarely fail on valid input, so
it matters only for failure-heavy uses) and move to value types later; C++
can use value types, dynamic languages plain values, and Go, C, and Zig
their error values and status codes
([details](claude-proposal-values-details.md#representation-on-each-backend)).

## Migration from `throws Bubble`

Nothing has to move: all 286 `throws Bubble` declarations keep compiling,
and the 87 public ones keep throwing for host code through generated
throwing forms. Where a library wants absence or reasons instead, about
70 percent of rewrites to `T?` are mechanical
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)),
and each implicitly propagating call needs a marker, at
[630 sites](claude-common-ground.md#propagation-markers)
([details](claude-proposal-values-details.md#migration-in-detail)).

## Cost

- **A compiler-known result type** costs about what a nullable does on
  every backend, and about nothing per failure, in hand-written forms of
  what each backend could emit
  ([measured](claude-explore/README.md#a-compiler-known-result-type-likely-cost)).
  Written as user classes, as today's translation makes them, it
  allocates per call (40 to 140 times a nullable on C++ and Rust), so it
  must be built in.
- **Against today's exceptions:** bubbling costs 2 to 13 times at 1
  percent failures and 11 to 107 times at 10 percent on C++, C#, Java,
  and JS ([measurements](claude-explore/README.md#measurements)); values
  avoid that inside Temper.
- **On real libraries** ([estimates](claude-explore/estimates/README.md)):
  0 to 1% on valid Wherewith queries on most backends (up to 3% on
  Python), and about nothing on invalid ones.

Full numbers, including nullables on the JVM and .NET 6, are in the
[details](claude-proposal-values-details.md#cost-in-detail).

## Open questions

- Names and location of `Result`, `Ok`, and `Failed`; a unit success for
  `Result<Void, E>`; `Result<T?, E>` in Java and C#.
- Whether `orelse` and `??` merge, and whether and when `throws Bubble`
  is deprecated.
- Whether std offers a short-circuiting `map` (a `List<U>` or the first
  failure) beside the plain one that collects results.
- What the throwing form raises (a wrapper holding `E`, or `E` generated
  as an exception class), and where its host message comes from.
- C++'s default host form; failing constructors becoming factories
  ([more](claude-proposal-values-details.md#open-questions-in-detail)).

## Pros and cons

| Pros | Cons |
|---|---|
| One mechanism inside Temper (return values), the same on every backend | Two forms per exported function, with names to choose, document, and keep compatible |
| No exceptions between Temper functions, so failure-heavy loops stay cheap on C++, C#, Java, and JS | `Int?` on the JVM and `int?` on .NET 6 cost more than today when failures are rare, unless the compiler avoids them |
| Generics, function types, `await`, generators, and what `orelse` catches need no special failure machinery | Cheap only once the compiler knows the result type; as user code today it allocates per call |
| Libraries' existing result values (Argmas's `ParseResult`, Hrefine's `UrlCheck`) become the normal style | Every fallible call needs a marker (about 630 in the surveyed code), and without an operator it's `orelse (e) return Failed(e)` |
| Rust, Go, Zig, C, and Lua get their native idioms directly | Host callbacks in Java, Python, and C# must return result values, which is unusual there |
| Any type can be a failure | In exception languages the throwing form may wrap it, so host code sees two names |
| `throws Bubble` code keeps working, and moves only where a library wants to | Two default operators (`??`, `orelse`) and two failure styles until `throws Bubble` is retired |
