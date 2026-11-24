# IDE hints for better code: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-24, for
[#687](https://github.com/temperlang/temper/issues/687). Suggestions
only; nothing here is decided.

## What hints are

Hints point at code that works but could be clearer, more portable,
faster, or more idiomatic, and usually offer a fix (a code action).
They're never errors: code with hints still builds. The language server
shows them in editors, and a command (`temper check`, or a flag on
`build`/`test`) reports them for CI.

## Before writing the list: brainstorm widely

The team has discussed many hints over time, and not all are written
down. Before an RFC, it's worth a session that goes beyond anyone's
current list, drawing on:

- **Other ecosystems:** Rust's Clippy, Go's `vet` and staticcheck,
  ESLint, Ruff, IntelliJ's Kotlin inspections, Swift's warnings, and
  rust-analyzer's assists.
- **Temper's own pitfalls,** as seen in its libraries, code reviews, and
  per-backend studies.
- **Portability:** code that works on one backend and surprises on
  another.
- **AI-written code:** patterns models produce that a person wouldn't.

## Kinds of hints, with examples

- **Style:** `++i` as a statement → `i += 1`.
- **Readability:**
  - a constructor or function called with a long list of positional
    arguments → an object literal with names;
  - several adjacent `Boolean` parameters, or literal `true`/`false`
    arguments → names or an enum.
- **Easy mistakes:**
  - an explicit `null` passed for a parameter with a default (it gives
    the default; is that what's meant?);
  - an object literal that matches several classes' fields (name the
    class);
  - a result that's computed and ignored.
- **Portability:** comparing floats with `==`; relying on 32-bit integer
  wrapping; iterating a string by index where code points are meant.
- **Performance:** building a string by concatenation in a loop
  (`StringBuilder`); copying a list in a loop.
- **API design (exported declarations):** missing docs; `Boolean`
  parameters; long positional parameter lists; mutable public fields.
- **Formatting-adjacent actions:** explode or implode a list (add or
  remove the line break after the bracket, or the trailing comma), which
  `temper fmt` then lays out.

## Design questions

- **Levels:** hint, information, and warning, and which kinds default to
  which.
- **Configuration:** per project (in config) and per line (a suppression
  comment), kept small; hints that need much configuration probably
  aren't worth having.
- **Speed:** hints run in the language server on every edit, so each
  must be cheap and work on one file where possible, like formatting.
- **Code actions:** every hint that can offer a safe fix should, and the
  fix must keep meaning (checked as `temper fmt` checks its output).
- **Stability:** hints shouldn't churn between versions, or CI that
  checks them becomes a chore; new hints start as information.

## Related

- [#681](https://github.com/temperlang/temper/issues/681): `temper fmt`.
- [#686](https://github.com/temperlang/temper/issues/686): object
  building, which several readability hints point toward.
