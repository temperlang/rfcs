# Making temper.keep real: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#677](https://github.com/temperlang/temper/issues/677). Suggestions
only; nothing here is decided.

## Where it is

- Kotlin Temper 0.4.0 started writing `temper.keep/<backend>/<library>/name-selection.json`
  as a preview: every name each backend chose, keyed by Temper's
  qualified name, never read back.
- Projects gitignore it, because Java and Python record every name,
  private and local ones included (2,148 lines for std;
  [#283](https://github.com/temperlang/temper/issues/283)).
- Temper's new compiler skips the directory when finding sources and
  doesn't write it yet.

## What it's for

A library's **published contract with its host-language users**, kept in
source control beside the library, so builds stay stable and breaking
changes are deliberate:

1. **Names** (first use case, from
   [#676](../../676-host-facing-names/tom/claude-initial-thoughts.md)):
   host-facing names the library chose or the compiler chose once, so
   adding a class or a keyword-colliding member never renames something
   already published. Example: a module class picked once as
   `Ordable.Functions` in C#, not re-derived on every build.
2. **API compatibility:** a summary of the public API per backend
   (types, members, signatures, nullability), so a build can report
   "this release removes `Wherewith.parse(String)`" before publishing.
3. **Decisions:** overrides and exceptions the library has made (a C#
   facade name, a Python module name, an accepted breaking change), with
   room for a reason.

## Design suggestions

- **Public names only.** Record only what host code can see: exported
  types, their public members, top-level exports, package and module
  names. Locals and private members can change freely, so they don't
  belong (fixes #283's spam).
- **Small, diffable text.** One file per library rather than per backend
  where names agree, with per-backend entries only where a backend
  differs. Sorted, one entry per line or a compact table, so a review
  diff shows exactly what changed. TOML or a line format may read better
  than the current JSON.
- **Read as well as written.** A recorded name wins over the default on
  later builds; a recorded name that no longer has a declaration is
  reported (removed API), not silently dropped.
- **Explicit updates.** A build that would change a recorded name or
  remove an entry reports it; the user accepts it with a flag
  (`--update-keep`, say) or a release step, which makes breaking changes
  visible in review.
- **Version-aware later:** an entry can say since which release it's
  public, so checks know what a release promises. Not needed for names.
- **Independent of the compiler's internals:** keyed by Temper's
  qualified names (module path plus declaration path), which are stable
  across compilers, not by internal ids.

## Steps

1. Define the file and its keys; write only public names, under a flag,
   in the new compiler.
2. Read it back: recorded names win, with a report of anything changed
   or missing.
3. Turn it on by default and commit it in the showcase libraries.
4. Add the API summary and a compatibility check, as part of each
   library's release workflow.

## Open questions

- One directory per project, or per library within a multi-library
  project?
- Does std get one, shipped with the compiler, so std's own host names
  are pinned between releases?
- How does a library record "this name is chosen on purpose" (an
  override) versus "this is what the default produced" (a pin)? Both
  stop future churn; only the first is a design choice worth a reason.
- Should the directory keep its name? `temper.keep` is distinctive but
  unclear; something like `temper.api` says what's in it.

## Related

- [#676](../../676-host-facing-names/tom/claude-initial-thoughts.md):
  host-facing names, the first use case.
- [#283](https://github.com/temperlang/temper/issues/283): the spam that
  keeps it gitignored today.
