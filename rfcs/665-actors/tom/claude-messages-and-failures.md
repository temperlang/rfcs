# Messages and failures

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. Suggestions only;
nothing here is decided.

## Values as messages

Immutable, identity-free values are natural messages: copying or sharing
them across actors is safe, and no host needs locks or deep copies to
send them (see [value types](../../668-value-types/tom/claude-value-types.md)
and `@imu` in [RFC 666](../../666-top-level-safety/README.md)). A rule like "a message type must be `@imu` or a value type" might give
BEAM and worker-based targets (JS, Dart) one portable story.

## Failures and panics

The [exceptions proposal](../../164-exceptions/tom/claude-proposal.md) (RFC 164) separates
declared failures from panics, and Temper code never catches a panic. A
panic inside an actor matches BEAM's "let it crash": the actor dies and a
supervisor decides what happens next. That fits well, as long as
supervision lives in the actor runtime rather than in Temper handlers.

Declared failures crossing actors should probably arrive as values in
messages (the failure object is an ordinary value), not as exceptions
thrown across actor boundaries. That keeps each actor's `try` and
`catch` local and avoids a host-specific way of rethrowing in another
thread or process.

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **Actors as blocks.** An actor was a block with a per-instance
  preface (its state) and a per-call body, wired by a controller to
  shared ring buffers; it returned whether it had more work. Blocking
  APIs were macros over non-blocking ones that `pause` when they can't
  make progress.
- **Which code can pause** should be decidable from syntax alone: a
  `pause` affects the innermost actor block, not whatever function a
  block happens to be inlined into.
- **Lowering `pause`.** On hosts with generators (JS, Python, C#, C++20,
  Lua), `pause` becomes `yield`; elsewhere a function body becomes a
  state machine: hoist locals into the closure, split the control-flow
  graph into maximal paths with each `pause` on its own, and run a
  `switch` on a state variable in a loop. Resumption costs a constant;
  no `goto` needed. A scheduler can drive such agents without promises.
- **Avoid async poisoning:** actors should be plain generators, not
  async ones, so asynchrony doesn't spread into every public API.
- **Host threads.** For host threads calling into Temper, the notes
  rejected vats and event loops in favor of immutable globals and a rule
  that Temper calls a host callback only on the thread that passed it
  in. Isolates and workers for actors are a separate question, but the
  callback rule may still hold.
