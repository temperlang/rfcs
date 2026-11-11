Forward by Tom: Claude wrote the below as the direct reply in claude code after
I pointed it at my list. Then I asked it to put its own feedback next to mine,
which I put in the claude-list.md file. As with that file, the original contents
below are directly from claude. I might put my own reactions next to the content
later.

---

Your list, compared with the plan file. We overlap on library tests, issue and
PR triage, cleaning up docs, the name, and the branch swap. A few things only
you have, which I think are important:
- the sensitive-content verification and a possible re-scrub
- the agent self-audit
- negative testing and behavior constraints humans can review. I'd emphasize
  these; they're the hardest part to get right with AI-written code.
- the regex libraries as test targets
- linking issues to RFCs

Things only the plan file has, which seem worth adding to yours:
- Owning what's still vendored from Kotlin: std, the runtimes, and the funtests
  are still copied from it with patches on top. Kotlin can't be retired until
  tempest owns them.
- Generated packages losing library metadata: tempest drops license,
  description, authors, and the per-language names from config.temper.md. Every
  generated pyproject.toml even says LicenseRef-Proprietary, Apache-2.0 OR MIT
  libraries included. That answers your publishability question: at least a
  check that generated packages are correct belongs before 657, even if actually
  publishing comes later.
- The runtime version: generated code names temper-core 0.6.0 but needs the
  patched runtime, so packages built against the real 0.6.0 won't build.
- Team sign-off on the stricter rules tempest already enforces, which reject
  code Kotlin accepts.
- Library CI: every library's CI downloads Kotlin's dev tarball. Switching to
  tempest's nightly, which has different asset names, is part of the transition.
- The CLI: commands Kotlin has and tempest doesn't (watch, doc), plus the
  TEMPEST_* to TEMPER_* environment variable rename that goes with your rename
  item.

Two typos, since the repo is public:
- "Verify that so sensitive content remains" should be "no sensitive content".
- "innapropriate" should be "inappropriate".

On human-written specs: a split that might suit Mike is to have humans write
each RFC's decisions and rationale, while AI does the parts that check it:
gathering evidence (which tests, files, or issues bear on each point), finding
contradictions with existing docs, and drafting test cases. Each RFC could then
say which parts were AI-assisted.
