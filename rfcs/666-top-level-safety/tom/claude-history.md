# From earlier design notes: top-level state

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **The same direction, early.** For host threads calling into Temper
  code concurrently, the notes set two goals: don't require every
  collection to be thread-safe, and don't require atomic reference
  counting everywhere. The answer was that globals are immutable, except
  for a small set of types that are safe as globals: caches of immutable
  keys and values, and registry lists. That is close to this RFC's
  atomic boxes and memo tables.
- **Atomic scalars.** A top-level integer assigned more than once was to
  map to an atomic type (Java's `AtomicLong`, say), which also avoids
  torn 64-bit writes; locking for anything larger needs whole-module
  reasoning, which the notes wanted to avoid.
- **Host callbacks.** Temper calls a host-supplied function only on the
  thread that passed it in.
- **No top-level side effects outside the REPL.** A design for runnable
  entry points listed continued support for top-level side effects in
  ordinary modules as a non-goal: programs start from an entry point
  function instead.
- **Deep vs shallow code.** Helpers nested inside a function share
  state safely per call, where module-level helpers sharing top-level
  state need locking; the notes wanted testing tools good enough that
  nesting doesn't cost testability.
