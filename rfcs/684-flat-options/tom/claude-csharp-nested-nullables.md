# C#: nullable type arguments

By Claude Code (Claude Opus 5.5), 2026-11-27, for
[#684](https://github.com/temperlang/temper/issues/684). A note on one
host where a type parameter's `T?` is hard to spell. Suggestions only.

## The problem

- For an unconstrained type parameter, C#'s `T?` is only an annotation:
  with `T = int` it is plain `int`, so it can't hold null.
- So the C# backend writes a type parameter's `T?` as `Optional<T>`, a
  wrapper, and converts at a call's top level.
- Nested inside another type, the two spellings meet and disagree. In
  the caller, `List<Int?>` can come from `f<T>(): List<T?>` with
  `T = Int` (`IReadOnlyList<Optional<int>>`) or from `g<T>(): List<T>`
  with `T = Int?` (`IReadOnlyList<int?>`), and one local can't name both.
- Kotlin Temper's C# backend has the same gap.

## What the compiler does now

- A type parameter bounded by a class or interface no value type can
  satisfy is written `T?` with a `class` constraint, so both sides agree.
- Other nested cases are reported as "not yet", naming the workaround.

## The general fix, for this RFC

- **Every nullable type argument is `Optional<X>` in C#,** everywhere:
  type arguments, method type arguments, `Func`/`Action`, and `Task`.
  Sound, but host APIs read worse (`IReadOnlyList<Optional<string>>`),
  and std's public `Task<string?>` would change.
- It's the same question this RFC asks for option-typed hosts: how a
  nullable type parameter is represented, and whether nesting is allowed.
  If this RFC's kinds of type formals keep nullable bindings away from
  type parameters used nullably (`T?` where `T` may itself be nullable),
  C# needs `Optional` far less often.
