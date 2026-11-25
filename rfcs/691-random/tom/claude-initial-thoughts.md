# Random numbers: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-25, for
[#691](https://github.com/temperlang/temper/issues/691). Suggestions
only; nothing here is decided. Mike has ideas on how randomness should
work in Temper that aren't written down yet; this note is a starting
point to set beside them, not a substitute.

## Goals

- **Easy to seed for consistent testing:** the same seed gives the same
  numbers on every backend, so a failing test or a simulation
  reproduces anywhere.
- **Secure by default where it matters:** code that needs
  unpredictability (tokens, keys, nonces, shuffles an attacker mustn't
  guess) gets the host's cryptographically secure source without having
  to know to ask for it, so nobody does something insecure by accident.
- **Small:** a few types in std, not language features.

## Two kinds of randomness, as two types

Most languages offer both kinds, but under names that invite mistakes
(Python's `random` versus `secrets`, Java's `Random` versus
`SecureRandom`, JS's `Math.random` versus `crypto.getRandomValues`).
Making them distinct types lets the type checker keep them apart:

- **A deterministic generator,** written in pure Temper (for example
  xoshiro256** or PCG on `Int64`), made from an explicit seed. Same
  sequence on every backend, cheap, copyable state. For tests,
  simulations, procedural content, and sampling.
- **A secure source,** `@connected` to each host's cryptographic
  generator (Python `secrets`/`os.urandom`, Java `SecureRandom`, .NET
  `RandomNumberGenerator`, JS `crypto.getRandomValues`, Rust `getrandom`,
  C++ the platform's (`getrandom`, `BCryptGenRandom`, `arc4random`),
  Lua through a host binding). Not seedable.

Both could implement a shared interface for drawing values (integers in
a range, floats, bytes, shuffles), so code that only needs "some
randomness" takes the interface.

## Where security comes in

- **Defaults:** the obvious way to get randomness (a `random()`-style
  entry point, or the interface's default instance) is the secure one;
  the deterministic generator always needs a seed, so it's never chosen
  by accident.
- **APIs that need unpredictability** (token and key generation, nonces)
  take the secure type, not the interface, so passing a seeded generator
  is a type error.
- **Tests** can still make those APIs deterministic through an explicit,
  clearly named testing hook (for example a test-only constructor of the
  secure type backed by a seeded generator), so reproducibility doesn't
  require weakening production code.

## Questions

- How does this fit Mike's ideas? (First thing to settle.)
- Seeds: `Int64`, bytes, or both; seeding from the secure source for
  "fresh but reproducible" runs (print the seed, reuse it).
- Range and float generation that's unbiased and identical on every
  backend (rejection sampling; floats from integer bits, not host
  `Math.random`).
- Where hosts lack a secure source (some Lua and embedded setups): fail
  clearly rather than fall back silently.
- Relation to a cross-backend property-testing library, which would
  build on the deterministic generator.
- Performance: the pure-Temper generator on `Int64` is cheap on most
  backends but not on Lua 5.1/LuaJIT or JS, where `Int64` is emulated;
  a 32-bit generator may suit those better, at the cost of a different
  sequence unless every backend uses it.
