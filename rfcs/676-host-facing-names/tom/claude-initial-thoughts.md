# Host-facing names: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The goal

Someone using a Temper library from Java, C#, Python, Rust, or any other
backend shouldn't need to know or name Temper. What they import, call,
catch, and read in docs should look like a library written in their
language, with names that belong to the library.

## Leaks today

- **Module classes:** Java and C# put a module's top-level functions and
  values in a class named `…Global` (`wherewith.WherewithGlobal`).
- **Failure types:** C++ `TemperBubble`, Rust `temper_core::Error`, and
  the most general exception type elsewhere (library-named failure types
  are part of [#164](../../164-exceptions/README.md)).
- **Runtime types in signatures:** C++ `temper::core::Str` and
  `NullableParam<T>`, Rust `ToArcString`, C# Temper's `Optional<T>`, Lua
  `temper.null`.
- **Clashes between generated names:** a C# library named like a std
  module (`json`) makes `JsonGlobal` ambiguous; two modules whose paths
  end alike (`state` and `parts/state`) share a C# class name and a C++
  init function name.
- **Escape suffixes** for names that collide with host keywords or
  members.

## Principles

1. **Names belong to the library:** classes, modules, failure types, and
   generated helpers carry the library's names, never Temper's.
2. **Host-native types in signatures** wherever a natural one exists;
   runtime helper types stay internal.
3. **The runtime is an implementation detail:** a dependency users install
   but never import or name.
4. **Stable once released:** host-facing names are API, so they'd be
   recorded and checked for compatibility (the temper.keep idea).

## Module classes in Java: `blah.Blah`

Java packages are lowercase by convention, so `package wherewith;` with
`class Wherewith` is natural and never ambiguous. Today's
`WherewithGlobal` would become `Wherewith`.

The catch is a module that already declares a type named like itself.
None of the six showcase libraries does, but std does: `std/regex`
exports `class Regex`, so Java today has both `temper.std.regex.Regex` and
`RegexGlobal`. Two options:

1. **Make it illegal** for a module to declare a type named like its
   module (compared after each backend's casing, so `json` and `Json`
   clash), and rename one side in std. Simple: one rule, no special
   output shape, and it fixes C#'s `TemperLang.Std.Regex.Regex` too.
2. **Merge instead:** when a module declares a type named like itself,
   the module's top-level functions and values become that type's static
   members (`Regex.compile(…)`). Idiomatic in Java and C#, but a second
   output shape to build, test, and explain, and C#'s namespace clash
   remains.

Tom prefers option 1, given good names. Precedent favors renaming the
type: Java's `java.util.regex` holds `Pattern` and `Matcher`, and
Python's `re` holds `Pattern` and `Match`. So `std/regex` could export
`Pattern` (or `Regex` stays and the module becomes `std/regexes` or
`std/patterns`, which reads worse). Renaming is breaking for std's
users, which is acceptable before 1.0. Kotlin's `Regex` in `kotlin.text`
and Go's `regexp.Regexp` show the other choices languages make.

## Module classes in C#

.NET discourages a type named like its namespace (`Wherewith.Wherewith`):
the Framework Design Guidelines say so, analyzer CA1724 flags it, and it
causes real lookup ambiguities. So C# needs a different answer from Java:

- **A library-chosen name** through whatever naming mechanism this RFC
  settles on (a decorator or a naming file). The best .NET facades are
  nouns that say what they do (`JsonSerializer`, `File`, `Math`), which
  no default can derive; Wherewith might pick `Sql`.
- **A better default than `Global`:** `WherewithFunctions`, or
  `WherewithModule` (F#'s word for exactly this).
- **`using static`:** docs can show
  `using static Wherewith.WherewithFunctions;`, after which C# code calls
  the functions unqualified and the class name rarely appears.
- **The ban doesn't settle C#'s module class:** with option 1, Java's
  module class becomes `regex.Regex`, but C# can't name it `Regex` in
  namespace `TemperLang.Std.Regex` for the same guideline reason, so C#
  keeps a suffixed default (or a chosen name).

std already breaks the guideline: C# gets class `Regex` in namespace
`TemperLang.Std.Regex`. Inside any namespace under `TemperLang.Std`, a bare
`Regex` means the namespace, not the class; and code that also imports
`System.Text.RegularExpressions` sees two `Regex` classes. Option 1 with
std's type renamed (`Pattern`) fixes this without any per-backend naming.

## Naming mechanism

Defaults should be good enough that most libraries never override them,
but a library needs a way to choose a host-facing name per backend where
the default is poor (the C# facade, a Python module name, a Rust crate
name). Candidates: decorators on declarations, a per-library naming file,
or an interactive pass that records choices. Whatever is chosen, the
names chosen are API and should be recorded with the library, in
temper.keep ([#677](../../677-temper-keep/tom/claude-initial-thoughts.md)).

## Sealed interfaces and final classes

Added 2026-11-21. Inside Temper, a sealed interface's implementations are
known, so `when` can be exhaustive, and classes can't be subclassed. No
backend carries either guarantee to host code today, so a host can add an
implementation that Temper's exhaustive code never expected, or subclass a
class Temper treats as final:

| Backend | Sealed interface today | Classes today | Could enforce |
|---|---|---|---|
| C++ | `struct` with pure virtuals | open | little, for an interface |
| C# | `public interface` | `public class` (open) | an `internal` member on the interface (C# 8+); `sealed class` |
| Java | plain `interface` | `final class` | `sealed … permits` on Java 17+ |
| JS | open class | open | a runtime check of `new.target` |
| Lua | open type | open | a runtime check |
| Python | open ABC | open | `__init_subclass__` rejecting unknown subclasses (runtime) |
| Rust | `pub trait` with public supertraits | structs (final) | the sealed-trait pattern: a private supertrait |

Suggestions:

- Enforce at compile time where the host language can (Rust, C#, Java
  17+); add cheap runtime checks or document the gap elsewhere.
- **Rust enums:** Kotlin Temper's Rust backend generated an `enum` for a
  sealed interface, giving Rust users exhaustive `match`; the new
  compiler doesn't yet. Restore it, but only for sealed interfaces that
  are exhaustive. A sealed interface marked non-exhaustive (sealed for
  extension, but `when` keeps a default; a possible decorator) must keep
  a trait or `#[non_exhaustive]`, and likewise avoid exhaustive switch
  shapes in other languages.

## Related

- [#677](../../677-temper-keep/tom/claude-initial-thoughts.md): temper.keep,
  where chosen names would be recorded.

- [#164](../../164-exceptions/README.md): library-named failure types.
- [#667](../../667-fun-types/README.md): host names for fun interfaces.
- [#671](https://github.com/temperlang/temper/issues/671): core names, which also reach
  host code through the runtime.

## From earlier design notes

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **A periphery.** Host code enters Temper code only through exported
  functions, members of exported types, and exported top-level values.
  The notes proposed pairs of members: a host-facing one that converts
  host values (and has an idiomatic name), and an internal one that
  generated code calls, whose name can be mangled or hidden (`private`,
  `friend`, or a parameter of a type only Temper can make). Conversion
  then happens once at the boundary, not inside loops. A Temper type
  passed in should come back out as the same host type.
- **APIs as feature sets.** Rather than one exported API, a library
  exports features, and each backend exports at least one form of each
  (a namespaced function, a static method, …). Names are split into
  words and rejoined per host style and reserved words; an experiment
  generated names from a grammar with style and part of speech.
- **Stable names.** Generated names must depend only on what the author
  puts in the API, and stay stable across declaration order and
  additive changes.
- **Declaring the API apart from `export`.** An `API.declare` /
  `expose` idea separated what a library publishes from how its
  modules import each other.
