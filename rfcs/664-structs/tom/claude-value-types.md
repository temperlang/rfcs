# Value types: notes toward struct types

By Claude, 2026-11-18, as input for this RFC. Nothing here is decided;
all syntax is hypothetical.

Two related wishes may or may not share one solution:

- **Value types:** small immutable data that C++, Rust, C#, Swift, and
  Go can hold by value (no allocation, contiguous lists), without
  costing JavaScript, Python, Java, or Lua anything.
- **Layout structs** (this RFC's issue, #664): fixed-size types with a
  predictable byte layout, read from and written to blobs (#663) for
  binary formats and typed IPC.

## Related issues

| Issue | What it covers |
|---|---|
| [#664](https://github.com/temperlang/temper/issues/664) | predictable-layout struct types (this RFC) |
| [#663](https://github.com/temperlang/temper/issues/663) | blobs and byte content, a prerequisite for #664 |
| [#90](https://github.com/temperlang/temper/issues/90) | value stability: shallowly immutable classes without identity (`===`), so constructor calls can be inlined |
| [#36](https://github.com/temperlang/temper/issues/36) | default and custom equivalence for record classes |
| [#297](https://github.com/temperlang/temper/issues/297) | struct splatting, for making variations |
| [#666](https://github.com/temperlang/temper/issues/666) | top-level constraints, building on `@imu` |

Related RFC drafts: [665 actors](../../665-actors/README.md) (immutable
values as messages), [659 memory management](../../659-memory-management/README.md)
(values can't form cycles), and [666 top-level safety](../../666-top-level-safety/README.md)
(`@imu`).

## Value types

**The key idea:** if copying a value and sharing a reference to it
can't be told apart, each backend may choose either. That takes a few
restrictions:

- **Immutable:** no `var` fields and no mutation after construction
  (`@imu`, deep enough that the value's own fields can't change).
- **No identity:** no `===`; equality and hashing are structural and
  generated (#36).
- **Final:** no subclasses. Implementing interfaces is allowed.
- **Not directly recursive:** a by-value struct can't contain itself.
- **Fields may hold references** to mutable objects; copying copies
  the reference, and every backend behaves the same.

```temper
// Hypothetical.
@value class Point(public x: Float64, public y: Float64) {}
let moved = { ...p, x: 3.0 };   // a variation, as #297 asks
```

**Per backend:**

| Backend | A value type as | Gain |
|---|---|---|
| C++ | a `struct` held by value, not `shared_ptr` | no allocation or reference counting; `std::vector<Point>` is contiguous |
| Rust | a `struct` deriving `Clone`, `PartialEq`, `Hash` (and `Copy` when fields allow), not `Arc` | the same |
| C# | `readonly record struct` | no GC allocation; contiguous lists |
| Swift, Go | `struct` | the same |
| Java | `record` today; a Valhalla value class later | modest now, large later |
| Kotlin | `data class`, or `value class` for one field | modest |
| JavaScript | a class (perhaps frozen) with generated equality | none needed; as today |
| Python | frozen `dataclass` with `slots` | slightly smaller objects |
| Lua | a table | as today |

**Caveats:**

- Big structs copy expensively; since copying is unobservable, a
  backend may still use a reference above some size (C#'s guidance is
  about 16 bytes). A performance choice, never a semantic one.
- C# structs always have a zero default value; Temper must never expose
  one (lists always hold real elements, but arrays and fields need
  care).
- A value used through an interface boxes in C# and needs `dyn` or
  generics in Rust: a cost, not a difference in behavior.
- `Point?` maps naturally: `Option<Point>`, `Nullable<Point>`,
  `std::optional<Point>`.

**Where it pays off:** color and matrix code (Chromarite's colors are
textbook value types; its matrices are flat partly for want of value
types), small records in parsers, and any `List` of small data.

## Layout structs as a subset?

One possible shape: a layout struct is a value type whose fields are
fixed-size scalars (`Int32`, `Float64`, fixed-width integers if Temper
gains them), other layout structs, or fixed-length arrays, with a
declared byte order and packing. Then:

- C, C++, Rust, C#, Go, and Swift get real `struct`s with matching
  layout (`#[repr(C)]`, `[StructLayout]`), readable straight from a
  blob where alignment allows.
- JavaScript, Java, Python, and Lua get ordinary objects plus generated
  read and write methods over `DataView`, `ByteBuffer`,
  `struct`/`memoryview`, and `string.pack`.

**Why they might not share a solution:**

- Layout cares about bytes (order, padding, alignment, fixed widths);
  value types care about semantics (immutability, identity). A
  general value type may hold strings and lists, which have no fixed
  layout.
- Binary formats often need variable-length parts, versioning, and
  validation that a struct type alone doesn't express; a schema or
  codec library (in Temper) might serve them better than a language
  feature.
- Mutation in place in a buffer (a view over bytes) is useful for
  binary work but contradicts value semantics.

So value types could come first as the semantic base, with layout
either built on them or kept separate as views or codecs over blobs.

## Open questions

- Marking: an annotation (`@value`), a keyword, or inferred from
  `@imu` plus no identity use?
- Whether `==` on value types is always structural, and how custom
  equivalence (#36) interacts.
- Size limits or hints for by-value representation.
- Fixed-width integer types for layout (`UInt8`, `Int16`, …) and how
  they map where hosts lack them (JavaScript, Lua).
- Endianness and alignment defaults for layout structs.
