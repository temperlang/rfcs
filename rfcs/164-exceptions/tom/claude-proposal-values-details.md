Detail moved out of the **failures as values** sketch
([claude-proposal-values.md](claude-proposal-values.md)) to keep it short,
for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17. Syntax marked **HYPOTHETICAL** doesn't
compile today.

## Any type as a failure

`E` in `Result<T, E>` can be any type, typically a class with readable
fields or a sealed interface of variants. Since `E` can be any type, an
exported function's throwing form can't throw `E` itself: it throws a
generated library exception holding it (`SqlProblemException`, with a
`problem` field), or the library base with `E`'s text for a `String`. In
Rust a foreign `E` can't implement `std::error::Error` (the orphan rule)
and needs a newtype, and in Go a type with `Error()`. Restricting exported
failures to classes declared as failures would remove the wrapper (an
open question).

The worked example's `keyword` returns `Result<Void, SqlProblem>`, which
needs a unit `Ok()`. Python host code calls the throwing `parse_select`,
which raises a `SqlProblemError` holding the `SqlProblem`, or the hidden
value form. Written as runnable code today, with a user-defined result
type and no propagation, the rule grows from 13 lines to 31.

## Representation on each backend

Results are first-class values in Temper's semantics; each backend still picks the
representation that is readable and cheapest there, with identical
behavior. On the JVM, the clearest choice is lightweight exceptions
internally: methods keep their real return types (`SqlNode`, not
`Object` or a wrapper), declare `throws SqlProblem` accurately (checked
or unchecked by the library's setting; generated fun interfaces declare
`throws E`), and each explicit propagation becomes a throw caught exactly
where the Temper code handles the failure. The exception classes are the
same ones the public API presents, so an escaping failure is exactly the
object host code expects. Because propagation is explicit, the compiler
can tell for each place a failure is created whether it may reach an
exported function unhandled: if so, it's constructed with a stack trace
from its origin; if every path handles it, without one
(`writableStackTrace = false`). Success costs nothing, and the estimates
show real libraries rarely fail.

Where Temper code holds a result (stores it, passes it to generic code,
or returns it without checking), the JVM materializes `Ok(value)` (one
allocation, often removed by escape analysis) or `Failed(failure)`
wrapping the same failure object, with no copy; if that result is later
propagated, the same object is thrown again. Kotlin Temper's exception
lowering already covers every result checked at its call
([review](claude-kotlin-result-review.md#5-relation-to-the-proposals));
holding is the addition.

Elsewhere: C# carries the exception object unthrown in a value-type
result and throws it at the boundary; JavaScript creates internal-only
failures without capturing a stack; Python raises real exceptions
throughout; C++, Rust, Go, C, and Zig use `std::expected`, `Result`,
`(v, err)`, and status codes. Tests check that an escaping failure
carries its origin's trace and a handled one none.

## Migration in detail

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

## Cost in detail

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

**On real libraries** ([estimates](claude-explore/estimates/README.md)):
Kelpto and Wherewith throw no failures on valid input. Values add an
estimated 0 to 1% on valid queries on most backends (up to 3% on Python)
with a built-in result type, and about nothing on invalid ones; written
as user classes, as today's translation would make them, they'd add 20 to
300% on C++ and Rust, so the result type must be built in. Lua's `pcall`
per executed `orelse` (1 to 6%) goes away either way once bug-like
builtins panic.

## Open questions in detail

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
