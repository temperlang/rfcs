# Pluggable effects in core and std: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#674](https://github.com/temperlang/temper/issues/674). Suggestions
only; nothing here is decided.

## The goal

Everything in core and std that reaches outside the program (network,
clock, files, randomness, console, environment, scheduling) has a
host-provided default and a way to swap it, on every backend. That
makes tests deterministic (a fixed clock, a fake network), lets hosts
route effects through their own infrastructure (a company's HTTP
client, a logging framework), and makes some negative tests
([#673](https://github.com/temperlang/temper/issues/673)) checkable in
process.

## Effects to cover

| Effect | Today | Pluggable form (sketch) |
|---|---|---|
| Network (std/net) | each backend's HTTP client, built in | a client with `send`, set per program or passed in; tempest's planned `set_net_client` shape |
| Clock (std/temporal `today()`, timing) | host clock | a clock source: `now()`, `today()` |
| Console and logging | host stdout or console | a sink; already close to this in tempest's REPL and playground, which capture logs |
| Randomness (if std gains it) | none yet | a seedable source |
| Files and environment (if std gains them) | none yet | interfaces from the start |
| Scheduling (async) | each backend's event loop or threads | a scheduler; would also address [#516](https://github.com/temperlang/temper/issues/516) (async blocks run in parallel on Python and Java) |

## Design questions

1. **How it's swapped:**
   - **Global setters** (`setNetClient(…)`), simple and what hosts
     expect, but global state (see RFC 666's concerns about top-level
     mutable state, and threads).
   - **Passed explicitly** (a context or capability object threaded
     through calls): testable and safe, but noisy for every call path.
   - **Scoped** (a dynamic scope or "with this clock, run …"), which
     needs host support (context variables in Python, async-local in
     C#, `AsyncLocalStorage` in JS); uneven across backends.
   - **Config objects:** Kotlin Temper's typed config and connected
     dependencies (#479, #482, #504) built part of this for Java, C#,
     JS, Python, and Rust; a natural place to start.
2. **Who swaps it:** host code (tests in Java or Python), Temper tests,
   or both. Temper tests need a way that works the same on every
   backend.
3. **Defaults:** each backend's natural host implementation, so nothing
   changes for code that doesn't care.
4. **Capabilities as security:** an effect not provided is an effect a
   library can't use (an "effect not available" failure), which ties to
   the secure-composition ideas and to declaring a library's effects in
   its metadata.
5. **Cost:** an indirection per effect call, negligible for network and
   files, worth measuring for the clock in tight loops.

## A possible first step

Network first, since std/net exists and tempest already plans the
client shape: a `NetClient` interface in std, the backend's current
client as the default, a setter for hosts and tests, and a fake client
in std's testing helpers. Then clock and console the same way.

## Related

- Tempest to-do: adopt the net-client shape on Python, JS, Rust, Java,
  and C#, then clock and files.
- [RFC 666](../../666-top-level-safety/README.md) (top-level safety):
  how swappable globals interact with concurrency.
- [RFC 665](../../665-actors/README.md) (actors): effects per actor.
- [#673](https://github.com/temperlang/temper/issues/673) (negative
  testing).
