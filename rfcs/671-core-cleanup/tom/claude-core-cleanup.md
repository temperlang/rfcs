# Core cleanup: notes toward the RFC

By Claude Code (Claude Opus 5.5), 2026-11-18, for
[#671](https://github.com/temperlang/temper/issues/671), gathering Tom's
direction and what's known so far. Nothing here is decided; syntax is
hypothetical. `tN` numbers are entries in Tom's to-do list.

## Goals

- Core reads like any other Temper library: declared in Temper, split
  into topic files, literate, with docs for everything.
- Editors and docs work on core as on user code: hover and go to
  definition everywhere, including within core.
- Kotlin-era bootstrapping workarounds go away.

## Cleanup items

| Item | To-do | Notes |
|---|---|---|
| Core's generic interface methods (`Listed.map<O>`, `reduceFrom<O>`, `reduceFromIndex<O>`, `Mapped.toListWith<T>`, `toListBuilderWith<T>`) become `@extension` functions | t699 (in progress) | user code can't declare generic methods on interfaces (overrides can't be generic); core was exempt only because it's read for signatures. Also fixes explicit type arguments on extension calls (t499) and C++'s "not yet" for generic interface methods (t79) |
| Drop `builtins.` prefixes in core (71 uses, 1 in std) | t700 | a Kotlin bootstrapping workaround (core declares classes named like the builtins); tempest reads `String` and `builtins.String` alike |
| Kotlin-era TODOs and markers | t704 | `export /*sealed*/ interface MapKey`, workarounds for old typing bugs ("overrides don't seem to work here", "Expected subtype of AnyValue"), generator bubbling TODOs |
| Declare more of core in core | t702 | macros (`if`, `while`, `orelse`, `await`), `panic`, operators, list literals, and the console have no declarations, so no hover docs or definition target |
| Every builtin whose hover shows `?` gets a declaration with docs | t706 | enumerate by script over the builtins and the language server's hover; `@connected` declarations where possible, documentation-only declarations for macros |
| Split core into a directory of `.temper.md` files by topic | t703 | core is one 1,752-line file; the build already lists core's files, so the split is mechanical. Restructuring in its own change, with no content changes |
| Language-server navigation within core | t701 | going into core works; jumping around inside core doesn't, notably on `builtins.Int`-style names |
| Audit all core-related code (core, the frontend's special cases, tmpl's builtin keys, each backend's core connections and runtime, editor and playground handling) | t705 | read-only, feeding the items above |
| Related fixes | t690, t691, t698 | `Listed.get`'s doc contradicts its behavior; `DenseBitVector.set` with a negative index differs by backend; generic `@fun interface`s don't translate yet (needed by [RFC 667](../../667-fun-types/README.md)'s core role names) |

Suggested order: t699, t700, t704, t702 and t706, t703 alone, then
t701 (easiest to test after the split).

## Naming core: `core.Whatever`

Tom's direction (t707): the qualified name says where a declaration
lives.

- **`core.Int`, not `builtins.Int`.** `core` matches the library's name,
  std's style (`import("std/regex")`), and the `-core-/` path editors
  show. `builtins` names a compiler concept users don't otherwise meet.
- **No hidden `builtins.` fallback.** `core` is an ordinary name; code
  that wants another name for it says so with an alias (below).
- **Rarely needed:** once core itself drops the prefixes, a qualifier
  matters only where user code shadows a core name, as with its own
  `class String`.
- **A user's own `core`:** an ordinary, shadowable name means a user's
  `let core = …` simply works in its scope. A top-level
  `let whatever = core;` would not help where a module declares its own
  `core`, since it would read the user's; an import alias names the
  module by path, so it can't be shadowed.
- **Backends:** a user module named `core` already breaks a zero check
  on Lua (a separate to-do), so if `core` becomes a public name, test a
  user module and variable named `core` on every backend.

**A further option (Tom):** define neither `core` nor `builtins` as a
name by default. Core's declarations stay in scope unqualified, as
today, and code that wants to qualify one imports a namespace
explicitly, under any name it likes:

```temper
// Hypothetical.
let core = import("core");
class String { … }               // the module's own String
let s: core.String = "text";     // core's
```

- Nothing is reserved: a user's `core` or `builtins` never conflicts,
  because neither exists until a module asks for it.
- `builtins.X` syntax goes away once core itself drops it (t700); std
  has one use, and the six libraries surveyed have none.
- Qualification is rare (only where a module shadows a core name), so
  one import line where it's needed costs little.

## Module aliases: `let whatever = import("core");`

Today Temper has destructuring imports only (`let { a, b as c } =
import("./dir")`, and `...` for every export). A module alias would bind
one name to a whole module:

```temper
// Hypothetical.
let k = import("core");
let rx = import("std/regex");
let n: k.Int = 1;
let match: rx.Match? = …;
```

- **A namespace, not an object.** The alias exists only at compile time:
  `k.Int` resolves to core's `Int` as `core.Int` would. It never reaches
  tmpl, so backends generate nothing for it.
- **Errors up front.** Using an alias as anything but a namespace (as a
  value, an argument, `k == k`, a field) is a type error in the frontend,
  so nothing downstream ever sees it.
- **General, not core-specific:** it works for std and a library's own
  modules too, and gives code a way to keep long import lists short.
- Open: whether `export let k = import(…)` re-exports a namespace (likely
  not at first); how the language server shows aliases (hover as the
  module, go to definition opens it).

## Counterarguments

The largest concerns first; none argues against the goals.

1. **Renamed imports may already cover aliasing.** Temper has
   destructuring imports with renames, so a module defining its own
   `String` could write `let { String as CoreString } = import("core");`
   once `import("core")` works, with no new kind of name. Module aliases
   add a namespace that isn't a value, with its own typing rules,
   language-server support, and errors, for a case that's rare by
   design. "When in doubt, leave it out" suggests starting with renamed
   destructuring imports from `"core"` and adding namespace aliases only
   if real code wants them, though aliases read better for std modules
   with many exports, so it's a real tradeoff.
2. **Code generators and future macros need a name for core that user
   code can't shadow.** The compiler refers to core through resolved
   symbols, so dropping `builtins.` doesn't affect it. But user-written
   macros or decorators that generate source (the direction of
   [RFC 662](../../662-clear-call-inlining/README.md) toward user-space
   macros) need a hygienic way to say "core's `List`" whatever the
   user's scope defines. With no default `core` or `builtins` name, a
   macro must inject an import or rely on hygiene machinery Temper
   doesn't have yet. This argues for some unshadowable path, perhaps
   compiler-internal and producible only by macro expansion, even if
   it's never user-facing. Decide early how macro hygiene names core. One option (Tom): macro hygiene could refer to core directly in a non-syntactic way, such as a resolved symbol a macro attaches to the code it generates, so no name in source is ever needed.
3. **Declaring macros in core can mislead.** Documentation-only
   declarations for `if`, `while`, `orelse`, or `await` give hover docs
   and a definition target, but look like functions users might pass or
   call. They need a clear marker and docs, and a check (for example, a
   test that every builtin has exactly one declaration) so they don't
   drift from the compiler's built-in list.
4. **Splitting core and converting it to `.temper.md`** makes `git
   blame` and history harder to follow, causes merge conflicts for open
   work touching core, and risks prose duplicating doc comments. These
   are one-time or manageable; doing the split alone keeps it reviewable.
5. **Requiring an explicit import to qualify** is less discoverable than
   a predefined `core`. A good error message answers it: "`String` here
   is your class; to use core's, `let { String as CoreString } =
   import("core")`."
6. **The extension methods change a few host-visible shapes** (static
   functions where host code might have seen methods); small, since
   `List` and `Map` mostly map to host collections.

**Suggested adjustments:** start with renamed destructuring imports
from `"core"` rather than namespace aliases, and settle how macro
hygiene names core before removing `builtins.` syntax entirely.

## Related issues

- [#30](https://github.com/temperlang/temper/issues/30): move `Deque` and
  `DenseBitVector` out of builtins and implicits (what belongs in core at
  all).
- [#250](https://github.com/temperlang/temper/issues/250): a class named
  `Type` causes issues in be-py and be-java (user names colliding with
  builtins; the same class of problem as qualification and backend
  naming).
- [RFC 670](../../670-type-associated-operators/README.md),
  type-associated operators, and
  [RFC 667](../../667-fun-types/tom/claude-fun-types-study.md), fun
  types (core's role-named fun interfaces): new core members they
  define wait for those RFCs, not this one. This cleanup declares what
  core already has (t702, t706) and doesn't add their members; where
  an item here touches the same declarations (operators, function
  types in signatures), it leaves their final shape to those RFCs.

No issue yet covers module aliases or a `core` qualifier.
