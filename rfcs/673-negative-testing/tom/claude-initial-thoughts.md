# Negative testing: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#673](https://github.com/temperlang/temper/issues/673). Suggestions
only; nothing here is decided.

Negative tests check that something *doesn't* happen: no network
traffic, no locale influence, no test code in a published package.
They're hard to enforce by reading code, but many can be checked from
outside, closed-box, as Mike suggested
([his examples](../../657-tempest/tom/mike-negative-testing.md)).

## Mike's examples, and a check for each

| Property | Closed-box check |
|---|---|
| `temper publish --dry-run` sends nothing | run it with networking disabled (a network namespace, `unshare -n`, or a CI job with no network) and require success; or record traffic with a local proxy and require none |
| `temper build --offline` fetches nothing | the same, with dependencies pre-fetched |
| No locale-sensitive comparisons in the compiler | run the compiler's tests under `LC_ALL=tr_TR.UTF-8` (and a few others, like `de_DE`, `ja_JP`) in CI and require identical output; the classic failure is Turkish dotless i in case mapping |
| HTTP imports respect `robots.txt` | a local test server whose `robots.txt` disallows a path; the import must not request it (server log) |
| Published packages don't link test-only dependencies | inspect the generated package metadata on every backend; done in tempest for Maven, the C# tests project, npm, Rust, Lua, and Python (Nov 2026), and could become a standing check |

## Generated code, too

The same idea applies to what Temper generates, which matters more to
library users:

- **No hidden effects:** a pure library's generated code makes no
  network, file, clock, or environment calls. Check by running its
  tests in a sandbox that denies them (network namespace, read-only
  file system, no environment), per backend.
- **Locale independence:** run every backend's tests under a few
  locales; string casing, number formatting, and sorting must not
  change. Float formatting is already a known cross-backend issue.
- **No Temper names in host APIs:** check generated signatures for
  runtime type names (a planned audit).
- **Determinism:** building twice gives byte-identical output
  (reproducible builds), and output doesn't depend on hash-map order or
  the build machine's paths.

## How to run them

- Mostly CI jobs, not unit tests: a sandboxed job per property, or a
  matrix entry (locales). Linux makes this easy (`unshare`, `bwrap`,
  Docker's `--network none`); macOS and Windows can run a subset.
- Keep them few and named, so a failure says which promise broke.
- Some belong in the nightly rather than every push (slower, or
  needing services).

## Test timeouts

A hang is a failure a negative test should catch, but today only
JavaScript has a per-test timeout, and by accident: mocha's 2 s default,
which makes slow tests flake on JS alone. The compiler plans to drop it, so
every backend waits. Real timeouts would be opt-in and the same on every
backend (set from Temper, by a decorator or a `temper test` flag), each
runner enforcing it its own way (JUnit's `assertTimeout`, a watchdog
thread or process elsewhere).

## Open questions

- Which properties are promises worth documenting (and so enforcing),
  and which are just good practice?
- Whether generated-code checks run on the six libraries in the
  nightly, like their tests.
- Pluggable effects ([#674](https://github.com/temperlang/temper/issues/674))
  would let many of these be tested in-process (a fake network that
  fails if called), complementing sandboxes.

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **Leak checks were on the early roadmap:** once a library builds its
  external API, each backend's test suite checks that no internals leak
  into it, the same promise as "no Temper names in host APIs".
- **Grammar fuzzing.** A generative grammar for a stable subset of the
  language, fed through the lexer and parser, found several real parser
  bugs quickly; the same kind of fuzzing could check that the compiler
  never crashes or emits code that doesn't compile.
- **Auditing macros.** The notes wanted to record which macros used
  their extra powers (reading ancestors, evaluating arguments out of
  order), so a critical module could list what it depends on.
- **Negative-testing infrastructure** was listed as part of the exit
  criteria for merging an initiative to main.
