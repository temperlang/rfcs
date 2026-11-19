# From earlier design notes: `this`

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **An explicit receiver parameter has precedent.** An early full
  signature grammar allowed a `this: T` formal before the ordinary
  parameters, after Java's receiver parameter, so a block's `this` type
  could be stated or annotated. That matches this RFC's explicit `this`
  in lambda signatures.
- **Type-qualified `this` already existed internally.** The earlier
  compiler rewrote each `this` to a lookup by type ("the nearest
  enclosing instance of this class"), which works because no class is an
  inner class of itself. Keeping `this` explicit let backends map it to
  JavaScript's implicit receiver, Python's explicit first parameter, or
  Java's `Type.this`. A qualified-this syntax could expose the same
  lookup.
- **Goals listed for `this`:** uses of private members act directly on
  the instance's storage; inherited members are recognized as such;
  external access goes through getters and setters; extension members
  are less specific than real members, but code inside a type can still
  use extensions on it; non-value uses of `this` can be implicit.
