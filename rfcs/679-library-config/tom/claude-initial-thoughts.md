# Improving library config: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-20, for
[#679](https://github.com/temperlang/temper/issues/679). Suggestions
only; nothing here is decided.

## Where config is today

A library's `config.temper.md` is Temper code that the compiler
evaluates while building. It declares the library's `name`, metadata
(`authors`, `description`, `license`, `homepage`, `repository`), and
backend options. Backend options were flat keys (`javaName`, `pyName`,
`csharpRootNamespace`, …). The earlier compiler had started moving to
typed, per-backend config objects (#479, #480, #482, #504) that each
backend injects into config modules, so the frontend never needs to know
which backends exist; that move is being completed now.

## Support code for config

Config sometimes wants code: metadata shared by several libraries in one
repository (Kelpto's four libraries repeat their license, authors, and
repository), computed values, and helpers that build typed backend
config. Suggestion:

- **Config-only libraries.** A library can be marked as config support
  (or a project can name one), importable only from `config.temper.md`
  files. It is never translated, packaged, or listed as a dependency of
  the library it configures, like Gradle's `buildSrc` or Cargo's build
  dependencies. Across repositories it's an ordinary library that a
  project lists as a config-only dependency.
- **Pure.** Config and its support code may not reach outside the
  program: no network, files, clock, environment, or randomness. Config
  is evaluated while compiling, and purity keeps it deterministic,
  reproducible, and safe to evaluate for tools. Pluggable effects
  ([#674](https://github.com/temperlang/temper/issues/674)) would make
  this easy to enforce: config runs with no effects provided.
- **Bounded.** Evaluation has a step limit (the interpreter already has
  one), so a config can't hang a build or an editor.

## Rendering config

Evaluate config and write its full result as plain data: JSON, or a
simple Temper-free format, with no executable code. Uses:

- **Tools without running Temper.** Editors, CI, documentation
  generators, and package registries read a library's effective config
  cheaply. A registry handling untrusted packages shouldn't execute
  their code to show metadata.
- **Review.** A diff of the rendered config shows what a change to
  config code actually changed.
- **Reproducibility.** Checked in beside the source, it pins the
  effective config, like a lock file; the team's earlier design notes
  proposed exactly this ("configuration dynamic but analyzable", with a
  declarative snapshot in version control).

Questions:

- **Format.** JSON is universal; TOML or YAML read better by hand. The
  shape should follow the typed config: a section per backend, named by
  the backend's own config type.
- **Defaults included or not.** Rendering the *effective* values,
  defaults filled in, is what tools want; rendering only what the
  library set is what reviews want. Possibly both, marked.
- **Stability.** If rendered files are checked in, key order and number
  formatting must be stable across compiler versions.
- **When.** A command (`temper config` or `temper build --render-config`)
  and possibly every build, written under `temper.out` or beside the
  config.
- **Relation to temper.keep
  ([#677](https://github.com/temperlang/temper/issues/677)).** The
  rendered config is a natural part of what a library records, but
  temper.keep is about the published API's compatibility; the two can
  share a directory without being one feature.

## Anything else?

- **Typed backend config documented in one place,** generated from the
  injected types, so every backend's options are discoverable (today
  they're in prose, and Lua's and C++'s were never filled in).
- **Validation messages.** Unknown keys and wrong types reported against
  the config file, with suggestions for near misses.
- **Profiles or overrides.** Development vs release settings (debug
  info, `#line` directives) belong in per-invocation options, not in
  checked-in config; config should say what's published, and a namespaced
  command-line override (by backend) covers the rest.
- **Multi-library projects.** A project-level config for settings shared
  by its libraries (metadata, versions), which the config-only support
  library would also cover.
- **Versions.** Where a library's version comes from (config, git tags,
  or a release tool), and how dependency version ranges are declared per
  backend.

## Related

- [#677](https://github.com/temperlang/temper/issues/677): temper.keep.
- [#674](https://github.com/temperlang/temper/issues/674): pluggable
  effects, for keeping config pure.
- [#676](https://github.com/temperlang/temper/issues/676): host-facing
  names, which typed config is how libraries choose.
- [#140](https://github.com/temperlang/temper/issues/140): external
  libraries.
