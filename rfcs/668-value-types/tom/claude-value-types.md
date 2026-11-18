# Value types

By Claude, 2026-11-18, as input for this RFC
([#668](https://github.com/temperlang/temper/issues/668)). Nothing here
is decided; all syntax is hypothetical. A survey of how 50 languages
could host them is in [claude-language-survey.md](claude-language-survey.md).

**Goal:** small immutable data that C++, Rust, C#, Swift, and Go can
hold by value (no allocation, contiguous lists), without costing
JavaScript, Python, Java, or Lua anything.

## Related issues

| Issue | What it covers |
|---|---|
| [#664](https://github.com/temperlang/temper/issues/664) | predictable-layout struct types, which may build on value types |
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

## Dense storage

Value types alone make `List<Point>` contiguous only where structs are
native (C, C++, Rust, C#, Swift, Go); elsewhere it's still a list of
references. Layering helps:

1. **Value types** are the semantic base (above).
2. **Plain-data value types**, whose fields are all fixed-size scalars
   or other plain-data value types, can be recognized by the compiler
   with no annotation. A std container (hypothetically `DenseList<P>`)
   can then be dense on every backend: a vector of structs where hosts
   have them, typed arrays underneath elsewhere (fields interleaved, or
   one array per field, which is often faster in JavaScript). Since
   elements are immutable and reads give copies, the backend chooses.
3. **Explicit byte layout** (byte order, packing, alignment) is needed
   only for binary interchange, in [RFC 664](../../664-structs/README.md).
   Dense in-memory storage needs none of it.

Dense containers can be a separate, opt-in step, so they don't hold up
value types themselves.

## Open questions

- Marking: an annotation (`@value`), a keyword, or inferred from
  `@imu` plus no identity use?
- Whether `==` on value types is always structural, how custom
  equivalence (#36) interacts, and one rule for float fields (NaN, -0.0).
- Size limits or hints for by-value representation.
- Whether value types may be map keys (Temper's `MapKey` is closed
  today); if so, runtimes without host hashing (Lua, PHP) must supply it.
