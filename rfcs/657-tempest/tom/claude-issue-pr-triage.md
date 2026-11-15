# Triage of open temperlang/temper issues and PRs

Draft for RFC 657: a potential resolution for every open issue and pull
request on temperlang/temper, with the new compiler (tempest) replacing
the Kotlin compiler. Not every item needs resolving before the switch;
the goal is that none is left without a plan.

Snapshot: the 216 items open on 2026-11-13 (200 issues, 16 PRs), checked
against tempest's `rfc-657-transition` branch at d18ad98, mostly by small
repros with its REPL and builds, otherwise from its notes and docs. Kotlin
was not rerun; each issue's own report stands for Kotlin's behavior.
Written by Claude Code (Claude Opus 5.5) for review; nothing has been
posted to GitHub.

## Summary

| Proposed resolution | Items |
|---|---|
| Close: fixed in the new compiler | 66 |
| Close: obsolete (Kotlin-only) | 16 |
| Close PR, covered by an existing or new issue | 16 |
| Keep | 71 |
| Keep, pointing to an RFC | 39 |
| Needs a team decision | 8 |

Status in the new compiler: 68 fixed, 26 partly, 85 still applies, 32 not applicable, 5 unverified.

Suggested process: for each closed item, a short comment with the
evidence (and for fixed bugs, the tempest test or note that pins it);
for kept items with Kotlin-specific wording, a retitle; for RFC items, a
link to the RFC once it exists.

## Team decisions

- [#50](https://github.com/temperlang/temper/issues/50) **Implement enum types** (applies): Question: reserve `enum` syntax before 1.0 (as the comments agreed), and if so, as a keyword error now?
- [#112](https://github.com/temperlang/temper/issues/112) **Comma Expression when used in combination with Lists is confusing** (applies): Question: make comma expressions outside lists and arguments (and doubled commas) syntax errors that point to `do { }`?
- [#126](https://github.com/temperlang/temper/issues/126) **Determine when we can promote Temper** (applies): Question: does this stay open as a tracking issue, now that the code is public and the switch is planned?
- [#131](https://github.com/temperlang/temper/issues/131) **Static names can conflict with instance names** (partly): Question: should a static and an instance member sharing a name be a compile error, or stay legal with per-backend renames as tempest does now?
- [#320](https://github.com/temperlang/temper/issues/320) **std/regex: find with an anchored regular expression and a begin offset anchors at wrong place** (applies): Question: should `^` anchor at the begin offset, or is matching JS/Python intended? If intended, document and close.
- [#516](https://github.com/temperlang/temper/issues/516) **Async blocks run in parallel on py and java, and lose updates to shared state** (fixed): Team call: adopt one-turn-at-a-time as Temper's async model (notes on concurrency), or keep it open for idiomatic parallelism per language; then close.
- [#519](https://github.com/temperlang/temper/issues/519) **PromiseBuilder.complete runs the waiting async block before it returns on rust, py and java** (fixed): Same team call as #516; close with it.
- [#524](https://github.com/temperlang/temper/issues/524) **Java's generated main exits after 10 seconds while an async block is still running, with exit code 0** (applies): Team call with #516: should main wait for every pending async block (and say so if it gives up), or keep a cap?

## Pull requests

Every PR closes; what's worth carrying over goes into the named issue.

| # | Title | Area | Status | Resolution | Carry over / action |
|---|---|---|---|---|---|
| [#451](https://github.com/temperlang/temper/pull/451) | generate getters and setters consistently with qnames | frontend | n/a | close PR, new issue: Interface properties and getter/setter pairs should mean the same thing | Close; carry over only the design point from review (an interface's `var name: String` and a get/set pair are the same member) as a language issue if the team still wants it; no code carries over. |
| [#507](https://github.com/temperlang/temper/pull/507) | Experimental: Add Elixir Backend. Hello, BEAM | backend | n/a | close PR, new issue: Elixir/BEAM backend for the new compiler | Close with thanks; carry over the be-elixir README's design decisions and the temper-core Elixir runtime as reference for a new-compiler backend, @actor to the actors RFC (#665), and the @imu claims on std/json and std/regex value classes if the team wants them in std. |
| [#515](https://github.com/temperlang/temper/pull/515) | frontend: name the operand type when no operator applies | frontend | n/a | close PR, covered by #508 | Close; carry over the message "X does not support infix `==`; give it a method marked @operator(\"==\")" (and <=> for comparisons) and its test cases to #508. |
| [#527](https://github.com/temperlang/temper/pull/527) | frontend: reject await and yield outside generator functions | frontend | n/a | close PR, covered by #521 | Close; carry over the rule (await/yield only in a generator body; top-level await only in the REPL) and its stage-test cases to #521. |
| [#529](https://github.com/temperlang/temper/pull/529) | be-cpp: drain the run queue after module init | backend/cpp | n/a | close PR, covered by #520 | Close; carry over the funtest control-flow/async-top-level-complete (and per-test drain case) if the new compiler's funtests lack an equivalent. |
| [#532](https://github.com/temperlang/temper/pull/532) | Run async blocks one at a time on py and java | backend | n/a | close PR, covered by #516 | Close; the design already carried over to the new compiler; the remaining question is #516's team call. |
| [#571](https://github.com/temperlang/temper/pull/571) | frontend: keep top-level reassignments in source order | frontend | n/a | close PR, covered by #540 | Close; carry over its cases (reassignments, the forward-reference conflict, the snapshot example) as inputs to the top-level order RFC. |
| [#572](https://github.com/temperlang/temper/pull/572) | be: do not leave a Void body's return store undeclared when it never returns | backend | n/a | close PR, covered by #536 | Close; carry over the bubble funtest section (a Void bubble keeps its field write) if the new compiler's funtests lack it. |
| [#573](https://github.com/temperlang/temper/pull/573) | builtin: read {m}, {m,} and {m,n} in regex literals as counts | regex | n/a | close PR, covered by #541 | Close; optionally carry over its unit cases for malformed braces (`{a}`, count with nothing to repeat) as parser tests. |
| [#574](https://github.com/temperlang/temper/pull/574) | interp: keep partial evaluation from settling a let assigned on one branch | frontend | n/a | close PR, covered by #528 | Close; carry over UsedBeforeInitTest's cases (loop body, labeled break) as definite-assignment tests if missing. |
| [#575](https://github.com/temperlang/temper/pull/575) | log: print every failing test, not only the first | tooling | n/a | close PR, covered by #505 | Close; nothing to carry over beyond a CLI test that several failures all print, which the new compiler can add. |
| [#585](https://github.com/temperlang/temper/pull/585) | be-py: count a nested def as a local when placing nonlocal | backend/python | n/a | close PR, covered by #559 | Close; nothing to carry over. |
| [#605](https://github.com/temperlang/temper/pull/605) | frontend: hoist a List local across an await as nullable | frontend | n/a | close PR, covered by #549 | Close; nothing to carry over. |
| [#614](https://github.com/temperlang/temper/pull/614) | be-py: put a dashed library's own directory on PYTHONPATH | backend/python | n/a | close PR, covered by #609 | Close; nothing to carry over. |
| [#615](https://github.com/temperlang/temper/pull/615) | interp: refuse a return the macro cannot place, at the return | frontend | partly | close PR, new issue: return in a block lambda: return from the enclosing function at @inlineUnrealizedGoal parameters, a clear error elsewhere | Close; carry over its error cases and the reviewer's forEach example as tests for the new issue. |
| [#634](https://github.com/temperlang/temper/pull/634) | Update to temper-regex-parser 0.4.0 | regex | partly | close PR, new issue: Bring temper-regex-parser 0.4.0's syntax and runtime fixes to the new compiler | Close once the new compiler is main; carry over the JS bitvector and cpp dense_bit_vector fixes (#621), the 0.4.0 regex syntax/special-class changes and their match.temper.md tests, the Lua regex runtime, and the NetResponse POST mime-type fix (unverified in the new compiler). |

## Suggested RFCs

Items that are design questions rather than bugs:

| # | Title | Area | Status | RFC topic / action |
|---|---|---|---|---|
| [#3](https://github.com/temperlang/temper/issues/3) | Full on pattern matching | language | applies | new RFC: pattern matching and destructuring in `when`; link it here. |
| [#5](https://github.com/temperlang/temper/issues/5) | Does-not-reference type bounds for acyclicity | language | applies | new RFC: no reference cycles (acyclic types), covering #5 and #7 together. |
| [#7](https://github.com/temperlang/temper/issues/7) | Properties that are `early` and/or `late` | language | partly | Same RFC as #5 (no reference cycles); note that the fields-first rule answers the constructor part. |
| [#8](https://github.com/temperlang/temper/issues/8) | Macros in user space | language | applies | new RFC: user-space macros; link it here. |
| [#10](https://github.com/temperlang/temper/issues/10) | Parameterized modules | language | applies | new RFC: parameterized modules; ask Mike to post his updated plans there. |
| [#16](https://github.com/temperlang/temper/issues/16) | Custom types for regex group captures | regex | applies | Fold into a regex RFC (custom capture types) or keep as a design issue; link the RFC once written. |
| [#18](https://github.com/temperlang/temper/issues/18) | String templates support | language | applies | new RFC: string templates with statement-level interpolation; link it here. |
| [#24](https://github.com/temperlang/temper/issues/24) | Automatic resource closing (such as `finally` or `Closeable`) | language | applies | Keep low priority; new RFC: resource cleanup (finally / closeable) when a std resource type needs it. |
| [#26](https://github.com/temperlang/temper/issues/26) | Break out std into separate libraries | stdlib | applies | new RFC: splitting std into separate libraries (with #30); link it here. |
| [#28](https://github.com/temperlang/temper/issues/28) | Support user subtypes of Listed and Mapped? | language | applies | new RFC or part of a meta-interfaces RFC: user subtypes of Listed and Mapped; note that it should at least be an error until designed. |
| [#29](https://github.com/temperlang/temper/issues/29) | Support user-defined map keys? | stdlib | applies | new RFC: value equality and hashing (map keys); add a compile-time error meanwhile. |
| [#30](https://github.com/temperlang/temper/issues/30) | Move Deque and DenseBitVector out of builtins/implicits | stdlib | applies | Fold into the std split RFC from #26. |
| [#84](https://github.com/temperlang/temper/issues/84) | Generate indexers in C# | backend/csharp | partly | Point to a meta-interfaces / operator mapping RFC (new RFC: meta interfaces and backend operators). |
| [#89](https://github.com/temperlang/temper/issues/89) | Class Expressions could use a Revision | language | applies | new RFC or decision: class expressions (keep, change syntax, or remove); meanwhile a clear error. |
| [#90](https://github.com/temperlang/temper/issues/90) | Value stability for class instances | language | applies | new RFC: value stability of immutable class instances (compile-time constants); ties to #11. |
| [#116](https://github.com/temperlang/temper/issues/116) | Infrastructure for resolving name collisions in a backwards compatible way | backend | partly | new RFC: stable backend names and API compatibility across releases. |
| [#130](https://github.com/temperlang/temper/issues/130) | Backend branching | backend | applies | new RFC: backend-specific Temper code (@backend). |
| [#140](https://github.com/temperlang/temper/issues/140) | Support external libraries (aka Templandia) | build | applies | Point to a new RFC: external library dependencies and package resolution. |
| [#164](https://github.com/temperlang/temper/issues/164) | Proposal: Explicit exception kinds to support panics | language | partly | Point to a new RFC: declared error kinds versus panics. |
| [#243](https://github.com/temperlang/temper/issues/243) | No reference identity checking by default | language | applies | Point to a new RFC: equality, identity, and hashing. |
| [#282](https://github.com/temperlang/temper/issues/282) | Feature request: Use different operators for integer division and float division | language | applies | Point to the operator-definitions RFC topic, or a new RFC: integer versus float division operators. |
| [#293](https://github.com/temperlang/temper/issues/293) | Reference cycles with closures | language | applies | Point to a new RFC: preventing reference cycles. |
| [#297](https://github.com/temperlang/temper/issues/297) | Support struct splatting | language | applies | Point to a new RFC: spread in object literals. |
| [#373](https://github.com/temperlang/temper/issues/373) | Temper has Float64 division that generates NaN / Infinity in Python backend | language | applies | new RFC: Float64 semantics across backends (division by zero, toString, parsing, rounding); retitle "Float64 division by zero differs by backend". |
| [#410](https://github.com/temperlang/temper/issues/410) | Explicit tracking of thread shareabilty | language | applies | Fold into the RFC from #666 (top-level static constraints) or #665 (actors and isolation); link both. |
| [#540](https://github.com/temperlang/temper/issues/540) | Top-level assignments to a `var` run before the statements written above them | language | applies | new RFC: top-level statement order (source order vs. do-blocks vs. one assignment); link #666. |
| [#554](https://github.com/temperlang/temper/issues/554) | `Float64.toString` gives a different string for the same number on each backend, and on lua and the interpreter some strings do not read back as the same number | stdlib | applies | new RFC: Float64 semantics across backends (format); keep the table as test input. |
| [#555](https://github.com/temperlang/temper/issues/555) | Float64 `floor`, `ceil` and `round` give different answers per backend: py returns Python ints, `round` has three tie rules, java's `round` saturates | stdlib | applies | new RFC: Float64 semantics across backends (rounding). |
| [#556](https://github.com/temperlang/temper/issues/556) | `toInt32`, `toInt64` and `toFloat64` accept inputs that JSON does not, and the backends disagree on which | stdlib | applies | new RFC: Float64 semantics across backends (number parsing grammar). |
| [#658](https://github.com/temperlang/temper/issues/658) | Document the RFC process | docs | n/a | RFC 658 (document the RFC process); close when it's accepted. |
| [#659](https://github.com/temperlang/temper/issues/659) | Compiler should statically check that ref-counting is sufficient for timely deallocation of values constructed solely by Temper code | language | applies | RFC 659-memory-management. |
| [#660](https://github.com/temperlang/temper/issues/660) | Need to hash out meaning of `this` | language | applies | new RFC: meanings of `this` (methods, tests, implicit receivers, qualified this). |
| [#661](https://github.com/temperlang/temper/issues/661) | Nail down what to do about `try { ... } finally { ... }` | language | applies | new RFC: try/finally semantics and translation. |
| [#662](https://github.com/temperlang/temper/issues/662) | Nail down function decorations to avoid surprises around inlining and function purity during compilation | language | applies | new RFC: function decorations for inlining and purity. |
| [#663](https://github.com/temperlang/temper/issues/663) | Blob / byte content APIs and connections | stdlib | applies | new RFC: binary content (blob/bytes) APIs and connections. |
| [#664](https://github.com/temperlang/temper/issues/664) | Hash out struct type semantics | language | applies | new RFC: struct type semantics (after #663). |
| [#665](https://github.com/temperlang/temper/issues/665) | Actors and isolation | language | applies | new RFC: actors and isolation; link #507 and #410. |
| [#666](https://github.com/temperlang/temper/issues/666) | Top-level static constraints | language | applies | new RFC: top-level static constraints; link #540 and #410. |
| [#667](https://github.com/temperlang/temper/issues/667) | Functional interface types decision needed | language | applies | new RFC: function types vs. functional interfaces; record the new compiler's current behavior as one option. |

## Keep open

| # | Title | Area | Status | Evidence | Action |
|---|---|---|---|---|---|
| [#9](https://github.com/temperlang/temper/issues/9) | Regex Unicode properties | regex | applies | std regex docs: "Unicode properties aren't supported yet" | Keep; relabel regex only (backend label is incidental). |
| [#11](https://github.com/temperlang/temper/issues/11) | Compile-time regex translation | regex | applies | regex tutorial still says compile-time translation is future work; the interpreter only caches constant regex literals | Keep as is. |
| [#12](https://github.com/temperlang/temper/issues/12) | Improve error messaging for bad property access | frontend | partly | repro: now "Member a defined in A incompatible with usage" at `this.a = 5`, then a run-time "Abstract property"; clearer than Kotlin's but still not saying the interface property is abstract | Retitle "Clearer error for assigning an interface's abstract property in a constructor" and post the new output. |
| [#14](https://github.com/temperlang/temper/issues/14) | Raw regex state machines | regex | applies | not implemented; depends on #11 | Keep as is. |
| [#15](https://github.com/temperlang/temper/issues/15) | Publish vscode extension | vscode | applies | new compiler's VS Code extension isn't in the Marketplace yet (its README says so) | Keep; retarget to publishing the new compiler's extension. |
| [#17](https://github.com/temperlang/temper/issues/17) | Initial publishing to package repositories | tooling | applies | no publish command in either compiler | Keep as a tracking issue. |
| [#23](https://github.com/temperlang/temper/issues/23) | Add union type restrictions | language | applies | repro: `let x: Int \| String = 1` is accepted without error | Keep; the rule is decided, the check is missing in both compilers. |
| [#25](https://github.com/temperlang/temper/issues/25) | Exhaustiveness checking for `match` | frontend | applies | repro: a `when` covering every subtype of a sealed interface still types as Void without `else` ("Cannot assign to Float64 from Void") | Keep; update the example to `when` (formerly `match`). |
| [#33](https://github.com/temperlang/temper/issues/33) | Regex interpolation | regex | partly | repro: `rgx"x${b}y"` escapes a string value correctly; interpolating a Regex value (`rgx"a${inner}c"`) fails at run time ("No member toString") | Retitle "Regex interpolation of regex values" and post the repro. |
| [#37](https://github.com/temperlang/temper/issues/37) | Custom comparison and comparators | language | partly | @operator("<=>") gives custom natural comparison; no std comparator helpers (lexicographic combination, keyed comparison) | Retitle "std comparator helpers"; natural comparison is done via @operator("<=>"). |
| [#43](https://github.com/temperlang/temper/issues/43) | Undefined type parameters in Java code gen | backend | partly | repro: `var hi<T>(...) { }` is now rejected, but with "Use of builtin @ is malformed"; and `var q = h` for generic `h` gives "Expected subtype of T, but got Int32" at a call | Retitle "Generic function values: clear errors for `var f<T>()` and for storing a generic function in a var"; post repro. |
| [#60](https://github.com/temperlang/temper/issues/60) | Add early error for misordered defaults | frontend | applies | repro: `let g(b: Int = a + 1, a: Int = 1)` is accepted; `g()` fails at run time ("a has not been initialized") | Keep; post the new output. |
| [#74](https://github.com/temperlang/temper/issues/74) | Add PYPI description to temper-std | backend/python | applies | generated pyproject.toml has `readme = {text = "n/a", ...}`, so PyPI's long description would be "n/a" | Retitle "Python backend: real readme (long description) for PyPI". |
| [#91](https://github.com/temperlang/temper/issues/91) | Keyword "in" errors are confusing. | frontend | applies | repro: label `in:` with `break in;` still gives "Expected a TopLevel here" (now a single error) | Keep; post the new single message; question for the issue: allow `in` as a label or say to use nym`in`. |
| [#95](https://github.com/temperlang/temper/issues/95) | SDK use case demo | other | applies | no SDK demo yet | Keep as a deliverable; depends on #96. |
| [#96](https://github.com/temperlang/temper/issues/96) | Fetch API design | stdlib | partly | std/net has NetRequest/NetResponse, but no request or response headers (std net docs) | Retitle "std/net: request and response headers" per the latest comment. |
| [#103](https://github.com/temperlang/temper/issues/103) | Temper.md highlight after lists | vscode | partly | per CommonMark, an indented block right after a list item is list content, not code; tempest follows that, so the code is prose (kotlin-differences lists a planned warning) | Retitle "Warn when indented code after a list item becomes prose"; check the grammar matches. |
| [#115](https://github.com/temperlang/temper/issues/115) | Allow running temper toolchain in a container with supported backend dependencies | tooling | applies | no published container image | Keep as a deliverable. |
| [#121](https://github.com/temperlang/temper/issues/121) | Sign Mac binaries | build | applies | release binaries include macOS Arm64; signing not set up | Keep; apply to the new compiler's macOS binaries. |
| [#123](https://github.com/temperlang/temper/issues/123) | LLM to make transition to Temper easier | other | applies | no LLM tooling deliverable | Keep as a tracking deliverable. |
| [#128](https://github.com/temperlang/temper/issues/128) | Get regex to minumum viable | regex | applies | regex still lacks compile-time translation (#11) and Unicode properties (#9) | Keep as the tracking issue. |
| [#129](https://github.com/temperlang/temper/issues/129) | Make "killer" libraries | other | applies | ongoing | Keep as a tracking issue. |
| [#137](https://github.com/temperlang/temper/issues/137) | Documentation of well-known types mention *AnyValue* unnecessarily as a super type. | docs | applies | tempest's docs/language/types.md still lists `extends AnyValue` on Boolean, Int32, String, and others | Keep as a docs issue for the generated types reference. |
| [#141](https://github.com/temperlang/temper/issues/141) | Separate regex replace one vs replace all | regex | partly | tempest's std regex `replace` replaces each match on every backend (docs/std/regex.md); no replace-first option | Retitle "Add regex replace-first alongside replace-all"; the backend inconsistency itself is gone. |
| [#160](https://github.com/temperlang/temper/issues/160) | Null type assignability to nullable other types | typer | partly | `let a = null; let b: Int? = a;` runs in the interpreter, but `a` has unknown type and translate fails with "not yet in tmpl: an expression of unknown type"; `Null` is not a declared type name in tempest | Retitle "Infer a type for `let a = null` so it translates"; the answer the issue suggests (infer a nullable top) still fits. |
| [#166](https://github.com/temperlang/temper/issues/166) | Lua regex replace failure | regex | unverified | Lua regex runtime not checked here | Re-run the bulletize case on the new compiler's Lua backend and update the issue. |
| [#167](https://github.com/temperlang/temper/issues/167) | Inject StringIndex bounds checks | language | applies | No injected StringIndex bounds checks found in tempest | Keep as a design item; settle panic versus bubble for bad indices first, as the comment says. |
| [#173](https://github.com/temperlang/temper/issues/173) | Consider parking_lot for Rust mutexes | backend/rust | applies | tempest's Rust output still uses std `RwLock` | Keep as a Rust backend performance item. |
| [#180](https://github.com/temperlang/temper/issues/180) | Add more backends | backend | applies | Placeholder for further backends; tempest has C++, C#, Java, JS, Lua, Python, Rust | Keep as the tracking issue for new backends. |
| [#188](https://github.com/temperlang/temper/issues/188) | Fix test counts for Lua | tooling | unverified | Lua test counts not checked here | Re-check `test -b lua` counts on a multi-test library with the new compiler, then close or update. |
| [#189](https://github.com/temperlang/temper/issues/189) | Stop supporting arbitrary `or` types | typer | partly | `[1, "two"]` no longer infers an or-type (element type unknown; docs/language/types.md marks unions deprecated), but `let x: Int \| String` is still accepted | Retitle "Reject arbitrary union types in declarations". |
| [#223](https://github.com/temperlang/temper/issues/223) | be-rust: Closure assigning capture in conditional fails to get wrapped | backend/rust | partly | Captured `j` is now `Arc<RwLock<i32>>`, but the immediately called closure is emitted as `{ ...; Arc::new(move \|k\| ...) }(i);` in statement position, which rustc rejects (E0308, block parsed as a statement) | Retitle "be-rust: immediately invoked closure in statement position doesn't compile"; include the new repro. |
| [#226](https://github.com/temperlang/temper/issues/226) | Should we have a .gitattributes? | tooling | applies | The new compiler's tree has no .gitattributes | Keep; fold into the switch-over repo setup. |
| [#231](https://github.com/temperlang/temper/issues/231) | Update docs and temper projects to use preferred syntax | docs | partly | tempest's docs use infix `is`/`as` (no `.is<`/`.as<` outside release notes); other temperlang/* repos unchecked | Retitle "Update temperlang/* library repos to infix is/as". |
| [#237](https://github.com/temperlang/temper/issues/237) | More docs in repl, such as via help function | repl | partly | tempest repl has `help("name")` and `help(String)`, but `help(raw)` prints "builtin raw: ?" and `help(String.fromCodePoint)` is refused | Retitle "REPL help for builtin functions and members". |
| [#242](https://github.com/temperlang/temper/issues/242) | Implement C ABI for Rust or C++ backend | backend | applies | No C ABI output in tempest | Keep as a feature request. |
| [#250](https://github.com/temperlang/temper/issues/250) | A class named "Type" causes issues in be-py and be-java. | frontend | applies | Repro: with a user class `Type`, `new Type()` resolves to core's `Type` and translate fails ("not yet in tmpl: core's Type.constructor"); no frontend error | Retitle "User class named Type is shadowed by builtin Type". |
| [#251](https://github.com/temperlang/temper/issues/251) | Double class crash | frontend | partly | No crash: Java renames the second class `Dup__2` in the REPL, and `build` reports "can't be named Dup, which another declaration has"; still no frontend error for duplicate top-levels | Retitle "Frontend error for duplicate top-level declarations". |
| [#272](https://github.com/temperlang/temper/issues/272) | Add backend construct matrix to temper docs | docs | applies | No construct-by-backend matrix in tempest's docs/backends | Keep as a docs item. |
| [#278](https://github.com/temperlang/temper/issues/278) | Ignore more files | build | unverified | tempest honors every .gitignore/.temperignore, but skipping non-library directories wasn't checked | Check against the new compiler's work-root scan; close if covered. |
| [#279](https://github.com/temperlang/temper/issues/279) | Ignore and test ignoring files in lang server | tooling | unverified | tempest's LSP ignore handling wasn't checked | Check the new compiler's language server with ignored files; close if covered. |
| [#288](https://github.com/temperlang/temper/issues/288) | `g++` does not mean `g++` on MacOS | backend/cpp | unverified | tempest builds C++ via CMake (honoring CXX), not a hard-coded g++; not run on macOS here | Retitle "Check C++ backend toolchain on macOS"; close after a macOS run. |
| [#296](https://github.com/temperlang/temper/issues/296) | Add way to remove slice of listbuilder without copy | stdlib | applies | ListBuilder still has only `splice` for removal | Keep as a std request. |
| [#300](https://github.com/temperlang/temper/issues/300) | Add `temper clean` subcommand | build | applies | No clean subcommand in tempest | Keep; fold in the temper.keep design (#283). |
| [#304](https://github.com/temperlang/temper/issues/304) | Optimize sealed interface type switching in Rust | backend/rust | applies | Repro: `when` over sealed subtypes still emits `temper_core::is::<P1>` if/else chains | Keep as a Rust optimization. |
| [#315](https://github.com/temperlang/temper/issues/315) | Validate against simple method naming conflict with overload name | frontend | applies | Repro: `@overload("hi")` plus a real method `hi` in the same class gives no error | Keep. |
| [#316](https://github.com/temperlang/temper/issues/316) | Support overload of non-method functions | frontend | applies | Repro: `@overload("hey")` on top-level functions; `hey("x")` gives "hey has not been declared" | Keep. |
| [#317](https://github.com/temperlang/temper/issues/317) | Validate against non-decorated overloads | frontend | applies | Repro: two top-level `let ho(...)` with different params give no error | Keep. |
| [#318](https://github.com/temperlang/temper/issues/318) | Generate overloads in be-cs and be-java | backend | applies | Repro: C# output has only HiInt/HiStr, no `Hi` overloads | Keep; the Java erasure caveat in the comments still applies. |
| [#324](https://github.com/temperlang/temper/issues/324) | be-js: default method implementations can be clobbered by pure virtual | backend/js | applies | Repro: `new D().f()` for `class D extends B & C` is a frontend error ("No callee matches inputs [D] among [(B) -> Int32, (C) -> Int32]"); JS still emits abstract `f` as a field on A and B | Retitle "Inherited default method through diamond: frontend error and JS clobbering". |
| [#326](https://github.com/temperlang/temper/issues/326) | Need check that overload name is not used in subtype | frontend | applies | Repro: class implementing `@overload("f") g()` and also defining `f()` gives no error | Keep. |
| [#341](https://github.com/temperlang/temper/issues/341) | be-py: Handle protected -> public forwarding | backend/python | applies | tempest repl translate(…, "py"): B's public getter `thing` doesn't override A's protected `_thing`, so sureThing() reads 'thing' in Python (interp gives "hi") | Retitle: "py: a public override of a protected getter doesn't replace the protected one". |
| [#343](https://github.com/temperlang/temper/issues/343) | be-lua: Still can need too many registers | backend/lua | partly | tempest moves module-level locals past 128 into a table (notes/tmpl/profiles.md, "Lua's limits on locals"); a function with over 200 live locals or many temporaries is still not handled | Retitle: "lua: a function can still exceed Lua's local/register limits"; note module-level case is handled in the new compiler. |
| [#360](https://github.com/temperlang/temper/issues/360) | Call `clone_boxed` to avoid deep wrapping in Rust | backend/rust | applies | tempest keeps Kotlin's interface surface (wrapper struct + clone_boxed trait); notes/api-compat.md proposes Arc<dyn XTrait> interfaces that remove the wrapping, not done | Keep as a Rust output-quality issue; link the new compiler's Rust interface proposal when it's written up. |
| [#383](https://github.com/temperlang/temper/issues/383) | [Feature Request] be-go: Add Go support | backend | applies | no Go backend in the new compiler yet; Go is on its list of planned backends | Keep as the Go backend request; note new backends will target the new compiler. |
| [#408](https://github.com/temperlang/temper/issues/408) | Feature: Python+Rust (for example, via PyO3) | backend | applies | no C ABI / native Python path in the new compiler | Keep; point to #242 and say native bindings would be built on the new compiler. |
| [#431](https://github.com/temperlang/temper/issues/431) | Adding optional param is breaking change for rust | backend/rust | applies | tempest's Rust still maps optional params to Option<T> positional params (notes/api-compat.md, Rust mapping) | Keep for the API compatibility checker; consider builders/options structs for Rust functions too. |
| [#437](https://github.com/temperlang/temper/issues/437) | Haxe and Nim support | backend | applies | no Haxe or Nim backend in the new compiler | Keep as a backend request; maybe split Nim out when someone picks it up. |
| [#456](https://github.com/temperlang/temper/issues/456) | Userspace `@connected` methods | backend | partly | tempest supports user @connected functions and classes with Temper fallbacks and per-backend lists (kotlin-differences.md, "A user's @connected type"); interfaces, generics and generators still not connectable | Update the checklist for the new compiler: done items stay done; remaining are connected interfaces/types, generics, generators. |
| [#461](https://github.com/temperlang/temper/issues/461) | Improve method docs reference to `this` | docs | applies | tempest's docs/language/types.md still shows Int32.max as fn(Int32, Int32): Int32 | Keep as a docs issue against the new compiler's generated docs. |
| [#489](https://github.com/temperlang/temper/issues/489) | Multiline string failure | frontend | applies | tempest repl: the same multi-line string (`~a ${}` line followed by a `"${1}` line) fails with "Expected a Expression here"; each line alone works | Keep; reproduces in the new compiler. |
| [#508](https://github.com/temperlang/temper/issues/508) | `==` and `when` on class instances report an `Int32` signature, then fail at run time with an internal message | frontend | applies | tempest: `p == p` on a class without @operator("==") still reports the Int32 signature (repro); at run time it fails at the error, not with an internal message | Retitle: "`==`/`<` on a class without @operator reports an Int32 signature"; carry over #515's message wording. |
| [#511](https://github.com/temperlang/temper/issues/511) | A rejected assignment is emitted as written, and the failed build's output runs | frontend | applies | by design in both compilers: type-only errors run as written on dynamic backends, fail where reached on static ones, exit status 1 (kotlin-differences.md, "Type-only errors run on") | Retitle: "Option to skip writing or running output when the build has errors", per the maintainer's comment. |
| [#521](https://github.com/temperlang/temper/issues/521) | `await` outside an async block passes the frontend, then each backend fails in its own way | frontend | partly | tempest: top-level await is a located error ("await outside generator function body"); await in a plain function or method fails only as tmpl's internal "F6: an await outside a generator's own body", plus "T1: Error needs a type" (repro) | Retitle: "await in a non-generator function needs a located frontend error"; carry over #527's checker design and tests. |
| [#557](https://github.com/temperlang/temper/issues/557) | cpp: `String.toFloat64` bubbles on subnormal, underflowing and overflowing inputs, because `std::stod` throws on range errors | backend/cpp | partly | tempest's C++ toFloat64 uses strtod and returns the nearest double on underflow; overflow (1e400) still bubbles, "undecided" (temper-core string.hpp comment) | Retitle: "Should toFloat64 of an overflowing input give Infinity or bubble?"; fold into the Float64 RFC. |
| [#579](https://github.com/temperlang/temper/issues/579) | A generator's `done`, `is ValueResult`, and `nextSafe()` on its last step break on most backends | backend | partly | tempest: ValueResult tests and nextSafe() past the end work on js and py; Generator.done is "not yet in tmpl" (a clean build error) (repro) | Retitle: "Generator.done isn't translated yet". |
| [#612](https://github.com/temperlang/temper/issues/612) | cpp: a library named `nan`, `time`, `random` or after another C library function does not compile, because its namespace collides with the function | backend/cpp | applies | tempest's C++ for a library named `time` fails: "namespace time redeclared as different kind of entity" (repro) | Keep; the new compiler's C++ names need the same fix (escape or prefix libc-clashing namespaces). |
| [#619](https://github.com/temperlang/temper/issues/619) | A generic function passed as a value with its type argument, `identity<Int>`, fails at run time on every backend except the interpreter | frontend | partly | tempest: apply(identity<Int>, 5) is a build error "not yet in tmpl: a call typing didn't resolve" rather than a runtime failure (repro) | Retitle: "A generic function value with type arguments, identity<Int>, isn't supported". |
| [#621](https://github.com/temperlang/temper/issues/621) | `DenseBitVector.set` loses a bit set at index 128 or above on js, whatever the capacity, and on cpp any `set` or `get` past the capacity kills the program | backend/js | applies | tempest js: DenseBitVector set at 128 and 500 read back false (repro); cpp past-capacity not checked | Keep; carry over the js bitvector fix and cpp dense_bit_vector bounds change from #634. |
| [#622](https://github.com/temperlang/temper/issues/622) | `new Date(2023, 4, 31)` is 1 May on js and 31 April on cpp, and each backend's `Date.fromIsoString` accepts a different set of strings | stdlib | applies | tempest js: new Date(2023, 4, 31) is 2023-05-01, fromIsoString("96-03-31") is 1996-03-31, "2023-04-31" rolls over (repro) | Keep; std/temporal needs one validated parse and constructor on every backend. |
| [#657](https://github.com/temperlang/temper/issues/657) | Make tempest the new temper | other | n/a | tracking issue for RFC 657 (this transition) | Keep until the switch lands, then close. |

## Close: fixed in the new compiler

| # | Title | Area | Status | Evidence |
|---|---|---|---|---|
| [#1](https://github.com/temperlang/temper/issues/1) | TmpLTranslator should ensure that static methods invoke themselves via static reference instead of using their name | tmpl | fixed | Lua output calls Foo.f(true) for a recursive static method; tempest also requires the type name for static access ("Type name required for accessing static member") |
| [#2](https://github.com/temperlang/temper/issues/2) | Support arbitrary imports in repl | repl | fixed | repro: relative imports (import("./shape")) and `let { ... } = import("std/regex")` then `Dot` work in tempest repl; documented in `tempest repl --help` |
| [#21](https://github.com/temperlang/temper/issues/21) | Infer lambda block return types from function body | frontend | fixed | function literals typed from the type wanted (kotlin-differences, "Target typing"; Test: settle/types.cases "function literals typed from the type wanted"); repro: `["a","b"].map { shape => shape.toString() }` works without a declared return type |
| [#34](https://github.com/temperlang/temper/issues/34) | Class names sometimes missing on repl translate to py & others | repl | fixed | repro: translate(1, "py") of `let f(a: A2)` after `class A2 {}` in an earlier entry gives `def _f(a: _A2, /) -> int` with the class declared |
| [#35](https://github.com/temperlang/temper/issues/35) | Typing error in coroutine factories | frontend | fixed | kotlin-differences "Generators in any function form" (Test: settle/run.cases); functional test control-flow/actor-run passes on every backend |
| [#36](https://github.com/temperlang/temper/issues/36) | Custom equivalence and default equivalence for record classes | language | fixed | @operator("==") methods and @auto("==") generated eq are implemented (tempest typing notes, "Operators defined in Temper") |
| [#51](https://github.com/temperlang/temper/issues/51) | Private members of interfaces | frontend | fixed | repro: private interface methods work in the interpreter and translate (Java private interface method, C# private method); private backed properties get "Interfaces may not define backed properties" |
| [#65](https://github.com/temperlang/temper/issues/65) | Override ToString for toString in C# or others? | backend/csharp | fixed | repro: a Temper `toString()` translates to `public override string ToString()` in C# |
| [#73](https://github.com/temperlang/temper/issues/73) | Class declaration in REPL does not export symbol | repl | fixed | repro: same as #34; translating a later REPL entry that uses an earlier class works |
| [#78](https://github.com/temperlang/temper/issues/78) | Bad generic callback parameter type inference | frontend | fixed | repro: `hi(["there"]) { it => console.log(it); }` with `hi<T>(a: List<T>, action: fn (T): Void)` runs without errors |
| [#87](https://github.com/temperlang/temper/issues/87) | Java Backend makes unknown vFunction for join on certain functions. | backend/java | fixed | repro: `strs.join(" ", idString)` translates to `Core.listJoinObj(strs, " ", InteractiveGlobal::idString)` in Java |
| [#92](https://github.com/temperlang/temper/issues/92) | Race condition during logging errors. | tooling | fixed | repro: building the issue's example reports one clean error ("lib.temper:4:7: error: Expected a TopLevel here", "1 error") with no interleaving |
| [#97](https://github.com/temperlang/temper/issues/97) | Mutable closed-over vars in be-java | backend/java | fixed | Java backend translates generators, async, and await as state machines (functional tests, ASYNC list, run on Java) |
| [#102](https://github.com/temperlang/temper/issues/102) | Large temper files "Not generating code". | frontend | fixed | repro: the attached files build with the new compiler without a crash, reporting their real errors (s, error and rulesN undeclared) in about 6,400 messages |
| [#105](https://github.com/temperlang/temper/issues/105) | Inference propagates across decls | frontend | fixed | repro: describe(n, "types") shows `fuji: Fuji`, `apple: Apple` |
| [#106](https://github.com/temperlang/temper/issues/106) | Compound operator assignment to property fails | frontend | fixed | repro: `c.i += 2` on a `public var` property gives 3; also kotlin-differences, compound assignment (Test: settle/macros.cases) |
| [#108](https://github.com/temperlang/temper/issues/108) | Typer does not filter out BUBBLE from function output type. | frontend | fixed | repro: `g() orelse fallback` with `g: fn (): RT \| BUBBLE` types without errors |
| [#109](https://github.com/temperlang/temper/issues/109) | Bubble isn't a nominal type so can't be used as an upper bound. | frontend | fixed | repro: `let fb<T extends Bubble>(): T? { null }` is accepted |
| [#110](https://github.com/temperlang/temper/issues/110) | Bubbles create constrained init blocks | tmpl | fixed | repro: top-level lets that may bubble translate to flat statements in Java's static init (try/catch only around the `orelse`), no nested init blocks; module init runs in source order (tmpl notes) |
| [#111](https://github.com/temperlang/temper/issues/111) | continue in orelse counterexample | frontend | fixed | repro: the example runs and logs 1, 2 with no initialization errors |
| [#119](https://github.com/temperlang/temper/issues/119) | Keyword `default` not detected in JS. | backend/js | fixed | repro: a `default` property translates to `#default_` with `get default_()`, no crash |
| [#122](https://github.com/temperlang/temper/issues/122) | Open source license | other | fixed | the new compiler's repo is dual licensed Apache-2.0 or MIT (its README and LICENSE files) |
| [#127](https://github.com/temperlang/temper/issues/127) | Build native image such as with graalvm nativeimage | build | fixed | the new compiler is a native Rust binary |
| [#144](https://github.com/temperlang/temper/issues/144) | Adapt `await` to backends | backend | fixed | notes/kotlin-differences.md async section: funtests control-flow/async, async-waiters, async-broken-early, await-in-loop pass on every backend, Lua included |
| [#153](https://github.com/temperlang/temper/issues/153) | String.hasIndex compiles incorrectly on Python Backend | backend/python | fixed | tempest emits `if not len(s) > 0:`, which Python parses as `not (len(s) > 0)` since comparisons bind tighter than `not`; the output was already correct |
| [#156](https://github.com/temperlang/temper/issues/156) | Connected method call broken into temp assignment | frontend | fixed | Repro: `String.fromCodePoint(message[String.begin]) orelse "nope"` translates to a direct `string_from_code_point(...)` call in Python |
| [#158](https://github.com/temperlang/temper/issues/158) | Need static error message for forward function reference | frontend | fixed | Repro: local functions are visible before their declaration (c() returns 2, d() returns 4); a use of a later non-function local is a static "has not been declared" error |
| [#162](https://github.com/temperlang/temper/issues/162) | Need compiler error for not yet defined functions | frontend | fixed | Repro: g calling a later local function h now works (hoisted); g reading a later `let` gives static error "h has not been declared" |
| [#168](https://github.com/temperlang/temper/issues/168) | Content-based return type inference | typer | fixed | Repro: `noInline { "hi" }` gives "hi" with no error |
| [#178](https://github.com/temperlang/temper/issues/178) | String comparisons not translated | backend/rust | fixed | Repro: `a < b` on strings translates to native `a < b` in Rust (UTF-8 byte order equals code point order) |
| [#183](https://github.com/temperlang/temper/issues/183) | Record inferred type args for casting and new | typer | fixed | Repro: `a as B<Int>` lowers to `(as(a)^): B<Int32>` in tmpl, with type args recorded |
| [#190](https://github.com/temperlang/temper/issues/190) | Bad error for defaulted generic constructor property | frontend | fixed | Repro: `class C<T, U>(public t: T, public u: U? = null) {}` compiles; the `U \| Null` spelling gets "Null has not been declared" |
| [#198](https://github.com/temperlang/temper/issues/198) | Add C++ backend | backend/cpp | fixed | docs/backends/README.md: the new compiler's C++ backend passes every functional test |
| [#203](https://github.com/temperlang/temper/issues/203) | Bad panic handling in be-java | backend/java | fixed | Repro: `o as StringIndex orelse panic()` gives a clean try/catch throwing AssertionError, no unreachable statement |
| [#205](https://github.com/temperlang/temper/issues/205) | Type arg inference fails for properties | typer | fixed | Repro: `class Hi { public a: ListBuilder<Int> = new ListBuilder(); }` compiles |
| [#206](https://github.com/temperlang/temper/issues/206) | Partial type arg inference would be nice | typer | fixed | Repro: `let b: MapBuilder<Int, Boolean> = new MapBuilder<Int>();` compiles with no error |
| [#213](https://github.com/temperlang/temper/issues/213) | Validate no `this` use before init | frontend | fixed | Repro: calling a method from a field initializer errors "Calling this.next() before s is set" |
| [#222](https://github.com/temperlang/temper/issues/222) | be-rust: Comparison to StringIndex.none is bad | backend/rust | fixed | Repro: `i == StringIndex.none` translates to `i == None` |
| [#236](https://github.com/temperlang/temper/issues/236) | Remove backend lib name config from getting started | docs | fixed | tempest's docs/guide/getting-started.md doesn't ask for backend library-name config |
| [#238](https://github.com/temperlang/temper/issues/238) | Add dot autocomplete in repl | repl | fixed | docs/tools/repl.md: Tab completion offers the members of x's type after `x.` |
| [#246](https://github.com/temperlang/temper/issues/246) | Weakened type inference for `[]` | typer | fixed | Repro: `public slots: Mapped<String, Int> = new Map([])` compiles |
| [#264](https://github.com/temperlang/temper/issues/264) | Closure capture inconsistent | language | fixed | docs/internals/detail/04-interpreter.md and kotlin-differences.md: each loop pass gets its own binding in the interpreter and all backends, with tests |
| [#270](https://github.com/temperlang/temper/issues/270) | Disallow == where undefined or across types | language | fixed | Repro: `1 == "2"` is an error ("Actual arguments do not match signature") |
| [#271](https://github.com/temperlang/temper/issues/271) | Rust builders missing type params | backend/rust | fixed | Repro: `Range<Item>` with an unused type param translates to a non-generic Range and RangeBuilder with no stray `Item` |
| [#280](https://github.com/temperlang/temper/issues/280) | Handle arbitrary ignore files in tree | build | fixed | notes/kotlin-differences.md "Ignore files": every .gitignore and .temperignore under the work root is read; test gitignore_files_skip_what_they_list |
| [#283](https://github.com/temperlang/temper/issues/283) | Reduce temper.keep spam for be-java & be-py | build | fixed | tempest writes no temper.keep files yet, so no spam; what it should record is a pending API-compat design |
| [#294](https://github.com/temperlang/temper/issues/294) | Coviarant return types fail on C# lists | backend/csharp | fixed | Repro: a covariant override (`ListBuilder<Int>` for `Listed<Int>`) is now a compile error ("should be things(): Listed<Int32> to correctly override"), so no bad C# |
| [#295](https://github.com/temperlang/temper/issues/295) | Covariant return type problems on Rust | backend/rust | fixed | Same repro as #294: rejected in the frontend, so no bad Rust |
| [#302](https://github.com/temperlang/temper/issues/302) | Rust translator crashes on zero sealed subtypes | backend/rust | fixed | Repro: a sealed interface with no subtypes translates to Rust without error |
| [#359](https://github.com/temperlang/temper/issues/359) | Rust `dependency_on_unit_never_type_fallback` | backend/rust | fixed | tempest's Rust golden for interfaces/property-members has no cast of panic!(); every funtest's Rust passes clippy with -D warnings (temper-be-rust/tests/functional.rs) |
| [#426](https://github.com/temperlang/temper/issues/426) | Lua type annotations | backend/lua | fixed | tempest's Lua output carries LuaLS annotations (---@param, ---@type, ---@cast) and CI runs LuaLS --check on it (notes/tmpl/profiles.md) |
| [#458](https://github.com/temperlang/temper/issues/458) | Broken use before init in constructors | frontend | fixed | tempest repro: an explicit empty constructor reports "Property x/y not initialized in constructor" (Fields first, settle/fields-first.cases) |
| [#459](https://github.com/temperlang/temper/issues/459) | Prevent duplicate constructors | frontend | fixed | tempest rejects each constructor after the first ("A class can have only one constructor…", settle/classes.cases) and reports "Reading this.x before x is set" for the example |
| [#472](https://github.com/temperlang/temper/issues/472) | Cross entry references failing in repl translation | repl | fixed | tempest repl translate(n, "java") includes the earlier inputs n uses, so B's reference to A translates with no export error (kotlin-differences.md, "The REPL"; repro) |
| [#505](https://github.com/temperlang/temper/issues/505) | Incomplete test failure report | tooling | fixed | tempest test -b interp -b py prints every failing test with its message and per-backend tallies (repro with three failing tests) |
| [#520](https://github.com/temperlang/temper/issues/520) | On cpp, an async block never resumes when top-level code completes the promise it awaits | backend/cpp | fixed | tempest's C++ drains the queue when a promise is settled outside any block (runtime change 0005; funtests async-broken-early, await-in-loop) |
| [#528](https://github.com/temperlang/temper/issues/528) | A `let` assigned a constant on only one branch builds without an error and reads as that constant | frontend | fixed | tempest: `let x: Int; if (b) { x = 1; } x` reports "x is not initialized along branches" (repro; kotlin-differences.md, "Definite assignment of locals") |
| [#536](https://github.com/temperlang/temper/issues/536) | A `Void` function or method whose body ends in `panic()` or `bubble()` fails to build on js and rust | backend | fixed | tempest: a Void method ending in bubble() builds on js, keeps the field write, and `orelse` catches it (repro prints caught/7) |
| [#541](https://github.com/temperlang/temper/issues/541) | Regex literals read `{3}` and `{2,3}` as literal text, though `std/regex` documents them as counted repetition | regex | fixed | tempest's own regex parser reads {m}, {m,}, {m,n} as counts (temper-frontend/src/regex.rs, parses_the_dialect); repl /[0-9]{3}/ finds "123" |
| [#549](https://github.com/temperlang/temper/issues/549) | java, rust and cpp crash translating an async block that keeps a `List` local across an `await` | backend | fixed | tempest builds the issue's List-across-await case for java, rust and cpp (locals are cells), and py prints "3 2" (repro) |
| [#559](https://github.com/temperlang/temper/issues/559) | py: a local `var` that holds a function and is reassigned gets `nonlocal` in its own function, and the module fails to import | backend/python | fixed | tempest: a function-holding local var reassigned in its function prints 2 on py (repro, with a declared @fun interface type) |
| [#609](https://github.com/temperlang/temper/issues/609) | `temper run -b py` fails with ModuleNotFoundError for a library whose name has a dash, unless the build records a dependency from that library on another | backend/python | fixed | tempest run -b py of a library named hello-world prints hello (repro) |
| [#618](https://github.com/temperlang/temper/issues/618) | A function's last expression is dropped after a loop that holds both a `return` and a `continue` or `break` | frontend | fixed | tempest: afterContinue([""]) and (["", ""]) return -7 on js (repro) |
| [#620](https://github.com/temperlang/temper/issues/620) | js: `Mapped.getOr` returns the fallback for a key that is present with a null value | backend/js | fixed | tempest js: getOr on a key mapped to null returns null for MapBuilder and Map (repro) |
| [#629](https://github.com/temperlang/temper/issues/629) | csharp: an `if` as the arm of a sealed `when` is emitted unbraced, so the `else throw` that closes the `when` binds to the inner `if`, and the arm's common case throws | backend/csharp | fixed | tempest's C# braces each when arm's if (generated BareIf, repro) |
| [#630](https://github.com/temperlang/temper/issues/630) | js: a std function that a test file imports again is left out of the extracted test file, and the ReferenceError is reported as a bubble | backend/js | fixed | tempest's extracted js test imports parseJson itself (generated test/reimport.js, repro) |

## Close: obsolete

| # | Title | Area | Status | Why |
|---|---|---|---|---|
| [#42](https://github.com/temperlang/temper/issues/42) | Python version check can fail for test on watch with multiple test backends | tooling | n/a | Kotlin JVM file locking in watch's Python version check on Windows; new compiler has no such code and no watch yet; Close as Kotlin-only; reopen against the new compiler if watch shows it. |
| [#63](https://github.com/temperlang/temper/issues/63) | Java naming error when building ingenium | backend/java | n/a | Kotlin be-java name registry crash (vFunction not registered); the new Java backend has different naming; issue #87's similar case translates cleanly; Close as Kotlin-only; reopen with a repro if the library fails to build with the new compiler. |
| [#113](https://github.com/temperlang/temper/issues/113) | Sorted function doesn't always get declared | tmpl | n/a | Kotlin tmpl declaration placement, never reproduced; the new compiler's tmpl is a rewrite; Close; reopen with a repro against the new compiler. |
| [#117](https://github.com/temperlang/temper/issues/117) | Python backend: Pip uses global install for mypy | backend/python | n/a | the new compiler has no mypyc backend and installs nothing with pip; Close; if mypyc returns, open a new issue for tool installation. |
| [#118](https://github.com/temperlang/temper/issues/118) | Crash from Currents on temper build -b js | tooling | n/a | Kotlin Currents thread pool race; not in the new compiler; Close as Kotlin-only. |
| [#125](https://github.com/temperlang/temper/issues/125) | Stabilize temper watch and langserver | tooling | n/a | about Kotlin's watch and language server (JVM memory and CPU); the new compiler has a different language server and no watch yet; Close; open specific issues for the new language server and watch as they come up. |
| [#133](https://github.com/temperlang/temper/issues/133) | Java sometimes misses output | build | n/a | Intermittent missing Java output in Kotlin's test harness (Maven temp dirs); tempest's Java runner is separate code; Comment that this was a Kotlin test-harness flake; reopen a fresh issue if tempest's Java runs ever show it. |
| [#149](https://github.com/temperlang/temper/issues/149) | Python names registered by `PyTranslator.request` aren't visible to DocGen | docs | n/a | About Kotlin DocGen and PyTranslator.request internals; tempest has no doc generator yet; Close; doc generation in the new compiler will be its own design. |
| [#175](https://github.com/temperlang/temper/issues/175) | Side error in temper build: "FileContentStore: Callback with listing" failed | build | n/a | Kotlin FileContentStore race; tempest's driver doesn't share that code; Close as Kotlin-only. |
| [#186](https://github.com/temperlang/temper/issues/186) | Problems with typer plan initializer finding | typer | n/a | About Kotlin typer's findInitializers internals; Close as Kotlin-only. |
| [#245](https://github.com/temperlang/temper/issues/245) | CSharpTranslator fails to translate TList | backend/csharp | n/a | Crash in Kotlin's CSharpTranslator with no repro; Close; reopen with a repro if the new compiler's C# backend shows it. |
| [#253](https://github.com/temperlang/temper/issues/253) | Checklist: open source the things | other | n/a | Open-sourcing checklist for the Kotlin repo; only walkthrough docs remain; Close; track any remaining walkthrough docs under the docs move to the new compiler. |
| [#266](https://github.com/temperlang/temper/issues/266) | Organize temper-core name and version better | build | n/a | About constants in Kotlin's code base; Close as Kotlin-only. |
| [#285](https://github.com/temperlang/temper/issues/285) | Jansi warning on newer java | build | n/a | JVM/Jansi warning; the new compiler is a native binary; Close as Kotlin-only. |
| [#287](https://github.com/temperlang/temper/issues/287) | Temper repl can run only once at a time | repl | n/a | Kotlin's Sleepycat snapshot store lock; tempest's REPL keeps only a plain history file; Close as Kotlin-only. |
| [#435](https://github.com/temperlang/temper/issues/435) | Try java 25 aot caching | build | n/a | the new compiler is a native Rust binary; JVM startup and AOT caching no longer apply; Close: Kotlin/JVM distribution only; the new compiler ships as a native binary. |

## New compiler bugs found while triaging

Found while reproducing the issues above; each should get an issue
(or join the related one) after the switch:

- Rust: an immediately invoked closure in statement position comes out
  as `{ ...; Arc::new(move |k| ...) }(i);`, which rustc rejects (E0308)
  (related: #223).
- A user class named `Type` is shadowed by core's `Type`; `new Type()`
  gets no frontend error and fails in translation (#250).
- With `class D extends B & C` where C has a default `f`, `new D().f()`
  is a "No callee matches" error; JS output also emits abstract `f` as a
  field on the interface classes (#324).
- `let a = null` gets an unknown type and fails in translation (#160);
  `Null` isn't recognized as a type name (`Int | Null`), though `Int?`
  works.
- Duplicate top-level functions and duplicate classes get no frontend
  error (Java renames the second class).
- `var f(...) { }` gives the unclear "Use of builtin @ is malformed";
  `var q = h` for a generic `h` makes `q(1)` a type error (#43).
- `new (class CC {})()` fails with an empty name (#89).
- Interpolating a Regex value into `rgx"..."` fails at run time (#33).
- `when` over every subtype of a sealed interface still needs `else`
  (#25).
- A class instance as a map key fails only at run time; `class ML
  extends Listed<Int> {}` is accepted silently (#29, #28).
- A bad `in:` label in `config.temper.md` builds with exit 0, though the
  same code in a `.temper` file is an error (#91).
- An `await` in a plain function fails only with internal translation
  codes rather than a located error (#521).
- C++ output for a library named `time` clashes with the C function
  (#612).
- Python leaves a protected getter un-overridden by a public one (#341).
- Generated `pyproject.toml` has `readme = {text = "n/a"}` (#74).
- Thousands of errors from one bad input aren't capped (#102).

