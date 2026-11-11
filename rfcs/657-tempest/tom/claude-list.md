Forward by Tom: Claude wrote the things below, at least for the first commit.
It made its own document beforehand, then it made the list below after reading
mine.

---

Claude's list of things needed for making tempest the new temper, written
separately from Tom's list beside this one, for comparison. Each item names
what's missing and why it matters.

- Own what's still vendored from Kotlin temper.
  - std, core, the backend runtimes, and the functional tests are copied
    from Kotlin temper with patches on top.
  - Kotlin temper can't be retired until tempest owns these and its patches
    become ordinary commits.
- Get library metadata into generated packages.
  - tempest reads only `name` and `version` from `config.temper.md`.
  - `license`, `description`, `authors`, `homepage`, `repository`, and the
    per-language names and namespaces are dropped.
  - Every generated `pyproject.toml` says `LicenseRef-Proprietary`, even for
    Apache-2.0 OR MIT libraries.
  - So, before the switch, at least check that generated packages are
    correct, even if publishing them comes in a later round.
- Fix the runtime version that generated code names.
  - Generated output names `temper-core` 0.6.0 but needs the patched runtime
    APIs, so packages built against the published 0.6.0 won't build.
- Prove it from callers' side.
  - Run each library's tours unchanged on tempest's output.
  - Diff each library's public API against Kotlin temper's.
  - Run Kotlin temper's integration tests against tempest.
- Decide on the stricter rules tempest already enforces.
  - Nominal fun interfaces, function literals needing a declared type, and
    undeclared names in dead branches all reject code Kotlin temper
    accepts.
  - The team should sign off on each, or tempest should relax it.
- Handle Kotlin-accepted code tempest can't translate yet.
  - For example, `return` inside a `for … of` body, instance extensions, and
    types used as values.
- Close the CLI gaps.
  - `watch` and `repl -b` are missing; `doc` needs a decision to build it
    or drop it.
  - With the rename, the binary becomes `temper` and environment variables
    move from `TEMPEST_*` to `TEMPER_*`.
- Move library CI over.
  - Every library's CI downloads Kotlin temper's `dev` tarball. tempest
    publishes `nightly` with different asset names.
- Set up versioning and releases.
  - The workspace version is `0.0.0`, and there's no written release
    process yet.
- Put negative testing and human-reviewable constraints first (from Tom's
  list, and the hardest part to get right with AI-written code).
