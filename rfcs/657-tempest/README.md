# Proposal: Tempest becomes Temper

Author(s): Tom P.

Last updated: 2026-11-16

Discussion at https://github.com/temperlang/temper/issues/657.

## Abstract

Replace the Kotlin implementation of Temper with the Rust one, developed as
[temperlang/tempest](https://github.com/temperlang/tempest): its history
becomes temperlang/temper's `main`, its binary is `temper`, and the
Kotlin-based compiler gets no new development. Users keep writing the same
Temper. Current Temper libraries pass at least the same tests as they do on the
Kotlin-based compiler.

This document includes both handwritten text and content from
[a draft by Claude Code](tom/claude-proposal.md). All of it has been reviewed
and manually selected (or written) by humans.

## Background

Starting from Mike's original design and development, we've been developing
Temper for years. We've built a language that's usable for writing actual
libraries, and we've written some libraries in Temper, even if neither the
language itself nor any libraries have reached a 1.0 state. We've also written
an extensive body of tests. And we've designed the language carefully for its
intended purpose of developing cross-language libraries.

That said, we have much more designed, planned, and/or under consideration for
Temper, and the team is small. We have a number of outstanding bugs to fix.
We've also put extensive effort into revamping internals such as temporary
variable cleanup or improving the type system. We can make these things work,
but we have limited developer time to work through all the backlog of fixes,
let alone the intended features required to enact all our plans. And the
existing compiler written in Kotlin takes a while to start up and translate
Temper code to backends. It also uses quite a bit of memory, often in the 100s
of MiB for common uses at the scale we've used it for so far.

Agentic AI coding provides an opportunity to reimplement Temper to a faster,
lighter-weight, and more bug-free form. It enables the still small team to
implement future features sooner and to generate additional testing around
them. And because of our extensive testing, we have increased confidence that
an AI reimplementation will meet our existing design. Further, we expect that
many corporate users of Temper will already be using AI coding in their
organizations, so using AI coding for Temper itself isn't an alien concept.

Rust is a common target for code in the AI coding era because it can produce
efficient code while having a greater amount of safety guarantees than many
other common systems languages. It also already has a rich ecosystem. We also
already have team members with manual experience coding in Rust. This makes
Rust an attractive target for an AI reimplementation.

## Proposal

- The Rust compiler is Temper from the switch on. The Kotlin compiler gets no
  further development, and its code stays readable on a branch. (We have also
  discussed future experiments translating the Rust compiler to Temper itself,
  and the current proposal doesn't preclude such experiments. But any decision
  to actually use Temper for some or all of the Temper implementation in the
  future in an official form would require new official decision making by the
  team.)
- The new Rust implementation isn't a direct translation, although it was made
  with full view to the prior Kotlin source. There was no requirement to use
  the same stages or internal representation, for example. Details of the new
  design have been documented by AI with human review. Initial tests suggest
  that the Rust implementation is about an order of magnitude faster and uses
  about an order of magnitude less RAM
  ([measurements](https://github.com/temperlang/tempest/blob/rfc-657-transition/notes/size-and-speed.md#measured-so-far)).
- Users see Temper and `temper` everywhere: binary, help, errors, docs, editor
  extension, environment variables (`TEMPER_*`). "tempest" stays only as an
  internal codename in Rust code and stack traces.
- The new history moves to temperlang/temper by branch rename, so stars,
  bookmarks, and issues stay where they are:
  - merge tempest's [PR #8](https://github.com/temperlang/tempest/pull/8)
    (`rfc-657-transition`) into its `main`;
  - push the new history as a branch on temperlang/temper;
  - rename the old `main` to `kotlin` and the new branch to `main`;
  - review branch protections;
  - archive temperlang/tempest with a pointer.
- Review [this issue and PR triage list](tom/claude-issue-pr-triage.md) as a
  team. The initial list was based on AI review. We *don't* need to act on the
  list or finalize decisions to complete this RFC, but we do want to be
  prepared to act in the near future to avoid internal and external confusion.
  Triage suggests closing all PRs for Kotlin Temper while still keeping some
  issues open, updated for the new code base.
- First release of the new implementation will be `v0.7.0`, after an `rc` tag
  proves the release workflow end to end. The plan is in place for this, but
  such tagging and release would be after the core RFC described here.

## Rationale

- We've proven out the new compiler across existing and recently AI-developed
  Temper code bases. Older libraries include Temper's regex parser and engine,
  which pass at least the same tests on Tempest as on Kotlin-based Temper (in
  particular failing the same regex parser tests for the Lua backend in both
  cases), as well as internal libraries. Libraries recently expanded or
  developed by AI for Kotlin Temper include Chromarite, Hrefine, Kelpto,
  Ordable, and Wherewith. Details of these libraries are beyond the scope of
  this document, but they help to provide confidence in the translation.
- As discussed in background, Rust is a good target for the new implementation.
  Another consideration was implementing in Temper itself, but Temper isn't yet
  as stable as Rust nor as capable of producing code that's as efficient. And
  as also discussed earlier, we can experiment with Temper-in-Temper in the
  future, but Rust provides an efficient and reliable baseline for helping
  design Temper features that might make such an effort more effective, should
  we choose to pursue that. And perhaps any such effort could be piecemeal,
  since Temper also already compiles to Rust. We already had some Temper in use
  by the Kotlin code (such as the Regex parser) because Temper also compiles to
  Java, but piecemeal reimplementation in Temper on top of the Kotlin code base
  wouldn't have provided the same new lightweight and fast baseline we get with
  the Rust version.
- We plan to keep the temperlang/temper repo and GitHub project so that stars
  and bookmarks remain valid. There's also value in keeping the old PRs and
  issues related, even when the implementation has changed. They're all still
  part of Temper history.
- We can also move over to the new implementation before finishing action on
  existing PRs and issues because a faster switch leaves less down time and
  gives us more momentum. Establishing a line where existing Temper libraries
  and relevant tests pass is a better threshold for moving forward in a clean
  and efficient way as a team than to drag out the switch.

## Compatibility

Source compatibility with the Kotlin compiler is a key goal. However, the
Kotlin compiler isn't always consistent with itself. We also have some
partially implemented plans that encourage clean handling at this time. There
also are a handful of features that we can defer until after the switch to the
new compiler. Some example decisions made during Tempest development follow:

- Stricter checks, each rejecting code that didn't work everywhere: one
  constructor per class; unassigned locals in loop bodies; equally-good
  extension methods; nominal `@fun` interfaces and typed function literals.
  Each was checked against the libraries.
- Not yet available: `temper watch`, `temper doc`, `repl -b`, the `java8`
  backend, and `@json` adapters for generic types. The CLI says so plainly.
- A [full list of differences with the Kotlin implementation](https://github.com/temperlang/tempest/blob/rfc-657-transition/notes/kotlin-differences.md)
  was kept during development. Tom reviewed these during development, making
  many of the judgment calls as needed, but hasn't done fresh study in detail.
- There was purposeful intent during Tempest development to *avoid* adding new
  features or making decisions that felt incompatible with previous team
  discussions.

Going forward, compatible improvements are fine; changes that break backend
output or need team decisions go through RFCs.

## Implementation

Before the switch (Tom, with Claude Code):

- A green manual nightly on `rfc-657-transition`, including the full macOS and
  Windows runs
  ([passing run](https://github.com/temperlang/tempest/actions/runs/43555770061)).
- Team review of this proposal and awareness of
  [the triage list](tom/claude-issue-pr-triage.md), again with no requirement
  to act on the triage list before switching.
- Mike's check of `temper license` and the legal texts (COPYRIGHT, NOTICE,
  licenses of bundled crates and copied runtimes).
- No "final release" of the Kotlin-based compiler is required.

After the switch:

- tag `v0.7.0-rc.1` and `v0.7.0` as described above, which makes it easier to
  track what the first Rust-based compiler version was;
- update repository links (docs site, extension, download links) to
  temperlang/temper, and point library CI at the new nightly names;
- act on the triage list as reviewed;
- group outstanding fixes and improvements into coherent PRs and issues, with
  RFCs only for major decisions;
- move temperlang.dev to the new docs site, with redirects from old pages, then
  retire the Kotlin docs;
- publish the runtimes to package registries.

## Testing

- Positive: functional tests and shared test programs on every backend, with
  golden output; the libraries' own tests nightly; C++ under several compilers
  and sanitizers; generated Lua under both Lua 5.4 and LuaJIT; Linux, macOS,
  and Windows (x64 and Arm64). Also, more backend-specific testing is already
  being done for Tempest (such as mypy and pyright, tsc, LuaLS, clippy,
  compiler warnings as errors) than has been done for Kotlin-based Temper.
- Behavior constraints for initial use are the docs and the tests: a behavior
  change shows up as a changed golden or expectation in review
  ([details](tom/claude-vital.md#behavior-constraints-for-initial-use)).
- Negative testing isn't a blocker (per Mike); closed-box checks (no network,
  writes only where expected, hostile locales, deterministic builds) come after
  the switch ([sketch](tom/claude-vital.md#negative-testing-after-the-switch)).
- **Adding tests:**
  [`docs/internals/10-tests.md`](https://github.com/temperlang/tempest/blob/rfc-657-transition/docs/internals/10-tests.md)
  maps each Kotlin test location to its new one.

## Documentation

The new compiler's docs (guide, language, std, tools, backends, and contributor
internals) are in its `docs/` and published with a playground. User docs were
checked so nothing misleads, and say plainly what's not available yet. After
the switch, temperlang.dev should serve them, which may need DNS updates.
GitHub Pages should be able to serve the site, which is entirely static
content. Docs from snippets with ids (for a REPL `help("topic")`) can follow
later.

## Open issues (if applicable)

- Claude highlighted these as interesting items for the team in the triage
  list, but I don't think they're required for the switch: reserving `enum`,
  comma expressions, static and instance names sharing a name, regex anchors
  with a begin offset, the async model (one turn at a time, which is how this
  has been implemented under Tempest, due to differences between backends in
  Kotlin-based Temper) and Java's exit timeout, and whether the promotion issue
  stays open.
- Various "to do" items for after the switch also are listed above.
