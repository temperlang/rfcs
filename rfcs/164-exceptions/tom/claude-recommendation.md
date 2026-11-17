**Claude's recommendation** for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)),
for the team to review alongside the two proposal sketches,
[declared failures](claude-proposal-declared.md) and
[failures as values](claude-proposal-values.md), and their
[common ground](claude-common-ground.md). The team decides; the
proposals stay neutral and don't depend on this page. Drafted by Claude,
2026-11-17. Evidence: [claude-findings.md](claude-findings.md) and
[claude-explore/](claude-explore/README.md). Syntax is hypothetical.

## Comparison

| Question | Declared failures | Failures as values | Leans |
|---|---|---|---|
| Simpler to implement in Temper | Needs per-backend exception classes and generated sealed hierarchies, typed `catch`, message and cause, host categories, a stack-trace policy, and typed failures through `await` and generators | No exception machinery: failures are values, and propagation lowers to a branch with the existing value lowering. `await`, generators, what `orelse` catches, stack traces, and C and Zig stop being questions. A built-in result type costs about what a nullable does on every backend ([measured, hand-written](claude-explore/README.md#a-compiler-known-result-type-likely-cost)) | Values, clearly |
| Simpler for Temper users | A marker at the same [630 sites](claude-explore/README.md#propagation-markers); familiar to Java and C# users | A marker at the same 630 sites; with an operator, code reads about the same. One concept, familiar from Rust, Swift, Kotlin, and Go. Choosing `T?` or a result is a small, meaningful decision | About even |
| Idiomatic host libraries | Failures are exceptions in exception languages and `Result` in Rust, with no extra API | Needs generated throwing forms and a naming rule, such as .NET's `Parse` and `TryParse` | Declared |

## Recommendation

**Values as the core, with declared failure types as what a result
carries.**

- **Inside Temper, failures are values:** one mechanism, cheap, and the
  same on every backend.
- **Their types are Mike's sealed variants** with an optional message and
  cause, opaque to Temper, and can be written with Tom's `error case`
  declarations as sugar.
- **At exported functions, each backend presents them in its idiom:**
  exceptions with real types and messages in C#, Java, JS, and Python;
  `Result` in Rust; error unions in Zig; a status plus an error struct in
  C; `nil` plus a message in Lua. C++ is open (`std::expected`, or
  exceptions by configuration). Temper callers, in any library, always
  use the value form.
- **The price** is boundary generation and its naming rule, recorded in
  `temper.keep`. A throwing form is a few lines over the value form, and
  a host caller pays one shallow throw per failure.

This takes the clear implementation win, keeps the experience for Temper
users about even, and recovers most of declared failures' advantage for
host code with generated code at the boundary.

## Order of work

1. **Common ground first,** since every option needs it:
   [`return`, `break`, and `continue` as expressions](claude-common-ground.md#return-break-and-continue-as-expressions),
   [which builtins panic](claude-common-ground.md#which-builtins-panic),
   [precedence](claude-common-ground.md#precedence), and
   [`orelse` never catching panics](claude-common-ground.md#what-orelse-catches),
   with the bugs listed there.
2. **The core result type and propagation,** known to the compiler and
   lowered to each backend's cheapest form.
3. **Boundary forms per backend,** with the naming rule and its
   `temper.keep` records.
4. **Migration of `throws Bubble`** with a rewriting tool: the type
   checker already knows each propagating call, and about half of
   Chromarite's sites go once reads and division are settled.

## Open questions for the team

- Spelling of the result type and the propagation operator (postfix `?`
  collides with `?.`; postfix `!` reads as a non-null assertion).
- Whether `T throws E` stays as sugar for returning a result of `E`,
  which would keep today's syntax and Tom's.
- The naming rule for boundary forms per backend, and whether libraries
  opt in or out.
- What a throwing form raises: the failure class as a host exception
  subclass, or a wrapper holding it; and its stack-trace policy.
- Whether host callbacks must return values (unusual in C#, Java, and
  Python), or generated adapters may catch typed host exceptions.
- Whether, and when, `throws Bubble` is deprecated, and how long implicit
  propagation lasts.
