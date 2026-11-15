(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: The Rust compiler becomes Temper

Author(s): Tom P. (draft by Claude Code, Claude Opus 5.5)

Last updated: 2026-11-13

Discussion at https://github.com/temperlang/temper/issues/657.

## Abstract

Replace the Kotlin implementation of Temper with the Rust one, developed
as [temperlang/tempest](https://github.com/temperlang/tempest): its
history becomes temperlang/temper's `main`, its binary is `temper`, and
the Kotlin compiler gets no new features and is archived. Users keep
writing the same Temper; the libraries pass the same tests.

## Background

The Rust compiler reimplements the Kotlin one: the same language, std,
and seven backends (C++, C#, Java, JavaScript, Lua, Python, Rust), plus
an interpreter, REPL, language server, VS Code extension, and a browser
playground. Since the team agreed to the switch, the work has followed
[Tom's list](README.md) and [Claude's vital list](claude-vital.md). As of
this draft:

- **Libraries:** Chromarite, Hrefine, Kelpto, Ordable, Wherewith, and the
  regex libraries pass at least the tests they pass on the Kotlin
  compiler, on every backend, plus private team libraries. Five public
  ones run in the new compiler's nightly CI.
- **Kotlin bugs:** 177 fixed differences, each pinned by a test, listed
  in [`notes/kotlin-differences.md`](https://github.com/temperlang/tempest/blob/rfc-657-transition/notes/kotlin-differences.md).
  Known inconsistencies are in [`docs/inconsistencies.md`](https://github.com/temperlang/tempest/blob/rfc-657-transition/docs/inconsistencies.md).
- **Done for the switch:** a sensitive-content scan of the tree and
  history; triage of Kotlin-accepted code the new compiler couldn't
  translate; versioned releases from `v*` tags and a nightly prerelease;
  std, core, and the runtimes rehomed as first-class sources; a docs pass
  so nothing misleads; and the user-facing rename to Temper.
- **Issues and PRs:** every open item on temperlang/temper has a proposed
  resolution in [the triage list](claude-issue-pr-triage.md).

## Proposal

1. **One compiler.** The Rust compiler is Temper from the switch on. The
   Kotlin compiler gets a final release from its current `main`, then no
   new features, and its code stays readable on a branch.
2. **One name.** Users see Temper and `temper` everywhere: binary, help,
   errors, docs, editor extension, environment variables (`TEMPER_*`).
   "tempest" stays only as an internal codename in Rust code and stack
   traces.
3. **One repository.** The new history moves to temperlang/temper by
   branch rename, so stars, bookmarks, and issues stay where they are:
   - push the new history as a branch on temperlang/temper;
   - rename the old `main` to `kotlin` and the new branch to `main`;
   - review branch protections;
   - archive temperlang/tempest with a pointer.
4. **Issues and PRs** follow [the triage list](claude-issue-pr-triage.md),
   reviewed as a team: close what's fixed or Kotlin-only with a short
   comment and evidence, close PRs with their useful parts carried into
   issues, and point design questions at RFCs. None of the list's fixes is
   a precondition for the switch.
5. **First release:** `v0.7.0`, after an `rc` tag proves the release
   workflow end to end.

## Rationale

- **Why replace rather than keep both:** two compilers split every fix,
  test, and doc in two, and users would have to choose. The Rust
  compiler already passes what the libraries need, fixes many known bugs,
  ships as one binary with no JVM, and runs in the browser.
- **Why now:** the switch's vital items are done. What remains (below) is
  either mechanical or better done in the new home, where issues and PRs
  are tracked.
- **Why branch rename instead of a new repository:** existing links,
  stars, issue numbers, and watchers keep working, and the Kotlin history
  stays one branch away.
- **Alternatives considered:** a gradual switch backend by backend (two
  compilers for longer, with mixed output); a new repository (loses the
  issue tracker and links).

## Compatibility

Source compatibility with the Kotlin compiler is the goal, with the
exceptions in the [release notes](https://github.com/temperlang/tempest/blob/rfc-657-transition/docs/release-notes/unreleased.md),
the main ones being:

- **Stricter checks,** each rejecting code that didn't work everywhere:
  one constructor per class; unassigned locals in loop bodies;
  equally-good extension methods; nominal `@fun` interfaces and typed
  function literals. Each was checked against the libraries.
- **Runtimes:** generated packages depend on exactly the compiler's
  version of `temper-core` and std. Until those are on package registries,
  they come from `temper.out/` or a release's packages.
- **Not yet available:** `temper watch`, `temper doc`, `repl -b`, the
  `java8` backend, and `@json` adapters for generic types. The CLI says so
  plainly.
- **Settings:** environment variables are `TEMPER_*`.

Going forward, compatible improvements are fine; changes that break
backend output or need team decisions go through RFCs.

## Implementation

Before the switch (Tom, with Claude Code):

1. A green manual nightly on `rfc-657-transition`, including the full
   macOS and Windows runs.
2. Team review of this proposal and [the triage list](claude-issue-pr-triage.md).
3. Mike's check of `temper license` and the legal texts (COPYRIGHT,
   NOTICE, licenses of bundled crates and copied runtimes).
4. The Kotlin compiler's final release.

The switch: the branch swap in Proposal item 3, then `v0.7.0-rc.1`, then
`v0.7.0`.

After the switch:

- update repository links (docs site, extension, download links) to
  temperlang/temper, and point library CI at the new nightly names;
- act on the triage list as reviewed;
- group outstanding fixes and improvements into coherent PRs and issues,
  with RFCs only for major decisions;
- move temperlang.dev to the new docs site, with redirects from old
  pages, then retire the Kotlin docs;
- publish the runtimes to package registries.

## Testing

- **Positive:** functional tests and shared test programs on every
  backend, with golden output; the libraries' own tests nightly; C++
  under several compilers and sanitizers; Linux, macOS, and
  Windows (x64 and Arm64).
- **Behavior constraints for initial use** are the docs and the tests: a
  behavior change shows up as a changed golden or expectation in review
  ([details](claude-vital.md#behavior-constraints-for-initial-use)).
- **Negative testing** isn't a blocker (Mike); closed-box checks (no
  network, writes only where expected, hostile locales, deterministic
  builds) come after the switch ([sketch](claude-vital.md#negative-testing-after-the-switch)).
- **Adding tests:** [`docs/internals/10-tests.md`](https://github.com/temperlang/tempest/blob/rfc-657-transition/docs/internals/10-tests.md)
  maps each Kotlin test location to its new one.

## Documentation

The new compiler's docs (guide, language, std, tools, backends, and
contributor internals) are in its `docs/` and published with a
playground. User docs were checked so nothing misleads, and say plainly
what's not available yet. After the switch, temperlang.dev should serve
them, which needs the decisions below. Docs from snippets with ids (for
a REPL `help("topic")`) can follow later.

## Open issues

- **Team decisions in the triage list:** reserving `enum`, comma
  expressions, static and instance names sharing a name, regex anchors
  with a begin offset, the async model (one turn at a time) and Java's
  exit timeout, and whether the promotion issue stays open.
- **Docs site:** canonical domain, which repository publishes it, where
  the blog lives, and how long redirects stay.
- **The Kotlin compiler's final release:** its version and timing, and
  how long the `kotlin` branch is supported for fixes, if at all.
- **temperlang/tempest after the move:** archive with a pointer, or
  delete once links are updated.
