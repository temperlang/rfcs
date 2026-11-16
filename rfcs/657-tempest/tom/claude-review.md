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
