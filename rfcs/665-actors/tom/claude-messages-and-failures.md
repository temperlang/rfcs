# Messages and failures

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. Suggestions only;
nothing here is decided.

## Values as messages

Immutable, identity-free values are natural messages: copying or sharing
them across actors is safe, and no host needs locks or deep copies to
send them (see [value types](../../664-structs/tom/claude-value-types.md)
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
