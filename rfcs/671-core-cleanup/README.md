# Proposal: Core cleanup

Author(s): Tom P., drafted with Claude Code (Claude Opus 5.5), edited by Tom

Last updated: 2026-11-26

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/671.
Implemented in [#688](https://github.com/temperlang/temper/pull/688).

## Abstract

Core becomes an ordinary Temper library that follows its own rules:

- **Readable:** literate Markdown by topic, every declaration documented,
  examples run as tests.
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

Kotlin Temper's core was one 1,750-line file, which in Kotlin Temper (which I'll
call KTemper) supplied a number of function definitions for the interpreter as
well as some type definitions and signatures. It was complicated. Tempest only
ever read for signatures, while the interpreter and backends implemented members
natively. It carried bootstrapping workarounds, some of which only mattered in
KTemper, while some also mattered in Tempest. And some of these side effects
might also only have affected Tempest if KTemper manually worked around some:

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
- Undocumented builtins: macros and values showed `?` on hover. (Specific to
  Tempest. I haven't freshly reviewed what KTemper language server could even do
  here.)
- Backends disagreeing at the edges (indices out of bounds, `near`,
  `signum`, builders changed by their own callbacks).

Various plans to clean core up before predate the switch to Tempest, and if we
want to clean up in ways that make breaking changes, sooner is better than
later. And because a variety of cleanups are needed, this RFC is sort of a grab
bag of bug fixes, layout improvements, and actual semantic changes and/or new
features. At least old written issue is addressed here:
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
     [RFC 670](../../670-type-associated-operators/README.md)) and jumps
     (`return`, `break`, `continue`), which are syntax.
3. **The prose doc rule,** for any `.temper.md` file:
   - A `/** … */` before a declaration documents it.
   - Otherwise the doc starts at the first top-level paragraph whose
     first word is the declared name, and runs to the declaration. This matches
     Mike's earlier work on this topic. This effort doesn't seek to perfect
     handling of documentation, as that might be better addressed in RFC 689 or
     others, but this at least fixes some regression is supporting Markdown doc
     comments again.
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
   This was previously done in KTemper, but that was lost in the transition to
   Tempest. Full testing of all docs might still be out of scope of this RFC,
   but core and std themselves get their immediate docs tested.
5. **Generic list and map methods become extensions** (`listedMap`,
   `listedReduceFrom`, `listedReduceFromIndex`, `mappedToListWith`,
   `mappedToListBuilderWith`), as this was a language decision that we hadn't
   yet enforced in core. But core should follow the same rules as the rest of
   the language whenever possible, and some implementations, such as be-rust
   already had to use external functions to implement these methods, which isn't
   compatible with claimed dynamic dispatch. A sealed type in core could cheat
   somewhat, but it shouldn't.
   - Calls read the same: `xs.map { … }`, `xs.map<Int> { … }`.
   - Core keeps the rule that interface methods aren't generic; a test
     checks it.
   - `x.name<T>(…)` takes either all of an extension's type arguments or
     only those the receiver doesn't name.
6. **No representation-only fields.** `content`, `Problem`'s, and
   `PromiseBuilder`'s `_promise` are gone; bodies read `this`. The
   fields-initialized exemption is gone. Tempest doesn't make use of these prior
   KTemper bootstrapping mechanisms.
7. **Interpreter natives checked against core's bodies.** The interpreter
   keeps native Rust for speed; a test runs core's Temper bodies instead
   on shared inputs (135 cases) and lists any body not run, with a reason.
   Again, KTemper used these in the interpreter, but Tempest hasn't. Under this
   proposal, it still doesn't, beyond the testing for compatibility. It keeps
   the Rust implementations for speed reasons, including startup speed. Future
   efforts may seek to use the Temper definitions directly, but that is out of
   scope for this RFC.
8. **`core` and `std` are reserved:** only the built-in text or the
   compiler checkout's `lib/core` (for editors) gets core's privileges.
   Building another library named `temper-core` or `std` is an error. I haven't
   reviewed if this was enforced by KTemper.

### B. What core declares is all it enables

The frontend reads core's declarations instead of keeping lists of names.
Every check is on the type a name denotes (C.3), so aliases and imports
can't slip past. Some of these rules were already enforced in KTemper, some
hadn't survived the port to Tempest, and some might be new here to either. In
any case, the goal for this RFC is to be consistent.

| Capability | Rule |
| --- | --- |
| `new` | only a class with a public constructor. Every exported core class declares one; `private` where only core or the host makes values (`String`, numbers, `Boolean`, `List`, `Void`, `Type`, `Bubble`, `Promise`, `Empty`, `DoneResult`, string indices) |
| Extending | only unsealed interfaces; classes are final; sealed interfaces extend only in their own module |
| `is`, `as` | refused for `@mayDowncastTo(false)` types, checks that would introduce a type argument, connected types (below), and where nothing can match (`Bubble`, `Void`, `Never<T>`) |
| Statics | only those core declares (`String.fromCodePoint`, `Float64.pi`) |
| Type arguments | any type but `Void`, within the bound |

1. **A test checks every builtin type against every capability,** by
   every way of naming it, and fails when a type lacks a row. (tom to claude: What is a row here?)
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
   `doneResult()` and `empty()` make their values inside their classes. Some
   core types (such as `DoneResult`, tom to claude: others???) that should have hidden their constructors still suggested default
   public constructors by their type definition in Temper source, which wasn't
   necessarily honored for core types in KTemper. Tempest seeks to actually
   follow the definitions in core where provided.
5. **Sealed and private where core means it:**
   - `MapKey` is sealed: only `Int32` and `String` are keys. It had been sealed only in a comment.
   - `DoneResult`'s constructor is private; `doneResult()` makes one.
6. **Nameable again:** `Console`, `getConsole(name)`, and `Equatable<T>`
   (sealed; usable as a bound). Some ability to name these had been lost in the
   Tempest implementation.

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
     `let core = import("core");` and `core.String`. This is enabled by the
     namespace imports mentioned above, so `core` needs no special handling.

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
   `let M = Map; M<Boolean, Int>` is refused as `Map<Boolean, Int>` is. I
   haven't reviewed if this was a hole in KTemper or not. Another key goal of
   this RFC is that all semantic tightening, whether or not the issues existed
   in KTemper, is to ensure that all fixes, improvements, and refinements are
   fully tested to avoid further regression.

### D. Typing holes closed

1. **`Void` is never a value:** only a return type. Errors for `Void`
   parameters, locals, fields, `List<Void>`, `Void?`, `Void` bounds, and a
   `Void` result where a value is wanted. We implemented this long ago in
   KTemper. Holes in this regard found their way into Tempest, some of which may
   or may not have existed in KTemper, but we need to fill the hole in any case.
   This fits in the theme of core cleanup because we want to make the core
   library reliable.
2. **Type arguments fit their bounds everywhere:** calls, annotations,
   other types' arguments, supertypes.
   - Map keys must be a `MapKey` of themselves: `Map<Boolean, Int>` and
     `Map<AnyValue, Int>` are errors.
   - Unmarked type parameters are invariant: a `ListBuilder<Int32>` isn't
     a `ListBuilder<AnyValue>`. (`@out`/`@in` remain on a few core
     declarations here; a follow-up is planned for removing variance entirely.)
3. **Folded calls keep their type arguments:** `mk<Int>()` for
   `mk<T>(): List<T>` is a `List<Int32>`; `let n: Int = id<Int>("a")` is
   an error.
4. **Type parameters can't be made or extended:** "Cannot instantiate
   type parameter T", "Cannot extend type parameter T". This is because some
   backends erase generics. I haven't reviewed if there were holes in this in
   KTemper.
5. **A static and an instance member can't share a name** (inherited
   included; an interface's statics aren't inherited). I believe we enforced
   against this in KTemper, but it might not have found its way to Tempest.
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
   { null }` is `Int?`. Some effort is planned for improved error messages
   across null misuse, but this RFC document doesn't details specifics.

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
     `Queue.removeFirst` and `BitVector.set`. Typically, this is ensuring that
     behavior documented in core is actually followed across backends.
   - A bit vector reports length 0; an empty queue "index 0 … length 0". (tom to claude: is this new???)
   - String indices are in each backend's units (UTF-8 bytes, UTF-16
     units, or Python code points). (tom to claude: This was already the case in KTemper. do we need to mention it here?)
   - `orelse` isn't intended to catch it, and we at least intend to survey
     exceptions in behavior under this work. For example, exceptions on
     JavaScript and Lua for now. In RFC 164, we expect to finish ironing out
     inconsistencies across backends. To avoid panics for expected misses, use
     `getOr`, `hasIndex`, or `isEmpty`.

     ```temper
     let ls = [1, 2, 3];
     ls[3];          // panics: index 3 out of bounds for length 3
     ls.getOr(3, 0); // 0
     ```
   - Cheap on hot paths: one shared helper per runtime; C# one unsigned
     compare, inlined; Python tries the subscript first.
2. **Members settled on every backend:**
   (tom to claude? were these defined in ktemper? just missing in some backends or implemented wrong?)

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
   - In the past, issues included Rust
     deadlocks, C++ use-after-free, and JavaScript freezing `filter`'s input.
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
  types one by one. The need for ad hoc handling in Tempest was because KTemper
  didn't always recognize or follow all the definitions in Temper code for core.
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
  it and users search for it. Again, work in this RFC is mostly about better
  following and enforcement of defitions in core.
- **Collections to std, renamed:** core holds what the language needs.
- **Natives checked, not replaced by bodies:** running core's bodies costs
  every REPL and playground run a core settle (about 3 ms → 10–15 ms per
  small program); comparing the two gives the same assurance.

**Alternatives considered:**

- Rename `builtins` as `core`, but that retains a special case and a reserved
  word for which a general feature could provide.
- Shorter alternatives to `std/collections` such as `std/collect` or `std/util`,
  but the full name "collections" seemed more clearer. Name decisions could
  possibly be reconsideered in the future, but we need to settle by 1.0.

## Compatibility

Ideally, and in most cases below, any incompatibilities are compile-time errors.
And in many cases, these aren't actual compatibility changes so much as they're
stronger enforcement and consistency with definitions and documentation.

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
    exception before. And for many backends, host code still can catch panics as
    exceptions, but the intent is to remove this ability for Temper code itself,
    so consistent semantics are present in Temper.

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

- Hrefine's and Kelpto's private-constructor changes. Probably a full survey
  again of others.
- Language reference pages generated from core's and std's literate
  sources, replacing hand-kept copies. (tom to claude: this is just about improved automation of a portion of the docs? is this really after merge or just a change to how to site is built automatically?)

## Testing

- **Capability matrix:** every builtin type × every capability, by every
  way of naming it.
- **Connected scan:** each backend's sources against core's and std's
  `@connected` marks.
- **Core bodies vs natives:** 135 shared cases, both ways. (tom to claude: is this a fresh number? is it needed?)
- **Doc examples:** every marked example in core, std, and `docs/` runs
  in CI as marked; known exceptions are listed in
  `docs/inconsistencies.md`.
- **Shared programs on the interpreter and all seven backends:** core
  numbers, callback changes (C++ under AddressSanitizer), bit vectors,
  queues, out-of-bounds panics with each backend's whole message pinned.
- **Settle cases** for each typing rule, and LSP/REPL cases for hover and
  `help(…)` on core's declarations. (tom to claude: should we mention earlier the intent to improve core visibility in LSP?)
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
  core, or retire them.

## Open issues

- **Running core's bodies in the interpreter again,** once core settles
  cheaply (for example, loaded from cached compiled tmpl).
- **Sealed but not exhaustive:** `when` over `MapKey` can't name its
  cases; a general marker (useful for evolving libraries and enums, see
  [#50](https://github.com/temperlang/temper/issues/50)) is undecided.
- **Parse core once** into an index that the compiler and tools query,
  instead of several text scanners. (tom to claude: do we reparse it today for every case?)
- **Users' connected classes:** connecting an interface isn't reported
  yet; a policy for `@mayDowncastTo(true)` is needed. (tom to claude: what policy is lacking?)
- **Private constructors on the host side:** C# emits them public and
  Java package-private (belongs with
  [#676](https://github.com/temperlang/temper/issues/676)).
- **`orelse` catches panics on JavaScript and Lua,** until the
  error-handling work gives them a panic it passes over.
- **Callbacks that change what they walk,** beyond `sort`: backends
  differ (snapshot vs live). Belongs with an iterables RFC, alongside
  `forEach` on `Mapped` but not `Listed`.
- **Core decorators** are still matched by name, in their own namespace;
  they should become ordinary core declarations. This also needs and RFC which can also provide a path for user-defined decorators.
- **Runtimes restating core's bodies** (`near`, `reduceFromIndex`,
  `sorted`'s copy, seven times each): could drop `@connected` once
  backends translate core's bodies. (tom to claude: really???)
- **Core's extensions by name:** `listedMap(xs) { … }` and
  `xs.map<Int, String>` aren't callable yet. (tom to claude: why not???)
- **Not translated yet:** an `Equatable` bound; user classes extending
  `Console`, `Generator`, or other builtin interfaces; a `Console` value on
  JavaScript, Lua, and Rust; some core values as `AnyValue` on Rust and
  C++. (tom to claude: really??? did these holes exist in ktemper? i ended needing some special handling of Rquatable in be-rust in ktemper, but i guess you got around it?)
- **Erased type arguments in checks** from covariant supertypes. But as mentioned,
  an effort is underway to fully excise variance annotations from Temper, per earlier team decisions.
- **`Type` at run time:** `x is Type` is allowed but untested on backends. Defining
  consistent semantics for the runtime meaning of Type would be good but is outside the scope of this effort.
  `Type` values are still supported here for type aliases.
- **How macros name core:** future user-space macros need a name for
  `core` or names in it that user definitions don't shadow. One possibility is non-syntactic reference to core or
  its members.
- **Where moved runtime code lives** between core and std across backends. We've
  been inconsistent in the past, and it's still out of scope for this already large RFC.
- **Operators and function types in core** wait for
  [RFC 670](../../670-type-associated-operators/README.md) and
  [RFC 667](../../667-fun-types/README.md).

## Evidence

In this folder:

- [claude-core-cleanup.md](claude-core-cleanup.md): the cleanup items and
  the discussion that led to namespaces.
- [claude-deque-bitvector-to-std.md](claude-deque-bitvector-to-std.md):
  host types by backend, the connected rule, and the move.

In the compiler: the release notes and `notes/` (core's capabilities,
core's bodies, typing, Kotlin differences).
