# Enum types: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-26, for
[#50](https://github.com/temperlang/temper/issues/50). Suggestions only;
nothing here is decided. The issue's discussion (2025) agreed enums
needn't block 1.0, and that reserving syntax space is enough for now.

## Where things are

Since #50 was opened, Temper has gained most of what enums are made of:

- **Sealed interfaces** with exhaustive `when` (#6).
- **`@data` classes** (#694): plain data, checked, spreadable.
- **Value equality** through `@auto("==")`.
- **Singletons** today are written as a class with a private constructor
  and a static instance, or as module-level values.

So an enum can be mostly sugar over these, and the question is which
shape is worth a name of its own.

## Two kinds of enum

1. **Plain enumerations:** a closed set of named constants, like
   `enum Suit { Clubs, Diamonds, Hearts, Spades }`. Needs: identity or
   value equality, exhaustive `when`, iteration over all values, a name
   per value (for printing and parsing), maybe an ordinal.
2. **Variants with data** (algebraic data types, like Rust's enums or
   Kotlin's sealed classes): `Shape = Circle(r) | Rect(w, h)`. Temper
   already expresses these as a sealed interface plus `@data` classes;
   an enum syntax would only shorten them.

Plain enumerations are where Temper lacks something today: there's no
concise way to declare them, list their values, or map them to each
host's native enum.

## Host translation

| Backend | Plain enumeration | Variants with data |
|---|---|---|
| Java | `enum` | sealed interface + records (Java 17) or classes |
| C# | `enum` (integers) or a class of static instances | abstract record hierarchy |
| Rust | `enum` with unit variants | `enum` with data |
| C++ | `enum class` | `std::variant` or a class hierarchy |
| Python | `enum.Enum` | classes, or dataclasses |
| JS | frozen object of symbols or strings, or a class of instances | classes |
| Lua | table of unique values | tables with tags |

Native enums are what host users expect (`switch` over them, IDE help,
`EnumSet` in Java, `match` in Rust). C#'s and C++'s are integers,
though, so values carrying methods or data need classes there.

## Questions

- **Syntax space to reserve now:** an `enum` keyword (or `@enum`
  decorator on a sealed interface?), so code can't start using the name
  in ways that block it later.
- **Methods on enums:** allowed (Java style) or not (C# style)? Methods
  rule out C#'s and C++'s integer enums as the host form.
- **Ordinals and conversion to/from integers and strings:** generated
  `values()`, `name`, `valueOf(name)`; integers only if asked for, since
  they invite fragile persistence.
- **Exhaustiveness and evolution:** adding a value breaks exhaustive
  `when`s in other libraries; the same trade-off as sealed interfaces
  (closed per library), which fits.
- **Variants with data:** separate sugar, or one `enum` form that allows
  both (Rust/Swift style)? Keeping data variants as sealed interfaces
  plus `@data` classes keeps the language light.
- **Interaction with RFC 676:** host shapes for plain enums are
  host-facing API, so the native mapping above needs the same
  compatibility care as other public types.

## Suggestion

Reserve the syntax now (cheap). Later, add plain enumerations only, as
sugar for a sealed set of singletons with generated `values()` and
names, mapped to native enums where a backend's enums can carry what
Temper allows. Leave data variants to sealed interfaces and `@data`.
