Claude's list of what's vital for tempest to become Temper with no major
gaps, after reading Tom's list and Claude's longer plan side by side. Not
everything needs to be perfect; these are the items whose absence users or
library authors would hit. Roughly in order.

1. **No sensitive content.** Scan the current tree and any history added
   since the rewrite again, and run an agent self-audit.
2. **The libraries pass the same tests.** Every library on Tom's list, plus
   the private ones, on every backend, compared with what each passes on
   the Kotlin compiler. Run the libraries' tours unchanged on the new
   output as the clearest "callers can't tell" proof. Known gaps so far:
   one private library's C++ build hits a compiler bug; the regex
   libraries haven't been run yet.
3. **Team sign-off on the stricter rules** already on, which reject code
   the Kotlin compiler accepts: nominal `@fun` interfaces, function
   literals needing a declared type, and undeclared names in dead branches
   being errors. A decision, not work.
4. **Kotlin-accepted code that can't be translated yet, where real
   libraries hit it.** Triage the known list (for example `return` inside
   `for … of`, instance `@extension`, types as values) against item 2's
   runs; fix those, and file issues for the rest.
5. **An installable release with a version.** A real version number, a
   decision on the runtime version generated code names, a written
   release process, and the nightly that library CI fetches. Publishing
   the runtimes to package registries can follow later: output works with
   the runtime written beside it, as it's used today.
6. **The libraries' CI switched to it.** Small per library once item 5
   exists.
7. **`watch`,** which is in daily use and in Kotlin's integration checks.
   `repl -b` and `doc` can be decided and done later.
8. **Rehoming std, core, the runtimes, and the functional tests** out of
   the vendored copy into first-class directories, with the patches folded
   in and their reasons kept in the docs. Near the end, before the rename;
   the vendored copy stops being synced now.
9. **The rename to Temper:** the binary, environment variables, docs, and
   the editor extension. Mechanical but large, so last, just before the
   branch swap.
10. **Docs that would mislead.** A pass where old docs describe behavior
    that no longer applies (CLI options, installation), and a plan for the
    existing docs site; not perfect, just not wrong.
11. **Issue and PR triage, and the branch swap,** per Tom's process,
    including a written answer on what level of negative testing and
    documented behavior constraints is enough for initial use.

Not vital, for after the switch: per-backend goldens of std, Lua and C++
per-language names, publishing the runtimes to registries, the Docker
image, and further language-server and REPL features.

Already done: package metadata and per-language names in generated
packages, clean hover docs, the docs site and playground published, and
the Windows test fixes.

## Tom's decisions on the list

- **Item 3 (stricter rules) needs no sign-off:** they're safe
  adjustments as long as they stay backward compatible against the
  libraries, which item 2 checks.
- **Item 6 (switching libraries' CI) isn't needed for the switch.** It
  only concerns the libraries Tom manages, and the regex libraries have
  no CI yet. Library CI is still worth having later as integration tests
  of the built binaries; meanwhile the new compiler's own nightly and
  weekly CI already builds five public libraries (Hrefine, Chromarite,
  Ordable, Kelpto, and Wherewith) with its binary and tests them on every
  backend.
- **Item 7 (`watch`) can come after the switch.**

## Notes on Mike's comments

- **Docs assembled from snippets with ids:** this is how the Kotlin
  compiler's docs are built (`build-user-docs`): snippets with ids are
  extracted from source comments, annotations, grammar productions, and
  builtins, then inserted into skeleton pages. It's also where the
  insertion markers came from that the new playground's hovers now strip.
  Mike suggests getting back to that way of doing things, before or after
  the switch: one id per topic serves the docs site, hovers, and a REPL
  `help("topic")`. The new compiler's docs are hand-written pages with
  stable anchors, and its hovers come from doc comments, so moving to
  snippet ids is a docs-pipeline change, not a compiler one; after the
  switch seems right.
- **One user-facing name:** agreed, and item 9 plans it. User-facing
  surfaces say Temper: the binary, `--version`, help text, error
  messages, user-facing environment variables, user docs, and the editor
  extension. Non-user-facing things (Rust code, internal crate names,
  stack traces, developer-only variables, internals docs) can keep the
  codename as an implementation detail. A small CI check on just the
  user-facing surfaces would keep the codename from creeping back there.
- **A cheat sheet for adding tests:** cheap and worth doing before the
  switch, in the internals docs. It maps Kotlin's places to the new ones:
  frontend stage tests become a crate's `tests/` with goldens, or a
  functional test for language behavior; backend tests become a program
  in the shared backend test kit, run on every backend with a golden
  each (extending an existing program is preferred); plus how to update
  goldens and which local runs to use.
- **`temper license`:** the new CLI's `license` prints COPYRIGHT, NOTICE,
  and the Apache-2.0, MIT, and CC-BY-SA-4.0 texts, built into the binary,
  and `licenses` lists the bundled third-party crates (a test keeps the
  list current). Also worth a look: the playground's terms, the license
  headers on runtimes copied into generated code (they ship in users'
  packages), and attribution for code carried over from the Kotlin
  compiler.

## Negative testing, after the switch

Nothing new is needed before the switch. For later: Mike's examples (no
upstream sends from `publish --dry-run`, no fetches with `--offline`, no
locale effects, `robots.txt` respected, no test-only dependencies in
bundles) share a shape: a property of what the tool *doesn't* do, best
checked from outside the process. Some checks are cheap:

- **No network:** run `build`, and `test` on the interpreter, inside a
  network namespace (`unshare -n`, or a container with networking off).
  Simpler than proxychains, and any connection attempt fails loudly.
  Any backend whose toolchain fetches packages during tests gets a
  documented exception, or a vendored or cached registry. `publish`,
  `--offline`, and http imports don't exist yet in the new compiler;
  when they come, design them so this harness covers them.
- **Writes only where expected:** run a build with the project
  read-only except its output directory (a bind mount or Landlock), or
  under `strace -f -e trace=file`, and fail on writes elsewhere.
- **Locale and environment:** the compiler is in Rust, whose standard
  library never consults the locale, so it's immune by construction. The
  risk is in generated code and its runtimes: the C# runtime formatted
  numbers by the current culture (`1.5` as `1,5.0`, `-1` with U+2212),
  which the new C# backend fixes, and its tests already run under
  `sv-SE` to keep it fixed. Running each backend's tests once under a
  hostile locale (`tr_TR`, `sv-SE`) and time zone would generalize that.
- **Determinism:** building twice, from different directories and with a
  different `HOME`, gives identical output.
- **Dependencies in packages:** compare a published package's declared
  dependencies against what its non-test code imports.

These fit a "closed-box" CI job beside the existing ones, so the
constraints are enforced, not just spot-checked.
