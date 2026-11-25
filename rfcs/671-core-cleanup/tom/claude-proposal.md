(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: Core cleanup

Author(s): draft by Claude Code (Claude Opus 5.5), for Tom P. and the team

Last updated: 2026-11-24

Discussion at https://github.com/temperlang/temper/issues/671.

**This is a draft written by Claude for Tom and the team to react to,**
not a decision. It turns the notes in this folder
([core cleanup](claude-core-cleanup.md) and
[moving `Deque` and `DenseBitVector`](claude-deque-bitvector-to-std.md))
and the choices Tom made between 2026-11-18 and 2026-11-24 into one
proposal. The Temper compiler's `core-extension-methods` branch
implements all of it, so the examples here compile on that branch; where
the proposal departs from an earlier note, as in renaming the moved
types, it follows Tom's later decision.

## Abstract

Core becomes a Temper library like any other: literate Markdown files
by topic, with prose docs on every declaration and examples that run as
tests. What core declares is all it enables. A builtin class can be
made only through a constructor core declares public, extended only
where core allows it, and checked with `is` or `as` only where every
backend can tell it apart, so every type a host supplies is marked
`@connected` and Kotlin Temper's connected-type rule applies. Core's
generic list and map methods become extension functions, so core keeps
the rule that interface methods aren't generic. Several typing holes
close: `Void` is never a value, type arguments fit their bounds wherever
they're written, type parameters can't be made or extended, and a static
and an instance member can't share a name. Users' private constructors
are enforced per class. Modules can be imported as namespaces
(`let rx = import("std/regex")`), which replaces `builtins.X`. Core
loses its `Null` type, its representation-only fields, and two
collections, which move to std as `Queue` and `BitVector`. An index out
of bounds of a list, a string, or those collections panics on every
backend with one message. Core and std are reserved names, recognized
only from the compiler's own sources.

## Background

Core (`lib/core/`) declares the builtin types and functions every
Temper module sees. In Kotlin Temper it was one 1,750-line file that
typing read for signatures, while the interpreter and every backend
implemented its members natively. It carried bootstrapping workarounds
from that compiler's history:

- **Prefixed names.** Core wrote `builtins.Int` (71 times), because it
  declared classes named like the builtins, and user code could write
  `builtins.X` too.
- **Rules core didn't follow.** Interfaces can't have generic methods,
  because overrides can't be generic in every backend, but core's
  `Listed.map<O>` and four others were exempt.
- **Implied capabilities.** A class without a constructor got a public
  one, so Kotlin's typer took `new Int32()`, `new Void()`, and
  `new Empty()`. Private constructors weren't enforced at all.
- **Representation fields.** Each builtin class declared a private
  `content` field that only backends set, with an exemption from the
  fields-initialized check.
- **Unchecked bodies.** Many members had Temper bodies that nothing ran,
  so they could drift from what the interpreter and backends did.
- **Unmarked host types.** Some types each backend supplies, as `Pair`
  or `Listed`, weren't `@connected`, and the connected-type check for
  `is` and `as` only covered the ones that were. JavaScript translated
  `x is StringIndex` as `x >= 0` for any value.
- **Little documentation.** Macros, builtin values, and the console had
  no declarations, so editors showed `?` on hover and had nowhere to go.

As Temper's new compiler replaces Kotlin Temper, the team agreed to
clean core up before the switch, while breaking changes are cheapest.
Two related issues fold in:
[#30](https://github.com/temperlang/temper/issues/30) (move `Deque` and
`DenseBitVector` out of core) and the question of how code names core
when it shadows a core name.

## Proposal

Each item says what Temper does now, and in a **Kotlin Temper** line,
what the old compiler did.

### 1. Core is literate Markdown, documented and tested

- Core is a directory of `.temper.md` files, one per topic: `any`,
  `console`, `generators`, `language`, `lists`, `maps`, `numbers`, and
  `strings`, plus `config`. Each has a title, and a heading per class,
  interface, or function group.
- Every declaration has docs, written as prose. Builtin values,
  functions, and macros (`true`, `null`, `if`, `orelse`, `await`, and
  the rest) have bodiless `@connected` declarations, so hover, signature
  help, `help(…)` in the REPL, and go to definition work on them. In
  core such a declaration declares nothing; it's there for its docs.
  Operators wait for [RFC 670](../../670-type-associated-operators/README.md),
  and jumps (`return`, `break`, `continue`) are syntax, so neither is
  declared.
- **The doc rule for prose**, in any `.temper.md` file: a `/** … */`
  before a declaration documents it. Otherwise its doc starts at the
  first top-level paragraph whose first word is the declared name
  (ignoring case, and `` ` `` or `*` around it) and runs to the
  declaration, keeping the Markdown in between as written: paragraphs,
  lists, block quotes, example code blocks, and link reference
  definitions. HTML blocks are left out. A heading or thematic break
  ends a doc. The brief is the naming paragraph.

  ````markdown
  `listedMap` (`listed.map { … }`) maps elements using [transform].

      @extension("map")
      @connected
      export let listedMap<T, O>(listed: Listed<T>, transform: fn (T): O): List<O> {
        …
      }
  ````

- **Examples are tests.** A script runs core's and std's doc examples,
  comparing each `// ✅ value` comment with what the example produces;
  a panicking or failing example fails. Examples that can't run (as one
  that names a private member) are marked `temper inert`.

**Kotlin Temper:** one file, mostly `/** */` docs. It attached prose
docs too (`pickCommentToAttach`), but took each list item's paragraph
alone and dropped block quotes, code blocks, and links, and went past
headings. Its doc examples weren't run, and some had gone stale.

### 2. Generic list and map methods are extensions

`Listed.map<O>`, `reduceFrom<O>`, `reduceFromIndex<O>`,
`Mapped.toListWith<T>`, and `toListBuilderWith<T>` become `@extension`
functions (`listedMap`, `listedReduceFrom`, `listedReduceFromIndex`,
`mappedToListWith`, and `mappedToListBuilderWith`). Calls read the
same, `xs.map { … }` or `xs.map<Int> { … }`, with static dispatch.
A test checks that core declares no generic interface method.

A call `x.name<T>(…)` resolves to an extension, taking either all its
type arguments, as a call by name would, or only those the receiver's
type doesn't name, as a method's own: `[3].firstThrough<String> { … }`
for `listFirstThrough<T, O>(ls: List<T>, f: fn (T): O): O`.

Generated code calls the same runtime helpers as before. Java and C#
host code sees free functions where it might have expected methods,
as the runtimes' helpers already were.

**Kotlin Temper:** exempted core from "Overridable methods don't allow
generics", only because it read core for signatures. Its Rust runtime
already implemented these as generic free functions over a non-generic
trait.

### 3. What core declares is all it enables

The frontend reads core's declarations for each capability rather than
keeping lists of names. Each check is on the type a name denotes, so an
alias, an import, or a namespace member is checked as the type itself
(item 7).

| Capability | Rule |
| --- | --- |
| `new` | only a class with a public constructor. Every class core exports declares its constructor, `private` where only core or the host makes values (`String`, the numbers, `Boolean`, `List`, `Void`, `Type`, `Bubble`, `Promise`, `Empty`, `DoneResult`, and the string indices) |
| Extending | only unsealed interfaces. Classes are final; a sealed interface is extended only in its own module, for users' sealed interfaces too |
| `is`, `as` | refused for `@mayDowncastTo(false)` types, for checks that would introduce a type argument, for connected types (below), and where nothing can match (`Bubble` and `Void` aren't `AnyValue`s; `Never<T>` has no values) |
| Statics | only those core declares, as `String.fromCodePoint` or `Float64.pi`; others are "No member" errors |
| Type arguments | any type but `Void`, within the parameter's bound |

A test checks every builtin type against every capability, by name and
through each other way to name it, and fails when core adds a type
without a row.

**Connected types.** Every type a backend supplies from the host is
marked `@connected`. This adds `Pair`, `Listed`, `Mapped`,
`SafeGenerator`, and `Console` to those already marked, and std's
`Queue` and `BitVector` (item 13). A test scans each backend's sources
for the core and std types it maps to host or runtime types, and fails
naming any that isn't marked, so no hand-kept list can drift.

**The connected `is` and `as` rule**, as Kotlin Temper has it: a check
may target a `@connected` type, core's or a user's, only from a sealed
supertype that reaches it through sealed supertypes, unless
`@mayDowncastTo` on the type decides otherwise.

```temper
let f(r: GeneratorResult<Int>): Boolean { r is DoneResult<Int> } // OK: sealed path
let g(x: AnyValue): Boolean { x is StringBuilder }               // error
```

Two Temper types may connect to the same host type, and one host type
may stand for several values (a JavaScript number is an `Int32`, a
`Float64`, and a `StringIndex`), so a check from `AnyValue` can't be
translated faithfully. `x is String` is refused for the same reason,
though by its own marker: `String` is `@mayDowncastTo(false)`, since a
host string is confusable with other values the host represents as
strings, as scalars on several dynamic-language backends and dates in
some older host languages. The numbers, `Boolean`, `List`, and `Map`
are marked the same way.

**Kotlin Temper:** had the connected rule, but its core left several
host types unmarked, so the rule didn't cover them. It gave every class
without a constructor a public one, so `new Int32()` and `new Empty()`
type-checked; it already refused extending builtin classes.

### 4. `Void` is never a value

`Void` is only what a function returns, as `f(): Void` or `fn (): Void`.
It's no other type's subtype, not even `AnyValue`'s. A parameter,
local, or field of type `Void`, `List<Void>`, `Void?`, a function type's
`Void` parameter, a `Void` bound, and a `Void` result where a value is
wanted, as `let h(): AnyValue { b() }` for `b(): Void`, are errors.

**Kotlin Temper:** reported "Void expressions cannot be used as values"
for some of these, at varying positions, and let others pass.

### 5. Type arguments fit their bounds everywhere; invariance

A type argument must fit its parameter's bound wherever the type is
written: a call, an annotation, another type's argument, or a
supertype. It's judged as a type, so `AnyValue` fits only `AnyValue`. A
map key must be a `MapKey` of itself, so `Map<Boolean, Int>`,
`Map<AnyValue, Int>`, and `Map<MapKey<String>, Int>` are errors.

Type parameters without `@out` or `@in` compare their arguments
invariantly: a `ListBuilder<Int32>` isn't a `ListBuilder<AnyValue>`.
`@out` and `@in`, deprecated in the release notes, are kept on core's
few declarations and not yet honored otherwise.

**Folded calls keep their type arguments.** A call of constants is
folded to its value before it's checked, so it's typed from its
arguments: `let n: Int = id<Int>("a")` is "Cannot assign to Int32 from
String". Its explicit type arguments still bind the type parameters no
parameter mentions, so `mk<Int>()` for `mk<T>(): List<T>` is a
`List<Int32>`, as the value's type would show.

**Kotlin Temper:** checked bounds at calls only; it compared
unannotated parameters invariantly too. It folded calls of constants
before checking them as well.

### 6. Module namespaces; no `builtins`

`let NAME = import(PATH);` binds a compile-time namespace for any
module: your own, std, another library, or core.

```temper
let rx = import("std/regex");
let pattern: rx.Regex = new rx.Regex(rx.oneOrMore(new rx.CodePoints("ab")));
```

- `rx.member` names the export, in code and in types, and translates
  exactly as a destructuring import of it would. Backends never see the
  namespace.
- Using a namespace as a value, an unknown or private member (with a
  did-you-mean suggestion), and `export`, `var`, or a declared type on a
  namespace are errors. Editors hover, complete, and go to definition
  through it.
- In `new ns.C(x)`, the dots belong to the class, `new (ns.C)(x)`; only
  a namespace may qualify the class, and `new` without arguments, as
  `new { k: v }`, is its own error.
- **`builtins.X` and the reserved word `builtins` are gone.** Core's
  names stay in scope unqualified. Code that declares a name core has,
  as `class String`, reaches core's through
  `let core = import("core");` and `core.String`, or a renamed
  destructuring import. Neither `core` nor `builtins` is predefined, so
  a user's own `core` or `builtins`, as a module or a variable, works
  on every backend. The compiler names core by resolved symbols, never
  by a name in source.

**Kotlin Temper:** destructuring imports only; `builtins.X` was the
only way to qualify a core name, and its parser read `new ns.C(x)` as
`(new ns).C(x)`.

### 7. One way to resolve a type

One path decides what a name denotes as a type, through aliases
(top-level or local), imports, and namespace members. So every rule
above, and sealedness, private constructors, `Void` and `Never`, and
the connected rule, sees a type the same however it's named:
`let M = Map; M<Boolean, Int>` is refused as `Map<Boolean, Int>` is,
and `let D = C; new D()` as `new C()`. A local alias is the type itself
and is left out of generated code.

**Kotlin Temper:** rules were checked on names in several places, and
an alias could slip past some.

### 8. Type parameters can't be made or extended

`new T()` is "Cannot instantiate type parameter T", and `extends T`
"Cannot extend type parameter T", since `T` may stand for an interface,
a final class, or a sealed interface.

**Kotlin Temper:** reported `new T()` as "Malformed type reference" and
crashed on `interface I<T> extends T {}`.

### 9. A static and an instance member can't share a name

In a class or interface, a static and an instance member of one name,
or a static and an inherited instance member, are an error: "Static
property x and property x of C share a name". An interface's static
isn't inherited, so a class's instance member may share its name, as in
Java.

**Kotlin Temper:** didn't check; its Java output renamed the static.

### 10. Private constructors are enforced per class

`new C()` outside `C` (and classes nested in it), where `C`'s
constructor is private, is "C is not a concrete type with a public
constructor", through an alias or object literal too. Code that made
such values elsewhere in the module moves that into a static method of
the class. Core follows the same rule: `doneResult()` and `empty()` make
their values inside the classes.

This matches private methods, which are per class, and makes
private-constructor types usable as guarantees within Temper, such as a
sanitizer's output type that only the sanitizer makes. Host code can
still call some backends' constructors (open issue).

**Kotlin Temper:** didn't enforce private constructors.

### 11. Sealed and private where core means it

- **`MapKey` is sealed.** Only `Int32` and `String` are map keys, as no
  backend supports users' keys. A `when` over a `MapKey` still can't
  list its cases (`is Int32` and `is String` are refused), so it's
  sealed but not exhaustive in practice.
- **`DoneResult`'s constructor is private,** as `Promise`'s and
  `Empty`'s are; `doneResult()` makes one. No backend connected the
  constructor, so `new DoneResult()` was untranslatable or wrong.

**Kotlin Temper:** `MapKey` was sealed only in a comment
(`/*sealed*/`, "expected to be user-implementable in the future");
`DoneResult` had a public constructor.

### 12. `Console` and `Equatable` are nameable; `Null` is gone

- Code may name `Console` (and implement it), `getConsole(name)`, and
  `Equatable<T>` as a type or bound (`T extends Equatable<T>`; it's
  sealed), as in Kotlin Temper.
- **Core has no `Null` type.** `null` takes the nullable type its place
  wants, `Int?` in `let n: Int? = null;` or the other side's type in
  `x == null`. A declaration given only `null` needs a type:

  ```temper
  let a: String? = null; // `let a = null;` is an error
  ```

  `Null` is an ordinary name, free for a user's own class. Inside the
  compiler a bare null is the nullable bottom type, so joins need no
  special case, and hover shows the type the null's place wants.
  Programs that otherwise type-check behave the same.
- **Null alone has no members and is no condition.** `null.isEmpty` is
  "No member isEmpty in null"; `if (null)`, `while (null)`, and
  `null && b` are "Expected value of type Boolean not null"; and
  `null + 1` matches no signature of `+`. A join with a value, as
  `if (c) { 1 } else { null }`, has that value's type, made nullable.

**Kotlin Temper:** core was the prelude, so all of these were nameable,
including `Null`, which typed `let a = null;`. It refused members and
conditions on null alone too, with messages naming no type ("No type
for subject of .isEmpty") or `Empty?`.

### 13. `Deque` and `DenseBitVector` move to std as `Queue` and `BitVector`

```temper
let { Queue, BitVector } = import("std/collections");
```

- One module, `std/collections`, where hosts keep such types
  (`java.util`, Python's `collections`, Rust's `std::collections`, and
  .NET's `System.Collections`).
- Renamed for what they are: the API is first-in, first-out (`add`,
  `isEmpty`, `removeFirst`), and "dense" says nothing a user needs.
- Both stay `@connected` to the same host types (`java.util.Deque` and
  `BitSet`, Python's `collections.deque`, and so on), so host APIs don't
  change; runtimes' own types are renamed to match. By the connected
  rule, `is` and `as` can't target them.
- Each has a pure Temper body, the interpreter's only implementation.
- Every backend now agrees at the edges, as the body says: `get` at a
  negative index is `false`, `set` at one panics (setting `false`
  too), `removeFirst` on an empty queue panics, and a negative capacity
  is none. Both panics are a list's out-of-bounds panic, with its
  message (item 19).
- A missing import is a clean error naming it: "Deque has not been
  declared; it's std's Queue now: add
  `let { Queue } = import("std/collections");`". It's keyed on the
  unresolved name, so nothing is reserved and a user's own `Deque` or
  `Queue` works.

**Kotlin Temper:** both were in core, without `@connected` on the
classes, and backends disagreed on the edge cases.

### 14. `core` and `std` are reserved

The compiler treats a library as core, with core's privileges (naming
compiler internals, making its own private-constructor values, its
fields exemption), only for the built-in core's text or the `lib/core`
of the checkout the compiler was built from, which editors open. The
same holds for `std`. Building any other library named `temper-core` or
`std` is an error, so no library can claim those powers by copying the
layout.

**Kotlin Temper:** built core from its own tree, with no such check.

### 15. Core holds no representation-only fields

The builtins' `content` fields, `Problem`'s, and `PromiseBuilder`'s
`_promise` are gone. Bodies read `this`, as `Int32.min`'s
`if (this <= other) { this } else { other }`. What's left is state
core's own Temper sets and reads, which a test checks, so the
fields-initialized exemption is gone.

**Kotlin Temper:** declared `private let content` on each builtin class
and exempted it.

### 16. The interpreter's natives are checked against core's bodies

**History first.** Kotlin Temper's interpreter ran core's own Temper
bodies for members that aren't `@connected`: core's text was the
single source of what those members do in the interpreter, the REPL,
and the playground. The new compiler didn't carry that over. Its
interpreter implements core's members as native Rust functions instead,
so until this branch nothing tied those natives to core's bodies, and
the two could drift apart.

**What this proposal does.** The interpreter keeps native
implementations for `@connected` and bodiless members, as backends use
host code. A test runs core's Temper bodies in place of the natives on
shared inputs, 135 cases both ways, and lists any body not run with the
reason. Core members that aren't `@connected` must be listed with a
recorded reason.

**Why not return to Kotlin's approach now.** Running the bodies for
real means settling core with every program: a small program's settle
goes from about 3 ms to 10 to 15 ms, and a mix of core calls runs
several times slower, which matters most for the REPL and the
playground. So this branch keeps the natives and checks them against
the bodies. Running core's bodies again, as Kotlin did, remains open
(see Open issues), for example once core loads from a cached, binary
form of its compiled intermediate representation instead of being
settled each run.

**Kotlin Temper:** ran core's bodies in the interpreter, so there were
no separate natives to check for those members.

### 17. Core members settled on every backend

These were declared in Kotlin Temper's core, but their bodies, natives,
and backends disagreed or lacked an implementation:

| Member | Semantics now |
| --- | --- |
| `Int32`, `Int64` `succ()`, `pred()` | `n + 1` and `n - 1`, wrapping as `+` and `-` do on each backend |
| `Int32.signum` | `-1`, `0`, or `1`, at the extremes too |
| `listed.reduceFromIndex(initial, index, f)` | past the end gives `initial`; a negative index panics as `listed[index]` does (item 19) |
| `Float64.near(other, relTol, absTol)` | as Python's `math.isclose`, except that it's true whenever `==` is, so NaN is near NaN; an infinity is near only itself; never within a NaN margin |

A shared test program checks each on the interpreter and all seven
backends.

### 18. Builders stay memory safe when callbacks change them

`addAll` and `splice` given the builder itself add its values as they
were before the call. Callbacks of `map`, `reduceFrom`, `filter`, and
the like that change the builder they walk can't deadlock or read freed
memory on any backend; Rust's and C++'s walk a snapshot, as the
interpreter does. A `sort` whose comparison adds or removes values
panics everywhere, and every backend sorts a copy. A shared program
checks this on every backend, C++ under AddressSanitizer.

**Kotlin Temper:** its runtimes deadlocked (Rust), read freed memory
(C++), froze the input (JavaScript `filter`), or lost or kept values
depending on the backend.

### 19. Out of bounds panics everywhere, with one message

Reading or setting a list out of bounds (`ls[i]`, `set`, and `add` or
`addAll` at an index), `removeLast` on an empty builder, `reduce` on an
empty list, and reading a string at or past its end panic on the
interpreter and every backend, as core's docs already said. So do std's
`Queue.removeFirst` when empty and `BitVector.set` at a negative index.
All give one message:

```
index 3 out of bounds for length 3
```

- A bit vector has no length, every index from 0 up being in bounds,
  so it reports length 0: "index -1 out of bounds for length 0". An
  empty queue's `removeFirst` is "index 0 out of bounds for length 0".
- A string's index and length are in the backend's own units: UTF-8
  bytes on Rust, C++, Lua, and the interpreter; UTF-16 code units on
  JavaScript, Java, and C#; and code points on Python. Only an ASCII
  string's message reads the same everywhere.
- A panic isn't a bubble, so `orelse` doesn't catch it, except on
  JavaScript and Lua for now (open issue). Code handling indices of
  uncertain origin checks first, or uses `getOr`, `hasIndex`, or
  `isEmpty`.
- Each runtime panics through one shared helper, and the checks stay
  cheap on hot paths: C# reads through an inlined helper with one
  unsigned comparison, and Python tries the subscript first, which costs
  nothing on success from Python 3.11. Python's `removeLast` is a
  runtime call rather than a bare `.pop()`, about 60 ns more, the price
  of a panic `orelse` can't catch.

Tests pin each backend's whole panic message.

**Kotlin Temper:** core's docs said these panic, but its runtimes raised
host exceptions or bubbled, which `orelse` could catch (Python's
`IndexError`, C++'s and Lua's bubbles), JavaScript and Lua let `set` at
a negative index pass silently, and `Queue`'s and `BitVector`'s edges
differed by backend.

## Rationale

**Core as an ordinary library.** If core follows the rules it sets,
users can read it as an example, editors need no special paths, and the
rules get tested on the hardest code there is. Literate Markdown makes
core the source for the language reference, rather than hand-kept
copies, and running its examples keeps them true.

**Declarations, not lists.** Before this, what a builtin type allowed
lived in compiler tables, implied defaults, and backend special cases.
Reading it from core's declarations means one place to change and one
place to read, and the tests fail when core and the compiler disagree:
a type added without a capability row, a host type left unmarked, a
body that drifts from its native.

**Kotlin's connected rule, as a rule.** The alternative was marking
each affected type `@mayDowncastTo(false)`. One general rule covers
users' connected types too, matches Kotlin Temper, and fixes generated
code that was wrong, not just unchecked. Marking a type `@connected`
then says exactly "the host supplies this", which the backend scan
verifies.

**Strict now, looser later.** Each tightening here (sealed `MapKey`,
private `DoneResult` constructor, refusing `Void` values, bounds in
annotations) refuses code that was already unportable or wrong on some
backend. Loosening later breaks nothing; tightening after 1.0 would.
That is why the defaults are strict where in doubt.

**Namespaces over a predefined `core`.** A predefined `core` or
`builtins` name would be reserved in every module and would conflict
with user modules on some backends. Namespaces are general (they help
with std's many exports as well), cost one line where needed, and leave
nothing reserved. Renamed destructuring imports alone would have
covered core, but read worse for modules with many exports.

**Private constructors per class, not per module.** Temper has only
per-class `private`, deliberately, so per class matches private methods
and needs no new visibility. The cost is moving a few constructions
into static methods.

**Removing `Null`.** A type with one value that no host has adds a case
to every typing rule and backend. Taking null's type from its place
gives the same results for every program that type-checks, and the one
new error (`let a = null;`) asks for what a reader needed anyway.

**Out of bounds is a panic, with one message.** An index out of bounds
is a programming error, not an expected failure, and core declares
`get` and its kin without `throws Bubble`, so a bubble there was an
undeclared failure that code could come to rely on, on some backends
only. A panic everywhere makes such bugs fail the same way on every
backend, and one message, in Java's wording, lets tests pin them and
users search for them. `getOr`, `hasIndex`, and `isEmpty` cover code
that expects a miss. The bit vector reports length 0 rather than a
second message shape, and string messages keep each backend's units
rather than paying to convert indices on a path that should stay fast.

**Moving the collections, with new names.** Core should hold what the
language needs; a queue and a bit set are library types. Renaming at
the move costs nothing extra, since every user changes the import
anyway.

**Natives with checks, not bodies.** Running core's bodies would make
core the single source of behavior, but it costs every REPL and
playground run a core settle. Tests that compare the two give the same
assurance where it matters.

### Alternatives considered

- **Keep `builtins.X`, or predefine `core`:** both reserve a name;
  `builtins` names a compiler concept users don't otherwise meet.
- **Keep deprecated `Deque` and `DenseBitVector` exports in core:**
  std depends on core, so this needs duplicate declarations or compiler
  aliasing. One clean break with a targeted error is simpler.
- **Add `std/collections` to Kotlin Temper** so one source builds on
  both: more work on a compiler being retired.
- **Leave `Pair` unconnected and allow `is Pair`:** Pair is a tuple in
  Rust and a struct in C#, and erased type arguments let a
  `Pair<Int, String>` pass `is Pair<String, Int>` on most backends.
- **Enforce private constructors per module:** needs a visibility level
  Temper deliberately lacks.

## Compatibility

Temper libraries are all beta, and the switch to the new compiler is
the planned point for breaking changes. Each break but one is a
compile-time error with a message that says what to do; the exception,
out-of-bounds panics, shows at run time, with a message naming the
index and length.

| Change | Code that breaks | Migration |
| --- | --- | --- |
| `Deque`, `DenseBitVector` moved and renamed | any use | `let { Queue, BitVector } = import("std/collections");` and the new names; the error names the import |
| `builtins.X` removed | `builtins.String` and the like | drop the prefix, or `let core = import("core");` and `core.String` where the module shadows the name |
| No `Null` type | naming `Null`; `let a = null;` | the nullable type meant, as `String?`; a declared type |
| Private constructors enforced | `new C()` outside `C` for a private constructor | a static method on `C` that makes the value |
| `DoneResult` constructor private | `new DoneResult()` | `doneResult()` |
| `MapKey` sealed | a user type extending `MapKey` | none needed in practice; no backend supported such keys |
| Connected `is`/`as` rule | `x is StringBuilder`, `x is Pair<K, V>`, and the like from `AnyValue` | check through a sealed supertype, or keep a typed value rather than downcasting |
| `Void` not a value | `x: Void`, `List<Void>`, `Void?`, storing a `Void` result | drop the value, or return a real type |
| Bounds in annotations | `Map<Boolean, Int>` and other out-of-bound arguments | a type within the bound |
| `new T()`, `extends T` | type parameters made or extended | a factory function parameter |
| Static and instance member share a name | such pairs | rename one |
| `core`, `std` reserved | a library named `temper-core` or `std` | rename the library |
| Builtin classes' implied constructors | `new Int32()`, `new Empty()`, and the like | literals or core's functions (`empty()`) |
| Callbacks that change a builder during `sort` | comparisons that add or remove values | don't; it panics now |
| Out of bounds panics (run time) | `ls[i] orelse fallback` and the like for lists and strings; `set` at a negative index on JavaScript or Lua; `removeFirst` on an empty `Queue`; host code catching an `IndexError` or the like | `ls.getOr(i, fallback)`, or check `length`, `hasIndex`, or `isEmpty` first |

**Library changes after merge.** Of the public libraries surveyed,
Hrefine and Kelpto need source changes, both for private constructors:
each makes some values of classes with private constructors from
top-level functions, which move into static methods of those classes
(where a top-level helper has no outside users, it can go). The other
breaks don't occur in the surveyed libraries' sources, and their
generated code is otherwise unchanged.

**Kotlin Temper.** One source file can't always build under both
compilers: `std/collections` and namespaces don't exist in Kotlin
Temper, and its `Null` and `builtins.X` don't exist here. Since Kotlin
Temper is being replaced, libraries change once, at the switch.

**Host code.** Generated host APIs don't change, with one exception
noted in item 2: Java and C# callers that reached the generic list and
map helpers see free functions, as they already were in the runtimes.
The moved collections keep their host types, and the runtimes' own
types for them are renamed (as Python's `temper_core.BitVector`). An
index out of bounds now reaches host callers as each backend's panic
(Python a `BaseException`, Java an `AssertionError`, C#
`Environment.FailFast`, C++ the runtime's `panic()`, and Rust
`panic!()`), where some could catch a host exception before.

## Implementation

All of it is implemented on the Temper compiler's
`core-extension-methods` branch, in this order:

1. Generic methods as extensions; `builtins.` prefixes dropped from core;
   Kotlin-era TODOs resolved.
2. Core's bodies tested against the interpreter's natives; builtins
   documented in core; capabilities read from core's declarations.
3. `succ`, `pred`, `signum`, `reduceFromIndex`, and `near` settled on
   every backend; builder and callback safety.
4. Core split into a file per topic (a move with no content changes),
   then made literate, with prose docs and tested examples.
5. Module namespaces, `builtins` removed; `Void`, bounds, and
   `new ns.C()`; type parameters, `std` reserved, fields trimmed.
6. Connected types and the connected rule, private constructors, sealed
   `MapKey`, member names; one type-resolution path.
7. `Queue` and `BitVector` in `std/collections`; `Null` removed.
8. Out-of-bounds panics with one message on every backend, std's
   collections included; null alone refused as a subject or condition;
   folded calls' type arguments bound. Python's output now types
   generic functions whose result alone names a type parameter for
   pyright strict and mypy, with annotations or `cast()` rather than
   subscripting a class at run time, which was about six times slower.

Steps were checked by comparing the surveyed libraries' generated code
before and after on all seven backends, so changes in output are only
the intended ones. The release notes and the
notes on Kotlin Temper differences record each change with its tests.

After merge: Hrefine's and Kelpto's private-constructor changes; and
the language reference pages generated from core's and std's literate
sources, replacing hand-kept copies.

## Open issues

- **Running core's bodies in the interpreter again.** Kotlin Temper's
  interpreter ran core's Temper bodies; the new compiler uses checked
  natives (item 16) for speed. Returning to the bodies would make core's
  text the single source in the interpreter again; it needs core's
  settle to be cheap first, for example by loading core from a cached,
  binary form of its compiled intermediate representation (tmpl) rather
  than settling it each run. The checked natives are fine for now, and
  may stay fine later.
- **Sealed but not exhaustive.** `MapKey` is sealed so users can't
  extend it, but a `when` over it can't name its cases. A general marker
  for sealed interfaces that aren't exhaustive (which would also let
  libraries add cases without breaking users' `when`s, and decide which
  backends get enums) is undecided.
- **Parsing core once.** The compiler and editor tools read core's
  shapes, members, extensions, and signatures through several text
  scanners. Parsing core once into an index they all query would be
  simpler and faster; it's left as a follow-up.
- **Users' connected classes and downcasting.** Users can mark classes
  `@connected`, and the connected rule covers them, but connecting an
  interface isn't reported yet (Kotlin Temper refused it), and how a
  library declares that a connected type is safe to downcast on every
  backend (`@mayDowncastTo(true)`) needs a policy.
- **Private constructors on the host side.** Temper enforces them, but
  some backends emit them public (C#) or package-private (Java), so host
  code can forge values a library guards with one. This belongs with
  enforcing sealedness and finality at the host boundary, in the
  host-facing code work
  ([#676](https://github.com/temperlang/temper/issues/676)).
- **`orelse` catches panics on JavaScript and Lua.** Their runtimes'
  panic is their bubble, so there `orelse` still catches an index out of
  bounds, and `panic()` itself, which it catches on no other backend.
  This waits for the error-handling work, which can give each a panic
  that `orelse` passes over (Lua rethrowing what isn't a bubble, and
  JavaScript throwing a `Panic` subclass that `orelse` rethrows).
- **Callbacks that change what they walk.** Beyond `sort`, which values
  a `map` or `forEach` callback sees when it changes its builder is
  open: the interpreter, Rust, and C++ walk a snapshot; Python and Java
  the live builder; C# and Java throw for some.
- **Core's bodies as the implementation.** Some runtimes restate a body
  core writes in Temper (`near`, `reduceFromIndex`, and `sorted`'s copy,
  in seven runtimes each). Once backends translate core's bodies, those
  without a host speed-up could drop `@connected` and translate from
  core.
- **Core's extensions by name.** A library's extension can be called as
  a function or given all its type arguments; core's can't yet
  (`listedMap(xs) { … }`, `xs.map<Int, String>`).
- **Not translated yet:** an `Equatable` bound; a user class extending
  `Console`, `Generator`, or another builtin interface; and a `Console`
  as a value on JavaScript, Lua, and Rust. Rust and C++ also can't yet
  hold some core values (`Pair`, `List`, `Map`) as `AnyValue`.
- **Erased type arguments in checks.** Where a check from a covariant
  supertype names explicit type arguments, erasure can let a wrong one
  pass; refuse such checks, warn, or document.
- **`Type` at run time.** `x is Type` is allowed, as in Kotlin Temper,
  but no backend's ability to tell a `Type` apart is tested.
- **How macros name core.** Generated code from future user-space macros
  needs a way to say "core's `List`" that user code can't shadow, likely
  a resolved symbol rather than a name in source.
- **`Queue`'s API.** It's a queue only; whether it grows double-ended
  operations, which would change C#'s host type, waits for a need.
- **Where moved runtime code lives** on C# and Rust (core or std
  runtime).
- **Operators and function types in core** wait for
  [RFC 670](../../670-type-associated-operators/README.md) and
  [RFC 667](../../667-fun-types/README.md).

## Evidence

In this folder, drafted by Claude for the team:

- [claude-core-cleanup.md](claude-core-cleanup.md): the cleanup items,
  and the discussion that led to namespaces and no `builtins`.
- [claude-deque-bitvector-to-std.md](claude-deque-bitvector-to-std.md):
  host types by backend, the connected rule, and the move to std.

In the Temper compiler's branch: the release notes
(`docs/release-notes/unreleased.md`), and the notes on core's
capabilities, core's bodies, typing, and differences from Kotlin Temper
(`notes/`).
