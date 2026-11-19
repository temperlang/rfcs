# Single settle loop: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#675](https://github.com/temperlang/temper/issues/675). Suggestions
only; nothing here is decided.

## Where tempest is

Tempest's frontend runs one scheduler twice: an expansion round (read
blocks, resolve names, expand macros, inherit) and then a typing round
(infer declarations' types, decide object literals), with whole-tree
passes between and after: dropping dead branches whose dead side has
errors, flow facts, typing's checks, and module and top-level order.
Tempest's internals docs record this as a deliberate interim choice,
with the alternative "truly one loop, with typing items made as soon as
a declaration expands" (docs/internals/detail/02-settle-loop.md, "Two
rounds, and passes between and after").

## Why one loop

- **Macros that wait on types.** Today only the object literal waits on
  a type, and only in the typing round. User-space macros, contextual
  autoescaping, and compile-time evaluation all want to ask for a type
  and continue expanding, which two rounds can't express: a round-1
  macro can't wait on a type.
- **Compile-time evaluation and inlining** (RFC 662's clear-call
  inlining) need typed, settled callees while other code is still
  expanding.
- **Editors:** one dependency-driven loop is a better base for
  incremental re-settling in the language server than "redo round 2
  over everything".
- **"No stages" becomes true,** matching the design notes and docs.

## What it costs or risks

- **Ordering and cycles:** typing a declaration as soon as it expands
  means more waiting edges and more potential cycles (a macro asking for
  a type its own expansion decides); each needs the deterministic
  tie-break and a clear error.
- **Whole-tree passes:** dead-branch dropping, flow facts, and typing's
  checks assume a fully expanded tree. Each must become per-item work
  with explicit dependencies, or stay a final pass (which is fine if
  nothing needs to run after it).
- **Speed:** finer-grained items cost scheduler overhead; settle time
  is tracked nightly, so a regression would show.
- **Risk to correctness today:** the two-round structure is well
  tested. A migration should keep both paths comparable for a while
  (same diagnostics and output on every test and library).

## Principle: evaluation never changes typing

Tom's direction (2026-11-19): code type-checks by static types alone,
and compile-time evaluation, when it comes, only computes values for
code that already checks (constants, inlining). So `take(find("one"))`
stays an error even once tempest can run `find` while compiling, since
`find`'s declared result is `Int?`; `?? 0` or a null check states the
intent. Typing then can't change as evaluation improves, and reads the
same in the interpreter, the playground, and every backend. This
deliberately differs from Kotlin Temper, which accepted code its
evaluator could run.

## Is it needed now?

Not yet: every macro but the object literal needs only syntax.
Concrete triggers would be the first macro that needs a type during
expansion (user-space macros, autoescaping, compile-time evaluation),
or editor latency that incremental settling would fix. A cheap first
step is to make the typing round's items creatable early (as soon as a
declaration expands) while still scheduling them after expansion, so
the switch later is a scheduling change.

## On the issue's scope

The issue pairs the settle loop with a general cleanup, simplification,
audit, and test-quality pass across the whole code base (editors, the
playground, docs, and tests). Tom's reasoning: a general pass is needed
sometime, and a big structural change like the settle loop is a good
time for it, since much of the frontend gets reread and retested
anyway.

To keep that reviewable, a suggestion: one RFC and one plan, but the
work in bounded, themed changes (the settle loop first, then one area
at a time, each with its own tests and review), so the general pass
never becomes one enormous diff. Core's cleanup already has its own RFC
([671](../../671-core-cleanup/tom/claude-core-cleanup.md)) and can
proceed independently.

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.


- **Seeds that grow.** An early-stage macro could leave a call to a
  later-stage macro in place of itself; a macro expanding to a call of
  its own name wasn't re-expanded in the same stage (the Bash alias
  rule). A single loop needs some equivalent for multi-stage macros.
- **When a call is ready.** Calls were run when "satisfied" (callee
  known, arguments values or the trees the macro wants) or "going out of
  style" (the callee disappears after this stage), with unsatisfied
  arguments replaced by error nodes so the macro could still report
  something.
- **Scheduling.** One coroutine per module turned out not to make things
  easier; a module graph that hands out small tasks that are ready now
  was easier to test and visualize.
