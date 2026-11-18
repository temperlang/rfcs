# Failure labels on fun interfaces

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. Suggestions only;
nothing here is decided.

The [exceptions proposal](../../164-exceptions/tom/claude-proposal.md) (RFC 164) makes
callbacks polymorphic in failure through an ordinary generic parameter,
as with Swift 6's typed `throws(E)`. If named, nominal fun interfaces
replace bare arrow types, that parameter lives on the interface:

```temper
// Hypothetical.
@fun interface Mapper<T, R, E extends Error> { apply(x: T): R throws E; }

map<T, R, E extends Error>(xs: List<T>, f: Mapper<T, R, E>): List<R> throws E
```

Points that touch this RFC:

- **A failure label is part of the interface's signature,** like a
  [`forbids` clause](../../659-memory-management/README.md): stated once
  on the interface, not repeated on each use.
- **`Never<Error>` means "can't fail".** A method without `throws`
  means `throws Never<Error>`, so `Mapper<Int, Int, Never<Error>>`
  takes a callback that needs no `try`. Inference fills `E` at each
  call, so users rarely write it.
- **Interfaces that can and can't fail.** A function that can't fail
  fits where a failing one is expected; how that subtyping works between
  nominal interfaces (rather than structural arrow types) needs an answer
  here.

See [Semantics, item 6](../../164-exceptions/tom/claude-proposal.md#semantics) for the full
rule.
