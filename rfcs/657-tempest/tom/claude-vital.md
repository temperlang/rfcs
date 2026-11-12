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
