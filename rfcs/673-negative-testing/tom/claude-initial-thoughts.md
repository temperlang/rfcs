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

## Open questions

- Which properties are promises worth documenting (and so enforcing),
  and which are just good practice?
- Whether generated-code checks run on the six libraries in the
  nightly, like their tests.
- Pluggable effects ([#674](https://github.com/temperlang/temper/issues/674))
  would let many of these be tested in-process (a fake network that
  fails if called), complementing sandboxes.
