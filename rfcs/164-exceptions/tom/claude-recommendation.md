**Claude's recommendation** for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)),
for the team to review alongside the two proposal sketches,
[declared failures](claude-proposal-declared.md) and
[failures as values](claude-proposal-values.md), and their
[common ground](claude-common-ground.md). The team decides; the
proposals stay neutral and don't depend on this page. Drafted by Claude,
2026-11-17. Evidence: [claude-findings.md](claude-findings.md),
[claude-explore/](claude-explore/README.md), the
[error types survey](claude-error-types-survey.md), the
[example translations](claude-translations/README.md), and the
[Kotlin `Result` review](claude-kotlin-result-review.md). Syntax is
hypothetical.

## Two questions

The sketches have converged into one design space, with two separate
decisions:

1. **Semantics: are failures first-class values?** Either a result type
   that Temper code can hold, store, return, collect, and map, so generic
   code and function types work unchanged; or failures in flight only,
   existing between a throw and its handler, with effect polymorphism for
   generics and function types. This is the main decision.
2. **Syntax: how much exception-looking sugar sits on top?** `T throws E`
   as sugar for returning a result, a propagation marker (`try`, `!`, or
   `?`), `orelse` and `??`, and `error case` declarations. This is a
   smaller decision, and mostly independent of the first.

**Representation is a third choice, made per backend**, not by the RFC:
either semantics can be lowered to exceptions, value types, or status
codes ([below](#representation-per-backend)). The values sketch answers
question 1 with first-class failures and little sugar; the declared
sketch answers it with in-flight failures and the most sugar.

## Recommended answers

**Semantics: first-class failures.** Kotlin Temper is the strongest
evidence ([review](claude-kotlin-result-review.md)). Mike's 2026 work
already made `Result` the internal truth: `T throws Bubble` means
`Result<T, Bubble>`, the compiler knows the result type, propagation
lowers to a branch, and TmpL's two types per expression separate
representation from semantics. Typing failure through the return type
removed whole passes. Results stayed second-class (not `AnyValue`, never
held, hoisted so none outlives its check), which spares exception
backends a result type, but every later generic feature has paid a
special case for it: generics and function types (no failure
polymorphism, `asInt64Safe`), async and generators' hidden results, the
`HACK` in `checkFun` and the two-types retyping fixes, and libraries'
hand-rolled result classes (Argmas's `ParseResult`, Hrefine's
`UrlCheck`) that don't work with `orelse`. Making results first-class
removes those special cases rather than adding to them, and settles
`await`, generators, and what `orelse` catches by ordinary value rules.

**Speed doesn't decide it**
([estimates](claude-explore/estimates/README.md)): Kelpto and Wherewith
never fail on valid input, so both cost about the same there (values 0
to 1% more on most backends, with a built-in result type); values win
only on failure-heavy uses such as checking input as it's typed.

**Syntax: throwy sugar is optional, and can come later.** Recommended
minimum: `orelse` and `??`, `return`, `break`, and `continue` as
expressions, and one propagation marker once its spelling is settled.
Keeping `T throws E` as sugar for returning `Result<T, E>` would keep
today's code and Tom's surface; `error case` can declare failure types.
None of this changes the semantics, so it can be decided separately.

**Exported failures are declared failure types:** a non-generic class or
a sealed interface of them (Mike's variants, with an optional message
and cause opaque to Temper), so each backend generates one host class or
error type with the library's name and no wrapper. Inside a library, a
result may carry any type.

## Representation per backend

Each backend picks the cheapest readable form, with identical behavior
checked by shared tests
([values sketch](claude-proposal-values.md#semantics-and-representation-are-separate-choices)):

- **Java:** lightweight declared exceptions internally, with real return
  types and the same classes as the public API, and stack traces only
  where a failure may escape. That is Kotlin's current exception
  lowering, kept for every result checked at its call. Where Temper code
  holds a result, Java materializes `Ok(value)` (one allocation, often
  removed by escape analysis) or `Failed(theSameFailureObject)` (no
  copy; rethrown as the same object if later propagated).
- **C#, C++, and Rust:** value types (`readonly struct`,
  `std::expected`, `Result`).
- **JS, Python, and Lua:** plain values, or real exceptions where that
  is cheaper.
- **Go, C, and Zig:** their error values and status codes.

At exported functions, exception hosts get a throwing form with the
library's own types (`ParseSelect` beside C#'s `TryParseSelect`), Rust
`Result`, Go `(v, err)`, and Lua `nil, failure`. Temper callers always
use the value form. In Java, failures are unchecked by default and listed
in `throws` anyway; generated names follow the
[common-ground naming rule](claude-common-ground.md#naming-across-failure-styles)
and are recorded in `temper.keep`. `TemperBubble` and
`temper_core::Error` become each library's generated base.

## Order of work

1. **Common ground first,** since every option needs it:
   [`return`, `break`, and `continue` as expressions](claude-common-ground.md#return-break-and-continue-as-expressions),
   [which builtins panic](claude-common-ground.md#which-builtins-panic),
   [precedence](claude-common-ground.md#precedence), and
   [`orelse` never catching panics](claude-common-ground.md#what-orelse-catches),
   with the bugs listed there.
2. **First-class results in the compiler.** In Kotlin: drop
   `anyValueSuper = false`, let *Typer* allow results in locals, and
   teach `adjustForBubbles` to skip the check where a result is held
   ([review §5](claude-kotlin-result-review.md#5-relation-to-the-proposals)).
   In tempest, tmpl gains a result type in place of its `bubbles` flags,
   and the profile's `Failure` choice becomes a real lowering pass.
3. **Held-result representations** on exception backends, then
   **boundary forms** with library base types and naming.
4. **Syntax sugar,** as the team decides it.
5. **Migration of `throws Bubble`** with a rewriting tool: the type
   checker already knows each propagating call, and about half of
   Chromarite's sites go once reads and division are settled.

## Open questions for the team

- Question 1 itself, and whether anyone sees a generic or async case
  where in-flight failures stay simpler.
- The sugar: spelling of the result type and the propagation marker
  (postfix `?` collides with `?.`; postfix `!` reads as a non-null
  assertion), and whether `T throws E` stays as sugar.
- Whether exported failures must be declared failure types, or may be
  any type with a generated wrapper.
- Library categories beside the base (Python, Go), or none.
- Whether host callbacks must return values (unusual in C#, Java, and
  Python), or generated adapters may catch typed host exceptions.
- C++'s default host form (`std::expected`, or exceptions by
  configuration), and stack traces for escaping failures on JavaScript.
- Whether, and when, `throws Bubble` is deprecated, and how long
  implicit propagation lasts.
