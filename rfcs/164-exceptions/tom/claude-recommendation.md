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

1. **Semantics: can Temper code hold a result?** A result is the
   success-or-failure union, "a value or a failure". The failure object
   itself (a caught `SqlProblem` with its fields, message, and cause) is
   an ordinary value under every answer: it can be bound, stored,
   passed, put in lists, compared by its fields, and thrown again. The
   question is only about the union. Three answers:
   - **First-class results** (the values sketch): Temper code can hold,
     store, return, collect, and map a `Result<T, E>`.
   - **In-flight results only:** a failure exists between a throw and
     its handler, and nothing holds the union. This is Kotlin Temper
     today, with no way for generic code to pass a failure through.
   - **The middle ground** (the declared sketch's
     [refinement](claude-proposal-declared.md#refinement-pass-through-and-capture)):
     in flight by default, plus *pass-through* (a function fails only
     when a function it was given fails, as with Swift's `rethrows`)
     and *explicit capture* into a held `Result<T, E>` only where code
     asks.
2. **Syntax: how much exception-looking sugar sits on top?** Smaller,
   but it should follow the semantics ([below](#recommended-answers)).

**Representation is a third choice, made per backend**, not by the RFC
([below](#representation-per-backend)).

## Why generics decide the semantics

Typing `T throws E` as `Result<T, E>`, as Kotlin already does
internally, lets failure polymorphism fall out of ordinary generics:
`map<T, R>(xs: List<T>, f: fn (T): R)` given a fallible `f` instantiates
`R` as `Result<U, E>`.

- **First-class results:** generics work unchanged. `map` may collect its
  `R`s into a `List<R>`, a list of results.
- **In flight only:** instantiating `R` with a result is safe only where
  generic code uses `R` linearly, returning or propagating it at once.
  Checking that restriction is a hidden effect system, and Kotlin's
  special cases come from lacking one: the type checker's TODO for
  `fn <T>(f: fn (): T): T { f() }`, core's `forEach` inlined so
  `bubble()` escapes it, the `asInt64Safe` twin, and the `Bubble`
  type-parameter bugs
  ([#108](https://github.com/temperlang/temper/issues/108),
  [#109](https://github.com/temperlang/temper/issues/109); see
  [review §4](claude-kotlin-result-review.md#4-toms-question-did-mike-deliberately-keep-results-out-of-temper-code)).
- **Middle ground:** pass-through states that restriction as one keyword
  with a simple rule, so `map` returns `List<U> throws E` exactly when
  `f` fails; generic code that must hold a result captures it first, and
  then uses it unrestricted.

So Kotlin's complexity came from having no pass-through mechanism, not
from in-flight results as such.

## Recommended answers

**Semantics: first-class results or the middle ground; not in-flight
results without pass-through.** Mike's 2026 work already made `Result`
the internal truth, and typing failure through the return type removed
whole passes ([review](claude-kotlin-result-review.md)).
Without pass-through, every later generic feature paid a special case: function types, async and
generators' hidden results, the `HACK` in `checkFun`, and libraries'
own result classes (Argmas's `ParseResult`, Hrefine's `UrlCheck`) that
don't work with `orelse`. Both strong candidates remove these:

| | First-class results | Middle ground |
|---|---|---|
| New rules | none beyond the result type | pass-through and capture |
| `map` with a fallible `f` | a list of results; stopping at the first failure needs a separate std function | stops at the first failure; collecting every outcome needs `capture` |
| Async, generators, caches | ordinary value rules | capture, by the runtime or the library |
| Exception backends | held results wherever one may be held, including adapters where a throwing function meets generic code | held results only at capture sites; today's lowering elsewhere |
| Reading code | any value may be a result | a result exists only where `capture` says so |

Claude leans toward the **middle ground**: it is the smallest step from
today's code, Tom's surface, and Kotlin's IR that removes the special
cases, and `capture` gives most of first-class results' benefits.
First-class results are the better choice if the team prefers one
mechanism with no new rule, or expects many APIs to store results
(Swift 6 added typed `throws(E)` with generic error types for cases
`rethrows` couldn't express). The team decides.

**Speed doesn't decide it**
([estimates](claude-explore/estimates/README.md)): Kelpto and Wherewith
never fail on valid input, so the options cost about the same there.

**Syntax follows semantics.** With the middle ground, exception-style
syntax (`throws`, `try` or `!`, `catch`) is an argument in its favor: it
signals that results aren't values code can hold, except through
`capture`, while a caught failure object is an ordinary value. Result-style syntax (`Result<T, E>` return types, `orelse
(e)` on values) would wrongly suggest they can be stored freely. With
first-class results, result-style syntax fits better, or sugar that
doesn't hide that results can be held. Either way: `orelse` and `??`,
`return`, `break`, and `continue` as expressions, and one propagation
marker; `error case` can declare failure types.

**Suggested surface** (from [claude-syntax-options.md](claude-syntax-options.md#binding-the-failure)):
an expression-wide `try` marking propagation (Swift's); `orelse` as the
expression operator for defaults, never binding (`f() orelse 0`, as
today); `catch` as a keyword clause shaped like `else`, always taking a
block, optionally after a binding (`f() catch (e) { … }`), so it follows
Temper's brace rule and its block is never mistaken for a function
literal; and `do { … } catch (e) { … }` as the full block form, as Swift
spells it, so `try` keeps one meaning. `??` stays for null, and could
later merge with `orelse`.

**Exported failures are declared failure types:** a non-generic class or
a sealed interface of them, with an optional message and cause opaque to
Temper, so each backend generates one host class or error type with the
library's name and no wrapper.

## Representation per backend

Either candidate lowers per backend, with identical behavior checked by
shared tests
([values sketch](claude-proposal-values.md#semantics-and-representation-are-separate-choices)).
**Java** keeps Kotlin's lightweight exceptions, with stack traces only
where a failure may escape; a held result is `Ok(value)` or
`Failed(theSameFailureObject)`, built only at capture sites under the
middle ground. **C#** keeps exceptions in a first pass (real libraries
rarely fail on valid input) and can move to value types later if
failure-heavy uses need it; **C++ and Rust** use value types; **JS,
Python, and Lua** plain values or exceptions; **Go, C, and Zig** error
values.
Exported functions follow the
[common-ground naming rule](claude-common-ground.md#naming-across-failure-styles).

## Order of work

1. **Common ground first:**
   [`return` as an expression](claude-common-ground.md#return-break-and-continue-as-expressions),
   [which builtins panic](claude-common-ground.md#which-builtins-panic),
   [precedence](claude-common-ground.md#precedence), and
   [what `orelse` catches](claude-common-ground.md#what-orelse-catches).
2. **The chosen semantics in the compiler.** Either way, a function type
   carries its failure, so the `checkFun` TODO and `forEach`'s inlining
   go. Middle ground: pass-through as a failure-type parameter inferred
   from arguments, and `capture` producing a held `Result`. First-class:
   drop `anyValueSuper = false` and let held results skip the check
   ([review §5](claude-kotlin-result-review.md#5-relation-to-the-proposals)).
   In tempest, tmpl's `bubbles` flags gain a failure type or become a
   result type.
3. **Held-result representations,** then **boundary forms**.
4. **Syntax,** as the team decides it.
5. **Migration of `throws Bubble`** with a rewriting tool.

## Open questions

- Question 1, and cases that separate the candidates: APIs that store a
  callback's outcome (lazy values, caches, tasks) favor first-class
  results; short-circuiting helpers favor the middle ground.
- Spelling of the propagation marker (postfix `?` collides with `?.`;
  postfix `!` reads as a non-null assertion), of pass-through, and of
  `capture`.
- Whether exported failures must be declared failure types.
- When `throws Bubble` is deprecated, and how long implicit propagation
  lasts.
