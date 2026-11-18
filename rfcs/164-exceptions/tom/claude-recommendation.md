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
hypothetical. **Update, 2026-11-18:** Tom chose the middle ground, with
callbacks polymorphic through an ordinary generic failure parameter and
no `capture` in the first version; [claude-proposal.md](claude-proposal.md)
drafts it, and this page is updated to match. Tom also added another
option the same day, [option 0, no failure support](claude-option-no-failures.md),
compared [below](#recommended-answers).

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
     [refinement](claude-proposal-declared.md#refinement-generic-failure-parameters)):
     results stay in flight, and a higher-order function is generic over
     its callback's failure type (`fn (T): R throws E`, as with Swift 6's
     typed `throws(E)`), so it fails exactly when its callback does.
     Code that needs to keep an outcome stores the failure object. An
     earlier draft also had *explicit capture* into a held
     `Result<T, E>`; it is left out of the first version and could be
     added later.

   A further answer drops the question: **option 0, no failure
   support** ([claude-option-no-failures.md](claude-option-no-failures.md)).
   Temper keeps only nullables and panics, with no `throws`, `orelse`,
   or result type in core or std; libraries that want reasons define
   their own result types.
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
- **Middle ground:** failure gets its own type parameter instead of
  riding in `R`:
  `map<T, R, E>(xs: List<T>, f: fn (T): R throws E): List<R> throws E`.
  `R` never binds a result, since results aren't `AnyValue`; `E` is
  bounded by the failure root (`Error`) and is
  `Never<Error>` when `f` can't fail, so that call needs no `try`. The
  body can only propagate or handle `f`'s failure, never hold it, with
  no effect system beyond "results can't be held". Swift went the same
  way, from `rethrows` to typed `throws(E)`. The label spread that
  Java's checked exceptions are known for is answered separately by
  inferring labels on private code (proposed): authors would write 70 of
  today's 289
  ([throws after panics](claude-explore/throws-after-panics/README.md);
  [proposal](claude-proposal.md#semantics)).

So Kotlin's complexity came from having no failure polymorphism (its
`Bubble` type parameters couldn't be bounded), not from in-flight
results as such.

## Recommended answers

**Semantics: first-class results or the middle ground; not in-flight
results without failure polymorphism.** Mike's 2026 work already made `Result`
the internal truth, and typing failure through the return type removed
whole passes ([review](claude-kotlin-result-review.md)).
Without failure polymorphism, every later generic feature paid a special case: function types, async and
generators' hidden results, the `HACK` in `checkFun`, and libraries'
own result classes (Argmas's `ParseResult`, Hrefine's `UrlCheck`) that
don't work with `orelse`. The two strong candidates remove these, and
so does option 0, by having no failures for generic code to carry:

| | First-class results | Middle ground | Option 0: no failure support |
|---|---|---|---|
| New rules | none beyond the result type | failure parameters bounded by the failure root; results can't be held | none; `throws`, `orelse`, and `Bubble` go |
| `map` with a fallible `f` | a list of results; stopping at the first failure needs a separate std function | stops at the first failure; collecting every outcome stores failure objects | `f` returns `R?` or a library result, which `map` collects; stopping early is a loop or a separate function |
| Async, generators, caches | ordinary value rules | promises hold failures, and `try await` rethrows; caches store failure objects | promises can't be broken; async work resolves to a domain type (std/net's own status type) |
| Exception backends | held results wherever one may be held, including adapters where a throwing function meets generic code | no held results; today's lowering | nothing to lower but panics |
| Host APIs | a result type wherever an exported API holds results | no result types | `null`, `Boolean`, or each library's result types; no host exceptions unless a [decorated-result variant](claude-option-no-failures.md#a-variant-decorated-result-classes) generates them |
| Reading code | any value may be a result | no value is a result | failure is `null` or a library's own type |
| Where reasons go | the failure type | the failure type | a field or result type per library; 12 of 289 declarations need one ([audit](claude-option-no-failures-audit.md)) |

Claude leaned toward the **middle ground**, and Tom chose it
(2026-11-18): it is the smallest step from today's code, Tom's surface,
and Kotlin's IR that removes the special cases, and an ordinary generic
failure parameter does it with the generic machinery the compiler
already has. `capture` is left out of the first version: failure objects
are ordinary values, and promises already hold async failures, so it
can wait until real code shows the need. First-class results remain the
main alternative, the better choice if the team expects many APIs to
store results. Option 0 is the smallest language and compiler, and its
costs fall on host users (silent `null`s where they expect exceptions)
and on libraries (one result convention each); it could also serve as a
first phase, with declared failures added later if libraries miss them
([as a first phase](claude-option-no-failures.md#as-a-first-phase)).
The team decides.

**Speed doesn't decide it**
([estimates](claude-explore/estimates/README.md)): Kelpto and Wherewith
never fail on valid input, so the options cost about the same there.

**Syntax follows semantics.** With the middle ground, exception-style
syntax (`throws`, `try` or `!`, `catch`) is an argument in its favor: it
signals that results aren't values code can hold, while a caught
failure object is an ordinary value. Result-style syntax (`Result<T, E>` return types, `orelse
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
where a failure may escape; under the middle ground no result is ever
held, so it needs no result class (first-class results would build
`Ok(value)` or `Failed(theSameFailureObject)` wherever one is held). **C#** keeps exceptions in a first pass (real libraries
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
   go. Middle ground: `T throws E` as an ordinary generic `Result<T, E>`
   inside the compiler, with failure parameters as ordinary type
   parameters inferred from arguments. First-class:
   drop `anyValueSuper = false` and let held results skip the check
   ([review §5](claude-kotlin-result-review.md#5-relation-to-the-proposals)).
   In tempest, tmpl's `bubbles` flags gain a failure type or become a
   result type.
3. **Boundary forms,** plus held-result representations under
   first-class results.
4. **Syntax,** as the team decides it.
5. **Migration of `throws Bubble`** with a rewriting tool.

## Open questions

- Whether real code later needs capture or holdable results: APIs that
  store a callback's outcome (lazy values, caches, tasks) are the cases
  to watch.
- Spelling of the propagation marker (postfix `?` collides with `?.`;
  postfix `!` reads as a non-null assertion) and of failure parameters.
  The root is `Error`; `Failure`, `Exception`, `Fault`, and
  `Problem` were considered
  ([naming the root](claude-proposal.md#naming-the-root)).
- Whether exported failures must be declared failure types.
- When `throws Bubble` is deprecated, and how long implicit propagation
  lasts.
