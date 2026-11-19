# Non-escaping parameters: references that live only on the stack

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#659](https://github.com/temperlang/temper/issues/659). Suggestions
only; nothing here is decided.

## The idea

Let a function mark a parameter as *non-escaping*: the callee may use
the value while the call runs, but can't keep it. Backends with manual
or reference-counted memory (Rust, C++) can then pass a plain borrowed
reference instead of a counted one, avoiding reference-count traffic on
every call, without Temper needing lifetimes or a borrow checker.

It's an optimization: code means the same with or without the marker,
and backends with garbage collection ignore it.

## Rules (a sketch)

A non-escaping parameter may be:

- read, and its members used, within the function body;
- passed to another function's non-escaping parameter;
- used by a closure that is itself non-escaping (a block passed to a
  non-escaping parameter, called before the function returns).

It may not be:

- stored in a field, a module-level variable, or a collection;
- captured by a closure that can escape;
- returned, or made part of a returned value;
- passed to an ordinary (escaping) parameter.

Each rule is checked within one function body, from parameter
declarations alone. No lifetime inference, no regions: a value either
escapes or it doesn't.

## What backends do with it

| Backend | Escaping (today) | Non-escaping |
|---|---|---|
| Rust | an owned `Arc<T>`, cloned at the call | `&T`; no lifetime annotations needed, since nothing can flow into the result |
| C++ | `shared_ptr<T>` by value: an atomic increment and decrement per call | `T const&`, or `shared_ptr<T> const&` |
| Java, C#, JS, Python, Lua | a reference | the same reference; the marker is ignored |

For C++, this fits the existing plan to pass indirect values as
`T const&` in virtual members.

## Questions to settle

- **Read-only or mutable.** Read-only (Rust `&T`) is the safe start.
  Allowing mutation through the reference (`&mut T`) conflicts with
  other live borrows in Rust and needs aliasing rules, so it may never
  be worth it.
- **Blocks.** Trailing blocks are almost always called before the
  callee returns. Making block parameters non-escaping by default (as
  Swift does for closures) would let backends inline them or keep their
  captures on the stack; an escaping block would then need a marker.
  The team's early notes already wanted blocks that can't be stored.
- **Inference.** Private functions could have the marker inferred, as
  failure labels might be (RFC 164); exported signatures would state it,
  since adding or removing it changes the host-facing type in Rust and
  C++.
- **Syntax.** A decorator on the parameter (`@noEscape x: T`), a
  keyword, or a type modifier; a decorator keeps the grammar unchanged.
- **Interaction with value types (RFC 668).** Immutable value types
  passed by value already avoid counting; non-escaping references cover
  the larger mutable or shared objects that value types don't.

## Prior art

- C#: `scoped` parameters and `ref struct` types.
- Swift: closures are non-escaping unless marked `@escaping`.
- D: `scope` parameters.
- Kotlin: `inline` functions' lambda parameters can't escape.
- Research on second-class values (for example Osvald and others,
  "Gentrification gone too far? Affordable 2nd-class values for fun and
  (co-)effect", OOPSLA 2016): most of a borrow checker's benefit for
  parameters with only local checks.

## Related

- [#243](https://github.com/temperlang/temper/issues/243): no reference
  identity checks by default.
- [RFC 668](https://github.com/temperlang/temper/issues/668): value types.
- [RFC 667](../../667-fun-types/README.md): function types, where an
  escaping marker might live.
