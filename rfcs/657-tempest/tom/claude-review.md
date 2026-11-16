Claude's review of the RFC 657 proposal draft ([../README.md](../README.md)),
2026-11-16. Typos, grammar slips, one broken link, and list indentation
were fixed in the README itself; everything below is left for Tom to
decide.

## Inconsistencies to resolve

1. **A final Kotlin release, or not?** Proposal, first bullet: "The
   Kotlin compiler gets a final release from its current `main`".
   Implementation: "No 'final release' of the Kotlin-based compiler is
   required." Pick one; the Implementation line reads like the newer
   decision.
2. **"Archived."** The abstract says the Kotlin compiler "is archived",
   but the plan keeps temperlang/temper and moves the Kotlin history to a
   `kotlin` branch; only temperlang/tempest gets archived. Something like
   "gets no new development, and its history stays on a `kotlin`
   branch" would avoid readers thinking the repository is archived.
3. **Docs decisions "below".** Documentation says temperlang.dev
   "needs the decisions below", but Open issues doesn't list them (domain
   and who owns DNS, which repo publishes the site, where the blog lives,
   how long redirects stay). Either list them there or drop "which needs
   the decisions below".
4. **Abstract: "Current Temper libraries pass the same tests."** True as
   "the same tests they pass on the Kotlin compiler", which is the
   claim that matters; worth saying exactly that, since the regex
   libraries don't pass all their own tests on either compiler (see 6).

## Claims worth backing or softening

5. **"maybe 10x faster and uses 10x less RAM."** The direction is right,
   but a reader will ask for numbers. The new compiler's notes have the
   Kotlin side measured (a one-shot `temper test -b py` of about 28 s on a
   ~900-line library, much of it JVM startup; a watch process of about
   400 MB) and record size and speed for the Rust side over time. A
   sentence with one concrete before-and-after pair, or a link to those
   measurements, would make "10x" solid; otherwise "an order of magnitude
   in our measurements so far" says the same without sounding like a
   guess.
6. **Regex libraries as proof.** Rationale lists "Temper's regex parser
   and engine" among the code bases the new compiler is proven on. A
   check on LuaJIT and Lua 5.4 this week found temper-regex-engine behind
   current std on both compilers (declarations it uses no longer exist),
   and temper-regex-parser failing 12 of 106 tests on Lua 5.4 with either
   compiler. Both compilers behave the same there, so it doesn't hurt the
   argument, but "proven out" overstates; "behave the same as on the
   Kotlin compiler" is accurate.
7. **"Each was checked against the libraries"** (stricter checks): fine,
   and the differences list backs it. One more user-visible change may
   belong in Compatibility: generated packages depend on exactly the
   compiler's version of the language runtimes and std, which aren't on
   package registries yet, so users take them from `temper.out/` or a
   release's packages until publishing (listed under After the switch)
   happens. Library authors who publish will notice this first.

   > Tom: We already have a long history of expecting this for unreleased
   > Temper updates.

   Claude: agreed; no need to mention it, then.

## Smaller points

8. **"as of the time of writing this comment"** (abstract): "this
   document" or "this draft" may be what's meant.
9. **Proposal bullet on tempest naming:** "in Rust code, such as stack
   traces" reads as if stack traces are Rust code; "in Rust code and
   stack traces" (Mike's wording) is clearer.
10. **Implementation, "a green manual nightly … including the full macOS
    and Windows runs":** after this week's Windows and LuaJIT fixes, a
    fresh full run on the final branch commit would settle it; once green,
    it could be marked done, with the run linked.
11. **Rationale, last bullet:** "Establishing a line where existing
    Temper libraries and relevant tests pass is a better threshold" is
    clear now, but "a better threshold than what?" (presumably than
    finishing the triage first) could be said outright.
12. **Testing:** worth one line that generated code is checked by each
    language's own tools (mypy and pyright, tsc, LuaLS, clippy, compiler
    warnings as errors), and that generated Lua also runs under LuaJIT;
    reviewers from those ecosystems will look for it.
13. **Open issues:** "the async model (one turn at a time)" is already
    how the new compiler behaves on every backend; saying so would help
    the team see it's a confirmation, not a new design.

## What reads well

- The Background makes the case without overselling: small team, real
  backlog, Kotlin's startup and memory costs, and why AI plus extensive
  tests makes a rewrite reasonable.
- The process for the switch (branch rename, protections, archive with a
  pointer) is concrete and keeps stars, issues, and links working.
- The triage stance, review as a team but don't block the switch on it,
  matches what the team said, and the PR-versus-issue handling is clear.
- The commitment to RFCs for breaking or team-level changes closes the
  loop on how the new code base will be governed.

## Second pass, 2026-11-16

After Tom's update. Formatting was made consistent in the README (paragraphs
and list items wrapped at 79 columns, link text kept on one line,
"GitHub Pages"), plus two fixes: "no new further development" to "no further
development", and "faster and less using of RAM" to "faster and uses about an
order of magnitude less RAM". The two requested links are in:

- **Speed and memory:** tempest's
  [size and speed notes, "Measured so far"](https://github.com/temperlang/tempest/blob/rfc-657-transition/notes/size-and-speed.md#measured-so-far).
  They time each compiler stage on all Temper files of the Temper and
  Chromarite repos (Kotlin warmed up, so without JVM startup), and record
  peak memory: about 6 to 13 MiB for the Rust compiler's parse, tree, and
  settle stages against about 180 to 250 MiB for Kotlin's. So "an order of
  magnitude" is, if anything, modest for memory. End-to-end runs of the CLI
  aren't in that section; the "Data" and "Charts" sections cover build and
  test times.
- **Nightly:**
  [run 43555770061](https://github.com/temperlang/tempest/actions/runs/43555770061),
  every job green, the full macOS, Windows x64, and Windows Arm64 platform
  jobs included, at commit 3d210b5 (2026-11-14). The branch has moved on
  since (the LuaJIT `Int64` work, among others), so a fresh full run on the
  commit that's actually switched would be good to link instead, or as well.

Earlier items now resolved by the update: 1 (no final Kotlin release
anywhere), 2 ("archived" gone), 3 (Documentation now names DNS and GitHub
Pages instead of decisions below), 4 (the abstract says "the same tests as
they do on the Kotlin-based compiler"), 5, 6, 7 (Tom's note), 8, 9, 10
(linked), 11 ("than to drag out the switch"), 12, and 13.

New, small:

- **Regex engine:** the Rationale says the regex parser and engine pass the
  same tests on both compilers. For the parser that's exact. For the engine,
  tempest passed more in the same check (11 of 20 on Lua 5.4, against 8 of 20
  for Kotlin), both being behind current std. "At least the same tests" would
  be exact for both.
- **"be-lua":** internal jargon; "the Lua backend" reads more easily for
  people outside the core team, if the RFC is shared more widely.
