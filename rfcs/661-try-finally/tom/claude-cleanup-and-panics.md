# Cleanup and panics: `finally` and the exceptions draft

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. Suggestions only;
nothing here is decided.

The [exceptions proposal](../../164-exceptions/tom/claude-proposal.md#syntax) (RFC 164) makes
`try` an expression-wide propagation marker and spells the full block
form `do { … } catch (e) { … }`
([a full try/catch block](../../164-exceptions/tom/claude-syntax-options.md#a-full-trycatch-block)).
Cleanup has to fit beside that. Three hypothetical options:

1. **`try { … } finally { … }`.** Probably not at odds with `try` as a
   marker: `try` before a block marks propagation from the block, and
   `finally` attaches cleanup.
2. **`do { … } finally { … }`,** matching `do { … } catch`.
3. **`defer`,** as in Go and Zig, taking an expression rather than
   requiring a block: `defer close(h);` (several statements through a
   `do { … }` expression). It fits this RFC's "as if a call to a nested
   function" constraint, and lowers to Rust drop guards and Go's
   `defer`.

## Cleanup and panics

Cleanup can't run on a panic everywhere: C#'s `Environment.FailFast`
and C++'s `std::terminate` skip it, while Java, Python, JS, and Rust's
unwinding run native cleanup on their own
([panics per backend](../../164-exceptions/tom/claude-common-ground.md#panics-per-backend)).
Never running it would mean actively avoiding native `finally` on those
backends. Running it where possible helps hosts that recover from panics
per request or task (web servers, job runners), which would otherwise
leak locks or handles. Either way, code shouldn't rely on cleanup after
a panic. Worth exploring with a shared test program that records which
backends run it.
