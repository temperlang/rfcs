# Proposal: Core cleanup

Author(s): Tom P., drafted with Claude Code (Claude Opus 5.5), edited by Tom

Last updated: 2026-11-26

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/671.
Implemented in [#688](https://github.com/temperlang/temper/pull/688).

This document includes both handwritten text and content from
[a draft by Claude Code](tom/claude-proposal.md). All of it has been reviewed
and manually selected (or written) by humans.

## Abstract

Core becomes an ordinary Temper library that follows its own rules:

- **Readable:** literate Markdown by topic, every declaration documented
  and shown on hover, examples run as tests.
- **Honest:** what core declares is all it enables. No implied
  constructors, special-cased names, or hidden exemptions.
- **Nameable:** modules import as namespaces (`let rx = import("std/regex")`),
  replacing `builtins.X`.
- **Sound:** typing holes close (`Void` values, bounds, `Null`, and more).
- **Smaller:** `Deque` and `DenseBitVector` move to std as `Queue` and
  `BitVector`.
- **Consistent:** core's members behave the same on every backend,
  including out-of-bounds panics with one message.

## Background

Kotlin Temper (which I'll call KTemper) kept core in one 1,750-line file,
which supplied a number of function definitions for KTemper's interpreter
as well as type definitions and signatures. It was complicated. Tempest,
the Rust compiler replacing KTemper
([RFC 657](../657-tempest/README.md)), only ever read it for signatures,
while its interpreter and backends implemented members natively. Core
carried bootstrapping workarounds, some of which mattered only in KTemper,
and some in Tempest too. Some might have affected only Tempest, where
KTemper worked around them by hand:

- `builtins.Int` prefixes (71 of them), because core declared classes
  named like the builtins.
- Exemptions from rules users must follow: generic interface methods
  (`Listed.map<O>`), a fields-initialized exemption for representation-only
  `content` fields.
- Implied capabilities: a class without a constructor got a public one
  (`new Int32()` type-checked); private constructors weren't enforced.
- Unchecked Temper bodies that could drift from the natives.
- Host types not marked `@connected`, so `is`/`as` checks on them
  translated wrongly (JavaScript: `x is StringIndex` became `x >= 0`).
- Undocumented builtins: macros and values showed `?` on hover in
  Tempest. (KTemper's language server showed no docs on hover at all,
  only a declaration's kind, name, and type.)
- Backends disagreeing at the edges (indices out of bounds, `near`,
  `signum`, builders changed by their own callbacks).

Plans to clean up core predate the switch to Tempest, and for cleanups that
make breaking changes, sooner is better than later. Because a variety of
cleanups are needed, this RFC is sort of a grab bag of bug fixes, layout
improvements, and actual semantic changes or new features. At least one old
written issue is addressed here:
[#30](https://github.com/temperlang/temper/issues/30) (move `Deque` and
`DenseBitVector` out of core).

## Proposal

Work here touches six broadly defined areas.

### A. Core is an ordinary library

1. **Literate files by topic:** `any`, `console`, `generators`,
   `language`, `lists`, `maps`, `numbers`, `strings`, plus `config`.
2. **Every declaration documented, sometimes as Markdown prose.**
   - Builtin values, functions, and macros (`true`, `null`, `if`,
     `orelse`, `await`, …) get bodiless `@connected` declarations, so
     hover, signature help, REPL `help(…)`, and go-to-definition work.
   - Not declared: operators (wait for
     [RFC 670](../670-type-associated-operators/README.md)) and jumps
     (`return`, `break`, `continue`), which are syntax.
3. **The prose doc rule,** for any `.temper.md` file:
   - A `/** … */` before a declaration documents it.
   - Otherwise the doc starts at the first top-level paragraph whose
     first word is the declared name, and runs to the declaration. This
     matches Mike's earlier work on the topic. This effort doesn't seek to
     perfect doc handling, which [RFC 689](../689-doc-fragments/README.md)
     or others might better address, but it at least fixes a regression,
     supporting Markdown doc comments again.
   - Kept: paragraphs, lists, block quotes, example code, link
     definitions. Dropped: HTML blocks. A heading or thematic break ends
     it. The brief is the naming paragraph, and an example follows:

   ````markdown
   `listedMap` (`listed.map { … }`) maps elements using [transform].

       @extension("map")
       @connected
       export let listedMap<T, O>(listed: Listed<T>, transform: fn (T): O): List<O> { … }
   ````

4. **Examples are tests.** Core's and std's examples run in CI, each
   `// ✅ value` compared with the result. Blocks that can't run as part
   of their file are `temper inert`, and still checked when marked ✅ or ❌.
   KTemper ran docs' examples through its REPL as it generated the docs,
   filling in their results. Tempest's CI already checked the examples in
   `docs/` (`compat/check_doc_examples.py`), and this work extends that check
   to core's and std's literate sources. Richer checks (logged output, error
   messages) are left to [RFC 689](../689-doc-fragments/README.md).
5. **Generic list and map methods become extensions** (`listedMap`,
   `listedReduceFrom`, `listedReduceFromIndex`, `mappedToListWith`,
   `mappedToListBuilderWith`). No generic interface methods was a language
   decision we hadn't yet enforced in core. But core should follow the same
   rules as the rest of the language whenever possible, and some backends,
   such as be-rust, already had to implement these methods as external
   functions, which isn't compatible with claimed dynamic dispatch. A sealed
   type in core could cheat somewhat, but it shouldn't.
   - Calls read the same: `xs.map { … }`, `xs.map<Int> { … }`.
   - Core keeps the rule that interface methods aren't generic; a test
     checks it.
   - For a library's extension, `x.name<T>(…)` takes either all of its
     type arguments or only those the receiver doesn't name. Core's take
     only the latter for now (see Open issues).
6. **No representation-only fields.** `content`, `Problem`'s, and
   `PromiseBuilder`'s `_promise` are gone; bodies read `this`. The
   fields-initialized exemption is gone. Tempest doesn't use these KTemper
   bootstrapping mechanisms.
7. **Interpreter natives checked against core's bodies.** The interpreter
   keeps native Rust for speed; a test runs core's Temper bodies instead
   on shared inputs and lists any body not run, with a reason. KTemper's
   interpreter ran these bodies, but Tempest's hasn't, and under this
   proposal it still doesn't, beyond the testing for compatibility. It
   keeps the Rust implementations for speed, including startup speed.
   Future efforts may use the Temper definitions directly, but that is out
   of scope for this RFC.
8. **`core` and `std` are reserved:** only the built-in text or the
   compiler checkout's `lib/core` (for editors) gets core's privileges.
   Building another library named `temper-core` or `std` is an error.
   KTemper didn't enforce this: it built a library named `std`, and one
   named `temper-core` collided with the runtime's own output.

### B. What core declares is all it enables

The frontend reads core's declarations instead of keeping lists of names.
Every check is on the type a name denotes (C.3), so aliases and imports
can't slip past. Some of these rules were already enforced in KTemper, some
hadn't survived the port to Tempest, and some are new to both. In any case,
the goal for this RFC is to be consistent.

| Capability | Rule |
| --- | --- |
| `new` | only a class with a public constructor. Every exported core class declares one; `private` where only core or the host makes values (`String`, numbers, `Boolean`, `List`, `Void`, `Type`, `Bubble`, `Promise`, `Empty`, `DoneResult`, string indices) |
| Extending | only unsealed interfaces; classes are final; sealed interfaces extend only in their own module |
| `is`, `as` | refused for `@mayDowncastTo(false)` types, checks that would introduce a type argument, connected types (below), and where nothing can match (`Bubble`, `Void`, `Never<T>`) |
| Statics | only those core declares (`String.fromCodePoint`, `Float64.pi`) |
| Type arguments | any type but `Void`, within the bound |

1. **A test checks every builtin type against every capability,** by
   every way of naming it. Its table has one entry per builtin type,
   giving the expected result for each capability, and the test fails
   when a type core declares has no entry.
2. **Every host-supplied type is `@connected`:** adds `Pair`, `Listed`,
   `Mapped`, `SafeGenerator`, `Console`, and std's `Queue` and
   `BitVector`. A test scans each backend's sources and fails on any
   unmarked one.
3. **The connected `is`/`as` rule:** a check may target a
   connected type only from a sealed supertype reaching it through sealed
   supertypes, unless `@mayDowncastTo` says otherwise.
   - Why: several Temper types share a host type (a JS number is an
     `Int32`, a `Float64`, and a `StringIndex`), so a check from
     `AnyValue` can't translate faithfully.
   - `String`, the numbers, `Boolean`, `List`, and `Map` are
     `@mayDowncastTo(false)` for the same reason.

   ```temper
   let f(r: GeneratorResult<Int>): Boolean { r is DoneResult<Int> } // OK: sealed path
   let g(x: AnyValue): Boolean { x is StringBuilder }               // error
   ```

4. **Private constructors are enforced, per class** (and classes nested
   in it), through aliases and object literals too. Core follows it:
   `doneResult()` and `empty()` make their values inside their classes.
   - Core classes that declared no constructor implied a public one by
     their Temper definition, though they should have hidden it:
     `Boolean`, `DoneResult`, `Float64`, `Int32`, `Int64`, `List`,
     `Promise`, and `String`.
   - Others declared a private constructor that nothing enforced:
     `Empty`, `NoStringIndex`, `StringIndex`, and `Null`.
   - KTemper accepted `new` for these, as `new Int32()` (JavaScript's
     `new Number()`), `new String()`, and `new Empty()` or
     `new DoneResult<Int>()` (both failing at run time). Tempest follows
     the definitions in core where provided.
5. **Sealed and private where core means it:**
   - `MapKey` is sealed: only `Int32` and `String` are keys. It had been
     sealed only in a comment.
   - `DoneResult`'s constructor is private; `doneResult()` makes one.
6. **Nameable again:** `Console`, `getConsole(name)`, and `Equatable<T>`
   (sealed; usable as a bound). Tempest had lost some ability to name
   these.

### C. Naming core: namespaces, no `builtins`

1. **Module namespaces:** `let NAME = import(PATH);` for any module.

   ```temper
   let rx = import("std/regex");
   let pattern: rx.Regex = new rx.Regex(rx.oneOrMore(new rx.CodePoints("ab")));
   ```

   - `rx.member` works in code and types, translating as a destructuring
     import would; backends never see the namespace.
   - Errors: a namespace used as a value; unknown or private members
     (with did-you-mean); `export`, `var`, or a type on a namespace.
   - `new ns.C(x)` means `new (ns.C)(x)`.
   - Editors hover, complete, and go to definition through namespaces.
2. **`builtins.X` and the reserved word `builtins` are gone.**
   - Core's names stay in scope unqualified.
   - Code shadowing a core name reaches core's through
     `let core = import("core");` and `core.String`. The namespace
     imports above enable this, so `core` needs no special handling.

     ```temper
     let core = import("core");
     class String {
       public text: core.String;
       public constructor(text: core.String) { this.text = text; }
     }
     ```
   - Neither `core` nor `builtins` is predefined, so users may use them.
   - The compiler names core by resolved symbols, never source names.
3. **One path resolves a name to a type,** through aliases, imports, and
   namespaces. Every rule sees a type the same however it's named:
   `let M = Map; M<Boolean, Int>` is refused as `Map<Boolean, Int>` is.
   KTemper's holes here were in the rules themselves rather than aliases:
   it accepted `Map<Boolean, Int>` and `new Int32()` whether named directly
   or through an alias. Another key goal of this RFC is that all semantic
   tightening, whether or not the issues existed in KTemper, is fully
   tested to avoid further regression.

### D. Typing holes closed

1. **`Void` is never a value:** only a return type. Errors for `Void`
   parameters, locals, fields, `List<Void>`, `Void?`, `Void` bounds, and a
   `Void` result where a value is wanted. We implemented this long ago in
   KTemper. Holes in it found their way into Tempest, some of which may or
   may not have existed in KTemper, but we need to fill them in any case.
   This fits the theme of core cleanup because we want the core library to
   be reliable.
2. **Type arguments fit their bounds everywhere:** calls, annotations,
   other types' arguments, supertypes.
   - Map keys must be a `MapKey` of themselves: `Map<Boolean, Int>` and
     `Map<AnyValue, Int>` are errors.
   - Unmarked type parameters are invariant: a `ListBuilder<Int32>` isn't
     a `ListBuilder<AnyValue>`. (`@out`/`@in` remain on a few core
     declarations here; a follow-up is planned to remove variance
     entirely.)
3. **Folded calls keep their type arguments:** `mk<Int>()` for
   `mk<T>(): List<T>` is a `List<Int32>`; `let n: Int = id<Int>("a")` is
   an error.
4. **Type parameters can't be made or extended:** "Cannot instantiate
   type parameter T", "Cannot extend type parameter T". This is because some
   backends erase generics. KTemper had holes here: `new T()` gave only
   "Malformed type reference", and `extends T` crashed the compiler.
5. **A static and an instance member can't share a name** (inherited
   included; an interface's statics aren't inherited). KTemper didn't
   check this (its Java output renamed the static), nor did Tempest.
6. **No `Null` type.**
   - `null` takes the nullable type its place wants (`let n: Int? = null`,
     or the other side's type in `x == null`).
   - `let a = null;` needs a type, because `Null` doesn't exist independently.
     We had previously mostly removed the `Null` type in KTemper, but it was
     still defined in core, and that definition led to confusion in Tempest.
     This RFC removes the notion and definition of `Null` completely.

     ```temper
     let a = null;          // error: Declare a nullable type for a: null alone has none
     let a: String? = null; // OK
     ```
7. **Null alone has no members and is no condition:** `null.isEmpty`,
   `if (null)`, `null && b`, and `null + 1` are errors. `if (c) { 1 } else
   { null }` is `Int?`. Some effort is planned to improve error messages
   across null misuse, but this RFC doesn't detail specifics.

### E. `Deque` and `DenseBitVector` move to std as `Queue` and `BitVector`

```temper
let { Queue, BitVector } = import("std/collections");
```

1. **One module, `std/collections`,** where hosts keep such types.
2. **Renamed for what they are:** the API is first-in, first-out; "dense"
   is already implied by "vector".
3. **Same host types** (`java.util.Deque`, `BitSet`, Python's `deque`, …),
   so host APIs don't change; runtimes' own types renamed to match.
4. **Pure Temper bodies,** the interpreter's only implementation.
5. **Backends agree at the edges:** `get` at a negative index is `false`;
   `set` there panics; `removeFirst` on an empty queue panics; a negative
   capacity is none.
6. **A clean error for old names:** "Deque has not been declared; it's
   std's Queue now: add `let { Queue } = import("std/collections");`".
   Nothing is reserved, so users' own `Deque` or `Queue` works. We might want
   to add an actual `Deque` to `std/collections` in the future, but that's
   outside the scope of this RFC.

### F. Same behavior on every backend

1. **Out of bounds panics everywhere, with one message:**
   `index 3 out of bounds for length 3`.
   - Covers `ls[i]`, `set`, `add`/`addAll` at an index, `removeLast` and
     `reduce` when empty, string reads at or past the end, and std's
     `Queue.removeFirst` and `BitVector.set`. Mostly, this ensures that
     behavior documented in core is actually followed across backends.
   - New with this work, since backends differed here before:
     `BitVector.set` at a negative index reports length 0, as a bit vector
     has no length, and `removeFirst` on an empty queue reports index 0 and
     length 0.
   - String indices and lengths in the message are in each backend's
     units (UTF-8 bytes, UTF-16 units, or Python code points), as in
     KTemper, so only an ASCII string's message is the same everywhere.
   - `orelse` isn't intended to catch it, and this work at least surveys
     the exceptions, which are JavaScript and Lua for now.
     [RFC 164](../164-exceptions/README.md) should finish ironing out
     inconsistencies across backends. To avoid panics for expected misses,
     use `getOr`, `hasIndex`, or `isEmpty`.

     ```temper
     let ls = [1, 2, 3];
     ls[3];          // panics: index 3 out of bounds for length 3
     ls.getOr(3, 0); // 0
     ```
   - Cheap on hot paths: one shared helper per runtime; C# one unsigned
     compare, inlined; Python tries the subscript first.
2. **Members settled on every backend.** KTemper's core defined each of
   these with a Temper body, but backends missed or differed on some: on
   JavaScript, `signum` was undefined and `reduceFromIndex` wasn't a
   function (on Python too), and on JavaScript and Lua, `near` said an
   infinity wasn't near itself.

   | Member | Semantics |
   | --- | --- |
   | `succ()`, `pred()` (`Int32`, `Int64`) | `n + 1`, `n - 1`, wrapping as `+`/`-` do |
   | `Int32.signum` | `-1`, `0`, or `1`, extremes included |
   | `reduceFromIndex(initial, index, f)` | past the end gives `initial`; negative panics |
   | `Float64.near(other, relTol, absTol)` | Python's `math.isclose`, but true whenever `==` is (NaN near NaN); infinities near only themselves |

3. **Builders stay memory safe when callbacks change them:**
   - `addAll` and `splice` of the builder itself use its values from
     before the call.
   - `map`, `filter`, `reduceFrom`, … callbacks that change the builder
     can't deadlock or read freed memory; Rust and C++ walk a snapshot.
   - A `sort` comparison that adds or removes values panics; every
     backend sorts a copy.
   - In the past, issues included Rust deadlocks, C++ use-after-free, and
     JavaScript freezing `filter`'s input.
4. **Python types generic results cheaply:** a function whose result
   alone names a type parameter is annotated or `cast()`, passing pyright
   strict and mypy, instead of subscripting a class at run time (about
   6× slower). This is just a runtime performance improvement.

## Rationale

- **Core as an ordinary library:** users can read it as an example,
  editors need no special paths, and the rules get tested on the hardest
  code there is.
- **Declarations, not lists:** one place to change and to read; tests
  fail when core and the compiler disagree.
- **Kotlin's connected rule, as a rule:** one general rule covers users'
  connected types too and fixes wrong generated code, rather than marking
  types one by one. Tempest needed ad hoc handling because KTemper didn't
  always recognize or follow all of core's definitions in Temper code.
- **Strict now, looser later:** each tightening refuses code already
  unportable or wrong somewhere. Loosening later breaks nothing;
  tightening after 1.0 would.
- **Namespaces over a predefined `core`:** nothing reserved, general
  (helps std's many exports), one line where needed.
- **Private constructors per class:** Temper has only per-class
  `private`, deliberately; this matches private methods.
- **No `Null`:** a one-value type no host has adds a case to every rule;
  taking null's type from its place changes no type-checking program.
- **Out of bounds as a panic:** it's a programming error, and core never
  declared these as failing. One message (Java's wording) lets tests pin
  it and users search for it. Again, work in this RFC is mostly about
  better following and enforcing definitions in core.
- **Collections to std, renamed:** core holds what the language needs.
- **Natives checked, not replaced by bodies:** running core's bodies costs
  every REPL and playground run a core settle (about 3 ms → 10–15 ms per
  small program); comparing the two gives the same assurance.

**Alternatives considered:**

- Rename `builtins` as `core`, but that retains a special case and a
  reserved word where a general feature could provide.
- Shorter alternatives to `std/collections`, such as `std/collect` or
  `std/util`, but the full name "collections" seemed clearer. Names could
  be reconsidered in the future, but we need to settle them by 1.0.

## Compatibility

Ideally, and in most cases below, any incompatibilities are compile-time
errors. And in many cases, these aren't actual compatibility changes so
much as stronger enforcement and consistency with definitions and
documentation.

| Change | Breaks | Migration |
| --- | --- | --- |
| `Deque`, `DenseBitVector` moved | any use | `let { Queue, BitVector } = import("std/collections");` |
| `builtins.X` removed | `builtins.String`, … | drop the prefix, or `let core = import("core");` |
| No `Null` | naming `Null`; `let a = null;` | the nullable type meant; a declared type |
| Private constructors enforced | `new C()` outside `C` | a static method on `C` |
| `DoneResult` constructor private | `new DoneResult()` | `doneResult()` |
| `MapKey` sealed | user types extending it | none in practice; no backend supported them |
| Connected `is`/`as` | `x is StringBuilder`, `x is Pair<K, V>` from `AnyValue` | check through a sealed supertype, or keep the typed value |
| `Void` not a value | `x: Void`, `List<Void>`, `Void?` | drop the value, or return a real type |
| Bounds everywhere | `Map<Boolean, Int>`, … | a type within the bound |
| `new T()`, `extends T` | either | a factory function parameter |
| Static/instance name clash | such pairs | rename one |
| `core`, `std` reserved | libraries named `temper-core` or `std` | rename |
| No implied constructors | `new Int32()`, `new Empty()` | literals, `empty()` |
| `sort` comparisons changing the builder | such comparisons | don't; it panics |
| Out of bounds panics (run time) | `ls[i] orelse x`; negative `set` on JS/Lua; empty `removeFirst`; host code catching `IndexError` | `getOr`, `hasIndex`, `isEmpty`, or check `length` |

- **Libraries:** of the surveyed public libraries, Hrefine and Kelpto
  need changes, both for private constructors (move top-level makers into
  static methods). Generated code is otherwise unchanged.
- **KTemper:** one source can't always build on both compilers
  (namespaces, `std/collections`, `Null`, `builtins.X`), so libraries
  change once, at the switch.
- **Host code:** APIs don't change, except:
  - Java and C# see the generic list and map helpers as free functions,
    as the runtimes already had them.
  - Runtimes' own collection types are renamed (Python's
    `temper_core.BitVector`).
  - Out of bounds reaches hosts as each backend's panic (Python
    `BaseException`, Java `AssertionError`, C# `Environment.FailFast`,
    C++ `panic()`, Rust `panic!()`), where some could catch a host
    exception before. On many backends, host code can still catch panics
    as exceptions, but the intent is to remove this ability from Temper
    code itself, so Temper's semantics are consistent.

## Implementation

Done on [#688](https://github.com/temperlang/temper/pull/688), in this
order:

1. Generic methods as extensions; `builtins.` prefixes dropped; Kotlin-era
   TODOs resolved. (Yes, we had TODOs in core.)
2. Bodies tested against natives; builtins documented in core;
   capabilities read from declarations.
3. `succ`, `pred`, `signum`, `reduceFromIndex`, `near` settled; builder
   safety.
4. Core split by topic (a pure move), then made literate, with examples
   run as tests.
5. Namespaces, `builtins` removed; `Void`, bounds, `new ns.C()`; type
   parameters; `std` reserved; fields trimmed.
6. Connected types and rule; private constructors; sealed `MapKey`;
   member names; one type-resolution path.
7. `Queue` and `BitVector` in `std/collections`; `Null` removed.
8. Out-of-bounds panics everywhere; null alone refused; folded calls'
   type arguments; cheap Python type arguments.

After merge:

- Hrefine's and Kelpto's private-constructor changes, and probably a fresh
  survey of other libraries.

## Testing

- **Capability matrix:** every builtin type × every capability, by every
  way of naming it.
- **Connected scan:** each backend's sources against core's and std's
  `@connected` marks.
- **Core bodies vs natives:** shared cases, run both ways.
- **Doc examples:** every marked example in core, std, and `docs/` runs
  in CI as marked; known exceptions are listed in
  `docs/inconsistencies.md`.
- **Shared programs on the interpreter and all seven backends:** core
  numbers, callback changes (C++ under AddressSanitizer), bit vectors,
  queues, out-of-bounds panics with each backend's whole message pinned.
- **Settle cases** for each typing rule, and LSP/REPL cases for hover and
  `help(…)` on core's declarations.
- **Library output:** surveyed libraries' generated code compared before
  and after on all seven backends at each step.

## Documentation

- **Core's own literate files** are the reference for builtins, shown on
  hover and in `help(…)`.
- **Release notes** (`docs/release-notes/unreleased.md`): each breaking
  change with its migration.
- **Kotlin differences** (`notes/kotlin-differences.md`) and typing notes.
- **Contributor docs:** the prose doc rule; what `temper inert` means and
  when inert examples are checked.
- **Later:** generate `docs/language/builtins.md` and `types.md` from
  core's and std's literate sources, as KTemper's docs build partly did,
  replacing hand-kept copies, or retire them. This is docs automation
  only, with no language change.

## Open issues

- **Running core's bodies in the interpreter again,** once core settles
  cheaply (for example, loaded from cached compiled tmpl).
- **Sealed but not exhaustive:** `when` over `MapKey` can't name its
  cases; a general marker (useful for evolving libraries and enums, see
  [#50](https://github.com/temperlang/temper/issues/50)) is undecided.
- **One index of core:** core isn't reparsed per compile, but typing,
  docs, hover, and the interpreter's bodies harness each scan its text on
  their own (once per process). One parsed index that the compiler and
  tools query could replace them.
- **Users' connected classes:**
  - Connecting an interface isn't reported yet.
  - `@mayDowncastTo` on a user's type needs a policy. KTemper honors it
    unchecked, taking the user's word that every backend can tell the
    host type apart. Tempest reads it only from core, so a user's
    `@mayDowncastTo(true)` is ignored and the connected rule refuses the
    check.
- **Private constructors on the host side:** C# emits them public and
  Java package-private (belongs with
  [#676](https://github.com/temperlang/temper/issues/676)).
- **`orelse` catches panics on JavaScript and Lua,** until the
  error-handling work gives them a panic it passes over.
- **Callbacks that change what they walk,** beyond `sort`: backends
  differ (snapshot vs live). Belongs with an iterables RFC, alongside
  `forEach` on `Mapped` but not `Listed`.
- **Core decorators** are still matched by name, in their own namespace;
  they should become ordinary core declarations. This also needs an RFC,
  which can also provide a path for user-defined decorators.
- **Runtimes restating core's bodies** (`near` and `reduceFromIndex`,
  seven times each): those without a host speed-up could drop
  `@connected` and translate from core's bodies, once tmpl translates
  core's bodies at all. It doesn't yet, and KTemper's unconnected
  `reduceFromIndex` failed at run time on JavaScript and Python.
  (`sorted` keeps host sorts for speed and stability.)
- **Core's extensions by name:** `listedMap(xs) { … }` and
  `xs.map<Int, String>` aren't callable yet. Core is built in rather than
  loaded as a library, and typing reads its extensions as members of
  their types (`Listed.map<O>`), so `listedMap` isn't a name in scope, and
  the member takes only the type arguments the receiver doesn't name.
- **Not translated yet:** an `Equatable` bound; user classes extending
  `Console`, `Generator`, or other builtin interfaces; a `Console` value
  on JavaScript, Lua, and Rust; some core values as `AnyValue` on Rust
  and C++. Where checked, these worked in KTemper: on JavaScript, an
  `Equatable` bound, a class extending `Console`, and a `Console` value
  (and its Rust backend mapped an `Equatable` bound to `PartialEq`), so
  they're Tempest regressions still to fix.
- **Erased type arguments in checks** from covariant supertypes. But as
  mentioned, an effort is underway to remove variance annotations from
  Temper entirely, per earlier team decisions.
- **`Type` at run time:** `x is Type` is allowed but untested on
  backends. Consistent semantics for what a `Type` means at run time
  would be good but are outside the scope of this effort. `Type` values
  are still supported here for type aliases.
- **How macros name core:** future user-space macros need a name for
  `core`, or for names in it, that user definitions don't shadow. One
  possibility is a non-syntactic reference to core or its members.
- **Where moved runtime code lives** between core and std across
  backends. We've been inconsistent in the past, and it's still out of
  scope for this already large RFC.
- **Operators and function types in core** wait for
  [RFC 670](../670-type-associated-operators/README.md) and
  [RFC 667](../667-fun-types/README.md).

## Evidence

In this folder:

- [claude-core-cleanup.md](tom/claude-core-cleanup.md): the cleanup items and
  the discussion that led to namespaces.
- [claude-deque-bitvector-to-std.md](tom/claude-deque-bitvector-to-std.md):
  host types by backend, the connected rule, and the move.

In the compiler: the release notes and `notes/` (core's capabilities,
core's bodies, typing, Kotlin differences).
