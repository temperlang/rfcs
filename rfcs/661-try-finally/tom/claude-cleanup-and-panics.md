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

## Loop steps are exit actions too

Added 2026-11-23. A `for` loop's step (`for (init; cond; step)`) must
run on every way to the next iteration: the end of the body and each
`continue`. That is the same problem as `finally`, an action that runs
on certain exits from a block, so one design should serve both.

- **Today** the new compiler copies the step before each `continue`
  (linear: one copy per `continue` site), the same strategy as Java
  compilers copying a `finally` body, with the same size concerns.
- **Native shapes first:** backends with a C-style `for` whose
  `continue` runs the update (JS, Java, C#, C++) can emit
  `for (init; cond; step)` directly; backends with native `finally`
  emit it.
- **One shared lowering elsewhere,** used for both loop steps and
  cleanup where a backend lacks the native shape (Python and Lua have
  no C-style `for`; Rust has no `finally`): a labeled block whose
  `break` reaches the step or cleanup, or the step or cleanup as a
  local subroutine called at each exit ("as if a subroutine", above),
  rather than copying.
- **In the intermediate form,** a loop could keep its step as part of
  the loop, and a cleanup its body, and each backend chooses: native,
  shared lowering, or copy, by profile, as other optional lowerings
  are chosen.

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **`finally` must be able to veto.** A cleanup block can change the
  outcome: return a different result, or `break` out of an enclosing
  loop. That's why a plain closure called on each exit isn't enough, and
  why "as if a nested function" needs an answer for `return` and
  `break` inside `finally`: either forbid them, or have the nested
  function return a code that each call site acts on.
- **Copying blows up.** Java's compilers copy the `finally` body onto
  every exit path, which grows super-linearly when `finally`s nest, and
  is especially bad in source-to-source translation. The subroutine
  shape this RFC prefers avoids it.
- **Labeled blocks lower failure joins.** `orelse` already compiles to
  structured code with labeled blocks and breaks; `finally` can reuse
  that shape on hosts without native `try`/`finally`.
- **Reify scope exits early.** An early compiler design kept scope
  boundaries explicit in the control-flow graph, so cleanup was attached
  once and inlined late, instead of inlining early and having to
  remember it on every new exit.
