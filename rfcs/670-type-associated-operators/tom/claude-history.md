# From earlier design notes: type-associated operations

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **Customization without instance methods.** To avoid wrapping strings,
  ints, and booleans when they cross into Temper code, the notes
  proposed that ordering, equality, hashing, and debug output be
  customized without callable instance methods: `a <=> b` instead of
  `a.compareTo(b)`, `a == b` instead of `a.equals(b)`, `HashCode.of(a)`,
  and `out.append(a)`, possibly declared as type decorations
  (`@Comparator(…)`, `@Hasher(…)`). Backends then special-case host
  primitives using static types. This RFC's static `supports` is the
  same idea with a checkable shape.
- **Instance-free operations.** Conversion traits like
  `From[UntypedProperties]` (build a value from a bag of properties) and
  `To[T]` played the role of this RFC's `ByteUnpacking`: an operation
  of the type, needing no instance.
- **Limiting what extension types may implement.** Allowing extension
  types to implement only a few known interfaces (comparison, hashing)
  would let the compiler know which host values never need wrapping.
- **Dispatch.** Overloads were collected into per-scope cover functions,
  with static types used to call the right variant directly; a library
  had to import a multimethod to dispatch to it, so adding an overload
  elsewhere couldn't change a distant module's behavior. Diamond
  inheritance in dispatch was flagged, with Python's C3 linearization
  as one rule.
- **Hashing varies by host.** Hash codes were to be opaque, since widths
  and collisions differ by backend.
