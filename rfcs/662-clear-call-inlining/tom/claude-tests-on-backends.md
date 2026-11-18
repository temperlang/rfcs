# Tests that exercise backends

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. A suggestion only.

Whatever rule decides inlining could report, per test, whether any
assertion survived to the backend, so authors can see which tests check
translated code rather than a compile-time `assert(true)`. Related
planned work in the exceptions draft (RFC 164): per-test panic reporting
on every backend, and an `assertPanics { … }` helper, which only means
something if its block really runs in translated code
([panics in test runners](../../164-exceptions/tom/claude-common-ground.md#panics-in-test-runners)).
