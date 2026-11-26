# Host-facing studies: a cross-backend summary

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

This summarizes the seven backend studies beside it, read against
the [initial thoughts](claude-initial-thoughts.md) for #676 and
[#677's](../../677-temper-keep/tom/claude-initial-thoughts.md). The
studies have the evidence; this file has verdicts, shared fixes,
settled contradictions, and an order of work.

## The short version

- **Every backend compiles and runs the six showcase libraries'
  tours**, apart from Python, where a 2026-11-18 runtime change broke
  three of them. None reads as a native library yet, for the same
  few reasons everywhere: failures with no message; values with no
  equality, hashing, or debug form; docs dropped; and packages that
  can't be published or installed as users expect.
- **Five backends have bugs that lose data or memory safety** when a
  callback changes the collection it walks, or when a library keeps a
  list the caller still holds. C++ reads freed memory, Rust deadlocks,
  JS freezes the caller's array, and C# and Java lose changes made
  during a sort or a map walk without a word.
- **Java and C# silently drop generated code** when a class is named
  like the module class (`<Lib>Global`) or, in C#, `Logging`.
- **The closest to idiomatic** are Python (shape) and Java (behavior
  and speed); the furthest are C++ (nothing hidden or immutable) and
  Rust (reads as a port, with locks everywhere).
- **Most fixes are additive;** the breaking ones group into five
  RFC-sized themes (see the order of work).

## Verdicts by backend

**Lua.** The shape is close: modules are tables, classes callable,
properties read like fields, lists are 1-based tables, and callbacks
are plain functions. Biggest strength: lists map straight onto Lua
tables, both ways. Biggest gap: no-value is the truthy `temper.null`,
so `if x then` passes for every result, and five of six tours import
the runtime to undo it; close behind, the rockspecs install nothing
`require` finds, and the code doesn't parse on PUC Lua 5.1 though the
rockspecs claim it. Loops run 5 to 16 times slower than hand-written
Lua, and `orelse` 12 to 300 times. ([study](claude-lua-study.md))

**Rust.** Memory safe, `Send + Sync`, clippy-clean, and plain loops as
fast as `iter().sum()`. But it reads as a port: `Arc<String>`,
`Arc<Vec<T>>`, and `Arc<dyn Fn + Send + Sync>` in signatures, no
`Debug`, `Eq`, or `Hash` anywhere, an interface users can implement
only through a macro and an undocumented tuple-struct rule, and a lock
per mutable field, which loses updates across threads, costs 10 to 50
times a plain field, and deadlocks in two `ListBuilder` cases. Biggest
strength: safety and loop speed. Biggest gap: the interface and
thread model. ([study](claude-rust-study.md))

**C++.** Compiles warning-free on g++ 12 to 14 from C++14 to C++23,
and calls read plainly. But nothing is immutable or hidden: every
field (717 of them private in Temper) is a public data member, statics
and module values are writable slots, private constructors are public,
115 internal classes sit in public headers, and `temper::core` appears
1,872 times. Panics end the process while reporting a bubble, output
is lost on an uncaught bubble, nothing builds under `-fno-exceptions`,
and five runtime functions read freed memory when a callback changes
the list. Biggest strength: portability across standards and
compilers. Biggest gap: the object model, which needs a revamp RFC.
([study](claude-cpp-study.md))

**Python.** The most idiomatic surface: snake_case, properties,
keyword constructors, tuples and `mappingproxy`s out, ABCs that Python
classes subclass, and annotations clean under pyright and mypy strict.
Biggest strength: typing and nullability (`T | None`, real `None`).
Biggest gaps: no `py.typed`, so installed libraries are `Any` to mypy;
no `__hash__` or `__repr__`; positional-only functions; and `Bubble`,
which since a 2026-11-18 runtime change is no longer a
`RuntimeError`, so three tours crash. ([study](claude-python-study.md))

**JavaScript.** At run time, mostly native: plain ES modules on Node,
Bun, Deno, and browsers, frozen arrays, `Map`s, `bigint`s, options
objects for long constructors, and loops within 2 times of hand-written
code. Biggest strength: runtime fit and speed. Biggest gap:
TypeScript, since no `.d.ts` ships (`TS7016`, or silent `any`). Worst
bug: `filter` that keeps everything freezes the caller's array.
([study](claude-js-study.md))

**Java.** The best runtime behavior: `java.util` collections,
`java.util.function` callbacks, interfaces with `default` methods that
take lambdas, `orelse` catching only Temper's failures, unmodifiable
results, and hot loops as fast as hand-written Java. No tour imports
`temper.*`. Biggest gaps: no `equals` or `hashCode`, failures with
neither message nor stack trace, nullness that Kotlin can't read, POMs
stock Maven can't build, and two compiler bugs that matter beyond
style: a class named `<Lib>Global` silently replaces the module's
functions, and some public statics aren't `final` (Kelpto's default
sanitizer policy can be reassigned). ([study](claude-java-study.md))

**C#.** A near-idiomatic surface: PascalCase, `I`-prefixed interfaces,
properties, optional parameters, `Func`/`Action`, covariant
`IReadOnlyList<T>`, `Task<T>`, `IEnumerable<T>`, read-only statics, and
nullable annotations the compiler checks. Biggest strength: nullable
reference types done right. Biggest gaps: no `Equals`/`GetHashCode`,
classes not `sealed`, private constructors public, generators that
can be walked once, failures that cost 10 µs each and say only
`Exception of type 'TemperLang.Core.Bubble' was thrown`, and
`TemperLang.Std` pulling MSTest and 4.6 MB of test platform into every
program. ([study](claude-csharp-study.md))

## Comparison

"Callback mutation" gives the five cases of the
[full table](#callback-mutation-semantics) in order; "exc." is a host
exception that passes `orelse`.

| | Equality, hash | Printing | Failure messages | Panics vs bubbles | Nullability | Lists in / out | Callback mutation | Name collisions | Docs | Packaging | Speed vs hand | Runtime in API |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Lua | none, even for `@auto("==")` | `table: 0x…` | `Bubble` | distinct; panic is the string `panic` | truthy `temper.null` | kept / alias library state | 12, 2, 30, 3, 8 | `global` unreserved (5.5) | types only (LuaCATS) | rocks install nothing; 5.1 doesn't parse | 5–16× (5.4) | `temper.null`, `instance_of`, `temper.type` |
| Rust | `PartialEq` on 15; no `Eq`, `Hash` | no `Debug` | `bubble` | distinct (`panic!`) | `Option`, but `None::<&str>` | immutable `Arc<Vec>` | 12, panic, 1, 3, deadlock | inherent `to_string` beside `Display` | none | exact pins break resolution | ≈1× loops; 10–50× fields | `temper_core::Result`, `ToArcString`, macro |
| C++ | `eq`; `==` compares pointers | no `<<` | `bubble` | panic reported as a bubble, uncatchable | `NullableParam<T>` | kept / writable | UAF, past end, early stop, `out_of_range`, UAF | shared init names; `make` | none | no install or export | not measured; slow builds | `temper::core` ×1,872 |
| Python | `__eq__` on 15; unhashable | default repr | `''` | panic a bare `BaseException` | `T \| None` | kept / tuples | 1299, 2, exc., exc., exc. | soft keywords escaped | none; no `py.typed` | good, but exact `.dev` pins | 3–8× | `Bubble`, `Pair` |
| JS | `eq` on some | `Url {}` | `""` | `orelse panic()` swallows host errors | `null`; TS rejects `undefined` | not copied / frozen, but `filter` freezes input | 12, 3 (with `undefined`), 30, 3, 7 | 111 runtime names escape exports | none; no `.d.ts` | no `version`; runtime not on npm | 1–2× | `Pair`, `type()` |
| Java | `eq` on 15; no `equals` | `Cls@hash` without `toString` | none, no stack | panic `AssertionError`, cause lost | `@temper.core.Nullable` | kept / unmodifiable | 1299, exc., 1, exc., exc. | `<Lib>Global` overwritten; `getClass` | none | stock Maven fails | ≈1× | `Bubble`, `@Nullable` |
| C# | `Eq` on 15; no `Equals` | type name | placeholder text | `Panic : Exception`, cause lost | NRT right; `Optional<T>` | kept / immutable (slow) | exc. ×4, then 3 (dropped) | `<Lib>Global`, `Logging` overwritten | none | `Package Description`; std ships MSTest | 2–5× loops; 10 µs/failure | `Optional<T>`, `Bubble` |

## Cross-backend patterns, as shared fixes

### Memory safety and data loss in the runtimes

**Fix:** no runtime function holds a lock, an iterator, or a range-for
across a user callback; each either walks a snapshot or indexes to the
live length through a checked read, and detects changes it can't
honor. Plus the one-line fixes that lose data without any callback.

| Backend | Bug | Evidence |
|---|---|---|
| C++ | `reduceFrom`, `sort`, `map`, `reduce`, and `Mapped::forEach` read freed or out-of-range memory | [C++ §5](claude-cpp-study.md#5-memory-safety) |
| Rust | `ListBuilder.sort` and `addAll(self)` deadlock; a panic in `sort` poisons | [Rust §2](claude-rust-study.md#re-entrancy), A2 |
| JS | `filter` keeping everything freezes its input; `map` stores `undefined` | [JS §3](claude-js-study.md#lists-and-maps), bugs 13 and 16 |
| C# | `sort` drops what its comparison adds; generators walk once | [C# §8](claude-csharp-study.md#8-cross-backend-patterns-checked-for-c), bugs 3 and 6 |
| Java | map `forEach` that adds keys stops without a word; public statics not `final` | [Java patterns](claude-java-study.md#cross-backend-patterns-checked-for-java), bugs 3 and 8 |
| Rust | class `var` updates lose writes across threads | [Rust §2](claude-rust-study.md#shared-across-threads-but-not-atomic) |

Not breaking, and first: any memory-safe behavior beats today's.

### Callback mutation semantics

The five probes, with the interpreter and Rust rows checked for this
summary (same build as the studies, `13dc5669`):

| Case | Interpreter | Rust | Lua 5.4 | JS (Node 24) | Python | Java | C# | C++ |
|---|---|---|---|---|---|---|---|---|
| `reduceFrom` growing `b` | 12 | 12 | 12 | 12 | 1299 | 1299 | exc. | use after free |
| `map` shrinking `b`, length | 3 | panic: index 2 out of bounds | 2 | 3, ending `undefined` | 2 | exc. | exc. | 3, reading past the end |
| map `forEach` adding keys | 1 | 1 | 30 | 30 | exc. | 1 | exc. | stops early by luck |
| map `forEach` removing a later key | 6 | 3 | 3 | 3 | exc. | exc. | exc. | `std::out_of_range` |
| `sort` growing `b`, length | 3 | deadlock | 8 | 7 (6 on Bun, Deno) | exc. | exc. | 3, additions dropped | use after free |

Snapshot results are 12, 3, 1, 6, and 3; live results are 1299, 2, 30,
and 3 (sort has no live answer). The interpreter is a consistent
snapshot; core's own `reduceFromIndex` body is live (1299); every
compiled backend mixes the two or throws its host's exception, which
`orelse` and `Test.assertPanics` both miss.

**Options**, per operation:

| Option | Gains | Costs |
|---|---|---|
| A. Live length (index to the current length, checked reads) | Cheapest; matches core's `reduceFromIndex` and Python, Java for `reduce` | Results depend on where the change happens; sort has no sensible live answer |
| B. Snapshot (walk a copy) | Deterministic; matches the interpreter, and JS, Lua, Rust for `reduce` | A copy per call on builders (a `List` can't change, so it needs none) |
| C. Panic on change (a version counter checked after each callback) | Bugs surface where they happen; matches what Python, Java, and C# half do | A counter per builder; code that worked by accident starts panicking |

Temper currently leans to C for `sort` (the Rust study's fix panics
"`ListBuilder` changed length during sort", as Python raises), and to
memory safety everywhere first. Whether `forEach`, `map`, `filter`, and
`reduceFrom` take A, B, or C is open, and belongs to
[#671](https://github.com/temperlang/temper/issues/671), since these are
core's methods and core's docs already say a `Listed` "shouldn't be
modified concurrently". Whatever it picks, two rules hold for every
backend: a violation is a Temper panic, never a host exception that
passes `orelse`, and never a silent loss (Java's early stop, C#'s
dropped additions). Breaking only for code relying on a host's
accident.


### Generated-name collisions as errors

**Fix:** two generated host names that collide, or a generated name
that collides with something the host owns, is a build error naming
both declarations; never an overwrite, a silent rename of public API,
or uncompilable output.

| Backend | Today | Evidence |
|---|---|---|
| Java | `<Lib>Global` class replaces the module's functions; `getClass`, `wait`, `notify`, and `getX` beside `x` don't compile; a Temper `equals` overloads | [Java §3](claude-java-study.md#module-functions-global), bugs 1, 2, and 12 |
| C# | `<Lib>Global` and `Logging` replace generated files; members named for `object`'s hide rather than override | [C# §3](claude-csharp-study.md#module-classes-global-and-types-named-like-namespaces), [§8](claude-csharp-study.md#names-clashing-with-object) |
| C++ | modules whose paths end alike share an init function; `make` escaped for every name; a library named `all` | [C++ §7](claude-cpp-study.md#7-naming-and-api-idioms), [initial thoughts](claude-initial-thoughts.md#leaks-today) |
| JS | exports named like 111 runtime helpers get `_` (`from_`, `empty_`), so the runtime's names shape the API | [JS §3](claude-js-study.md#names) |
| Lua | `global` isn't reserved (a syntax error on 5.5) | [Lua bugs](claude-lua-study.md#bugs-found), 12 |

The silent overwrites are fixes (not breaking; they only turn lost code
into an error). Which names to escape and how (JS's helper names, Python
soft keywords, Java's `to` and `with`) is breaking and belongs to #676.

### Failure messages

**Fix:** every bubble carries a message: the runtime's own (the key for
`Map.get`, the text for a parse, "division by zero"), and for an
explicit `bubble()` in an exported function at least the function's
name. Temper code can't read a bubble's message, so only host-side text
changes.

All seven backends print nothing useful: `Bubble` (Lua), `bubble`
(Rust, C++), `''` (Python), `""` (JS), `null` (Java), and the
framework placeholder (C#). Java adds no stack trace, so an escaping
failure prints one line. Evidence: [Lua §3](claude-lua-study.md#3-errors),
[Rust errors](claude-rust-study.md#errors), [C++ §4](claude-cpp-study.md#4-errors-and-panics),
[Python §4](claude-python-study.md#4-errors), [JS §4](claude-js-study.md#4-errors),
[Java §4](claude-java-study.md#4-errors), and [C# §4](claude-csharp-study.md#4-errors).

Not breaking. Python's `Bubble(Exception)` should go back to
`Bubble(RuntimeError)` with it, which fixes three tours and what
`notes/api-compat.md` promises. Library-named failure types are
[#164](../../164-exceptions/README.md).

### Panics that look like bubbles, or swallow causes

**Fix:** a panic says it's a panic, carries what it replaced as its
cause, and never catches or hides a host exception.

C++ calls `std::terminate` inside the `catch` that `orelse` became, so
the crash report names `TemperBubble` ([C++ §4](claude-cpp-study.md#4-errors-and-panics));
JS compiles `f() orelse panic()` to a catch-all, so a `TypeError` in a
user's callback becomes `Error: panic` ([JS §4](claude-js-study.md#4-errors), bug 7);
Java and C# drop the bubble a panic replaces, and the host's own index
exception ([Java §4](claude-java-study.md#4-errors), [C# §4](claude-csharp-study.md#4-errors));
Python raises a bare `BaseException("panic")` with the bubble only as
context ([Python §4](claude-python-study.md#4-errors)).

Not breaking. The panic's host type (Python `BaseException` or
`Exception`, Java `AssertionError`, which JUnit reports as an
assertion failure, C# `Exception`, which `catch (Exception)` catches,
and whether C++ panics are recoverable) is #164's panic question.

### Equality, hashing, and printing from `@auto("==")`

**Fix:** for `@auto("==")` classes, generate the host's equality and
hash from the same fields (`equals`/`hashCode`, `Equals`/`GetHashCode`
with `IEquatable<T>`, `__eq__` with `__hash__`, `PartialEq` with `Eq`
and `Hash` where no field is a float, `operator==` in C++, `__eq` in
Lua), keeping `eq`. Hashing the same fields agrees with `==` by
construction ([Rust A14](claude-rust-study.md#a14-eq-and-hash-recommendations-16-and-21)).
A hand-written `eq` (Hrefine's `Url`) stays on identity hashing until
Temper has a `hash` to pair with it. Plus a debug form for every class:
`Debug` in Rust, `__repr__` in Python, an inspect hook in JS, `__name`
in Lua, `operator<<` in C++, and a generated `toString` in Java and C#
where Temper has none.

Same 15 classes everywhere, hashable nowhere (Python's are actively
unhashable) ([Python §2](claude-python-study.md#__repr__-__eq__-and-__hash__),
[Java §2](claude-java-study.md#equals-hashcode-and-tostring),
[C# §2](claude-csharp-study.md#equals-gethashcode-and-tostring),
[Rust traits](claude-rust-study.md#common-traits), [C++ §3](claude-cpp-study.md#objects)).

Additive. Two questions need deciding once for all backends: the
printed format (users will parse it, so it's API, recorded with
#677), and a Temper-level hashing rule for hand-written `==`, which
fits [#670](../../670-type-associated-operators/README.md)'s
type-associated operations. Records and enums wait on
[#668](../../668-value-types/tom/claude-value-types.md).

### Defensive copies at the boundary

**Fix:** where an exported constructor or function *stores* a `List`
argument (a field, a module value, a closure that outlives the call),
convert it with the runtime's existing "copy unless it's ours" helper
(`listedToList` and its kin); where a getter typed `Listed` returns a
builder the library holds, return a snapshot or a read-only view that
can't be cast back. Calls inside the library pay nothing.

Affected: Python, Java, C#, and C++ keep the caller's list, so
Chromarite's "immutable" `Color` changes when the caller's list does;
Lua and C++ return library-held lists writable; JS, Java, and C# leak
held builders through `Listed` getters ([Python §2](claude-python-study.md#immutability),
[Java §2](claude-java-study.md#immutability-and-aliasing),
[C# §2](claude-csharp-study.md#immutability-and-aliasing),
[C++ §1](claude-cpp-study.md#1-immutability),
[Lua §1](claude-lua-study.md#lists), [JS §3](claude-js-study.md#lists-and-maps)).

Not breaking in Temper's terms (it's what `List` promises); one copy
per stored list from host callers. A cross-backend rule, so it goes
with collection semantics.

### Docs and editor types on every backend

**Fix:** emit each declaration's doc, which Temper's IR already keeps,
in each host's form: `///` and `//!` with "# Errors" and "# Panics"
(Rust), docstrings (Python), Javadoc with `package-info.java` (Java),
XML docs with `GenerateDocumentationFile` (C#), JSDoc prose (JS), `---`
prose (Lua), and Doxygen-style comments (C++). Plus the type
declarations each ecosystem reads: `py.typed`, `.d.ts`, and LuaLS
fixes (nullable parameters accepting `nil`, constructors as
`@overload`, a complete runtime meta file).

Zero doc comments reach any backend's output today (C++, which its
study didn't cover, was checked for this summary). Java's doclint
finds 39 to 1,015 missing comments per library, C# 1,684 CS1591s
([Java §6](claude-java-study.md#6-javadoc), [C# §6](claude-csharp-study.md#6-xml-docs),
[Python §7](claude-python-study.md#7-docs-and-editors),
[JS §1](claude-js-study.md#1-types-and-editors),
[Lua §6](claude-lua-study.md#6-docs-and-editor-support),
[Rust §4](claude-rust-study.md#4-crate-packaging)).

Additive: one shared piece (`[n]` references per host), one printer each.

### Packaging metadata and runtime versions

**Fix:** every package carries the config's prose as its description,
a real version, license entries in the host's current form,
repository and homepage when known, no tests, and nothing that runs
on install; dependencies on the runtime are ranges, not exact pins;
release-only steps (signing, publishing) sit in a release profile.

| Backend | Worst problem | Evidence |
|---|---|---|
| Lua | `build.modules` empty, so `require` fails after install | [Lua §4](claude-lua-study.md#4-modules-and-packaging) |
| Rust | `=` pins on `indexmap` and others fail users' resolution; a test `main.rs` | [Rust §4](claude-rust-study.md#4-crate-packaging) |
| C++ | no `install()`/`export()`; tests and demos in `all`; one runtime copy per output | [C++ §6](claude-cpp-study.md#6-packaging-and-builds) |
| Python | no `py.typed`; uv refuses exact `.dev` pins | [Python §5](claude-python-study.md#5-packaging) |
| JS | no `version` (`npm pack` fails for five of six); runtime 0.7 not on npm | [JS §2](claude-js-study.md#packagejson) |
| Java | stock `mvn install` fails (JDK 8 toolchain, gpg); malformed gpg config | [Java §5](claude-java-study.md#5-packaging) |
| C# | std depends on MSTest (4.6 MB in every program); `Package Description` | [C# §5](claude-csharp-study.md#5-packaging) |

Mostly additive. Ranges need a runtime compatibility promise within a
minor version. Package coordinates (`groupId`, NuGet prefixes) are #676.

**Host versions to support** belong here too. For Lua, the studies
covered 5.1, 5.4, and LuaJIT; **Lua 5.5** is out now and should join
them: it reserves `global` (a name the backend doesn't yet avoid, so
generated code can fail to parse), and its other changes need a look
against the runtime and the tests' framework (LuaUnit 3.5 is the
current release). The same question applies to every backend: which
host versions each promises, stated in the docs and tested in CI.

### Logging

**Fix:** a library never writes to stdout unconditionally. What it logs
(`console.log`, `getConsole(name)`) goes through the host's standard
logging facility where one exists, or through a sink the host can
replace where none does, with no heavy dependencies.

| Backend | Today | Proposed |
|---|---|---|
| Python | `logging.getLogger(name)`, `INFO` | as is |
| Java | `java.util.logging` | as is (no dependency; SLF4J users bridge with `jul-to-slf4j`; `System.Logger` needs Java 9, above the Java 8 floor) |
| C# | `Microsoft.Extensions.Logging` via `Logging.Init(ILoggerFactory)` | `…Logging.Abstractions` only, and setup on a member that can't collide with a user's `Logging` ([C# §3](claude-csharp-study.md#module-classes)) |
| Rust | `println!` | the `log` facade (`log::info!`), so the host picks the logger |
| JS | `console.log` | a documented, settable sink per library, `console` by default |
| C++ | a `std::function` sink, `std::cout` by default | the sink documented and settable; stderr by default |
| Lua | `temper.log`, which prints | a documented, settable sink, `print` by default; optionally a LuaLogging adapter |

Open question: should `console.log` in a library default to logging at
`INFO` (as Python does) or to silence, with a program's `main` keeping
today's printing?

### Runtime names in public APIs

**Fix:** users never import or name the runtime (#676's principle 3).
Each leak gets a library-owned or host-native replacement:

| Backend | What users name today | Replacement |
|---|---|---|
| Lua | `temper.null`, `null_to_nil`, `instance_of`, `temper.type` | `nil` at scalar boundaries, `lib.null` in lists; `Shape.extend{…}`; `Output.is(x)` |
| Rust | `temper_core::Result`, `Error`, `cast`, `impl_any_value_trait!` | per-crate `Result`/`Error` re-exports, typed `downcast`, an adapter trait |
| C++ | `TemperBubble`, `temper::core::Str`, `NullableParam`, `Mapped::Ordered` | library aliases, `std::optional`, a `Map` type (the revamp) |
| Python | `temper_core.Bubble`, `Pair` | library failure types (#164); `Pair` as a `NamedTuple` or tuple |
| JS | `Pair` from `@temperlang/core`, `type()` | accept `[key, value]` arrays; interfaces subclassable directly |
| Java | `temper.core.Bubble`, `@temper.core.Nullable` | #164's types; JSpecify |
| C# | `Optional<T>` (`.OrNull()`), `Bubble`, public runtime extension methods | `Try…` members; `internal` extensions; #164's types |

Mixed: re-exports and extra accepted forms are additive; changing
signature types (Lua null, C++ aliases) is breaking. The principle and
the list of what a library re-exports belong to #676.

### Smaller shared patterns

- **Arguments unchecked at the boundary:** `Int` wraps silently in Lua,
  Python, and JS; non-null parameters aren't checked in Java and C#.
  Checks at exported entry points (range, `requireNonNull`,
  `ThrowIfNull`) are cheap and change only wrong calls. Not breaking.
- **Translation overhead in loops:** helper calls per index and per
  add in Lua and Python (5 to 16 and 3 to 8 times), locks in Rust,
  `ImmutableList` indexing in C#, `orelse` via `pcall` in Lua and via
  thrown exceptions in C# and JS. Plain arithmetic where ranges allow
  is already planned; add inlined indexing, `for x in xs`, and
  non-throwing internal paths for bubbles `orelse` catches. Not
  breaking.
- **Multi-library names:** Kelpto ships as `kelpto-md`, `kelpto_md`,
  or `kelpto-md/kelpto_md`, where hosts expect `kelpto.md`. #676.

## Contradictions between studies, settled

1. **Python's `reduceFrom`.** The C++ study lists Python with the
   backends that "iterate a snapshot" and give 12; the Python, JS, Java,
   and C# studies report 1299. **Checked:** Python gives 1299 (live,
   through `functools.reduce` over the live list). The C++ study's line
   is wrong for Python only.
2. **The interpreter and Rust.** The C++ study also lists both as
   giving 12, unchecked elsewhere. **Checked:** both give 12. The
   interpreter is a snapshot in all five cases (12, 3, 1, 6, 3); Rust
   isn't (it panics in `map`, skips the removed key, and deadlocks in
   `sort`).
3. **Java's "silent stop" when map `forEach` adds keys.** The Java study
   calls Java's 1 a silent early stop; the interpreter and Rust also
   give 1, because the map started with one key. So 1 is also the
   snapshot answer. **Settled:** Java's result is wrong only under a
   live or panic contract; it stays a bug in practice, since Java isn't
   a snapshot elsewhere (it throws when a key is removed).
4. **C#'s "dropped" sort additions.** The C# study calls its 3 a silent
   loss; the interpreter also gives 3, since a snapshot sort ignores
   what the comparison adds. **Settled:** correct under a snapshot
   contract, a bug under the panic contract Temper leans to for `sort`.
5. **JS's `map` length 3.** Same length as the interpreter, different
   contents: JS's list ends in `undefined`, in a list typed `number[]`.
   A bug under any contract.
6. **Counts** of `toString` classes (34 or 35) and public types (160 to
   180) differ by what each study counted; immaterial. Nothing else
   conflicts: immutability, aliasing, and speed figures agree.
7. **Studies against other docs:** `notes/api-compat.md` (Python's
   `RuntimeError`), #164's Java and C# translations (Java 8, "catches
   every exception"), and `docs/backends/README.md` (C#'s `IList`
   overloads) are out of date; those docs need the edits.

## Suggested order of work

### 1. Quick wins (not breaking)

In this order, since the first two lose data or code without a sound:

1. **Memory safety and data loss:** C++'s runtime loops (one sanitized
   change), Rust's `ListBuilder` deadlocks and atomic `+=`, JS's
   `filter`, C#'s generators and `sort`, Java's non-final statics and
   map walk; plus Python's `Bubble(RuntimeError)` regression, which
   breaks three tours today.
2. **Silent name collisions:** `<Lib>Global` and `Logging` overwrites
   (Java, C#) become errors; Java names that don't compile
   (`getClass`, `wait`, `notify`, `getX`) and C#'s `object` members are
   escaped or rejected; Lua reserves `global`.
3. **Messages:** bubble messages on all seven; panics with causes; JS
   `orelse panic()` rethrows host errors; C++ panics outside `catch`,
   with output flushed.
4. **Packaging:** Lua `build.modules` and 5.1 parsing; Rust without
   `main.rs`; npm `version` and `files`; Maven release
   profile and gpg fix; std without MSTest; CMake `install`/`export`;
   metadata from the config everywhere.
5. **Docs:** doc comments on every backend, plus `py.typed`, LuaLS
   annotation fixes, and editor-visible JS types at default settings.
6. **Values:** equality and hash from `@auto("==")`, and debug forms
   (Rust `Debug` first, since the orphan rule stops users adding it).

### 2. Themed medium changes

Each a bounded change with its own tests:

- **Boundary hygiene:** defensive copies of stored lists, read-only
  views of held builders, `Int` range and null checks at entry points.
- **Host typing:** `.d.ts` written by the JS backend; JSpecify for Java;
  nullable context in `TemperLang.Core`; Python `Mapping` parameters and
  keyword-capable optional parameters (their names then recorded as
  API, #677).
- **Speed:** loop lowering (Lua, Python), `orelse` without `pcall` or
  stack capture, Rust local builders and `const`s, C#
  `ReadOnlyCollection`, JS `/* @__PURE__ */` and lazy tables.
- **Runtime versions:** a compatibility promise within a minor version,
  then ranges in every package format, and one shared runtime per
  build (C++, Rust by path).
- **The collection contract,** once #671 decides it: one change per
  runtime, each with the five probes as tests.

### 3. Breaking changes, as RFC-sized themes

| Theme | RFC | Contents |
|---|---|---|
| Host-facing names | #676 | Module class names (`blah.Blah` in Java, a better suffix or chosen name in C#), the type-named-like-module ban, the naming mechanism, escape rules, package coordinates, dotted multi-library names, and which runtime types libraries re-export |
| Failure types | #164 | Library-named failures with messages, panics' host types, nullable twins kept, Lua `nil, failure` with null settled together, C++ `expected` and `-fno-exceptions`, stack policy (Java, JS, C#) |
| C++ revamp | new | Private and `const` state, `detail` and out-of-header internals, `List` distinct from `ListBuilder`, a `Map` type, library aliases, version-adaptive `optional`/`expected`, packaging; outline in [C++ study](claude-cpp-study.md#outline-for-a-c-backend-revamp-rfc) |
| Rust-idiomatic variant | new | Thread model (one lock per object, or single-threaded `Rc`), plain traits users implement, `&str`/`Arc<str>`, slices, `impl Fn` callbacks, `usize` indexes, no inherent `to_string`, as one opt-in variant ([Rust 23](claude-rust-study.md#recommendations)) |
| Collection semantics | #671, or new | Callback mutation contract, the defensive-copy rule, `List` versus `ListBuilder` in every host, map iteration order, and Lua maps as plain tables |

### Construction that stays compatible

Adding a constructor parameter breaks host callers wherever construction
is positional and the host has no named or default arguments (Java,
Rust, C++, JS without the props form, Lua). Temper itself already builds
objects by name, through object literals (property bags). A policy to
consider: exported classes expose **named construction only** (the
existing builders for Java and Rust, JS's `static new(props)`, keyword
arguments where the host has them), with a positional constructor only
when a class asks for one. Builders already exist for public
constructors with two or more parameters, so this mostly removes an
entry point rather than adding code. Rust has no overloading; its usual
tools are builders, `impl Into<Option<T>>` parameters, and struct
literals with `..Default::default()` (which needs a `Default`, so it
fits only classes whose properties all have defaults). Watch generated
size: no new code per class beyond today's builders.

## Shared decisions, per-backend proposals, and PRs

Much of this is common to every backend, and is best decided once:
the cross-backend patterns above (generated-name collisions as errors,
runtime memory safety and callback mutation, failure messages and
panics, equality, hashing, and printing, defensive copies, docs and
editor types, packaging metadata and supported host versions, logging,
and runtime names in public APIs). What remains is each host's own
idioms: C++'s immutability and CMake packaging, C#'s nullable reference
types, Rust's ownership in signatures, Lua's packaging, and so on.

So a suggested shape:

1. **#676 proper** states the principles and the shared decisions.
2. **One appendix per backend** proposes that host's idioms, building on
   the shared decisions (the per-backend studies are their starting
   points).
3. **PRs follow where the fix lives:** a themed PR across all backends
   when the fix is in shared code (tmpl or the frontend, as for the
   name-collision check), and one PR per backend (or a few themed ones)
   applying the shared decisions plus its appendix when the fix is in
   that backend. Each PR is bounded and themed, with its own tests.

## What #676 should decide, and what goes elsewhere

**For #676 (host-facing names):**

- The module class: Java's `blah.Blah` with the type-named-like-module
  ban (and std's `Regex` renamed), C#'s default (`…Functions` or
  `…Module`) and chosen facade names.
- The naming mechanism (decorators, a naming file, or both) and its
  per-backend reach: facade names, Python module names, crate names,
  Rust interface trait names (`Listen` beside `ListenerTrait`), the
  options-object factory (`new`, `from`), and C#'s `Async` suffix.
- Escape policy: escape only real keywords, never runtime helper names
  (JS), soft keywords (Python), or contextual words (Java's `to`,
  `with`); host-owned member names (`getClass`, `GetHashCode`) are
  errors or escapes; every collision is an error.
- Package coordinates and layout: reverse-domain `groupId`, NuGet
  prefixes, dotted subpackages for multi-library projects (`kelpto.md`
  in Lua, Python, Java, and JS).
- The runtime-never-named rule, with the list of what a library
  re-exports or replaces (`Pair`, `Optional<T>`, `Result`, the null
  sentinel), and equality's method name where hosts have no operator
  (`eq`, `equals`).
- Whether libraries can mark host-facing units: index parameters
  (Lua's 1-based, Rust's `usize`) and string positions (UTF-16 in JS).

**Elsewhere:**

- **#164:** failure types and messages in each host, panics' types,
  `Result` versus exceptions per host, nullable twins, Lua's `nil,
  failure` (decided with Lua's null), C++ exception-free builds, and
  the cost of `orelse` (stackless or non-throwing internal paths).
- **#671:** the callback mutation contract for `forEach`, `map`,
  `filter`, and `reduceFrom` (`sort` leaning to panic), and core's
  `Listed` aliasing docs.
- **#677:** recording chosen names, parameter names that become API
  (Python keywords, C# named arguments), generated `toString` formats,
  and the API summary that would catch removals.
- **#668 and #670:** records, enums, and value shapes (#668); hashing
  that agrees with hand-written `==` (#670).
- **New RFCs:** the C++ revamp, the Rust-idiomatic variant, and, if
  #671 doesn't take it, collection semantics as a whole.
- **No RFC:** the quick wins and most medium changes.
