# Tests that exercise backends

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. A suggestion only.

Whatever rule decides inlining could report, per test, whether any
assertion survived to the backend, so authors can see which tests check
translated code rather than a compile-time `assert(true)`. Related
planned work in the exceptions draft (RFC 164): per-test panic reporting
on every backend, and an `assertPanics { … }` helper, which only means
something if its block really runs in translated code
([panics in test runners](../../164-exceptions/tom/claude-common-ground.md#panics-in-test-runners)).

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **The problem was seen early.** A test of `1 + 1` had to reassign its
  variable so that the frontend wouldn't fold the whole thing to `2`
  before any backend saw it.
- **Kinds of functions.** The notes distinguish plain functions, pure
  functions (no free variables beyond the module, no stateful values;
  safe to evaluate during compilation), specials that see their
  arguments as trees but survive to run time, and macros that don't
  survive. Some could be dual mode: run at compile time when their
  inputs are known, otherwise at run time. That gives one possible
  vocabulary for the decorations.
- **Trailing blocks promise call counts.** Blocks passed to inlinable
  functions were to say whether they're called at most once, exactly
  once, or at least once, which affects what can be inlined and what
  definite-assignment checks know.
- **Testing nested helpers.** A `rather { x = 123 } in { tests }`
  construct let tests reach helpers nested inside functions by
  re-entering the function with chosen values. Concern at the time: the
  tested setup might differ too much from production.
- **Inline defaults.** `@inlineDefault` parameters would inline their
  default expression at each call site, so defaults could refer to the
  caller's context.
