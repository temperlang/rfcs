# From earlier design notes: process

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

## Values the team has written down

- **Testability is central.** Results on a few backends should predict
  results on all of them, so a contributor with a modest laptop can
  iterate on a few backends and leave the full matrix to CI.
- **No second-class backends.** Once a backend is stable, every new
  feature must work on it; features that only some backends support
  would fragment the library ecosystem that Temper exists to build.
- **Unsafety by conversation.** Unsafe features expand who can build
  safe abstractions, but casual users shouldn't stumble into them;
  publishing a library that uses them could require talking to the
  team first.
- **Prefer native over reinvented.** Map concepts to each host's own
  types and tools before building Temper-specific ones; it keeps
  output small and lets host debuggers work.
- **Dynamism as a means.** Consistent semantics on every backend comes
  first; types then let backends erase the dynamic checks.

## Working patterns

- **Initiatives with owners.** Each area of the code has an owner who
  can accept contributions; work happens on initiative branches with
  stated exit criteria for merging to main.
- **Review at the exit, not every step.** No required review inside an
  initiative; the exit requires review of added tests and docs, plus
  targeted self-review of the pieces that have caused trouble before.
- **Tests first, docs first, RFCs.** Write tests before code; write
  user-facing docs early ("docs start off as lies and become true");
  an RFC is a document with tests and draft docs that a group
  coordinates on.
- **Negative-testing infrastructure** as part of what lets an
  initiative merge.
- **Outside contributions.** CONTRIBUTING.md should explain how to take
  an AI-generated proof of concept from an outside contributor.

## Still open from then

- Contributor terms: a CLA, a DCO, or relying on the hosting site's
  inbound-equals-outbound terms.
